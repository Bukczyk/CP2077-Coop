local root=assert(arg[1]);local L=arg[2] and dofile(arg[2]) or dofile(root..'/runtime/session/cet/CP2077Coop/player_locomotion.lua')
local function action()return {fresh=true,stance=1,weapon=1,record='0000000000',aim=1}end
local function pose(x,y,a,yaw)return {x=x,y=y,z=10,yaw=yaw or 0,actions=a or action()}end
for _,route in ipairs({{0,1,0},{1,0,1},{0,-1,2},{-1,0,3}})do
    local s=L.new(true,true);L.step(s,pose(0,0),0)
    for i=1,60 do L.step(s,pose(route[1]*i/60,route[2]*i/60),i/60)end
    assert(s.directionWeight==1 and s.direction==route[3],'holstered direction must follow unchanged body axes')
    local frozen=s.progress;L.step(s,pose(route[1],route[2]),1.02)
    assert(s.directionWeight==1 and s.progress==frozen,'short hold must freeze unarmed steps')
    L.step(s,pose(route[1],route[2]),1.10)
    assert(s.phase==0 and s.directionWeight==0,'real stop must settle')
end
local s=L.new(true);L.step(s,pose(0,0),0);L.step(s,pose(.1,0),.05)
assert(s.directionWeight>0)
for _,change in ipairs({function(a)a.fresh=false end,function(a)a.stance=2 end,
    function(a)a.weapon=0 end,function(a)a.weapon=3 end,function(a)a.record='16ac119774'end,
    function(a)a.aim=0 end,function(a)a.aim=2 end})do
    local a=action();change(a);L.step(s,pose(.2,0,a),.1);assert(s.directionWeight==0,'unknown or incoherent holstered state must fail neutral')
    s=L.new(true);L.step(s,pose(0,0),0);L.step(s,pose(.1,0),.05)
end
local ordinary=L.new();L.step(ordinary,pose(0,0),0);L.step(ordinary,pose(.1,0),.05)
assert(ordinary.directionWeight==0,'default renderer is unchanged')
print('Unarmed direction: four axes, independent stance guard, frozen hold, stop and default fallback passed')
