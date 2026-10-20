local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local L=arg[2] and dofile(arg[2]) or require("player_locomotion")
local a={fresh=true,stance=1,weapon=2,record="16ac119774",aim=1}
local function pose(x,y,actions,z)return {x=x,y=y,z=z or 10,yaw=0,actions=actions or a}end
local function near(x,y)assert(math.abs(x-y)<1e-8,tostring(x).." differs from "..tostring(y))end
local s=L.new(true,true)
L.step(s,pose(0,0),0)
assert(s.smooth and s.phaseWeight==0,"matched action renderer must support neutral gait blend")
L.step(s,pose(0,.02),.02)
assert(s.phase==1 and s.previousPhase==0 and s.phaseWeight>0 and s.phaseWeight<1,
    "walk entry must blend from idle rather than snap")
for i=2,6 do L.step(s,pose(0,i*.02),i*.02)end
near(s.phaseWeight,0)
-- A right strafe leaves a frozen right-leg sample when it stops.
for i=1,10 do L.step(s,pose(i*.02,.12),.12+i*.02)end
assert(s.direction==1 and s.directionWeight==1)
local held=s.progress
L.step(s,pose(.2,.12),.34);assert(s.phase==1,"brief interpolation gap retains gait")
L.step(s,pose(.2,.12),.40)
assert(s.phase==0 and s.previousPhase==1 and s.phaseWeight>0)
assert(s.phaseDirection==1 and s.phaseDirectionWeight==1,"stop must retain departing strafe identity")
near(s.previousProgress,held)
L.step(s,pose(.2,.12),.42);near(s.previousProgress,held);near(s.phaseWeight,0)
-- Sprint has real-clock timing independent of actor/world time and does not
-- rewrite network heading or the root transform while blending.
local t,x=.42,.2
local sawSprint=false
for i=1,16 do
    t=t+.02;x=x+.12;local p=pose(x,.12);local saved=p.x
    L.step(s,p,t);assert(p.x==saved and p.yaw==0,"cosmetics cannot rewrite root/heading")
    if s.phase==2 and not sawSprint then
        sawSprint=true;assert(s.previousPhase==1 and s.phaseWeight>0,"sprint enters through walk blend")
    end
end
assert(sawSprint);near(s.phaseWeight,0)
local other=L.new(true,true);L.step(other,pose(20,20),t)
near(other.phaseWeight,0);assert(other.previousPhase==0,"actors cannot share departing state")
-- Rapid retargeting retains the dominant pose without accumulating a chain.
s.phaseWeight=.8;s.previousPhase=0;s.previousProgress=.25;s.phase=2
L.step(s,pose(x+.02,.12),t+.02)
if s.phase==1 then assert(s.previousPhase==0);near(s.previousProgress,.25)end
for _,actions in ipairs({{fresh=false,stance=1},{fresh=true,stance=2},{fresh=true,stance=0}})do
    s.phaseWeight=.8;L.step(s,pose(x+.04,.12,actions),t+.04);near(s.phaseWeight,0)
    t=t+.04;x=x+.04
end
s.phaseWeight=.8;L.step(s,pose(x+100,.12),t+.02);near(s.phaseWeight,0)
s.phaseWeight=.8;L.step(s,pose(x+100,.12),t+1);near(s.phaseWeight,0)
local jump=L.new(true,true);L.step(jump,pose(0,0),0);jump.phaseWeight=.8
L.step(jump,pose(0,0,a,10.5),.1);assert(jump.phase==5 and jump.phaseWeight==0,"takeoff cannot retain ground pose")
local events={};NewObject=function()return {}end;CName={new=function(v)return v end}
L.apply({QueueEvent=function(_,e)events[#events+1]=e end},s)
assert(#events==19 and events[1].key=="cp_coop_loco_progress" and events[19].key=="cp_coop_loco_phase")
for _,e in ipairs(events)do assert(e.value==e.value and e.value>=0 and e.value<=5,"all queued values bounded")end
print("Gait blend: real-clock walk/sprint/stop, frozen direction, per-actor state, bounded retarget and fail-neutral passed")
