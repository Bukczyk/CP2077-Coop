-- All calls execute from CET's game-thread callbacks or explicit fixture calls.
local Engine={}
Engine.__index=Engine
local record="Vehicle.v_standard2_archer_hella_player"
local tag="CP2077VehicleSeatFixture"
local slots={"seat_front_left","seat_front_right","seat_back_left","seat_back_right"}
local function key(value)
    if value==nil or type(value)=="number" then return nil end
    local hash=value.hash
    if hash==nil or type(hash)=="number" then return nil end
    local text=tostring(hash):gsub("[uUlL]+$","")
    if not text:match("^[1-9][0-9]*$") or #text>20 or (#text==20 and text>"18446744073709551615") then return nil end
    return text
end
local function system()
    local value=Game.GetDynamicEntitySystem()
    assert(value and value:IsReady()==true,"dynamic_system_unavailable")
    return value
end
function Engine.new(generation) return setmetatable({generation=generation or 1},Engine) end
function Engine:descriptor()
    local player=assert(Game.GetPlayer(),"player_unavailable")
    assert(player:IsAttached() and player:CP2077VehicleProbe_OnFoot(),"player_not_on_foot")
    local appearance=player:CP2077VehicleProbe_DefaultAppearance()
    assert(appearance and appearance~="" and appearance~="None","default_appearance_unavailable")
    return {record=record,appearance=appearance,color="None"}
end
function Engine:create(descriptor,pose)
    assert(self.id==nil,"already_owns_car")
    local s=system()
    assert(not s:IsPopulated(CName.new(tag)),"previous_fixture_still_present")
    assert(descriptor.record==record and descriptor.appearance==self:descriptor().appearance
        and descriptor.color=="None","unsupported_descriptor")
    local creator=assert(Game.GetPlayer(),"creator_unavailable")
    self.creator=assert(key(creator:GetEntityID()),"creator_identity_unavailable")
    local localPosition=creator:GetWorldPosition()
    local distance=math.sqrt((pose.x-localPosition.x)^2+(pose.y-localPosition.y)^2+(pose.z-localPosition.z)^2)
    assert(distance>=6 and distance<=15 and math.abs(pose.z-localPosition.z)<=3,"spawn_point_outside_local_fixture_bounds")
    local spec=DynamicEntitySpec.new()
    spec.recordID=TweakDBID.new(record); spec.appearanceName=CName.new(descriptor.appearance)
    spec.position=Vector4.new(pose.x,pose.y,pose.z,1)
    spec.orientation=Quaternion.new(pose.qx,pose.qy,pose.qz,pose.qw)
    spec.persistState=false; spec.persistSpawn=false; spec.alwaysSpawned=true
    spec.spawnInView=true; spec.active=true; spec.tags={CName.new(tag)}
    self.appearance=descriptor.appearance -- Frozen for this car's lifetime, not a later record default.
    self.system=s -- Retain the exact creator even while native creation is pending.
    self.id=s:CreateEntity(spec)
    self.key=assert(key(self.id),"create_identity_unavailable")
    return self.key,self.creator
end
function Engine:_actor(expected)
    assert(expected==self.key and self.id~=nil,"not_owned_identity")
    local s=self.system
    assert(s and s:IsReady()==true,"creator_system_unavailable")
    local world=Game.FindEntityByID(self.id)
    local population=s:GetEntity(self.id)
    local function attached(candidate,label)
        if candidate==nil then return false end
        assert(key(candidate:GetEntityID())==expected,label.."_identity_mismatch")
        local value=candidate:IsAttached()
        assert(type(value)=="boolean",label.."_attachment_unavailable")
        return value
    end
    local worldAttached=attached(world,"world")
    local populationAttached=attached(population,"population")
    local retainedAttached=attached(self.retained,"retained")
    -- Validate before changing ownership. A later exact-ID wrapper cannot erase
    -- evidence that the first observed actor is still attached.
    if self.retained==nil then
        if worldAttached then self.retained=world;retainedAttached=true
        elseif populationAttached then self.retained=population;retainedAttached=true end
    end
    local actor,actorAttached
    if retainedAttached then actor=self.retained;actorAttached=true
    elseif world~=nil then actor=world;actorAttached=worldAttached
    elseif population~=nil then actor=population;actorAttached=populationAttached
    else actor=self.retained;actorAttached=false end
    return actor,s,population,world,actorAttached,retainedAttached
end
function Engine:observe(expected)
    local actor,s,population,world,attached,retainedAttached=self:_actor(expected)
    local o={id=expected,managed=s:IsManaged(self.id),spawning=s:IsSpawning(self.id),spawned=s:IsSpawned(self.id),
        worldPresent=world~=nil,populationPresent=population~=nil,attached=attached,
        retainedAttached=retainedAttached}
    if not o.attached then return o end
    local player=assert(Game.GetPlayer(),"player_unavailable")
    -- After deletion, the entity may remain attached briefly but no longer be managed.
    o.player=assert(key(player:GetEntityID()),"player_identity_unavailable")
    -- Read before Owned: its native record guard can reject before a full sample
    -- exists. A hard record mismatch is not a recoverable cosmetic quarantine.
    if actor:GetRecordID()~=TweakDBID.new(record) then self.recordFault=true end
    if self.recordFault then o.recordFault=true; return o end
    if o.managed and o.player==self.creator then assert(actor:CP2077VehicleProbe_Owned(player),"ownership_unavailable") end
    o.onFoot=player:CP2077VehicleProbe_OnFoot()
    local position=actor:GetWorldPosition(); local q=actor:GetWorldOrientation(); local v=actor:GetLinearVelocity()
    o.pose={x=position.x,y=position.y,z=position.z,qx=q.i,qy=q.j,qz=q.k,qw=q.r}
    o.speed=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
    o.velocity={x=v.x,y=v.y,z=v.z}
    o.record=record
    -- Missing cosmetics quarantine new mounts/motion, but must not erase otherwise
    -- valid identity/seat observations required to safely leave an owned car.
    local appearanceOk,appearance=pcall(function()return actor:CP2077VehicleProbe_Appearance()end)
    local colorOk,color=pcall(function()return actor:CP2077VehicleProbe_ColorVariant()end)
    o.appearanceAvailable=appearanceOk and type(appearance)=="string" and appearance~=""
    o.colorAvailable=colorOk and type(color)=="string" and color~=""
    o.appearance=o.appearanceAvailable and appearance or nil
    o.color=o.colorAvailable and color or nil
    -- No unnamed or customized variant is silently treated as the requested default.
    o.occupants={}; o.slots={}; o.events={}
    for _,mount in ipairs(actor:CP2077VehicleProbe_ReadSeats()) do
        o.occupants[#o.occupants+1]={parent=key(mount.parent),child=key(mount.child),slot=mount.slot}
    end
    for _,slot in ipairs(slots) do o.slots[slot]=actor:CP2077VehicleProbe_HasSeat(CName.new(slot)) end
    o.eventOverflow=actor:CP2077VehicleProbe_EventOverflow()
    for _,event in ipairs(actor:CP2077VehicleProbe_ReadEvents()) do
        o.events[#o.events+1]={serial=event.serial,child=key(event.child),slot=event.slot,mounting=event.mounting}
    end
    local info=player:CP2077VehicleProbe_MountInfo()
    o.playerMount={parent=key(info.parentId),child=key(info.childId),slot=player:CP2077VehicleProbe_MountSlot()}
    local manager=actor:GetCameraManager()
    o.camera=manager and {perspective=tostring(manager:GetActivePerspective()),
        persistent=tostring(manager:GetPersistentPerspective()),tpp=manager:IsTPPActive()} or {unavailable=true}
    return o
end
function Engine:acknowledge(expected,serial)
    local actor=self:_actor(expected)
    assert(actor,"event_actor_unavailable")
    return actor:CP2077VehicleProbe_AcknowledgeEvents(serial)
end
function Engine:request(expected,child,operation,slot)
    -- Last observation can predate pause or save/menu changes. These reads are
    -- before the native request, so failure is a definite rejection, not an
    -- ambiguous submitted outcome that would quarantine the pending request.
    local ok,actor,player=pcall(function()
        assert(not self.recordFault,"request_record_fault")
        local handler=assert(Game.GetSystemRequestsHandler(),"request_context_unavailable")
        assert(handler:IsGamePaused()==false and handler:IsPreGame()==false,"request_context_inactive")
        local current,s,_,_,attached=self:_actor(expected)
        local creator=Game.GetPlayer()
        assert(current and attached==true and s:IsManaged(self.id)==true
            and s:IsSpawned(self.id)==true and s:IsSpawning(self.id)==false
            and creator and creator:IsAttached()==true
            and key(creator:GetEntityID())==self.creator and child==self.creator,
            "request_identity_unavailable")
        if current:GetRecordID()~=TweakDBID.new(record) then
            self.recordFault=true;error("request_record_mismatch")
        end
        if operation=="mount" then
            assert(type(self.appearance)=="string" and self.appearance~="" and self.appearance~="None"
                and creator:CP2077VehicleProbe_DefaultAppearance()==self.appearance
                and current:CP2077VehicleProbe_Appearance()==self.appearance
                and current:CP2077VehicleProbe_ColorVariant()=="None","request_cosmetics_unavailable")
        elseif operation=="unmount" then
            local info=creator:CP2077VehicleProbe_MountInfo()
            assert(key(info.parentId)==expected and key(info.childId)==self.creator
                and creator:CP2077VehicleProbe_MountSlot()==slot,"request_player_relationship_changed")
            local matches=0
            for _,occupant in ipairs(current:CP2077VehicleProbe_ReadSeats()) do
                local occupantId=key(occupant.child)
                assert(key(occupant.parent)==expected and occupantId,"request_occupant_identity_unavailable")
                if occupantId==self.creator or occupant.slot==slot then
                    assert(occupantId==self.creator and occupant.slot==slot,"request_vehicle_relationship_changed")
                    matches=matches+1
                end
            end
            assert(matches==1,"request_vehicle_relationship_changed")
        else error("request_operation_invalid") end
        return current,creator
    end)
    if not ok then return false end
    -- Keep the actual mutation outside that pcall: an exception after entering
    -- the native request still has an unknown outcome and must retain ownership.
    return actor:CP2077VehicleProbe_Request(player,CName.new(slot),operation=="mount",CName.new(self.appearance))
end
function Engine:delete(expected)
    if self.recordFault then return false end
    local actor,s=self:_actor(expected)
    local player=Game.GetPlayer()
    if not actor or not player or key(player:GetEntityID())~=self.creator
        or not actor:CP2077VehicleProbe_CanRetire(player) then return false end
    return s:DeleteEntity(self.id)
end
function Engine:applyPose(expected,child,generation,request,target)
    if self.recordFault then return false end
    assert(generation==self.generation and child==self.creator,"pose_scope_mismatch")
    -- A pause can begin after the last observation but before this manual call.
    -- No native application has happened yet, so unknown/paused is a rejection.
    local pauseOk,paused=pcall(function() return Game.GetSystemRequestsHandler():IsGamePaused() end)
    if not pauseOk or paused~=false then return false end
    local actor=self:_actor(expected)
    local player=Game.GetPlayer()
    assert(actor and player and key(player:GetEntityID())==self.creator,"pose_identity_unavailable")
    return actor:CP2077VehicleProbe_ApplyPose(player,generation,request,
        Vector4.new(target.x,target.y,target.z,1),Quaternion.new(target.qx,target.qy,target.qz,target.qw))
end
return Engine
