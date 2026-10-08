-- Opt-in cosmetic players, using the original render-only StaticEntitySystem asset.
-- No NPC target tag, collider, AI, combat or appearance promise. Game-thread only.
local M = {}
M.tag = "CP2077Session.PassivePlayer"
M.template = "base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent"
local function key(value)
    local ok, hash = pcall(function() return value.hash end)
    return tostring(ok and hash ~= nil and hash or value):gsub("[uUlL]+$", "")
end
local function validId(value)
    if value == nil or type(value) == "number" then return false end
    local id = key(value)
    return id:match("^[1-9][0-9]*$") and #id <= 20
        and (#id < 20 or id <= "18446744073709551615")
end
local function system()
    local ok, value = pcall(function() return Game.GetStaticEntitySystem() end)
    if not ok or value == nil then return nil end
    local ready, result = pcall(function() return value:IsReady() end)
    return ready and result and value or nil
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
local function gone(s, entry)
    return not s:IsManaged(entry.id) and not s:IsSpawning(entry.id)
        and not s:IsSpawned(entry.id) and s:GetEntity(entry.id) == nil
end
local Controller = {}
Controller.__index = Controller
function M.new(log)
    return setmetatable({owned = {}, retryAfter = {}, scope = nil, resetting = false, log = log}, Controller)
end
function Controller:status(reason)
    if self.lastStatus ~= reason then
        self.lastStatus = reason
        if self.log then self.log(reason) end
    end
end
function Controller:retire(player, entry)
    entry.retiring = true
    -- Missing native mappings are already unbound after BeginFrame/SetActive.
    -- A different exact mapping is never ours to remove.
    if entry.bound then
        local ok, resolved = pcall(function() return Game.CP2077Session_Resolve(entry.id) end)
        if not ok or resolved == nil then return false end
        if key(resolved) == entry.session then
            local unbound, accepted = pcall(function() return Game.CP2077Session_Unbind(entry.entity) end)
            if not unbound or not accepted then return false end
        elseif key(resolved) ~= "0" then return false end
        entry.bound, entry.actor = false, nil
    end
    if entry.id ~= nil then
        local s = system()
        if s == nil then return false end
        local observed, absent = pcall(gone, s, entry)
        if not observed then return false end
        if not absent and not entry.removing then
            local ok, accepted = pcall(function() return s:DespawnEntity(entry.id) end)
            if not ok or not accepted then return false end
            entry.removing = true
        end
        observed, absent = pcall(gone, s, entry)
        if not observed or not absent then return false end
    end
    self.owned[player] = nil
    return true
end
function Controller:pump()
    local complete = true
    for player, entry in pairs(self.owned) do
        if entry.retiring and not self:retire(player, entry) then complete = false end
    end
    if self.resetting and next(self.owned) == nil then
        self.scope, self.resetting = nil, false
        self.retryAfter = {}
    end
    return complete
end
function Controller:reset()
    self.resetting = true
    for _, entry in pairs(self.owned) do entry.retiring = true end
    return self:pump()
end
function Controller:spawn(s, entry, pose, now)
    if now < (self.retryAfter[pose.player] or 0) then return false end
    -- A failed asynchronous token may retire immediately. Keep the retry gate
    -- independently until this player leaves, or the entire scope is retired.
    self.retryAfter[pose.player] = now + 1
    local ok, id = pcall(function()
        local spec = StaticEntitySpec.new()
        spec.templatePath = ResRef.FromName(M.template)
        spec.position = Vector4.new(pose.x, pose.y, pose.z, 1.0)
        spec.orientation = Quaternion.new(0.0, 0.0, math.sin(pose.yaw * 0.5), math.cos(pose.yaw * 0.5))
        spec.attached = true
        spec.tags = {CName.new(M.tag), CName.new(M.tag .. "." .. tostring(pose.player))}
        return s:SpawnEntity(spec)
    end)
    if not ok or id == nil or not validId(id) then return false end
    entry.id = id -- retain the exact token even while creation is pending
    return true
end
function Controller:place(s, entry, pose)
    local ok, actor, pending = pcall(function()
        return s:GetEntity(entry.id), s:IsManaged(entry.id) or s:IsSpawning(entry.id) or s:IsSpawned(entry.id)
    end)
    if not ok then return false, "observation_unavailable" end
    if actor == nil then
        if pending then return false, "spawn_pending" end
        return false, "spawn_disappeared", true
    end
    local read, exact, attached = pcall(function()
        return key(actor:GetEntityID()) == key(entry.id), actor:IsAttached()
    end)
    if not read then return false, "observation_unavailable" end
    if not exact then return false, "actor_identity_changed", true end
    if not attached then return false, "attachment_pending" end
    if not entry.bound then
        local accepted, bound = pcall(function() return Game.CP2077Session_Bind(entry.entity, actor:GetEntityID()) end)
        if not accepted or not bound then return false, "binding_rejected", true end
        entry.bound = true
    end
    local resolved, current = pcall(function() return Game.CP2077Session_Resolve(entry.id) end)
    if not resolved or current == nil or key(current) ~= entry.session then
        return false, "binding_changed", true
    end
    entry.actor = actor
    local moved = pcall(function()
        local world = WorldTransform.new()
        WorldTransform.SetPosition(world, Vector4.new(pose.x, pose.y, pose.z, 1.0))
        WorldTransform.SetOrientationEuler(world, EulerAngles.new(0.0, 0.0, math.deg(pose.yaw)))
        actor:SetWorldTransform(world)
    end)
    -- SetWorldTransform returning is not proof of placement. The live fixture
    -- separately compares actual position with the native interpolated sample.
    return moved, moved and "transform_submitted" or "transform_rejected", not moved
end
function Controller:step(scope, players, now)
    assert(type(scope) == "string" and scope ~= "" and finite(now), "invalid passive player scope/time")
    assert(type(players) == "table" and #players <= 256, "invalid passive player count")
    local desired, sessions = {}, {}
    for _, pose in ipairs(players) do
        local player = pose.player
        assert(finite(player) and player >= 1 and player <= 4294967295 and player % 1 == 0,
            "invalid passive PlayerId")
        assert(validId(pose.entity), "invalid passive SessionEntityId")
        assert(finite(pose.x) and finite(pose.y) and finite(pose.z) and finite(pose.yaw), "invalid passive pose")
        local sid = key(pose.entity)
        assert(not desired[player] and not sessions[sid], "duplicate passive player identity")
        desired[player], sessions[sid] = pose, true
    end
    if self.scope ~= nil and self.scope ~= scope then self:reset() end
    if self.resetting then
        self:pump()
        if self.resetting then self:status("scope_retirement_pending"); return false end
    end
    self.scope = scope
    for player, entry in pairs(self.owned) do
        if not desired[player] or entry.session ~= key(desired[player].entity) then entry.retiring = true end
    end
    local clean = self:pump()
    for player in pairs(self.retryAfter) do
        if not desired[player] and not self.owned[player] then self.retryAfter[player] = nil end
    end
    -- Do not replace any identity while a prior actor still exists. This also
    -- covers a session entity moving to another player entry in a bad snapshot.
    if not clean then self:status("retirement_pending"); return false end
    local s = system()
    if s == nil then self:status("static_system_unavailable"); return false end
    local complete, reason = clean, clean and "transform_submitted" or "retirement_pending"
    for player, pose in pairs(desired) do
        local entry = self.owned[player]
        if entry == nil then
            entry = {entity = pose.entity, session = key(pose.entity)}
            self.owned[player] = entry
        end
        if entry.retiring then complete, reason = false, "retirement_pending"
        else
            if entry.id == nil and not self:spawn(s, entry, pose, now) then complete, reason = false, "spawn_retry" end
            if entry.id ~= nil then
                local placed, why, retire = self:place(s, entry, pose)
                if not placed then complete, reason = false, why end
                if retire then self:retire(player, entry) end
            end
        end
    end
    self:status(reason)
    return complete
end
function Controller:boundIds()
    local ids = {}
    for _, entry in pairs(self.owned) do
        if entry.bound and not entry.retiring then ids[#ids + 1] = entry.id end
    end
    return ids
end
return M
