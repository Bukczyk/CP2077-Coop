local root=assert(arg[1])
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function fixture()
    local f={events={},reports={},attached=true,managed=true,spawning=false,deletes=0}
    -- Preserve an exact, non-number ID throughout retirement.
    f.id={hash="9007199254740993ULL"}
    local actor={IsAttached=function() return f.attached end}
    local system={IsReady=function() return true end,
        GetTagged=function() return {} end,
        GetTaggedIDs=function() return {} end,
        CreateEntity=function() return f.id end,
        DeleteTagged=function() f.deletes=f.deletes+1; f.managed=false end,
        IsManaged=function(_,id) check(id==f.id,"managed lookup retains exact ID"); return f.managed end,
        IsSpawning=function(_,id) check(id==f.id,"spawning lookup retains exact ID"); return f.spawning end}
    local player={IsAttached=function() return true end,
        GetWorldPosition=function() return {x=1,y=2,z=3} end,
        GetWorldOrientation=function() return {ToEulerAngles=function() return {yaw=0} end} end}
    Game={GetPlayer=function() return player end,GetDynamicEntitySystem=function() return system end,
        FindEntityByID=function(id)
            check(id==f.id,"engine lookup retains exact ID")
            if f.lookupError then error("engine unavailable") end
            return actor
        end}
    CName={new=function(v) return v end}; TweakDBID=CName
    Vector4={new=function() return {} end}; NewObject=function() return {} end
    registerForEvent=function(name,callback) f.events[name]=callback end
    json={encode=function(record) f.reports[#f.reports+1]=record; return "mock" end}
    package.loaded.player_pose={new=function() return {reset=function() end} end}
    f.mod=assert(loadfile(root.."/experiments/player-pose-fixture/init.lua"))()
    function f:has(event)
        for _,record in ipairs(self.reports) do if record.event==event then return true end end
        return false
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
print("player_pose_fixture: "..checks.." checks passed")
