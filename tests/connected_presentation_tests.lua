local root = assert(arg[1], "repository path required")
local loader = assert(loadfile(root .. "/tests/cet_require.lua"))()
local requireCet = loader(root .. "/experiments/shared-encounter")
local Codec = assert(requireCet("connected/codec"))
local Joiner = assert(requireCet("connected/joiner"))
local checks = 0
local function eq(actual, expected, why)
    checks = checks + 1
    assert(actual == expected, (why or "unexpected value") .. ": "
        .. tostring(actual) .. " ~= " .. tostring(expected))
end

local TARGET = "9007199254740993"
local OTHER = "9007199254740994"
local FIRST = "18014398509481985"
local SECOND = "18014398509481986"

local function fixture(options)
    options = options or {}
    local f = {frames = {}, attempts = {}, mapped = {}, requests = {},
        scope = {session = "1", epoch = 1, generation = "1", self = 2, host = 1, active = true}}
    f.mapped[TARGET] = FIRST
    local config = {
        context = function() return f.scope end,
        resolve = function(target)
            if f.onResolve then f.onResolve(target) end
            if f.resolveError then error("registry temporarily unavailable") end
            return f.mapped[target]
        end,
        apply = function(frame)
            if f.onApply then f.onApply(frame) end
            eq(frame.localKey, f.mapped[frame.sessionKey], "never queue against a retired or unrelated projection")
            f.attempts[#f.attempts + 1] = frame
            if f.applyError then error("partial queue failure") end
            if f.rejectQueue then return false end
            f.frames[#f.frames + 1] = frame
            return true
        end,
        requestTarget = function(request) return f.requests[request] end,
        reactionDuration = 2, deathDuration = 4,
        capacity = options.capacity or 16, eventCapacity = options.eventCapacity or 64
    }
    f.controller = assert(Joiner.new(config))
    function f:outcome(event, life, health, overrides)
        local packet = {type = "outcome", session = self.scope.session, epoch = self.scope.epoch,
            generation = self.scope.generation, host = self.scope.host, hostEvent = event,
            requester = self.scope.self, requestEvent = event, kind = Codec.kind,
            disposition = 2, reason = 0,
            body = assert(Codec.result({target = TARGET, health = health, maximum = 100, life = life}))}
        self.requests[event] = TARGET
        for key, value in pairs(overrides or {}) do packet[key] = value end
        return packet
    end
    function f:accept(packet, now)
        local ok, reason = self.controller:accept(packet, now)
        eq(ok, true, "admit valid result: " .. tostring(reason))
    end
    function f:state()
        return assert(self.controller:inspect(TARGET))
    end
    return f
end

-- A connected death remains terminal through a local asynchronous retirement.
-- No engine call is allowed while the registry has no current exact projection.
do
    local f = fixture()
    f:accept(f:outcome("1", "alive", 75), 0)
    f.controller:step(0)
    eq(f:state().health, 75)
    eq(f:state().maximum, 100)
    eq(f:state().life, "alive")
    f:accept(f:outcome("2", "dead", 0), 1)
    f.controller:step(1)
    eq(f:state().health, 0)
    eq(f:state().life, "dead")
    f.mapped[TARGET] = nil -- old ID may still exist while managed despawn runs
    local before = #f.attempts
    f.controller:step(1.1)
    f.controller:step(1.2)
    eq(#f.attempts, before, "retiring old ID receives no pose")
    f.mapped[TARGET] = SECOND
    f.controller:step(1.3)
    local replacement = f.frames[#f.frames]
    eq(replacement.localKey, SECOND)
    eq(replacement.phase, "dead", "replacement starts at terminal state")
    eq(replacement.progress, 1, "replacement does not replay death")
    eq(f:state().health, 0)
    eq(f:state().life, "dead")
    before = #f.attempts
    f.controller:step(2)
    eq(#f.attempts, before, "terminal pose queues once per exact local binding")
end

-- The state may arrive before any projection, then survive an alive recreation.
-- Supplied state is metadata/pose restoration, never an engine damage request.
do
    local f = fixture()
    f.mapped[TARGET] = nil
    f:accept(f:outcome("1", "alive", 75), 0)
    f.controller:step(0)
    eq(#f.attempts, 0)
    eq(f:state().health, 75)
    f.mapped[TARGET] = FIRST
    f.controller:step(0.1)
    eq(f.frames[#f.frames].phase, "idle", "late projection does not replay an old hit")
    f:accept(f:outcome("2", "alive", 50), 0.2)
    f.controller:step(0.2)
    eq(f.frames[#f.frames].phase, "reaction", "fresh result can react on its current body")
    f.mapped[TARGET] = nil
    f.controller:step(0.3)
    f.mapped[TARGET] = SECOND
    f.controller:step(0.4)
    eq(f.frames[#f.frames].localKey, SECOND)
    eq(f.frames[#f.frames].phase, "idle", "replacement does not replay an in-progress old hit")
    eq(f:state().health, 50)
    eq(f:state().maximum, 100)
    eq(f:state().life, "alive")
end

-- Several results may arrive while unbound. The newest accepted HOST state wins.
do
    local f = fixture()
    f.mapped[TARGET] = nil
    f:accept(f:outcome("9007199254740993", "alive", 50), 0)
    f:accept(f:outcome("9007199254740994", "dead", 0), 0.1)
    f.controller:step(0.2)
    eq(#f.attempts, 0)
    eq(f:state().health, 0)
    eq(f:state().life, "dead")
    eq(f:state().hostEvent, "9007199254740994")
    f.mapped[TARGET] = SECOND
    f.controller:step(0.3)
    eq(f.frames[1].phase, "dead")
    eq(f.frames[1].progress, 1)
end

-- A changed exact mapping can appear between updates without a nil observation.
-- Registry failure is not permission to reuse the formerly bound local handle.
do
    local f = fixture()
    f:accept(f:outcome("1", "dead", 0), 0)
    f.controller:step(0)
    f.controller:step(4)
    f.resolveError = true
    local before = #f.attempts
    f.controller:step(4.1)
    eq(#f.attempts, before, "unavailable identity lookup queues no pose")
    f.resolveError = false
    f.mapped[TARGET] = SECOND
    f.controller:step(4.2)
    eq(f.frames[#f.frames].localKey, SECOND)
    eq(f.frames[#f.frames].phase, "dead")
    eq(f.frames[#f.frames].progress, 1)
    eq(f:state().health, 0)
end

-- Duplicate, stale and conflicting results cannot replay or overwrite a death.
do
    local f = fixture()
    local accepted = f:outcome("9007199254740994", "dead", 0)
    f:accept(accepted, 0)
    f.controller:step(0)
    f.controller:step(4)
    local before = #f.attempts
    eq(f.controller:accept(accepted, 4.1), false, "duplicate is not another hit")
    eq(f.controller:accept(f:outcome("9007199254740993", "alive", 75), 4.2), false,
        "adjacent opaque stale ID cannot resurrect")
    eq(f.controller:accept(f:outcome("9007199254740994", "alive", 75), 4.3), false,
        "same event with different body is rejected")
    eq(f.controller:accept(f:outcome("9007199254740995", "alive", 75), 4.4), false,
        "newer alive result cannot reverse terminal death in one scope")
    f.controller:step(5)
    eq(#f.attempts, before)
    eq(f:state().health, 0)
    eq(f:state().life, "dead")
end

-- A new bridge generation is a separate recovery case. Do not carry old death
-- across it or accept an old-scope callback as fresh authoritative information.
do
    local f = fixture()
    local old = f:outcome("7", "dead", 0)
    f:accept(old, 0)
    f.controller:step(0)
    f.controller:step(4)
    f.scope.generation = "2"
    f.mapped[TARGET] = SECOND
    local before = #f.attempts
    f.controller:step(5)
    eq(f.controller:inspect(TARGET), nil, "scope change clears retained outcome")
    eq(f.controller:accept(old, 5.1), false, "old generation cannot restore state")
    f.controller:step(5.2)
    eq(#f.attempts, before, "new scope needs freshly supplied state")
    f:accept(f:outcome("8", "dead", 0), 5.3)
    f.controller:step(5.3)
    f.controller:step(9.3)
    eq(f.frames[#f.frames].localKey, SECOND)
    eq(f.frames[#f.frames].phase, "dead")
    eq(f.frames[#f.frames].progress, 1)
end

-- Queue failure can happen after one setter. Keep the accepted state and retry
-- the same desired pose; success is queue acceptance, not visual observation.
do
    local f = fixture()
    f.mapped[TARGET] = nil
    f:accept(f:outcome("1", "dead", 0), 0)
    f.mapped[TARGET], f.applyError = SECOND, true
    f.controller:step(1)
    eq(#f.attempts, 1)
    eq(#f.frames, 0)
    eq(f:state().life, "dead")
    f.applyError, f.rejectQueue = false, true
    f.controller:step(2)
    eq(#f.attempts, 2)
    eq(#f.frames, 0)
    f.rejectQueue = false
    f.controller:step(3)
    eq(#f.attempts, 3)
    eq(#f.frames, 1)
    for _, frame in ipairs(f.attempts) do
        eq(frame.localKey, SECOND)
        eq(frame.phase, "dead")
        eq(frame.progress, 1)
    end
    f.controller:step(4)
    eq(#f.attempts, 3)
end

-- Rejected or unsupported input must not consume a valid event identity or
-- alter the last state. Own outcomes must match the locally submitted target.
for _, invalid in ipairs({"host", "kind", "body", "own_target", "own_missing", "disposition", "scope"}) do
    local f = fixture()
    local packet = f:outcome("1", "alive", 75)
    if invalid == "host" then packet.host = 3
    elseif invalid == "kind" then packet.kind = Codec.kind + 1
    elseif invalid == "body" then packet.body = packet.body .. "00"
    elseif invalid == "own_target" then f.requests[packet.requestEvent] = OTHER
    elseif invalid == "own_missing" then f.requests[packet.requestEvent] = nil
    elseif invalid == "disposition" then packet.disposition = 3
    else packet.generation = "2" end
    eq(f.controller:accept(packet, 0), false, invalid)
    f.controller:step(0)
    eq(f.controller:inspect(TARGET), nil, invalid .. " did not admit a state")
    eq(#f.attempts, 0)
    f:accept(f:outcome("1", "alive", 75), 0.1)
    eq(f:state().health, 75, "correct outcome still admitted after " .. invalid)
end

do
    local f = fixture()
    local ok, reason = f.controller:accept(f:outcome("1", "defeated", 0), 0)
    eq(ok, false)
    eq(reason, "unsupported_life", "defeated must not silently use an alive reaction")
    f.controller:step(0)
    eq(#f.attempts, 0)
    eq(f.controller:inspect(TARGET), nil)
    f:accept(f:outcome("1", "dead", 0), 0.1)
    eq(f:state().life, "dead")
end

-- Bounded admission rejects additional state instead of evicting a retained
-- corpse. Existing state remains usable, including on a replacement projection.
do
    local f = fixture({capacity = 1})
    f:accept(f:outcome("1", "dead", 0), 0)
    f.controller:step(0)
    local packet = f:outcome("2", "alive", 50, {
        body = assert(Codec.result({target = OTHER, health = 50, maximum = 100, life = "alive"}))})
    f.requests[packet.requestEvent] = OTHER
    local ok, reason = f.controller:accept(packet, 0.1)
    eq(ok, false)
    eq(reason, "full")
    eq(f.controller:inspect(OTHER), nil)
    eq(f:state().life, "dead")
    f.mapped[TARGET] = SECOND
    f.controller:step(0.2)
    eq(f.frames[#f.frames].localKey, SECOND)
    eq(f.frames[#f.frames].phase, "dead")
    eq(f.frames[#f.frames].progress, 1)
end

do
    local f = fixture({eventCapacity = 1})
    f:accept(f:outcome("1", "dead", 0), 0)
    f.controller:step(0)
    local ok, reason = f.controller:accept(f:outcome("2", "dead", 0), 0.1)
    eq(ok, false)
    eq(reason, "event_full")
    eq(f:state().hostEvent, "1", "event admission never evicts the existing watermark")
    f.mapped[TARGET] = SECOND
    f.controller:step(0.2)
    eq(f.frames[#f.frames].phase, "dead")
    eq(f.frames[#f.frames].progress, 1)
    eq(f:state().health, 0)
end

-- Diagnostics return copies. Consumers cannot resurrect or alter retained state
-- by mutating either the top-level observation or its pose snapshot.
do
    local f = fixture()
    f.mapped[TARGET] = nil
    f:accept(f:outcome("1", "dead", 0), 0)
    f.mapped[TARGET] = FIRST
    f.controller:step(0.1)
    local snapshot = f:state()
    snapshot.health, snapshot.maximum, snapshot.life, snapshot.hostEvent = 100, 200, "alive", "99"
    snapshot.pose.phase, snapshot.pose.health = "idle", 100
    local current = f:state()
    eq(current.health, 0)
    eq(current.maximum, 100)
    eq(current.life, "dead")
    eq(current.hostEvent, "1")
    eq(current.pose.phase, "dead")
    eq(current.pose.health, 0)
end

-- A delayed engine update does not restart an already expired transient.
for _, life in ipairs({"alive", "dead"}) do
    local f = fixture()
    f:accept(f:outcome("1", life, life == "dead" and 0 or 75), 0)
    f.controller:step(10)
    eq(f.frames[1].phase, life == "dead" and "dead" or "idle")
    eq(f.frames[1].progress, life == "dead" and 1 or 0)
end

-- Mapping callbacks cannot carry a result across a scope transition or enter
-- the controller recursively while an engine callback is being applied.
do
    local f = fixture()
    f:accept(f:outcome("1", "dead", 0), 0)
    f.onResolve = function() f.scope.generation = "2" end
    eq(f.controller:step(1), false)
    eq(#f.attempts, 0)
    eq(f.controller:inspect(TARGET), nil)
end
do
    local f = fixture()
    local packet = f:outcome("1", "dead", 0)
    f:accept(packet, 0)
    f.onApply = function()
        local ok, reason = f.controller:accept(packet, 0)
        eq(ok, false)
        eq(reason, "callback_busy")
    end
    f.controller:step(0)
    eq(#f.frames, 1)
end

print("connected JOINER presentation/restoration checks passed: " .. checks)
