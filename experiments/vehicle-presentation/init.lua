-- Manual local fixture, not a production mod. No automatic activation or keys.
local Fixture=require("fixture")
local Engine=require("engine")
local Movement=require("movement")
local run,elapsed,lines,bytes=nil,0,0,0
local requestsEnabled=false
local movement,generation,stopRequested=nil,0,false
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
    if type(dt)~="number" or dt~=dt or dt<0 or dt==math.huge then
        run:step(dt,nil)
        if movement then movement:update(dt,nil,nil,false) end
        return
    end
    elapsed=elapsed+dt
    if elapsed<0.1 then return end
    local delta=elapsed; elapsed=0
    local ok,paused=pcall(function() return Game.GetSystemRequestsHandler():IsGamePaused() end)
    if not ok then paused=nil end
    run:step(delta,paused)
    if movement then
        local wasPending=not movement:canRetire()
        -- During a move, a read failure may make initial placement stale. Exact
        -- ownership/safe readback still gates reconciliation of that same move.
        movement:update(delta,paused,run.last,(run.state=="ready" or wasPending)
            and not run.identityFault and not run.unsupported and not run.retiring and run.pending==nil)
        if wasPending and movement:canRetire() and movement.last then
            -- Future requalification uses the observed pose, never the command.
            run.target=movement.last.pose
        end
    end
    if stopRequested and (not movement or movement:canRetire()) then run:stop() end
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
        if generation>=1000000000 then return false,"fixture_generation_exhausted" end
        generation=generation+1
        local engine=Engine.new(generation)
        local ok,descriptor=pcall(engine.descriptor,engine)
        if not ok then return false,tostring(descriptor) end
        run=Fixture.new(engine,descriptor,report)
        elapsed=0; lines=0; bytes=0; requestsEnabled=false;stopRequested=false;movement=nil
        local started,reason=run:start(target)
        if started then movement=Movement.new(engine,run.id,run.player,generation,target,descriptor,report) end
        return started,reason
    end,
    enableRequests=function(enabled)
        if type(enabled)~="boolean" then return false end
        if enabled and (stopRequested or movement and (movement.enabled or not movement:canRetire())) then return false end
        requestsEnabled=enabled; return true
    end,
    enableMovement=function(enabled)
        if not movement or stopRequested or (enabled and requestsEnabled) then return false end
        return movement:setEnabled(enabled)
    end,
    move=function(target,expectedGeneration)
        if not movement or stopRequested or requestsEnabled or not run or run.state~="ready" or run.pending then
            return false,"fixture_unavailable"
        end
        return movement:submit(target,expectedGeneration)
    end,
    request=function(operation,seat)
        if not requestsEnabled or not run or stopRequested or movement and not movement:canRetire() then return false,"requests_disabled" end
        return run:request(operation,seat)
    end,
    stop=function()
        requestsEnabled=false;stopRequested=true
        if movement then movement:setEnabled(false);if not movement:canRetire() then return false end end
        return not run or run:stop()
    end,
    status=function()
        return run and {state=run.state,id=run.id,retiring=run.retiring or false,
            pending=run.pending~=nil,requestsEnabled=requestsEnabled,cameraVerified=false,
            generation=generation,stopRequested=stopRequested,movement=movement and movement:status()}
            or {state="idle",requestsEnabled=false,cameraVerified=false}
    end
}
