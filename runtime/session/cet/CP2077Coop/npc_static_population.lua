-- Experimental render-only NPC projection using the verified custom entEntity template.
-- Game-thread only; owns and deletes only EntityIDs returned by StaticEntitySystem.
local M = {}
local assetPath = "base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent"
local commonTag = "CP2077Coop.ExperimentalStaticNpc"
local bySessionEntity, byLocalEntity = {}, {}
local function key(value)
    -- CET creates new EntityID wrappers. Only their opaque Uint64 hash is identity.
    local ok, hash = pcall(function() return value.hash end)
    return tostring(ok and hash ~= nil and hash or value)
end
local function system()
    if Game == nil or Game.GetStaticEntitySystem == nil then return nil end
    local ok, result = pcall(function()
        local value = Game.GetStaticEntitySystem()
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
    return system() ~= nil, "Codeware StaticEntitySystem is unavailable"
end
function M.spawn(npc)
    local s = system()
    if s == nil or npc == nil or npc.entity == nil then return nil end
    local sid = key(npc.entity)
    if bySessionEntity[sid] then return bySessionEntity[sid].id end
    local x, y, z, yaw = transform(npc)
    if not x then return nil end
    local ok, id = pcall(function()
        local spec = StaticEntitySpec.new()
        spec.templatePath = ResRef.FromName(assetPath)
        spec.position = Vector4.new(x, y, z, 1.0)
        spec.orientation = Quaternion.new(0.0, 0.0, math.sin(yaw * 0.5), math.cos(yaw * 0.5))
        spec.attached = true
        local tag = CName.new(commonTag .. "." .. sid)
        spec.tags = { CName.new(commonTag), tag }
        return s:SpawnEntity(spec)
    end)
    if not ok or id == nil or key(id):match("^0[uUlL]*$") then return nil end
    local entry = { id = id, session = sid, entity = nil, bound = false }
    bySessionEntity[sid], byLocalEntity[key(id)] = entry, entry
    return id
end
function M.bind(sessionEntity, localId)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil or key(entry.id) ~= key(localId) then return false end
    -- Codeware can still return a handle after accepting asynchronous despawn.
    -- Its existence is not permission to revive or drive a retiring entity.
    if entry.removing then return false, "removing" end
    if entry.bound then return true end
    local s = system()
    if s == nil then return false end
    local ok, entity, spawning, spawned, managed = pcall(function()
        return s:GetEntity(entry.id), s:IsSpawning(entry.id), s:IsSpawned(entry.id), s:IsManaged(entry.id)
    end)
    if not ok then return false end
    if entity == nil then
        -- Codeware removes failed/aborted spawn tokens. Only an actual managed
        -- or in-flight entity is pending; an absent ID cannot complete later.
        -- Reads can straddle the asynchronous token-to-entity transition.
        if managed or spawning or spawned then return nil, "pending" end
        return false
    end
    local readOk, actual = pcall(function() return entity:GetEntityID() end)
    if not readOk or key(actual) ~= key(entry.id) then return false end
    local boundOk, bound = pcall(function() return Game.CP2077Session_Bind(sessionEntity, actual) end)
    if not boundOk or not bound then return false end
    entry.entity, entry.bound = entity, true
    return true
end
function M.move(localId, npc)
    local entry = byLocalEntity[key(localId)]
    if entry == nil or entry.removing or not entry.bound or entry.entity == nil then return false end
    local x, y, z, yaw = transform(npc)
    if not x then return false end
    local ok = pcall(function()
        if key(entry.entity:GetEntityID()) ~= key(entry.id) then error("projection handle changed") end
        local world = WorldTransform.new()
        WorldTransform.SetPosition(world, Vector4.new(x, y, z, 1.0))
        WorldTransform.SetOrientationEuler(world, EulerAngles.new(0.0, 0.0, math.deg(yaw)))
        entry.entity:SetWorldTransform(world)
    end)
    return ok
end
function M.remove(localId)
    local entry = byLocalEntity[key(localId)]
    if entry == nil then return true end
    if entry.bound then return false end
    local s = system()
    if s == nil then return false end
    local function isGone()
        return not s:IsManaged(entry.id) and not s:IsSpawning(entry.id)
            and not s:IsSpawned(entry.id) and s:GetEntity(entry.id) == nil
    end
    -- Failed creation, a world reset or another completed removal may already
    -- have retired the owned ID. DespawnEntity then legitimately returns false.
    local observed, gone = pcall(isGone)
    if not observed then return false end
    if not gone then
        if not entry.removing then
            local ok, removed = pcall(function() return s:DespawnEntity(entry.id) end)
            if not ok or not removed then return false end
            entry.removing = true
        end
        -- A queued despawn is not observed disappearance. Retain ownership for retry.
        observed, gone = pcall(isGone)
    end
    if not observed or not gone then return false end
    byLocalEntity[key(entry.id)] = nil
    if bySessionEntity[entry.session] == entry then bySessionEntity[entry.session] = nil end
    return true
end
function M.unbind(sessionEntity)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil then return true end
    if entry.bound then
        -- BeginFrame and SetActive(false) can retire the native mapping before
        -- Lua observes catalog removal or a new generation. Missing is already
        -- unbound; a different exact mapping must never be removed on our behalf.
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
