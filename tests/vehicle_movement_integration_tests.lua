local root=assert(arg[1]);package.path=root.."/experiments/vehicle-presentation/?.lua;"..package.path
local checks=0
local function check(v,message) checks=checks+1;assert(v,message) end
local function copy(t) if type(t)~="table"then return t end local r={}for k,v in pairs(t)do r[k]=copy(v)end return r end
local ID,PLAYER="9007199254740993","9007199254740995"
local origin={x=10,y=0,z=0,qx=0,qy=0,qz=0,qw=1}
local descriptor={record="Vehicle.v_standard2_archer_hella_player",appearance="fixture_default",color="None"}
local originalEngine=package.loaded.engine
local originalPrint=print;print=function()end
local function harness()
    local data={calls=0,deletes=0,creates=0,paused=false}
    local o={id=ID,player=PLAYER,pose=copy(origin),attached=true,retainedAttached=true,worldPresent=true,populationPresent=true,
        managed=true,spawned=true,spawning=false,onFoot=true,occupants={},playerMount={},speed=0,eventOverflow=false,
        slots={seat_front_left=true},events={},record=descriptor.record,appearance=descriptor.appearance,color=descriptor.color}
    local engine={}
    function engine:descriptor()return descriptor end
    function engine:create()data.creates=data.creates+1;return ID,PLAYER end
    function engine:observe()if data.readFailure then error("read unavailable")end return copy(o)end
    function engine:applyPose(id,player,generation,request,target)
        check(id==ID and player==PLAYER and generation==data.generation)
        data.calls=data.calls+1;data.target=copy(target)
        if data.throwApplication then error("unknown native outcome")end
        return true
    end
    function engine:delete()data.deletes=data.deletes+1;return true end
    function engine:request()error("no seat operation expected")end
    package.loaded.engine={new=function(generation)data.generation=generation;return engine end}
    local callbacks={};registerForEvent=function(name,fn)callbacks[name]=fn end
    json={encode=function()return "{}"end}
    Game={GetSystemRequestsHandler=function()return{IsGamePaused=function()return data.paused end}end}
    local api=dofile(root.."/experiments/vehicle-presentation/init.lua")
    check(api.status().state=="idle" and data.creates==0 and data.calls==0)
    check(api.start(origin));for _=1,5 do callbacks.onUpdate(0.1)end
    check(api.status().state=="ready" and not api.status().movement.enabled and data.calls==0)
    local target=copy(origin);target.x=target.x+0.3
    return api,data,o,callbacks,target
end
do
    local api,d,o,cb,target=harness();local generation=api.status().generation
    check(not api.move(target,generation));check(api.enableRequests(true));check(not api.enableMovement(true))
    check(api.enableRequests(false));check(api.enableMovement(true));check(not api.enableRequests(true))
    check(not api.move(target,generation+1) and d.calls==0)
    check(api.move(target,generation) and d.calls==1)
    check(api.status().movement.pending and not api.status().movement.movementQualified)
    check(not api.stop() and api.status().stopRequested and not api.status().retiring)
    check(not api.enableRequests(true));check(not api.enableMovement(true));check(not api.request("mount","seat_front_left"))
    check(not api.start(origin));check(not api.move(target,generation));cb.onShutdown()
    for _=1,25 do cb.onUpdate(0.1)end
    check(d.deletes==0 and d.calls==1 and api.status().movement.fault=="movement_readback_timeout")
    o.pose=copy(target);for _=1,5 do cb.onUpdate(0.1)end
    check(not api.status().movement.pending and api.status().movement.state=="observed_after_fault")
    check(api.status().retiring and d.deletes>=1 and api.status().state~="closed")
    o.managed=false;o.spawned=false;o.attached=false;o.retainedAttached=false;o.worldPresent=false;o.populationPresent=false
    for _=1,5 do cb.onUpdate(0.1)end
    check(api.status().state=="closed")
    o.managed=true;o.spawned=true;o.attached=true;o.retainedAttached=true;o.worldPresent=true;o.populationPresent=true;o.pose=copy(origin)
    check(api.start(origin));for _=1,5 do cb.onUpdate(0.1)end
    check(api.status().generation==generation+1 and not api.status().movement.enabled)
    check(api.enableMovement(true));check(not api.move(target,generation) and d.calls==1)
end
do
    local api,d,o,cb,target=harness();api.enableMovement(true)
    check(api.move(target,api.status().generation));cb.onUpdate(0/0)
    check(api.status().movement.fault=="clock_unavailable" and api.status().movement.pending)
    check(not api.stop());for _=1,8 do cb.onUpdate(0.1)end
    check(d.deletes==0 and d.calls==1)
    o.pose=copy(target);for _=1,6 do cb.onUpdate(0.1)end
    check(not api.status().movement.pending and d.deletes>=1)
end
do
    local api,d,o,cb,target=harness();api.enableMovement(true)
    -- Reconcile a full pitch result after a read failure even though it exceeds
    -- the original spawn's five-degree readiness tolerance.
    target=copy(origin);target.qx=math.sin(math.rad(8)/2);target.qw=math.cos(math.rad(8)/2)
    check(api.move(target,api.status().generation));d.readFailure=true;cb.onUpdate(0.1)
    check(api.status().movement.pending and d.deletes==0)
    d.readFailure=false;o.pose=copy(target);for _=1,8 do cb.onUpdate(0.1)end
    check(api.status().state=="ready" and api.status().movement.state=="observed_after_fault")
    check(not api.move(origin,api.status().generation),"fault must prevent further applications")
    api.stop();cb.onUpdate(0.1);check(d.deletes>=1)
end
do
    local api,d,o,cb,target=harness();api.enableMovement(true);d.throwApplication=true
    check(not api.move(target,api.status().generation));check(not api.stop());cb.onUpdate(0.1)
    check(d.deletes==0 and api.status().movement.pending and d.calls==1)
    o.pose=copy(target);for _=1,6 do cb.onUpdate(0.1)end
    check(d.deletes>=1 and d.calls==1)
end
do
    local api,d,o,cb,target=harness();api.enableMovement(true);check(api.move(target,api.status().generation))
    o.occupants={{parent=ID,child=PLAYER,slot="seat_front_left"}};o.onFoot=false
    o.playerMount={parent=ID,child=PLAYER,slot="seat_front_left"};o.pose=copy(target)
    api.stop();for _=1,6 do cb.onUpdate(0.1)end
    check(d.deletes==0 and api.status().movement.pending)
    o.occupants={};o.onFoot=true;o.playerMount={};for _=1,6 do cb.onUpdate(0.1)end
    check(d.deletes>=1 and not api.status().movement.pending)
end
-- Test the real adapter's final pause/identity/generation gate and full quaternion.
package.loaded.engine=nil;local Engine=require("engine")
local carId={hash=ID.."ULL"};local playerId={hash=PLAYER.."ULL"}
local data={calls=0,paused=false};local player,actor,system={},{},{}
function player:GetEntityID()return playerId end
function player:IsAttached()return true end
function player:CP2077VehicleProbe_DefaultAppearance()return descriptor.appearance end
function actor:GetEntityID()return carId end
function actor:IsAttached()return true end
function actor:GetRecordID()return descriptor.record end
function actor:CP2077VehicleProbe_Appearance()return descriptor.appearance end
function actor:CP2077VehicleProbe_ColorVariant()return "None" end
function actor:CP2077VehicleProbe_ApplyPose(p,generation,request,position,q,expectedAppearance)
    check(p==player and generation==9 and request==1 and position.x==10.3 and q.i~=0 and q.k==0
        and expectedAppearance==descriptor.appearance,"native pose arguments preserve frozen descriptor and full quaternion")
    data.calls=data.calls+1;return true
end
function system:IsReady()return true end
function system:GetEntity()return actor end
function system:IsManaged()return true end
function system:IsSpawned()return true end
function system:IsSpawning()return false end
Game={GetPlayer=function()return player end,GetDynamicEntitySystem=function()return system end,FindEntityByID=function()return actor end,
    GetSystemRequestsHandler=function()if data.pauseFailure then error("pause unavailable")end
        return{IsGamePaused=function()return data.paused end,IsPreGame=function()return false end}end}
CName={new=function(value)return value end};TweakDBID={new=function(value)return value end}
Vector4={new=function(x,y,z,w)return{x=x,y=y,z=z,w=w}end}
Quaternion={new=function(i,j,k,r)return{i=i,j=j,k=k,r=r}end}
local engine=Engine.new(9);engine.id=carId;engine.key=ID;engine.creator=PLAYER;engine.system=system;engine.appearance=descriptor.appearance
local target=copy(origin);target.x=10.3;target.qx=math.sin(math.rad(6)/2);target.qw=math.cos(math.rad(6)/2)
data.paused=true;check(not engine:applyPose(ID,PLAYER,9,1,target) and data.calls==0)
data.paused=nil;check(not engine:applyPose(ID,PLAYER,9,1,target) and data.calls==0)
data.pauseFailure=true;check(not engine:applyPose(ID,PLAYER,9,1,target) and data.calls==0)
data.pauseFailure=false;data.paused=false
check(not engine:applyPose(ID,PLAYER,8,1,target) and data.calls==0,"scope failure is definite pre-native rejection")
check(not engine:applyPose("12",PLAYER,9,1,target) and data.calls==0)
check(not engine:applyPose(ID,"13",9,1,target) and data.calls==0)
playerId.hash="14ULL";check(not engine:applyPose(ID,PLAYER,9,1,target) and data.calls==0)
playerId.hash=PLAYER.."ULL";check(engine:applyPose(ID,PLAYER,9,1,target) and data.calls==1)
package.loaded.engine=originalEngine;print=originalPrint
print("vehicle_movement_integration: "..checks.." checks passed")
