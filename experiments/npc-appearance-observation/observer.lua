-- Read-only, one-shot local evidence. Native reads occur only inside update().
local Observer = {}
Observer.__index = Observer
local MAX_TARGETS, MAX_LOGS = 8, 64
local MAX_COUNTER = 2147483647 -- Exact in both Lua runtimes; never wrap identities.
local U64_MAX = "18446744073709551615"

local function decimal(value, zeroAllowed)
    if type(value) ~= "string" or not value:match("^%d+$") then return false end
    if #value > 1 and value:sub(1, 1) == "0" then return false end
    if #value > 20 or (#value == 20 and value > U64_MAX) then return false end
    return zeroAllowed or value ~= "0"
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function reference(value)
    local kind = type(value)
    return kind == "table" or kind == "userdata" or kind == "cdata"
end

local function labelValid(label)
    return type(label) == "string" and #label > 0 and #label <= 48
        and label:match("^[%w_.-]+$") ~= nil
end

local function text(value, limit)
    return type(value) == "string" and #value <= limit
end

function Observer.new(options)
    return setmetatable({ getGame = options.getGame, log = options.log,
        entries = {}, order = {}, scope = 1, ticket = 0, frame = 0,
        logCount = 0, closed = false, resetPending = false }, Observer)
end

function Observer:_log(label, status)
    if self.logCount >= MAX_LOGS then return end
    self.logCount = self.logCount + 1
    if self.log then
        pcall(self.log, string.format("[npc-appearance-observation] scope=%d ticket=%d label=%s result=%s",
            status.scope, status.ticket or 0, label, status.reason))
    end
end

function Observer:request(label, actor)
    if self.closed then return false, "closed" end
    if self.resetPending then return false, "reset_pending" end
    if self.ticket >= MAX_COUNTER then return false, "counter_exhausted" end
    if not labelValid(label) then return false, "invalid_label" end
    if not reference(actor) then return false, "invalid_target_reference" end
    local previous = self.entries[label]
    if not previous and #self.order >= MAX_TARGETS then return false, "capacity" end
    if not previous then self.order[#self.order + 1] = label end
    self.ticket = self.ticket + 1
    self.entries[label] = { actor = actor, pending = true,
        status = { valid = false, reason = "queued", scope = self.scope,
            ticket = self.ticket, queuedFrame = self.frame, visualQualified = false } }
    return true, previous and previous.pending and "coalesced" or "queued", self.ticket
end

function Observer:status(label)
    if label ~= nil then
        local entry = self.entries[label]
        return entry and copy(entry.status) or { valid = false, reason = "not_requested", visualQualified = false }
    end
    local result = { scope = self.scope, frame = self.frame, resetPending = self.resetPending,
        closed = self.closed, closedReason = self.closedReason, logCount = self.logCount, targets = {} }
    for key, entry in pairs(self.entries) do result.targets[key] = copy(entry.status) end
    return result
end

function Observer:reset()
    if self.closed then return false, "closed" end
    if self.scope >= MAX_COUNTER then return false, "counter_exhausted" end
    self.resetPending = true
    -- Evidence is invalid immediately, without calling the engine from the API.
    for _, entry in pairs(self.entries) do
        entry.status = { valid = false, reason = "reset_pending", scope = self.scope,
            ticket = entry.status.ticket, visualQualified = false }
    end
    return true, "queued"
end

function Observer:close(reason)
    self.entries, self.order, self.context = {}, {}, nil
    self.contextId, self.resetPending, self.closed = nil, false, true
    self.scope = math.min(self.scope + 1, MAX_COUNTER)
    self.closedReason = reason or "shutdown"
end

function Observer:_reject(label, reason)
    local entry = self.entries[label]
    entry.actor, entry.pending = nil, false
    entry.status = { valid = false, reason = reason, scope = self.scope,
        ticket = entry.status.ticket, frame = self.frame, visualQualified = false }
    self:_log(label, entry.status)
end

function Observer:_invalidate(reason)
    if self.scope >= MAX_COUNTER then self:close("counter_exhausted"); return end
    self.scope = self.scope + 1
    self.context, self.contextId = nil, nil
    for _, label in ipairs(self.order) do
        local entry = self.entries[label]
        if entry.actor then self:_reject(label, reason) end
    end
end

function Observer:_context()
    local game = self.getGame()
    if not game then return nil, "context_unavailable" end
    local requests = game.GetSystemRequestsHandler()
    if not requests then return nil, "context_unavailable" end
    local paused, preGame = requests:IsGamePaused(), requests:IsPreGame()
    if paused == true then return nil, "paused" end
    if preGame == true then return nil, "unloaded" end
    if paused ~= false or preGame ~= false then return nil, "context_unknown" end
    local player = game.GetPlayer()
    if not player then return nil, "unloaded" end
    local id = player:CP2077NpcAppearanceObservation_ContextIdentity(player)
    if not decimal(id, false) then return nil, "context_unavailable" end
    return { actor = player, id = id }
end

function Observer:_sameContext(previous, current, expected)
    return previous:CP2077NpcAppearanceObservation_ContextIdentity(current) == expected
end

function Observer:_capture(entry, context)
    local actor = entry.actor
    local expected = actor:GetEntityID() -- Opaque native wrapper, never converted by Lua.
    local before = actor:CP2077NpcAppearanceObservation_Identity(context.actor)
    local raw = actor:CP2077NpcAppearanceObservation_Capture(context.actor, expected)
    if not raw or raw.valid ~= true then
        local reason = raw and raw.reason
        local allowed = { context_unavailable = true, unsupported_root = true,
            target_unavailable = true, incoherent_capture = true, unknown_record_or_template = true }
        return nil, allowed[reason] and reason or "invalid_native_sample"
    end
    local after = actor:CP2077NpcAppearanceObservation_Identity(context.actor)
    if not decimal(before, false) or before ~= after or raw.entityDecimal ~= before
        or raw.contextDecimal ~= context.id then return nil, "identity_mismatch" end
    if not decimal(raw.recordDecimal, false) or not decimal(raw.templateHash, false)
        or not decimal(raw.appearanceHash, true) or not decimal(raw.colorHash, true)
        or not text(raw.templatePath, 2048) or not text(raw.appearance, 256)
        or not text(raw.color, 256) then return nil, "invalid_native_sample" end
    -- Only primitive data escapes the engine helper. No refs/wrappers in snapshots.
    return { entityId = before, recordId = raw.recordDecimal, templateHash = raw.templateHash,
        templatePath = raw.templatePath, templatePathAvailable = #raw.templatePath > 0,
        appearance = raw.appearance, appearanceHash = raw.appearanceHash,
        appearanceNameAvailable = #raw.appearance > 0,
        color = raw.color, colorHash = raw.colorHash, colorNameAvailable = #raw.color > 0,
        contextId = context.id }
end

function Observer:_tick()
    local context, reason = self:_context()
    if not context then self:_invalidate(reason); return end
    if self.context and (self.contextId ~= context.id
        or not self:_sameContext(self.context, context.actor, self.contextId)) then
        self:_invalidate("context_changed"); return
    end
    self.context, self.contextId = context.actor, context.id
    local results = {}
    for _, label in ipairs(self.order) do
        local entry = self.entries[label]
        if entry.pending then
            local ok, sample, failure = pcall(self._capture, self, entry, context)
            results[label] = { entry = entry, ticket = entry.status.ticket, sample = ok and sample or nil,
                reason = ok and failure or "engine_read_failed" }
        elseif entry.actor and entry.status.valid then
            local ok, id = pcall(function()
                return entry.actor:CP2077NpcAppearanceObservation_Identity(context.actor)
            end)
            if not ok or id ~= entry.status.observed.entityId then
                self:_reject(label, "target_identity_lost")
            end
        end
    end
    if self.closed or self.resetPending then return end
    local after, afterReason = self:_context()
    if not after then self:_invalidate(afterReason); return end
    if after.id ~= context.id or not self:_sameContext(context.actor, after.actor, context.id) then
        self:_invalidate("context_changed"); return
    end
    for _, label in ipairs(self.order) do
        local result, entry = results[label], self.entries[label]
        if self.closed or self.resetPending then return end
        if result and entry == result.entry and entry.status.ticket == result.ticket and entry.pending then
            if not result.sample then self:_reject(label, result.reason)
            else
                entry.pending = false
                entry.status = { valid = true, reason = "captured", scope = self.scope,
                    ticket = entry.status.ticket, frame = self.frame, observed = result.sample,
                    historical = true, visualQualified = false }
                self:_log(label, entry.status)
            end
        end
    end
end

function Observer:update(dt)
    if self.closed then return end
    if self.frame >= MAX_COUNTER then self:close("counter_exhausted"); return end
    self.frame = self.frame + 1
    if self.resetPending then
        self.entries, self.order, self.context = {}, {}, nil
        self.contextId, self.resetPending = nil, false
        self.scope = self.scope + 1
        return
    end
    local active = false
    for _, entry in pairs(self.entries) do if entry.actor then active = true; break end end
    if not active then return end
    if type(dt) ~= "number" or dt ~= dt or dt < 0 or dt > 1 then
        self:_invalidate("update_gap"); return
    end
    local ok = pcall(self._tick, self)
    if not ok then self:_invalidate("context_read_failed") end
end

return Observer
