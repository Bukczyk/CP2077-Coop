-- Local, game-thread presentation fixture. This is NOT network admission,
-- authority validation, a reliable-event ledger, or an exactly-once guarantee.
-- The caller must validate the source before calling stage(). Serial numbers
-- below are bounded local fixture counters, never protocol EventIds.
--
-- IDs are nonempty opaque strings. Derive localKey directly from the returned
-- projection EntityID.hash, without converting a Uint64 through a Lua number.
-- resolve(sessionKey) must return the current exact localKey or nil. Neither
-- proximity nor an entity name is a mapping. apply(frame) runs on the caller's
-- game thread and returns true only when the engine accepted the desired pose.
-- Queue acceptance does not establish that an animation was visually observed.
-- apply() can retry the same desired pose after failure; it must not trigger
-- gameplay effects. Clip durations must come from the actual clip metadata.
--
-- API: new(config); reset(scope, now); bind(scope, sessionKey, localKey, now);
-- unbind(scope, sessionKey, localKey, now); stage(scope, sessionKey, localKey,
-- serial, "reaction"|"death", now); apply(scope, sessionKey, localKey, now).
-- inspect(scope, sessionKey) returns a copy; size() includes retained entries.
-- Unbound entries are retained until a NEW caller-owned scope token is set.
-- This bounds memory without evicting death state or allowing resurrection.

local M = {}
local MAX_SAFE_INTEGER = 9007199254740991

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function integer(value, maximum)
    return finite(value) and value >= 1 and value <= maximum
        and value == math.floor(value)
end

local function key(value)
    return type(value) == "string" and value ~= "" and #value <= 256
end

local function scopeToken(value)
    local kind = type(value)
    return (kind == "string" and value ~= "" and #value <= 256)
        or kind == "table" or kind == "userdata" or kind == "cdata"
end

local function duration(value)
    return finite(value) and value > 0 and value <= 600
end

function M.new(config)
    if type(config) ~= "table" then return nil, "invalid_config" end
    local capacity = config.capacity == nil and 64 or config.capacity
    local maxSerial = config.maxSerial == nil and 2147483647 or config.maxSerial
    if not integer(capacity, 4096) or not integer(maxSerial, MAX_SAFE_INTEGER)
        or not duration(config.reactionDuration) or not duration(config.deathDuration)
        or type(config.resolve) ~= "function" or type(config.apply) ~= "function" then
        return nil, "invalid_config"
    end

    -- Copy configuration values so later caller edits cannot alter the bounds.
    local reactionDuration, deathDuration = config.reactionDuration, config.deathDuration
    local resolve, applyFrame = config.resolve, config.apply
    local scope, clock, count, busy = nil, 0, 0, false
    local entries, localOwners = {}, {}
    local controller = {}

    local function context(givenScope, now)
        if busy then return false, "callback_busy" end
        if scope == nil or givenScope ~= scope then return false, "wrong_scope" end
        if not finite(now) or now < 0 then return false, "invalid_time" end
        if now < clock then return false, "stale_time" end
        return true
    end

    local function invoke(callback, ...)
        busy = true
        local ok, result = pcall(callback, ...)
        busy = false
        return ok, result
    end

    local function mapping(sessionKey, localKey)
        local ok, actual = invoke(resolve, sessionKey)
        if not ok then return false, "mapping_unavailable" end
        if actual == nil then return false, "mapping_missing" end
        if actual ~= localKey then return false, "wrong_mapping" end
        return true
    end

    local function bound(givenScope, sessionKey, localKey, now)
        local ok, reason = context(givenScope, now)
        if not ok then return nil, reason end
        if not key(sessionKey) or not key(localKey) then return nil, "invalid_key" end
        local entry = entries[sessionKey]
        if not entry then return nil, "unknown_entity" end
        if entry.localKey == nil then return nil, "unbound" end
        if entry.localKey ~= localKey then return nil, "wrong_projection" end
        ok, reason = mapping(sessionKey, localKey)
        if not ok then return nil, reason end
        return entry
    end

    function controller:reset(nextScope, now)
        if busy then return false, "callback_busy" end
        if not scopeToken(nextScope) then return false, "invalid_scope" end
        if nextScope == scope then return false, "same_scope" end
        if not finite(now) or now < 0 then return false, "invalid_time" end
        scope, clock, count = nextScope, now, 0
        entries, localOwners = {}, {}
        return true, "reset"
    end

    function controller:bind(givenScope, sessionKey, localKey, now)
        local ok, reason = context(givenScope, now)
        if not ok then return false, reason end
        if not key(sessionKey) or not key(localKey) then return false, "invalid_key" end
        local entry = entries[sessionKey]
        if entry and entry.localKey and entry.localKey ~= localKey then
            return false, "already_bound"
        end
        if localOwners[localKey] and localOwners[localKey] ~= sessionKey then
            return false, "projection_in_use"
        end
        if not entry and count >= capacity then return false, "full" end
        ok, reason = mapping(sessionKey, localKey)
        if not ok then return false, reason end
        clock = now
        if entry and entry.localKey == localKey then return true, "already_bound" end
        if not entry then
            entry = {serial = 0, kind = "idle", startedAt = now, dead = false}
            entries[sessionKey], count = entry, count + 1
        end
        entry.localKey, entry.appliedPhase = localKey, nil
        -- Recreating a known dead entity must immediately restore its final
        -- pose, even if the old projection disappeared halfway through death.
        if entry.dead then entry.kind, entry.startedAt = "dead", now end
        localOwners[localKey] = sessionKey
        return true, "bound"
    end

    function controller:unbind(givenScope, sessionKey, localKey, now)
        local ok, reason = context(givenScope, now)
        if not ok then return false, reason end
        if not key(sessionKey) or not key(localKey) then return false, "invalid_key" end
        local entry = entries[sessionKey]
        if not entry then return false, "unknown_entity" end
        if entry.localKey == nil then return false, "unbound" end
        if entry.localKey ~= localKey then return false, "wrong_projection" end
        -- Do not resolve here: the engine may already have removed the binding.
        -- Require the exact formerly owned pair before retiring local ownership.
        clock, localOwners[localKey] = now, nil
        entry.localKey, entry.appliedPhase = nil, nil
        return true, "unbound"
    end

    function controller:stage(givenScope, sessionKey, localKey, serial, kind, now)
        local entry, reason = bound(givenScope, sessionKey, localKey, now)
        if not entry then return false, reason end
        if not integer(serial, maxSerial) then return false, "invalid_serial" end
        if kind ~= "reaction" and kind ~= "death" then return false, "invalid_kind" end
        if serial == entry.serial then return false, "duplicate" end
        if serial < entry.serial then return false, "stale_serial" end
        if entry.dead then return false, "terminal_death" end
        clock = now
        entry.serial, entry.kind, entry.startedAt = serial, kind, now
        entry.dead, entry.appliedPhase = kind == "death", nil
        return true, "staged"
    end

    function controller:apply(givenScope, sessionKey, localKey, now)
        local entry, reason = bound(givenScope, sessionKey, localKey, now)
        if not entry then return false, reason end
        clock = now
        local phase, progress = entry.kind, 0
        if phase == "reaction" then
            progress = math.min(1, (now - entry.startedAt) / reactionDuration)
            if progress >= 1 then phase, progress = "idle", 0 end
        elseif phase == "death" then
            progress = math.min(1, (now - entry.startedAt) / deathDuration)
            if progress >= 1 then phase, progress = "dead", 1 end
        elseif phase == "dead" then
            progress = 1
        end
        local frame = {scope = scope, sessionKey = sessionKey, localKey = localKey,
            serial = entry.serial, phase = phase, progress = progress, dead = entry.dead}
        -- Terminal poses are queued once per local binding. Active clips need
        -- repeated phase/progress updates, supplied by the caller's game clock.
        if (phase == "idle" or phase == "dead") and entry.appliedPhase == phase then
            return true, "unchanged", frame
        end
        local ok, accepted = invoke(applyFrame, frame)
        if not ok then return false, "engine_error" end
        if accepted ~= true then return false, "engine_rejected" end
        entry.appliedPhase = phase
        return true, "queued", frame
    end

    function controller:inspect(givenScope, sessionKey)
        if scope == nil or givenScope ~= scope then return nil, "wrong_scope" end
        local entry = entries[sessionKey]
        if not entry then return nil, "unknown_entity" end
        return {localKey = entry.localKey, serial = entry.serial, kind = entry.kind,
            startedAt = entry.startedAt, dead = entry.dead, appliedPhase = entry.appliedPhase}
    end

    function controller:size() return count, capacity end
    return controller
end

return M
