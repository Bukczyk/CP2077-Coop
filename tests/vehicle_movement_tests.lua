local root=assert(arg[1]);package.path=root.."/experiments/vehicle-presentation/?.lua;"..package.path
local Movement=require("movement")
local checks=0
local function check(v,message) checks=checks+1;assert(v,message) end
local function copy(t) if type(t)~="table" then return t end local c={}for k,v in pairs(t)do c[k]=copy(v)end return c end
local ID,PLAYER="9007199254740993","9007199254740995"
local origin={x=10,y=0,z=0,qx=0,qy=0,qz=0,qw=1}
local descriptor={record="Vehicle.v_standard2_archer_hella_player",appearance="fixture_default",color="None"}
local function harness()
    local engine={calls=0};function engine:applyPose(id,player,generation,request,target)
        check(id==ID and player==PLAYER and generation==7 and request>=1)
        self.calls=self.calls+1;self.target=copy(target);return true
    end
    local o={id=ID,player=PLAYER,pose=copy(origin),attached=true,retainedAttached=true,worldPresent=true,populationPresent=true,
        managed=true,spawned=true,spawning=false,onFoot=true,occupants={},playerMount={},speed=0,eventOverflow=false,
        record=descriptor.record,appearance=descriptor.appearance,color=descriptor.color}
    local reports={};local m=Movement.new(engine,ID,PLAYER,7,origin,descriptor,function(k,v)reports[#reports+1]={kind=k,value=copy(v)}end)
    m:update(0.1,false,o,true)
    local target=copy(origin);target.x=target.x+0.3
    return m,engine,o,target,reports
end
local function observe(m,o,target) o.pose=copy(target);m:update(0.1,false,o,true);m:update(0.3,false,o,true) end
do
    local m,e,o,t,reports=harness()
    check(not m:submit(t,7) and e.calls==0)
    check(m:setEnabled(true));check(not m:submit(t,6) and e.calls==0)
    check(m:submit(t,7) and e.calls==1 and m.pending and not m:canRetire())
    check(not m:submit(t,7) and e.calls==1)
    for _=1,10 do m:update(0.1,false,o,true) end
    check(m.pending and m.state=="pending","queued command counted as movement")
    observe(m,o,t);check(m.state=="observed" and m:canRetire() and e.calls==1)
    local result;for _,r in ipairs(reports)do if r.kind=="movement_observed"then result=r.value end end
    check(result and not result.late and result.movementQualified==false and result.cameraVerified==false)
end
do
    local m,e,o,t=harness();m:setEnabled(true)
    for _,field in ipairs({"x","y","z","qx","qy","qz","qw"}) do local bad=copy(t);bad[field]=0/0;check(not m:submit(bad,7)) end
    local far=copy(t);far.x=11;check(not m:submit(far,7))
    local high=copy(t);high.z=0.3;check(not m:submit(high,7))
    local spin=copy(t);spin.qz=math.sin(math.rad(20)/2);spin.qw=math.cos(math.rad(20)/2);check(not m:submit(spin,7))
    check(not m:submit(origin,7));local sign=copy(origin);sign.qw=-1;check(not m:submit(sign,7));check(e.calls==0)
end
do
    local m,e,o,t=harness();m:setEnabled(true)
    -- Pitch-only change must be applied and observed, not reduced to heading.
    t=copy(origin);t.qx=math.sin(math.rad(6)/2);t.qw=math.cos(math.rad(6)/2)
    check(m:submit(t,7));check(e.target.qx==t.qx)
    m:update(0.4,false,o,true);check(m.pending~=nil)
    local equivalent=copy(t);equivalent.qx=-t.qx;equivalent.qw=-t.qw
    observe(m,o,equivalent);check(m.state=="observed")
end
do
    local m,e,o,t=harness();m:setEnabled(true);check(m:submit(t,7));o.pose=copy(t)
    m:update(0.1,false,o,true);m:update(100,true,o,true)
    check(m.pending and not m.fault and e.calls==1)
    m:update(0.1,false,o,true);check(m.pending,"pause preserved settling interval")
    m:update(0.3,false,o,true);check(m:canRetire())
end
do
    local m,e,o,t=harness();m:setEnabled(true);check(m:submit(t,7));m:update(2.1,false,o,true)
    check(m.fault=="movement_readback_timeout" and m.pending and not m:canRetire() and e.calls==1)
    for _=1,10 do m:update(1,false,o,true) end check(e.calls==1)
    observe(m,o,t);check(m.state=="observed_after_fault" and m:canRetire())
    local next=copy(t);next.x=next.x+0.3;check(not m:submit(next,7),"fault auto-reset")
end
for _,change in ipairs({
    function(o)o.id="100"end,function(o)o.player="101"end,function(o)o.spawned=false end,
    function(o)o.spawning=true end,function(o)o.attached=false end,function(o)o.managed=false end,
    function(o)o.retainedAttached=false end,function(o)o.populationPresent=false end,
    function(o)o.worldPresent=false end,function(o)o.onFoot=false end,
    function(o)o.occupants={{child=PLAYER,parent=ID,slot="seat_front_left"}}end,
    function(o)o.playerMount.parent="200"end,function(o)o.speed=0.2 end,function(o)o.speed=-1 end,
    function(o)o.color="custom"end,function(o)o.appearance="other"end,function(o)o.eventOverflow=true end
}) do
    local m,e,o,t=harness();m:setEnabled(true);change(o);m:update(0.1,false,o,true)
    check(not m:submit(t,7) and e.calls==0)
end
do
    local m,e,o,t=harness();m:setEnabled(true);check(m:submit(t,7))
    o.occupants={{child=PLAYER,parent=ID,slot="seat_front_left"}};o.onFoot=false;m:update(0.1,false,o,true)
    check(m.pending and m.fault=="unsafe_or_unknown_readback" and not m:canRetire())
    m:setEnabled(false);check(not m:canRetire(),"disable dropped pending request")
    o.occupants={};o.onFoot=true;observe(m,o,t);check(m:canRetire() and e.calls==1)
end
do
    local m,e,o,t=harness();m:setEnabled(true);function e:applyPose()self.calls=self.calls+1;error("unknown native outcome")end
    check(not m:submit(t,7));check(m.pending and m.fault=="application_outcome_unknown" and e.calls==1)
    observe(m,o,t);check(m:canRetire() and m.state=="observed_after_fault")
end
do
    local m,e,o,t=harness();m:setEnabled(true);function e:applyPose()self.calls=self.calls+1;return false end
    check(not m:submit(t,7));check(m:canRetire() and not m.pending and e.calls==1)
end
do
    local m,e,o,t=harness();m:setEnabled(true);m:update(0.1,nil,o,true);check(not m:submit(t,7))
    m:update(0.1,false,o,true);check(m:submit(t,7));m:update(0/0,false,o,true)
    check(m.pending and m.fault=="clock_unavailable" and e.calls==1)
end
do
    local m,e,o,t=harness();m:setEnabled(true)
    for i=1,16 do local p=copy(origin);p.x=p.x+(i%2==1 and 0.3 or 0);check(m:submit(p,7));observe(m,o,p) end
    check(e.calls==16 and not m:submit(t,7),"request bound missing")
end
-- Retargeting cannot walk outside the activation origin through small steps.
do
    local m,e,o,t=harness();m:setEnabled(true)
    for i=1,4 do local p=copy(origin);p.x=p.x+i*0.5;check(m:submit(p,7));observe(m,o,p) end
    local p=copy(origin);p.x=12.5;check(not m:submit(p,7) and e.calls==4)
end
print("vehicle_movement: "..checks.." checks passed")
