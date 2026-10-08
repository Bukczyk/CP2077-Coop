-- Experimental player-proxy actuator. Transport/interpolation supplies the pose;
-- this only owns one AI teleport command on the exactly bound engine actor.
local Pose = {}
Pose.__index = Pose
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function close(actual, yaw, target)
    local dx, dy, dz = actual.x-target.x, actual.y-target.y, actual.z-target.z
    local angle = math.abs((yaw-target.yaw+180)%360-180)
    return dx*dx+dy*dy+dz*dz <= 0.04 and angle <= 5
end
function Pose.new(log)
    return setmetatable({log=log or function() end}, Pose)
end
function Pose:release()
    if self.command ~= nil and self.actor ~= nil then
        local ok, stopped = pcall(function() return self.actor:CP2077Session_StopPose(self.command) end)
        if not ok or stopped ~= true then
            self.fault="cancellation_unconfirmed"
            self.log("fault="..self.fault)
            return false -- never stack a replacement on an unretired command
        end
    end
    self.command, self.sent = nil, nil
    return true
end
function Pose:reset()
    self:release()
    -- Called when this exact actor/session lifetime ends. The owner deletes its
    -- tagged actor; a replacement actor must never inherit the old command.
    self.command, self.sent = nil, nil
    self.actor, self.key, self.firstSeen = nil, nil, nil
    self.failures, self.fault, self.nextSend = 0, nil, 0
    self.submissionLogged, self.observedLogged = false, false
    self.everSubmitted = false
    self.lastReadback, self.lastFailure = nil, nil
    self.submissions = 0
end
-- Return detached values, never the owned engine command or a mutable target.
function Pose:diagnostics()
    local function copy(value)
        if not value then return nil end
        local result={}
        for key,item in pairs(value) do result[key]=item end
        return result
    end
    return {actor=self.key, submissions=self.submissions or 0,
        failures=self.failures or 0, fault=self.fault,
        readback=copy(self.lastReadback), failure=copy(self.lastFailure)}
end
function Pose:fail(reason, now)
    -- Preserve the last comparison BEFORE cancellation mutates command state.
    self.lastFailure={reason=reason,at=now}
    for key,value in pairs(self.lastReadback or {}) do self.lastFailure[key]=value end
    if not self:release() then return end
    self.failures = self.failures + 1
    self.nextSend = now + 0.1
    self.log("retry=" .. tostring(self.failures) .. " reason=" .. reason)
    if self.failures >= 3 then
        self.fault = reason
        self.log("fault=" .. reason .. " until_actor_or_session_reset")
    end
end
function Pose:step(actor, target, now)
    if actor == nil then return "missing" end
    local key = tostring(actor:GetEntityID().hash) -- keep Uint64 exact
    if self.key ~= key then
        self:reset()
        self.key, self.actor, self.firstSeen = key, actor, now
    end
    if self.fault then return "fault" end
    if not actor:IsAttached() or not actor:CP2077Session_PoseReady() then
        if not self:release() then return "fault" end
        if now-self.firstSeen >= 3 then self.fault="attachment_timeout"; self.log("fault="..self.fault) end
        return "waiting_attachment"
    end
    if not (finite(now) and finite(target.x) and finite(target.y) and finite(target.z) and finite(target.yaw)) then
        self:release(); self.fault="invalid_pose"; self.log("fault="..self.fault); return "fault"
    end
    local actual = actor:GetWorldPosition()
    local yaw = actor:GetWorldOrientation():ToEulerAngles().yaw
    -- A newly created actor can exist before AI/placement initializes. Never
    -- overwrite its spawn pose with a growing queue of commands at the origin.
    if actual.x == 0 and actual.y == 0 and actual.z == 0 then
        if now-self.firstSeen >= 3 then self.fault="placement_timeout"; self.log("fault="..self.fault) end
        return "waiting_placement"
    end
    local desired = {x=target.x,y=target.y,z=target.z,yaw=math.deg(target.yaw)}
    if self.command ~= nil then
        local state=actor:CP2077Session_PoseState(self.command)
        local dx,dy,dz=actual.x-self.sent.x,actual.y-self.sent.y,actual.z-self.sent.z
        self.lastReadback={state=state,age=now-self.submittedAt,
            positionError=math.sqrt(dx*dx+dy*dy+dz*dz),
            yawError=math.abs((yaw-self.sent.yaw+180)%360-180),
            actualX=actual.x,actualY=actual.y,actualZ=actual.z,actualYaw=yaw,
            sentX=self.sent.x,sentY=self.sent.y,sentZ=self.sent.z,sentYaw=self.sent.yaw}
        -- SendCommand/Success only describe scheduling. Read the real transform
        -- against the admitted command, not a newer moving network target.
        if close(actual,yaw,self.sent) then
            if not self:release() then return "fault" end
            self.failures=0
            if not self.observedLogged then self.log("observed_pose"); self.observedLogged=true end
        else
            if state == 3 or state == 4 or state == 6 or state < 0 then
                self:fail("command_state_"..tostring(state),now)
            elseif now >= self.deadline then
                self:fail("readback_timeout",now)
            end
            return self.fault and "fault" or "pending"
        end
    end
    if close(actual,yaw,desired) then self.failures=0; return "observed" end
    if now < self.nextSend then return "cooldown" end
    local command=actor:CP2077Session_SubmitPose(desired.x,desired.y,desired.z,desired.yaw)
    if command == nil then
        if not self.everSubmitted and now-self.firstSeen < 3 then
            self.nextSend=now+0.1
            return "waiting_submission"
        end
        self:fail("submission_rejected",now); return self.fault and "fault" or "retry"
    end
    self.everSubmitted=true
    self.submissions=self.submissions+1
    self.submittedAt=now
    self.lastReadback=nil
    self.command,self.sent,self.deadline=command,desired,now+1
    self.nextSend=now+0.1
    if not self.submissionLogged then self.log("command_submitted_not_yet_observed"); self.submissionLogged=true end
    return "pending"
end
return Pose
