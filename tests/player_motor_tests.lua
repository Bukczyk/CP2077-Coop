local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local Motor=require("player_motor")
local function actor()
    local a={pos={x=10,y=10,z=2},yaw=0,starts=0,stops=0,turns=0,snaps=0}
    function a:GetWorldPosition() return self.pos end
    function a:GetWorldOrientation() return {ToEulerAngles=function() return {yaw=self.yaw} end} end
    function a:CP2077Session_StartMove(x,y,z,gait)
        self.starts=self.starts+1
        return {state=2,target={x=x,y=y,z=z},gait=gait,owner=self}
    end
    function a:CP2077Session_RetargetMove(c,x,y,z)
        assert(c.owner==self,"cross-player command")
        if c.state==2 then c.target={x=x,y=y,z=z} end
        return c.state
    end
    function a:CP2077Session_StopMove(c) assert(c.owner==self); self.stops=self.stops+1 end
    function a:CP2077Session_SnapProxy(x,y,z,yaw)
        self.snaps=self.snaps+1 -- deliberately does NOT move: a queued call is not success
    end
    function a:CP2077Session_TurnProxy(yaw) self.turns=self.turns+1; self.yaw=yaw end
    return a
end
local function target(x,y,z,yaw) return {x=x,y=y or 10,z=z or 2,yaw=yaw or 0} end

-- A continuous render trajectory must reuse executing commands, never teleport
-- normal motion or mix command handles between independently keyed players.
local actors,motors={},{ }
for i=1,3 do actors[i]=actor(); motors[i]=Motor.new(actors[i]) end
for frame=1,600 do
    for i=1,3 do
        local x=10+frame/60*(i+1)
        actors[i].pos={x=x-0.5,y=10,z=2}
        motors[i]:step(target(x),1/60)
    end
end
for i=1,3 do
    assert(actors[i].snaps==0,"normal tracking must not snap")
    assert(actors[i].starts<10,"must retain movement rather than restart every frame")
    local x=actors[i].pos.x
    for _=1,120 do motors[i]:step(target(x,nil,nil,math.pi/2),1/60) end
    assert(motors[i].command==nil,"stop after stationary sample")
    assert(actors[i].turns>0 and actors[i].turns<5,"idle facing bounded")
end

-- A stuck actor gets bounded corrective attempts, with observed error retained.
local a=actor(); local m=Motor.new(a)
for _=1,600 do m:step(target(30),1/60) end
assert(a.snaps>=2 and a.snaps<=10,"correction cooldown")
assert(m.error==20,"failed engine correction must remain observable")
-- Origin placement grace, then recovery, with no command flood.
a=actor(); a.pos={x=0,y=0,z=0}; m=Motor.new(a)
for _=1,90 do m:step(target(30),1/60) end
assert(a.snaps==0 and a.starts==0,"wait for streamed actor placement")
for _=1,90 do m:step(target(30),1/60) end
assert(a.snaps>0 and a.snaps<=2)
-- Pending commands must get time to start; terminal commands can be replaced.
a=actor(); m=Motor.new(a); m:step(target(11),1/60)
m.command.state=1
for _=1,40 do m:step(target(11),1/60) end
assert(a.starts==1,"pending handle must not be flooded")
m.command.state=4
for _=1,20 do m:step(target(11),1/60) end
assert(a.starts==2,"replace terminal command")
m:stop(); assert(m.command==nil and a.stops>0)
-- A long render pause cannot produce a fake extreme speed.
a=actor(); m=Motor.new(a); m:step(target(11),1/60); m:step(target(12),2)
assert(m.speed==0)
print("player_motor: PASS (3 actors, retained motion, stop/turn, pending/rejected command, observed correction, stream grace)")
