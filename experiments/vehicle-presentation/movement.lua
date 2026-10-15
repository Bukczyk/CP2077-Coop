-- Single-call, unoccupied-car pose probe. No networking or continuous renderer.
local Fixture=require("fixture")
local Movement={}
Movement.__index=Movement
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function copy(p) local r={} for k,v in pairs(p) do r[k]=v end return r end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function angle(a,b)
    local dot=math.abs(a.qx*b.qx+a.qy*b.qy+a.qz*b.qz+a.qw*b.qw)
    local na=math.sqrt(a.qx*a.qx+a.qy*a.qy+a.qz*a.qz+a.qw*a.qw)
    local nb=math.sqrt(b.qx*b.qx+b.qy*b.qy+b.qz*b.qz+b.qw*b.qw)
    return math.deg(2*math.acos(math.min(1,dot/(na*nb))))
end
function Movement.new(engine,id,creator,generation,origin,descriptor,report)
    assert(Fixture.validId(id) and Fixture.validId(creator) and Fixture.validPose(origin))
    assert(type(generation)=="number" and generation%1==0 and generation>0 and generation<=1000000000)
    return setmetatable({engine=engine,id=id,creator=creator,generation=generation,origin=copy(origin),
        descriptor=copy(descriptor),report=report or function() end,state="idle",time=0,serial=0,enabled=false},Movement)
end
function Movement:_fault(reason)
    if not self.fault then self.fault=reason;self.report("movement_fault",{reason=reason,id=self.id,generation=self.generation}) end
    self.state="unresolved"
end
function Movement:_safe(o)
    return type(o)=="table" and o.id==self.id and o.player==self.creator and Fixture.validPose(o.pose)
        and o.attached==true and o.retainedAttached==true and o.worldPresent==true and o.populationPresent==true
        and o.managed==true and o.spawned==true and o.spawning==false and o.onFoot==true
        and type(o.occupants)=="table" and next(o.occupants)==nil
        and type(o.playerMount)=="table" and o.playerMount.parent==nil
        and finite(o.speed) and o.speed>=0 and o.speed<0.2 and o.eventOverflow==false
        and o.record==self.descriptor.record and o.appearance==self.descriptor.appearance and o.color==self.descriptor.color
end
function Movement:setEnabled(enabled)
    if type(enabled)~="boolean" then return false end
    self.enabled=enabled;return true
end
function Movement:canRetire() return self.pending==nil end
function Movement:update(dt,paused,observation,ownerReady)
    self.last=nil
    if not finite(dt) or dt<0 or type(paused)~="boolean" then
        if self.pending then self.pending.settledSince=nil;self:_fault("clock_unavailable") end
        return
    end
    if paused then if self.pending then self.pending.settledSince=nil end;return end
    self.time=self.time+dt
    if ownerReady~=true or not self:_safe(observation) then
        if self.pending then self.pending.settledSince=nil;self:_fault("unsafe_or_unknown_readback") end
        return
    end
    self.last=observation
    if not self.pending then return end
    local pending=self.pending
    local pe=distance(pending.target,observation.pose)
    local qe=angle(pending.target,observation.pose)
    if pe<=0.025 and qe<=0.5 then
        pending.settledSince=pending.settledSince or self.time
        if self.time-pending.settledSince>=0.25 then
            self.pending=nil
            self.state=self.fault and "observed_after_fault" or "observed"
            self.report("movement_observed",{id=self.id,generation=self.generation,request=pending.serial,
                positionError=pe,orientationErrorDegrees=qe,elapsed=self.time-pending.started,
                late=self.fault~=nil,cameraVerified=false,movementQualified=false})
            return
        end
    else pending.settledSince=nil end
    self.report("movement_readback",{id=self.id,generation=self.generation,request=pending.serial,
        positionError=pe,orientationErrorDegrees=qe,time=self.time,cameraVerified=false})
    if self.time-pending.started>=2 then self:_fault("movement_readback_timeout") end
end
function Movement:submit(target,generation)
    if not self.enabled or generation~=self.generation or self.pending or self.fault
        or not self.last or self.serial>=16 then return false,"unavailable_or_stale" end
    if not Fixture.validPose(target) then return false,"invalid_pose" end
    local travel=distance(target,self.last.pose)
    local turn=angle(target,self.last.pose)
    if travel>0.5 or turn>10 or distance(target,self.origin)>2 or angle(target,self.origin)>30
        or math.abs(target.z-self.origin.z)>0.25 then return false,"outside_probe_bounds" end
    if travel<0.1 and turn<2 then return false,"change_below_probe_resolution" end
    self.serial=self.serial+1
    self.pending={serial=self.serial,target=copy(target),started=self.time}
    local ok,queued=pcall(self.engine.applyPose,self.engine,self.id,self.creator,self.generation,self.serial,target)
    if not ok then self:_fault("application_outcome_unknown");return false,"application_outcome_unknown" end
    if queued~=true then self.pending=nil;return false,"application_rejected" end
    self.state="pending"
    self.report("movement_submitted",{id=self.id,generation=self.generation,request=self.serial,
        target=copy(target),cameraVerified=false,movementQualified=false})
    return true,"queued"
end
function Movement:status()
    return {state=self.state,generation=self.generation,pending=self.pending~=nil,enabled=self.enabled,
        fault=self.fault,requests=self.serial,cameraVerified=false,movementQualified=false}
end
return Movement
