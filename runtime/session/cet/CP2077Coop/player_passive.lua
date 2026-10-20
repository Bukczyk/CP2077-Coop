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
    return ready and result == true and value or nil
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
local function liveReference(actor)
    if actor == nil then return nil end
    -- CET can return a non-nil WeakReference after its native object expired.
    -- A positive native expiry observation is absence; an error/unknown result
    -- remains unqualified. Lua truthiness alone cannot observe engine lifetime.
    if type(IsDefined) == "function" then
        local defined = IsDefined(actor)
        if type(defined) ~= "boolean" then error("invalid_static_reference_observation") end
        if not defined then return nil end
    end
    return actor
end
local function observe(entry)
    -- Keep the creator system and exact observed actor through unbind and
    -- world transitions. A fresh global system must not inherit an old token.
    local s = entry.system
    if s == nil or s:IsReady() ~= true then return nil end
    local managed, spawning, spawned = s:IsManaged(entry.id), s:IsSpawning(entry.id), s:IsSpawned(entry.id)
    if type(managed) ~= "boolean" or type(spawning) ~= "boolean" or type(spawned) ~= "boolean" then
        error("invalid_static_lifecycle")
    end
    local actor, globalActor = liveReference(s:GetEntity(entry.id)), liveReference(Game.FindEntityByID(entry.id))
    local function attachment(candidate)
        if candidate == nil then return false end
        if key(candidate:GetEntityID()) ~= key(entry.id) then error("static_actor_identity_changed") end
        local attached = candidate:IsAttached()
        if type(attached) ~= "boolean" then error("invalid_static_attachment") end
        return attached
    end
    local attached, globalAttached = attachment(actor), attachment(globalActor)
    -- Never replace a retained exact handle just because a lookup disappeared.
    if entry.actor == nil then entry.actor = actor or globalActor end
    local retainedAttached = attachment(liveReference(entry.actor))
    -- A global handle may appear before the creator has finished registration.
    -- Only a completed exact creator-owned spawn can qualify later absence.
    if attached and managed and spawned and not spawning then entry.seenReady = true end
    return {system=s, actor=actor, globalActor=globalActor, attached=attached,
        managed=managed, spawning=spawning, spawned=spawned,
        -- Retained native references keep a detached object alive and therefore
        -- FindEntityByID may continue returning it. Require observed removal
        -- from the creator AND false attachment on every exact handle, rather
        -- than waiting for our own retained reference to destroy itself.
        absent=not managed and not spawning and not spawned
            and not attached and not globalAttached and not retainedAttached}
end
local Controller = {}
Controller.__index = Controller
function M.new(log, locomotion, actions, directionalWalk)
    return setmetatable({owned = {}, retryAfter = {}, scope = nil, resetting = false, log = log,
        locomotion = locomotion and require("player_locomotion") or nil, actions=actions,
        directionalWalk=directionalWalk==true and actions~=nil}, Controller)
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
            if not unbound or accepted ~= true then return false end
        elseif key(resolved) ~= "0" then return false end
        entry.bound = false
    end
    if entry.id ~= nil then
        local observed, state = pcall(observe, entry)
        if not observed or state == nil then return false end
        if not state.absent and not entry.removing then
            -- Codeware's successful static spawn callback inserts the actor
            -- without checking whether DespawnEntity erased its pending token.
            -- Do not infer cancellation from a never-attached token's absence.
            if not state.actor or not state.attached or not state.managed
                or state.spawning or not state.spawned then return false end
            local ok, accepted = pcall(function() return state.system:DespawnEntity(entry.id) end)
            if not ok or accepted ~= true then return false end
            entry.removing = true
        end
        observed, state = pcall(observe, entry)
        if not observed or state == nil or not state.absent or not entry.seenReady then return false end
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
    -- Keep the retry gate independently until this player leaves or the entire
    -- scope is retired. Unconfirmed asynchronous creation retains its token.
    self.retryAfter[pose.player] = now + 1
    entry.system = s
    local ok, id = pcall(function()
        local spec = StaticEntitySpec.new()
        spec.templatePath = ResRef.FromName(self.actions and self.actions.available() and self.actions.template
            or self.locomotion and self.locomotion.template or M.template)
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
function Controller:place(entry, pose, now)
    local ok, state = pcall(observe, entry)
    if not ok or state == nil then return false, "observation_unavailable" end
    local actor = state.actor
    if actor == nil then
        if state.absent and entry.seenReady then return false, "actor_disappeared", true end
        return false, "spawn_unconfirmed"
    end
    if not state.managed or state.spawning or not state.spawned then return false, "spawn_pending" end
    if not state.attached then return false, "attachment_pending" end
    if not entry.bound then
        local accepted, bound = pcall(function() return Game.CP2077Session_Bind(entry.entity, actor:GetEntityID()) end)
        if not accepted or bound ~= true then return false, "binding_rejected", true end
        entry.bound = true
    end
    local resolved, current = pcall(function() return Game.CP2077Session_Resolve(entry.id) end)
    if not resolved or current == nil or key(current) ~= entry.session then
        return false, "binding_changed", true
    end
    local moved = pcall(function()
        local world = WorldTransform.new()
        WorldTransform.SetPosition(world, Vector4.new(pose.x, pose.y, pose.z, 1.0))
        WorldTransform.SetOrientationEuler(world, EulerAngles.new(0.0, 0.0,
            math.deg(pose.yaw+(self.locomotion and self.locomotion.yawOffset or 0))))
        actor:SetWorldTransform(world)
        entry.target = pose
        if self.locomotion then
            entry.presentation = entry.presentation or self.locomotion.new(self.directionalWalk,
                self.actions and self.actions.available())
            self.locomotion.step(entry.presentation, pose, now)
            self.locomotion.apply(actor, entry.presentation)
        end
        if self.actions and self.actions.available() then
            entry.actions=entry.actions or {}
            -- Presentation failure must not retire or stall the moving body.
            local applied,status=pcall(self.actions.apply,actor,entry.actions,pose.actions,entry.presentation)
            entry.actionStatus=applied and status or "presentation_adapter_error"
        end
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
                local placed, why, retire = self:place(entry, pose, now)
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
function Controller:diagnostics()
    local result = {}
    for player, entry in pairs(self.owned) do
        local t, m = entry.target, entry.presentation
        local p = {entity=entry.session, actor=entry.id and key(entry.id),
            mode=self.locomotion and "passive_locomotion" or "passive_idle",
            loadedPresentationVersion=self.locomotion and self.locomotion.revision,
            visualYawOffsetDegrees=self.locomotion and math.deg(self.locomotion.yawOffset),
            retirementSubmitted=entry.removing == true, seenReady=entry.seenReady == true,
            lifecycle=entry.retiring and "retiring" or "static",
            x=t and t.x,y=t and t.y,z=t and t.z,yaw=t and t.yaw,
            speed=m and m.speed, gait=m and m.phase, commandAge=0, commands=0,snaps=0,
            presentationTime=m and m.previous and m.previous.time,
            gaitBlendEnabled=m and m.smooth,gaitBlendWeight=m and m.phaseWeight,
            gaitBlendPreviousPhase=m and m.previousPhase,gaitBlendPreviousProgress=m and m.previousProgress,
            gaitBlendPreviousDirection=m and m.phaseDirection,gaitBlendPreviousDirectionWeight=m and m.phaseDirectionWeight,
            gaitCrouchBackward=m and m.crouchBackward,gaitCrouchProgress=m and m.crouchProgress,
            gaitDirectionEnabled=self.directionalWalk,gaitDirection=m and m.direction,
            gaitPreviousDirection=m and m.previousDirection,gaitDirectionBlend=m and m.directionBlend,
            gaitDirectionWeight=m and m.directionWeight,gaitPreviousProgress=m and m.directionPreviousProgress}
        if self.actions then
            p.actionLayerVersion=self.actions.revision
            p.actionStatus=entry.actionStatus
            p.actions=t and t.actions
            local a=p.actions
            p.actionRevision=a and a.revision;p.actionSequence=a and a.sequence
            p.actionFresh=a and a.fresh;p.actionAgeMs=a and a.ageMs
            p.actionStance=a and a.stance;p.actionWeapon=a and a.weapon
            p.actionRecord=a and a.record;p.actionAim=a and a.aim
            local inputs=entry.actions and entry.actions.inputs or {}
            p.actionPose=inputs.cp_coop_weapon_pose
            p.actionCrouchMotion=inputs.cp_coop_crouch_motion
            p.actionStanceWeight=inputs.cp_coop_stance
            p.actionWeaponBlend=inputs.cp_coop_weapon_blend
            p.actionPreviousPose=inputs.cp_coop_weapon_previous_pose
            p.actionPreviousProgress=inputs.cp_coop_weapon_previous_progress
        end
        local ok, actual, heading = pcall(function()
            local o = observe(entry)
            if o and o.actor and o.attached then
                local position = o.actor:GetWorldPosition()
                local yawOk, yaw = pcall(function() return o.actor:GetWorldOrientation():ToEulerAngles().yaw end)
                return position, yawOk and yaw or nil
            end
        end)
        p.readback = ok and actual and "available" or "unavailable"
        if not ok then p.lifecycleObservationError=tostring(actual) end
        if p.readback == "available" then
            p.actualX,p.actualY,p.actualZ = actual.x,actual.y,actual.z
            p.actualYawDegrees = heading
            if t and type(heading)=="number" then
                local expected=math.deg(t.yaw)+(self.locomotion and math.deg(self.locomotion.yawOffset) or 0)
                p.yawErrorDegrees=math.abs((heading-expected+180)%360-180)
            end
            if t then p.error=math.sqrt((actual.x-t.x)^2+(actual.y-t.y)^2+(actual.z-t.z)^2) end
        end
        result[tostring(player)] = p
    end
    return result
end
return M
