local root=assert(arg[1])
local originalIo=io
local checks=0
local function check(v,s)checks=checks+1;assert(v,s)end
local function fixture(stale)
    local f={self=2,host=1,session="1ULL",phase=4,actor="100ULL",attached=true,paused=false,moves=0,captures=0}
    if stale then f.request={version=1,mode="place-observer",session="1",request="old"} end
    local events={}
    registerForEvent=function(n,fn)events[n]=fn end
    io={open=function(name,mode)
        if mode=="w" then return {write=function()end,close=function()end} end
        if not f.request then return nil end
        return {read=function()return "request"end,close=function()end}
    end}
    json={decode=function()return f.request end,encode=function(value)f.receipt=value;return "receipt"end}
    spdlog={info=function()end}
    GetMod=function()return {startCapture=function()f.captures=f.captures+1 end}end
    local player={IsAttached=function()return f.attached end,GetEntityID=function()return {hash=f.actor}end}
    Game={GetPlayer=function()return player end,
        CP2077Session_Self=function()return f.self end,CP2077Session_Host=function()return f.host end,
        CP2077Session_Session=function()return f.session end,CP2077Session_Phase=function()return f.phase end,
        GetSystemRequestsHandler=function()return {IsGamePaused=function()return f.paused end}end,
        GetTeleportationFacility=function()return {Teleport=function(_,p,v,a)
            check(p==player and v.x==-813 and v.y==817.5 and v.z==24.4042 and a.yaw==0,"only the fixed observing actor/view")
            f.moves=f.moves+1
        end}end}
    Vector4={new=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end}
    EulerAngles={new=function(r,p,y)return {yaw=y}end}
    assert(loadfile(root.."/experiments/player-locomotion/observer.lua"))()
    function f:tick(n)for _=1,n or 1 do events.onUpdate(0.05)end end
    function f:arm(nonce)self.request={version=1,mode="place-observer",session="1",request=nonce or "new"}end
    return f
end
for _,change in ipairs({function(f)f.self=f.host end,function(f)f.session="2ULL" end,
    function(f)f.paused=nil end,function(f)f.paused=true end,function(f)f.attached=false end,
    function(f)f.phase=0 end}) do
    local f=fixture();f:arm();change(f);f:tick()
    check(f.moves==0 and f.receipt.accepted==false,"invalid/unknown context cannot move a player")
end
do
    local f=fixture();f:arm();f:tick(200)
    check(f.moves==1 and f.captures==1,"one request places once; never hold/teleport every update")
    check(f.receipt.request=="new" and f.receipt.accepted==true,"exact request receipt reports submission only")
    f:arm("next");f:tick(5);check(f.moves==2,"another explicit request can place again")
end
do
    local f=fixture(true);f:tick(10);check(f.moves==0,"stale request at module load cannot move observer")
end
do
    local f=fixture()
    for i=1,20 do f:arm("nonce"..i);f:tick(5)end
    check(f.moves==16,"request count stays bounded")
end
io=originalIo
print("player_locomotion_observer: PASS ("..checks.." checks; explicit single placement, no persistent movement lock)")
