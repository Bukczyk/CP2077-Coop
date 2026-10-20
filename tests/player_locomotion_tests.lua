local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local L=arg[2] and assert(loadfile(arg[2]))() or require("player_locomotion")
local checks=0
local function check(v,m) checks=checks+1;assert(v,m) end
local function pose(x,z) return {x=x,y=0,z=z or 10} end
local a,b=L.new(),L.new()
L.step(a,pose(0),0);L.step(b,pose(20),0)
for i=1,60 do
    L.step(a,pose(i/60*2),i/60)
    L.step(b,pose(20),i/60)
    check(a.phase==1 and b.phase==0,"walking and idle are per actor")
end
for i=1,10 do L.step(a,pose(2+i/60*6),1+i/60) end
check(a.phase==2,"sustained horizontal sprint selects sprint within 167 ms")
local stoppedAt=1+10/60
L.step(a,pose(3),stoppedAt+0.02);check(a.phase==2,"one short sample gap cannot flicker to idle")
L.step(a,pose(3),stoppedAt+0.08);check(a.phase==0,"real stop selects neutral idle within 80 ms")
local base=stoppedAt+0.08
local seen={}
for i=1,72 do
    local t=i/60
    local z=10+1.75*4*(t/1.2)*(1-t/1.2)
    L.step(a,pose(3,z),base+t)
    seen[a.phase]=true
    check(a.phase~=2,"vertical jump never becomes a sprint")
end
check(seen[5] and seen[3] and seen[4],"takeoff, air and landing selected")
for i=1,90 do L.step(a,pose(3),base+1.2+i/60) end
check(a.phase==0 and not a.airborne,"landing cannot retain jump or crossed-arms pose")
check(b.phase==0 and b.cycles==0,"other actor's gait never advances")
local jitter=L.new();local x=0
L.step(jitter,pose(x),0)
for i=1,120 do
    x=x+(i%2==0 and 3.6 or 3.4)/60
    L.step(jitter,pose(x),i/60)
    check(jitter.phase==1,"speed noise around old threshold cannot alternate walk/sprint")
end
local teleported=L.new()
L.step(teleported,pose(0),0)
L.step(teleported,pose(6,11),1/60)
check(not teleported.airborne and teleported.phase==0 and teleported.ground==11,
    "upward/lateral source teleport resets ground instead of latching jump")
local ledge=L.new()
L.step(ledge,pose(0),0);L.step(ledge,pose(0,10.5),0.1)
L.step(ledge,pose(0,10.5),0.15)
check(ledge.airborne,"brief apex cannot count as landing")
for i=1,10 do L.step(ledge,pose(0,10.5),0.15+i/30) end
check(not ledge.airborne and ledge.ground==10.5,"higher landing settles without crossing old ground")
L.step(a,pose(2.1,100),20);check(a.phase==0 and not a.airborne,"long gap is a new baseline")
local queued={}; NewObject=function(name) check(name=="entAnimInputSetterFloat","typed engine input");return {} end
CName={new=function(x)return x end}
local actor={GetEntityID=function()return {hash="9007199254740993ULL"}end,
    QueueEvent=function(_,event)queued[#queued+1]=event end}
L.apply(actor,a)
check(#queued==2 and queued[1].key=="cp_coop_loco_progress" and queued[2].key=="cp_coop_loco_phase",
    "progress precedes selector; queueing alone is not playback evidence")
local before=#queued
for i=1,600 do L.apply(actor,a) end
check(#queued==before,"unchanged idle inputs must not be submitted every frame")
a.progress=.25;L.apply(actor,a)
check(#queued==before+1 and queued[#queued].key=="cp_coop_loco_progress","changed progress must still reach the graph")
local otherActor={GetEntityID=function()return {hash="9007199254740994ULL"}end,QueueEvent=actor.QueueEvent}
before=#queued;check(not pcall(L.apply,otherActor,a) and #queued==before,"input cache cannot cross exact actor identities")
local numeric={GetEntityID=function()return {hash=9007199254740993}end,QueueEvent=actor.QueueEvent}
check(not pcall(L.apply,numeric,L.new()),"lossy numeric actor identity cannot qualify an input cache")
local retry=L.new();local accepted={};local fail=true
local recovering={GetEntityID=actor.GetEntityID,QueueEvent=function(_,event)
    if fail and event.key=="cp_coop_loco_phase" then error("queue temporarily unavailable") end
    accepted[#accepted+1]=event.key
end}
check(not pcall(L.apply,recovering,retry) and #accepted==1,"partial queue failure must remain observable")
fail=false;L.apply(recovering,retry)
check(#accepted==2 and accepted[2]=="cp_coop_loco_phase","failed input must retry without replaying an admitted input")
local full=L.new(true,true);before=#queued;L.apply(actor,full)
local initial=#queued-before
for i=1,600 do L.apply(actor,full) end
check(initial==19 and #queued==before+19,"full directional idle must settle after its 19 initial inputs")
check(full.inputSubmissions==19,"diagnostic counter must count successful queue submissions only")
local timed=L.new(true,true);L.step(timed,pose(0),0);before=#queued;L.apply(actor,timed)
for i=1,30 do L.step(timed,pose(0),i/60);L.apply(actor,timed) end
check(#queued==before+19,"stable idle must not repeat inputs before its repair deadline")
for i=31,60 do L.step(timed,pose(0),i/60);L.apply(actor,timed) end
check(#queued==before+38,"a bounded real-second repair must refresh every graph input")
L.step(timed,pose(0),-1);L.apply(actor,timed)
check(#queued==before+57,"clock rewind must repair the graph once")
L.step(timed,pose(0),-1);L.apply(actor,timed)
check(#queued==before+57,"duplicate clock must not cause a repair burst")
print("player_locomotion: PASS ("..checks.." checks, cosmetic inference only)")
