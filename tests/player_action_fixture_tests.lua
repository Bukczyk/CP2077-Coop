local root=assert(arg[1])
assert(loadfile(root.."/experiments/player-locomotion/capture_fixture.lua"))
local originalIo=io
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
local function fixture(stale)
    local f={session="1ULL",self=2,host=1,phase=4,attached=true,paused=false,
        ready=true,spawned=false,managed=false,spawning=false,actorAttached=false,
        spawns=0,despawns=0,actorKey="100ULL",inputs={}}
    if stale then f.request={version=1,mode="action-fixture",session="1",request="stale"} end
    local events={}
    registerForEvent=function(n,fn)events[n]=fn end
    io={open=function(_,mode)
        if mode=="w" then return {write=function()end,close=function()end} end
        if not f.request then return nil end
        return {read=function()return "request"end,close=function()end}
    end}
    json={decode=function()return f.request end,encode=function(value)f.receipt=value;return "receipt"end}
    spdlog={info=function()end}
    CName={new=function(v)return v end};ResRef={FromName=function(v)return v end}
    Vector4={new=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end}
    Quaternion={new=function()return {}end};EulerAngles={new=function()return {}end}
    WorldTransform={new=function()return {}end,SetPosition=function()end,SetOrientationEuler=function()end}
    NewObject=function()return {}end;IsDefined=function(v)return v~=nil end
    StaticEntitySpec={new=function()return {}end}
    local actor={IsAttached=function()return f.actorAttached end,GetEntityID=function()return {hash=f.actorKey}end,
        SetWorldTransform=function()end,QueueEvent=function(_,event)f.inputs[#f.inputs+1]=event end}
    local system={IsReady=function()return f.ready end,
        SpawnEntity=function(_,spec)
            check(spec.templatePath=="base\\cp2077coop\\entities\\player_actions_fixture.ent","fixed fixture only")
            f.spawns=f.spawns+1;f.managed=true;f.spawning=true;return {hash="100ULL"}
        end,GetEntity=function()return f.spawned and actor or nil end,
        IsManaged=function()return f.managed end,IsSpawned=function()return f.spawned end,
        IsSpawning=function()return f.spawning end,
        DespawnEntity=function(_,id)
            check(id.hash=="100ULL","despawn exact owned token")
            f.despawns=f.despawns+1;f.managed=false;f.spawned=false;f.actorAttached=false;return true
        end}
    Game={GetPlayer=function()return {IsAttached=function()return f.attached end}end,
        CP2077Session_Self=function()return f.self end,CP2077Session_Host=function()return f.host end,
        CP2077Session_Session=function()return f.session end,CP2077Session_Phase=function()return f.phase end,
        GetSystemRequestsHandler=function()return {IsGamePaused=function()return f.paused end}end,
        GetStaticEntitySystem=function()return system end,FindEntityByID=function()return f.spawned and actor or nil end}
    assert(loadfile(root.."/experiments/player-locomotion/action_fixture.lua"))()
    function f:tick(n)for _=1,n or 1 do events.onUpdate(0.05)end end
    function f:arm(nonce)self.request={version=1,mode="action-fixture",session="1",request=nonce or "new"}end
    function f:attach()self.spawned=true;self.spawning=false;self.actorAttached=true end
    return f
end
for _,change in ipairs({function(f)f.self=f.host end,function(f)f.session="2ULL"end,
    function(f)f.paused=true end,function(f)f.paused=nil end,function(f)f.attached=false end,
    function(f)f.phase=0 end}) do
    local f=fixture();f:arm();change(f);f:tick(5);check(f.spawns==0,"invalid context rejected")
end
do
    local f=fixture(true);f:tick(5);check(f.spawns==0,"stale request skipped")
end
do
    local f=fixture();f:arm();f:tick();f:attach();f:tick(1100)
    local crouch,aim,neutral=false,false,false
    for _,event in ipairs(f.inputs)do
        if event.key=="cp_coop_stance" and event.value==1 then crouch=true end
        if event.key=="cp_coop_weapon_pose" and event.value==8 then aim=true end
        if event.key=="cp_coop_weapon_weight" and event.value==0 then neutral=true end
    end
    check(crouch and aim and neutral,"fixed crouch/aim/neutral sequence submitted")
    check(f.spawns==1 and f.despawns==1 and f.receipt.status=="removed","bounded sequence removes exact actor")
end
do
    local f=fixture();f:arm();f:tick(300);f:arm("second");f:tick(10)
    check(f.spawns==1 and f.despawns==0,"unconfirmed asynchronous token never replaced")
    f:attach();f:tick(2);check(f.despawns==1,"late spawn is removed before a replacement")
end
do
    local f=fixture();f:arm();f:tick();f:attach();f.actorKey="999ULL"
    local ok=pcall(function()f:tick()end)
    check(not ok and f.despawns==0,"foreign actor cannot be posed or removed")
end
io=originalIo
print("player action fixture: PASS ("..checks.." checks, context/identity/cleanup and bounded local poses)")
