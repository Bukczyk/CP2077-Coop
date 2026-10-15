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
-- Pure comparison uses the observer's actual copied status schema. No fixture
-- profile selection, native hashing, engine lookup or lifecycle mutation occurs.
local Comparison=require("comparison")
local function clone(t)
    if type(t)~="table" then return t end
    local r={};for k,v in pairs(t) do r[k]=clone(v) end;return r
end
local function source(name)
    local judy=name~="mitch_default"
    return {valid=true,reason="captured",scope=2,ticket=17,frame=200,historical=true,visualQualified=false,
        observed={entityId="18446744073709551615",contextId="9007199254740997",
            recordId=judy and "63110975482" or "67785639286",
            templateHash=judy and "18351684596531345670" or "15874478119190254727",
            templatePath=judy and "base\\quest\\secondary_characters\\judy.ent" or "base\\quest\\tertiary_characters\\mitch.ent",
            templatePathAvailable=true,appearance=judy and "judy_default" or "mitch_default",
            appearanceHash=judy and "14696382396136616853" or "14305357555168828196",
            appearanceNameAvailable=true,color="None",colorHash="0",colorNameAvailable=true}}
end
local function target(name)
    name=name or "judy_default"
    local o=observed();o.observedAppearanceHash="16982411286042166782"
    o.template=name=="judy_default" and "base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent"
        or "base\\cp2077coop\\entities\\cp2077coop_networkhumanoid_mitch.ent"
    o.templateHash=name=="judy_default" and "4410265881089470268" or "5362881734093004222"
    local t={slot="one",generation="local:7",profile=name,state="ready",retiring=false,
        entity="9007199254740993",requestedAppearance="default",visualQualified=false,colorMatchVerified=false,observed=o}
    for _,key in ipairs({"observedAppearance","observedAppearanceHash","observedColor","observedColorHash",
        "appearanceNameAvailable","colorNameAvailable","visualStateObserved","colorObserved",
        "identityVerified","identityFault","appearanceVerified"}) do t[key]=o[key] end
    return t
end
for _,name in ipairs({"judy_default","mitch_default"}) do
    local s,t=source(name),target(name)
    local r=Comparison.report("one","local:7",s,t)
    check(r.status=="candidate_resource_match" and r.sourceCandidateProfile==name,"reviewed profile candidate: "..name)
    check(r.source.observed.appearance~=r.target.observedAppearance,"source and proxy appearance names intentionally differ")
    check(r.source.observed.entityId~=r.target.entity and r.source.observed.entityId=="18446744073709551615",
        "distinct actor identities remain exact above double precision")
    check(r.source.scope==2 and r.source.ticket==17 and r.source.frame==200 and not r.target.captureFrameAvailable,
        "asymmetric historical provenance preserved without a fabricated target frame")
    check(r.historical and not r.freshnessVerified and not r.sourceAuthenticated and not r.simultaneousCapture
        and not r.resourceBytesVerified and not r.visualQualified and not r.colorMatchVerified,"no unsupported verification")
    check(r.colorObservedEqual==true and r.resourceChain.appearanceEntry=="default","None/zero is observed equality only")
    r.source.observed.color="mutated";r.target.profile="mutated";r.resourceChain.profile="mutated"
    check(s.observed.color=="None" and t.profile==name and Comparison.report("one","local:7",s,t).resourceChain.profile==name,
        "returned evidence and resource chain are detached copies")
    s.observed.templatePath="";s.observed.templatePathAvailable=false;s.observed.appearance="";s.observed.appearanceNameAvailable=false
    check(Comparison.report("one","local:7",s,t).status=="candidate_resource_match","known hashes establish relationship without inventing observed symbols")
end
do
    local s,t=source(),target("mitch_default")
    local r=Comparison.report("one","local:7",s,t)
    check(r.status=="different_profile" and r.sourceCandidateProfile=="judy_default" and r.target.profile=="mitch_default",
        "explicitly selected wrong profile reported without selecting another")
    t=target();s.observed.color="";s.observed.colorNameAvailable=false
    check(Comparison.report("one","local:7",s,t).colorObservedEqual==false,"same hash with different observed name is not equality")
    s.observed.color="variant";s.observed.colorNameAvailable=true;s.observed.colorHash="9007199254740995"
    r=Comparison.report("one","local:7",s,t)
    check(r.status=="candidate_resource_match" and not r.colorObservedEqual and not r.colorMatchVerified,
        "unreviewed nonzero color neither blocks resource relationship nor becomes supported matching")
end
local sourceCases={
    {"valid string",function(s) s.valid="true" end,"invalid_input"},
    {"wrong reason",function(s) s.reason="queued" end,"invalid_input"},
    {"not historical",function(s) s.historical=false end,"invalid_input"},
    {"visual claim",function(s) s.visualQualified=true end,"invalid_input"},
    {"bad scope",function(s) s.scope=0 end,"invalid_input"},
    {"counter overflow",function(s) s.ticket=2147483648 end,"invalid_input"},
    {"fractional frame",function(s) s.frame=1.5 end,"invalid_input"},
    {"numeric ID",function(s) s.observed.entityId=9007199254740992 end,"invalid_input"},
    {"ID overflow",function(s) s.observed.entityId="18446744073709551616" end,"invalid_input"},
    {"zero ID",function(s) s.observed.contextId="0" end,"invalid_input"},
    {"leading zero",function(s) s.observed.recordId="063110975482" end,"invalid_input"},
    {"unknown record",function(s) s.observed.recordId="1" end,"unsupported_source"},
    {"unknown template",function(s) s.observed.templateHash="1";s.observed.templatePath="";s.observed.templatePathAvailable=false end,"unsupported_source"},
    {"wrong name/hash",function(s) s.observed.appearanceHash="14305357555168828196" end,"invalid_input"},
    {"wrong path/hash",function(s) s.observed.templatePath="base\\quest\\tertiary_characters\\mitch.ent" end,"invalid_input"},
    {"wrong flag",function(s) s.observed.templatePathAvailable=false end,"invalid_input"},
    {"other appearance",function(s) s.observed.appearance="judy_diving_suit";s.observed.appearanceHash="1" end,"unsupported_source"},
    {"absent symbols/unknown hash",function(s) s.observed.appearance="";s.observed.appearanceNameAvailable=false;s.observed.appearanceHash="1" end,"unsupported_source"},
    {"None observed",function(s) s.observed.appearance="None";s.observed.appearanceHash="0" end,"unsupported_source"},
    {"None contradiction",function(s) s.observed.colorHash="1" end,"invalid_input"},
    {"missing color",function(s) s.observed.color=nil end,"invalid_input"},
    {"missing color hash",function(s) s.observed.colorHash=nil end,"invalid_input"},
    {"color flag string",function(s) s.observed.colorNameAvailable="true" end,"invalid_input"},
    {"oversize field",function(s) s.observed.appearance=string.rep("x",257) end,"invalid_input"},
    {"cycle in field",function(s) s.observed.appearance=s end,"invalid_input"},
    {"metatable",function(s) setmetatable(s,{__index=function() error("metamethod called") end}) end,"invalid_input"},
}
for _,case in ipairs(sourceCases) do
    local s=source();case[2](s)
    local ok,r=pcall(Comparison.report,"one","local:7",s,target())
    check(ok and r.status==case[3],"source boundary: "..case[1])
end
for _,reason in ipairs({"queued","reset_pending","paused","target_identity_changed","unloaded","shutdown"}) do
    check(Comparison.report("one","local:7",{valid=false,reason=reason,visualQualified=false},target()).status=="unknown",
        "unavailable source stays unknown: "..reason)
end
local targetCases={
    {"generation",function(t) t.generation="local:8" end,"unknown"},
    {"slot",function(t) t.slot="other" end,"unknown"},
    {"retiring",function(t) t.retiring=true end,"unknown"},
    {"move queued",function(t) t.state="move_queued" end,"unknown"},
    {"identity fault",function(t) t.identityFault=true end,"unknown"},
    {"identity unknown",function(t) t.identityVerified=false end,"unknown"},
    {"template hash",function(t) t.observed.templateHash="1" end,"invalid_input"},
    {"template path",function(t) t.observed.template="wrong" end,"invalid_input"},
    {"template unknown",function(t) t.observed.templateVerified=false end,"unknown"},
    {"root unknown",function(t) t.observed.rootVerified=false end,"unknown"},
    {"numeric entity",function(t) t.entity=9007199254740992 end,"invalid_input"},
    {"color claim",function(t) t.colorMatchVerified=true end,"invalid_input"},
    {"nested claim",function(t) t.observed.colorMatchVerified=true end,"invalid_input"},
    {"appearance hash",function(t) t.observedAppearanceHash="1";t.observed.observedAppearanceHash="1" end,"invalid_input"},
    {"requested appearance",function(t) t.requestedAppearance="other" end,"invalid_input"},
}
for _,case in ipairs(targetCases) do
    local t=target();case[2](t)
    check(Comparison.report("one","local:7",source(),t).status==case[3],"target boundary: "..case[1])
end
for _,field in ipairs({"observedAppearance","observedAppearanceHash","observedColor","observedColorHash",
    "appearanceNameAvailable","colorNameAvailable","visualStateObserved","colorObserved","appearanceVerified"}) do
    local t=target();t.observed[field]=nil
    check(Comparison.report("one","local:7",source(),t).reason=="target_duplicate_"..field,"duplicate disagreement: "..field)
end
do
    local s=source();s.unrelatedCycle=s
    local r=Comparison.report("one","local:7",s,target())
    check(r.status=="candidate_resource_match" and r.source.unrelatedCycle==nil,"unknown cyclic keys are not traversed or copied")
    check(Comparison.report(nil,"local:7",s,target()).status=="invalid_input","invalid call returns bounded failure")
    check(Comparison.report("one","local:7",s,nil).status=="unknown","missing target stays unknown")
    local c,e=fixture();local _,generation=c:start("one","judy_default",pose());c:pump();c:pump()
    c.slots.one.idKey="9007199254740993";e.world.one.o=clone(target().observed);c:pump()
    local calls=e.calls;local result=c:compare("one",generation,source())
    check(result.status=="candidate_resource_match" and e.calls==calls,"controller exposes pure comparison")
    c:stop("one");check(c:compare("one",generation,source()).status=="unknown" and e.calls==calls,"queued stop immediately removes comparison qualification")
end
print("Passive model fixture state/queue checks: "..checks)
