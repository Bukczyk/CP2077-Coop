local root=assert(arg[1]);local originalIo=io
package.path=root..'/experiments/player-locomotion/?.lua;'..package.path
local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local function fixture()
    local f={held=true,paused=false,writes=0,fileSize=0,visualCalls=0,outputs={}}
    local events={}
    registerForEvent=function(name,fn)events[name]=fn end
    json={encode=function(sample)f.sample=sample;return 'sample' end}
    spdlog={info=function()f.error=true end}
    io={open=function(name,mode)
        check(name=='capture.jsonl' and mode=='a','only the bounded private log is written')
        return {seek=function()return f.fileSize end,close=function()end,
            write=function(_,line)f.fileSize=f.fileSize+#line;f.writes=f.writes+1;f.outputs[#f.outputs+1]=f.sample end}
    end}
    local player
    player={CP2077Capture_Ready=function()return true end,
        IsAttached=function()return true end,
        GetEntityID=function()return {hash=f.numericEntity and 9007199254740993 or '9007199254740993ULL'}end,
        GetWorldPosition=function()if f.failPose then error('pose unavailable')end;return {x=f.badPose and 0/0 or 12,y=-4,z=30}end,
        GetWorldOrientation=function()return {ToEulerAngles=function()return {yaw=45}end}end,
        GetWorldForward=function()return {x=0,y=1,z=0}end,
        GetFPPCameraComponent=function()
            if f.failCamera then error('unavailable')end
            return {GetLocalToWorld=function()return {}end,
                IsEnabled=function()return not f.disabledCamera end,
                GetEntity=function()return f.foreignCamera and
                    {IsAttached=function()return true end,GetEntityID=function()return {hash='9007199254740992ULL'}end} or player end}
        end,
        CP2077Capture_HeldTemplate=function()return 'base/weapon_root.ent' end,
        CP2077Capture_HeldAppearance=function()return 'variant' end,
        CP2077Capture_Crouched=function()return false end,CP2077Capture_Aiming=function()return true end,
        CP2077Capture_HasWeapon=function()return f.held end,CP2077Capture_HeldRecord=function()return 'native-record' end,
        CP2077Capture_HeldVisuals=function()
            f.visualCalls=f.visualCalls+1
            if f.failVisuals then error('unavailable') end
            return {{name='body',kind='skinned',path='base/weapon.mesh',appearance='variant',
                enabled=true,mask=f.badMask and 1 or '18446744073709551615ULL',localTransform={}}}
        end}
    Game={GetPlayer=function()return player end,CP2077Session_Phase=function()
        f.phaseCalls=(f.phaseCalls or 0)+1
        return f.phaseFlip and f.phaseCalls%2==0 and 3 or 4
    end,
        GetCameraSystem=function()error('active camera fallback must not be read')end,
        GetSystemRequestsHandler=function()return {IsGamePaused=function()return f.paused end}end,
        CP2077Session_Self=function()return 2 end,CP2077Session_Session=function()return '1ULL' end,
        CP2077Session_Epoch=function()return 3 end,CP2077Session_SelfEntity=function()return '9007199254740999ULL' end,
        CP2077Session_Generation=function()
            f.generationCalls=(f.generationCalls or 0)+1
            return f.scopeFlip and f.generationCalls%2==0 and '9007199254740995ULL' or '9007199254740994ULL'
        end}
    PlayerPuppet={GetCurrentLocomotionState=function()return 'Jump' end}
    Matrix={IsOk=function()return true end,GetDirectionVector=function()return {x=0,y=1,z=0}end}
    assert(loadfile(root..'/experiments/player-locomotion/capture_fixture.lua'))()
    function f:tick(n)for _=1,n or 1 do events.onUpdate(.25)end end
    return f
end
do
    local f=fixture();f:tick(3)
    check(f.outputs[1].visuals==nil and f.outputs[2].visuals[1].mask=='18446744073709551615','stable metadata retains the exact opaque native mask')
    check(f.visualCalls==2 and f.writes==3,'two matching observations qualify metadata while essential state continues')
    check(f.outputs[1].cameraAim.yawDegrees==0 and f.outputs[1].cameraAim.pitchDegrees==0,'read-only camera angles captured without changing core state')
    local pose=f.outputs[1].sourcePose
    check(f.outputs[1].sourcePoseStatus=='observed' and pose.x==12 and pose.y==-4 and pose.z==30 and pose.yawDegrees==45,
        'same-callback actual position/body heading retained')
    check(pose.localEntity=='9007199254740993' and pose.sessionEntity=='9007199254740999'
        and pose.generation=='9007199254740994' and pose.epoch==3 and pose.locomotion=='Jump',
        'local entity, network entity and scope must remain exact and separate')
    check(f.outputs[3].observation==3 and f.outputs[3].captureRevision=='20261020-source-pose-1','bounded source ordinals retained')
    f.held=false;f:tick();f.held=true;f:tick(2)
    check(f.visualCalls==4,'redraw allows a fresh assembled-weapon observation')
end
for _,field in ipairs({'failPose','badPose','numericEntity','scopeFlip','phaseFlip'})do
    local f=fixture();f[field]=true;f:tick(3)
    check(f.writes==3 and f.outputs[1].sourcePose==nil and f.outputs[1].sourcePoseStatus=='unavailable' and not f.error,
        'invalid/unavailable/changing source scope must not stop essential action observations')
end
do
    local f=fixture();f.failCamera=true;f:tick(3)
    check(f.writes==3 and f.outputs[1].cameraAim==nil and not f.error,'camera failure cannot stop essential action capture')
end
for _,field in ipairs({'disabledCamera','foreignCamera'})do
    local f=fixture();f[field]=true;f:tick(3)
    check(f.writes==3 and f.outputs[1].cameraAim==nil and not f.error,
        'disabled/foreign camera rejected while essential action state continues')
end
do
    local f=fixture();f.failVisuals=true;f:tick(25)
    check(f.visualCalls==10 and f.writes==25 and not f.error,'optional unavailable probe stays bounded and never stops source capture')
end
do
    local f=fixture();f.badMask=true;f:tick()
    check(f.outputs[1].visuals==nil and f.writes==1,'rounded native mask rejected without losing core state')
end
do
    local f=fixture();f.paused=true;f:tick();f.paused=nil;f:tick()
    check(f.writes==0,'paused or unknown pause state is not captured')
end
do
    local f=fixture();f.fileSize=2*1024*1024;f:tick(3)
    check(f.writes==0,'persistent file bound applies across reloads')
end
io=originalIo
print('player action capture: PASS ('..checks..' checks, native identity, optional probe isolation and bounds)')
