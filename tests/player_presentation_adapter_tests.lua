local root=assert(arg[1]);package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local M=require("player_presentation")
local valid="1|123|456|12|2|2|16ac119774|2"
local value=assert(M.decode(valid));assert(value.record=="16ac119774" and value.revision==123)
for _,raw in ipairs({"|"..valid,valid.."|",valid:gsub("123","-1"),valid:gsub("16ac119774","16ac119775"),
    valid:gsub("|2|2|16ac","|2|1|16ac"),valid:gsub("|2$","|3"),valid:gsub("|12|","|9007199254740993|")})do
    assert(M.decode(raw)==nil,"malformed native presentation accepted: "..raw)
end
assert(M.decode("1|1|1|0|0|0|0000000000|0"))
assert(M.decode("0|1|1|30001|2|3|0100000001|1"))
CName={new=function(v)return v end};NewObject=function()return {}end
local calls,events={},{}
local actor={GetEntityID=function()return {hash="9007199254740993ULL"}end,IsAttached=function()return true end,
    CP2077Fixture_SetWeaponVisible=function(_,v)calls[#calls+1]=v;return true end,
    QueueEvent=function(_,v)events[#events+1]=v end}
local state={}
assert(M.apply(actor,state,value,{phase=0})=="presentation_submitted" and calls[1]==true)
local before=#events
value.sequence=457;value.ageMs=0
M.apply(actor,state,value,{phase=0});assert(#events==before and #calls==1,"repair replayed commands")
M.apply(actor,state,value,{phase=1});assert(#events>before and #calls==1)
value.fresh=false;M.apply(actor,state,value,{phase=1});assert(calls[2]==false)
before=#events;M.apply(actor,state,value,{phase=1});assert(#events==before and #calls==2)
value.fresh=true;M.apply(actor,state,value,{phase=1});assert(calls[3]==true,"fresh recovery failed")
local foreign={GetEntityID=function()return {hash="9007199254740994ULL"}end,IsAttached=function()return true end}
assert(M.apply(foreign,state,value,{phase=0})=="actor_changed" and #calls==3)
local failed={};actor.CP2077Fixture_SetWeaponVisible=function()calls[#calls+1]="rejected";return false end
before=#events;M.apply(actor,failed,value,{phase=0});M.apply(actor,failed,value,{phase=0})
assert(#events==before and #calls==4,"failed visibility mutated actor or retried every frame")

-- Independent synthetic resource observation, matching the fixed local recipe.
local prefix="base\\weapons\\firearms\\shotgun_dual\\"
local rows={
    {kind="rig",name="Receiver",path=prefix.."rig\\w_shotgun_dual__rcv1.rig"},
    {kind="rig",name="Barrel",path=prefix.."rostovic_igla\\rig\\w_shotgun_dual__rostovic_igla__base1.rig"},
    {kind="rig",name="Magazine",path=prefix.."rostovic_satara\\rig\\w_shotgun_dual__rostovic_satara__mag_std.rig"}}
local meshes={
    {"rostovic_igla","base1_01","Barrel","pimp1"},
    {"rostovic_satara","rcv1_01","Receiver","pimp1_igla"},
    {"rostovic_satara","mag_std_01_left_01","Magazine","default"},
    {"rostovic_satara","mag_std_01_right_01","Magazine","default"},
    {"rostovic_satara","rcv1_01_decal_n01_default","Receiver","default"}}
for _,m in ipairs(meshes)do
    rows[#rows+1]={kind="skinned",enabled=true,path=prefix..m[1].."\\entities\\meshes\\w_shotgun_dual__"..m[1].."__"..m[2]..".mesh",
        parent=m[3],skin=m[3],appearance=m[4],mask="18446744073709551615ULL"}
end
assert(M.iglaVisuals(rows))
rows[4].appearance="pimp2";assert(not M.iglaVisuals(rows));rows[4].appearance="pimp1"
rows[4].mask=18446744073709551615;assert(not M.iglaVisuals(rows));rows[4].mask="18446744073709551615ULL"
rows[9]={kind="static",enabled=true,path="base\\scope.mesh"};assert(not M.iglaVisuals(rows));rows[9]=nil
local pushes={};local nativeRecord={semantic="igla"};local empty={semantic="empty"}
TweakDBID={new=function()return empty end}
Game={CP2077Session_Session=function()return "9007199254740993ULL"end,CP2077Session_Epoch=function()return 1 end,
    CP2077Presentation_Version=function()return 32773 end,
    CP2077Session_Generation=function()return "9007199254740994ULL"end,
    CP2077Presentation_IsIgla=function(v)return v.semantic=="igla"end,
    CP2077Presentation_RecordsEqual=function(a,b)return a.semantic==b.semantic end,
    CP2077Presentation_Push=function(session,epoch,generation,stance,weapon,record,aim)
        assert(type(session)=="string" and type(generation)=="string" and type(record)=="table")
        pushes[#pushes+1]={stance=stance,weapon=weapon,record=record,aim=aim};return 0
    end}
local ready,held=true,true
local player={CP2077Capture_Ready=function()return ready end,CP2077Capture_HasWeapon=function()return held end,
    CP2077Capture_Crouched=function()return true end,CP2077Capture_Aiming=function()return true end,
    CP2077Capture_HeldRecord=function()return nativeRecord end,CP2077Capture_HeldVisuals=function()return rows end}
M.capture(player,0);assert(pushes[1].weapon==3,"unstable resources were marked supported")
M.capture(player,.06);assert(pushes[2].weapon==2 and pushes[2].record==nativeRecord)
ready=false;M.capture(player,.12);assert(pushes[3].stance==0 and pushes[3].weapon==0 and pushes[3].record==empty)
ready=true;M.capture(player,.18);assert(pushes[4].weapon==3,"unavailable capture did not reset stability")
held=false;M.capture(player,.24);assert(pushes[5].weapon==1 and pushes[5].record==empty and pushes[5].aim==1)
print("presentation adapter: PASS (opaque identity/record, exact visuals, repairs, stale release and actor ownership)")
