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
    assert(value and value:IsReady(),"dynamic_system_unavailable")
    return value
end
function Engine.new() return setmetatable({},Engine) end
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
    self.id=s:CreateEntity(spec)
    self.key=assert(key(self.id),"create_identity_unavailable")
    return self.key,self.creator
end
function Engine:_actor(expected)
    assert(expected==self.key and self.id~=nil,"not_owned_identity")
    local s=system()
    local world=Game.FindEntityByID(self.id)
    local population=s:GetEntity(self.id)
    if world then assert(key(world:GetEntityID())==expected,"world_identity_mismatch") end
    if population then assert(key(population:GetEntityID())==expected,"population_identity_mismatch") end
    if self.retained then assert(key(self.retained:GetEntityID())==expected,"retained_identity_mismatch") end
    if world and world:IsAttached() then self.retained=world
    elseif population and population:IsAttached() then self.retained=population end
    local actor=world or population or self.retained
    if self.retained and self.retained:IsAttached() then actor=self.retained end
    return actor,s,population,world
end
function Engine:observe(expected)
    local actor,s,population,world=self:_actor(expected)
    local o={id=expected,managed=s:IsManaged(self.id),spawning=s:IsSpawning(self.id),spawned=s:IsSpawned(self.id),
        worldPresent=world~=nil,populationPresent=population~=nil,attached=actor~=nil and actor:IsAttached(),
        retainedAttached=self.retained~=nil and self.retained:IsAttached()}
    if not o.attached then return o end
    local player=assert(Game.GetPlayer(),"player_unavailable")
    -- After deletion, the entity may remain attached briefly but no longer be managed.
    o.player=assert(key(player:GetEntityID()),"player_identity_unavailable")
    if o.managed and o.player==self.creator then assert(actor:CP2077VehicleProbe_Owned(player),"ownership_unavailable") end
    o.onFoot=player:CP2077VehicleProbe_OnFoot()
    local position=actor:GetWorldPosition(); local q=actor:GetWorldOrientation(); local v=actor:GetLinearVelocity()
    o.pose={x=position.x,y=position.y,z=position.z,qx=q.i,qy=q.j,qz=q.k,qw=q.r}
    o.speed=math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
    o.velocity={x=v.x,y=v.y,z=v.z}
    o.record=actor:GetRecordID()==TweakDBID.new(record) and record or "unsupported_record"
    o.appearance=actor:CP2077VehicleProbe_Appearance(); o.color=actor:CP2077VehicleProbe_ColorVariant()
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
    local actor,s=self:_actor(expected)
    local player=Game.GetPlayer()
    assert(actor and s:IsManaged(self.id) and player and key(player:GetEntityID())==self.creator
        and child==self.creator,"request_identity_unavailable")
    return actor:CP2077VehicleProbe_Request(player,CName.new(slot),operation=="mount")
end
function Engine:delete(expected)
    local actor,s=self:_actor(expected)
    local player=Game.GetPlayer()
    if not actor or not player or key(player:GetEntityID())~=self.creator
        or not actor:CP2077VehicleProbe_CanRetire(player) then return false end
    return s:DeleteEntity(self.id)
end
return Engine
