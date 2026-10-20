local root=assert(arg[1]);local L=arg[2] and dofile(arg[2]) or dofile(root..'/runtime/session/cet/CP2077Coop/player_locomotion.lua')
local function pose(x,y,yaw,a)return {x=x,y=y,z=10,yaw=yaw or 0,actions=a or {fresh=true,stance=2,weapon=1,record='0000000000',aim=1}}end
local function near(a,b)assert(math.abs(a-b)<1e-7,tostring(a)..' != '..tostring(b))end
local function route(dx,dy,yaw,direction,side,stride)
    local s=L.new(true,true);L.step(s,pose(0,0,yaw),0)
    for i=1,60 do L.step(s,pose(dx*i/60,dy*i/60,yaw),i/60)end
    near(s.crouchDirection,direction);near(s.crouchSide,side);near(s.crouchSideWeight,1)
    near(s.crouchProgress,math.sqrt(dx*dx+dy*dy)/stride);near(s.directionWeight,0)
    local held=s.crouchProgress;L.step(s,pose(dx,dy,yaw),1.02);near(s.crouchProgress,held)
    L.step(s,pose(dx,dy,yaw),1.1);near(s.phase,0);near(s.crouchProgress,held);near(s.crouchSideWeight,1)
    return s
end
local s=route(.5,0,0,1,0,1.4817253351211548)
route(-.5,0,0,3,1,1.4952208995819092)
route(0,.5,math.pi/2,1,0,1.4817253351211548)
route(0,-.5,math.pi/2,3,1,1.4952208995819092)
local frozen=s.cycles
L.step(s,pose(.49,0),1.12)
near(s.crouchPreviousSide,0);near(s.crouchSide,1);near(s.crouchPreviousProgress,frozen)
near(s.crouchSideBlend,.25)
L.step(s,pose(.48,0),1.14);near(s.crouchSideBlend,.5);near(s.crouchPreviousProgress,frozen)
L.step(s,pose(.46,0),1.18);near(s.crouchSideBlend,1)
for _,bad in ipairs({pose(.45,0,math.huge),pose(.45,0,0,{fresh=false,stance=2}),pose(.45,0,0,{fresh=true,stance=1})})do
    local state=route(.5,0,0,1,0,1.4817253351211548);L.step(state,bad,1.12)
    near(state.crouchSideWeight,0);near(state.crouchProgress,0)
end
local a=route(.5,0,0,1,0,1.4817253351211548)
L.step(a,pose(20,0),1.12);near(a.crouchSideWeight,0);near(a.crouchProgress,0)
local b=route(.5,0,0,1,0,1.4817253351211548)
L.step(b,pose(.51,0),2);near(b.crouchSideWeight,0);near(b.crouchProgress,0)
local c=L.new();L.step(c,pose(0,0),0);L.step(c,pose(.1,0),.1)
near(c.crouchSideWeight,0);near(c.cycles,.1/3.7953503131866455)
-- Noisy diagonal velocities must not alternate clips. Crossing the boundary
-- deliberately must select the next axis and settle at the real-clock rate.
for _,yaw in ipairs({0,math.pi/2})do
    local state=L.new(true,true);local x,y,t=0,0,0
    L.step(state,pose(x,y,yaw),t)
    local expected={0,1,1,2,2,3,3,0}
    for leg,angle in ipairs({35,55,125,145,215,235,305,325})do
        for frame=1,90 do
            local a=(angle+(frame%2==0 and .5 or -.5))*math.pi/180
            local dx,dy=math.sin(a)/60,math.cos(a)/60
            x=x+math.cos(yaw)*dx-math.sin(yaw)*dy
            y=y+math.sin(yaw)*dx+math.cos(yaw)*dy;t=t+1/30
            local p=pose(x,y,yaw);L.step(state,p,t)
            near(state.crouchDirection,expected[leg])
            assert(p.x==x and p.y==y and p.yaw==yaw,'diagonal inference cannot rewrite the network root')
            assert(state.directionWeight==0,'diagonal crouch cannot expose the standing direction bank')
            if frame>=3 then
                local side=expected[leg]==1 or expected[leg]==3
                near(state.crouchSideWeight,side and 1 or 0)
                near(state.crouchBackward,expected[leg]==2 and 1 or 0)
            end
        end
    end
    local held=state.crouchProgress
    for i=1,6 do t=t+1/30;L.step(state,pose(x,y,yaw),t);near(state.crouchProgress,held)end
    near(state.phase,0)
end
print('Side crouch: four body-relative routes, measured stride, frozen stop/departure, real-clock blend, guards and default isolation passed')
