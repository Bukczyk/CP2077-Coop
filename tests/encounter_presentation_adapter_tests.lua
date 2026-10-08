local root = assert(arg[1])
package.path = root .. "/experiments/shared-encounter/?.lua;" .. package.path

-- Model CET NewObject's native RTTI lookup, not REDscript alias resolution.
-- The old short name must fail here exactly as it failed in the live probe.
local available = {entAnimInputSetterFloat = true}
local constructions = {}
NewObject = function(name)
    constructions[#constructions + 1] = name
    if available[name] then return {nativeType = name} end
    return nil
end
CName = {new = function(value) return value end}

assert(NewObject("AnimInputSetterFloat") == nil)
local Adapter = require("presentation")
local events = {}
local entity = {QueueEvent = function(_, event)
    assert(event.nativeType == "entAnimInputSetterFloat")
    events[#events + 1] = event
end}

local function event(index, key, value)
    assert(events[index].key == key and events[index].value == value)
end

local ok, reason = Adapter.apply(entity, "reaction", 0.5)
assert(ok and reason == "queued_not_observed" and #events == 2)
assert(constructions[2] == "entAnimInputSetterFloat")
event(1, "cp_coop_hit_progress", 0.5)
event(2, "cp_coop_phase", 1)

ok, reason = Adapter.apply(entity, "death", 1)
assert(ok and reason == "queued_not_observed" and #events == 4)
event(3, "cp_coop_death_progress", 1)
event(4, "cp_coop_phase", 2)
assert(Adapter.apply(entity, "death", 1))
event(5, "cp_coop_death_progress", 1)
event(6, "cp_coop_phase", 2) -- resamples terminal pose instead of restart event

assert(Adapter.apply(entity, "idle", 0))
event(7, "cp_coop_phase", 0)
local before = #constructions
for _, value in ipairs({-1, 1.1, math.huge, -math.huge, 0/0, "0.5", false}) do
    assert(not Adapter.apply(entity, "death", value))
end
assert(not Adapter.apply(entity, "death", nil))
assert(not Adapter.apply(entity, "unsupported", 0))
assert(not Adapter.apply(nil, "idle", 0))
assert(#events == 7 and #constructions == before)

-- Constructor lookup failure queues no event and never reports success.
available.entAnimInputSetterFloat = false
ok, reason = Adapter.apply(entity, "death", 1)
assert(not ok and reason:find("entAnimInputSetterFloat unavailable", 1, true))
assert(#events == 7)
available.entAnimInputSetterFloat = true

-- QueueEvent is void and can fail after the first setter was already queued.
-- The caller must not acknowledge application or discard retry state.
local calls = 0
local partial = {QueueEvent = function()
    calls = calls + 1
    if calls == 2 then error("fixture queue failure") end
end}
ok, reason = Adapter.apply(partial, "reaction", 0.5)
assert(not ok and reason:find("queue_failed_or_partial", 1, true) and calls == 2)
assert(reason:find("fixture queue failure", 1, true))

print("encounter presentation adapter: native RTTI lookup, queue ordering, bounded inputs and failure checks PASS")
