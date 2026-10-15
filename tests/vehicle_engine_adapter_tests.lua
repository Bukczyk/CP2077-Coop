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
    GetSystemRequestsHandler=function() return {IsGamePaused=function() return data.paused end,IsPreGame=function() return false end} end}
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
check(not e:request("9007199254740993","100","mount","seat_front_left") and data.requests==0)
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

-- Lifecycle observations and deletion belong to the system that created the
-- token. A new ready system cannot certify an old creator's disappearance.
local baseGet,baseDelete,baseReady=system.GetEntity,system.DeleteEntity,system.IsReady
local baseFind=Game.FindEntityByID
local function freshFixture()
    system.GetEntity,system.DeleteEntity,system.IsReady=baseGet,baseDelete,baseReady
    Game.GetDynamicEntitySystem=function()return system end
    Game.FindEntityByID=baseFind
    data.present,data.attached,data.managed,data.spawned,data.spawning=false,false,false,false,false
    data.mounts,data.events,data.cameraFailure,data.deleted={},{},false,0
    local engine=Engine.new();local fixture=Fixture.new(engine,desc)
    check(fixture:start(target))
    for _=1,5 do fixture:step(0.1,false)end
    check(fixture.state=="ready" and engine.retained==actor)
    return engine,fixture
end
do
    local engine,fixture=freshFixture()
    local replacementCalls=0
    local replacement={IsReady=function()return true end,GetEntity=function()return nil end,
        IsManaged=function()return false end,IsSpawned=function()return false end,IsSpawning=function()return false end,
        DeleteEntity=function()error("replacement system must not delete original token")end}
    Game.GetDynamicEntitySystem=function()replacementCalls=replacementCalls+1;return replacement end
    fixture:stop();fixture:step(0.1,false)
    check(data.deleted==1 and replacementCalls==0,"delete uses pinned creator")
    data.attached,data.managed=false,false
    Game.FindEntityByID=function()return nil end
    for _=1,6 do fixture:step(0.1,false)end
    check(fixture.state~="closed" and data.spawned and data.present,
        "empty replacement cannot certify original population removal")
    data.present,data.spawned=false,false
    for _,unknown in ipairs({{value=false},{},{value="true"},{value=1}})do
        system.IsReady=function()return unknown.value end
        for _=1,6 do fixture:step(0.1,false)end
        check(fixture.state~="closed","unready or unknown original creator retains ownership")
    end
    system.IsReady=baseReady
    fixture:step(0.1,false);check(fixture.state~="closed","known recovery starts fresh absence interval")
    for _=1,4 do fixture:step(0.1,false)end
    check(fixture.state=="closed" and replacementCalls==0,"only original creator absence completes cleanup")
end

-- A rejected later wrapper must not overwrite the first exact attached handle.
-- Cover nil and truthy malformed values as well as valid detached/attached ones.
for _,sample in ipairs({{}, {value="false"}, {value=0}, {value=false}, {value=true}})do
    local engine,fixture=freshFixture()
    fixture:stop();fixture:step(0.1,false);check(data.deleted==1)
    local wrapperAttached=sample.value
    local wrapper=setmetatable({IsAttached=function()return wrapperAttached end},{__index=actor})
    Game.FindEntityByID=function()return wrapper end
    system.GetEntity=function()return wrapper end
    fixture:step(0.1,false)
    check(engine.retained==actor,"later wrapper cannot replace first retained actor")
    if type(sample.value)~="boolean" then
        check(fixture.state=="observation_unavailable","malformed attachment rejected before mutation")
    end
    wrapperAttached=false;Game.FindEntityByID=function()return nil end
    system.GetEntity=function()return nil end
    data.managed,data.spawned=false,false
    for _=1,6 do fixture:step(0.1,false)end
    check(fixture.state~="closed" and actor:IsAttached(),"first attached actor blocks false absence")
    data.attached=false
    for _=1,5 do fixture:step(0.1,false)end
    check(fixture.state=="closed","explicit original detach and absent lookups permit cleanup")
end
system.GetEntity,system.DeleteEntity,system.IsReady=baseGet,baseDelete,baseReady
Game.GetDynamicEntitySystem=function()return system end;Game.FindEntityByID=baseFind

-- Actual init + Engine + Fixture regression: a fresh pause/context change after
-- the last ready sample must reject before native request and leave no pending
-- owner. The next valid request can complete through its event + relationship.
local function restoreRequestContext()
    data.paused,data.preGame,data.playerAttached=false,false,true
    data.handlerMissing,data.handlerThrow,data.pauseThrow,data.preGameThrow=false,false,false,false
    data.present,data.attached,data.managed,data.spawned,data.spawning=true,true,true,true,false
end
function player:IsAttached()return data.playerAttached end
Game.GetSystemRequestsHandler=function()
    if data.handlerThrow then error("handler unavailable")end
    if data.handlerMissing then return nil end
    return {IsGamePaused=function()if data.pauseThrow then error("pause read failed")end return data.paused end,
        IsPreGame=function()if data.preGameThrow then error("pregame read failed")end return data.preGame end}
end
function actor:CP2077VehicleProbe_Request(p,slot,mounting)
    check(p==player and slot=="seat_front_left")
    data.requests=data.requests+1
    if data.nativeThrow then error("unknown native request outcome")end
    return true
end
local function actualEntrypoint()
    restoreRequestContext()
    data.present,data.attached,data.managed,data.spawned=false,false,false,false
    data.mounts,data.events,data.cameraFailure,data.nativeThrow={}, {},false,false
    data.created,data.deleted,data.requests=0,0,0
    local callbacks={};registerForEvent=function(name,fn)callbacks[name]=fn end
    local api=dofile(root.."/experiments/vehicle-presentation/init.lua")
    check(api.start(target));for _=1,6 do callbacks.onUpdate(0.1)end
    check(api.status().state=="ready" and api.enableRequests(true))
    return api,callbacks
end
local savedPrint=print;print=function()end
for _,case in ipairs({{key="paused",value=true},{key="paused"},{key="paused",value="false"},
    {key="preGame",value=true},{key="preGame"},{key="preGame",value=0},
    {key="handlerMissing",value=true},{key="handlerThrow",value=true},
    {key="pauseThrow",value=true},{key="preGameThrow",value=true},
    {key="playerAttached",value=false},{key="playerAttached"},
    {key="managed"},{key="spawned"},{key="spawning"}})do
    local api,callbacks=actualEntrypoint()
    data[case.key]=case.value -- change after the last good onUpdate sample
    local accepted,reason=api.request("mount","seat_front_left")
    check(not accepted and reason=="request_rejected" and data.requests==0,
        "fresh inactive/unknown context must reject before native request: "..case.key)
    check(not api.status().pending and api.status().state=="ready","preflight rejection must not quarantine")
    restoreRequestContext()
    check(api.request("mount","seat_front_left") and data.requests==1 and api.status().pending,
        "known valid context must recover without a new fixture")
    data.mounts={{parent=carId,child=playerId,slot="seat_front_left"}}
    data.events={{serial=1,child=playerId,slot="seat_front_left",mounting=true}}
    callbacks.onUpdate(0.1)
    check(not api.status().pending and api.status().state=="ready","exact completion still observed")
    data.paused=true
    check(not api.request("unmount","seat_front_left") and data.requests==1 and not api.status().pending,
        "fresh pause also rejects unmount before submission")
    data.paused=false
    check(api.request("unmount","seat_front_left") and data.requests==2)
    data.mounts={};data.events={{serial=2,child=playerId,slot="seat_front_left",mounting=false}}
    callbacks.onUpdate(0.1)
    check(not api.status().pending and api.status().state=="ready","unmount recovery still observes both conditions")
end
do
    local api,callbacks=actualEntrypoint();data.nativeThrow=true
    local accepted,reason=api.request("mount","seat_front_left")
    check(not accepted and reason=="request_unresolved" and data.requests==1 and api.status().pending,
        "actual native exception must retain ambiguous ownership")
    check(not api.stop());callbacks.onUpdate(0.1)
    check(data.deleted==0 and api.status().pending,"unknown native outcome must hold cleanup")
end
print=savedPrint
-- Actual entrypoint regressions for fresh cosmetics and safe quarantined exit.
local cosmetic
local expectedRecord="Vehicle.v_standard2_archer_hella_player"
local function cosmeticValue(field)
    if cosmetic[field.."Throw"] then error(field.." unavailable")end
    return cosmetic[field]
end
function player:CP2077VehicleProbe_DefaultAppearance()return cosmeticValue("default")end
function actor:CP2077VehicleProbe_Appearance()return cosmeticValue("appearance")end
function actor:CP2077VehicleProbe_ColorVariant()return cosmeticValue("color")end
function actor:GetRecordID()return cosmetic.record end
function actor:CP2077VehicleProbe_Owned(p)
    -- Model the real native record rejection, not only the earlier loose shim.
    return p==player and data.managed and data.spawned and not data.spawning and cosmetic.record==expectedRecord
end
function actor:CP2077VehicleProbe_ReadSeats()return cosmetic.seats or data.mounts end
function actor:CP2077VehicleProbe_Request(p,slot,mounting,expectedAppearance)
    check(p==player and slot=="seat_front_left" and expectedAppearance=="hella_fixture_default",
        "native request lost frozen appearance or exact player/seat")
    data.requests=data.requests+1
    if data.nativeThrow then error("unknown native outcome")end
    return not cosmetic.nativeReject
end
local function restoreCosmetics()
    cosmetic={appearance="hella_fixture_default",color="None",default="hella_fixture_default",record=expectedRecord}
end
local function cosmeticEntrypoint()
    restoreCosmetics();return actualEntrypoint()
end
local function completeMount(api,callbacks)
    check(api.request("mount","seat_front_left"));data.mounts={{parent=carId,child=playerId,slot="seat_front_left"}}
    data.events={{serial=1,child=playerId,slot="seat_front_left",mounting=true}};callbacks.onUpdate(0.1)
    check(not api.status().pending and api.status().state=="ready")
end
print=function()end
for _,case in ipairs({{key="appearance",value="custom"},{key="appearance"},{key="appearance",value=false},
    {key="appearanceThrow",value=true},{key="color",value="custom"},{key="color"},{key="colorThrow",value=true},
    {key="default",value="new_default"},{key="default"},{key="defaultThrow",value=true}})do
    local api,callbacks=cosmeticEntrypoint();cosmetic[case.key]=case.value
    local accepted,reason=api.request("mount","seat_front_left")
    check(not accepted and reason=="request_rejected" and data.requests==0 and not api.status().pending,
        "fresh cosmetic preflight submitted unsafe mount: "..case.key)
    restoreCosmetics();completeMount(api,callbacks)
end
do
    local api=cosmeticEntrypoint();cosmetic.default="new_default";cosmetic.appearance="new_default"
    check(not api.request("mount","seat_front_left") and data.requests==0,"new record default replaced pinned descriptor")
end
for _,case in ipairs({{key="appearance",value="custom"},{key="appearance"},{key="appearanceThrow",value=true},
    {key="color",value="custom"},{key="color"},{key="colorThrow",value=true}})do
    local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks);cosmetic[case.key]=case.value
    callbacks.onUpdate(0.1);check(api.status().state=="appearance_mismatch","cosmetic failure discarded valid identity/seats")
    check(api.request("unmount","seat_front_left") and data.requests==2,"cosmetic quarantine blocked exact exit")
    data.events={{serial=2,child=playerId,slot="seat_front_left",mounting=false}};callbacks.onUpdate(0.1)
    check(api.status().pending,"event alone completed quarantined exit")
    data.mounts={};callbacks.onUpdate(0.1)
    check(not api.status().pending and api.status().state=="appearance_mismatch" and not api.status().cameraVerified)
    restoreCosmetics();callbacks.onUpdate(0.1)
    check(not api.request("mount","seat_front_left") and data.requests==2,"restoration cleared sticky cosmetic quarantine")
    api.stop();callbacks.onUpdate(0.1);check(data.deleted==1,"safe empty quarantined cleanup blocked")
end
do
    local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks)
    cosmetic.appearance="custom";callbacks.onUpdate(0.1);restoreCosmetics();callbacks.onUpdate(0.1)
    check(api.request("unmount","seat_front_left") and data.requests==2,"restored cosmetics must permit exact exit")
end
for _,method in ipairs({"CP2077VehicleProbe_Appearance","CP2077VehicleProbe_ColorVariant"})do
    local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks)
    local saved=actor[method];actor[method]=nil
    setmetatable(actor,{__index=function(_,key)if key==method then error("cosmetic binding lookup failed")end end})
    callbacks.onUpdate(0.1)
    check(api.status().state=="appearance_mismatch" and api.request("unmount","seat_front_left"),
        "cosmetic method lookup escaped failure isolation")
    data.events={{serial=2,child=playerId,slot="seat_front_left",mounting=false}};data.mounts={}
    callbacks.onUpdate(0.1);check(not api.status().pending and api.status().state=="appearance_mismatch")
    setmetatable(actor,nil);actor[method]=saved
end
for _,fresh in ipairs({false,true})do
    for _,wrong in ipairs({"wrong_record",false})do
        local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks)
        cosmetic.record=wrong
        if not fresh then callbacks.onUpdate(0.1)end
        check(not api.request("unmount","seat_front_left") and data.requests==1,"wrong record allowed exit")
        restoreCosmetics();callbacks.onUpdate(0.1)
        check(api.status().state=="record_mismatch" and not api.request("unmount","seat_front_left"),
            "fresh or observed hard record fault was forgotten")
        data.mounts={};api.stop();callbacks.onUpdate(0.1);check(data.deleted==0,"record restoration permitted cleanup")
    end
end
for _,seats in ipairs({{},{{parent=carId,child=zeroId,slot="seat_front_left"}},
    {{parent=zeroId,child=playerId,slot="seat_front_left"}},{{parent=carId,child=playerId,slot="seat_front_right"}},
    {{parent=carId,child=playerId,slot="seat_front_left"},{parent=carId,child=playerId,slot="seat_front_left"}}})do
    local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks)
    cosmetic.color="custom";callbacks.onUpdate(0.1);cosmetic.seats=seats -- player-side readback stays exact
    check(not api.request("unmount","seat_front_left") and data.requests==1 and not api.status().pending,
        "stale vehicle relationship was accepted")
end
do
    local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks)
    cosmetic.color="custom";callbacks.onUpdate(0.1);data.mounts={} -- last sample still mounted
    check(not api.request("unmount","seat_front_left") and data.requests==1 and not api.status().pending,
        "stale player relationship was accepted")
end
for _,unknown in ipairs({false,true})do
    local api,callbacks=cosmeticEntrypoint();completeMount(api,callbacks)
    cosmetic.color="custom";callbacks.onUpdate(0.1)
    data.nativeThrow=unknown;cosmetic.nativeReject=not unknown
    check(not api.request("unmount","seat_front_left") and data.requests==2)
    check(api.status().pending==unknown,"native rejection and unknown outcome were conflated")
    api.stop();callbacks.onUpdate(0.1);check(data.deleted==0)
end
print=savedPrint
print("vehicle_engine_adapter: "..checks.." checks passed")
