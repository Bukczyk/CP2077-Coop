-- Bounded local command queue. No game API access from public methods.
local M={}
local Comparison=require("comparison")
local Controller={};Controller.__index=Controller
local MAX_SLOTS=8 -- local diagnostic budget, unrelated to multiplayer capacity
local MAX_SERIAL=2147483647
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
    return setmetatable({engine=engine,log=log,slots={},logical={},serial=0,token=token,
        instance=tostring(token),pumping=false,closed=false,logCount=0},Controller)
end
function Controller:_logical(slot,profile)
    if self.logical[slot] then return self.logical[slot] end
    -- Literal local subfolder paths work in CET's sandbox. Stage the original
    -- shared modules here; never rely on another mod's bare require cache keys.
    local State=require("cp2077_passive_encounter/presentation_state")
    local Adapter=require("cp2077_passive_encounter/presentation")
    local logical={profile=profile,clock=0,serial=0,dead=false,life="alive",progress=nil}
    logical.state=assert(State.new({capacity=1,maxSerial=MAX_SERIAL,
        reactionDuration=Adapter.clipDuration.reaction,deathDuration=Adapter.clipDuration.death,
        resolve=function(key)
            local e=self.slots[key]
            return e and e.logical==logical and not e.retiring and e.idKey or nil
        end,
        apply=function(frame)
            local e=self.slots[slot]
            if not e or e.logical~=logical then return false end
            local generation=e.generation
            local function current()
                return self.pumping and not self.closed and self.slots[slot]==e and not e.retiring
                    and e.generation==generation and e.idKey==frame.localKey and logical.serial==frame.serial
                    and not e.queuedMove and not e.movePending and e.state=="ready"
            end
            if not current() then return false end
            e.presentationSample={serial=frame.serial,phase=frame.phase,progress=frame.progress,
                generation=generation,entity=frame.localKey,clock=logical.clock}
            return self.engine:present(e,frame,current)
        end}))
    assert(logical.state:reset(self.token,0))
    self.logical[slot]=logical
    return logical
end
local function bodyProfile(logical)
    if logical.life=="defeated" then
        return logical.profile=="judy_encounter" and "judy_defeated" or "mitch_defeated"
    end
    return logical.profile
end
function Controller:_body(slot,profile,pose,logical,prior)
    if self.serial>=MAX_SERIAL then return nil,"body_counter_exhausted" end
    self.serial=self.serial+1
    local e={slot=slot,profile=logical and bodyProfile(logical) or profile,
        generation=self.instance..":"..self.serial,logical=logical,encounter=logical~=nil,
        restoreSerial=prior and prior.serial or 0,restoreDead=prior and prior.dead or false,
        target=poseCopy(pose),state="start_queued",visualQualified=false,placementVerified=false}
    self.slots[slot]=e
    return e
end
function Controller:start(slot,profile,pose)
    if self.closed then return false,"fixture_shutdown" end
    if type(slot)~="string" or #slot>32 or not slot:match("^[A-Za-z][A-Za-z0-9_-]*$") then return false,"invalid_slot" end
    local spec=type(profile)=="string" and self.engine:profile(profile) or nil
    if not spec or spec.defeated==true then return false,"unsupported_profile" end
    if not validPose(pose) then return false,"invalid_pose" end
    if self.slots[slot] and self.slots[slot].state~="closed" then return false,"slot_owned" end
    local count=0;for _ in pairs(self.slots) do count=count+1 end
    if not self.slots[slot] and count>=MAX_SLOTS then return false,"local_slot_budget" end
    if self.logical[slot] and self.logical[slot].profile~=profile then return false,"retained_profile_mismatch" end
    if self.serial>=MAX_SERIAL then return false,"body_counter_exhausted" end
    local prior=self.logical[slot]
    local logical
    if spec.encounter==true then
        local ok,value=pcall(self._logical,self,slot,profile)
        if not ok then return false,"presentation_dependency_unavailable" end
        logical=value
    end
    local e,why=self:_body(slot,profile,pose,logical,prior)
    if not e then return false,why end
    return true,e.generation
end
function Controller:baseline(slot,generation,life,progress)
    local e=self.slots[slot]
    if self.closed or not e or e.generation~=generation then return false,"stale_generation" end
    if not e.encounter then return false,"presentation_profile_unsupported" end
    if life~="alive" and life~="defeated" and life~="dead" then return false,"invalid_life" end
    if life=="defeated" then
        if not finite(progress) or progress<0 or progress>1 then return false,"invalid_progress" end
    elseif progress~=nil then return false,"unexpected_progress" end
    if e.state=="closed" or (e.retiring and not e.transition) then return false,"slot_stopped" end
    local logical=e.logical
    if logical.dead then
        if life~="dead" then return false,"terminal_death" end
        -- A supplied final Dead baseline supersedes a queued/partial death clip.
        if logical.finalDeadBaseline then return true,"terminal_unchanged",logical.serial end
    end
    if logical.serial>=MAX_SERIAL then return false,"presentation_counter_exhausted" end
    logical.serial=logical.serial+1
    logical.life,logical.progress,logical.dead=life,progress,life=="dead"
    logical.finalDeadBaseline=life=="dead"
    -- Supplied final baseline supersedes transient hits and queued movement.
    -- It is retained even while the original body is still owned/retiring.
    e.queuedPresentation,e.queuedMove=nil,nil
    e.baselinePending={life=life,progress=progress,serial=logical.serial}
    if e.profile~=bodyProfile(logical) then
        e.retiring,e.transition=true,true
        e.state="transition_queued"
        e.placementVerified,e.observed=false,nil
    end
    return true,"baseline_queued",logical.serial
end
function Controller:present(slot,generation,kind)
    local e=self.slots[slot]
    if self.closed or not e or e.generation~=generation then return false,"stale_generation" end
    if not e.encounter then return false,"presentation_profile_unsupported" end
    if kind~="reaction" and kind~="death" then return false,"unsupported_presentation" end
    local logical=e.logical
    if logical.dead then return false,"terminal_death" end
    if logical.life~="alive" then return false,"life_not_alive" end
    if e.retiring or e.state~="ready" or e.queuedMove or e.movePending then return false,"slot_not_ready" end
    if e.queuedPresentation and kind~="death" then return false,"presentation_pending" end
    if logical.serial>=MAX_SERIAL then return false,"presentation_counter_exhausted" end
    logical.serial=logical.serial+1
    if kind=="death" then logical.dead,logical.life=true,"dead" end -- retained even before stage/stop
    e.baselinePending=nil
    e.queuedPresentation={kind=kind,serial=logical.serial}
    return true,"presentation_queued",logical.serial
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
    e.transition=false -- explicit stop/reset can never trigger a replacement
    e.retiring,e.queuedMove=true,nil
    e.queuedPresentation,e.presentationSample,e.baselinePending=nil,nil,nil
    if e.encounter then e.presentationSubmission="cancelled_by_stop" end
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
        local logical=e.logical
        local state=logical and logical.state:inspect(self.token,e.slot) or nil
        local presentation=logical and {clock=logical.clock,serial=logical.serial,terminal=logical.dead,
            pending=e.queuedPresentation,desired=state,sample=e.presentationSample,
            life=logical.life,progress=logical.progress,baselinePending=e.baselinePending,
            finalDeadBaseline=logical.finalDeadBaseline==true,
            logicalProfile=logical.profile,desiredProfile=bodyProfile(logical),transition=e.transition==true,
            submission=e.presentationSubmission,reason=e.presentationReason,
            preflightError=e.presentationPreflightError,
            submissionReason=e.presentationSubmissionReason,forwarded=e.presentationForwarded,
            animationObserved=false} or nil
        return copy({slot=e.slot,profile=e.profile,generation=e.generation,state=e.state,
            encounter=e.encounter==true,presentation=presentation,
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
            retiring=e.retiring==true,spawnAttempted=e.spawnAttempted==true,automaticReplacement=e.automatic==true})
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
        if e.presentationBound then
            assert(e.logical.state:unbind(self.token,e.slot,e.idKey,e.logical.clock))
            e.presentationBound=false
        end
        e.placementVerified,e.observed=false,nil
        local ok,done=pcall(self.engine.retire,self.engine,e)
        if ok and done==true then
            e.state,e.reason="closed",nil
            if e.transition and not self.closed and self.slots[e.slot]==e then
                -- No new native creation until the old exact lifetime is gone.
                -- Choose the newest baseline now, never the first request's body.
                local replacement,why=self:_body(e.slot,e.logical.profile,e.target,e.logical,e.logical)
                if not replacement then e.reason=why else
                    replacement.automatic=true
                    replacement.automaticPlayer=e.automaticPlayer or e.originalPlayer
                    replacement.automaticPlayerId=e.automaticPlayerId or e.playerId
                end
                e.transition=false
            end
        else e.state,e.reason="retirement_pending",e.identityFault and "owned_native_identity_mismatch"
            or (ok and "awaiting_disappearance" or tostring(done)) end
        return
    end
    if e.state=="start_queued" or e.state=="spawn_deferred" then
        local function current()
            return self.pumping and not self.closed and self.slots[e.slot]==e and not e.retiring
                and (e.state=="start_queued" or e.state=="spawn_deferred")
                and (not e.logical or e.profile==bodyProfile(e.logical))
        end
        local ok,result=pcall(self.engine.create,self.engine,e,current)
        if e.retiring then
            -- Preserve cancellation or newer life intent raised by a creation
            -- callback, including an unknown outcome after native entry.
            e.state=e.transition and "transition_queued" or "stop_queued"
            e.reason=not ok and tostring(result) or nil
            return
        end
        if not ok or result~=true then
            e.reason=tostring(result)
            e.state=e.spawnAttempted and "spawn_outcome_unknown" or (e.automatic and "spawn_deferred" or "closed")
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
function Controller:_presentation(e,dt)
    if not e.encounter then return end
    e.presentationPreflightError=nil
    if e.retiring or e.state~="ready" then e.presentationReason="slot_not_ready";return end
    local logical=e.logical
    if not finite(dt) or dt<0 or dt>0.25 then e.presentationReason="invalid_delta";return end
    local ready,why=pcall(self.engine.presentationReady,self.engine,e)
    if not ready or why~=true then
        e.presentationReason="context_or_actor_unavailable"
        e.presentationPreflightError=tostring(why):sub(1,256)
        return
    end
    if logical.life=="defeated" then
        local serial=logical.serial
        if e.defeatedAppliedSerial==serial then e.presentationReason="unchanged";return end
        local generation=e.generation
        local function current()
            return self.pumping and not self.closed and self.slots[e.slot]==e and not e.retiring
                and e.generation==generation and logical.serial==serial and logical.life=="defeated"
                and not e.queuedMove and not e.movePending and e.state=="ready"
        end
        local frame={localKey=e.idKey,serial=serial,phase="defeated",progress=logical.progress}
        e.presentationSample={serial=serial,phase=frame.phase,progress=frame.progress,
            generation=generation,entity=e.idKey,clock=logical.clock}
        local accepted=self.engine:present(e,frame,current)
        e.presentationReason=accepted and "queued" or "engine_rejected"
        if accepted and current() then
            e.defeatedAppliedSerial=serial;e.baselinePending=nil
        end
        return -- explicit held sample, no automatic elapsed-time progression
    end
    if not e.presentationBound then
        assert(logical.state:bind(self.token,e.slot,e.idKey,logical.clock))
        -- A logical replacement receives only final state, never an old hit.
        if e.restoreSerial>0 then
            assert(logical.state:restore(self.token,e.slot,e.idKey,e.restoreSerial,
                e.restoreDead and "dead" or "alive",logical.clock))
        end
        e.presentationBound=true
    end
    local baseline=e.baselinePending
    if baseline then
        local ok,reason=logical.state:restore(self.token,e.slot,e.idKey,baseline.serial,baseline.life,logical.clock)
        if not ok then e.presentationReason=reason;return end
        if e.baselinePending==baseline then e.baselinePending=nil end
    end
    local command=e.queuedPresentation
    if command then
        local ok,reason=logical.state:stage(self.token,e.slot,e.idKey,command.serial,command.kind,logical.clock)
        -- A queued fresh command may predate the first bind. Restore only on
        -- replacement; first-body admission must animate normally.
        if not ok then e.presentationReason=reason;return end
        if e.queuedPresentation==command then e.queuedPresentation=nil end
    end
    local ok,reason=logical.state:apply(self.token,e.slot,e.idKey,logical.clock)
    e.presentationReason=reason
    -- Credit time only after this slot's desired sample passed fresh preflight.
    -- Partial/failed setters retry the latest sample without advancing its clock.
    if ok then logical.clock=logical.clock+dt end
end
function Controller:pump(dt)
    if self.pumping then return false end
    self.pumping=true
    for _,e in pairs(self.slots) do
        local ok,why=pcall(self._step,self,e)
        if not ok then
            e.state,e.reason="observation_unknown",tostring(why)
            e.placementVerified,e.observed=false,nil
        end
        if self.slots[e.slot]~=e then e=self.slots[e.slot] end
        if ok then
            local presented,why=pcall(self._presentation,self,e,dt)
            if not presented then
                e.presentationReason="presentation_error"
                e.presentationSubmissionReason=tostring(why)
            end
        end
        -- Log changed appearance evidence even when the state stays mismatched.
        -- Unchanged frames stay silent and the instance limit still applies.
        local observed=e.observed or {}
        local message=e.state..":"..tostring(e.reason)..":"..tostring(observed.observedAppearance)
            ..":"..tostring(observed.appearanceVerified)..":"..tostring(observed.observedAppearanceHash)
            ..":"..tostring(observed.observedColor)..":"..tostring(observed.observedColorHash)
            ..":"..tostring(observed.visualStateObserved)
            ..":"..tostring(e.logical and e.logical.serial)..":"..tostring(e.logical and e.logical.life)
            ..":"..tostring(e.logical and e.logical.progress)..":"..tostring(e.presentationSubmission)
            ..":"..tostring(e.presentationReason)
            ..":"..tostring(e.presentationPreflightError)
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
