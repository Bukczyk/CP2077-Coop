local root=assert(arg[1])
package.path=root.."/experiments/vehicle-presentation/?.lua;"..package.path
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
local carId={hash="9007199254740993ULL"};local playerId={hash="9007199254740995ULL"};local zeroId={hash="0ULL"}
local ffiOk,ffi=pcall(require,"ffi")
if ffiOk then
    -- Real LuaJIT Uint64 values, constructed without a lossy double literal.
    carId.hash=ffi.new("uint64_t",9007199254740992)+1
    playerId.hash=ffi.new("uint64_t",9007199254740992)+3
    zeroId.hash=ffi.new("uint64_t",0)
end
local target={x=10,y=0,z=0,qx=0,qy=0,qz=math.sin(math.pi/4),qw=math.cos(math.pi/4)}
local data={created=0,deleted=0,requests=0,paused=false,present=false,attached=false,managed=false,spawning=false,spawned=false,mounts={},events={}}
local player,actor,system={},{},{}
function player:IsAttached() return true end
function player:GetEntityID() return playerId end
function player:GetWorldPosition() return {x=0,y=0,z=0} end
function player:CP2077VehicleProbe_OnFoot() return #data.mounts==0 end
function player:CP2077VehicleProbe_DefaultAppearance() return "hella_fixture_default" end
function player:CP2077VehicleProbe_MountInfo()
    return {parentId=#data.mounts==0 and zeroId or carId,childId=playerId,slotId={id="seat_front_left"}}
end
function player:CP2077VehicleProbe_MountSlot() return #data.mounts==0 and "None" or "seat_front_left" end
function actor:IsAttached() return data.attached end
function actor:GetEntityID() return carId end
function actor:CP2077VehicleProbe_Owned(p) return p==player and data.managed and data.spawned and not data.spawning end
function actor:GetWorldPosition() return {x=10,y=0,z=0} end
function actor:GetWorldOrientation() return {i=target.qx,j=target.qy,k=target.qz,r=target.qw} end
function actor:GetLinearVelocity() return {x=0,y=0,z=0} end
function actor:GetRecordID() return "Vehicle.v_standard2_archer_hella_player" end
function actor:CP2077VehicleProbe_Appearance() return "hella_fixture_default" end
function actor:CP2077VehicleProbe_ColorVariant() return "None" end
function actor:CP2077VehicleProbe_ReadSeats() return data.mounts end
function actor:CP2077VehicleProbe_HasSeat(slot) return slot=="seat_front_left" or slot=="seat_front_right" end
function actor:CP2077VehicleProbe_EventOverflow() return false end
function actor:CP2077VehicleProbe_ReadEvents() return data.events end
function actor:CP2077VehicleProbe_AcknowledgeEvents(serial)
    while data.events[1] and data.events[1].serial<=serial do table.remove(data.events,1) end
    return true
end
function actor:GetCameraManager()
    if data.cameraFailure then error("camera temporarily unavailable") end
    return {GetActivePerspective=function() return "FPP" end,GetPersistentPerspective=function() return "TPPFar" end,IsTPPActive=function() return false end}
end
function actor:CP2077VehicleProbe_Request(p,slot,mounting)
    check(p==player and slot=="seat_front_left");data.requests=data.requests+1;return true
end
function actor:CP2077VehicleProbe_CanRetire(p)
    return p==player and #data.mounts==0 and data.managed and data.spawned and not data.spawning
end
function system:IsReady() return true end
function system:IsPopulated() return data.managed end
function system:CreateEntity(spec)
    data.created=data.created+1;data.spec=spec;data.present=true;data.attached=true;data.managed=true;data.spawned=true;return carId
end
function system:IsManaged(id) check(id==carId);return data.managed end
function system:IsSpawned(id) check(id==carId);return data.spawned end
function system:IsSpawning(id) check(id==carId);return data.spawning end
function system:GetEntity(id) check(id==carId);return data.present and actor or nil end
function system:DeleteEntity(id) check(id==carId);data.deleted=data.deleted+1;return true end
Game={GetPlayer=function() return player end,GetDynamicEntitySystem=function() return system end,
    FindEntityByID=function(id) check(id==carId);return data.present and actor or nil end,
    GetSystemRequestsHandler=function() return {IsGamePaused=function() return data.paused end} end}
CName={new=function(s) return s end};TweakDBID={new=function(s) return s end}
DynamicEntitySpec={new=function() return {} end}
Vector4={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
Quaternion={new=function(i,j,k,r) return {i=i,j=j,k=k,r=r} end}
local Engine=require("engine")
local e=Engine.new();local desc=e:descriptor()
check(desc.appearance=="hella_fixture_default" and desc.color=="None")
check(e:create(desc,target)=="9007199254740993")
check(data.created==1 and data.spec.appearanceName==desc.appearance)
check(data.spec.orientation.k==target.qz and data.spec.orientation.r==target.qw)
check(data.spec.persistState==false and data.spec.persistSpawn==false)
local o=e:observe("9007199254740993")
check(o.player=="9007199254740995" and o.pose.qz==target.qz and o.playerMount.parent==nil)
check(o.camera.perspective=="FPP" and o.camera.persistent=="TPPFar")
check(o.slots.seat_front_left and not o.slots.seat_back_left)
data.mounts={{parent=carId,child=playerId,slot="seat_front_left"}}
data.events={{serial=1,child=playerId,slot="seat_front_left",mounting=true}}
o=e:observe("9007199254740993")
check(o.occupants[1].parent=="9007199254740993" and o.occupants[1].child=="9007199254740995")
check(o.playerMount.parent=="9007199254740993" and o.events[1].child=="9007199254740995")
check(not e:delete("9007199254740993") and data.deleted==0)
check(not pcall(e.delete,e,"9007199254740992") and data.deleted==0)
check(not pcall(e.request,e,"9007199254740993","100","mount","seat_front_left") and data.requests==0)
data.mounts={};check(e:delete("9007199254740993") and data.deleted==1)
check(not pcall(e.create,e,desc,target) and data.created==1)
data.present=false;data.managed=false;data.spawned=false
o=e:observe("9007199254740993")
check(not o.worldPresent and not o.populationPresent and o.retainedAttached and o.attached,
    "retained attached handle lost with both lookups")
data.attached=false;o=e:observe("9007199254740993")
check(not o.retainedAttached and not o.attached)
-- No automatic activation, preserved false pause value, no keyboard bindings,
-- requests disabled by default, and shutdown never tries asynchronous deletion.
data.present=false;data.attached=false;data.managed=false;data.spawned=false;data.deleted=0;data.created=0
local callbacks={};registerForEvent=function(name,fn) callbacks[name]=fn end
json={encode=function() return "{}" end}
local originalPrint=print;print=function() end
local api=dofile(root.."/experiments/vehicle-presentation/init.lua")
check(data.created==0 and api.status().state=="idle")
check(not api.start({x=1}));check(api.start(target));check(data.created==1)
for _=1,6 do callbacks.onUpdate(0.1) end
check(api.status().state=="ready","false pause became unavailable")
check(not api.request("mount","seat_front_left") and data.requests==0)
check(not api.start(target) and data.created==1)
callbacks.onShutdown();check(data.deleted==0)
check(api.enableRequests(true));check(api.request("mount","seat_front_left"));check(data.requests==1)
check(api.stop()==false and not api.status().requestsEnabled)
callbacks.onUpdate(0.1);check(data.deleted==0,"pending mount deleted on stop")
print=originalPrint
-- A leaked object tag prevents a second instance from hiding an old fixture.
local e2=Engine.new();check(not pcall(e2.create,e2,desc,target))
data.managed=false
local close={x=1,y=0,z=0,qx=0,qy=0,qz=0,qw=1}
check(not pcall(e2.create,e2,desc,close) and data.created==1)
-- Creator is pinned before asynchronous creation can finish, not on first readback.
data.present=false;data.attached=false;data.managed=false;data.spawned=false;data.mounts={};data.events={}
local e3=Engine.new()
local Fixture=require("fixture")
local f=Fixture.new(e3,desc)
check(f:start(target));local savedPlayerHash=playerId.hash;playerId.hash="200ULL"
for _=1,6 do f:step(0.1,false) end
check(f.identityFault and f.state=="player_changed" and f.player=="9007199254740995")
check(e3:delete("9007199254740993")==false and data.deleted==0)
playerId.hash=savedPlayerHash
data.spawned=false;check(not e3:delete("9007199254740993") and data.deleted==0)
-- A read failure after peeking finished events must leave the event replayable.
data.present=false;data.attached=false;data.managed=false;data.spawned=false;data.mounts={};data.events={}
local e4=Engine.new();local f4=Fixture.new(e4,desc)
check(f4:start(target));for _=1,5 do f4:step(0.1,false) end
check(f4.state=="ready" and f4:request("mount","seat_front_left"))
data.mounts={{parent=carId,child=playerId,slot="seat_front_left"}}
data.events={{serial=1,child=playerId,slot="seat_front_left",mounting=true}}
data.cameraFailure=true;f4:step(0.1,false)
check(f4.pending and not f4.pending.finished and #data.events==1,"camera failure discarded completion")
data.cameraFailure=false;f4:step(0.1,false)
check(f4.pending==nil and f4.state=="ready" and #data.events==0)
print("vehicle_engine_adapter: "..checks.." checks passed")
