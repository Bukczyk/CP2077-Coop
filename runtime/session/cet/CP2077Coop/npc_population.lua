-- Game-thread-only NPC projection adapter. It owns only entities created below.
-- Codeware DynamicEntitySystem signatures are matched to the installed Codeware source.
local M = {}
local commonTag = "CP2077Coop.NetworkNpc"
local bySessionEntity, byLocalEntity = {}, {}
local clock, age, wasPaused, paused = nil, 0, true, true
local QUIET_PERIOD, RETRY_DELAY, MAX_DELETE_ATTEMPTS = 0.25, 0.5, 3
local function key(value)
    -- CET may return a fresh EntityID wrapper on each lookup. The opaque hash,
    -- not wrapper text or a Lua number, identifies the owned entity.
    local ok, hash = pcall(function() return value.hash end)
    return tostring(ok and hash ~= nil and hash or value)
end
local function clearObservations(entry)
    entry.stable, entry.stableAt, entry.absentSince = 0, nil, nil
end
-- One caller-owned game update timestamp, shared by reset/step in that frame.
-- Paused or unknown pause state never advances attachment/absence qualification.
function M.observe(now, isPaused)
    if type(now) ~= "number" or now ~= now or math.abs(now) == math.huge
        or now < 0 or (clock and now < clock) or type(isPaused) ~= "boolean" then
        paused, wasPaused = true, true
        for _, entry in pairs(byLocalEntity) do clearObservations(entry) end
        return false
    end
    if clock and not isPaused and not wasPaused then age = age + now - clock end
    clock, paused, wasPaused = now, isPaused, isPaused
    if paused then for _, entry in pairs(byLocalEntity) do clearObservations(entry) end end
    return true
end
local function system()
    if Game == nil or Game.GetDynamicEntitySystem == nil then return nil end
    local ok, result = pcall(function()
        local value = Game.GetDynamicEntitySystem()
        if value == nil or not value:IsReady() then return nil end
        return value
    end)
    if not ok or result == nil then return nil end
    return result
end
local function transform(npc)
    local x, y, z, yaw = tonumber(npc.x), tonumber(npc.y), tonumber(npc.z), tonumber(npc.yaw)
    for _, value in ipairs({x or false, y or false, z or false, yaw or false}) do
        if not value or value ~= value or math.abs(value) == math.huge then return nil end
    end
    return x, y, z, yaw
end
function M.available()
    return system() ~= nil, "Codeware DynamicEntitySystem is unavailable"
end
function M.spawn(npc)
    local s = system()
    if s == nil or npc == nil or npc.entity == nil or npc.record == nil then return nil end
    local sid = key(npc.entity)
    if bySessionEntity[sid] then return bySessionEntity[sid].id end
    local record = npc.record
    local okRecord, exists = pcall(function() return TweakDB:GetRecord(record) end)
    if not okRecord or exists == nil then return nil end
    local x, y, z, yaw = transform(npc)
    if not x then return nil end
    local ok, id = pcall(function()
        local tag = CName.new(commonTag .. "." .. sid)
        local spec = DynamicEntitySpec.new()
        spec.recordID = record
        spec.position = Vector4.new(x, y, z, 1.0)
        spec.orientation = Quaternion.new(0.0, 0.0, math.sin(yaw * 0.5), math.cos(yaw * 0.5))
        spec.persistState = false
        spec.persistSpawn = false
        spec.alwaysSpawned = true
        spec.spawnInView = true
        spec.active = true
        spec.tags = { CName.new(commonTag), tag }
        return s:CreateEntity(spec)
    end)
    if not ok or id == nil or key(id):match("^0[uUlL]*$") then return nil end
    local entry = { id = id, session = sid, entity = nil, bound = false }
    bySessionEntity[sid], byLocalEntity[key(id)] = entry, entry
    return id
end
function M.bind(sessionEntity, localId)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil or key(entry.id) ~= key(localId) then return false end
    if entry.retiring then return false, "retiring" end
    if entry.bound then return true end
    local s = system()
    if s == nil then return false end
    local ok, entity, spawning, spawned, managed = pcall(function()
        local value = s:GetEntity(entry.id)
        return value, s:IsSpawning(entry.id), s:IsSpawned(entry.id), s:IsManaged(entry.id)
    end)
    if not ok then return false end
    if entity == nil then
        -- A failed creation loses its managed token. Do not wait forever for
        -- an absent token; keep real streaming/state transitions pending.
        if managed or spawning or spawned then return nil, "pending" end
        return false
    end
    local readOk, actual = pcall(function() return entity:GetEntityID() end)
    if not readOk or key(actual) ~= key(entry.id) then return false end
    local ok, bound = pcall(function() return Game.CP2077Session_Bind(sessionEntity, actual) end)
    if not ok or not bound then return false end
    entry.entity, entry.bound, entry.retainedActor = entity, true, entity
    return true
end
function M.move(localId, npc)
    local entry = byLocalEntity[key(localId)]
    if entry == nil or entry.retiring or not entry.bound or entry.entity == nil then return false end
    local x, y, z, yaw = transform(npc)
    if not x then return false end
    -- This exact game API is already used by the matched remote-player bridge.
    local ok = pcall(function()
        local entity = entry.entity
        if key(entity:GetEntityID()) ~= key(entry.id) then error("projection handle changed") end
        Game.GetTeleportationFacility():Teleport(entity, Vector4.new(x, y, z, 1.0), EulerAngles.new(0.0, 0.0, math.deg(yaw)))
    end)
    return ok
end

function M.remove(localId)
    local entry = byLocalEntity[key(localId)]
    if entry == nil then return true end
    entry.retiring = true
    if entry.bound then return false end
    if clock == nil or paused then clearObservations(entry); return false, "observation_paused" end
    local s = system()
    if s == nil then clearObservations(entry); return false, "manager_unavailable" end
    local function observe()
        local actor, populationActor = Game.FindEntityByID(entry.id), s:GetEntity(entry.id)
        for _, candidate in pairs({actor=actor,populationActor=populationActor,retained=entry.retainedActor}) do
            if key(candidate:GetEntityID()) ~= key(entry.id) then error("owned actor identity changed") end
        end
        entry.retainedActor = actor or populationActor or entry.retainedActor
        local attached = actor ~= nil and actor:IsAttached()
        local retainedAttached = entry.retainedActor ~= nil and entry.retainedActor:IsAttached()
        local managed, spawning, spawned = s:IsManaged(entry.id), s:IsSpawning(entry.id), s:IsSpawned(entry.id)
        if type(attached) ~= "boolean" or type(retainedAttached) ~= "boolean"
            or type(managed) ~= "boolean" or type(spawning) ~= "boolean"
            or type(spawned) ~= "boolean" then error("invalid lifetime observation") end
        return {actor=actor,populationActor=populationActor,attached=attached,retainedAttached=retainedAttached,
            managed=managed,spawning=spawning,spawned=spawned}
    end
    local observed, o = pcall(observe)
    if not observed then clearObservations(entry); return false, "observation_error" end
    if entry.removing then
        local absent = o.actor == nil and o.populationActor == nil and not o.retainedAttached
            and not o.managed and not o.spawning and not o.spawned
        if not absent then entry.absentSince=nil; return false, "despawn_pending" end
        entry.absentSince = entry.absentSince or age
        if age - entry.absentSince < QUIET_PERIOD then return false, "absence_observation_pending" end
    else
        -- Codeware's pending CreateStub callback may still produce an actor
        -- after an early DeleteEntity forgets its token. Absence alone cannot
        -- retire a never-attached token, even when IsManaged/IsSpawning are false.
        if not (o.attached and o.managed and o.spawned and not o.spawning) then
            clearObservations(entry)
            return false, o.managed and "spawn_pending" or "ownership_unconfirmed"
        end
        if entry.stableAt ~= clock then entry.stable=(entry.stable or 0)+1; entry.stableAt=clock end
        if entry.stable < 2 then return false, "attachment_observation_pending" end
        if (entry.deleteAttempts or 0) >= MAX_DELETE_ATTEMPTS then return false, "delete_unconfirmed" end
        if entry.nextDelete and age < entry.nextDelete then return false, "delete_retry_pending" end
        entry.deleteAttempts,entry.nextDelete = (entry.deleteAttempts or 0)+1,age+RETRY_DELAY
        local ok, removed = pcall(function() return s:DeleteEntity(entry.id) end)
        if not ok or removed ~= true then return false, "delete_unconfirmed" end
        entry.removing,entry.absentSince = true,nil
        return false, "delete_submitted"
    end
    byLocalEntity[key(entry.id)] = nil
    if bySessionEntity[entry.session] == entry then bySessionEntity[entry.session] = nil end
    return true
end
function M.unbind(sessionEntity)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil then return true end
    if entry.bound then
        -- The native frame may already have removed this binding. A missing
        -- mapping is unbound; never remove a different entity's mapping.
        local resolvedOk, resolved = pcall(function() return Game.CP2077Session_Resolve(entry.id) end)
        if not resolvedOk or resolved == nil then return false end
        local resolvedKey = key(resolved)
        if resolvedKey == key(sessionEntity) then
            local ok, unbound = pcall(function() return Game.CP2077Session_Unbind(sessionEntity) end)
            if not ok or not unbound then return false end
        elseif not resolvedKey:match("^0[uUlL]*$") then
            return false
        end
    end
    entry.bound, entry.entity = false, nil
    return true
end
return M
