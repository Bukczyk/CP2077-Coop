-- Explicit LOCAL measurement only. It never upgrades actions.lua's ADS status.
-- Caller ticks step on the game thread and keeps this object alive until its
-- cleanup is confirmed, or retires the exact disposable actor on failure.
local M={}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function id(a)
    local hash=a:GetEntityID().hash
    if hash==nil or type(hash)=="number" then return nil end
    return tostring(hash)
end
function M.new(config)
    if type(config)~="table" or config.enabled~=true then return nil,"opt_in_required" end
    local actions,resolve=config.actions,config.resolve
    local timeout,hold,settle=config.timeout or 1,config.hold or 1,config.settle or 0.25
    if type(actions)~="table" or type(actions.reserveAimProbe)~="function"
        or type(actions.releaseAimProbe)~="function" or type(resolve)~="function"
        or not finite(timeout) or timeout<0.1 or timeout>2 or not finite(hold) or hold<0 or hold>2
        or not finite(settle) or settle<0.1 or settle>0.5 or settle>=timeout then return nil,"invalid_config" end
    local p={phase="idle",active=0,logicalAimObserved=false,cleanupConfirmed=false,visual="unverified"}
    local busy=false
    local function call(fn,...)
        busy=true; local ok,a=pcall(fn,...); busy=false; return ok,a
    end
    local function fail(reason)
        p.phase,p.reason="failed",reason
        return "failed",reason
    end
    local function exact()
        local ok,current=call(resolve,p.entity)
        local valid,key=call(id,current)
        local original,originalKey=call(id,p.actor)
        return ok and valid and original and key==p.key and originalKey==p.key
    end
    local function unreserve()
        local ok,value=call(function() return actions:releaseAimProbe(p.scope,p.entity,p.token) end)
        if ok and value==true then p.reservationHeld=false; return true end
        return false
    end
    local function rejectBeforeLease(reason)
        if not unreserve() then reason="reservation_release_unconfirmed" end
        return false,select(2,fail(reason))
    end
    local function restore()
        local ok,value=call(function() return p.actor:CP2077Session_RequestAimProbe(p.lease,false) end)
        if not ok or value~=true then return fail("restore_unconfirmed") end
        p.phase,p.at="restoring",p.active
        return "queued","restore_submitted"
    end
    function p:start(scope,entity,now)
        if busy or self.phase~="idle" then return false,"already_started_or_busy" end
        if not finite(now) or now<0 then return false,"invalid_time" end
        local ok,binding=call(function() return actions:reserveAimProbe(scope,entity,now) end)
        if not ok or not binding then return false,"presentation_not_ready" end
        self.scope,self.entity,self.key,self.token,self.weapon=scope,entity,binding.localKey,binding.token,binding.weapon
        self.reservationHeld=true
        self.last,self.at=now,0
        local found,actor=call(resolve,entity); self.actor=actor
        if not found or not exact() then
            return rejectBeforeLease("mapping_changed")
        end
        local acquired,lease=call(function() return actor:CP2077Session_AcquireAimProbe(self.weapon) end)
        if not acquired then self.leaseUncertain=true; return false,select(2,fail("lease_uncertain")) end
        if lease==nil or lease==false then
            return rejectBeforeLease("lease_rejected")
        end
        self.lease,self.leaseOwned=lease,true
        -- From this point a thrown callback may have mutated engine state.
        local sent,accepted=call(function() return actor:CP2077Session_RequestAimProbe(lease,true) end)
        if not sent or accepted~=true then return false,select(2,fail("aim_submission_unconfirmed")) end
        self.phase="awaiting_aim"
        return true,"queued"
    end
    function p:stop()
        if busy then return false,"callback_busy" end
        if self.phase=="idle" or self.phase=="complete" then return true,"inactive" end
        self.stopping=true
        -- Pending Aim must drain before conditional Normal restoration.
        return self.phase~="failed","stop_requested"
    end
    function p:step(now,paused)
        if busy then return "failed","callback_busy" end
        if self.phase=="idle" or self.phase=="complete" or self.phase=="failed" then return self.phase,self.reason end
        if not finite(now) or now<self.last then return fail("invalid_time") end
        if not paused and not self.paused then self.active=self.active+now-self.last end
        self.last,self.paused=now,paused==true
        if paused then return "queued","paused" end
        if not exact() then return fail("mapping_changed") end
        local ok,state=call(function() return self.actor:CP2077Session_ReadAimProbe(self.lease) end)
        if not ok or (state~=0 and state~=1) then return fail("state_conflict_or_unavailable") end
        local held,matches=call(function() return self.actor:CP2077Session_HeldPresentationMatches(self.weapon,true) end)
        if not held or matches~=true then return fail("held_weapon_changed") end
        if self.phase=="awaiting_aim" then
            if state==1 then
                self.logicalAimObserved=true
                if self.active-self.at>=timeout then self.failure="late_aim_readback" end
                if self.stopping or self.failure then return restore() end
                self.phase,self.at="holding",self.active
                return "partial","logical_aim_observed_visual_unverified"
            end
            if self.active-self.at>=timeout then return fail("aim_timeout_retirement_required") end
            return "queued","awaiting_logical_aim"
        elseif self.phase=="holding" then
            if state~=1 then return fail("external_state_change") end
            if self.stopping or self.active-self.at>=hold then return restore() end
            return "partial","logical_aim_observed_visual_unverified"
        elseif self.phase=="restoring" then
            if self.active-self.at>=timeout then self.failure=self.failure or "late_restore_readback" end
            if state==0 then
                self.normalSince=self.normalSince or self.active
                if self.active-self.normalSince>=settle then
                    local released,value=call(function() return self.actor:CP2077Session_ReleaseAimProbe(self.lease) end)
                    if not released or value~=true then return fail("release_unconfirmed") end
                    self.leaseOwned=false
                    self.cleanupConfirmed=true
                    if not unreserve() then return fail("reservation_release_unconfirmed") end
                    if self.failure then return fail(self.failure) end
                    self.phase,self.reason="complete","logical_cycle_observed_visual_unverified"
                    return self.phase,self.reason
                end
            else self.normalSince=nil end
            if self.active-self.at>=timeout then return fail("restore_timeout_retirement_required") end
            return "queued","awaiting_stable_normal"
        end
    end
    function p:inspect()
        return {phase=self.phase,reason=self.reason,localKey=self.key,activeSeconds=self.active,
            logicalAimObserved=self.logicalAimObserved,cleanupConfirmed=self.cleanupConfirmed,
            visual="unverified",reservationHeld=self.reservationHeld==true,
            retirementRequired=self.phase=="failed" and (self.leaseOwned==true or self.leaseUncertain==true)}
    end
    return p
end
return M
