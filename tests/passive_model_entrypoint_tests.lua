local root=assert(arg[1])
local checks=0
local function check(v,why) checks=checks+1;assert(v,why) end
local previous=arg[2];arg[2]="helper"
local make=assert(loadfile(root.."/tests/passive_model_engine_tests.lua"))();arg[2]=previous
local folder=root.."/experiments/passive-models/"
local function load(f)
    package.loaded.engine=nil;package.loaded.fixture=nil
    local events={};local savedPrint=print
    print=function(message) f.logs[#f.logs+1]=message end
    registerForEvent=function(name,callback) events[name]=callback end
    registerHotkey=function() error("fixture must not change bindings") end
    local api=assert(loadfile(folder.."init.lua"))()
    print=savedPrint
    local function update()
        local prior=print;print=function(message) f.logs[#f.logs+1]=message end
        events.onUpdate(1/60);print=prior
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
    local getter=a.CP2077PassiveModelFixture_CurrentAppearance
    local function breakAppearance()
        if fault=="missing" then a.CP2077PassiveModelFixture_CurrentAppearance=nil
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
    a.CP2077PassiveModelFixture_CurrentAppearance=getter;a.appearanceError=false;a.appearance="default";tick()
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
print("Passive model real entrypoint checks: "..checks)
