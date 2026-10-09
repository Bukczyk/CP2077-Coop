-- Opt-in local Codeware cancellation experiment. Never binds a network entity.
-- Install the exact production player_lifetime.lua beside this file.
local Lifetime=assert(require("player_lifetime"),"player_lifetime module missing")
local tag="CP2077CleanupFixture"
local run
local function log(event,data)
    data=data or {}; data.event=event
    if run then data.actor=tostring(run.id.hash); data.t=run.age; data.mode=run.mode end
    print("CLEANUP_FIXTURE "..json.encode(data))
end
local function observePause()
    local ok,paused=pcall(function()
        local requests=Game.GetSystemRequestsHandler()
        if requests==nil then return nil end
        return requests:IsGamePaused()
    end)
    if not ok then return {status="error"} end
    if type(paused)~="boolean" then return {status="unavailable"} end
    return {status="observed",paused=paused}
end
local function evidence(s)
    local a=Game.FindEntityByID(run.id)
    local population=s:GetEntity(run.id)
    local attached=a~=nil and a:IsAttached()
    if attached then run.seenAttached=true end
    return {attached=attached,managed=s:IsManaged(run.id),spawning=s:IsSpawning(run.id),
        spawned=s:IsSpawned(run.id),actorPresent=a~=nil,populationPresent=population~=nil,
        observedActor=a~=nil and tostring(a:GetEntityID().hash) or nil,
        populationActor=population~=nil and tostring(population:GetEntityID().hash) or nil,
        tagged=#s:GetTaggedIDs(CName.new(tag)),pause=run.pause,watchAge=run.watchAge,
        status=run.life and run.life.status or "immediate_reproduction",
        done=run.life~=nil and run.life.done or false,
        deleteAttempts=run.life and run.life.deleteAttempts or nil,
        deletionAt=run.deletionAt,doneAt=run.doneAt}
end
registerForEvent("onUpdate",function(dt)
    if not run or run.finished then return end
    local ok,err=pcall(function()
        run.age=run.age+dt
        run.pause=observePause()
        -- Unknown pause state does not authorize deletion or advance the watch.
        local paused="unavailable"
        if run.pause.status=="observed" then paused=run.pause.paused end
        if paused==false and run.previousPaused==false then run.watchAge=run.watchAge+dt end
        run.previousPaused=paused
        local s=Game.GetDynamicEntitySystem()
        if run.life then
            run.life:pump(run.age,paused)
            if run.life.deleteIssued and not run.deletionAt then
                run.deletionAt=run.age
                log("delete_after_spawn",{accepted=true,status=run.life.status,
                    deleteAttempts=run.life.deleteAttempts,pause=run.pause})
            end
            if run.life.done and not run.doneAt then
                run.doneAt=run.age
                log("retired",evidence(s))
            end
        end
        if run.age>=run.nextSample then
            run.nextSample=run.age+0.1
            log("sample",evidence(s))
        end
        -- Observe a full window even if initial lookup is empty: a queued spawn
        -- callback can appear after registry removal.
        -- Count five observed, unpaused seconds. Pausing cannot end the test
        -- while the real lifetime controller is correctly deferring removal.
        if run.watchAge>=5 then
            run.finished=true
            local result=evidence(s);result.seenAttached=run.seenAttached==true
            log("finished",result)
        end
    end)
    if not ok then run.finished=true;log("error",{message=tostring(err)}) end
end)
return {
    start=function(mode)
        mode=mode or "settled"
        if run or (mode~="immediate" and mode~="settled") then return false end
        local p=Game.GetPlayer(); local s=Game.GetDynamicEntitySystem()
        if not p or not p:IsAttached() or not s or not s:IsReady() then return false end
        if #s:GetTaggedIDs(CName.new(tag))>0 then return false end
        local q=p:GetWorldPosition(); local spec=NewObject("DynamicEntitySpec")
        spec.recordID=TweakDBID.new("Character.Judy")
        spec.position=Vector4.new(q.x+3,q.y,q.z,1); spec.orientation=p:GetWorldOrientation()
        spec.persistState=false;spec.persistSpawn=false;spec.alwaysSpawned=true
        spec.spawnInView=true;spec.active=true;spec.tags={CName.new(tag)}
        local id=s:CreateEntity(spec)
        run={id=id,mode=mode,age=0,watchAge=0,nextSample=0}
        if mode=="settled" then
            run.life=Lifetime.new(id,function(message) log("lifetime_status",{message=message}) end)
            -- Request cancellation immediately, exactly like a connection loss
            -- before the CreateEntity callback completes. The module decides
            -- when attachment is stable enough to submit DeleteEntity safely.
            run.life:retire()
            log("retirement_requested",{status=run.life.status,done=run.life.done})
        end
        log("created",{managed=s:IsManaged(id),spawning=s:IsSpawning(id),spawned=s:IsSpawned(id)})
        if mode=="immediate" then
            run.deleted=true;run.deletionAt=0
            log("delete_immediate",{accepted=s:DeleteEntity(id)})
        end
        return true
    end,
    inspect=function()
        if not run then return end
        log("inspect",evidence(Game.GetDynamicEntitySystem()))
    end,
    recover=function()
        if not run or not run.finished then return false end
        local a=Game.FindEntityByID(run.id)
        if a~=nil and a:IsAttached() then
            -- Explicit recovery of this fixture's exact returned ID only.
            Game.GetPreventionSpawnSystem():RequestDespawn(run.id)
            log("recovery_requested")
        end
        return true
    end,
    reset=function()
        if not run or not run.finished then return false end
        if run.life and not run.life.done then return false end
        local s=Game.GetDynamicEntitySystem();local a=Game.FindEntityByID(run.id)
        if a~=nil or s:GetEntity(run.id)~=nil or s:IsManaged(run.id)
            or s:IsSpawning(run.id) or s:IsSpawned(run.id) then return false end
        log("reset_confirmed");run=nil;return true
    end,
}
