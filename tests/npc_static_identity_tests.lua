local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path

-- EntityID is a wrapper around an opaque Uint64, not a stable Lua table address.
-- Decimal text stands in for the Uint64 value so this test never rounds through
-- a Lua number; adjacent identities above 2^53 must remain separate.
local wrapperSerial = 0
local function entityId(hash)
    wrapperSerial = wrapperSerial + 1
    local serial = wrapperSerial
    local opaque = setmetatable({}, {__tostring = function() return hash end})
    return setmetatable({hash = opaque}, {
        __tostring = function() return "EntityID wrapper #" .. serial end
    })
end
local function hashOf(id) return tostring(id.hash) end
local function npc(session, overrides)
    local value = {entity = session, x = 1, y = 2, z = 3, yaw = 0.5}
    for field, replacement in pairs(overrides or {}) do value[field] = replacement end
    return value
end

local function fixture(hashes)
    local f = {spawnCalls = 0, bindCalls = 0, unbindCalls = 0, despawnCalls = 0, moves = 0,
        entries = {}, mapped = {}, despawnMode = "queued", observationError = false}
    local system = {}
    function system:IsReady()
        if f.readyOverride then return f.readyOverride.value end
        return true
    end
    function system:SpawnEntity(spec)
        f.spawnCalls = f.spawnCalls + 1
        local hash = assert(hashes[f.spawnCalls], "unexpected duplicate spawn")
        local entry = {hash = hash, managed = true, spawning = false,
            spawned = true, visibleHandle = true, attached = true, spec = spec}
        entry.actor = {
            GetEntityID = function() return entityId(entry.actualHash or hash) end,
            IsAttached = function() return entry.attached end,
            SetWorldTransform = function(_, world)
                f.moves = f.moves + 1
                entry.lastTransform = world
            end
        }
        f.entries[hash] = entry
        return entityId(hash)
    end
    function system:IsManaged(id)
        if f.observationError then error("engine observation temporarily unavailable") end
        return assert(f.entries[hashOf(id)]).managed
    end
    function system:IsSpawning(id) return assert(f.entries[hashOf(id)]).spawning end
    function system:IsSpawned(id) return assert(f.entries[hashOf(id)]).spawned end
    function system:GetEntity(id)
        local entry = assert(f.entries[hashOf(id)])
        return entry.visibleHandle and entry.actor or nil
    end
    function system:DespawnEntity(id)
        assert(f.entries[hashOf(id)], "attempted to remove an unowned entity")
        f.despawnCalls = f.despawnCalls + 1
        if f.despawnMode == "error" then error("despawn failed") end
        return f.despawnMode ~= "rejected"
    end
    Game = {
        GetStaticEntitySystem = function() return f.systemOverride or system end,
        FindEntityByID = function(id)
            local entry = f.entries[hashOf(id)]
            if not entry then return nil end
            local visible = entry.globalVisible
            if visible == nil then visible = entry.visibleHandle end
            return visible and (entry.globalActor or entry.actor) or nil
        end,
        CP2077Session_Bind = function(session, localId)
            f.bindCalls = f.bindCalls + 1
            assert(not f.mapped[session], "duplicate native bind")
            f.mapped[session] = hashOf(localId)
            return true
        end,
        CP2077Session_Unbind = function(session)
            f.unbindCalls = f.unbindCalls + 1
            if not f.mapped[session] or f.denyUnbind then return false end
            f.mapped[session] = nil
            return true
        end,
        CP2077Session_Resolve = function(localId)
            if f.resolveError then error("native registry observation unavailable") end
            for session, hash in pairs(f.mapped) do
                if hash == hashOf(localId) then return session end
            end
            return "0ULL"
        end
    }
    StaticEntitySpec = {new = function() return {} end}
    ResRef = {FromName = function(value) return value end}
    CName = {new = function(value) return value end}
    Vector4 = {new = function(x, y, z, w) return {x=x, y=y, z=z, w=w} end}
    Quaternion = {new = function(x, y, z, w) return {x=x, y=y, z=z, w=w} end}
    EulerAngles = {new = function(roll, pitch, yaw) return {roll=roll, pitch=pitch, yaw=yaw} end}
    WorldTransform = {
        new = function() return {} end,
        SetPosition = function(world, position) world.position = position end,
        SetOrientationEuler = function(world, angles) world.angles = angles end
    }
    package.loaded.npc_static_population = nil
    f.adapter = require("npc_static_population")
    return f
end

do
    local first, second = "9007199254740993ULL", "9007199254740994ULL"
    local f = fixture({first, second})
    local a = f.adapter
    local sourceA, sourceB = npc("18014398509481985ULL"), npc("18014398509481986ULL")
    local idA, idB = assert(a.spawn(sourceA)), assert(a.spawn(sourceB))
    assert(tostring(idA) ~= tostring(entityId(first)), "fixture must change wrapper text")
    assert(hashOf(idA) == first and hashOf(idB) == second)
    assert(not a.bind(sourceA.entity, entityId(second)) and f.bindCalls == 0,
        "a different exact identity must never bind")
    f.entries[first].actualHash = second
    assert(not a.bind(sourceA.entity, entityId(first)) and f.bindCalls == 0,
        "the resolved actor must still match the returned local identity")
    f.entries[first].actualHash = nil
    assert(a.bind(sourceA.entity, entityId(first)))
    assert(a.bind(sourceB.entity, entityId(second)))
    assert(f.mapped[sourceA.entity] == first and f.mapped[sourceB.entity] == second)
    assert(a.bind(sourceA.entity, entityId(first)) and f.bindCalls == 2)
    assert(a.move(entityId(first), sourceA) and a.move(entityId(second), sourceB))
    assert(f.moves == 2 and f.entries[first].lastTransform.position.z == 3)
    assert(a.spawn(sourceA) == idA and a.spawn(sourceB) == idB and f.spawnCalls == 2)
    f.entries[first].actualHash = second
    assert(not a.move(entityId(first), sourceA) and f.moves == 2,
        "a replaced actor handle must not receive a transform")
    assert(not a.move(entityId("9007199254740995ULL"), sourceA))
end

do
    local hash = "18446744073709551614ULL"
    local f = fixture({hash, "18446744073709551613ULL"})
    local a, source = f.adapter, npc("9007199254740993ULL")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, entityId(hash)))
    assert(not a.remove(entityId(hash)) and f.despawnCalls == 0,
        "bound projections cannot be despawned")
    assert(a.unbind(source.entity))
    f.despawnMode = "error"
    assert(not a.remove(entityId(hash)) and f.despawnCalls == 1)
    assert(a.spawn(source) == id and f.spawnCalls == 1, "failed despawn lost ownership")
    f.despawnMode = "rejected"
    assert(not a.remove(entityId(hash)) and f.despawnCalls == 2)
    assert(a.spawn(source) == id and f.spawnCalls == 1)
    f.despawnMode = "queued"
    assert(not a.remove(entityId(hash)) and f.despawnCalls == 3,
        "a queued request must not be acknowledged as disappearance")
    local binds, moves = f.bindCalls, f.moves
    local bound, reason = a.bind(source.entity, entityId(hash))
    assert(bound == false and reason == "removing" and f.bindCalls == binds,
        "a still-visible handle pending removal must never rebind")
    assert(not a.move(entityId(hash), source) and f.moves == moves,
        "a retiring entity must not receive a transform")
    local entry = f.entries[hash]
    local function stillOwned()
        assert(not a.remove(entityId(hash)))
        assert(f.despawnCalls == 3, "queued despawn was requested twice")
        assert(a.spawn(source) == id and f.spawnCalls == 1, "pending removal lost ownership")
    end
    stillOwned() -- still managed
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle = false, true, false, false
    stillOwned() -- creation can still be in flight after despawn was queued
    entry.spawning, entry.spawned = false, true
    stillOwned()
    entry.spawned, entry.visibleHandle = false, true
    stillOwned() -- flags are clear but the actual handle has not disappeared
    entry.visibleHandle, f.observationError = false, true
    stillOwned() -- failed observation is not proof of disappearance
    f.observationError = false
    entry.attached = false
    assert(a.remove(entityId(hash)) and f.despawnCalls == 3)
    assert(a.remove(entityId(hash)) and f.despawnCalls == 3)
    assert(a.spawn(source) ~= id and f.spawnCalls == 2,
        "confirmed removal must release the session mapping for later recreation")
end

-- Unknown or malformed flags cannot confirm disappearance, either before any
-- despawn request or while an accepted asynchronous despawn is pending.
for _, field in ipairs({"managed", "spawning", "spawned"}) do
    for _, phase in ipairs({"before", "after"}) do
        for _, kind in ipairs({"nil", "string", "number"}) do
            local first, second = "9007199254740993ULL", "9007199254740994ULL"
            local f = fixture({first, second})
            local a, source = f.adapter, npc("unknown-lifecycle")
            local id = assert(a.spawn(source))
            assert(a.bind(source.entity, id) and a.unbind(source.entity))
            if phase == "after" then
                assert(not a.remove(id) and f.despawnCalls == 1)
            end
            local entry = f.entries[first]
            entry.managed, entry.spawning, entry.spawned, entry.visibleHandle, entry.attached = false, false, false, false, false
            if kind == "nil" then entry[field] = nil
            elseif kind == "string" then entry[field] = "false"
            else entry[field] = 0 end
            local attempts = f.despawnCalls
            assert(not a.remove(entityId(first)), "invalid " .. field .. " cannot prove disappearance")
            assert(f.despawnCalls == attempts, "invalid observations cannot trigger another despawn")
            assert(a.spawn(source) == id and f.spawnCalls == 1, "unknown lifetime must retain its exact ID")
            entry[field] = false
            assert(a.remove(entityId(first)) and f.despawnCalls == attempts)
            assert(hashOf(a.spawn(source)) == second and f.spawnCalls == 2,
                "known false observations and no handle permit replacement")
        end
    end
end

do
    local f = fixture({"9007199254740993ULL"})
    local a = f.adapter
    for _, field in ipairs({"x", "y", "z", "yaw"}) do
        for _, invalid in ipairs({math.huge, -math.huge, 0/0}) do
            assert(a.spawn(npc("invalid", {[field] = invalid})) == nil)
        end
    end
    assert(f.spawnCalls == 0, "non-finite transform reached the engine")
    local source = npc("valid")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, entityId(hashOf(id))))
    for _, field in ipairs({"x", "y", "z", "yaw"}) do
        for _, invalid in ipairs({math.huge, -math.huge, 0/0}) do
            assert(not a.move(entityId(hashOf(id)), npc("valid", {[field] = invalid})))
        end
    end
    assert(f.moves == 0, "non-finite move reached the engine")
end

do
    local first, second = "9007199254740993ULL", "9007199254740994ULL"
    local f = fixture({first, second})
    local a, source = f.adapter, npc("18014398509481985ULL")
    local id = assert(a.spawn(source))
    local entry = f.entries[first]
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle = true, true, false, false
    local bound, reason = a.bind(source.entity, id)
    assert(bound == nil and reason == "pending", "an in-flight token must remain pending")
    entry.spawning = false
    bound, reason = a.bind(source.entity, id)
    assert(bound == nil and reason == "pending", "a managed token transition must remain pending")
    entry.managed = false -- Token removal does not prove callback completion.
    bound, reason = a.bind(source.entity, id)
    assert(bound == nil and reason == "pending", "unknown creation must retain callback ownership")
    assert(not a.remove(id) and f.despawnCalls == 0,
        "never-completed token cannot be cancelled or released")
    assert(a.spawn(source) == id and f.spawnCalls == 1)
    -- Late success is retired under the original owner, never rebound.
    entry.managed, entry.spawned, entry.visibleHandle, entry.attached = true, true, true, true
    assert(not a.remove(id) and f.despawnCalls == 1)
    assert(a.bind(source.entity, id) == false and f.bindCalls == 0)
    entry.managed, entry.spawned, entry.visibleHandle, entry.attached = false, false, false, false
    assert(a.remove(id) and hashOf(a.spawn(source)) == second and f.spawnCalls == 2)
end

do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("18014398509481985ULL")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, id))
    f.mapped = {} -- registry and engine were cleared before Lua cleanup
    local entry = f.entries[hash]
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle, entry.attached = false, false, false, false, false
    f.despawnMode = "rejected"
    assert(a.unbind(source.entity) and a.remove(id))
    assert(f.unbindCalls == 0 and f.despawnCalls == 0,
        "observed prior cleanup must not depend on repeated native calls succeeding")
end

do
    local first, second = "9007199254740993ULL", "9007199254740994ULL"
    local f = fixture({first, second})
    local controller = require("npc_runtime").new(f.adapter)
    local source = npc("18014398509481985ULL")
    local bubble = {radius = 20, centers = {{x=0,y=0,z=0}}}
    assert(controller:step("generation-1", bubble, {source}))
    assert(f.mapped[source.entity] == first)
    -- The real native BeginFrame/SetActive path clears or removes registry
    -- records before Lua asks the old projection to clean up.
    f.mapped = {}
    assert(not controller:step("generation-2", bubble, {source}))
    assert(f.unbindCalls == 0 and f.despawnCalls == 1 and f.spawnCalls == 1,
        "a retired native mapping must allow despawn but still await disappearance")
    local entry = f.entries[first]
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle, entry.attached = false, false, false, false, false
    assert(controller:step("generation-2", bubble, {source}))
    assert(f.spawnCalls == 2 and f.mapped[source.entity] == second,
        "confirmed cleanup must allow a new-generation projection")
end

do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("18014398509481985ULL")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, id))
    f.resolveError = true
    assert(not a.unbind(source.entity) and f.unbindCalls == 0)
    assert(not a.remove(id), "failed lookup must retain bound ownership")
    f.resolveError = false
    f.mapped[source.entity], f.mapped["18014398509481986ULL"] = nil, hash
    assert(not a.unbind(source.entity) and f.unbindCalls == 0,
        "a different exact session mapping must not be unbound")
    assert(not a.remove(id) and f.despawnCalls == 0)
    f.mapped["18014398509481986ULL"], f.mapped[source.entity] = nil, hash
    f.denyUnbind = true
    assert(not a.unbind(source.entity) and f.unbindCalls == 1)
    assert(not a.remove(id), "a rejected native unbind must retain ownership")
    f.denyUnbind = false
    assert(a.unbind(source.entity) and f.unbindCalls == 2)
end

-- Explicit reset within the SAME epoch used to rebind the old visible handle
-- on the next step because only identity changes forced cleanup to resume.
do
    local first, second = "9007199254740993ULL", "9007199254740994ULL"
    local f = fixture({first, second})
    local attempts = 0
    local bind = f.adapter.bind
    f.adapter.bind = function(...)
        attempts = attempts + 1
        return bind(...)
    end
    local controller = require("npc_runtime").new(f.adapter)
    local source = npc("18014398509481985ULL")
    local bubble = {radius = 20, centers = {{x=0,y=0,z=0}}}
    assert(controller:step("same-epoch", bubble, {source}))
    assert(attempts == 1 and f.moves == 1 and f.mapped[source.entity] == first)
    assert(not controller:reset() and controller.resetting)
    assert(controller.owned[source.entity].retiring and not controller.owned[source.entity].bound)
    for _ = 1, 3 do
        assert(not controller:step("same-epoch", bubble, {source}))
        assert(controller.resetting and f.spawnCalls == 1 and attempts == 1 and f.moves == 1,
            "same-epoch pending reset accessed a retiring projection")
        assert(f.despawnCalls == 1 and f.mapped[source.entity] == nil)
    end
    local old = f.entries[first]
    old.managed, old.spawning, old.spawned, old.visibleHandle, old.attached = false, false, false, false, false
    assert(controller:step("same-epoch", bubble, {source}))
    assert(not controller.resetting and f.spawnCalls == 2 and attempts == 2)
    assert(f.mapped[source.entity] == second and not controller.owned[source.entity].retiring,
        "confirmed removal must allow a fresh exact ID in the same epoch")
end

-- Failed unbind still marks the old projection retiring, and each next step
-- makes at most one cleanup attempt without further binding or movement.
do
    local f = fixture({"9007199254740993ULL"})
    local controller = require("npc_runtime").new(f.adapter)
    local source = npc("18014398509481985ULL")
    local bubble = {radius = 20, centers = {{x=0,y=0,z=0}}}
    assert(controller:step("same-epoch", bubble, {source}))
    f.denyUnbind = true
    assert(not controller:reset() and controller.resetting)
    assert(controller.owned[source.entity].retiring)
    for attempt = 2, 4 do
        assert(not controller:step("same-epoch", bubble, {source}))
        assert(f.unbindCalls == attempt and f.bindCalls == 1 and f.moves == 1)
        assert(f.despawnCalls == 0, "despawn must wait for confirmed unbind")
    end
end

-- Relevance can return while a prior bubble-exit despawn is still pending.
-- Retirement must finish even though that entity is desired again.
do
    local first, second, third = "9007199254740993ULL", "9007199254740994ULL", "9007199254740995ULL"
    local f = fixture({first, second, third})
    local controller = require("npc_runtime").new(f.adapter)
    local source = npc("18014398509481985ULL")
    local other = npc("18014398509481986ULL")
    local bubble = {radius = 20, centers = {{x=0,y=0,z=0}}}
    assert(controller:step("same-epoch", bubble, {source, other}))
    local retiringHash, survivingHash = f.mapped[source.entity], f.mapped[other.entity]
    assert(not controller:step("same-epoch", bubble, {other}))
    assert(controller.owned[source.entity].retiring and not controller.resetting)
    local binds, moves = f.bindCalls, f.moves
    assert(not controller:step("same-epoch", bubble, {source, other}))
    assert(f.bindCalls == binds and f.moves == moves and f.despawnCalls == 1)
    local old = f.entries[retiringHash]
    old.managed, old.spawning, old.spawned, old.visibleHandle, old.attached = false, false, false, false, false
    assert(controller:step("same-epoch", bubble, {source, other}))
    assert(f.mapped[source.entity] == third and f.mapped[other.entity] == survivingHash)
end

for _, zero in ipairs({"0", "0ULL", "0ull"}) do
    local f = fixture({zero, "9007199254740993ULL"})
    assert(f.adapter.spawn(npc("zero-return")) == nil, "zero EntityID hash was accepted")
    assert(f.bindCalls == 0)
    assert(f.adapter.spawn(npc("zero-return")) ~= nil and f.spawnCalls == 2,
        "a rejected zero identity must not reserve the session mapping")
end

-- A transient creator lookup must not replace the first retained live handle.
do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("retained-handle")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, id) and a.unbind(source.entity))
    local entry, original = f.entries[hash], f.entries[hash].actor
    assert(not a.remove(id) and f.despawnCalls == 1)
    entry.actor = {GetEntityID=function() return entityId(hash) end, IsAttached=function() return false end}
    assert(not a.remove(id))
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle = false, false, false, false
    assert(not a.remove(id) and f.despawnCalls == 1,
        "replacement lookup erased the attached retained actor")
    entry.attached = false
    assert(original:IsAttached() == false and a.remove(id))
end

-- Global registry visibility independently blocks release, including a detached
-- object, and foreign identity must never be treated as absence.
do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("global-handle")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, id) and a.unbind(source.entity))
    assert(not a.remove(id))
    local entry = f.entries[hash]
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle, entry.attached = false, false, false, false, false
    entry.globalVisible = true
    assert(not a.remove(id), "global entity is still registered")
    entry.globalActor = {GetEntityID=function() return entityId("foreign") end, IsAttached=function() return false end}
    assert(not a.remove(id), "wrong global identity is unknown, not absent")
    entry.globalVisible = false
    assert(a.remove(id))
end

-- Only creator-owned, managed, spawned and attached observation completes a
-- creation. Global/retained attachment by itself cannot authorize cancellation.
for _, missing in ipairs({"managed", "spawned", "spawning", "creatorHandle"}) do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("incomplete-" .. missing)
    local id = assert(a.spawn(source))
    local entry = f.entries[hash]
    entry.globalVisible = true
    if missing == "managed" then entry.managed = false
    elseif missing == "spawned" then entry.spawned = false
    elseif missing == "spawning" then entry.spawning = true
    else entry.visibleHandle = false end
    assert(not a.remove(id) and f.despawnCalls == 0)
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle, entry.globalVisible, entry.attached = false, false, false, false, false, false
    assert(not a.remove(id) and a.spawn(source) == id and f.spawnCalls == 1,
        "an incomplete creator observation cannot release a future callback")
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle, entry.globalVisible, entry.attached = true, false, true, true, true, true
    assert(not a.remove(id) and f.despawnCalls == 1)
    entry.managed, entry.spawned, entry.visibleHandle, entry.globalVisible, entry.attached = false, false, false, false, false
    assert(a.remove(id))
end

-- Unknown attachment/readiness must not become false, and a fresh system lookup
-- cannot take ownership of a token created by the retained original system.
for _, invalid in ipairs({{}, {value="true"}, {value=1}, {value=false}}) do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("strict-readiness")
    local id = assert(a.spawn(source))
    f.readyOverride = invalid
    f.systemOverride = {IsReady=function() return true end,
        DespawnEntity=function() error("replacement system must not be used") end}
    assert(not a.remove(id) and f.despawnCalls == 0)
    f.readyOverride = nil
    assert(not a.remove(id) and f.despawnCalls == 1,
        "retained creator must remain usable despite fresh Game wrapper")
end
for _, invalid in ipairs({{}, {value="false"}, {value=0}}) do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("strict-attachment")
    local id = assert(a.spawn(source))
    local entry = f.entries[hash]
    entry.attached = invalid.value
    assert(not a.remove(id) and f.despawnCalls == 0)
    entry.attached = true
    assert(not a.remove(id) and f.despawnCalls == 1)
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle = false, false, false, false
    entry.attached = invalid.value
    assert(not a.remove(id), "unknown retained attachment cannot prove disappearance")
    entry.attached = false
    assert(a.remove(id))
end

print("Static projection opaque identity, pending token ownership and observed retirement checks passed")

-- Exercise real init.lua, runtime and adapter through the reconnect hotkey.
do
local report=print
local f={tokens={},actors={},globals={},disposed={},callbacks={},despawns={},nextId=0,bindings={},logs={}}
local events,hotkeys={},{}
local function id(value) return {hash=value} end
local function key(value) return value.hash end
local static={}
function static:IsReady() return true end
function static:SpawnEntity(spec)
    f.nextId=f.nextId+1
    local value="900719925474099"..(f.nextId+2).."ULL"
    local token={failed=false,aborted=false}
    f.tokens[value]=token
    -- A callback already queued/running holds its own token reference. Erasing
    -- the static system's token map does not set failed/aborted in that object.
    f.callbacks[value]=function()
        local actor={attached=true,GetEntityID=function() return id(value) end,
            SetWorldTransform=function() end,IsAttached=function(self) return self.attached end}
        token.entity=actor
        assert(not token.failed and not token.aborted)
        f.actors[value], f.globals[value]=actor,actor
        f.tokens[value]=nil
    end
    return id(value)
end
function static:IsManaged(value)
    if f.unknownFlags then return nil end
    return f.tokens[key(value)]~=nil or f.actors[key(value)]~=nil
end
function static:IsSpawning(value)
    local token=f.tokens[key(value)]
    return token~=nil and not token.entity and not token.failed and not token.aborted
end
function static:IsSpawned(value) return f.actors[key(value)]~=nil end
function static:GetEntity(value) return f.actors[key(value)] end
function static:DespawnEntity(value)
    local k=key(value)
    f.despawns[k]=(f.despawns[k] or 0)+1
    local tokenRemoved=f.tokens[k]~=nil
    f.tokens[k]=nil -- Codeware removes the map entry, not a callback tombstone.
    local entityRemoved=f.actors[k]~=nil
    if entityRemoved then f.disposed[k]=true end -- disposal remains asynchronous.
    return tokenRemoved or entityRemoved
end
local dynamic={IsReady=function() return true end,DeleteTagged=function() end,
    GetTagged=function() return {} end,GetTaggedIDs=function() return {} end,
    IsTagged=function() return false end}
local player={IsAttached=function() return true end,GetEntityID=function() return id("player") end,
    GetWorldPosition=function() return {x=0,y=0,z=0} end,
    GetWorldOrientation=function() return {ToEulerAngles=function() return {yaw=0} end} end}
Game={
    GetStaticEntitySystem=function() return static end,GetDynamicEntitySystem=function() return dynamic end,
    FindEntityByID=function(value) return f.globals[key(value)] end,
    GetPlayer=function() return player end,
    GetSystemRequestsHandler=function() return {IsPreGame=function() return false end,IsGamePaused=function() return false end} end,
    CP2077Session_ExperimentalStaticNpcProjection=function() return true end,
    CP2077Session_SetActive=function() f.bindings={} end,CP2077Session_PushLocal=function() end,
    CP2077Session_BeginFrame=function() return 0 end,
    CP2077Session_Generation=function() return 1 end,CP2077Session_Session=function() return 1 end,
    CP2077Session_Epoch=function() return 1 end,CP2077Session_Phase=function() return 4 end,
    CP2077Session_Bind=function(session,value) f.bindings[session]=key(value);return true end,
    CP2077Session_Unbind=function(session) f.bindings[session]=nil;return true end,
    CP2077Session_Resolve=function(value)
        for session,localId in pairs(f.bindings) do if localId==key(value) then return session end end
        return "0ULL"
    end,
    CP2077Session_SelfEntity=function() return "self" end,CP2077Session_Self=function() return 2 end,
    CP2077Session_Host=function() return 1 end,CP2077Session_BubbleRadius=function() return 100 end,
    CP2077Session_NpcCapacity=function() return 128 end,CP2077Session_NpcCount=function() return 1 end,
    CP2077Session_NpcSelect=function() return true end,CP2077Session_NpcEntity=function() return "18014398509481985ULL" end,
    CP2077Session_NpcRecord=function() return 123 end,CP2077Session_NpcX=function() return 1 end,
    CP2077Session_NpcY=function() return 2 end,CP2077Session_NpcZ=function() return 3 end,
    CP2077Session_NpcYaw=function() return 0 end,
}
StaticEntitySpec={new=function() return {} end}
ResRef={FromName=function(value) return value end}
CName={new=function(value) return value end}
Vector4={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
Quaternion={new=function(i,j,k,r) return {i=i,j=j,k=k,r=r} end}
EulerAngles={new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end}
WorldTransform={new=function() return {} end,SetPosition=function() end,SetOrientationEuler=function() end}
Observe=function() end
registerForEvent=function(name,callback) events[name]=callback end
registerHotkey=function(name,_,callback) hotkeys[name]=callback end
print=function(message) f.logs[#f.logs+1]=tostring(message) end
package.loaded.npc_static_population=nil
package.loaded.config={experimentalNpcReplication=true,experimentalPassivePlayers=false}
local runtime=require("npc_runtime")
local original=runtime.new
runtime.new=function(adapter) f.controller=original(adapter);return f.controller end
assert(loadfile(root.."/runtime/session/cet/CP2077Coop/init.lua"))()
local function tick()
    events.onUpdate(1/60)
    for _,line in ipairs(f.logs) do assert(not line:find("BRIDGE_ERROR",1,true),line) end
end
events.onInit()
tick()
runtime.new=original
local sid="18014398509481985ULL"
local old="9007199254740993ULL"
assert(f.nextId==1 and f.tokens[old] and f.controller.owned[sid])
hotkeys.cp2077_session_reconnect()
assert(f.despawns[old]==nil and f.tokens[old] and f.controller.resetting,
    "reconnect must never cancel an in-flight static token")
for _=1,3 do tick() end
assert(f.nextId==1 and f.controller.owned[sid] and not f.bindings[sid])
-- External erasure cannot prove a successful callback will not arrive later.
f.tokens[old]=nil
for _=1,3 do tick() end
assert(f.nextId==1 and f.controller.owned[sid] and f.despawns[old]==nil)
f.callbacks[old]()
f.unknownFlags=true
tick()
assert(f.nextId==1 and f.despawns[old]==nil and f.controller.owned[sid])
f.unknownFlags=false
tick()
local oldActor=f.actors[old]
assert(f.disposed[old] and f.despawns[old]==1 and not f.bindings[sid],
    "late completed actor must retire under original owner without binding")
-- Creator registry loses visibility first; global and retained handle stay live.
f.actors[old]=nil
tick()
assert(f.nextId==1 and f.controller.owned[sid] and f.despawns[old]==1)
f.globals[old]=nil
tick()
assert(f.nextId==1 and oldActor.attached and f.controller.owned[sid],
    "empty lookups must not erase the exact retained attached handle")
oldActor.attached=false
tick()
local replacement="9007199254740994ULL"
assert(f.nextId==2 and key(f.controller.owned[sid].localId)==replacement,
    "observed retirement should recover with one new exact projection")
f.callbacks[replacement]()
tick()
assert(f.bindings[sid]==replacement and f.despawns[old]==1 and f.actors[old]==nil)
local count=0;for _ in pairs(f.actors) do count=count+1 end
assert(count==1 and f.actors[replacement].attached,
    "late callback/reconnect must not leave a duplicate actor")
print=report
report("Real entrypoint static pending reconnect, late callback retirement and single replacement passed")
end
