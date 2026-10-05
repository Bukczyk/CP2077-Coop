-- Game-thread-only NPC projection adapter. It owns only entities created below.
-- Codeware DynamicEntitySystem signatures are matched to the installed Codeware source.
local M = {}
local commonTag = "CP2077Coop.NetworkNpc"
local bySessionEntity, byLocalEntity = {}, {}
local function key(value) return tostring(value) end
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
    local x, y, z, yaw = tonumber(npc.x), tonumber(npc.y), tonumber(npc.z), tonumber(npc.yaw)
    if not x or not y or not z or not yaw or x ~= x or y ~= y or z ~= z or yaw ~= yaw then return nil end
    local ok, id = pcall(function()
        local tag = CName.new(commonTag .. "." .. sid)
        local spec = DynamicEntitySpec.new()
        spec.recordID = record
        spec.position = Vector4.new(x, y, z, 1.0)
        spec.orientation = Quaternion.new(0.0, 0.0, 0.0, 1.0)
        spec.persistState = false
        spec.persistSpawn = false
        spec.alwaysSpawned = true
        spec.spawnInView = true
        spec.active = true
        spec.tags = { CName.new(commonTag), tag }
        return s:CreateEntity(spec)
    end)
    if not ok or id == nil or key(id) == "0" then return nil end
    local entry = { id = id, session = sid, entity = nil, bound = false }
    bySessionEntity[sid], byLocalEntity[key(id)] = entry, entry
    return id
end
function M.bind(sessionEntity, localId)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil or key(entry.id) ~= key(localId) then return false end
    if entry.bound then return true end
    local s = system()
    if s == nil then return false end
    local ok, entity, spawning, spawned = pcall(function()
        local value = s:GetEntity(entry.id)
        return value, s:IsSpawning(entry.id), s:IsSpawned(entry.id)
    end)
    if not ok then return false end
    if entity == nil then
        -- CreateEntity returns its exact EntityID before asynchronous streaming finishes.
        if spawning or not spawned then return nil, "pending" end
        return false
    end
    local readOk, actual = pcall(function() return entity:GetEntityID() end)
    if not readOk or key(actual) ~= key(entry.id) then return false end
    local ok, bound = pcall(function() return Game.CP2077Session_Bind(sessionEntity, actual) end)
    if not ok or not bound then return false end
    entry.entity, entry.bound = entity, true
    return true
end
function M.move(localId, npc)
    local entry = byLocalEntity[key(localId)]
    if entry == nil or not entry.bound or entry.entity == nil then return false end
    local x, y, z, yaw = tonumber(npc.x), tonumber(npc.y), tonumber(npc.z), tonumber(npc.yaw)
    if not x or not y or not z or not yaw or x ~= x or y ~= y or z ~= z or yaw ~= yaw then return false end
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
    local s = system()
    if s == nil then return false end
    local ok, removed = pcall(function() return s:DeleteEntity(entry.id) end)
    if not ok or not removed then return false end
    byLocalEntity[key(entry.id)] = nil
    if bySessionEntity[entry.session] == entry then bySessionEntity[entry.session] = nil end
    return true
end
function M.unbind(sessionEntity)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil then return true end
    if entry.bound then
        local ok, unbound = pcall(function() return Game.CP2077Session_Unbind(sessionEntity) end)
        if not ok or not unbound then return false end
    end
    entry.bound, entry.entity = false, nil
    return true
end
return M
