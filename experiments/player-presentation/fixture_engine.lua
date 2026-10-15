-- Only fixture:onUpdate calls this adapter. Native identity is not Lua wrapper equality.
local Engine={}; Engine.__index=Engine
local TAG="CP2077PlayerActionFixture"
local function key(id)
    assert(id~=nil and type(id)~="number","identity_unavailable")
    local hash=id.hash
    assert(hash~=nil and type(hash)~="number","identity_precision_unavailable")
    local text=tostring(hash):gsub("[uUlL]+$","")
    assert(text:match("^[1-9][0-9]*$") and #text<=20
        and (#text<20 or text<="18446744073709551615"),"invalid_identity")
    return text
end
local function boolean(value)
    assert(type(value)=="boolean","lifecycle_unknown"); return value
end
function Engine.new() return setmetatable({},Engine) end
function Engine:context()
    local handler=assert(Game.GetSystemRequestsHandler(),"context_unavailable")
    assert(handler:IsGamePaused()==false and handler:IsPreGame()==false,"context_inactive_or_unknown")
    local current=assert(Game.GetPlayer(),"player_unavailable")
    assert(current:IsAttached()==true,"player_detached")
    if self.player==nil then return current end
    if key(current:GetEntityID())~=self.playerKey or key(self.player:GetEntityID())~=self.playerKey then self.contextFault=true end
    local same=CP2077ActionFixture.Context(current,self.player)
    if same==0 then self.contextFault=true end
    assert(not self.contextFault and same==1,"original_player_unavailable")
    return current
end
function Engine:create(pose)
    assert(not self.createAttempted,"creation_already_attempted")
    local player=self:context()
    local playerKey=key(player:GetEntityID())
    local s=assert(Game.GetDynamicEntitySystem(),"creator_unavailable")
    assert(s:IsReady()==true and s:IsPopulated(CName.new(TAG))==false,"creator_or_old_fixture_unavailable")
    local position=player:GetWorldPosition()
    local distance=math.sqrt((pose.x-position.x)^2+(pose.y-position.y)^2+(pose.z-position.z)^2)
    assert(distance>=3 and distance<=8 and math.abs(pose.z-position.z)<=2,"spawn_outside_local_bounds")
    local spec=DynamicEntitySpec.new()
    spec.recordID=TweakDBID.new("Character.Judy")
    spec.position=Vector4.new(pose.x,pose.y,pose.z,1)
    spec.orientation=Quaternion.new(0,0,math.sin(pose.yaw*math.pi/360),math.cos(pose.yaw*math.pi/360))
    spec.persistState=false;spec.persistSpawn=false;spec.alwaysSpawned=true
    spec.spawnInView=true;spec.active=true;spec.tags={CName.new(TAG)}
    self.player,self.playerKey,self.system=player,playerKey,s
    self:context() -- constructors/getters may have changed context before admission
    assert(s:IsReady()==true and s:IsPopulated(CName.new(TAG))==false,"creator_or_old_fixture_unavailable")
    self.createAttempted=true -- before native call, including exceptions/invalid tokens
    self.id=s:CreateEntity(spec)
    self.key=key(self.id)
end
function Engine:observe()
    assert(self.id and self.key,"creation_outcome_unknown")
    local s=assert(self.system,"creator_unavailable")
    assert(s:IsReady()==true,"original_creator_unavailable")
    local managed,spawning,spawned=boolean(s:IsManaged(self.id)),boolean(s:IsSpawning(self.id)),boolean(s:IsSpawned(self.id))
    local world,population=Game.FindEntityByID(self.id),s:GetEntity(self.id)
    local function attached(actor)
        if actor==nil then return false end
        if key(actor:GetEntityID())~=self.key then self.identityFault=true end
        if self.retained~=nil then
            local same=CP2077ActionFixture.Same(actor,self.retained)
            if same==false then self.identityFault=true end
            assert(type(same)=="boolean","native_reference_unknown")
        end
        return boolean(actor:IsAttached())
    end
    local wa,pa=attached(world),attached(population)
    if self.retained==nil and pa and wa and managed and spawned and not spawning then
        assert(CP2077ActionFixture.Same(world,population)==true,"world_population_disagree")
        self.retained=population -- first exact completed creator-owned actor only
    end
    local ra=attached(self.retained)
    assert(not self.identityFault,"foreign_actor_quarantined")
    local ready=wa and pa and ra and managed and spawned and not spawning
    if ready then
        local identity=CP2077ActionFixture.Actor(self:context(),self.retained,self.id,population)
        if identity==0 then self.identityFault=true end
        assert(identity==1 and not self.identityFault,"actor_identity_unavailable")
        self.completed=true -- explicit creator-owned attached native completion, not a timer
    end
    return {ready=ready,absent=world==nil and population==nil and not ra
        and not managed and not spawning and not spawned}
end
function Engine:guard()
    self:context()
    assert(not self.deleteAttempted,"retirement_already_requested")
    assert(self:observe().ready,"actor_not_ready")
    return self.retained
end
-- Each actual actions/probe call gets a fresh game-thread guard. The facade
-- never substitutes whichever actor currently happens to have the same ID.
local methods={"GetEntityID","IsAttached","CP2077Session_PoseReady",
    "CP2077Session_StanceMatches","CP2077Session_ReadPresentationWeapon",
    "CP2077Session_ApplyStance","CP2077Session_HasPresentationItem",
    "CP2077Session_PresentationGrantCount","CP2077Session_EquipPresentation",
    "CP2077Session_StopPresentation","CP2077Session_AcquireAimProbe",
    "CP2077Session_ReadAimProbe","CP2077Session_RequestAimProbe","CP2077Session_ReleaseAimProbe"}
function Engine:actor()
    if self.facade==nil then
        self.facade={}
        for _,name in ipairs(methods) do
            self.facade[name]=function(_,...)
                local actor=self:guard()
                return actor[name](actor,...)
            end
        end
    end
    return self.facade
end
function Engine:capture(Actions)
    local player=self:context()
    local state,reason=Actions.capture(player)
    self:context() -- reject context changes during a native capture callback
    return state,reason
end
function Engine:retire()
    self:guard() -- fresh creator/lifecycle/native-reference check before mutation
    self.deleteAttempted=true -- one attempt, even false/throw may be ambiguous
    local accepted=self.system:DeleteEntity(self.id)
    self.deleteAccepted=accepted==true
    return self.deleteAccepted
end
return Engine
