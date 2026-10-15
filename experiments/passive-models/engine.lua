-- Explicit local experiment. These methods are called only by the onUpdate pump.
local M = {}
local Engine = {}; Engine.__index = Engine
local TAG = "CP2077Coop.PassiveModelFixture"
local GRAPH = "base\\cp2077coop\\animations\\networkhumanoid_idle.animgraph"
-- Keep these allowlists aligned with build_profile.py. Paths refer to resources,
-- not bundled vanilla payloads; ResourceExists verifies presence, not content.
local profiles = {
    judy_default = {
        template="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent",
        mesh="base\\characters\\appearances\\main_npc\\proxy\\judy_default\\judy_default.mesh",
        rig="base\\characters\\base_entities\\woman_base\\woman_base.rig",
        animset="base\\animations\\npc\\gameplay\\woman_average\\gang\\unarmed\\wa_gang_unarmed_locomotion_combat.anims",
    },
    mitch_default = {
        template="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid_mitch.ent",
        mesh="base\\characters\\appearances\\main_npc\\proxy\\mitch_default\\mitch_default.mesh",
        rig="base\\characters\\base_entities\\man_base\\man_base.rig",
        animset="base\\animations\\npc\\gameplay\\man_average\\gang\\unarmed\\ma_gang_unarmed_locomotion_combat.anims",
    },
}
local function opaque(value)
    if value == nil or type(value) == "number" then return nil end
    local text = tostring(value):gsub("[uUlL]+$", "")
    if text:match("^[1-9][0-9]*$") and #text <= 20
        and (#text < 20 or text <= "18446744073709551615") then return text end
end
local function key(id)
    if id == nil or type(id) == "number" then return nil end
    return opaque(id.hash)
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)~=math.huge end
local function nativeHash(value)
    return type(value)=="string" and value:match("^%d+$")~=nil
        and (#value==1 or value:sub(1,1)~="0") and #value<=20
        and (#value<20 or value<="18446744073709551615")
end
local function visualState(actor,entry)
    local player=assert(Game.GetPlayer(),"visual_context_unavailable")
    local raw=actor:CP2077PassiveModelFixture_CurrentVisualState(player,entry.originalPlayer,entry.retained,entry.id)
    assert(raw and raw.valid==true,"visual_state_incoherent_or_unavailable")
    assert(raw.entityDecimal==entry.idKey and raw.contextDecimal==entry.playerId,"visual_identity_mismatch")
    assert(nativeHash(raw.appearanceHash) and nativeHash(raw.colorHash),"visual_hash_unavailable")
    assert(type(raw.appearance)=="string" and #raw.appearance<=256
        and type(raw.color)=="string" and #raw.color<=256,"visual_name_unavailable")
    return {appearance=raw.appearance,appearanceHash=raw.appearanceHash,
        color=raw.color,colorHash=raw.colorHash}
end
local function ownedIdentity(actor,entry)
    local ok,value=pcall(function()
        return actor:CP2077PassiveModelFixture_OwnedIdentity(Game.GetPlayer(),entry.retained,entry.id)
    end)
    if ok and value==-1 then entry.identityFault=true end
    return ok and value==1 and not entry.identityFault
end
local function boolean(value) assert(type(value)=="boolean", "unknown_lifecycle"); return value end
local function paused()
    local requests = assert(Game.GetSystemRequestsHandler(), "pause_unavailable")
    return boolean(requests:IsGamePaused())
end
local function localPlayer()
    assert(not paused(), "paused")
    local requests = assert(Game.GetSystemRequestsHandler(), "game_context_unavailable")
    assert(requests:IsPreGame()==false, "game_not_loaded")
    local player = assert(Game.GetPlayer(), "player_unavailable")
    assert(player:IsAttached()==true, "player_not_attached")
    return player, assert(key(player:GetEntityID()), "player_identity_unavailable")
end
local function distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
local function pose(actor)
    local p,q = actor:GetWorldPosition(), actor:GetWorldOrientation()
    local result={x=p.x,y=p.y,z=p.z,qx=q.i,qy=q.j,qz=q.k,qw=q.r}
    for _,field in ipairs({"x","y","z","qx","qy","qz","qw"}) do
        assert(finite(result[field]), "pose_unavailable")
    end
    local norm=q.i*q.i+q.j*q.j+q.k*q.k+q.r*q.r
    assert(math.abs(norm-1)<0.01, "orientation_not_unit")
    return result
end
function M.new() return setmetatable({owned={}},Engine) end
function Engine:profile(name)
    local source=profiles[name]
    if not source then return nil end
    return {name=name,template=source.template,appearance="default",graph=GRAPH,
        mesh=source.mesh,rig=source.rig,animset=source.animset}
end
function Engine:create(entry)
    assert(not entry.spawnAttempted, "spawn_already_attempted")
    local p=assert(profiles[entry.profile], "unsupported_profile")
    local player,playerId=localPlayer()
    local where=player:GetWorldPosition()
    assert(finite(where.x) and finite(where.y) and finite(where.z), "player_pose_unavailable")
    assert(distance(entry.target,where)>=1 and distance(entry.target,where)<=15
        and math.abs(entry.target.z-where.z)<=3, "spawn_outside_local_bounds")
    local creator=assert(Game.GetStaticEntitySystem(), "static_system_unavailable")
    assert(creator:IsReady()==true, "static_system_not_ready")
    local depot=assert(Game.GetResourceDepot(), "resource_depot_unavailable")
    for _,path in ipairs({p.template,GRAPH,p.mesh,p.rig,p.animset}) do
        local exists=depot:ResourceExists(ResRef.FromName(path))
        assert(type(exists)=="boolean", "resource_observation_unknown")
        assert(exists, "missing_resource:"..path)
    end
    local ids=creator:GetTaggedIDs(CName.new(TAG))
    assert(type(ids)=="table", "tag_observation_unknown")
    for _,id in pairs(ids) do
        local found=assert(key(id), "tag_identity_unknown")
        assert(self.owned[found]~=nil, "historical_fixture_present")
    end
    local spec=StaticEntitySpec.new()
    spec.templatePath=ResRef.FromName(p.template)
    spec.appearanceName=CName.new("default")
    spec.position=Vector4.new(entry.target.x,entry.target.y,entry.target.z,1)
    spec.orientation=Quaternion.new(0,0,math.sin(entry.target.yaw/2),math.cos(entry.target.yaw/2))
    spec.attached=true
    spec.tags={CName.new(TAG),CName.new(TAG.."."..entry.slot)}
    -- Reserve provenance BEFORE the native call. Exceptions/invalid IDs after
    -- this point have unknown outcomes and cannot authorize an automatic retry.
    entry.creator,entry.playerId,entry.expectedTemplate=creator,playerId,p.template
    entry.originalPlayer=player -- Retain native context identity; Lua wrappers may differ later.
    entry.templateHash=assert(opaque(ResRef.GetHash(spec.templatePath)), "template_hash_unavailable")
    entry.spawnAttempted=true
    entry.id=creator:SpawnEntity(spec)
    entry.idKey=assert(key(entry.id), "spawn_identity_unknown")
    assert(not self.owned[entry.idKey], "duplicate_returned_identity")
    self.owned[entry.idKey]=entry
    return true
end
function Engine:observe(entry)
    assert(entry.idKey and self.owned[entry.idKey]==entry, "owned_identity_unavailable")
    local s=assert(entry.creator,"creator_unavailable")
    assert(s:IsReady()==true, "creator_not_ready")
    local managed,spawning,spawned=boolean(s:IsManaged(entry.id)),boolean(s:IsSpawning(entry.id)),boolean(s:IsSpawned(entry.id))
    local function attachment(actor)
        if actor==nil then return false end
        assert(key(actor:GetEntityID())==entry.idKey, "actor_identity_mismatch")
        return boolean(actor:IsAttached())
    end
    local actor,globalActor=s:GetEntity(entry.id),Game.FindEntityByID(entry.id)
    local attached,globalAttached=attachment(actor),attachment(globalActor)
    if not entry.retained then entry.retained=actor or globalActor end
    local retainedAttached=attachment(entry.retained)
    local identityVerified=false
    if actor or globalActor then identityVerified=ownedIdentity(actor or globalActor,entry) end
    local ready=actor~=nil and attached and managed and spawned and not spawning
    if ready then entry.completed=true end
    local o={ready=ready,managed=managed,spawning=spawning,spawned=spawned,
        attached=attached,globalAttached=globalAttached,retainedAttached=retainedAttached,
        absent=not managed and not spawning and not spawned and actor==nil
            and globalActor==nil and not retainedAttached,
        templateVerified=false,rootVerified=false,appearanceVerified=false,visualStateObserved=false,
        colorObserved=false,colorMatchVerified=false,visualQualified=false}
    o.identityVerified,o.identityFault=identityVerified,entry.identityFault==true
    if o.identityFault then o.visualFault="owned_native_identity_mismatch" end
    -- Visual/readback failures must block movement, not exact owned retirement.
    if actor then
        local ok,visual=pcall(function()
            local template=actor:GetTemplatePath()
            local actualHash=assert(opaque(ResRef.GetHash(template)), "template_readback_unavailable")
            local exact=actor:IsExactlyA(CName.new("entEntity"))
            assert(type(exact)=="boolean", "class_readback_unavailable")
            return {templateHash=actualHash,template=ResRef.ToString(template),rootVerified=exact,
                templateVerified=actualHash==entry.templateHash,pose=pose(actor)}
        end)
        if ok then
            o.templateVerified,o.rootVerified=visual.templateVerified,visual.rootVerified
            o.template,o.templateHash,o.pose=visual.template,visual.templateHash,visual.pose
            if not o.templateVerified then o.visualFault="template_mismatch"
            elseif not o.rootVerified then o.visualFault="not_passive_entity" end
        else o.visualFault="visual_readback_unavailable" end
        local appearanceOk,current=pcall(visualState,actor,entry)
        if appearanceOk then
            o.visualStateObserved,o.colorObserved=true,true
            o.observedAppearance,o.observedAppearanceHash=current.appearance,current.appearanceHash
            o.observedColor,o.observedColorHash=current.color,current.colorHash
            o.appearanceNameAvailable,o.colorNameAvailable=#current.appearance>0,#current.color>0
        end
        o.appearanceVerified=identityVerified and appearanceOk and current.appearance=="default"
        if not o.appearanceVerified and not o.visualFault then
            if not appearanceOk then
                o.visualFault="visual_state_readback_unavailable"
            elseif current.appearance=="" or current.appearance=="None" then
                o.visualFault="appearance_readback_unavailable"
            else o.visualFault="appearance_mismatch" end
        end
    end
    return o
end
function Engine:move(entry,target)
    assert(not entry.retiring,"retiring")
    local _,playerId=localPlayer()
    assert(playerId==entry.playerId,"player_changed")
    local o=self:observe(entry)
    assert(o.ready and o.identityVerified and o.templateVerified and o.rootVerified and o.appearanceVerified and o.pose,"actor_not_qualified")
    assert(distance(target,o.pose)<=5,"move_exceeds_five_meters")
    local player=Game.GetPlayer()
    assert(distance(target,player:GetWorldPosition())<=20,"move_outside_local_bounds")
    local world=WorldTransform.new()
    WorldTransform.SetPosition(world,Vector4.new(target.x,target.y,target.z,1))
    WorldTransform.SetOrientationEuler(world,EulerAngles.new(0,0,math.deg(target.yaw)))
    local actor=assert(entry.creator:GetEntity(entry.id),"actor_disappeared_before_move")
    assert(key(actor:GetEntityID())==entry.idKey and actor:IsAttached()==true,"actor_changed_before_move")
    assert(ownedIdentity(actor,entry),"owned_native_identity_changed_before_move")
    assert(opaque(ResRef.GetHash(actor:GetTemplatePath()))==entry.templateHash
        and actor:IsExactlyA(CName.new("entEntity"))==true,"visual_changed_before_move")
    local current=visualState(actor,entry)
    assert(current.appearance=="default" and current.appearance==o.observedAppearance
        and current.appearanceHash==o.observedAppearanceHash and current.color==o.observedColor
        and current.colorHash==o.observedColorHash,"visual_state_changed_before_move")
    entry.moveAttempted=true
    actor:SetWorldTransform(world)
    return true -- submission only; controller compares a later actual readback.
end
function Engine:retire(entry)
    if not entry.spawnAttempted then return true end
    local o=self:observe(entry)
    if entry.identityFault then return false end -- Never touch or release a positively foreign actor.
    if entry.completed and o.absent then
        self.owned[entry.idKey]=nil
        return true
    end
    if not entry.removalAttempted and o.ready and o.identityVerified and not paused() then
        local actor=entry.creator:GetEntity(entry.id)
        if not actor or not ownedIdentity(actor,entry) then return false end
        entry.removalAttempted=true -- A thrown/unknown native outcome must not be reissued.
        local accepted=entry.creator:DespawnEntity(entry.id)
        assert(accepted==true,"despawn_not_confirmed")
        entry.removing=true
    end
    return false
end
return M
