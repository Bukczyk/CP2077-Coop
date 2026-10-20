local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local L=arg[2] and dofile(arg[2]) or require("player_locomotion")
local function action()return {fresh=true,stance=2,weapon=1,record="0000000000",aim=1}end
local function pose(x,y,yaw,a)return {x=x,y=y,z=10,yaw=yaw or 0,actions=a or action()}end
local function near(x,y)assert(math.abs(x-y)<1e-7,tostring(x).." != "..tostring(y))end
local function route(dx,dy,yaw,back,distance)
    local s=L.new(true,true);L.step(s,pose(0,0,yaw),0)
    for i=1,60 do
        local p=pose(dx*i/60,dy*i/60,yaw);L.step(s,p,i/60)
        assert(p.x==dx*i/60 and p.y==dy*i/60 and p.yaw==yaw,"cosmetics cannot rewrite root")
    end
    assert(s.directionWeight==0,"standing combat bank cannot enter crouch")
    near(s.crouchBackward,back);near(s.crouchProgress,(math.sqrt(dx*dx+dy*dy)/distance)%1)
    return s
end
route(0,.6,0,0,6.249844074249268)
local s=route(0,-.6,0,1,3.992504835128784)
do
    local blend=L.new(true,true);L.step(blend,pose(0,0),0)
    L.step(blend,pose(0,-.01),.02);near(blend.crouchBackward,.25)
    L.step(blend,pose(0,-.02),.04);near(blend.crouchBackward,.5)
    L.step(blend,pose(0,-.04),.08);near(blend.crouchBackward,1)
end
route(.6,0,math.pi/2,1,3.992504835128784)
route(-.6,0,math.pi/2,0,6.249844074249268)
local held=s.crouchProgress
L.step(s,pose(0,-.6),1.02);near(s.crouchProgress,held);near(s.crouchBackward,1)
L.step(s,pose(0,-.6),1.1)
assert(s.phase==0 and s.progress==0,"real stop exits gait")
near(s.crouchProgress,held);near(s.crouchBackward,1) -- moving layer fades from frozen feet.
local x=0;local t=1.1
for i=1,6 do x=x+.01;t=t+.02;L.step(s,pose(x,-.6),t)end
near(s.crouchBackward,0);near(s.crouchSideWeight,1)
for _,change in ipairs({function(a)a.fresh=false end,function(a)a.stance=0 end,function(a)a.stance=1 end})do
    local state=route(0,-.6,0,1,3.992504835128784);local a=action();change(a)
    L.step(state,pose(0,-.61,0,a),1.02);near(state.crouchBackward,0);near(state.crouchProgress,0)
end
for _,yaw in ipairs({0/0,math.huge})do
    local state=route(0,-.6,0,1,3.992504835128784)
    L.step(state,pose(0,-.61,yaw),1.02);near(state.crouchBackward,0);near(state.crouchProgress,0)
end
L.step(s,pose(0,-10),3);near(s.crouchBackward,0);near(s.crouchProgress,0)
local ordinary=L.new();L.step(ordinary,pose(0,0),0);L.step(ordinary,pose(0,-.1),.1)
near(ordinary.cycles,.1/3.7953503131866455);near(ordinary.crouchBackward,0)
local events={};CName={new=function(v)return v end};NewObject=function()return {}end
L.apply({QueueEvent=function(_,e)events[#events+1]=e end},s)
assert(#events==19 and events[1].key=="cp_coop_loco_progress" and events[19].key=="cp_coop_loco_phase")
for _,e in ipairs(events)do assert(e.value==e.value and e.value>=0 and e.value<=5,"finite graph inputs")end
print("Crouch direction: forward/back/yaw, native stride, frozen stop, real-clock weights and fail-neutral passed")
