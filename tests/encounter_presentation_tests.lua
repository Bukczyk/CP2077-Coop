local root = assert(arg[1])
package.path = root .. "/experiments/shared-encounter/?.lua;" .. package.path
local Presentation = require("presentation_state")

local function rejected(reason, ok, actual)
    assert(ok == false and actual == reason,
        "expected " .. reason .. ", got " .. tostring(ok) .. "/" .. tostring(actual))
end

local function fixture(overrides)
    local f = {mapped = {}, frames = {}, accepts = true}
    local config = {capacity = 2, maxSerial = 100,
        reactionDuration = 2, deathDuration = 4,
        resolve = function(session)
            if f.resolveError then error("engine registry unavailable") end
            return f.mapped[session]
        end,
        apply = function(frame)
            if f.onApply then f.onApply(frame) end
            if f.engineError then error("engine call failed") end
            if f.accepts then f.frames[#f.frames + 1] = frame end
            return f.accepts
        end}
    for k, v in pairs(overrides or {}) do config[k] = v end
    f.controller = assert(Presentation.new(config))
    f.scope = {} -- opaque reference; its contents have no authority semantics
    assert(f.controller:reset(f.scope, 0))
    function f:bind(session, localKey, now)
        self.mapped[session] = localKey
        assert(self.controller:bind(self.scope, session, localKey, now or 0))
    end
    return f
end

-- Reaction progress and completion, duplicate/stale local serials, then death.
do
    local f = fixture()
    local c, s = f.controller, f.scope
    f:bind("entity-a", "projection-a")
    assert(c:apply(s, "entity-a", "projection-a", 0))
    assert(f.frames[1].phase == "idle")
    assert(c:stage(s, "entity-a", "projection-a", 2, "reaction", 1))
    rejected("duplicate", c:stage(s, "entity-a", "projection-a", 2, "reaction", 1))
    rejected("stale_serial", c:stage(s, "entity-a", "projection-a", 1, "death", 1))
    assert(c:apply(s, "entity-a", "projection-a", 1))
    assert(f.frames[2].phase == "reaction" and f.frames[2].progress == 0)
    assert(c:apply(s, "entity-a", "projection-a", 2))
    assert(f.frames[3].phase == "reaction" and f.frames[3].progress == 0.5)
    assert(c:apply(s, "entity-a", "projection-a", 3))
    assert(f.frames[4].phase == "idle")
    local ok, reason = c:apply(s, "entity-a", "projection-a", 4)
    assert(ok and reason == "unchanged" and #f.frames == 4)
    assert(c:stage(s, "entity-a", "projection-a", 3, "death", 4))
    assert(c:apply(s, "entity-a", "projection-a", 6))
    assert(f.frames[5].phase == "death" and f.frames[5].progress == 0.5)
    assert(c:apply(s, "entity-a", "projection-a", 8))
    assert(f.frames[6].phase == "dead" and f.frames[6].progress == 1)
    rejected("terminal_death", c:stage(s, "entity-a", "projection-a", 4, "reaction", 9))
    rejected("terminal_death", c:stage(s, "entity-a", "projection-a", 4, "death", 9))
    assert(c:apply(s, "entity-a", "projection-a", 10))
    assert(#f.frames == 6 and c:inspect(s, "entity-a").dead)
end

-- Exact opaque keys retain adjacent 64-bit values; wrong, replaced and unknown
-- mappings never reach the engine. A dead entity survives local recreation.
do
    local f = fixture()
    local c, s = f.controller, f.scope
    local a, b = "18446744073709551614ULL", "18446744073709551613ULL"
    local pa, pb = "9007199254740993ULL", "9007199254740994ULL"
    f:bind(a, pa)
    f:bind(b, pb)
    rejected("wrong_projection", c:stage(s, a, pb, 1, "death", 0))
    rejected("unknown_entity", c:stage(s, "unknown", pa, 1, "death", 0))
    f.mapped[a] = pb
    rejected("wrong_mapping", c:stage(s, a, pa, 1, "death", 0))
    rejected("wrong_mapping", c:apply(s, a, pa, 0))
    f.mapped[a] = nil
    rejected("mapping_missing", c:apply(s, a, pa, 0))
    f.mapped[a] = pa
    f.resolveError = true
    rejected("mapping_unavailable", c:apply(s, a, pa, 0))
    f.resolveError = false
    assert(#f.frames == 0)
    assert(c:stage(s, a, pa, 1, "death", 0))
    assert(c:apply(s, a, pa, 1))
    assert(c:unbind(s, a, pa, 1))
    rejected("unbound", c:apply(s, a, pa, 1))
    f.mapped[a] = "new-projection"
    assert(c:bind(s, a, "new-projection", 1))
    assert(c:apply(s, a, "new-projection", 1))
    assert(f.frames[2].phase == "dead" and f.frames[2].progress == 1)
    rejected("wrong_projection", c:unbind(s, a, pa, 1))
    rejected("duplicate", c:stage(s, a, "new-projection", 1, "death", 1))
    rejected("terminal_death", c:stage(s, a, "new-projection", 2, "reaction", 1))
    assert(c:inspect(s, b).serial == 0 and not c:inspect(s, b).dead)
end

-- Full capacity explicitly rejects admission. Unbinding does not discard the
-- scoped record to create space; reset needs a different scope and clears it.
do
    local f = fixture({capacity = 1})
    local c, s = f.controller, f.scope
    f:bind("a", "pa")
    assert(c:stage(s, "a", "pa", 1, "death", 0))
    assert(c:unbind(s, "a", "pa", 0))
    f.mapped.b = "pb"
    rejected("full", c:bind(s, "b", "pb", 0))
    assert(c:size() == 1 and c:inspect(s, "a").dead)
    rejected("same_scope", c:reset(s, 0))
    local nextScope = {}
    assert(c:reset(nextScope, 0) and c:size() == 0)
    rejected("wrong_scope", c:bind(s, "b", "pb", 0))
    assert(c:bind(nextScope, "b", "pb", 0))
    rejected("wrong_scope", c:stage(s, "b", "pb", 2, "death", 0))
    rejected("wrong_scope", c:apply(s, "b", "pb", 0))
    assert(c:apply(nextScope, "b", "pb", 0))
    assert(f.frames[1].phase == "idle")
end

-- Queue failure/exception retains the desired state. Success means only queue
-- acceptance; this fixture makes no visual observation or network guarantee.
do
    local f = fixture()
    local c, s = f.controller, f.scope
    f:bind("a", "pa")
    assert(c:stage(s, "a", "pa", 1, "death", 0))
    f.accepts = false
    rejected("engine_rejected", c:apply(s, "a", "pa", 1))
    rejected("terminal_death", c:stage(s, "a", "pa", 2, "reaction", 1))
    f.engineError = true
    rejected("engine_error", c:apply(s, "a", "pa", 2))
    f.engineError, f.accepts = false, true
    local ok, reason, frame = c:apply(s, "a", "pa", 5)
    assert(ok and reason == "queued" and frame.phase == "dead" and #f.frames == 1)
end

-- All scalar limits, malformed keys, nonfinite/backwards clocks and serial
-- exhaustion are checked before committing any local presentation instruction.
do
    local f = fixture({maxSerial = 3})
    local c, s = f.controller, f.scope
    f:bind("a", "pa")
    for _, invalid in ipairs({math.huge, -math.huge, 0/0, -1, "1"}) do
        rejected("invalid_time", c:stage(s, "a", "pa", 1, "reaction", invalid))
    end
    for _, invalid in ipairs({0, -1, 1.5, 4, math.huge, -math.huge, 0/0, "1"}) do
        rejected("invalid_serial", c:stage(s, "a", "pa", invalid, "reaction", 0))
    end
    rejected("invalid_kind", c:stage(s, "a", "pa", 1, "revive", 0))
    rejected("invalid_key", c:bind(s, 9007199254740992, "pb", 0))
    rejected("invalid_key", c:bind(s, "b", "", 0))
    rejected("invalid_key", c:bind(s, string.rep("x", 257), "pb", 0))
    assert(c:inspect(s, "a").serial == 0 and #f.frames == 0)
    assert(c:stage(s, "a", "pa", 3, "reaction", 2))
    rejected("stale_time", c:apply(s, "a", "pa", 1))
    rejected("stale_time", c:unbind(s, "a", "pa", 1))
    rejected("invalid_serial", c:stage(s, "a", "pa", 4, "death", 2))
    assert(not c:inspect(s, "a").dead)
end

-- Mapping ownership, snapshot isolation, repeated bind and callback reentrancy.
do
    local f = fixture()
    local c, s = f.controller, f.scope
    f:bind("a", "pa")
    f.mapped.b = "pa"
    rejected("projection_in_use", c:bind(s, "b", "pa", 0))
    rejected("already_bound", c:bind(s, "a", "pb", 0))
    assert(c:stage(s, "a", "pa", 1, "reaction", 0))
    assert(c:bind(s, "a", "pa", 1))
    local copy = c:inspect(s, "a")
    copy.dead, copy.serial = true, 99
    assert(not c:inspect(s, "a").dead and c:inspect(s, "a").serial == 1)
    f.onApply = function()
        rejected("callback_busy", c:reset({}, 0))
        rejected("callback_busy", c:stage(s, "a", "pa", 2, "death", 1))
    end
    assert(c:apply(s, "a", "pa", 1))
    assert(f.frames[1].progress == 0.5, "repeated bind restarted the clip")
    assert(not c:inspect(s, "a").dead)
end

for _, invalid in ipairs({false, 0, -1, 1.5, 4097, math.huge, 0/0}) do
    local c, reason = Presentation.new({capacity = invalid,
        reactionDuration = 1, deathDuration = 2, resolve = function() end, apply = function() end})
    assert(c == nil and reason == "invalid_config")
end
for _, invalid in ipairs({0, -1, 601, math.huge, 0/0, "1"}) do
    local c, reason = Presentation.new({reactionDuration = invalid,
        deathDuration = 2, resolve = function() end, apply = function() end})
    assert(c == nil and reason == "invalid_config")
end
for _, field in ipairs({"reactionDuration", "deathDuration", "maxSerial"}) do
    local config = {reactionDuration = 1, deathDuration = 2,
        resolve = function() end, apply = function() end}
    config[field] = 0/0
    local c, reason = Presentation.new(config)
    assert(c == nil and reason == "invalid_config")
end
do
    local f = fixture()
    local c, s = f.controller, f.scope
    for _, invalid in ipairs({false, 1, ""}) do
        rejected("invalid_scope", c:reset(invalid, 0))
    end
    rejected("invalid_time", c:reset({}, math.huge))
    f:bind("a", "pa")
    assert(c:inspect(s, "a").serial == 0, "invalid reset discarded the live scope")
    rejected("mapping_missing", c:bind(s, "b", "pb", 0))
    assert(c:size() == 1, "failed binding consumed capacity")
end

print("encounter presentation local fixture tests passed")
