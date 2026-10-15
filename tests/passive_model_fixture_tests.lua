local root=assert(arg[1])
package.path=root.."/experiments/passive-models/?.lua;"..package.path
local Fixture=require("fixture")
local checks=0
local function check(v,why) checks=checks+1;assert(v,why) end
local function pose(x) return {x=x or 2,y=0,z=0,yaw=0} end
local function observed(x) return {ready=true,templateVerified=true,rootVerified=true,visualQualified=false,
    identityVerified=true,identityFault=false,
    observedAppearance="default",appearanceVerified=true,visualStateObserved=true,
    observedAppearanceHash="9007199254740995",observedColor="None",observedColorHash="0",
    colorObserved=true,appearanceNameAvailable=true,colorNameAvailable=true,colorMatchVerified=false,
    pose={x=x or 2,y=0,z=0,qx=0,qy=0,qz=0,qw=1}} end
local function fixture()
    local engine={calls=0,creates=0,moves=0,deletes=0,world={}}
    function engine:profile(name)
        if name=="judy_default" or name=="mitch_default" then return {name=name} end
    end
    function engine:create(e)
        self.calls=self.calls+1;self.creates=self.creates+1
        if self.createReject then error("missing_resource") end
        e.spawnAttempted=true;e.idKey=e.slot
        self.world[e.slot]={o=observed(e.target.x)}
        if self.createUnknown then e.idKey=nil;error("unknown_create") end
        return true
    end
    function engine:observe(e)
        self.calls=self.calls+1
        local w=self.world[e.slot]
        if w.fail then error("observation_failed") end
        return w.o
    end
    function engine:move(e,target)
        self.calls=self.calls+1
        local w=self.world[e.slot]
        if w.rejectMove then error("move_rejected") end
        e.moveAttempted=true;self.moves=self.moves+1;w.target=target
        if w.applyMove then w.o=observed(target.x) end
        if w.throwMove then error("move_outcome_unknown") end
        return true
    end
    function engine:retire(e)
        self.calls=self.calls+1
        if not e.spawnAttempted then return true end
        local w=self.world[e.slot]
        if w.fail then error("observation_failed") end
        if w.gone then self.deletes=self.deletes+1;return true end
        return false
    end
    local logs={}
    local c=Fixture.new(engine,function(...) logs[#logs+1]={...} end)
    return c,engine,logs
end

do
    local c,e=fixture();local target=pose(2)
    local ok,gen=c:start("judy","judy_default",target)
    check(ok and e.calls==0,"start queues only")
    target.x=999
    check(not c:start("judy","mitch_default",pose()),"queued slot reserved")
    local other,genB=c:start("mitch","mitch_default",pose(4))
    check(other and gen~=genB,"independent generations")
    local snapshot=c:status();snapshot.judy.requestedTarget.x=999;snapshot.judy.profile="mitch_default"
    check(c:status("judy").requestedTarget.x==2 and c:status("judy").profile=="judy_default","input/status copied")
    check(e.calls==0,"status is pure")
    c:pump();check(e.creates==2 and c:status("judy").state=="spawn_pending","create is not readback")
    c:pump();check(c:status("judy").placementVerified and c:status("mitch").placementVerified,"both observed")
    check(not c:status("judy").visualQualified,"never claim visuals")
    e.world.judy.fail=true;c:pump()
    check(not c:status("judy").placementVerified and c:status("judy").observed==nil,"failed observation clears current evidence")
    check(c:status("mitch").placementVerified,"one slot failure does not block another")
    e.world.judy.fail=false;c:pump()
    local before=e.calls
    check(c:move("judy",gen,pose(3)) and e.calls==before,"move queues only")
    check(not c:move("judy",gen,pose(4)),"bounded one queued move")
    check(c:stop("judy") and e.calls==before,"stop queues only")
    check(not c:status("judy").placementVerified,"stopped state cannot retain qualification")
    c:pump();check(e.moves==0 and c:status("judy").state=="retirement_pending","stop supersedes move")
    e.world.judy.gone=true;c:pump()
    check(c:status("judy").state=="closed" and c:status("mitch").state=="ready","isolated closure")
    local again,newGen=c:start("judy","mitch_default",pose(3))
    check(again and newGen~=gen and not c:move("judy",gen,pose()),"stale generation rejected")
end
do
    local c,e=fixture();local _,gen=c:start("one","judy_default",pose());c:pump();c:pump()
    check(c:move("one",gen,pose(3)),"queue movement")
    c:pump()
    local s=c:status("one")
    check(e.moves==1 and s.state=="move_pending" and not s.placementVerified and not s.observed,"submission not readback")
    c:pump();s=c:status("one")
    check(s.state=="move_pending" and s.observed.pose.x==2 and s.submittedTarget.x==3,"actual vs requested")
    c:pump();check(e.moves==1,"never resend automatically")
    e.world.one.o=observed(3);c:pump()
    check(c:status("one").state=="ready" and c:status("one").placementVerified,"later actual readback qualifies")
    e.world.one.rejectMove=true;c:move("one",gen,pose(4));c:pump();s=c:status("one")
    check(s.moveSubmission=="rejected" and s.submittedTarget.x==3 and e.moves==1,"preflight rejection not submitted")
    e.world.one.rejectMove=false;e.world.one.throwMove=true;e.world.one.applyMove=true;c:pump()
    c:move("one",gen,pose(4));c:pump();s=c:status("one")
    check(s.moveSubmission=="unknown" and s.state=="move_pending","unknown native outcome kept")
    c:pump();check(c:status("one").placementVerified and e.moves==2,"unknown outcome resolved by readback")
end
do
    local c,e=fixture()
    check(not c:start("bad.slot","judy_default",pose()),"slot validation")
    check(not c:start("x","unknown",pose()),"profile validation")
    for _,bad in ipairs({{x=0/0,y=0,z=0,yaw=0},{x=1,y=2,z=3},{x=1,y=2,z=3,yaw=math.huge}}) do
        check(not c:start("x","judy_default",bad),"pose validation")
    end
    for i=1,8 do check(c:start("slot"..i,"judy_default",pose()),"bounded named slot") end
    check(not c:start("slot9","judy_default",pose()) and e.calls==0,"local fixture budget")
    c:reset();check(e.calls==0,"reset only queues")
    c:pump();check(e.creates==0,"stop before update cancels unsubmitted creates")
    c:shutdown();check(not c:start("slot1","judy_default",pose()),"closed entrypoint cannot restart")
end
do
    local c,e=fixture();e.createUnknown=true
    c:start("x","judy_default",pose());c:pump();c:pump()
    check(e.creates==1 and c:status("x").state=="spawn_outcome_unknown","unknown create no retry")
    check(not c:start("x","judy_default",pose()),"unknown create retains slot")
end
do
    local c,e,logs=fixture();c:start("x","judy_default",pose());c:pump()
    for i=1,200 do e.world.x.fail=i%2==0;c:pump() end
    check(#logs==64,"total log budget")
end
do
    local c,e,logs=fixture();local _,gen=c:start("one","judy_default",pose());c:pump();c:pump()
    local o=e.world.one.o
    o.observedAppearance="wrong";o.appearanceVerified=true;c:pump()
    check(c:status("one").state=="visual_mismatch" and not c:status("one").placementVerified
        and not c:status("one").appearanceVerified,"exact default name required even with true verification flag")
    check(not c:move("one",gen,pose(3)) and e.moves==0,"mismatched appearance cannot queue movement")
    local count=#logs;o.observedAppearance="different";c:pump()
    check(#logs==count+1,"changed observed name logged within unchanged mismatch state")
    c:pump();check(#logs==count+1,"unchanged appearance does not log every frame")
    o.observedAppearance="default";o.appearanceVerified="true";c:pump()
    check(not c:status("one").appearanceVerified and not c:status("one").placementVerified,"strict Boolean appearance flag")
    o.appearanceVerified=true;c:pump()
    check(c:status("one").state=="ready" and c:status("one").appearanceVerified,"later appearance can recover")
    check(not c:status("one").visualQualified,"correct name is not visible qualification")
end
do
    local c,e,logs=fixture();local _,gen=c:start("color","judy_default",pose());c:pump();c:pump()
    local s=c:status("color")
    check(s.visualStateObserved and s.colorObserved and s.observedColor=="None" and s.observedColorHash=="0",
        "copied coherent color is exposed")
    check(not s.colorMatchVerified and not s.visualQualified,"color observation never becomes a visual match")
    s.observed.observedColor="mutated";s.observedColor="mutated"
    check(c:status("color").observedColor=="None","color status cannot mutate owned evidence")
    local o=e.world.color.o;o.visualStateObserved="true";c:pump()
    check(not c:status("color").appearanceVerified and not c:status("color").placementVerified
        and not c:move("color",gen,pose(3)),"strict coherent-capture Boolean required")
    o.visualStateObserved=true;o.colorMatchVerified=true;c:pump()
    check(c:status("color").state=="ready" and not c:status("color").colorMatchVerified,
        "no backend/caller flag can invent supported color matching")
    local lines=#logs;o.observedColorHash="18446744073709551615";c:pump()
    check(#logs==lines+1,"changed color hash logged even with unchanged name/state")
    c:pump();check(#logs==lines+1,"unchanged pair silent")
    o.observedAppearanceHash="9007199254740997";c:pump()
    check(#logs==lines+2,"changed appearance hash also logged")
end
print("Passive model fixture state/queue checks: "..checks)
