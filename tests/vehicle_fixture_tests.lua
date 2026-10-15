local root=assert(arg[1])
package.path=root.."/experiments/vehicle-presentation/?.lua;"..package.path
local Fixture=require("fixture")
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function clone(t)
    if type(t)~="table" then return t end
    local out={} for k,v in pairs(t) do out[k]=clone(v) end return out
end
local target={x=10,y=20,z=30,qx=0,qy=0,qz=0,qw=1}
local descriptor={record="Vehicle.v_standard2_archer_hella_player",appearance="fixture_default",color="None"}
local CAR,PLAYER="9007199254740993","9007199254740995"
local function harness()
    local engine={created=0,deleted=0,requests=0}
    local sample={id=CAR,managed=true,spawning=false,spawned=true,attached=true,worldPresent=true,populationPresent=true,retainedAttached=true,
        player=PLAYER,onFoot=true,pose=clone(target),speed=0,record=descriptor.record,appearance=descriptor.appearance,color="None",
        occupants={},playerMount={},slots={seat_front_left=true,seat_front_right=true},events={},eventOverflow=false,camera={perspective="FPP"}}
    function engine:create(d,p) self.created=self.created+1; self.descriptor=d; self.target=p; return CAR,PLAYER end
    function engine:observe(id) check(id==CAR,"wrong observation identity"); return clone(sample) end
    function engine:acknowledge(id,serial)
        check(id==CAR,"wrong event ack identity")
        while sample.events[1] and sample.events[1].serial<=serial do table.remove(sample.events,1) end
        return true
    end
    function engine:request(id,child,operation,seat)
        check(id==CAR and child==PLAYER,"wrong request identity"); self.requests=self.requests+1; return true
    end
    function engine:delete(id) check(id==CAR,"wrong delete identity"); self.deleted=self.deleted+1; return true end
    local reports={}
    local f=Fixture.new(engine,descriptor,function(kind,data) reports[#reports+1]={kind=kind,data=clone(data)} end)
    check(f:start(target)); return f,engine,sample,reports
end
local function ready(f) for _=1,5 do f:step(0.1,false) end check(f.state=="ready",f.state) end
local function event(o,serial,mounting,child,slot)
    o.events={{serial=serial,mounting=mounting,child=child or PLAYER,slot=slot or "seat_front_left"}}
end
local function mounted(o,slot,child)
    o.onFoot=false; o.occupants={{parent=CAR,child=child or PLAYER,slot=slot or "seat_front_left"}}
    o.playerMount=clone(o.occupants[1])
end
local function absent(o)
    o.attached=false;o.worldPresent=false;o.populationPresent=false;o.managed=false;o.spawning=false;o.spawned=false;o.retainedAttached=false
end
do
    local f,e,o=harness();o.spawned=false;f:stop()
    for _=1,15 do f:step(0.1,false) end
    check(e.deleted==0,"attached but not spawned car deleted")
    o.spawned=true;f:step(0.1,false);check(e.deleted==0)
    o.spawned=false;f:step(0.3,false);o.spawned=true;f:step(0.1,false);check(e.deleted==0)
    f:step(0.3,false);check(e.deleted==1)
end
do
    local f,e,o=harness();o.player="200"
    for _=1,10 do f:step(0.1,false) end
    check(f.identityFault and f.state=="player_changed" and f.player==PLAYER,
        "replacement before first attachment became creator")
    f:stop();f:step(1,false);check(e.deleted==0 and e.requests==0)
end
do
    local f,e,o,reports=harness();ready(f);check(f:request("mount","seat_front_left"))
    mounted(o);event(o,1,true)
    o.pose.qw=2;f:step(0.1,false);check(f.pending and not f.pending.finished and #o.events==1)
    o.pose.qw=1
    function e:acknowledge() error("ack transport unavailable") end
    f:step(0.1,false);check(f.pending==nil and not f.eventAckConfirmed and #o.events==1)
    f:step(0.1,false);check(not f.identityFault and f.state=="ready")
    local count=0;for _,r in ipairs(reports) do if r.kind=="request_observed" then count=count+1 end end
    check(count==1,"ack replay reapplied completion")
    o.events[1].slot="seat_front_right";f:step(0.1,false);check(f.identityFault)
end
do
    local f,e,o=harness();ready(f);f:stop();f:step(0.1,false);check(e.deleted==1)
    absent(o);o.retainedAttached=true
    for _=1,8 do f:step(0.1,false) end
    check(f.state~="closed","empty lookups ignored retained attached handle")
    check(not f:start(target) and e.created==1)
    o.retainedAttached=false;f:step(0.1,false);check(f.state~="closed");f:step(0.3,false);check(f.state=="closed")
end
check(Fixture.validId(CAR)); check(not Fixture.validId(9007199254740993)); check(not Fixture.validId("0"))
check(not Fixture.validId("18446744073709551616")); check(not Fixture.validId("001"))
check(Fixture.validPose(target))
for _,field in ipairs({"x","y","z","qx","qy","qz","qw"}) do local p=clone(target);p[field]=0/0;check(not Fixture.validPose(p)) end
do local p=clone(target);p.qw=2;check(not Fixture.validPose(p));p.qw=-1;check(Fixture.validPose(p)) end
do
    local f,e,o=harness(); o.spawning=true;o.attached=false;o.worldPresent=false;o.populationPresent=false;o.spawned=false
    f:stop();for _=1,100 do f:step(0.1,false) end
    check(e.deleted==0,"deleted pending spawn")
    o.spawning=false;o.attached=true;o.worldPresent=true;o.populationPresent=true;o.spawned=true
    f:step(0.1,false);check(e.deleted==0);f:step(0.1,false);check(e.deleted==0)
    f:step(0.3,true);check(e.deleted==0);f:step(0.1,false);check(e.deleted==0)
    f:step(0.3,false);check(e.deleted==1)
    check(f.state~="closed","delete accepted was treated as disappeared")
    o.managed=false;o.spawned=false;f:step(0.1,false);check(f.state~="closed")
    absent(o);f:step(0.1,false);check(f.state~="closed");f:step(0.3,false);check(f.state=="closed")
end
do
    local f,e,o=harness(); ready(f)
    check(not f:request("mount","prefix_seat_front_left"));check(not f:request("mount","seat_back_left"));check(e.requests==0)
    o.occupants={{parent=CAR,child="100",slot="seat_front_left"}};f:step(0.1,false)
    check(not f:request("mount","seat_front_left"));check(e.requests==0)
    o.occupants={};f:step(0.1,false);check(f:request("mount","seat_front_left"));check(e.requests==1)
    check(not f:request("mount","seat_front_left"));mounted(o);f:step(0.1,false)
    check(f.pending~=nil,"relationship alone completed request")
    event(o,1,true);f:step(0.1,false);check(f.pending==nil and f.state=="ready")
    f:stop();f:step(1,false);check(e.deleted==0,"deleted occupied car")
    o.onFoot=true;o.occupants={};o.playerMount={};f:step(0.1,false);check(e.deleted==1)
end
do
    local f,e,o,reports=harness();ready(f);check(f:request("mount","seat_front_left"))
    for _=1,20 do f:step(1,true) end check(f.pending and not f.pending.timedOut)
    f:step(5.1,false);check(f.state=="request_unresolved" and f.pending.timedOut)
    f:stop();o.onFoot=true;f:step(1,false);check(e.deleted==0,"released timed out request")
    mounted(o);event(o,1,true);f:step(0.1,false)
    check(f.pending==nil and e.deleted==0)
    local observed=false
    for _,r in ipairs(reports) do if r.kind=="request_observed" then observed=r.data.late and r.data.cameraVerified==false end end
    check(observed,"late completion or camera limit not reported")
end
do
    local f,e,o=harness();ready(f);mounted(o);f:step(0.1,false)
    check(not f:request("unmount","seat_front_right"));check(f:request("unmount","seat_front_left"))
    event(o,1,false);f:step(0.1,false);check(f.pending~=nil,"exit event alone completed request")
    o.occupants={};o.onFoot=false;f:step(0.1,false);check(f.pending~=nil)
    o.onFoot=true;o.playerMount={};f:step(0.1,false);check(f.pending==nil and f.state=="ready")
end
do
    local f,e,o=harness();ready(f);o.occupants={{parent="123",child=PLAYER,slot="seat_front_left"}}
    f:stop();f:step(1,false);check(e.deleted==0 and f.last==nil)
end
do
    local f,e,o=harness();o.pose.x=0
    for _=1,8 do f:step(0.1,false) end check(f.state=="placement_unconfirmed");check(not f:request("mount","seat_front_left"))
    o.pose=clone(target);o.pose.qw=-1;f:step(0.1,false);check(f.state=="ready","quaternion sign equivalence lost")
    o.color="custom_red";f:step(0.1,false);check(f.state=="appearance_mismatch");check(not f:request("mount","seat_front_left"))
    f:stop();f:step(0.1,false);check(e.deleted==1,"owned unsupported appearance cannot be safely retired")
end
do
    local f,e,o=harness();ready(f);check(f:request("mount","seat_front_left"))
    mounted(o);o.playerMount.parent="101";event(o,1,true);f:step(0.1,false)
    check(f.pending~=nil,"one-sided relationship acknowledged")
    o.playerMount.parent=CAR;f:step(0.1,false);check(f.pending==nil)
    check(f:request("unmount","seat_front_left"));event(o,2,false)
    o.onFoot=true;o.playerMount={};f:step(0.1,false)
    check(f.pending~=nil,"remaining child occupant accepted as dismounted")
end
do
    local f,e,o=harness();for _=1,5 do f:step(0.1,false) end
    o.player="200";f:stop();f:step(1,false);check(f.identityFault and e.deleted==0)
end
do
    local f,e,o=harness();for _=1,5 do f:step(0.1,false) end
    o.eventOverflow=true;f:stop();f:step(1,false);check(e.deleted==0 and f.state=="observation_unavailable")
    o.eventOverflow=false;o.occupants={{parent=CAR,child=PLAYER,slot="seat_front_left"},{parent=CAR,child=PLAYER,slot="seat_front_right"}}
    f:step(1,false);check(e.deleted==0)
end
do
    local f,e,o=harness();for _=1,5 do f:step(0.1,false) end
    function e:request() error("ambiguous native request") end
    check(not f:request("mount","seat_front_left"));check(f.pending and f.state=="request_unresolved")
    f:stop();f:step(1,false);check(e.deleted==0)
end
do
    local f,e,o=harness();for _=1,5 do f:step(0.1,false) end
    f:step(0.1,nil);check(not f:request("mount","seat_front_left"));check(e.requests==0)
    f:stop();f:step(1/0,false);check(e.deleted==0)
end
print("vehicle_fixture: "..checks.." checks passed")
