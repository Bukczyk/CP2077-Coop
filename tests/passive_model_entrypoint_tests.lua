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
    local function update()
        local prior=print;print=function(message) f.logs[#f.logs+1]=message end
        f.inUpdate=true
        local ok,why=pcall(events.onUpdate,1/60)
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
print("Passive model real entrypoint checks: "..checks)
