local root = assert(arg[1])
package.path = root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local Motor = require("player_motor")
local checks = 0
local function check(condition, message)
    checks = checks+1
    assert(condition, message)
end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function distance(a, b)
    local x, y, z = a.x-b.x, a.y-b.y, a.z-b.z
    return math.sqrt(x*x+y*y+z*z)
end
local function angle(a, b) return (a-b+180)%360-180 end
local function target(x, y, z, yaw) return {x=x, y=y or 10, z=z or 2, yaw=yaw or 0} end
local function copy(p) return {x=p.x, y=p.y, z=p.z} end

-- A deterministic command-driven actor. The tests supply only network targets;
-- observed position evolves from admitted commands, never from those targets.
-- This is a scheduling/motion model, not REDengine navigation or animation.
local function actor(x, y)
    local a = {pos=target(x or 10, y), yaw=0, starts=0, stops=0, turns=0, snaps=0,
        retargets=0, travel=0, accepted=0, reject={}, inert={}, maxOwned=0}
    function a:GetWorldPosition() return copy(self.pos) end
    function a:GetWorldOrientation() return {ToEulerAngles=function() return {yaw=self.yaw} end} end
    function a:submit(kind, x2, y2, z2, yaw, gait)
        assert(self.current == nil, "stacked actor commands")
        for _, value in ipairs({x2, y2, z2, yaw, gait}) do assert(finite(value), "non-finite engine input") end
        if self.reject[kind] then return nil end
        local c = {owner=self, kind=kind, state=1, age=0, target=target(x2,y2,z2), yaw=yaw, gait=gait}
        self.current = c
        self.accepted = self.accepted+1
        self.maxOwned = math.max(self.maxOwned, 1)
        return c
    end
    function a:CP2077Session_StartMove(x2, y2, z2, gait)
        self.starts = self.starts+1
        return self:submit("move", x2, y2, z2, 0, gait)
    end
    function a:CP2077Session_MotorState(c)
        assert(c.owner == self and c == self.current, "foreign actor/state handle")
        return self.invalidState or c.state
    end
    function a:CP2077Session_RetargetMove(c, x2, y2, z2, gait)
        assert(c.owner == self and c == self.current, "cross-player command")
        assert(finite(x2) and finite(y2) and finite(z2) and finite(gait))
        self.retargets = self.retargets+1
        if self.rejectRetarget then return -1 end
        if c.state == 2 then c.target, c.gait = target(x2,y2,z2), gait end
        return c.state
    end
    function a:CP2077Session_StopMove(c)
        assert(c.owner == self and c == self.current, "cross-player cancellation")
        self.stops = self.stops+1
        if self.stopDenied then return false end
        c.state = 3
        self.current = nil
        return true
    end
    function a:CP2077Session_SnapProxy(x2, y2, z2, yaw)
        self.snaps = self.snaps+1
        return self:submit("correction", x2, y2, z2, yaw, 0)
    end
    function a:CP2077Session_TurnProxy(yaw)
        self.turns = self.turns+1
        return self:submit("turn", self.pos.x, self.pos.y, self.pos.z, yaw, 0)
    end
    function a:advance(delta)
        local c = self.current
        if not c then return end
        c.age = c.age+delta
        if self.pendingForever or c.age < (self.admissionDelay or 0.06) then return end
        c.state = self.forceState or 2
        if self.forceState or self.inert[c.kind] then
            if self.inertSuccess then c.state = 5 end
            return
        end
        if c.kind == "move" then
            local gap = distance(self.pos, c.target)
            if gap > 0 then
                local travel = math.min(gap, ({[0]=1.7, [1]=4, [2]=7})[c.gait]*delta)
                for _, axis in ipairs({"x", "y", "z"}) do
                    self.pos[axis] = self.pos[axis]+(c.target[axis]-self.pos[axis])*travel/gap
                end
                self.travel = self.travel+travel
            end
        elseif c.kind == "correction" then
            if c.age >= 0.12 then self.pos, self.yaw, c.state = copy(c.target), c.yaw, 5 end
        else
            local gap = angle(c.yaw, self.yaw)
            local turn = math.min(math.abs(gap), 240*delta)
            self.yaw = self.yaw+(gap < 0 and -turn or turn)
            if math.abs(angle(c.yaw, self.yaw)) <= 3 then c.state = 5 end
        end
    end
    return a
end
local function run(a, m, frames, desired, delta)
    delta = delta or 1/60
    for frame=1,frames do
        a:advance(delta)
        m:step(type(desired) == "function" and desired(frame) or desired, delta)
    end
end

-- Simultaneous command-driven walks/runs/sprints, stops and fast reversals.
local actors, motors, errors = {}, {}, {}
for i=1,3 do actors[i]=actor(10, i*20); motors[i]=Motor.new(actors[i]); errors[i]=0 end
for frame=1,900 do
    local t = frame/60
    local route = t <= 4 and t or (t <= 6 and 4 or (t <= 10 and 10-t or 0))
    for i=1,3 do
        local speed = ({1.2, 3, 5.5})[i]
        local desired = target(10+route*speed, i*20, 2, t > 6 and math.pi or 0)
        actors[i]:advance(1/60)
        motors[i]:step(desired, 1/60)
        errors[i] = math.max(errors[i], motors[i].error or 0)
        assert(motors[i].fault == nil, "healthy trajectory fault: "..tostring(motors[i].fault))
    end
end
for i=1,3 do
    local a, m = actors[i], motors[i]
    check(a.travel > 8*({1.2,3,5.5})[i]-0.4, "actor really followed both directions")
    check(distance(a.pos,target(10,i*20)) < 0.2, "final stop reached from commanded motion")
    check(errors[i] < 3, "bounded simulated tracking error")
    check(a.snaps == 0, "normal continuous movement must not teleport")
    check(a.starts <= 4 and a.retargets > 60, "retain and retarget executing movement")
    check(m.command == nil and a.current == nil, "stationary actor retires final command")
    check(math.abs(angle(a.yaw,180)) <= 5 and a.turns <= 2, "idle turn observes orientation")
end

-- Wrapped orientation: 179 to -179 degrees is already inside tolerance.
local a = actor(); a.yaw = 179
local m = Motor.new(a)
run(a,m,120,target(10,nil,nil,math.rad(-179)))
check(a.turns == 0, "yaw wrap must not issue a nearly full-circle turn")
run(a,m,120,target(10,nil,nil,math.rad(-160)))
check(a.turns == 1 and math.abs(angle(a.yaw,-160)) <= 5, "wrapped turn observed once")

-- Invalid data neither poisons timers nor reaches the engine.
for _, delta in ipairs({0, -1, math.huge, -math.huge, 0/0, "bad"}) do
    a = actor(); m = Motor.new(a)
    check(m:step(target(11),delta) == "invalid_delta" and m.clock == 0 and a.accepted == 0, "reject bad delta")
end
for _, field in ipairs({"x","y","z","yaw"}) do
    for _, value in ipairs({math.huge,-math.huge,0/0,"bad"}) do
        a = actor(); m = Motor.new(a); local desired = target(11); desired[field] = value
        check(m:step(desired,1/60) == "fault" and a.accepted == 0, "reject invalid target "..field)
    end
end
for _, value in ipairs({false, 5, "bad", {}}) do
    a=actor(); m=Motor.new(a)
    check(m:step(value,1/60) == "fault" and a.accepted == 0, "reject malformed target")
end
a=actor(); m=Motor.new(a); m:step(target(11),1/60)
local bad=target(11); bad.x=0/0
m:step(bad,1/60)
check(a.current == nil and m.fault == "invalid_target", "invalid sample retires stale movement")
a=actor(); m=Motor.new(a); a.pos.x=math.huge
check(m:step(target(11),1/60) == "fault" and a.accepted == 0, "reject invalid engine position")
a=actor(); m=Motor.new(a); a.yaw=0/0
check(m:step(target(11),1/60) == "fault" and a.accepted == 0, "reject invalid engine heading")
a=actor(); m=Motor.new(a)
check(m:step(target(1e100),1/60) == "fault" and finite(m.clock) and a.accepted == 0, "reject finite Lua value that overflows engine Float")

-- Rejected submissions and terminal/unstarted movement get exactly three tries.
for _, mode in ipairs({"reject", "pending", "failed", "false_success", "retarget", "invalid_state"}) do
    a=actor(); m=Motor.new(a)
    if mode == "reject" then a.reject.move=true
    elseif mode == "pending" then a.pendingForever=true
    elseif mode == "failed" then a.forceState=6
    elseif mode == "false_success" then a.forceState=5
    elseif mode == "retarget" then a.rejectRetarget=true; a.inert.move=true
    else a.invalidState=99 end
    run(a,m,1200,target(11))
    check(a.starts == 3 and m.fault ~= nil, "bounded movement retries: "..mode)
    check(m.command == nil and a.current == nil and a.snaps == 0, "failed movement cannot leak/stack commands: "..mode)
end
-- Pending admission within the deadline is retained instead of flooded.
a=actor(); a.admissionDelay=0.7; m=Motor.new(a)
run(a,m,40,target(11))
check(a.starts == 1 and m.command ~= nil, "retain pending admitted movement")
run(a,m,180,target(11))
check(a.starts == 1 and distance(a.pos,target(11)) < 0.2 and not m.fault, "late admitted move converges")
a=actor(); a.reject.move=true; m=Motor.new(a); m:step(target(11),1/60)
a.reject.move=false
run(a,m,180,target(11))
check(a.starts == 2 and m.failures.move == 0 and not m.fault, "observed motion clears transient submission failure")

-- A successful command status without transform change is not correction success.
for _, mode in ipairs({"rejected", "unobserved", "false_success", "failed"}) do
    a=actor(); m=Motor.new(a)
    if mode == "rejected" then a.reject.correction=true
    elseif mode == "failed" then a.forceState=6
    else a.inert.correction=true; a.inertSuccess=mode == "false_success" end
    run(a,m,1800,target(30))
    check(a.snaps == 3 and m.observedSnaps == 0 and m.fault ~= nil, "bounded unobserved corrections: "..mode)
    check(m.error == 20 and m.command == nil and a.current == nil, "retain real correction error: "..mode)
end
-- Corrective readback compares the admitted target while newer targets coalesce.
a=actor(); m=Motor.new(a); m:step(target(30),1/60)
local admitted=m.command
run(a,m,12,target(30.5))
check(m.observedSnaps == 1 and admitted.state == 3, "observe and retire admitted correction")
run(a,m,180,target(30.5))
check(a.snaps == 1 and distance(a.pos,target(30.5)) < 0.2 and not m.fault, "resume latest target after correction")
-- A walking failure cannot disguise itself as an endless train of successful snaps.
a=actor(); a.inert.move=true; m=Motor.new(a)
run(a,m,2400,function(frame) return target(10+frame/60*2) end)
check(a.snaps == 3 and m.fault == "correction_limit", "successful snap spam has a recovery budget")
check(a.current == nil, "correction budget fault leaves no active command")
a=actor(); a.inert.move=true; m=Motor.new(a)
run(a,m,300,target(10.5))
check(a.snaps == 1 and m.observedSnaps == 1 and not m.fault,
    "detect stalled motion even inside former 0.75m dead zone: "..a.snaps.."/"..m.observedSnaps.."/"..tostring(m.fault))
-- After a settled recovery, a later unrelated warp is allowed.
a=actor(); m=Motor.new(a)
run(a,m,180,target(30)); run(a,m,180,target(50))
check(a.snaps == 2 and m.observedSnaps == 2 and not m.fault, "observed stable recovery replenishes corrections")

-- Turn rejection, false success and cancellation ownership are also bounded.
for _, mode in ipairs({"rejected", "unobserved", "false_success"}) do
    a=actor(); m=Motor.new(a)
    if mode == "rejected" then a.reject.turn=true
    else a.inert.turn=true; a.inertSuccess=mode == "false_success" end
    run(a,m,1200,target(10,nil,nil,math.pi/2))
    check(a.turns == 3 and m.fault ~= nil and a.current == nil, "bounded facing failure: "..mode)
end
for _, kind in ipairs({"move","correction","turn"}) do
    a=actor(); m=Motor.new(a)
    local desired=kind == "move" and target(11) or (kind == "correction" and target(30) or target(10,nil,nil,math.pi/2))
    m:step(desired,1/60)
    local command=m.command; a.stopDenied=true
    check(not pcall(function() m:stop() end) and m.command == command and a.current == command, "retain failed cancellation: "..kind)
    run(a,m,300,desired)
    check(a.accepted == 1, "unconfirmed retirement prohibits replacements: "..kind)
    a.stopDenied=false; m:stop()
    check(m.command == nil and a.current == nil, "external cleanup can retry exact cancellation: "..kind)
end

-- A turn can retire for new motion; no obsolete facing command is left behind.
a=actor(); a.inert.turn=true; m=Motor.new(a); m:step(target(10,nil,nil,math.pi),1/60)
local turn=m.command
run(a,m,180,target(12))
check(turn.state == 3 and a.starts == 1 and distance(a.pos,target(12)) < 0.2 and not m.fault, "new motion supersedes idle turn")
-- Origin grace defers all commands; later recovery still uses readback.
a=actor(); a.pos={x=0,y=0,z=0}; m=Motor.new(a)
run(a,m,90,target(30))
check(a.accepted == 0, "stream placement grace")
run(a,m,120,target(30))
check(a.snaps == 1 and m.observedSnaps == 1 and not m.fault, "origin recovery admitted and observed once")
-- Actual pause gating is covered by session_lifecycle_tests' real entrypoint.
a=actor(); m=Motor.new(a); m:step(target(11),1/60); m:step(target(12),2)
check(m.speed == 0 and finite(m.clock), "long render interval must not invent velocity")
print("player_motor: PASS ("..checks.." checks; commanded trajectories, stops/reversals, wrap, rejection/readback, bounded recovery, ownership)")
