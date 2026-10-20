local root=assert(arg[1]);local originalIo=io
local function fixture()
    local f={rows={},logs={},events={},hooks={},ground=true,owner='1ULL',generationCalls=0,phase=4}
    registerForEvent=function(name,fn)f.events[name]=fn end
    ObserveAfter=function(name,method,fn)assert(method=='OnUpdate');f.hooks[name]=fn end
    CName={new=function(v)return v end}
    Reflection={GetClass=function(name)return {GetFunction=function(_,method)
        return {GetParameters=function()return method=='IsOnGround' and {} or {1,2,3}end,
            IsNative=function()return true end,GetReturnType=function()return {GetName=function()return 'Bool'end}end}
    end}end}
    json={encode=function(row)f.pending=row;return string.rep('x',20)end}
    spdlog={info=function(v)f.logs[#f.logs+1]=v end}
    io={open=function(path,mode)assert(path=='ground.jsonl' and mode=='a');return {
        seek=function()return f.fileBytes or 0 end,close=function()end,
        write=function(_,line)f.rows[#f.rows+1]=f.pending;f.fileBytes=(f.fileBytes or 0)+#line end}end}
    local player={CP2077Capture_Ready=function()return true end,GetEntityID=function()return {hash=f.numeric and 1 or '1ULL'}end,
        GetWorldPosition=function()return {x=f.badPosition and 0/0 or 1,y=2,z=3}end}
    Game={GetPlayer=function()return player end,CP2077Session_Phase=function()return f.phase end,
        GetSystemRequestsHandler=function()return {IsGamePaused=function()return f.paused==true end}end,
        CP2077Session_Self=function()return 2 end,CP2077Session_Epoch=function()return 3 end,
        CP2077Session_Session=function()return '4ULL'end,CP2077Session_SelfEntity=function()return '9007199254740993ULL'end,
        CP2077Session_Generation=function()
            f.generationCalls=f.generationCalls+1
            return f.scopeFlip and f.generationCalls%2==0 and '3ULL' or '2ULL'
        end}
    PlayerPuppet={GetCurrentLocomotionState=function()return f.ground and 'Default' or 'Jump'end}
    local interface={executionOwner={IsAttached=function()return true end,GetEntityID=function()return {hash=f.owner}end},
        IsOnGround=function()if f.failGround then error('unavailable')end;return f.ground end}
    f.api=assert(loadfile(root..'/experiments/player-locomotion/ground_probe.lua'))();f.events.onInit()
    function f:tick(dt,name)
        self.events.onUpdate(dt or .21)
        self.hooks[name or 'LocomotionEventsTransition']({},dt or .21,{},interface)
    end
    return f
end
do
    local f=fixture();f:tick();f.ground=false;f:tick(.01,'LocomotionAirEvents');f.ground=true;f:tick(.01,'CrouchEvents')
    assert(#f.rows==3 and f.rows[1].grounded==true and f.rows[2].grounded==false and f.rows[3].grounded==true)
    assert(f.rows[2].observer=='LocomotionAirEvents' and f.rows[3].observer=='CrouchEvents','hook closure kept the wrong class')
    assert(f.rows[1].localEntity=='1' and f.rows[1].sessionEntity=='9007199254740993','opaque identities rounded/mixed')
    f:tick(.01);assert(#f.rows==3,'stable state logged every frame')
    f:tick(.21);assert(#f.rows==4,'bounded pulse lost')
end
for _,field in ipairs({'numeric','scopeFlip','paused','badPosition','failGround'})do
    local f=fixture();f[field]=true;f:tick();assert(#f.rows==0,field..' produced an unqualified ground value')
end
do local f=fixture();f.owner='2ULL';f:tick();assert(#f.rows==0,'foreign execution owner admitted')end
do local f=fixture();f.phase=3;f:tick();assert(#f.rows==0,'inactive session admitted')end
do local f=fixture();f:tick(301);assert(#f.rows==0 and f.api.status().stopped,'time bound bypassed')end
do local f=fixture();f.fileBytes=1048576;f:tick();assert(#f.rows==0 and f.api.status().stopped,'persistent byte bound bypassed')end
do local f=fixture();for i=1,1805 do f.ground=i%2==0;f:tick(.01)end;assert(#f.rows==1800 and f.api.status().stopped,'row bound bypassed')end
do local f=fixture();for i=1,36001 do f:tick(.0001)end;assert(f.api.status().stopped,'callback bound bypassed')end
io=originalIo
print('PRIVATE ground probe: exact identity, false/unavailable separation, scope, pulse and persistent bounds PASS')
