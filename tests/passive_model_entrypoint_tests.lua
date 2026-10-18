local root=assert(arg[1])
local checks=0
local function check(v,why) checks=checks+1;assert(v,why) end
local previous=arg[2];arg[2]="helper"
local make=assert(loadfile(root.."/tests/passive_model_engine_tests.lua"))();arg[2]=previous
local folder=root.."/experiments/passive-models/"
local function load(f)
    f.requireUpdate=true
    package.loaded.engine=nil;package.loaded.fixture=nil
    local events={};local savedPrint=print
    print=function(message) f.logs[#f.logs+1]=message end
    registerForEvent=function(name,callback) events[name]=callback end
    registerHotkey=function() error("fixture must not change bindings") end
    local api=assert(loadfile(folder.."init.lua"))()
    print=savedPrint
    local function update(dt)
        local prior=print;print=function(message) f.logs[#f.logs+1]=message end
        f.inUpdate=true
        local ok,why=pcall(events.onUpdate,dt==nil and 1/60 or dt)
        f.inUpdate=false;print=prior
        assert(ok,why)
    end
    return api,update,events
end
local function p(x) return {x=x,y=0,z=0,yaw=0} end
do
    local f=make();local api,tick,events=load(f)
    check(f.native==0 and f.creates==0,"loading entrypoint does nothing to engine")
    local a,ga=api.start("judy","judy_default",p(2))
    local b,gb=api.start("mitch","mitch_default",p(4))
    check(a and b and ga~=gb and f.native==0,"public start queues independent slots")
    check(not api.start("judy","mitch_default",p(4)),"duplicate queued start")
    api.status();check(f.native==0,"public status reads cached data")
    tick();check(f.creates==2,"both profiles create on update")
    local ids={};for value in pairs(f.tokens) do ids[#ids+1]=value end;table.sort(ids)
    local first,second=f.complete(ids[1]),f.complete(ids[2]);tick()
    local sj,sm=api.status("judy"),api.status("mitch")
    check(sj.profile=="judy_default" and sm.profile=="mitch_default" and sj.entity~=sm.entity,"exact independent profile binding")
    check(sj.observed.template~=sm.observed.template and not sj.visualQualified,"template readback only")
    local logged=table.concat(f.logs,"\n")
    check(logged:find('profile="judy_default"',1,true) and logged:find('profile="mitch_default"',1,true),"diagnostics identify both profiles")
    check(logged:find('generation="'..ga..'"',1,true) and logged:find('entity="'..sj.entity..'"',1,true),"diagnostics pin lifetime and exact actor")
    check(logged:find('observed={x=',1,true) and logged:find('templateHash=',1,true) and logged:find('visualQualified=false',1,true),"diagnostics separate readback and visual qualification")
    local lines=#f.logs;tick();check(#f.logs==lines,"no per-frame diagnostic spam")
    local before=f.native;api.move("judy",ga,p(3));api.stop("judy")
    check(f.native==before,"public move/stop do not invoke engine")
    tick();check(f.moves==0 and f.deletes==1,"stop supersedes queued move")
    local old=sj.entity.."ULL";local alive=sm.entity.."ULL"
    check(f.actors[alive] and not f.actors[alive].disposed,"other slot untouched")
    f.finish(old);tick();check(api.status("judy").state=="closed","exact cleanup completes")
    local restarted,newGen=api.start("judy","mitch_default",p(3))
    check(restarted and newGen~=ga and not api.move("judy",ga,p(2)),"stale generation cannot command replacement")
    local native=f.native;events.onShutdown();check(f.native==native,"shutdown queues only")
    check(not api.start("extra","judy_default",p(2)),"shutdown stops new work")
    tick();check(f.creates==2,"shutdown cancels queued replacement before spawn")
end
do
    local f=make();local api,tick=load(f)
    api.start("late","mitch_default",p(3));tick()
    local value=next(f.tokens);local token=f.tokens[value]
    api.stop("late");tick();check(f.deletes==0,"stop never cancels pending static token")
    f.tokens[value]=nil;tick()
    check(api.status("late").state=="retirement_pending" and f.creates==1,"missing token retains slot")
    f.tokens[value]=token;local a=f.complete(value)
    f.unknownFlags=true;tick();check(f.deletes==0,"nil flags no cleanup")
    f.unknownFlags=false;tick();check(f.deletes==1,"late callback retired exactly once")
    f.actors[value]=nil;tick();check(api.status("late").state=="retirement_pending","global survival")
    f.globals[value]=nil;tick();check(api.status("late").state=="retirement_pending","retained survival")
    a.attached=false;tick();check(api.status("late").state=="closed","observed terminal disappearance")
end
do
    local f=make();local api,tick=load(f)
    local ok,gen=api.start("move","judy_default",p(2));tick();local value=next(f.tokens);local a=f.complete(value);tick()
    check(ok and api.move("move",gen,p(3)),"actual entrypoint queues move")
    tick();check(f.moves==1 and not api.status("move").placementVerified,"void transform call not placement proof")
    tick();check(api.status("move").observed.pose.x==2,"actual pose unchanged")
    a.position=a.submitted.position;a.orientation=a.submitted.orientation;tick()
    check(api.status("move").placementVerified,"later actual pose matches")
    f.creatorError=true;tick()
    check(not api.status("move").placementVerified and not api.status("move").observed,"failed current observation clears qualification")
end
do
    local f=make();local api,tick,events=load(f)
    api.start("old","judy_default",p(2));tick();events.onShutdown()
    -- Reload without a final cleanup update: new Engine owns none of old tags.
    local newApi,newTick=load(f)
    newApi.start("newname","mitch_default",p(4));newTick()
    check(f.creates==1 and newApi.status("newname").state=="closed","historical tag blocks reload replacement even with new slot name")
    check(newApi.status("newname").reason:find("historical_fixture_present",1,true),"clear reload blocker")
end
for _,fault in ipairs({"missing","throwing","nil","None","empty","number","boolean","table","wrong"}) do
    local f=make();local api,tick=load(f)
    local _,generation=api.start("judy","judy_default",p(2))
    api.start("mitch","mitch_default",p(4));tick()
    local first=api.status("judy").entity.."ULL";local second=api.status("mitch").entity.."ULL"
    local a,b=f.complete(first),f.complete(second)
    local getter=a.CP2077PassiveModelFixture_CurrentVisualState
    local function breakAppearance()
        if fault=="missing" then a.CP2077PassiveModelFixture_CurrentVisualState=nil
        elseif fault=="throwing" then a.appearanceError=true
        elseif fault=="nil" then a.appearance=nil
        elseif fault=="None" then a.appearance="None"
        elseif fault=="empty" then a.appearance=""
        elseif fault=="number" then a.appearance=1
        elseif fault=="boolean" then a.appearance=true
        elseif fault=="table" then a.appearance={name="default"}
        else a.appearance="wrong" end
    end
    breakAppearance();tick()
    local s=api.status("judy")
    check(s.state=="visual_mismatch" and not s.appearanceVerified and not s.placementVerified
        and not s.visualQualified,"real entrypoint fails closed on appearance: "..fault)
    check(api.status("mitch").state=="ready" and api.status("mitch").appearanceVerified,
        "other profile independently qualifies")
    local before=f.native
    check(not api.move("judy",generation,p(3)) and f.native==before and f.moves==0,"bad appearance cannot queue native move")
    a.CP2077PassiveModelFixture_CurrentVisualState=getter;a.appearanceError=false;a.appearance="default";tick()
    s=api.status("judy")
    check(s.state=="ready" and s.observedAppearance=="default" and s.appearanceVerified
        and s.placementVerified and not s.visualQualified,"actual later appearance recovers without visual claim")
    breakAppearance();tick();api.stop("judy");tick()
    check(f.deletes==1 and not b.disposed,"missing or wrong appearance never blocks exact isolated cleanup")
    f.finish(first);tick();check(api.status("judy").state=="closed","appearance-independent removal observed")
end

do
    local f=make();local api,tick=load(f)
    local _,generation=api.start("final","judy_default",p(2));tick()
    local value=next(f.tokens);local a=f.complete(value);tick()
    check(api.move("final",generation,p(3)),"valid current appearance admits queued move")
    local lookups=0;local changed=setmetatable({appearance="wrong"},{__index=a})
    f.lookupHook=function()
        lookups=lookups+1
        return lookups<3 and a or changed -- controller sample, adapter preflight, final mutation actor
    end
    tick();local s=api.status("final")
    check(f.moves==0 and s.state=="move_rejected" and s.moveSubmission=="rejected",
        "changed final exact-ID appearance cannot receive transform")
    check(not s.placementVerified and not s.appearanceVerified and not s.observed,
        "contradicted preflight clears cached qualification")
    f.lookupHook=nil;tick()
    check(api.status("final").state=="ready" and api.status("final").appearanceVerified,"fresh appearance evidence recovers")
end

do
    local f=make();local api,tick=load(f);api.start("names","judy_default",p(2));tick()
    local value=next(f.tokens);local a=f.complete(value);a.appearance="wrong_one";tick()
    local count=#f.logs;a.appearance="wrong_two";tick()
    check(#f.logs==count+1 and f.logs[#f.logs]:find('observedAppearance="wrong_two"',1,true)
        and f.logs[#f.logs]:find('appearanceVerified="false"',1,true),"same-state name changes are logged")
    tick();check(#f.logs==count+1,"unchanged name remains silent")
    for i=1,100 do a.appearance="wrong_"..i;tick() end
    check(#f.logs==64 and api.status("names").observedAppearance=="wrong_100",
        "appearance log changes remain bounded without stopping observations")
end
for _,fault in ipairs({"throwing","nil","number","hash_missing","hash_number","hash_overflow","incoherent"}) do
    local f=make();local api,tick=load(f)
    local _,generation=api.start("judy","judy_default",p(2));api.start("mitch","mitch_default",p(4));tick()
    local first=api.status("judy").entity.."ULL";local second=api.status("mitch").entity.."ULL"
    local a,b=f.complete(first),f.complete(second)
    local function breakColor()
        if fault=="throwing" then a.colorError=true
        elseif fault=="nil" then a.color=nil
        elseif fault=="number" then a.color=3
        elseif fault=="hash_missing" then a.colorHash=nil
        elseif fault=="hash_number" then a.colorHash=9007199254740992
        elseif fault=="hash_overflow" then a.colorHash="18446744073709551616"
        else f.visualHook=function(actor) if actor==a then a.color=a.color.."_changed" end end end
    end
    breakColor();tick();local s=api.status("judy")
    check(s.state=="visual_mismatch" and not s.visualStateObserved and not s.colorObserved
        and not s.appearanceVerified and not s.placementVerified,"coherent color fault blocks readiness: "..fault)
    check(api.status("mitch").state=="ready" and api.status("mitch").colorObserved,"sibling remains independent")
    local before=f.native;check(not api.move("judy",generation,p(3)) and f.native==before and f.moves==0,
        "public queue cannot bypass failed pair readback")
    a.colorError=false;a.color="None";a.colorHash="0";f.visualHook=nil;tick();s=api.status("judy")
    check(s.state=="ready" and s.colorObserved and s.observedColor=="None" and s.observedColorHash=="0"
        and not s.colorMatchVerified and not s.visualQualified,"None/zero recovery is observation only")
    breakColor();tick();api.stop("judy");tick()
    check(f.deletes==1 and not b.disposed,"active color fault does not block exact isolated cleanup")
    f.finish(first);tick();check(api.status("judy").state=="closed","color fault cleanup observed")
end
do
    local f=make();local api,tick=load(f);local _,gen=api.start("color","judy_default",p(2));tick()
    local value=next(f.tokens);local a=f.complete(value);tick()
    check(api.move("color",gen,p(3)),"coherent tuple admits queued movement")
    local lookups=0;f.lookupHook=function()
        lookups=lookups+1
        if lookups==3 then a.color="blue";a.colorHash="18446744073709551615" end
        return a
    end
    tick();local s=api.status("color")
    check(f.moves==0 and s.state=="move_rejected" and not s.observed and not s.visualStateObserved,
        "same native actor changed color before mutation clears stale readback")
    f.lookupHook=nil;tick();s=api.status("color")
    check(s.state=="ready" and s.observedColor=="blue" and s.observedColorHash=="18446744073709551615"
        and not s.colorMatchVerified,"new coherent color recoverable but not matching")
    local lines=#f.logs;a.colorHash="9007199254740993";tick()
    check(#f.logs==lines+1 and f.logs[#f.logs]:find('observedColorHash="9007199254740993"',1,true)
        and f.logs[#f.logs]:find('colorMatchVerified=false',1,true),"full hash-only changes logged without false match")
    tick();check(#f.logs==lines+1,"unchanged pair does not flood logs")
    for i=1,100 do a.colorHash=tostring(i);tick() end
    check(#f.logs==64 and api.status("color").observedColorHash=="100","color diagnostics stay bounded")
end
for _,replacement in ipairs({"actor","player","fresh_wrappers"}) do
    local f=make();local api,tick=load(f)
    local _,gen=api.start("pinned","judy_default",p(2));api.start("sibling","mitch_default",p(4));tick()
    local first=api.status("pinned").entity.."ULL";local second=api.status("sibling").entity.."ULL"
    local a=f.complete(first);f.complete(second);tick()
    check(api.status("pinned").visualStateObserved,"first exact native actor pinned")
    if replacement=="actor" then
        local changed=setmetatable({nativeRef={}},{__index=a})
        f.actors[first],f.globals[first]=changed,changed
    elseif replacement=="player" then f.playerNative={}
    else
        f.actors[first]=setmetatable({},{__index=a})
        f.globals[first]=setmetatable({},{__index=a})
    end
    tick();local s=api.status("pinned")
    if replacement=="fresh_wrappers" then
        check(s.state=="ready" and s.visualStateObserved,"fresh wrappers retain same original native identity")
        check(api.move("pinned",gen,p(3)),"fresh wrappers do not falsely block movement")
        tick();check(f.moves==1,"exact original native actor receives bounded transform")
    else
        check(s.state=="visual_mismatch" and not s.visualStateObserved and not s.placementVerified,
            "same ID cannot replace original native "..replacement)
        check(not api.move("pinned",gen,p(3)) and f.moves==0,"replacement cannot acquire movement qualification")
        if replacement=="actor" then check(api.status("sibling").state=="ready","other native actor unaffected") end
    end
end
do
    local f=make();local api,tick=load(f);local _,gen=api.start("final_ref","judy_default",p(2));tick()
    local value=next(f.tokens);local a=f.complete(value);tick()
    check(api.move("final_ref",gen,p(3)),"queue with original native actor")
    local lookups=0;local changed=setmetatable({nativeRef={}},{__index=a})
    f.lookupHook=function()
        lookups=lookups+1
        if lookups==3 then f.globals[value]=changed;return changed end
        return a
    end
    tick();local s=api.status("final_ref")
    check(f.moves==0 and s.state=="move_rejected" and not s.observed,
        "matching tuple/global lookup cannot substitute a new same-ID native actor before mutation")
end
do
    local f=make();local api,tick=load(f);api.start("owned","judy_default",p(2));tick()
    local value=next(f.tokens);local original=f.complete(value);tick()
    local replacement=setmetatable({nativeRef={}},{__index=original})
    f.actors[value],f.globals[value]=replacement,replacement
    api.stop("owned");tick();local s=api.status("owned")
    check(f.deletes==0 and not replacement.disposed and original.attached,
        "same-ID foreign native actor cannot be retired in place of retained original")
    check(s.state=="retirement_pending" and s.identityFault
        and s.reason=="owned_native_identity_mismatch","positive native replacement remains visible and quarantined")
    f.actors[value],f.globals[value]=original,original;tick()
    check(f.deletes==0 and api.status("owned").identityFault,"identity fault remains sticky after original lookup returns")
    f.finish(value);tick()
    check(api.status("owned").state=="retirement_pending" and not api.start("owned","mitch_default",p(3)),
        "positive ownership loss cannot authorize replacement after later absence")
end
for _,fault in ipairs({"unknown","throwing","missing"}) do
    local f=make();local api,tick=load(f);api.start("owned","judy_default",p(2));tick()
    local value=next(f.tokens);local a=f.complete(value);tick()
    local method=a.CP2077PassiveModelFixture_OwnedIdentity
    if fault=="unknown" then f.identityUnknown=true
    elseif fault=="throwing" then f.identityThrows=true
    else a.CP2077PassiveModelFixture_OwnedIdentity=nil end
    api.stop("owned");tick()
    check(f.deletes==0 and api.status("owned").state=="retirement_pending"
        and not api.status("owned").identityFault,"unknown identity blocks removal without inventing foreign actor")
    f.identityUnknown,f.identityThrows=false,false;a.CP2077PassiveModelFixture_OwnedIdentity=method
    a.colorError=true;tick()
    check(f.deletes==1,"recovered exact identity permits cleanup even with throwing color getter")
    f.finish(value);tick();check(api.status("owned").state=="closed","valid exact removal recovery")
end
do
    local f=make();local api,tick=load(f);api.start("final_delete","judy_default",p(2));tick()
    local value=next(f.tokens);local a=f.complete(value);tick()
    local other=setmetatable({nativeRef={}},{__index=a});local lookups=0
    f.lookupHook=function()
        lookups=lookups+1
        if lookups==2 then f.globals[value]=other;return other end
        return a
    end
    api.stop("final_delete");tick()
    check(f.deletes==0 and api.status("final_delete").identityFault,
        "foreign replacement between retirement observation and native call is revalidated")
end
do
    local f=make();local api,tick=load(f);api.start("uncertain","judy_default",p(2));tick()
    local value=next(f.tokens);f.complete(value);tick();f.despawnThrows=true
    api.stop("uncertain");tick();tick();tick()
    check(f.deletes==1 and api.status("uncertain").state=="retirement_pending","unknown native removal is never resubmitted")
    f.finish(value);tick();check(api.status("uncertain").state=="closed","actual later disappearance resolves unknown removal")
end
-- The real public API consumes the copied PR27 observer status schema. Native
-- engine/helper calls remain mocked and update-bound, not live engine evidence.
local function sourceStatus(name)
    local judy=name=="judy_default"
    return {valid=true,reason="captured",scope=3,ticket=12,frame=44,historical=true,visualQualified=false,
        observed={entityId="18446744073709551615",contextId="9007199254740997",
            recordId=judy and "63110975482" or "67785639286",
            templateHash=judy and "18351684596531345670" or "15874478119190254727",
            templatePath=judy and "base\\quest\\secondary_characters\\judy.ent" or "base\\quest\\tertiary_characters\\mitch.ent",
            templatePathAvailable=true,appearance=name,appearanceNameAvailable=true,
            appearanceHash=judy and "14696382396136616853" or "14305357555168828196",
            color="None",colorHash="0",colorNameAvailable=true}}
end
do
    local f=make()
    -- Match the reviewed SDK-computed identifiers in the native shim, while
    -- retaining its checks that every engine read occurs inside onUpdate.
    local original=ResRef.FromName
    ResRef.FromName=function(path)
        local r=original(path)
        if path=="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent" then r.hash="4410265881089470268ULL"
        elseif path=="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid_mitch.ent" then r.hash="5362881734093004222ULL" end
        return r
    end
    local api,tick,events=load(f)
    local _,judy=api.start("judy","judy_default",p(2));local _,mitch=api.start("mitch","mitch_default",p(4))
    local before=f.native
    check(api.compare("judy",judy,sourceStatus("judy_default")).status=="unknown" and f.native==before,
        "comparison before spawn neither reads nor creates")
    tick()
    for value in pairs(f.tokens) do local actor=f.complete(value);actor.appearanceHash="16982411286042166782" end
    tick();before=f.native
    local source=sourceStatus("judy_default")
    local a=api.compare("judy",judy,source)
    local b=api.compare("mitch",mitch,sourceStatus("mitch_default"))
    check(a.status=="candidate_resource_match" and b.status=="candidate_resource_match","both actual entrypoint profiles compare")
    check(f.native==before and f.creates==2 and f.moves==0 and f.deletes==0,"comparison has zero engine reads or mutations")
    check(a.target.entity~=a.source.observed.entityId and a.source.observed.entityId=="18446744073709551615",
        "different exact source and target IDs retained")
    check(not a.visualQualified and not a.colorMatchVerified and not a.resourceBytesVerified,"candidate does not certify rendered parity")
    check(api.compare("mitch",mitch,source).status=="different_profile","wrong explicit slot is reported only")
    check(api.compare("judy","stale",source).reason=="stale_generation","stale generation cannot identify current slot")
    check(api.compare("absent",judy,source).status=="unknown","unknown slot is not created")
    a.source.observed.recordId="mutated";a.target.entity="mutated";a.resourceChain.proxyMesh="mutated"
    check(source.observed.recordId=="63110975482" and api.compare("judy",judy,source).target.entity==api.status("judy").entity,
        "report mutations cannot alter input or cached fixture")
    source.observed.appearanceHash="1"
    check(api.compare("judy",judy,source).status=="invalid_input" and a.source.observed.appearanceHash=="14696382396136616853",
        "input mutation cannot rewrite a previous report")
    source=sourceStatus("judy_default");source.unrelated=source
    check(api.compare("judy",judy,source).status=="candidate_resource_match","unused cyclic data is ignored without traversal")
    check(api.compare("judy",judy,{valid=false,reason="reset_pending",visualQualified=false}).status=="unknown",
        "latest source reset status cannot compare")
    -- An older copied sample is deliberately historical: this pure API cannot
    -- detect a subsequent source-only reset, reload, reconnect or color change.
    local prior=api.compare("judy",judy,source)
    check(prior.status=="candidate_resource_match" and not prior.freshnessVerified and not prior.sourceAuthenticated,
        "old supplied snapshots never gain freshness or authentication")
    f.paused=true
    check(api.compare("judy",judy,source).status=="candidate_resource_match" and f.native==before,
        "before another update comparison is explicitly cached historical evidence")
    tick();check(api.compare("judy",judy,source).status=="candidate_resource_match",
        "read-only fixture observation is allowed while paused; report makes no unpaused claim")
    f.creatorError=true;tick();check(api.compare("judy",judy,source).status=="unknown","failed actual target observation invalidates comparison")
    f.creatorError=false;f.paused=false;tick()
    local value=api.status("judy").entity.."ULL";f.actors[value].color="different";f.actors[value].colorHash="7";tick()
    a=api.compare("judy",judy,source)
    check(a.status=="candidate_resource_match" and not a.colorObservedEqual and not a.colorMatchVerified,"changed color is reported without inventing support")
    check(api.compare("mitch",mitch,sourceStatus("mitch_default")).colorObservedEqual,"sibling color evidence remains independent")
    before=f.native;local logCount=#f.logs
    for _=1,100 do api.compare("judy",judy,source) end
    check(f.native==before and #f.logs==logCount,"repeated reports do not call engine or emit spam")
    api.stop("judy")
    check(api.compare("judy",judy,source).status=="unknown" and f.native==before,"stop invalidates comparison synchronously")
    tick();f.finish(value);tick()
    local _,replacement=api.start("judy","mitch_default",p(2));tick()
    local replacementId=api.status("judy").entity.."ULL"
    f.complete(replacementId).appearanceHash="16982411286042166782";tick()
    check(api.compare("judy",judy,source).reason=="stale_generation","closed and recreated slot rejects prior generation")
    check(api.compare("judy",replacement,sourceStatus("mitch_default")).status=="candidate_resource_match",
        "recreated slot compares only its current explicit generation")
    before=f.native;events.onShutdown()
    check(api.compare("mitch",mitch,sourceStatus("mitch_default")).status=="unknown" and f.native==before,"shutdown stays engine-free and invalidates target")
end
local function encounterReady(profile,dt)
    local f=make();local api,tick,events=load(f)
    local ok,gen=api.start("one",profile or "judy_encounter",p(2));check(ok,"encounter start accepted")
    tick();local value=api.status("one").entity.."ULL";local actor=f.complete(value);tick(dt)
    return f,api,tick,gen,value,actor,events
end
for _,profile in ipairs({"judy_encounter","mitch_encounter"}) do
    local f,api,tick,gen,value,a=encounterReady(profile)
    check(api.status("one").state=="ready" and #f.events==1 and f.events[1].value==0,"first observation submits idle only")
    local before=f.native
    check(api.present("one",gen,"reaction"),"reaction queued through public API")
    local snapshot=api.status("one");snapshot.presentation.pending.kind="death"
    check(f.native==before and #f.events==1 and api.status("one").presentation.pending.kind=="reaction","public status/command engine-free and copied")
    tick(0.1);local s=api.status("one")
    check(#f.events==3 and f.events[2].key=="cp_coop_hit_progress" and f.events[2].value==0 and f.events[3].value==1,"actual shared modules produce native setter pair")
    check(s.presentation.submission=="queued_not_observed" and not s.presentation.animationObserved and not s.visualQualified,"no animation delivery claim")
    for _=1,6 do tick(0.1) end
    check(f.events[#f.events].key=="cp_coop_phase" and f.events[#f.events].value==0,"completed reaction explicitly returns idle")
    before=#f.events;tick(0.1);check(#f.events==before,"idle not resubmitted each frame")
    check(api.present("one",gen,"death"),"terminal sequence admitted")
    tick(0.1);check(f.events[#f.events].value==2,"death phase submitted")
    for _=1,21 do tick(0.1) end
    s=api.status("one")
    check(s.presentation.sample.phase=="dead" and s.presentation.sample.progress==1 and s.presentation.terminal,"final desired death sample retained")
    check(not api.present("one",gen,"reaction"),"terminal body cannot replay reaction")
    before=#f.events;tick();check(#f.events==before,"terminal pose not spammed")
    check(not api.compare("one",gen,sourceStatus("judy_default")).visualQualified,"encounter presentation grants no appearance comparison qualification")
end
for _,kind in ipairs({"reaction","death"}) do
    local f,api,tick,gen=encounterReady("judy_encounter",0/0)
    check(#f.events==0 and api.status("one").state=="ready","invalid delta leaves ready unbound body")
    check(api.present("one",gen,kind),"command admitted before first valid presentation pump")
    tick(0.1);local s=api.status("one").presentation
    check(not s.pending and s.sample.phase==kind and s.sample.progress==0 and s.reason=="queued","first bind preserves fresh command")
end
for _,kind in ipairs({"reaction","death"}) do
    local f,api,tick,gen,value=encounterReady("mitch_encounter")
    check(api.present("one",gen,kind),"pre-stop command admitted")
    local before=f.native;api.reset();check(f.native==before,"reset remains engine-free")
    tick();f.finish(value);tick();check(api.status("one").state=="closed","old body observed gone")
    local ok,newGen=api.start("one","mitch_encounter",p(2));check(ok and newGen~=gen,"replacement explicitly requested")
    tick();local nextId=api.status("one").entity.."ULL";f.complete(nextId);f.events={};tick()
    local s=api.status("one").presentation
    check(s.sample.phase==(kind=="death" and "dead" or "idle") and not s.pending,"retained intent restored without old nonlethal replay")
    check(#f.events==(kind=="death" and 2 or 1),"only final normalized replacement sample")
    if kind=="death" then check(f.events[1].value==1 and f.events[2].value==2,"death admitted before stop survives reset without first stage") end
    check(not api.present("one",gen,"reaction"),"old generation cannot command replacement")
end
do
    local f,api,tick,gen,value=encounterReady("judy_encounter")
    api.present("one",gen,"reaction");tick();api.stop("one");tick();f.finish(value);tick()
    local _,nextGen=api.start("one","judy_encounter",p(2));tick();f.complete(api.status("one").entity.."ULL");tick(0/0)
    check(api.present("one",nextGen,"death"),"fresh death admitted before replacement binding")
    f.events={};tick(0.1);local s=api.status("one").presentation
    check(s.sample.phase=="death" and s.sample.progress==0 and not s.pending,"prior alive restore cannot consume fresh death serial")
end
for _,fault in ipairs({"paused","unknown_pause","missing_context","pregame"}) do
    local f,api,tick,gen=encounterReady("judy_encounter")
    api.present("one",gen,"reaction");tick(0.1)
    local clock=api.status("one").presentation.clock;local before=#f.events
    if fault=="paused" then f.paused=true elseif fault=="unknown_pause" then f.paused=nil
    elseif fault=="missing_context" then f.requests=false else f.preGame=true end
    tick(0.2);tick(0.2)
    check(api.status("one").presentation.clock==clock and #f.events==before,"unavailable context neither forwards nor advances: "..fault)
    f.paused=false;f.requests=true;f.preGame=false;tick(0.1)
    check(api.status("one").presentation.clock>clock and #f.events==before+2,"fresh context resumes same sample clock")
end
for _,fault in ipairs({"throw_first","throw_second","pause","player","actor","stop","new_death"}) do
    local f,api,tick,gen,value,a=encounterReady("judy_encounter")
    api.present("one",gen,"reaction");f.events={}
    f.queueHook=function(actor,event,count)
        if fault=="throw_first" then error("unknown first setter")
        elseif fault=="throw_second" then if count==2 then error("unknown second setter") end
        elseif fault=="pause" then f.paused=true
        elseif fault=="player" then f.playerNative={}
        elseif fault=="actor" then local other=setmetatable({nativeRef={}},{__index=a});f.actors[value],f.globals[value]=other,other
        elseif fault=="stop" then api.stop("one")
        elseif fault=="new_death" then api.present("one",gen,"death") end
    end
    local clock=api.status("one").presentation.clock;tick(0.1)
    local s=api.status("one").presentation
    check(#f.events==(fault=="throw_second" and 2 or 1) and s.clock==clock,"partial sample is frozen: "..fault)
    check(s.submission=="failed_or_partial" and not s.animationObserved,"partial setter outcome not called observed")
    if fault=="throw_first" or fault=="throw_second" or fault=="pause" or fault=="new_death" then
        f.queueHook=nil;f.paused=false;f.events={};tick(0.1)
        s=api.status("one").presentation
        check(#f.events==2 and s.clock>clock and s.submission=="queued_not_observed","latest sample retry after fresh preflight")
        check(f.events[1].key==(fault=="new_death" and "cp_coop_death_progress" or "cp_coop_hit_progress"),"retry never replays superseded reaction")
    elseif fault=="actor" then
        f.queueHook=nil;api.stop("one");tick()
        check(f.deletes==0 and api.status("one").identityFault,"foreign same-ID actor never receives cleanup")
    end
end
do
    local f,api,tick,gen,value,a,events=encounterReady("judy_encounter")
    local _,other=api.start("other","mitch_encounter",p(4));tick();local second=api.status("other").entity.."ULL";f.complete(second);tick()
    api.present("one",gen,"reaction");api.present("other",other,"reaction");tick(0.1)
    a.colorError=true;local frozen=api.status("one").presentation.clock
    for _=1,4 do tick(0.1) end
    check(api.status("one").presentation.clock==frozen and api.status("other").presentation.clock>frozen,"faulted native read freezes only its own logical clock")
    a.colorError=false;tick(0.1)
    check(api.status("one").presentation.reason=="queued" and api.status("one").presentation.clock>frozen,"recovery never hits shared stale time")
    local before=f.native;events.onShutdown();check(f.native==before and not api.present("one",gen,"death"),"shutdown only queues and closes public presentation")
    tick();check(f.deletes==2,"shutdown cleanup can proceed at later update without presentation")
end

local function finishTransition(f,api,tick,oldId,oldGeneration,expected)
    local count=f.creates
    tick();check(f.creates==count and api.status("one").generation==oldGeneration,"retiring body remains sole owned generation")
    f.finish(oldId);tick()
    local s=api.status("one")
    check(s.generation~=oldGeneration and s.profile==expected and s.state=="start_queued" and f.creates==count,
        "observed old absence creates only a queued new generation with latest profile")
    tick();s=api.status("one");local id=s.entity.."ULL";local actor=f.complete(id);f.events={};tick()
    return s.generation,id,actor
end
for _,family in ipairs({"judy","mitch"}) do
    local profile=family.."_encounter"
    local f,api,tick,g,id,a=encounterReady(profile)
    api.present("one",g,"reaction");tick(.1)
    local before=f.native
    check(api.baseline("one",g,"defeated",.35) and f.native==before,"baseline queues only on public surface")
    local st=api.status("one")
    check(st.profile==profile and st.presentation.logicalProfile==profile and st.presentation.life=="defeated"
        and st.presentation.progress==.35 and not st.presentation.terminal,"defeated supplied separately while old immutable body retained")
    local ng,nid,na=finishTransition(f,api,tick,id,g,family.."_defeated")
    check(#f.events==1 and f.events[1].key=="cp_coop_defeated_progress" and f.events[1].value==.35,
        "actual entrypoint submits one normalized held sample through matched graph")
    check(f.events[1].actor==na.nativeRef and not api.status("one").presentation.animationObserved,"exact new actor is not visual success")
    check(not api.baseline("one",g,"dead") and not api.present("one",ng,"reaction"),"stale body and defeated transient reaction rejected")
    local calls=#f.events;for _=1,12 do tick(.1) end
    check(#f.events==calls,"held progress has no elapsed time or auto loop")
    before=f.native;local status=api.status("one");status.presentation.life="dead"
    check(api.status("one").presentation.life=="defeated" and f.native==before,"new baseline diagnostics copied and engine-free")
    check(api.baseline("one",ng,"alive"),"explicit alive baseline requests same-family encounter replacement")
    local ag,aid=finishTransition(f,api,tick,nid,ng,profile)
    check(#f.events==1 and f.events[1].key=="cp_coop_phase" and f.events[1].value==0,"return to alive restores idle without stale hit")
    api.baseline("one",ag,"defeated",.6)
    local dg,did=finishTransition(f,api,tick,aid,ag,family.."_defeated")
    api.baseline("one",dg,"dead")
    local deadg=finishTransition(f,api,tick,did,dg,profile)
    check(#f.events==2 and f.events[1].key=="cp_coop_death_progress" and f.events[1].value==1
        and f.events[2].value==2,"defeated to dead selects final dead pose without death replay")
    check(api.status("one").presentation.terminal and not api.baseline("one",deadg,"alive")
        and not api.baseline("one",deadg,"defeated",0),"terminal dead forbids local resurrection")
    calls=#f.events;check(api.baseline("one",deadg,"dead"),"final dead repeat converges idempotently");tick()
    check(#f.events==calls,"final dead repeat not replayed")
end
for _,begun in ipairs({false,true}) do
    local f,api,tick,g=encounterReady("judy_encounter")
    api.present("one",g,"death");if begun then tick(.1) end
    check(not api.baseline("one",g,"alive"),"transient dead intent already terminal")
    check(api.baseline("one",g,"dead"),"supplied Dead supersedes even queued/begun death")
    f.events={};tick(.1)
    check(#f.events==2 and f.events[1].value==1 and f.events[2].value==2
        and api.status("one").presentation.finalDeadBaseline,"supplied baseline is final, not transient death continuation")
end
for _,latest in ipairs({"alive","defeated","dead"}) do
    local f,api,tick,g,id=encounterReady("mitch_encounter")
    api.baseline("one",g,"defeated",.2);tick()
    check(api.baseline("one",g,latest,latest=="defeated" and .8 or nil),"latest supplied state can replace pending transition")
    local ng=finishTransition(f,api,tick,id,g,latest=="defeated" and "mitch_defeated" or "mitch_encounter")
    check(f.creates==2 and api.status("one").presentation.life==latest,"no obsolete intermediate body spawned")
    check(f.events[1].value==(latest=="defeated" and .8 or latest=="dead" and 1 or 0),"latest desired state is first replacement sample")
end
for _,cancel in ipairs({"stop","reset","shutdown"}) do
    local f,api,tick,g,id,a,events=encounterReady("judy_encounter")
    api.baseline("one",g,"defeated",.4);tick()
    local native=f.native
    if cancel=="stop" then api.stop("one") elseif cancel=="reset" then api.reset() else events.onShutdown() end
    check(f.native==native and not api.baseline("one",g,"alive"),"explicit cancellation cannot be rearmed")
    f.finish(id);tick();tick()
    check(f.creates==1 and api.status("one").state=="closed" and api.status("one").presentation.life=="defeated","cancel keeps supplied state but creates no body")
    if cancel~="shutdown" then
        local ok,ng=api.start("one","judy_encounter",p(2));check(ok and ng~=g,"explicit manual restart after cancellation")
        tick();local nid=api.status("one").entity.."ULL";f.complete(nid);f.events={};tick()
        check(api.status("one").profile=="judy_defeated" and f.events[1].value==.4,"manual same-family restart retains supplied defeated")
    end
end
for _,fault in ipairs({"unknown_flags","retained","foreign_native","unknown_spawn"}) do
    local f,api,tick,g,id,a
    if fault=="unknown_spawn" then
        f=make();api,tick=load(f);local ok;ok,g=api.start("one","judy_encounter",p(2));f.spawnThrows=true;tick()
        check(ok and api.status("one").state=="spawn_outcome_unknown","uncertain native spawn retained")
    else f,api,tick,g,id,a=encounterReady("judy_encounter") end
    api.baseline("one",g,"defeated",.2)
    if fault=="unknown_flags" then f.unknownFlags=true
    elseif fault=="retained" then f.actors[id],f.globals[id]=nil,nil
    elseif fault=="foreign_native" then local foreign=setmetatable({nativeRef={}},{__index=a});f.actors[id],f.globals[id]=foreign,foreign end
    for _=1,4 do tick(.1) end
    check(f.creates==1 and f.deletes==0 and api.status("one").generation==g,"uncertain or foreign old lifetime blocks replacement: "..fault)
end
for _,fault in ipairs({"paused","unknown_pause","requests","pregame","invalid_delta","color","throw_setter"}) do
    local f,api,tick,g,id=encounterReady("judy_encounter");api.baseline("one",g,"defeated",.2)
    local ng,nid,a=finishTransition(f,api,tick,id,g,"judy_defeated")
    api.start("other","mitch_encounter",p(4));tick();local oid=api.status("other").entity.."ULL";f.complete(oid);tick()
    api.present("other",api.status("other").generation,"reaction")
    api.baseline("one",ng,"defeated",.8);f.events={}
    if fault=="paused" then f.paused=true elseif fault=="unknown_pause" then f.paused=nil
    elseif fault=="requests" then f.requests=false elseif fault=="pregame" then f.preGame=true
    elseif fault=="color" then a.colorError=true elseif fault=="throw_setter" then
        f.queueHook=function(actor) if actor.nativeRef==a.nativeRef then error("unknown held submission") end end
    end
    tick(fault=="invalid_delta" and 0/0 or .1)
    local held=0;for _,event in ipairs(f.events) do if event.actor==a.nativeRef then held=held+1 end end
    check(held==(fault=="throw_setter" and 1 or 0),"unknown context/readback prevents held setter: "..fault)
    if fault=="color" or fault=="throw_setter" then check(#f.events>=2,"one slot failure cannot block sibling reaction") end
    f.paused=false;f.requests=true;f.preGame=false;a.colorError=false;f.queueHook=nil
    api.baseline("one",ng,"defeated",.9);f.events={};tick(.1)
    local last;for _,event in ipairs(f.events) do if event.actor==a.nativeRef then last=event end end
    check(last and last.value==.9 and last.key=="cp_coop_defeated_progress","recovery submits newest held sample only")
end


for _,fault in ipairs({"paused","unknown_pause","requests","pregame","missing_resource"}) do
    local f,api,tick,g,id=encounterReady("judy_encounter")
    api.baseline("one",g,"defeated",.25);tick();f.finish(id);tick()
    local nextg=api.status("one").generation
    if fault=="paused" then f.paused=true elseif fault=="unknown_pause" then f.paused=nil
    elseif fault=="requests" then f.requests=false elseif fault=="pregame" then f.preGame=true
    else f.resources[f.engine:profile("judy_defeated").template]=false end
    tick();tick();check(f.creates==1 and api.status("one").state=="spawn_deferred"
        and not api.status("one").spawnAttempted,"definite replacement preflight rejection retains active baseline: "..fault)
    f.paused=false;f.requests=true;f.preGame=false;f.resources={};tick()
    check(f.creates==2 and api.status("one").generation==nextg,"same deferred generation resumes one native creation")
    f.complete(api.status("one").entity.."ULL");f.events={};tick()
    check(f.events[1].value==.25 and api.status("one").state=="ready","deferred replacement eventually presents latest life")
end
do
    local f,api,tick,g,id=encounterReady("mitch_encounter")
    api.baseline("one",g,"defeated",.1);tick();f.finish(id);tick();f.spawnThrows=true;tick()
    check(f.creates==2 and api.status("one").state=="spawn_outcome_unknown","automatic native outcome unknown is retained")
    f.spawnThrows=false;for _=1,4 do tick() end
    check(f.creates==2,"automatic creation is never retried after an actual native attempt")
end
do
    local f,api,tick,g,id=encounterReady("judy_encounter")
    api.baseline("one",g,"defeated",.1);tick();f.finish(id);tick();f.paused=true;tick()
    api.stop("one");f.paused=false;tick();tick()
    check(api.status("one").state=="closed" and f.creates==1,"stop cancels definitely unsubmitted deferred replacement")
end


for _,fault in ipairs({"new_native","new_id","unknown","throw","constructor_swap"}) do
    local f,api,tick,g,id=encounterReady("judy_encounter")
    local original,originalId=f.playerNative,f.playerId
    api.baseline("one",g,"defeated",.3);tick();f.finish(id);tick()
    local constructor=StaticEntitySpec.new
    if fault=="new_native" then f.playerNative={}
    elseif fault=="new_id" then f.playerId="9007199254741997ULL"
    elseif fault=="unknown" then f.playerIdentityUnknown=true
    elseif fault=="throw" then f.playerIdentityThrows=true
    else StaticEntitySpec.new=function() local spec=constructor();f.playerNative={};return spec end end
    tick();tick()
    check(f.creates==1 and api.status("one").state=="spawn_deferred" and not api.status("one").spawnAttempted,
        "automatic replacement cannot transfer supplied baseline to a different or unknown player: "..fault)
    StaticEntitySpec.new=constructor;f.playerNative=original;f.playerId=originalId
    f.playerIdentityUnknown=false;f.playerIdentityThrows=false
    tick();check(f.creates==2,"exact original native context recovers despite fresh Lua wrappers")
    f.complete(api.status("one").entity.."ULL");f.events={};tick()
    check(f.events[1].value==.3 and api.status("one").state=="ready","original context recovery restores supplied sample")
end
do
    local f,api,tick,g,id=encounterReady("mitch_encounter")
    api.baseline("one",g,"defeated",.4);tick();f.playerNative={}
    f.finish(id);tick();tick()
    check(api.status("one").state=="spawn_deferred","different player cannot own automatic continuation")
    api.stop("one");tick()
    check(api.status("one").state=="closed" and f.creates==1,"explicit cleanup can close definitely unsubmitted replacement despite player change")
end

-- Creation preparation may synchronously dispatch another fixture request.
-- Neither initial nor automatic creation may submit an obsolete body afterward.
for _,automatic in ipairs({false,true}) do
    for _,action in ipairs({"stop","reset","shutdown","baseline"}) do
        local f,api,tick,g,id,events
        if automatic then
            local a
            f,api,tick,g,id,a,events=encounterReady("judy_encounter")
            api.baseline("one",g,"defeated",.4);tick();f.finish(id);tick()
        else
            f=make();api,tick,events=load(f)
            local ok;ok,g=api.start("one","judy_encounter",p(2));check(ok,"initial queued body")
        end
        local before=f.creates
        local constructor=StaticEntitySpec.new
        local invoked=false
        StaticEntitySpec.new=function()
            local spec=constructor()
            if not invoked then
                invoked=true
                if action=="stop" then check(api.stop("one"),"callback stop")
                elseif action=="reset" then check(api.reset(),"callback reset")
                elseif action=="shutdown" then events.onShutdown()
                else
                    local progress;if not automatic then progress=.7 end
                    check(api.baseline("one",api.status("one").generation,
                        automatic and "alive" or "defeated",progress),"callback newest baseline")
                end
            end
            return spec
        end
        tick();StaticEntitySpec.new=constructor
        check(invoked and f.creates==before and not api.status("one").spawnAttempted,
            "callback cancellation/supersession prevents obsolete native spawn")
        for _=1,4 do tick() end
        if action=="baseline" then
            local s=api.status("one")
            check(f.creates==before+1 and s.profile==(automatic and "judy_encounter" or "judy_defeated"),
                "newest baseline progresses after cancelled unsubmitted creation")
            f.complete(s.entity.."ULL");f.events={};tick()
            check(f.events[1].key==(automatic and "cp_coop_phase" or "cp_coop_defeated_progress")
                and f.events[1].value==(automatic and 0 or .7),"only latest baseline presented")
        else
            check(f.creates==before and api.status("one").state=="closed",
                "explicit cancellation closes without automatic resurrection")
        end
    end
end

print("Passive model real entrypoint checks: "..checks)
