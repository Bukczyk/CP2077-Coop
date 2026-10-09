-- Optional game-thread actuator. Interpolation owns the target; this adapter
-- never predicts it again. One exact actor owns one move, correction or turn.
local Motor = {}
Motor.__index = Motor
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function position(value)
    local kind = type(value)
    -- CET narrows these Lua doubles to engine Float arguments.
    return (kind == "table" or kind == "userdata") and
        finite(value.x) and math.abs(value.x) <= 3.4028234e38 and
        finite(value.y) and math.abs(value.y) <= 3.4028234e38 and
        finite(value.z) and math.abs(value.z) <= 3.4028234e38
end
local function distance(a, b)
    local x, y, z = a.x-b.x, a.y-b.y, a.z-b.z
    return math.sqrt(x*x+y*y+z*z)
end
local function angle(a, b) return (a-b+180)%360-180 end
local function copy(value) return {x=value.x, y=value.y, z=value.z, yaw=value.yaw} end
local function failed(state) return state == -1 or state == 3 or state == 4 or state == 6 end

function Motor.new(actor)
    return setmetatable({actor=actor, clock=0, speed=0, nextCommand=0, nextSnap=0,
        nextTurn=0, commands=0, snaps=0, turns=0, observedSnaps=0, stalled=0,
        spawnWait=0, recoveryTime=0, correctionAttempts=0,
        failures={move=0, correction=0, turn=0}}, Motor)
end

function Motor:stop()
    if self.command ~= nil and self.actor:CP2077Session_StopMove(self.command) ~= true then
        self.fault = "cancellation_unconfirmed"
        -- Existing lifecycle cleanup catches this error and retains ownership.
        -- Do not drop the only handle and admit a second engine command.
        error(self.fault)
    end
    self.command, self.kind, self.sent = nil, nil, nil
end

function Motor:release()
    local ok = pcall(function() self:stop() end)
    if not ok then self.fault = "cancellation_unconfirmed" end
    return ok
end

function Motor:fail(kind, reason)
    self.lastFailure = reason
    if not self:release() then return "fault" end
    self.failures[kind] = self.failures[kind]+1
    self.nextCommand = self.clock+0.25
    if self.failures[kind] >= 3 then self.fault = reason end
    return self.fault and "fault" or "retry"
end

function Motor:invalid(reason)
    self:release()
    self.fault = self.fault or reason
    return "fault"
end

function Motor:submit(kind, desired, gait)
    local command
    if kind == "move" then
        self.commands = self.commands+1
        command = self.actor:CP2077Session_StartMove(desired.x, desired.y, desired.z, gait)
    elseif kind == "correction" then
        self.snaps = self.snaps+1
        self.correctionAttempts = self.correctionAttempts+1
        self.nextSnap = self.clock+1
        command = self.actor:CP2077Session_SnapProxy(desired.x, desired.y, desired.z, desired.yaw)
    else
        self.turns = self.turns+1
        self.nextTurn = self.clock+0.5
        command = self.actor:CP2077Session_TurnProxy(desired.yaw)
    end
    if command == nil then return self:fail(kind, kind.."_submission_rejected") end
    self.command, self.kind, self.sent = command, kind, copy(desired)
    self.issued, self.nextCommand = self.clock, self.clock+0.08
    return "pending"
end

function Motor:step(target, delta)
    -- A bad tick must not poison any timer, velocity estimate or engine input.
    if not finite(delta) or delta <= 0 or not finite(self.clock+delta) then return "invalid_delta" end
    if self.fault then return "fault" end
    -- The entrypoint can resolve the exact actor before attachment or its AI
    -- controller is ready, even when spawn readback is already nonzero. Do not
    -- spend active-time deadlines or submission budgets during that interval.
    if self.actor:CP2077Session_PoseReady() ~= true then return "waiting_attachment" end
    if not position(target) or not finite(target.yaw) then return self:invalid("invalid_target") end
    local current = self.actor:GetWorldPosition()
    local yaw = self.actor:GetWorldOrientation():ToEulerAngles().yaw
    if not position(current) or not finite(yaw) then return self:invalid("invalid_readback") end
    local error = distance(current, target)
    if not finite(error) then return self:invalid("invalid_distance") end
    self.clock, self.error = self.clock+delta, error
    local desired = {x=target.x, y=target.y, z=target.z, yaw=math.deg(target.yaw%(2*math.pi))}

    -- Streamed actors may report the origin before placement initializes.
    if math.abs(current.x)+math.abs(current.y)+math.abs(current.z) < 0.01 and
        math.abs(target.x)+math.abs(target.y)+math.abs(target.z) > 1 and self.spawnWait < 2 then
        self.spawnWait = self.spawnWait+delta
        return "waiting_placement"
    end
    local jump = false
    if self.previous and delta < 0.25 then
        local displacement = distance(target, self.previous)
        jump = displacement > 6
        local raw = jump and 0 or math.min(30, displacement/delta)
        self.speed = self.speed+(raw-self.speed)*(1-math.exp(-delta/0.12))
    else self.speed = 0 end
    self.previous = copy(target)
    local travel = self.observed and distance(current, self.observed) or 0
    if self.kind == "move" and delta < 0.25 and error >= 0.2 and travel < 0.15*delta then
        self.stalled = self.stalled+delta
    else self.stalled = 0 end
    self.observed = copy(current)

    -- Successful teleports do not themselves reset the correction budget.
    -- Require sustained observed locomotion or a settled target before allowing
    -- another burst, so an immobile actor cannot teleport along a moving route.
    local tracking = self.kind == "move" and travel >= 0.15*delta and error < 3
    local settled = self.command == nil and error < 0.2 and self.speed < 0.25
    if delta < 0.25 and (tracking or settled) then
        self.recoveryTime = self.recoveryTime+delta
        if tracking then self.failures.move = 0 end
        if self.recoveryTime >= 1 then self.correctionAttempts = 0 end
    else self.recoveryTime = 0 end

    if self.command ~= nil then
        local state = self.actor:CP2077Session_MotorState(self.command)
        self.commandState = state
        if not finite(state) or state%1 ~= 0 or state < -1 or state > 6 then
            return self:fail(self.kind, "invalid_command_state")
        end
        if self.kind ~= "move" then
            local kind = self.kind
            local observed = math.abs(angle(yaw, self.sent.yaw)) <= 5 and
                (kind == "turn" or distance(current, self.sent) <= 0.2)
            if kind == "turn" and (error >= 0.2 or self.speed >= 0.25) then
                if not self:release() then return "fault" end
            elseif observed then
                if not self:release() then return "fault" end
                self.failures[kind] = 0
                if kind == "correction" then self.observedSnaps = self.observedSnaps+1 end
            elseif failed(state) then return self:fail(kind, kind.."_command_failed")
            elseif self.clock-self.issued >= 1 then return self:fail(kind, kind.."_readback_timeout")
            else return "pending" end
        elseif failed(state) then return self:fail("move", "move_command_failed")
        elseif state == 5 then
            if error >= 0.2 then return self:fail("move", "move_unobserved_completion") end
            if not self:release() then return "fault" end
        elseif (state == 0 or state == 1) and self.clock-self.issued >= 1 then
            return self:fail("move", "move_start_timeout")
        end
    end

    if error < 0.2 and self.speed < 0.25 then
        if not self:release() then return "fault" end
        if math.abs(angle(desired.yaw, yaw)) > 5 and self.clock >= self.nextTurn and self.clock >= self.nextCommand then
            return self:submit("turn", desired)
        end
        return "idle"
    end
    if error > 6 or math.abs(current.z-target.z) > 1.5 or self.stalled > 1.5 or jump then
        if self.clock < self.nextSnap or self.clock < self.nextCommand then return "cooldown" end
        if not self:release() then return "fault" end
        if self.correctionAttempts >= 3 then self.fault = "correction_limit"; return "fault" end
        self.stalled, self.recoveryTime = 0, 0
        return self:submit("correction", desired)
    end
    if self.clock < self.nextCommand then return "cooldown" end
    local pace = self.speed+math.min(2, error*0.6)
    local gait = pace > 4.5 and "Sprint" or (pace > 1.8 and "Run" or "Walk")
    if self.gait == "Sprint" and pace > 4 then gait = "Sprint"
    elseif self.gait == "Run" and pace > 1.4 and pace < 4.8 then gait = "Run" end
    local gaitValue = ({Walk=0, Run=1, Sprint=2})[gait]
    if self.command ~= nil then
        if self.commandState == 0 or self.commandState == 1 then return "pending" end
        local state = self.actor:CP2077Session_RetargetMove(self.command, target.x, target.y, target.z, gaitValue)
        if state ~= 2 then return self:fail("move", "move_retarget_failed") end
        self.gait, self.nextCommand = gait, self.clock+0.08
        return "tracking"
    end
    self.gait = gait
    return self:submit("move", desired, gaitValue)
end
return Motor
