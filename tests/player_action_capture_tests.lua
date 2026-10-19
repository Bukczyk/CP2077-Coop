local root=assert(arg[1]);local originalIo=io
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
    local player={CP2077Capture_Ready=function()return true end,
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
    Game={GetPlayer=function()return player end,CP2077Session_Phase=function()return 4 end,
        GetSystemRequestsHandler=function()return {IsGamePaused=function()return f.paused end}end,
        CP2077Session_Self=function()return 2 end,CP2077Session_Session=function()return '1ULL' end}
    assert(loadfile(root..'/experiments/player-locomotion/capture_fixture.lua'))()
    function f:tick(n)for _=1,n or 1 do events.onUpdate(.25)end end
    return f
end
do
    local f=fixture();f:tick(3)
    check(f.outputs[1].visuals==nil and f.outputs[2].visuals[1].mask=='18446744073709551615','stable metadata retains the exact opaque native mask')
    check(f.visualCalls==2 and f.writes==3,'two matching observations qualify metadata while essential state continues')
    f.held=false;f:tick();f.held=true;f:tick(2)
    check(f.visualCalls==4,'redraw allows a fresh assembled-weapon observation')
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
