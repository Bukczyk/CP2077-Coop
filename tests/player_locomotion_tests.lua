local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local L=require("player_locomotion")
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
L.step(a,pose(2.1),1.01);check(a.phase==2,"sprint derives from horizontal speed")
L.step(a,pose(2.1),1.03);check(a.phase==0,"stop selects neutral idle immediately")
local seen={}
for i=1,72 do
    local t=i/60
    local z=10+1.75*4*(t/1.2)*(1-t/1.2)
    L.step(a,pose(2.1,z),1.03+t)
    seen[a.phase]=true
    check(a.phase~=2,"vertical jump never becomes a sprint")
end
check(seen[5] and seen[3] and seen[4],"takeoff, air and landing selected")
for i=1,90 do L.step(a,pose(2.1),2.23+i/60) end
check(a.phase==0 and not a.airborne,"landing cannot retain jump or crossed-arms pose")
check(b.phase==0 and b.cycles==0,"other actor's gait never advances")
L.step(a,pose(2.1,100),20);check(a.phase==0 and not a.airborne,"long gap is a new baseline")
local queued={}; NewObject=function(name) check(name=="entAnimInputSetterFloat","typed engine input");return {} end
CName={new=function(x)return x end}
L.apply({QueueEvent=function(_,event)queued[#queued+1]=event end},a)
check(#queued==2 and queued[1].key=="cp_coop_loco_progress" and queued[2].key=="cp_coop_loco_phase",
    "progress precedes selector; queueing alone is not playback evidence")
print("player_locomotion: PASS ("..checks.." checks, cosmetic inference only)")
