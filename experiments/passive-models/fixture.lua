-- Bounded local command queue. No game API access from public methods.
local M={}
local Comparison=require("comparison")
local Controller={};Controller.__index=Controller
local MAX_SLOTS=8 -- local diagnostic budget, unrelated to multiplayer capacity
local function copy(value)
    if type(value)~="table" then return value end
    local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)~=math.huge end
local function validPose(p)
    if type(p)~="table" then return false end
    for _,k in ipairs({"x","y","z","yaw"}) do if not finite(p[k]) then return false end end
    if math.abs(p.x)>100000 or math.abs(p.y)>100000 or math.abs(p.z)>100000 or math.abs(p.yaw)>math.pi then return false end
    return true
end
local function poseCopy(p) return {x=p.x,y=p.y,z=p.z,yaw=p.yaw} end
local function matched(p,target)
    if not p or not target then return false end
    for _,k in ipairs({"x","y","z","qx","qy","qz","qw"}) do if not finite(p[k]) then return false end end
    local distance=math.sqrt((p.x-target.x)^2+(p.y-target.y)^2+(p.z-target.z)^2)
    local dot=math.abs(p.qz*math.sin(target.yaw/2)+p.qw*math.cos(target.yaw/2))
    return distance<=0.05 and dot>=math.cos(0.02/2)
end
function M.new(engine,log)
    local token={}
    return setmetatable({engine=engine,log=log,slots={},serial=0,token=token,
        instance=tostring(token),pumping=false,closed=false,logCount=0},Controller)
end
function Controller:start(slot,profile,pose)
    if self.closed then return false,"fixture_shutdown" end
    if type(slot)~="string" or #slot>32 or not slot:match("^[A-Za-z][A-Za-z0-9_-]*$") then return false,"invalid_slot" end
    if type(profile)~="string" or not self.engine:profile(profile) then return false,"unsupported_profile" end
    if not validPose(pose) then return false,"invalid_pose" end
    if self.slots[slot] and self.slots[slot].state~="closed" then return false,"slot_owned" end
    local count=0;for _ in pairs(self.slots) do count=count+1 end
    if not self.slots[slot] and count>=MAX_SLOTS then return false,"local_slot_budget" end
    self.serial=self.serial+1
    local e={slot=slot,profile=profile,generation=self.instance..":"..self.serial,
        target=poseCopy(pose),state="start_queued",visualQualified=false,placementVerified=false}
    self.slots[slot]=e -- reserve immediately, before a second queued start
    return true,e.generation
end
function Controller:move(slot,generation,pose)
    local e=self.slots[slot]
    if self.closed or not e or e.generation~=generation then return false,"stale_generation" end
    if e.retiring or e.state~="ready" or e.movePending or e.queuedMove then return false,"slot_not_ready" end
    if not validPose(pose) then return false,"invalid_pose" end
    e.queuedMove=poseCopy(pose)
    e.state,e.placementVerified,e.observed="move_queued",false,nil
    return true,"move_queued"
end
function Controller:stop(slot)
    local e=self.slots[slot]
    if not e then return false,"unknown_slot" end
    if e.state=="closed" then return true,"closed" end
    e.retiring,e.queuedMove=true,nil
    e.placementVerified,e.observed=false,nil
    e.state="stop_queued"
    return true,"stop_queued"
end
function Controller:reset()
    for slot in pairs(self.slots) do self:stop(slot) end
    return true,"stop_all_queued"
end
function Controller:shutdown()
    self.closed=true
    self:reset()
end
function Controller:status(slot)
    local function snapshot(e)
        local observed=e.observed or {}
        return copy({slot=e.slot,profile=e.profile,generation=e.generation,state=e.state,
            reason=e.reason,entity=e.idKey,requestedAppearance="default",visualQualified=false,
            observedAppearance=observed.observedAppearance,
            observedAppearanceHash=observed.observedAppearanceHash,
            observedColor=observed.observedColor,observedColorHash=observed.observedColorHash,
            visualStateObserved=observed.visualStateObserved==true,
            colorObserved=observed.colorObserved==true,colorMatchVerified=false,
            identityVerified=observed.identityVerified==true,
            identityFault=e.identityFault==true or observed.identityFault==true,
            appearanceNameAvailable=observed.appearanceNameAvailable==true,
            colorNameAvailable=observed.colorNameAvailable==true,
            appearanceVerified=observed.identityVerified==true and observed.visualStateObserved==true
                and observed.appearanceVerified==true and observed.observedAppearance=="default",
            requestedTarget=e.target,queuedTarget=e.queuedMove,submittedTarget=e.submittedTarget,observed=e.observed,
            placementVerified=e.placementVerified==true,moveSubmission=e.moveSubmission,
            retiring=e.retiring==true,spawnAttempted=e.spawnAttempted==true})
    end
    if slot~=nil then return self.slots[slot] and snapshot(self.slots[slot]) or nil end
    local out={};for name,e in pairs(self.slots) do out[name]=snapshot(e) end;return out
end
function Controller:compare(slot,generation,sourceStatus)
    -- Historical supplied source + current cached target only. No engine access,
    -- registration, queue, retained comparison state, or automatic profile choice.
    local target=type(slot)=="string" and self:status(slot) or nil
    return Comparison.report(slot,generation,sourceStatus,target)
end
function Controller:_step(e)
    if e.state=="closed" then return end
    if e.retiring then
        e.placementVerified,e.observed=false,nil
        local ok,done=pcall(self.engine.retire,self.engine,e)
        if ok and done==true then e.state,e.reason="closed",nil
        else e.state,e.reason="retirement_pending",e.identityFault and "owned_native_identity_mismatch"
            or (ok and "awaiting_disappearance" or tostring(done)) end
        return
    end
    if e.state=="start_queued" then
        local ok,result=pcall(self.engine.create,self.engine,e)
        if not ok or result~=true then
            e.reason=tostring(result)
            e.state=e.spawnAttempted and "spawn_outcome_unknown" or "closed"
            return
        end
        e.submittedTarget=poseCopy(e.target)
        e.state="spawn_pending"
        return -- a command returning is not a readback
    end
    if e.state=="spawn_outcome_unknown" and not e.idKey then return end
    local ok,o=pcall(self.engine.observe,self.engine,e)
    if not ok or type(o)~="table" then
        e.state,e.reason="observation_unknown",tostring(o)
        e.placementVerified,e.observed=false,nil
        return
    end
    e.observed=copy(o)
    local appearanceVerified=o.identityVerified==true and o.visualStateObserved==true
        and o.appearanceVerified==true and o.observedAppearance=="default"
    e.placementVerified=matched(o.pose,e.target) and o.ready==true and o.templateVerified==true
        and o.rootVerified==true and appearanceVerified
    if o.visualFault then e.state,e.reason="visual_mismatch",o.visualFault;return end
    if o.ready==true and not appearanceVerified then e.state,e.reason="visual_mismatch","appearance_unverified";return end
    if not (o.ready==true and o.templateVerified==true and o.rootVerified==true and appearanceVerified and o.pose) then
        e.state,e.reason="spawn_pending","awaiting_ready_actor";return
    end
    if e.queuedMove then
        local target=e.queuedMove;e.queuedMove=nil
        -- A preflight failure is different from an attempted native mutation.
        e.moveAttempted=false
        local submitted,result=pcall(self.engine.move,self.engine,e,target)
        if not e.moveAttempted then
            e.moveSubmission,e.state,e.reason="rejected","move_rejected",tostring(result)
            -- Final native preflight may contradict the earlier cached sample.
            e.placementVerified,e.observed=false,nil
            return
        end
        -- Keep unknown native outcomes observable; never automatically reissue.
        e.target=target;e.submittedTarget=poseCopy(target);e.movePending=true
        e.moveSubmission=submitted and result==true and "submitted" or "unknown"
        e.state,e.reason="move_pending",submitted and nil or tostring(result)
        e.placementVerified,e.observed=false,nil
        return
    end
    if e.movePending then
        if not e.placementVerified then e.state="move_pending";return end
        e.movePending=false
    end
    e.state,e.reason="ready",nil
end
function Controller:pump()
    if self.pumping then return false end
    self.pumping=true
    for _,e in pairs(self.slots) do
        local ok,why=pcall(self._step,self,e)
        if not ok then
            e.state,e.reason="observation_unknown",tostring(why)
            e.placementVerified,e.observed=false,nil
        end
        -- Log changed appearance evidence even when the state stays mismatched.
        -- Unchanged frames stay silent and the instance limit still applies.
        local observed=e.observed or {}
        local message=e.state..":"..tostring(e.reason)..":"..tostring(observed.observedAppearance)
            ..":"..tostring(observed.appearanceVerified)..":"..tostring(observed.observedAppearanceHash)
            ..":"..tostring(observed.observedColor)..":"..tostring(observed.observedColorHash)
            ..":"..tostring(observed.visualStateObserved)
        if self.log and self.logCount<64 and e.lastLog~=message then
            e.lastLog=message
            self.logCount=self.logCount+1
            pcall(self.log,e.slot,e.state,e.reason,self:status(e.slot))
        end
    end
    self.pumping=false
    return true
end
return M
