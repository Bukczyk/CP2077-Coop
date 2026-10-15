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
print("Passive model real entrypoint checks: "..checks)
