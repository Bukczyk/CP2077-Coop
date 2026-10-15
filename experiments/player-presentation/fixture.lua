local Actions=require("actions")
local Probe=require("aim_probe")
local Engine=require("fixture_engine")
local Fixture={};Fixture.__index=Fixture
local MAX=2147483647
local ENTITY="local-disposable-actor" -- local controller key, never a network ID
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function copy(t,depth)
    if type(t)~="table" then return t end
    if (depth or 0)>5 then return nil end
    local out={};for k,v in pairs(t) do out[k]=copy(v,(depth or 0)+1) end;return out
end
function Fixture.new()
    return setmetatable({generation=0,phase="inactive",reason="explicit_start_required",clock=0,serial=0},Fixture)
end
function Fixture:start(pose)
    if self.closed then return false,"closed" end
    if self.phase~="inactive" and self.phase~="retired" then return false,"already_owned" end
    if type(pose)~="table" or not finite(pose.x) or not finite(pose.y) or not finite(pose.z)
        or not finite(pose.yaw) or math.abs(pose.x)>100000 or math.abs(pose.y)>100000
        or math.abs(pose.z)>100000 or math.abs(pose.yaw)>360 then return false,"invalid_pose" end
    if self.generation>=MAX then return false,"generation_exhausted" end
    self.generation=self.generation+1
    self.pose={x=pose.x,y=pose.y,z=pose.z,yaw=pose.yaw}
    self.phase,self.reason="start_queued","awaiting_update"
    self.stopQueued,self.captureQueued,self.aimQueued=false,false,false
    self.clock,self.actionClock,self.serial,self.stable,self.quiet,self.valid,self.readyLast=0,0,0,0,nil,false,false
    self.actions,self.probe,self.engine,self.bound=nil,nil,nil,false
    self.follow,self.aimPending,self.nextCapture,self.captureIntent=false,false,nil,nil
    self.cleanupRoute=nil
    return self.generation,"queued"
end
function Fixture:capture(generation)
    if self.closed or generation~=self.generation or self.phase~="ready" or self.stopQueued then return false,"not_ready_or_stale" end
    if self.aimQueued or self.aimPending or (self.probe and self.probe:inspect().phase~="complete") then return false,"probe_owned" end
    self.captureQueued,self.follow=true,true;return true,"queued_follow"
end
function Fixture:aim(generation)
    if self.closed or generation~=self.generation or self.phase~="ready" or self.stopQueued then return false,"not_ready_or_stale" end
    if self.aimPending or (self.probe and self.probe:inspect().phase~="complete") then return false,"probe_owned" end
    self.aimQueued=true;return true,"queued"
end
function Fixture:stop()
    if self.phase=="inactive" or self.phase=="retired" then return true,"inactive" end
    self.stopQueued=true;self.captureQueued,self.aimQueued,self.aimPending,self.follow=false,false,false,false
    return true,"queued"
end
function Fixture:shutdown() self.closed=true;self:stop() end
function Fixture:status()
    return {generation=self.generation,phase=self.phase,reason=self.reason,closed=self.closed==true,
        owned=self.engine~=nil and self.phase~="retired",entity=self.engine and self.engine.key,
        creationAttempted=self.engine and self.engine.createAttempted==true or false,
        deleteAttempted=self.engine and self.engine.deleteAttempted==true or false,
        cleanupRoute=self.cleanupRoute,activeSeconds=self.clock,serial=self.serial,
        captureQueued=self.captureQueued==true,aimQueued=self.aimQueued==true,stopQueued=self.stopQueued==true,
        following=self.follow==true,aimPreparing=self.aimPending==true,captureIntent=self.captureIntent,
        actions=self.actions and copy(self.actions:inspect(ENTITY)),probe=self.probe and copy(self.probe:inspect()),
        visualQualified=false}
end
function Fixture:_freeze(reason)
    self.reason=reason;self.valid,self.readyLast=false,false;self.stable,self.quiet=0,nil
end
function Fixture:_stop(now,o)
    self.phase="stopping"
    if not self.engine.createAttempted then self.phase,self.reason="retired","not_created";return end
    if not o.absent then
        self.quiet=nil
        if self.cleanupRoute=="completed_actor_external_removal" then self.cleanupRoute=nil end
    end
    if self.engine.deleteAttempted or (self.engine.completed and o.absent) then
        if not self.engine.deleteAttempted then self.cleanupRoute="completed_actor_external_removal" end
        if o.absent then
            self.quiet=self.quiet or now
            if now-self.quiet>=0.25 then
                self.phase,self.reason="retired","exact_absence_observed"
                self.actions,self.probe=nil,nil -- only now discard uncertain module ownership
                return
            end
            self.reason="absence_qualification_pending"
        else self.quiet=nil;self.reason="retirement_unconfirmed" end
        return
    end
    if not o.ready then self.reason="stable_attachment_required";return end
    if not self.cleanupRoute then
        if self.probe then
            self.probe:stop();self.probe:step(self.actionClock,false)
            local p=self.probe:inspect()
            if p.phase~="complete" and p.phase~="failed" then self.reason="draining_aim_probe";return end
            if p.retirementRequired or p.reservationHeld then self.cleanupRoute="uncertain_probe_exact_retirement" end
        end
        if not self.cleanupRoute and self.bound then
            local ok,reason=self.actions:unbind(self.scope,ENTITY,self.actorKey,self.actionClock)
            if not ok then self.cleanupRoute="unreleased_action_exact_retirement";self.reason=reason end
        end
        self.cleanupRoute=self.cleanupRoute or "released_actions_exact_retirement"
    end
    if self.stable<2 then self.reason="stable_attachment_required";return end
    local ok,accepted=pcall(self.engine.retire,self.engine)
    self.reason=ok and (accepted and "delete_submitted" or "delete_outcome_unconfirmed") or "delete_outcome_unknown"
    self.quiet=nil
end
function Fixture:_update(dt)
    if self.phase=="inactive" or self.phase=="retired" then return end
    if not finite(dt) or dt<0 or dt>1 then self:_freeze("invalid_delta");return end
    if not self.engine then self.engine=Engine.new() end
    -- A rejected pre-call preparation owns no native lifetime. Do not require a
    -- now-replaced player to close work that never reached CreateEntity.
    if self.stopQueued and not self.engine.createAttempted then
        self.phase,self.reason="retired","cancelled_before_create";return
    end
    local context,why=pcall(self.engine.context,self.engine)
    if not context then self:_freeze(tostring(why):match("[^:]+$") or "context_unknown");return end
    if self.phase=="start_queued" then
        if self.stopQueued then self.phase,self.reason="retired","cancelled_before_create";return end
        local created,err=pcall(self.engine.create,self.engine,self.pose)
        self.phase,self.reason=created and "spawning" or "failed",created and "awaiting_attachment" or tostring(err):match("[^:]+$")
        return
    end
    if not self.engine.createAttempted then
        if self.stopQueued then self.phase,self.reason="retired","not_created" end
        return
    end
    local ok,o=pcall(self.engine.observe,self.engine)
    if not ok then self:_freeze(tostring(o):match("[^:]+$") or "observation_unknown");return end
    if self.valid then self.clock=self.clock+dt end
    self.valid=true
    if o.ready and dt>0 then self.stable=self.stable+1 else self.stable=0 end
    if o.ready and self.readyLast then self.actionClock=self.actionClock+dt end
    self.readyLast=o.ready
    if self.stopQueued then self:_stop(self.clock,o);return end
    if not o.ready then self.readyLast=false;self.reason="attachment_pending";return end
    if self.phase=="failed" then return end
    self.phase,self.reason="ready","awaiting_capture"
    if not self.actions then
        self.scope="local-action-fixture:"..self.generation
        self.actions=assert(Actions.new({capacity=1,resolve=function()return self.engine:actor()end}))
        assert(self.actions:reset(self.scope,self.actionClock))
    end
    -- A skipped observation interval must not consume module deadlines.
    local now=self.actionClock
    local probeActive=self.probe and self.probe:inspect().phase~="complete"
    local injectAim=self.aimQueued==true
    if injectAim or (not probeActive and not self.aimPending and
        (self.captureQueued or (self.follow and (not self.nextCapture or now>=self.nextCapture)))) then
        self.captureQueued=false
        self.aimQueued=false
        if self.serial>=MAX then self.phase,self.reason="failed","serial_exhausted";return end
        local captured,state,reason=pcall(self.engine.capture,self.engine,Actions)
        if not captured or not state then self.phase,self.reason="failed",captured and reason or "capture_unavailable";return end
        if injectAim then
            state.aiming=true -- explicit local test intent, not observed physical ADS
            self.aimPending=true
        end
        self.captureIntent=injectAim and "injected_local_aim" or "observed_local_state"
        self.nextCapture=now+0.25
        self.serial=self.serial+1
        local staged,why=self.actions:stage(self.scope,ENTITY,self.serial,state,now)
        if not staged then self.phase,self.reason="failed",why;return end
        if not self.bound then
            local actor=self.engine:actor()
            assert(self.actions:bind(self.scope,ENTITY,actor,now))
            self.actorKey=tostring(self.engine.id.hash);self.bound=true
        end
        self.probe=nil
    end
    if self.probe and self.probe:inspect().phase~="complete" then
        local status,reason=self.probe:step(now,false);self.reason=reason or status
        if status=="failed" then self.phase="failed" end
        if status=="complete" then self.follow,self.nextCapture=true,nil end
    elseif self.bound then
        local status,reason=self.actions:step(self.scope,ENTITY,now,false);self.reason=reason or status
        if status=="failed" then self.phase="failed" end
        if self.aimPending and status=="partial" and reason=="ads_unavailable" then
            self.aimPending=false
            self.probe=assert(Probe.new({enabled=true,actions=self.actions,resolve=function()return self.engine:actor()end}))
            local started,why=self.probe:start(self.scope,ENTITY,now)
            self.reason=why
            if not started then self.phase="failed" end
        end
    end
end
function Fixture:update(dt)
    if self.busy then return end
    self.busy=true
    local ok,why=pcall(self._update,self,dt)
    self.busy=false
    if not ok then self.phase="failed";self:_freeze("update_error:"..tostring(why):sub(-120)) end
end
return Fixture
