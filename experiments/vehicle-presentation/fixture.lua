-- Local game-thread fixture only. No SessionEntityId allocation or networking.
local Fixture = {}
Fixture.__index = Fixture
local seats = {seat_front_left=true, seat_front_right=true, seat_back_left=true, seat_back_right=true}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function id(s)
    return type(s)=="string" and s:match("^[1-9][0-9]*$") and #s<=20
        and (#s<20 or s<="18446744073709551615")
end
local function pose(p)
    if type(p)~="table" then return false end
    for _,k in ipairs({"x","y","z","qx","qy","qz","qw"}) do
        if not finite(p[k]) then return false end
    end
    local norm=p.qx*p.qx+p.qy*p.qy+p.qz*p.qz+p.qw*p.qw
    return math.abs(p.x)<100000 and math.abs(p.y)<100000 and math.abs(p.z)<100000
        and math.abs(norm-1)<0.001
end
local function copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
function Fixture.new(engine, descriptor, report)
    assert(type(engine)=="table" and type(descriptor)=="table")
    assert(descriptor.record=="Vehicle.v_standard2_archer_hella_player"
        and type(descriptor.appearance)=="string" and descriptor.appearance~=""
        and descriptor.color=="None", "unsupported vehicle descriptor")
    return setmetatable({engine=engine,descriptor=copy(descriptor),report=report or function() end,
        state="idle",time=0,nextRequest=1,deleteAttempts=0,events=0,eventReceipts={},eventOrder={}},Fixture)
end
function Fixture:_status(state, detail)
    if self.state~=state then self.report("state",{state=state,detail=detail,id=self.id,time=self.time}) end
    self.state=state
end
function Fixture:start(target)
    if self.state~="idle" or not pose(target) then return false,"invalid_start" end
    self.target=copy(target)
    -- A thrown create call has an unknown outcome. Never retry automatically.
    self:_status("creating")
    local ok,result,creator=pcall(self.engine.create,self.engine,self.descriptor,self.target)
    if not ok or not id(result) then self:_status("create_unresolved"); return false,"create_unresolved" end
    self.id=result
    if not id(creator) then self.identityFault=true; self:_status("creator_unresolved"); return false,"creator_unresolved" end
    self.player=creator; self:_status("spawning"); return true
end
local function safeObservation(o, expected)
    if type(o)~="table" or o.id~=expected then return false end
    for _,k in ipairs({"managed","spawning","spawned","attached","worldPresent","populationPresent","retainedAttached"}) do
        if type(o[k])~="boolean" then return false end
    end
    if o.attached then
        if not pose(o.pose) or not finite(o.speed) or o.speed<0 or type(o.occupants)~="table"
            or not id(o.player) or type(o.onFoot)~="boolean" or type(o.slots)~="table"
            or type(o.events)~="table" or o.eventOverflow~=false
            or type(o.playerMount)~="table" then return false end
        if #o.occupants>4 or #o.events>64 then return false end
        local mount=o.playerMount
        if mount.parent~=nil and (not id(mount.parent) or mount.child~=o.player or type(mount.slot)~="string") then return false end
        if o.onFoot and mount.parent~=nil then return false end
        local occupied, children={},{}
        for _,v in ipairs(o.occupants) do
            if type(v)~="table" or v.parent~=expected or not id(v.child)
                or not seats[v.slot] or occupied[v.slot] or children[v.child] then return false end
            occupied[v.slot]=true; children[v.child]=true
        end
    end
    return true
end
function Fixture:_safeEmpty(o)
    return o.attached and o.managed and o.spawned and not o.spawning and #o.occupants==0
        and o.onFoot and o.player==self.player and o.speed<0.2
end
function Fixture:_relationship(o, child, seat)
    if o.playerMount.parent~=self.id or o.playerMount.child~=child or o.playerMount.slot~=seat then return false end
    for _,v in ipairs(o.occupants) do if v.child==child then return v.slot==seat end end
    return false
end
function Fixture:request(operation, seat)
    local o=self.last
    if self.state~="ready" or self.retiring or self.pending or not o
        or not o.attached or not o.managed or not o.spawned or o.spawning or o.speed>=0.2 then return false,"not_ready" end
    if operation~="mount" and operation~="unmount" then return false,"invalid_operation" end
    if not seats[seat] or o.slots[seat]~=true then return false,"unsupported_seat" end
    if operation=="mount" then
        if not o.onFoot then return false,"player_not_on_foot" end
        for _,v in ipairs(o.occupants) do if v.slot==seat or v.child==self.player then return false,"occupied" end end
    elseif not self:_relationship(o,self.player,seat) then return false,"wrong_relationship" end
    local pending={operation=operation,seat=seat,child=self.player,started=self.time,
        request=self.nextRequest,afterEvent=self.events,finished=false,timedOut=false}
    self.nextRequest=self.nextRequest+1; self.pending=pending
    local ok,queued=pcall(self.engine.request,self.engine,self.id,self.player,operation,seat)
    -- A thrown request may have reached the engine. Retain its unresolved owner.
    if not ok then pending.timedOut=true; self:_status("request_unresolved"); return false,"request_unresolved" end
    if queued~=true then self.pending=nil; return false,"request_rejected" end
    self:_status("request_pending"); return true,"queued"
end
function Fixture:stop()
    if self.state=="idle" or self.state=="closed" then return true end
    self.retiring=true
    return false -- No immediate deletion, especially during asynchronous creation.
end
function Fixture:step(dt,paused)
    if self.state=="idle" or self.state=="closed" then return end
    if not finite(dt) or dt<0 or type(paused)~="boolean" then
        self.stableSince=nil; self.absentSince=nil; self.last=nil
        self:_status("clock_unavailable"); return
    end
    if paused then self.stableSince=nil; self.absentSince=nil; self.last=nil; return end
    self.time=self.time+dt
    if not self.id or self.identityFault then return end
    local ok,o=pcall(self.engine.observe,self.engine,self.id)
    if not ok or not safeObservation(o,self.id) then
        self.stableSince=nil; self.absentSince=nil; self.last=nil
        self:_status("observation_unavailable",ok and "invalid_readback" or tostring(o):sub(1,200)); return
    end
    self.last=o
    if o.attached then
        if self.player and self.player~=o.player then
            self.identityFault=true; self:_status("player_changed"); return
        end
        self.player=o.player
        self.seenAttached=true
        if o.spawning or not o.managed or not o.spawned then self.stableSince=nil else self.stableSince=self.stableSince or self.time end
        -- Validate the entire batch before consuming any event. Native readback
        -- is a peek: exceptions or rejected samples must not lose completion.
        local previous=0
        for _,event in ipairs(o.events) do
            if type(event)~="table" or not finite(event.serial) or event.serial<=previous or event.serial>100000 or event.serial%1~=0
                or not id(event.child) or not seats[event.slot] or type(event.mounting)~="boolean" then
                self.identityFault=true; self:_status("invalid_event"); return
            end
            previous=event.serial
            if event.serial<=self.events then
                local receipt=self.eventReceipts[event.serial]
                if not receipt or receipt.child~=event.child or receipt.slot~=event.slot or receipt.mounting~=event.mounting then
                    self.identityFault=true; self:_status("changed_event_replay"); return
                end
            end
        end
        for _,event in ipairs(o.events) do
            if event.serial>self.events then
                self.events=event.serial
                self.eventReceipts[event.serial]=copy(event)
                self.eventOrder[#self.eventOrder+1]=event.serial
                if #self.eventOrder>64 then self.eventReceipts[table.remove(self.eventOrder,1)]=nil end
                self.report("seat_event",event)
                local p=self.pending
                if p and event.serial>p.afterEvent and event.child==p.child and event.slot==p.seat
                    and event.mounting==(p.operation=="mount") then p.finished=true end
            end
        end
        if #o.events>0 then
            local ackOk,ack=pcall(self.engine.acknowledge,self.engine,self.id,self.events)
            self.eventAckConfirmed=ackOk and ack==true
        end
        local descriptorMatches=o.record==self.descriptor.record and o.appearance==self.descriptor.appearance
            and o.color==self.descriptor.color
        if not descriptorMatches then self.unsupported=true; self:_status("appearance_mismatch") end
        if self.pending then
            local p=self.pending
            local relationship=self:_relationship(o,p.child,p.seat)
            local childPresent=false
            for _,v in ipairs(o.occupants) do if v.child==p.child then childPresent=true end end
            local observed=p.operation=="mount" and relationship
                or p.operation=="unmount" and o.onFoot and not childPresent
            if observed and p.finished then
                self.report("request_observed",{request=p.request,operation=p.operation,late=p.timedOut,
                    seat=p.seat,child=p.child,camera=o.camera,cameraVerified=false,time=self.time})
                self.pending=nil; self:_status(self.unsupported and "appearance_mismatch" or "ready")
            elseif self.time-p.started>=5 then
                p.timedOut=true; self:_status("request_unresolved")
            end
        elseif not self.unsupported and not self.retiring and self.state~="ready" and self.stableSince
            and self.time-self.stableSince>=0.25 then
            local p=self.target; local a=o.pose
            local distance=math.sqrt((p.x-a.x)^2+(p.y-a.y)^2+(p.z-a.z)^2)
            local dot=math.abs(p.qx*a.qx+p.qy*a.qy+p.qz*a.qz+p.qw*a.qw)
            if distance<=0.5 and dot>=math.cos(math.rad(5)/2) then self:_status("ready")
            else self:_status("placement_unconfirmed") end
        end
    else self.stableSince=nil end
    if self.retiring and not self.pending and not self.identityFault then
        if self.deleteIssued then
            local absent=not o.worldPresent and not o.populationPresent and not o.managed
                and not o.spawning and not o.spawned and not o.attached and not o.retainedAttached
            if absent then
                self.absentSince=self.absentSince or self.time
                if self.time-self.absentSince>=0.25 then self:_status("closed"); return end
            else self.absentSince=nil end
        end
        if self.stableSince and self.time-self.stableSince>=0.25 and self:_safeEmpty(o)
            and self.deleteAttempts<3 and (not self.lastDelete or self.time-self.lastDelete>=0.5) then
            self.deleteAttempts=self.deleteAttempts+1; self.lastDelete=self.time
            -- Issuing a delete is not observing deletion, even when it returns true.
            self.deleteIssued=true
            local deletedOk,accepted=pcall(self.engine.delete,self.engine,self.id)
            self:_status(deletedOk and accepted==true and "retiring" or "delete_unresolved")
        elseif not self.deleteIssued then self:_status("retirement_waiting_for_safe_empty_car") end
    end
    self.report("sample",{time=self.time,state=self.state,id=self.id,observation=o,
        pending=self.pending and copy(self.pending) or nil,eventAckConfirmed=self.eventAckConfirmed,
        cameraVerified=false})
end
Fixture.validId=id
Fixture.validPose=pose
return Fixture
