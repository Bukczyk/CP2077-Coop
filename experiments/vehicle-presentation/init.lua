-- Manual local fixture, not a production mod. No automatic activation or keys.
local Fixture=require("fixture")
local Engine=require("engine")
local run,elapsed,lines,bytes=nil,0,0,0
local requestsEnabled=false
local function report(kind,data)
    if lines>=9000 or bytes>=8*1024*1024 then return end
    local line="[CP2077VehicleFixture] "..kind.." "..json.encode(data)
    lines=lines+1; bytes=bytes+#line
    print(line)
    if lines>=9000 or bytes>=8*1024*1024 then
        print("[CP2077VehicleFixture] log_limit; observation/cleanup still active; restart prohibited until closed")
    end
end
registerForEvent("onUpdate",function(dt)
    if not run or run.state=="closed" then return end
    if type(dt)~="number" or dt~=dt or dt<0 or dt==math.huge then run:step(dt,nil); return end
    elapsed=elapsed+dt
    if elapsed<0.1 then return end
    local delta=elapsed; elapsed=0
    local ok,paused=pcall(function() return Game.GetSystemRequestsHandler():IsGamePaused() end)
    if not ok then paused=nil end
    run:step(delta,paused)
end)
registerForEvent("onShutdown",function()
    if run and run.state~="closed" then
        -- Shutdown cannot poll asynchronous cleanup. Never delete here.
        print("[CP2077VehicleFixture] shutdown_with_owned_car; no deletion claimed; avoid hot reload while fixture owns a car")
    end
end)
return {
    start=function(target)
        if run and run.state~="closed" then return false,"already_owned_or_unresolved" end
        if not Fixture.validPose(target) then return false,"invalid_pose" end
        local engine=Engine.new()
        local ok,descriptor=pcall(engine.descriptor,engine)
        if not ok then return false,tostring(descriptor) end
        run=Fixture.new(engine,descriptor,report)
        elapsed=0; lines=0; bytes=0; requestsEnabled=false
        return run:start(target)
    end,
    enableRequests=function(enabled)
        if type(enabled)~="boolean" then return false end
        requestsEnabled=enabled; return true
    end,
    request=function(operation,seat)
        if not requestsEnabled or not run then return false,"requests_disabled" end
        return run:request(operation,seat)
    end,
    stop=function() requestsEnabled=false; return not run or run:stop() end,
    status=function()
        return run and {state=run.state,id=run.id,retiring=run.retiring or false,
            pending=run.pending~=nil,requestsEnabled=requestsEnabled,cameraVerified=false}
            or {state="idle",requestsEnabled=false,cameraVerified=false}
    end
}
