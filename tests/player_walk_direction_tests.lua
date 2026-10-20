local root=assert(arg[1]);local L=assert(loadfile(root..'/runtime/session/cet/CP2077Coop/player_locomotion.lua'))()
local function action()return {fresh=true,stance=1,weapon=2,record='16ac119774',aim=1}end
local function pose(x,y,yaw,a)return {x=x,y=y,z=10,yaw=yaw,actions=a}end
local function near(a,b)assert(math.abs(a-b)<.000001,tostring(a)..' != '..tostring(b))end
local function route(dx,dy,yaw,expected)
    local s=L.new(true);local a=action();L.step(s,pose(0,0,yaw,a),0)
    for i=1,60 do
        local p=pose(dx*i/60,dy*i/60,yaw,a);L.step(s,p,i/60)
        assert(p.yaw==yaw and p.x==dx*i/60 and p.y==dy*i/60,'direction inference must not rotate or move body pose')
    end
    assert(s.phase==1 and s.direction==expected and s.directionWeight==1 and s.directionBlend==1)
    return s
end
route(0,1.2,0,0);route(1.2,0,0,1);route(0,-1.2,0,2);route(-1.2,0,0,3)
route(-1.2,0,math.pi/2,0);route(0,1.2,math.pi/2,1)
local back=route(0,-1.2,0,2);near(back.cycles,1.2/1.593894124031067)
do
    local hold=route(1.2,0,0,1);local a=action()
    L.step(hold,pose(1.2,0,0,a),1.02)
    assert(hold.phase==1 and hold.directionWeight==1 and hold.direction==1,
        'brief zero-motion sample must retain direction with the existing walking hold')
    L.step(hold,pose(1.2,0,0,a),1.08)
    assert(hold.phase==0 and hold.directionWeight==0,'real stop still exits direction gait within80ms')
end
local a=action();local s=L.new(true);L.step(s,pose(0,0,0,a),0)
local x,y=0,0
for i=1,120 do
    x=x+(i%2==0 and 1.01 or .99)/60;y=y+1/60;L.step(s,pose(x,y,0,a),i/60)
    assert(s.direction==0,'small velocity noise around a diagonal cannot chatter between clips')
end
local saved=s.cycles
for i=1,6 do
    x=x+1.7/60;y=y+1/60;L.step(s,pose(x,y,0,a),2+i/60)
    assert(s.direction==1)
    near(s.directionPreviousProgress,saved)
end
assert(s.directionBlend==1 and s.directionWeight==1,'real-clock direction change must settle within100ms')
for _,change in ipairs({function(v)v.fresh=false end,function(v)v.stance=2 end,function(v)v.weapon=1 end,
    function(v)v.weapon=3 end,function(v)v.record='0000000000'end,function(v)v.aim=0 end})do
    local state=L.new(true);local value=action();L.step(state,pose(0,0,0,value),0)
    L.step(state,pose(.1,0,0,value),.05);assert(state.directionWeight>0)
    change(value);L.step(state,pose(.2,0,0,value),.1)
    assert(state.directionWeight==0,'ineligible state must immediately leave the combat gait')
end
for _,yaw in ipairs({0/0,math.huge})do
    local state=L.new(true);L.step(state,pose(0,0,0,action()),0);L.step(state,pose(.1,0,yaw,action()),.05)
    assert(state.directionWeight==0,'invalid heading cannot enter direction layer')
end
local ordinary=L.new();local crouched=L.new(true);local c=action();c.stance=2
L.step(ordinary,pose(0,0,0,c),0);L.step(crouched,pose(0,0,0,c),0)
for i=1,60 do
    L.step(ordinary,pose(i/60,0,0,c),i/60);L.step(crouched,pose(i/60,0,0,c),i/60)
    near(ordinary.cycles,(i/60/3.7953503131866455)%1)
    near(crouched.cycles,(i/60/1.4817253351211548)%1)
    assert(crouched.directionWeight==0,'crouch must never expose standing combat feet')
end
L.step(back,pose(50,50,0,a),3);assert(back.phase==0 and back.directionWeight==0,'teleport/gap resets direction eligibility')
local events={};CName={new=function(v)return v end};NewObject=function()return {}end
L.apply({QueueEvent=function(_,e)events[#events+1]=e end},s)
assert(#events==14 and events[1].key=='cp_coop_loco_progress' and events[14].key=='cp_coop_loco_phase')
for _,e in ipairs(events)do assert(e.value==e.value and e.value>=0 and e.value<=3,'all cosmetic graph values finite/bounded')end
print('Armed walk direction: four-way/yaw axes, measured stride, hysteresis, fixed pose, real-time blend and guarded fallback passed')
