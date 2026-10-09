local root=assert(arg[1])
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function fixture()
    local f={events={},reports={},attached=true,managed=true,spawning=false,deletes=0,
        visible=false,paused=false,steps=0,reset=0}
    -- Preserve an exact, non-number ID throughout retirement.
    f.id={hash="9007199254740993ULL"}
    local actor={IsAttached=function() return f.attached end,
        GetEntityID=function() return f.id end,
        GetWorldPosition=function() return {x=4,y=2,z=3} end,
        GetWorldOrientation=function() return {ToEulerAngles=function() return {yaw=0} end} end}
    local system={IsReady=function() return true end,
        GetTagged=function() return f.visible and {actor} or {} end,
        GetTaggedIDs=function() return {} end,
        CreateEntity=function() return f.id end,
        DeleteTagged=function() f.deletes=f.deletes+1; f.managed=false end,
        IsManaged=function(_,id) check(id==f.id,"managed lookup retains exact ID"); return f.managed end,
        IsSpawning=function(_,id) check(id==f.id,"spawning lookup retains exact ID"); return f.spawning end}
    local player={IsAttached=function() return true end,
        GetWorldPosition=function() return {x=1,y=2,z=3} end,
        GetWorldOrientation=function() return {ToEulerAngles=function() return {yaw=0} end} end}
    Game={GetPlayer=function() return player end,GetDynamicEntitySystem=function() return system end,
        GetSystemRequestsHandler=function()
            if f.pauseMissing then return nil end
            return {IsGamePaused=function()
                if f.pauseError then error("pause observation unavailable") end
                return f.paused
            end}
        end,
        FindEntityByID=function(id)
            check(id==f.id,"engine lookup retains exact ID")
            if f.lookupError then error("engine unavailable") end
            return actor
        end}
    CName={new=function(v) return v end}; TweakDBID=CName
    Vector4={new=function() return {} end}; NewObject=function() return {} end
    registerForEvent=function(name,callback) f.events[name]=callback end
    json={encode=function(record) f.reports[#f.reports+1]=record; return "mock" end}
    package.loaded.player_pose={new=function(log)
        return {reset=function() f.reset=f.reset+1 end,
            diagnostics=function() return {submissions=f.steps,fault=f.poseFault} end,
            step=function(self,_,_,now,paused)
                f.posePaused=paused
                f.steps=f.steps+1; f.poseNow=now; self.fault=f.poseFault
                if f.poseFault then log("fault="..f.poseFault) end
                return f.poseFault and "fault" or "pending"
            end}
    end}
    f.mod=assert(loadfile(root.."/experiments/player-pose-fixture/init.lua"))()
    function f:has(event)
        for _,record in ipairs(self.reports) do if record.event==event then return true end end
        return false
    end
    function f:last(event)
        for index=#self.reports,1,-1 do
            if self.reports[index].event==event then return self.reports[index] end
        end
    end
    return f
end
local f=fixture()
check(f.mod.start(),"fixture starts")
f.mod.stop()
f.events.onUpdate(0.02)
check(not f:has("retired"),"empty tags and unmanaged do not prove detachment")
check(not f.mod.start(),"cannot spawn during retirement")
f.attached=false; f.spawning=true; f.events.onUpdate(0.02)
check(not f:has("retired"),"pending spawn prevents retirement")
f.spawning=false; f.managed=true; f.events.onUpdate(0.02)
check(not f:has("retired"),"managed ID prevents retirement")
f.managed=false; f.events.onUpdate(0.02)
check(f:has("retired"),"all observations confirm retirement")
check(f.mod.start(),"confirmed retirement permits next trial")

f=fixture(); f.mod.start(); f.mod.stop(); f.events.onUpdate(3.1)
check(f:has("retirement_unconfirmed"),"timeout recorded")
check(not f.mod.start(),"timeout cannot silently permit another actor")
local reports=#f.reports
f.events.onUpdate(5)
check(#f.reports==reports and f.deletes==1,"timeout avoids logging and deletion flood")

f=fixture(); f.mod.start(); f.mod.stop(); f.lookupError=true
check(pcall(f.events.onUpdate,0.02),"lookup failure does not escape callback")
check(f:has("retirement_error"),"lookup failure recorded")
check(not f.mod.start(),"lookup failure blocks duplicate trial")

-- Pause probes must identify observed false separately from unavailable data,
-- without changing the controller's deadline clock or recovering a fault.
f=fixture(); f.mod.start(); f.visible=true; f.events.onUpdate(0.1)
local sample=f:last("sample")
check(sample.pause.status=="observed" and sample.pause.paused==false,
    "running engine is an observed false pause state")
check(sample.dt==0.1 and sample.pose.submissions==1,
    "sample pairs CET delta with controller evidence")
f.paused=true; f.poseFault="readback_timeout"; f.events.onUpdate(3)
sample=f:last("sample")
check(sample.pause.paused==true and sample.pose.fault=="readback_timeout",
    "paused failure records pause and controller diagnosis together")
check(f.steps==2 and f.poseNow==3.1 and f.reset==0 and f.posePaused==true,
    "fixture forwards observed pause while retaining wall time and fault evidence")
local failure=f:last("controller")
check(failure.pause.paused==true and failure.pose.fault=="readback_timeout",
    "controller failure retains pause evidence at failure time")
f.mod.stop()
check(f:last("stop").pose.fault=="readback_timeout" and f.reset==1,
    "stop captures diagnostics before reset")

for _,missing in ipairs({"pauseMissing","pauseError"}) do
    f=fixture(); f.mod.start(); f.visible=true; f[missing]=true
    check(pcall(f.events.onUpdate,0.1),"pause observation cannot escape update")
    sample=f:last("sample")
    check(sample.pause.status==(missing=="pauseError" and "error" or "unavailable")
        and sample.pause.paused==nil,"missing pause data never implies false")
    check(f.steps==1 and not f:has("error"),"pause probe failure does not stop actor trial")
end
print("player_pose_fixture: "..checks.." checks passed")
