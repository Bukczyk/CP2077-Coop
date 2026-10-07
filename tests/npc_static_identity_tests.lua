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
    function system:IsReady() return true end
    function system:SpawnEntity(spec)
        f.spawnCalls = f.spawnCalls + 1
        local hash = assert(hashes[f.spawnCalls], "unexpected duplicate spawn")
        local entry = {hash = hash, managed = true, spawning = false,
            spawned = true, visibleHandle = true, spec = spec}
        entry.actor = {
            GetEntityID = function() return entityId(entry.actualHash or hash) end,
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
        GetStaticEntitySystem = function() return system end,
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
    assert(a.remove(entityId(hash)) and f.despawnCalls == 3)
    assert(a.remove(entityId(hash)) and f.despawnCalls == 3)
    assert(a.spawn(source) ~= id and f.spawnCalls == 2,
        "confirmed removal must release the session mapping for later recreation")
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
    entry.managed = false -- failed/aborted callback retired the token
    assert(a.bind(source.entity, id) == false, "a cancelled creation must not wait forever")
    f.despawnMode = "error"
    assert(a.remove(id) and f.despawnCalls == 0,
        "an already-absent creation must retire without another despawn")
    assert(a.spawn(source) ~= id and f.spawnCalls == 2)
end

do
    local hash = "9007199254740993ULL"
    local f = fixture({hash})
    local a, source = f.adapter, npc("18014398509481985ULL")
    local id = assert(a.spawn(source))
    assert(a.bind(source.entity, id))
    f.mapped = {} -- registry and engine were cleared before Lua cleanup
    local entry = f.entries[hash]
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle = false, false, false, false
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
    entry.managed, entry.spawning, entry.spawned, entry.visibleHandle = false, false, false, false
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

for _, zero in ipairs({"0", "0ULL", "0ull"}) do
    local f = fixture({zero, "9007199254740993ULL"})
    assert(f.adapter.spawn(npc("zero-return")) == nil, "zero EntityID hash was accepted")
    assert(f.bindCalls == 0)
    assert(f.adapter.spawn(npc("zero-return")) ~= nil and f.spawnCalls == 2,
        "a rejected zero identity must not reserve the session mapping")
end

print("Static projection opaque EntityID wrappers, exact binding, finite transforms and observed despawn passed")
