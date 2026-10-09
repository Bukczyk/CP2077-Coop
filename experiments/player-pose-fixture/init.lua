-- Local-only engine test. Install with an exact copy of player_pose.lua beside
-- this file. Nothing runs until GetMod("zz_PlayerPoseFixture").start() is called.
-- Never publishes player state, binds a session entity, or moves the player.
local Pose = require("player_pose")
local tag = "CP2077PoseFixture"
local run, elapsed, retiring = nil, 0, nil
local function report(event, data)
    data = data or {}; data.event = event
    print("POSE_FIXTURE " .. json.encode(data))
end
local function stop(reason)
    if not run then return end
    run.pose:reset()
    retiring={id=run.id,age=0,nextSample=0}
    Game.GetDynamicEntitySystem():DeleteTagged(CName.new(tag))
    report("stop", {reason=reason, samples=run.samples, fault=run.fault})
    run = nil
end
registerForEvent("onUpdate", function(dt)
    if retiring and not retiring.blocked then
        local ok, err = pcall(function()
        retiring.age=retiring.age+dt
        local system=Game.GetDynamicEntitySystem()
        local entity=Game.FindEntityByID(retiring.id)
        local attached=entity~=nil and entity:IsAttached()
        local managed=system:IsManaged(retiring.id)
        local spawning=system:IsSpawning(retiring.id)
        if retiring.age>=retiring.nextSample then
            retiring.nextSample=retiring.age+0.1
            report("retirement",{actor=tostring(retiring.id.hash),t=retiring.age,
                attached=attached,managed=managed,spawning=spawning,
                tagged=#system:GetTaggedIDs(CName.new(tag))})
        end
        if not attached and not managed and not spawning then
            report("retired",{actor=tostring(retiring.id.hash),t=retiring.age})
            retiring=nil
        elseif retiring.age>3 then
            report("retirement_unconfirmed",{actor=tostring(retiring.id.hash)})
            retiring.blocked=true
        end
        end)
        if not ok then
            retiring.blocked=true
            report("retirement_error",{actor=tostring(retiring.id.hash),message=tostring(err)})
        end
    end
    if not run then return end
    local ok, err = pcall(function()
        elapsed = elapsed + dt
        if elapsed > 32 then stop("duration_limit"); return end
        local actors = Game.GetDynamicEntitySystem():GetTagged(CName.new(tag))
        if #actors ~= 1 then
            if elapsed > 3 then stop("expected_one_actor"); end
            return
        end
        local actor = actors[1]
        local phase = math.floor(elapsed / 5)
        -- Stationary placement, translation, rotation, then a short moving path.
        local x = run.x + (phase >= 1 and 1 or 0)
        local travel = math.max(0, math.min(10, elapsed-15))
        if phase >= 3 then x = run.x + 1 + travel*run.speed end
        local target={x=x,y=run.y,z=run.z,
            yaw=run.yaw+(phase>=2 and math.pi/2 or 0)+travel*run.turnRate}
        local result = run.pose:step(actor,target,elapsed)
        run.fault = run.pose.fault
        if elapsed >= run.nextSample then
            run.nextSample=elapsed+0.1; run.samples=run.samples+1
            local q=actor:GetWorldPosition()
            local c=run.pose.command
            report("sample", {t=elapsed,phase=phase,result=result,fault=run.fault,
                actor=tostring(actor:GetEntityID().hash),target=target,
                actual={x=q.x,y=q.y,z=q.z,yaw=actor:GetWorldOrientation():ToEulerAngles().yaw},
                commandState=c and actor:CP2077Session_PoseState(c),sent=run.pose.sent})
        end
    end)
    if not ok then report("error",{message=tostring(err)}); stop("error") end
end)
registerForEvent("onShutdown", function() stop("shutdown") end)
return {
    start=function(speed, turnRate, initialTurn)
        if run or retiring then return false end
        speed, turnRate = speed or 0.5, turnRate or 0
        initialTurn=initialTurn or 0
        if type(speed)~="number" or speed~=speed or speed<0 or speed>8 or
            type(turnRate)~="number" or turnRate~=turnRate or math.abs(turnRate)>3 or
            type(initialTurn)~="number" or initialTurn~=initialTurn or math.abs(initialTurn)>math.pi then return false end
        local player=Game.GetPlayer()
        if not player or not player:IsAttached() then return false end
        local system=Game.GetDynamicEntitySystem()
        if not system or not system:IsReady() then return false end
        if #system:GetTagged(CName.new(tag)) > 0 then return false end
        local p=player:GetWorldPosition()
        local yaw=player:GetWorldOrientation():ToEulerAngles().yaw
        local spec=NewObject("DynamicEntitySpec")
        spec.recordID=TweakDBID.new("Character.Judy")
        spec.position=Vector4.new(p.x+3,p.y,p.z,1)
        spec.orientation=player:GetWorldOrientation()
        spec.persistState=false; spec.persistSpawn=false
        spec.alwaysSpawned=true; spec.spawnInView=true; spec.active=true
        spec.tags={CName.new(tag)}
        local id=system:CreateEntity(spec)
        elapsed=0
        run={id=id,x=p.x+3,y=p.y,z=p.z,yaw=math.rad(yaw)+initialTurn,speed=speed,turnRate=turnRate,samples=0,nextSample=0,
            pose=Pose.new(function(message) report("controller",{message=message}) end)}
        report("start",{actor=tostring(id.hash),method="local scripted target; not network or walking input",speed=speed,turnRate=turnRate,initialTurn=initialTurn})
        return true
    end,
    stop=function() stop("manual") end,
}
