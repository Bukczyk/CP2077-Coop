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
        if value == nil or value:IsReady() ~= true then return nil end
        return value
    end)
    if not ok or result == nil then return nil end
    return result
end
local function liveReference(entity)
    if entity == nil then return nil end
    -- An expired CET weak wrapper is still non-nil. Only a positive native
    -- expiry observation establishes absence; errors/unknown remain pending.
    if type(IsDefined) == "function" then
        local defined = IsDefined(entity)
        if type(defined) ~= "boolean" then error("invalid static reference observation") end
        if not defined then return nil end
    end
    return entity
end
local function observe(entry)
    -- Retain the creator itself. A replacement returned by Game cannot prove
    -- absence, and CET is not required to return the same Lua wrapper each time.
    local s = entry.creator
    local ok, result = pcall(function()
        if s == nil or s:IsReady() ~= true then return nil end
        local managed, spawning, spawned = s:IsManaged(entry.id), s:IsSpawning(entry.id), s:IsSpawned(entry.id)
        if type(managed) ~= "boolean" or type(spawning) ~= "boolean"
            or type(spawned) ~= "boolean" then error("invalid static lifetime observation") end
        local function attachment(entity)
            if entity == nil then return false end
            if key(entity:GetEntityID()) ~= key(entry.id) then error("static projection identity changed") end
            local attached = entity:IsAttached()
            if type(attached) ~= "boolean" then error("invalid static attachment observation") end
            return attached
        end
        local entity = liveReference(s:GetEntity(entry.id))
        local attached = attachment(entity)
        -- Never overwrite the first exact handle with a detached replacement.
        -- Both it and the global registry can outlive creator-map visibility.
        if entry.retained == nil and entity ~= nil then entry.retained = entity end
        local retainedAttached = attachment(liveReference(entry.retained))
        local globalEntity = liveReference(Game.FindEntityByID(entry.id))
        local globalAttached = attachment(globalEntity)
        if entity ~= nil and attached and managed and spawned and not spawning then
            entry.completed = true
        end
        return {system=s,entity=entity,attached=attached,retainedAttached=retainedAttached,
            globalEntity=globalEntity,globalAttached=globalAttached,
            managed=managed,spawning=spawning,spawned=spawned}
    end)
    return ok and result or nil
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
    local entry = { id = id, session = sid, creator = s, entity = nil, bound = false, completed = false }
    bySessionEntity[sid], byLocalEntity[key(id)] = entry, entry
    return id
end
function M.bind(sessionEntity, localId)
    local entry = bySessionEntity[key(sessionEntity)]
    if entry == nil or key(entry.id) ~= key(localId) then return false end
    -- Codeware can still return a handle after accepting asynchronous despawn.
    -- Its existence is not permission to revive or drive a retiring entity.
    if entry.retiring then return false, "removing" end
    if entry.bound then return true end
    local o = observe(entry)
    if o == nil then return false end
    -- Codeware v1.18.0 can erase a pending token while its successful callback
    -- remains able to insert the actor. Never interpret that gap as final loss.
    if not (o.entity ~= nil and o.attached and o.managed and o.spawned and not o.spawning) then
        return nil, "pending"
    end
    local boundOk, bound = pcall(function() return Game.CP2077Session_Bind(sessionEntity, entry.id) end)
    if not boundOk or bound ~= true then return false end
    entry.entity, entry.bound = o.entity, true
    return true
end
function M.move(localId, npc)
    local entry = byLocalEntity[key(localId)]
    if entry == nil or entry.retiring or not entry.bound or entry.entity == nil then return false end
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
    entry.retiring = true
    local function isGone(o)
        return o ~= nil and entry.completed and not o.managed and not o.spawning
            and not o.spawned and not o.attached and not o.globalAttached and not o.retainedAttached
    end
    local o = observe(entry)
    if o == nil then return false end
    -- Never cancel a pending StaticEntitySystem token. Its successful callback
    -- inserts the actor without checking token membership. Even all-false maps
    -- cannot release a never-completed creation; keep its owner for late recovery.
    if not entry.completed then return false end
    if not isGone(o) then
        if not entry.removing then
            if not (o.entity ~= nil and o.attached and o.managed and o.spawned and not o.spawning) then return false end
            local ok, removed = pcall(function() return o.system:DespawnEntity(entry.id) end)
            if not ok or removed ~= true then return false end
            entry.removing = true
        end
        -- A queued despawn is not observed disappearance. Retain ownership for retry.
        o = observe(entry)
    end
    if not isGone(o) then return false end
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
            if not ok or unbound ~= true then return false end
        elseif not resolvedKey:match("^0[uUlL]*$") then
            return false
        end
    end
    entry.bound, entry.entity = false, nil
    return true
end
return M
