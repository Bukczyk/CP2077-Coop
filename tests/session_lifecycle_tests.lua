-- Executes the real CET entrypoint, including lifecycle registration. Engine
-- mocks deliberately return a new EntityID wrapper on every read.
local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local report = print
local realLifetime = require("player_lifetime")
local hasFfi, ffi = pcall(require, "ffi")
local function uint64(offset)
    if hasFfi then return ffi.new("uint64_t", 9007199254740992) + offset end
    -- Lua 5.4 fallback preserves the opaque-value behavior; LuaJIT uses real
    -- uint64_t cdata, like CET, to check precision beyond the double boundary.
    return setmetatable({}, {__tostring=function()
        return offset == 1 and "9007199254740993ULL" or "9007199254740994ULL"
    end})
end

local function fixture(role, experimental, motor, passive, markers)
    local state = {
        attached=true, pregame=false, hasPlayer=true, hash=uint64(1),
        activations={}, bindings={}, logs={}, observations=0, cleared=0,
        npcReads=0, npcOffers=0, npcSpawns=0, pushes=0, ready=false,
        remotes={}, bodies={}, unbindings={}, frameGeneration=1,
        playerSpawns=0, teleports=0, world={}, mapped={}, deleted={}, phase=4,
        paused=false, npcClocks={},

        retirementPumps={},
    }
    package.loaded.player_lifetime={new=function(...)
        local owner=realLifetime.new(...)
        local pump=owner.pump
        owner.pump=function(self,now,paused)
            state.retirementPumps[#state.retirementPumps+1]={now=now,paused=paused}
            return pump(self,now,paused)
        end
        return owner
    end}
    local events, hotkeys = {}, {}
    Game, Observe, CName = nil, nil, nil
    package.loaded.npc_runtime, package.loaded.npc_population = nil, nil
    local npcRuntime=require("npc_runtime")
    package.loaded.npc_runtime={contains=npcRuntime.contains,new=function(...)
        local controller=npcRuntime.new(...)
        local reset=controller.reset
        controller.reset=function(self,...)
            if state.npcResetThrows then error("injected NPC reset failure") end
            return reset(self,...)
        end
        return controller
    end}
    package.loaded.config = nil
    if experimental ~= nil then package.loaded.config={experimentalNpcReplication=experimental,
        experimentalPlayerMovement=motor == true,experimentalPassivePlayers=passive == true,
        experimentalPlayerMarkers=markers==true,showSessionUI=true} end
    print = function(message) state.logs[#state.logs+1] = tostring(message) end
    registerForEvent = function(name, callback)
        assert(events[name] == nil, "duplicate lifecycle registration")
        events[name] = callback
    end
    registerHotkey = function(name, _, callback) hotkeys[name] = callback end
    local runtime = require("npc_runtime")
    local newRuntime = runtime.new
    runtime.new = function(adapter)
        state.npcProjection = newRuntime(adapter)
        return state.npcProjection
    end
    state.bridge=assert(loadfile(root .. "/runtime/session/cet/CP2077Coop/init.lua"))()
    local population=package.loaded.npc_population
    local observe=population.observe
    population.observe=function(now,paused)
        state.npcClocks[#state.npcClocks+1]={now=now,paused=paused}
        return observe(now,paused)
    end

    assert(events.onInit, "entrypoint must register onInit")
    assert(state.observations == 0, "no engine observation during module load")
    -- These callbacks must also be harmless before the engine API is ready.
    events.onUpdate(1/60)
    hotkeys.cp2077_session_reconnect()
    events.onShutdown()
    assert(#state.activations == 0)

    local system = {}
    function system:IsReady() return not state.dynamicUnavailable end
    function system:DeleteTagged() error("player cleanup must not delete by tag") end
    local function key(id) return tostring(id.hash) end
    local function entry(id) return state.world[key(id)] end
    function system:GetTaggedIDs(tag)
        local ids={}
        for _,e in pairs(state.world) do
            if e.tagged and (tag==e.tag or tag=="CP2077Session.Projection") then ids[#ids+1]=e.id end
        end
        return ids
    end
    function system:GetTagged(tag)
        local actors={}
        for _,id in ipairs(self:GetTaggedIDs(tag)) do
            local e=entry(id); if e.visible then actors[#actors+1]=e.actor end
        end
        return actors
    end
    function system:IsManaged(id) local e=entry(id); return e~=nil and e.managed end
    function system:IsSpawning(id) local e=entry(id); return e~=nil and e.spawning end
    function system:IsSpawned(id) local e=entry(id); return e~=nil and e.spawned end
    function system:GetEntity(id) local e=entry(id); return e and e.managed and e.visible and e.actor or nil end
    function system:DeleteEntity(id)
        local e=assert(entry(id),"deletion must own an exact ID")
        state.deleted[#state.deleted+1]=key(id); e.tagged=false
        if not state.delayDelete then state.gone(id) end
        return true
    end
    function system:IsTagged() return false end
    function system:CreateEntity() state.npcSpawns=state.npcSpawns+1; error("unexpected NPC creation") end
    local player = {}
    state.markers={}
    function player:CP2077Session_ClearPlayerMarkers() state.markers={}; return true end
    function player:CP2077Session_SetPlayerMarker(id,x,y,z,yaw)
        state.markers[id]={x=x,y=y,z=z,yaw=yaw}; return true
    end
    function player:CP2077Session_RemovePlayerMarker(id)
        if state.markerCleanupFails then return false end
        state.markers[id]=nil; return true
    end
    function player:IsAttached() return state.attached end
    function player:GetEntityID() return {hash=state.hash} end
    function player:GetWorldPosition() return {x=1,y=2,z=3} end
    function player:GetWorldOrientation()
        return {ToEulerAngles=function() return {yaw=30} end}
    end
    function state.add(actor,tag,pending)
        local id=actor:GetEntityID()
        local e={id=id,actor=actor,tag=tag,tagged=true,visible=not pending,
            managed=true,spawning=pending==true,spawned=not pending}
        actor.IsAttached=function() return e.visible end
        state.world[key(id)]=e
        return id
    end
    function state.gone(id)
        local e=assert(entry(id)); e.visible,e.managed,e.spawning,e.spawned,e.tagged=false,false,false,false,false
    end
    function state.finishSpawn(id)
        local e=assert(entry(id)); e.visible,e.managed,e.spawning,e.spawned=true,true,false,true
    end
    function player:CP2077Session_SpawnProxy(tag,x,y,z)
        state.playerSpawns=state.playerSpawns+1
        local actor=state.bodies[tag]
        if not actor then
            local hash=tostring(1000+state.playerSpawns).."ULL"
            actor={GetEntityID=function() return {hash=hash} end}
            actor.CP2077Session_PoseReady=function() return true end
            actor.GetWorldPosition=function() return {x=x,y=y,z=z} end
            actor.GetWorldOrientation=function() return {ToEulerAngles=function() return {yaw=0} end} end
            actor.CP2077Session_StopPose=function() return true end
        end
        return state.add(actor,tag,state.pendingSpawn)
    end
    local native = {
        GetPlayer=function()
            if state.playerUnavailable then error("player lookup unavailable") end
            if state.hasPlayer then return player end
        end,
        GetSystemRequestsHandler=function()
            if state.requestsUnavailable then error("requests handler unavailable") end
            return {IsPreGame=function() return state.pregame end,
                IsGamePaused=function()
                    if state.pauseUnavailable then error("pause observation unavailable") end
                    return state.paused
                end}

        end,
        GetDynamicEntitySystem=function() return system end,
        FindEntityByID=function(id) local e=entry(id); return e and e.visible and e.actor or nil end,
        GetTeleportationFacility=function()
            return {Teleport=function() state.teleports=state.teleports+1 end}
        end,
        CP2077Session_SetActive=function(value)
            state.activations[#state.activations+1]=value
            if value==false and state.deactivateThrows then error("injected deactivation failure") end
        end,
        CP2077Session_PushLocal=function() state.pushes=state.pushes+1 end,
        CP2077Session_BeginFrame=function()
            if state.bridgeFailure then error("test bridge failure") end
            return #state.remotes
        end,
        CP2077Session_Generation=function() return state.frameGeneration end,
        CP2077Session_Select=function(index) state.selected=state.remotes[index+1]; return state.selected~=nil end,
        CP2077Session_Player=function() return state.selected.id end,
        CP2077Session_Entity=function() return state.selected.entity end,
        CP2077Session_X=function() return state.selected.x end,
        CP2077Session_Y=function() return 2 end,
        CP2077Session_Z=function() return 3 end,
        CP2077Session_Yaw=function() return 0 end,
        CP2077Session_Resolve=function(id) return state.mapped[key(id)] or "0ULL" end,
        CP2077Session_Unbind=function(id)
            state.unbindings[#state.unbindings+1]=id
            for hash,session in pairs(state.mapped) do if tostring(session)==tostring(id) then state.mapped[hash]=nil end end
            return true
        end,

        CP2077Session_Session=function() return uint64(1) end,
        CP2077Session_Epoch=function() return 1 end,
        CP2077Session_Phase=function() return state.phase end,
        CP2077Session_Bind=function(session, id)
            if state.denyBind then return false end
            state.mapped[key(id)]=session
            state.bindings[#state.bindings+1]=tostring(id.hash); return true
        end,
        CP2077Session_SelfEntity=function() return uint64(2) end,
        CP2077Session_BubbleRadius=function() return 100 end,
        CP2077Session_Self=function() return role == "HOST" and 1 or 2 end,
        CP2077Session_Host=function() return 1 end,
        CP2077Session_NpcCapacity=function() state.npcReads=state.npcReads+1; return 128 end,
        CP2077Session_NpcCount=function() state.npcReads=state.npcReads+1; return 0 end,
        CP2077Session_NpcOffer=function() state.npcOffers=state.npcOffers+1; return true end,
    }
    state.init = function()
        state.ready=true
        Game, CName = native, {new=function(value) return value end}
        Observe = function(class, method, callback)
            assert(state.ready and class == "NPCPuppet" and method == "OnGameAttached")
            state.observations=state.observations+1
            state.observeNpc=callback
        end
        events.onInit()
        assert(state.observations == 1, "register observer when CET is ready")
    end
    state.tick = function(count)
        for _=1,(count or 1) do events.onUpdate(1/60) end
        for _, message in ipairs(state.logs) do
            assert(state.allowBridgeError or not message:find("BRIDGE_ERROR",1,true), message)
        end
    end
    state.reconnect=hotkeys.cp2077_session_reconnect
    state.rawTick=events.onUpdate
    state.shutdown=events.onShutdown
    state.draw=events.onDraw
    state.overlayOpen=events.onOverlayOpen
    return state
end

for _, role in ipairs({"HOST","JOINER"}) do
    local s=fixture(role)
    s.init()
    s.tick(180)
    assert(#s.activations == 1 and s.activations[1], role .. ": wrapper churn must not restart session")
    assert(#s.bindings == 180 and s.pushes == 180)
    assert(s.npcReads == 0 and s.npcOffers == 0 and s.npcSpawns == 0,
        "experimental NPC replication must default off")

    -- Real entity replacement still reconnects, even for adjacent opaque 64-bit
    -- hashes that would collapse if converted to a Lua double.
    local previous=s.bindings[#s.bindings]
    s.hash=uint64(2)
    s.tick(60)
    assert(#s.activations == 3 and not s.activations[2] and s.activations[3])
    assert(previous ~= s.bindings[#s.bindings], "must not round Uint64 identities")

    s.reconnect()
    assert(#s.activations == 4 and not s.activations[4])
    s.tick(120)
    assert(#s.activations == 5 and s.activations[5])
    for _, reason in ipairs({"detached","pregame","no-player"}) do
        local before=#s.activations
        if reason == "detached" then s.attached=false
        elseif reason == "pregame" then s.pregame=true
        else s.hasPlayer=false end
        s.tick(3)
        assert(#s.activations == before+1 and not s.activations[#s.activations], reason)
        s.attached, s.pregame, s.hasPlayer=true, false, true
        s.tick(3)
        assert(#s.activations == before+2 and s.activations[#s.activations], reason)
    end
    local before=#s.activations
    s.shutdown()
    assert(#s.activations == before+1 and not s.activations[#s.activations])
end

-- Opt-in still registers the observer in onInit and reaches the NPC bridge.
for _, role in ipairs({"HOST","JOINER"}) do
    local s=fixture(role,true)
    s.init()
    s.observeNpc({IsAttached=function() return false end})
    s.tick(3)
    assert(s.npcReads > 0 and #s.activations == 1)
end

-- Disabled mode ignores even real attachment notifications on both roles.
for _, role in ipairs({"HOST","JOINER"}) do
    local s=fixture(role,false)
    s.init()
    s.observeNpc({IsAttached=function() error("disabled NPC was inspected") end})
    s.tick()
    assert(s.npcReads == 0 and s.npcOffers == 0 and s.npcSpawns == 0)
end
-- Real entrypoint: independent motors, exact body replacement and cleanup.
local made, stopped={},{}
package.loaded.player_motor={new=function(actor)
    made[#made+1]=actor
    return {actor=actor, step=function(self,target) self.target=target end,
        stop=function() stopped[#stopped+1]=actor end}
end}
local s=fixture("HOST",false,true)
local function body(hash) return {GetEntityID=function() return {hash=hash} end} end
local first,second,replacement=body("9007199254741993ULL"),body("9007199254741994ULL"),body("9007199254741995ULL")
s.remotes={{id=2,entity=uint64(1),x=10},{id=3,entity=uint64(2),x=20}}
s.bodies["CP2077Session.Projection.2"]=first
s.bodies["CP2077Session.Projection.3"]=second
s.init(); s.tick(10)
assert(#made==2 and #stopped==0,"one motor per exact remote body")
s.bodies["CP2077Session.Projection.2"]=replacement
s.tick()
assert(#made==2 and #stopped==0,"a changed tag lookup cannot replace the exact owned actor")
s.remotes[1].entity="9007199254740995ULL"
s.tick(30)
assert(#made==3 and stopped[1]==first,"session identity replacement retires the old command owner")
s.remotes={s.remotes[2]}
s.tick(30)
assert(stopped[2]==replacement,"departure stops only that player's motor")
s.reconnect()
s.tick(30)
assert(stopped[3]==second,"reconnect cancels remaining motor")
assert(#made==4 and made[4]==second,"new generation creates a fresh motor")
-- Optional engine animation observations cannot break transform readback or
-- submit/release commands. Execute the actual diagnostic entrypoint.
second.GetWorldPosition=function() return {x=20,y=30,z=4} end
second.GetWorldOrientation=function() return {ToEulerAngles=function() return {yaw=45} end} end
local d=s.bridge.playerDiagnostics()["3"]
assert(d.readback=="available" and d.actualX==20 and d.gaitChangeRequests==nil,
    "old/missing animation helper preserves transform diagnostics")
second.CP2077Session_MotorGaitChanges=function() return 7 end
second.GetTimeDilationValue=function() return 0.05 end
second.GetHighLevelStateFromBlackboard=function() return "Relaxed" end
second.GetUpperBodyStateFromBlackboard=function() return "Normal" end
second.GetMovePolicesComponent=function() return {
    GetCurrentLocomotionAction=function() return "Move" end,
    GetDestination=function() return {x=21,y=31,z=4} end,
    GetTopPolicies=function() return {GetMovementType=function() return "Run" end} end,
    IsPausedByDynamicCollision=function() return false end,
    IsInIdle=function() return false end,IsPathfindingFailed=function() return true end} end
d=s.bridge.playerDiagnostics()["3"]
assert(d.gaitChangeRequests==7 and d.locomotionAction=="Move" and d.policyIdle==false and d.pathFailed==true,
    "actual actor policy observations are forwarded without inventing visual success")
assert(d.actorTimeScale==0.05 and d.highLevelState=="Relaxed" and d.upperBodyState=="Normal",
    "time scale and actor animation state observations remain separate")
assert(d.destinationX==21 and d.destinationY==31 and d.destinationZ==4
    and d.policyMovementType=="Run" and d.collisionPaused==false,
    "engine destination and gait distinguish a stale path from a current network marker")
second.GetMovePolicesComponent=function() error("policy unavailable") end
d=s.bridge.playerDiagnostics()["3"]
assert(d.readback=="available" and d.actualX==20 and d.gaitChangeRequests==nil,
    "optional policy read failure is isolated from transform readback")
assert(#made==4 and #stopped==3,"read-only diagnostics do not alter command ownership")
s.shutdown()
package.loaded.player_motor=nil
-- A latched motor fault falls back to the pose actuator, then retries one fresh
-- motor after a cooldown instead of freezing the actor until it is recreated.
local motors, poseSteps, poseResets={},0,0
package.loaded.player_motor={new=function(actor)
    local m={steps=0,stop=function() end}
    function m:step() self.steps=self.steps+1 end
    motors[#motors+1]=m
    return m
end}
package.loaded.player_pose={new=function()
    return {reset=function() poseResets=poseResets+1 end, release=function() return true end,
        step=function() poseSteps=poseSteps+1 end, diagnostics=function() return {} end}
end}
local function onlyDiagnostics(state) local _, d=next(state.bridge.playerDiagnostics()); return assert(d) end
s=fixture("HOST",false,true)
s.remotes={{id=2,entity=uint64(1),x=10}}
s.bodies["CP2077Session.Projection.2"]=body("9007199254741996ULL")
s.init(); s.tick(10)
assert(#motors==1 and motors[1].steps>0 and poseSteps==0,"healthy motor owns presentation")
motors[1].fault="move_start_timeout"
local frozenSteps=motors[1].steps
s.tick(60)
assert(#motors==1 and motors[1].steps==frozenSteps,"faulted motor is not stepped")
assert(poseSteps>0,"pose actuator presents the actor while the motor is faulted")
assert(onlyDiagnostics(s).mode=="pose_fallback")
local resetsBefore=poseResets
s.tick(5*60)
assert(#motors==2 and motors[2].steps>0,"a fresh motor is retried after the cooldown")
assert(poseResets>resetsBefore,"the pose command is released before the motor resumes")
assert(onlyDiagnostics(s).motorRecoveries==1)
motors[2].fault="cancellation_unconfirmed"
local held=poseSteps
s.tick(10*60)
assert(#motors==2 and poseSteps==held,"an unconfirmed cancellation never stacks a second command")
s.shutdown()
package.loaded.player_motor, package.loaded.player_pose=nil, nil
-- The actual entrypoint keeps session snapshots/bindings alive while paused,
-- but informs the pose owner that world AI cannot execute its commands.
local pauseFlags={}
package.loaded.player_pose={new=function()
    return {reset=function() end, step=function(_,_,_,_,paused)
        pauseFlags[#pauseFlags+1]=paused
    end}
end}
s=fixture("HOST",false,false)
s.remotes={{id=2,entity=uint64(1),x=10}}
s.bodies["CP2077Session.Projection.2"]=first
s.init(); s.tick(2)
s.paused=true; s.tick(240)
assert(pauseFlags[1]==false and pauseFlags[#pauseFlags]==true,
    "entrypoint forwards observed engine pause to the pose owner")
assert(s.pushes==242 and #s.activations==1,
    "pause must not disconnect or stop the native snapshot path")
s.paused=false; s.tick()
assert(pauseFlags[#pauseFlags]==false,"resume reaches the pose owner")
s.shutdown()
package.loaded.player_pose=nil
-- JOINER admission while paused defers its initial game-side teleport/spawn.
Vector4={new=function() return {} end}; EulerAngles={new=function() return {} end}
s=fixture("JOINER",false,false)
s.remotes={{id=1,entity=uint64(1),x=10}}
s.paused=true; s.init(); s.tick(240)
assert(s.playerSpawns==0 and s.teleports==0,"pause defers new actors and initial alignment")
s.paused=false; s.tick()
assert(s.playerSpawns==1 and s.teleports==1,"resume starts deferred game-side admission")
s.shutdown()
-- A canceled CreateEntity still owns its token while attachment is pending.
-- Empty tags and the loss of a loaded player must not permit early deletion.
package.loaded.player_motor={new=function()
    return {step=function() end,stop=function() end}
end}
s=fixture("HOST",false,true)
s.pendingSpawn=true
s.remotes={{id=2,entity=uint64(1),x=10}}
s.init(); s.tick(2)
local pendingId
for _,e in pairs(s.world) do pendingId=e.id; e.tagged=false end
assert(pendingId and s.playerSpawns==1,"retain one pending exact spawn")
s.hasPlayer=false; s.tick(120)
assert(#s.deleted==0,"unload never deletes before pending attachment finishes")
s.finishSpawn(pendingId); s.delayDelete=true; s.tick(4)
assert(#s.deleted==1,"unloaded retirement resumes after exact attachment")
s.hasPlayer=true; s.tick(120)
assert(s.playerSpawns==1,"empty tags cannot permit a duplicate while exact actor remains")
s.gone(pendingId); s.pendingSpawn=false; s.tick(30)
assert(s.playerSpawns==2,"observed disappearance permits a fresh player actor")
s.shutdown()

-- Startup recovery and failed-mode cleanup retain exact IDs after the manager's
-- tag index has been emptied. No unrelated or newly rebound actor is deleted.
s=fixture("HOST",false,true)
local pauseUnknownId=s.add(body("9007199254744997ULL"),"CP2077Session.Projection.9")
s.pauseUnavailable=true; s.init(); s.tick(120)
assert(#s.deleted==0,"unknown pause state cannot qualify player cleanup alongside NPC pumping")
s.pauseUnavailable=false; s.tick(30)
assert(#s.deleted==1 and not s.world[tostring(pauseUnknownId.hash)].visible,
    "both update paths recover after pause observation returns")
s.shutdown()

s=fixture("HOST",false,true)
local orphan=body("9007199254740997ULL")
local orphanId=s.add(orphan,"CP2077Session.Projection.9")
s.delayDelete=true
s.remotes={{id=2,entity=uint64(1),x=10}}
s.init(); s.tick(5)
assert(#s.deleted==1 and s.playerSpawns==0,"recover and retire the pre-init exact tagged actor")
assert(not s.world[tostring(orphanId.hash)].tagged,"mock confirms tag index is empty")
s.tick(120)
assert(s.playerSpawns==0,"startup orphan remains a gate after tags disappear")
s.gone(orphanId); s.tick(30)
assert(s.playerSpawns==1,"startup orphan disappears before a replacement is admitted")
local activeId
for _,e in pairs(s.world) do if e.visible then activeId=e.id end end
s.denyBind=true; s.allowBridgeError=true; s.tick(5)
assert(#s.deleted==2,"latched bridge error still pumps owned cleanup")
s.gone(activeId); s.tick(30)
s.denyBind=false; s.reconnect(); s.tick(30)
assert(s.playerSpawns==2,"explicit reconnect follows completed failed-mode cleanup")
s.shutdown()
assert(next(s.bridge.playerRetirementDiagnostics())~=nil,
    "shutdown records owned retirement instead of reporting deletion as complete")

-- A different authoritative binding on the old exact body must not be removed.
-- Retaining that uncertain lifetime also prevents replacement actors.
local function onlyDiagnostics(state) local _, d=next(state.bridge.playerDiagnostics()); return assert(d) end
s=fixture("HOST",false,true)
s.remotes={{id=2,entity=uint64(1),x=10}}
s.init(); s.tick(3)
local stolenId
for _,e in pairs(s.world) do if e.visible then stolenId=e.id end end
local stolenKey=tostring(stolenId.hash)
s.mapped[stolenKey]="9007199254740999ULL"
s.remotes={}; s.tick(120)
assert(#s.unbindings==0 and #s.deleted==0 and s.mapped[stolenKey]=="9007199254740999ULL",
    "retirement never unbinds or deletes a different exact mapping")
s.remotes={{id=2,entity=uint64(2),x=10}}; s.tick(30)
assert(s.playerSpawns==1,"uncertain ownership blocks a reused PlayerId replacement")
s.shutdown()

-- An absent tracked actor is diagnostic evidence, never permission to respawn.
s=fixture("HOST",false,true)
s.pendingSpawn=true; s.remotes={{id=2,entity=uint64(1),x=10}}
s.init(); s.tick(2)
assert(s.bridge.playerDiagnostics()["2"].lifecycle=="spawn_pending",
    "pending creation is reported before the first actor is observed")
local missingId
for _,e in pairs(s.world) do missingId=e.id end
s.finishSpawn(missingId); s.tick(2)
assert(s.bridge.playerDiagnostics()["2"].actorState=="actor_present")
s.gone(missingId); s.tick(120)
assert(s.bridge.playerDiagnostics()["2"].lifecycle=="actor_missing" and s.playerSpawns==1,
    "missing actor keeps the owned lifetime and prevents an automatic duplicate")
local missingReports=0
for _,line in ipairs(s.logs) do
    if line:find("PLAYER_ACTOR",1,true) and line:find("status=actor_missing",1,true) then missingReports=missingReports+1 end
end
assert(missingReports==1,"missing-actor diagnostics do not flood every frame")
s.shutdown()

-- A transient exact lookup failure must not label a recovered player as broken
-- forever in the movement-test log. Keep the same actor, binding and motor.
s=fixture("HOST",false,true)
s.remotes={{id=2,entity=uint64(1),x=10}}
s.init(); s.tick(3)
local originalActor=s.bridge.playerDiagnostics()["2"].actor
local findEntity=Game.FindEntityByID
Game.FindEntityByID=function() error("transient exact lookup failure") end
s.tick()
assert(s.bridge.playerDiagnostics()["2"].lifecycle=="actor_observation_error",
    "active lookup failure reaches value-only diagnostics")
Game.FindEntityByID=findEntity; s.tick()
local recovered=s.bridge.playerDiagnostics()["2"]
assert(recovered.lifecycle=="actor_present" and recovered.actor==originalActor and s.playerSpawns==1,
    "recovered diagnostics describe the same present actor without respawning it")
s.shutdown()

-- Stop failures must first retain dynamic IDs, leave the bridge inactive, and
-- allow failed-mode retirement pumping without silently reconnecting.
for _,failure in ipairs({"deactivateThrows","npcResetThrows"}) do
    s=fixture("HOST",false,true)
    s.pendingSpawn=true; s.remotes={{id=2,entity=uint64(1),x=10}}
    s.init(); s.tick(2)
    local ownedId
    for _,e in pairs(s.world) do ownedId=e.id end
    s[failure]=true; s.allowBridgeError=true; s.reconnect()
    assert(next(s.bridge.playerRetirementDiagnostics())~=nil,
        failure..": throwing cleanup must retain the exact pending ID")
    s.tick(120)
    assert(#s.deleted==0 and s.playerSpawns==1,
        failure..": failed mode cannot delete a pending creation or spawn again")
    s.finishSpawn(ownedId); s.tick(30)
    assert(#s.deleted==1 and next(s.bridge.playerRetirementDiagnostics())==nil,
        failure..": failed-mode ticks continue observed cleanup")
    s[failure]=false; s.tick(30)
    local activations=0; for _,value in ipairs(s.activations) do if value then activations=activations+1 end end
    assert(activations==1 and s.playerSpawns==1,
        failure..": clearing the external error does not auto-reconnect")
    s.pendingSpawn=false; s.reconnect(); s.tick(30)
    assert(s.playerSpawns==2,failure..": explicit successful reconnect admits a fresh actor")
    s.shutdown()
end

-- Passive mode can inherit a pending dynamic token on reload. A throwing
-- passive reset cannot discard that recovered ID or prevent failure pumping.
local passiveResetThrows=true
package.loaded.player_passive={new=function()
    return {reset=function() if passiveResetThrows then error("injected passive reset failure") end end,
        pump=function() end,status=function() end,step=function() end,boundIds=function() return {} end}
end}
s=fixture("HOST",false,false,true)
local recoveredId=s.add(body("9007199254742993ULL"),"CP2077Session.Projection.2",true)
s.allowBridgeError=true; s.init(); s.tick(2)
assert(next(s.bridge.playerRetirementDiagnostics())~=nil and #s.deleted==0,
    "passive reset failure preserves recovered pending dynamic ownership")
s.finishSpawn(recoveredId); s.tick(30)
assert(#s.deleted==1 and next(s.bridge.playerRetirementDiagnostics())==nil,
    "throwing passive cleanup does not block dynamic retirement pumping")
passiveResetThrows=false; s.shutdown(); package.loaded.player_passive=nil
package.loaded.player_motor=nil
-- The actual entrypoint supplies one timestamp and explicit pause state to NPC
-- retirement even after unload or a latched bridge failure. Unknown is not false.
do
    local s=fixture("JOINER",false); s.init(); s.tick()
    local first=s.npcClocks[#s.npcClocks]
    assert(first.paused==false and first.now>0,"normal NPC pump is explicitly unpaused")
    s.paused=true; s.tick()
    local paused=s.npcClocks[#s.npcClocks]
    assert(paused.paused==true and paused.now>first.now)
    s.pauseUnavailable=true; s.tick()
    assert(s.npcClocks[#s.npcClocks].paused==nil,"unknown pause must reach fail-closed adapter")
    s.pauseUnavailable=false; s.paused=false; s.hasPlayer=false; s.tick(3)
    local unloaded=s.npcClocks[#s.npcClocks]
    assert(unloaded.now>paused.now and unloaded.paused==false,"unloaded game still pumps retained NPCs")
    s.hasPlayer=true; s.bridgeFailure=true; s.rawTick(1/60)
    local failed=s.npcClocks[#s.npcClocks]
    s.rawTick(1/60)
    assert(s.npcClocks[#s.npcClocks].now>failed.now,"latched failure still pumps NPC retirement")
end

-- A throwing handler getter must still invalidate the real dynamic adapter's
-- pending observations, on both the first failed update and latched-error ticks.
for _,phase in ipairs({"attachment","absence","early-engine-error"}) do
    local s=fixture("JOINER",false); s.init(); s.tick()
    local population=package.loaded.npc_population
    local system=Game.GetDynamicEntitySystem()
    local localId={hash="123ULL"}
    local gone,deletes=false,0
    local actor={GetEntityID=function() return localId end,IsAttached=function() return not gone end}
    function system:CreateEntity() return localId end
    function system:GetEntity() if not gone then return actor end end
    function system:IsManaged() return not gone end
    function system:IsSpawning() return false end
    function system:IsSpawned() return not gone end
    function system:DeleteEntity() deletes=deletes+1; return true end
    Game.FindEntityByID=function() if not gone then return actor end end
    TweakDB={GetRecord=function() return {} end}
    DynamicEntitySpec={new=function() return {} end}
    Vector4={new=function() return {} end}
    Quaternion={new=function() return {} end}
    local id=assert(population.spawn({entity="456ULL",record=123,x=0,y=0,z=0,yaw=0}))
    assert(not population.remove(id) and deletes==0,"one attachment sample must not delete")
    if phase=="absence" then
        s.rawTick(0.01)
        assert(not population.remove(id) and deletes==1)
        gone=true; s.rawTick(0.1)
        assert(not population.remove(id),"one absence sample must not release ownership")
    end
    local deletesBefore,pushesBefore=deletes,s.pushes
    if phase=="early-engine-error" then
        s.playerUnavailable=true
        local count=#s.npcClocks
        local before=s.npcClocks[count].now
        s.rawTick(5)
        assert(#s.npcClocks>count,"error before pause lookup must invalidate NPC observations")
        local sample=s.npcClocks[#s.npcClocks]
        assert(sample.paused==nil and math.abs(sample.now-before-5)<1e-9)
        for index=count+1,#s.npcClocks do
            assert(s.npcClocks[index].now==sample.now,"cleanup invalidation never advances the clock twice")
        end
        assert(not population.remove(id) and deletes==0,"early engine error cannot qualify deletion")
        s.playerUnavailable=false
    end
    s.requestsUnavailable=true
    for _,delta in ipairs({5,7}) do
        local count=#s.npcClocks
        local before=s.npcClocks[count].now
        s.rawTick(delta)
        assert(#s.npcClocks>count,"getter failure must still pump NPC retirement")
        local sample=s.npcClocks[#s.npcClocks]
        assert(sample.paused==nil,"throwing handler getter supplies unknown pause")
        assert(math.abs(sample.now-before-delta)<1e-9,"failed tick advances clock by exactly one delta")
        for index=count+1,#s.npcClocks do
            assert(s.npcClocks[index].now==sample.now,"error invalidation reuses the current timestamp")
        end
        assert(not population.remove(id) and deletes==deletesBefore,"unknown interval cannot retire NPC")
        assert(s.pushes==pushesBefore,"handler failure must not continue normal session work")
    end
    s.requestsUnavailable=false
    local before=s.npcClocks[#s.npcClocks].now
    s.rawTick(0.01)
    local recovered=s.npcClocks[#s.npcClocks]
    assert(recovered.paused==false and math.abs(recovered.now-before-0.01)<1e-9)
    assert(not population.remove(id) and deletes==deletesBefore,"recovery requires fresh qualification")
    if phase~="absence" then
        s.rawTick(0.01)
        assert(not population.remove(id) and deletes==1,"second recovered observation may submit deletion")
    else
        s.rawTick(0.2)
        assert(not population.remove(id),"unknown interval cannot satisfy absence quiet time")
        s.rawTick(0.06)
        assert(population.remove(id),"fresh unpaused quiet interval can complete retirement")
    end
end


-- An engine failure between clock advancement and retirement observation must
-- invalidate the old qualification, including after the bridge error latches.
local function retirementStatus(state)
    local _,entry=next(state.bridge.playerRetirementDiagnostics())
    return entry and entry.status
end
local function waitForRetirement(state,status)
    for _=1,30 do
        state.tick()
        if retirementStatus(state)==status then return end
    end
    error("did not reach retirement status "..status)
end
local function injectFailure(kind,setPassiveFailure)
    if kind=="passive" then
        setPassiveFailure(true)
        return function() setPassiveFailure(false) end
    end
    local name=kind=="player" and "GetPlayer" or "GetSystemRequestsHandler"
    local original=Game[name]
    Game[name]=function()
        if kind=="pause" then
            return {IsGamePaused=function() error("injected pause lookup failure") end,
                IsPreGame=function() return false end}
        end
        error("injected "..kind.." lookup failure")
    end
    return function() Game[name]=original end
end
for _,stage in ipairs({"attachment_observation_pending","absence_observation_pending"}) do
    for _,kind in ipairs({"handler","pause","player","passive"}) do
        local passiveFailure=false
        package.loaded.player_passive={new=function()
            return {reset=function() end,pump=function()
                if passiveFailure then error("injected passive pump failure") end
            end,status=function() end,step=function() end,boundIds=function() return {} end}
        end}
        local state=fixture("HOST",false,false,kind=="passive")
        state.add(body("9007199254743993ULL"),"CP2077Session.Projection.2")
        state.init(); waitForRetirement(state,stage)
        local before=state.retirementPumps[#state.retirementPumps].now
        local restore=injectFailure(kind,function(value) passiveFailure=value end)
        state.allowBridgeError=true; state.rawTick(5)
        local bridgeErrors=0
        for _,line in ipairs(state.logs) do
            if line:find("BRIDGE_ERROR",1,true) then bridgeErrors=bridgeErrors+1 end
        end
        assert(bridgeErrors==(kind=="pause" and 0 or 1),
            kind..": pause uncertainty is nonfatal; infrastructure errors remain latched")
        local observed=state.retirementPumps[#state.retirementPumps]
        assert(observed.paused==true and math.abs(observed.now-before-5)<1e-9,
            kind..": failure invalidates known retirement at the same once-advanced time")
        assert(next(state.bridge.playerRetirementDiagnostics())~=nil,
            kind..": failed interval cannot release ownership")
        restore(); state.rawTick(1/60)
        observed=state.retirementPumps[#state.retirementPumps]
        assert(math.abs(observed.now-before-5-1/60)<1e-9,
            kind..": failed-mode resume advances by exactly its own delta")
        if stage=="attachment_observation_pending" then
            assert(#state.deleted==0,kind..": resume needs two new attached observations")
            state.rawTick(1/60)
            assert(#state.deleted==1,kind..": fresh second observation permits deletion")
            state.rawTick(1/60)
        end
        assert(retirementStatus(state)=="absence_observation_pending",
            kind..": resume begins a new absence interval")
        state.rawTick(0.1); state.rawTick(0.1)
        assert(next(state.bridge.playerRetirementDiagnostics())~=nil,
            kind..": less than the fresh quiet interval retains ownership")
        state.rawTick(0.051)
        assert(next(state.bridge.playerRetirementDiagnostics())==nil,
            kind..": complete fresh quiet interval permits retirement")
        local activations=0
        for _,value in ipairs(state.activations) do if value then activations=activations+1 end end
        assert(activations==1,kind..": cleanup recovery does not restart the session")
        state.shutdown(); package.loaded.player_passive=nil
    end
end

-- Unknown pause context in an already-failed tick also resets the quiet window.
-- Neither a missing handler nor a non-boolean pause value means unpaused.
for _,kind in ipairs({"handler","pause","nil-handler","nil-pause","malformed-pause"}) do
    local state=fixture("HOST",false,false)
    state.add(body("9007199254744993ULL"),"CP2077Session.Projection.2")
    state.init(); waitForRetirement(state,"absence_observation_pending")
    local restorePlayer=injectFailure("player")
    state.allowBridgeError=true; state.rawTick(1/60); restorePlayer(); state.rawTick(1/60)
    assert(retirementStatus(state)=="absence_observation_pending")
    local original=Game.GetSystemRequestsHandler
    local restore
    if kind=="handler" or kind=="pause" then restore=injectFailure(kind)
    else
        Game.GetSystemRequestsHandler=function()
            if kind=="nil-handler" then return nil end
            return {IsGamePaused=function()
                if kind=="malformed-pause" then return "false" end
            end}
        end
        restore=function() Game.GetSystemRequestsHandler=original end
    end
    local before=state.retirementPumps[#state.retirementPumps].now
    state.rawTick(5)
    local observed=state.retirementPumps[#state.retirementPumps]
    assert(observed.paused==true and math.abs(observed.now-before-5)<1e-9,
        kind..": failed mode reports unavailable pause at current time")
    restore(); state.rawTick(1/60); state.rawTick(0.2)
    assert(next(state.bridge.playerRetirementDiagnostics())~=nil,
        kind..": failed-mode unknown interval cannot finish removal")
    state.rawTick(0.051)
    assert(next(state.bridge.playerRetirementDiagnostics())==nil,
        kind..": retirement recovers only after a new quiet interval")
    state.shutdown()
end
-- Cleanup can return early on one NPC, leaving a second NPC's last sample at
-- an older clock. A failed frame must invalidate BEFORE stop/reset samples it.
do
    local s=fixture("JOINER",false); s.init(); s.tick()
    local system=Game.GetDynamicEntitySystem()
    local actors,nextId,deletes={},100,0
    function system:CreateEntity()
        nextId=nextId+1
        local id={hash=tostring(nextId).."ULL"}
        actors[id.hash]={GetEntityID=function() return id end,IsAttached=function() return true end}
        return id
    end
    function system:GetEntity(id) return actors[id.hash] end
    function system:IsManaged(id) return actors[id.hash]~=nil end
    function system:IsSpawning() return false end
    function system:IsSpawned(id) return actors[id.hash]~=nil end
    function system:DeleteEntity() deletes=deletes+1; return true end
    Game.FindEntityByID=function(id) return actors[id.hash] end
    Game.CP2077Session_Resolve=function() return "0ULL" end
    Game.GetTeleportationFacility=function() return {Teleport=function() end} end
    TweakDB={GetRecord=function() return {} end}
    DynamicEntitySpec={new=function() return {} end}
    Vector4={new=function() return {} end}
    Quaternion={new=function() return {} end}
    EulerAngles={new=function() return {} end}
    local c=s.npcProjection
    local identity=c.identity
    local bubble={radius=100,centers={{x=0,y=0,z=0}}}
    local a={entity="456ULL",record=123,x=0,y=0,z=0,yaw=0}
    local b={entity="789ULL",record=123,x=0,y=0,z=0,yaw=0}
    local byId={[a.entity]=a,[b.entity]=b}
    assert(c:step(identity,bubble,{a,b}))
    -- Choose the runtime's iteration order rather than relying on hash order.
    local first=next(c.owned)
    local second=first==a.entity and b.entity or a.entity
    assert(not c:step(identity,bubble,{byId[first]}))
    s.rawTick(1)
    assert(not c:step(identity,bubble,{byId[second]}))
    assert(deletes==0,"both retirements have only one attachment observation")
    local count=#s.npcClocks
    local before=s.npcClocks[count].now
    s.playerUnavailable=true
    s.rawTick(1)
    assert(deletes==0,"early failure must invalidate cached NPC context before reset deletes")
    assert(c.owned[first] and c.owned[second],"failed frame retains both owned IDs")
    for index=count+1,#s.npcClocks do
        assert(s.npcClocks[index].paused==nil and math.abs(s.npcClocks[index].now-before-1)<1e-9,
            "pre/post cleanup invalidation uses one unknown timestamp")
    end
    s.playerUnavailable=false
    s.rawTick(0.01)
    assert(deletes==0,"recovery must collect a fresh first attachment sample")
    s.rawTick(0.01)
    assert(deletes==2,"only fresh second attachment samples may submit deletion")
end

-- Map input does not wait for the avatar's dynamic entity system. A temporarily
-- unavailable cleanup is retried while the save remains unloaded.
s=fixture("HOST",false,false,false,true)
s.dynamicUnavailable=true; s.remotes={{id=2,entity=uint64(1),x=10},{id=3,entity=uint64(2),x=20}}
s.init(); s.tick(2)
assert(s.markers[2].x==10 and s.markers[3].x==20 and s.playerSpawns==0)
s.remotes={{id=3,entity=uint64(2),x=25}}; s.tick(12)
assert(not s.markers[2] and s.markers[3].x==25)
s.markerCleanupFails=true; s.hasPlayer=false; s.tick()
assert(s.bridge.markerDiagnostics()["3"].retiring and s.markers[3])
s.markerCleanupFails=false; s.tick(90)
assert(not s.markers[3] and next(s.bridge.markerDiagnostics())==nil)
s.shutdown()
s=fixture("HOST",false,false,false,false)
s.phase=1; s.markers[77]={x=123}; s.init(); s.tick()
assert(next(s.markers)==nil,"disabled/disconnected reload clears retained owned pins")
s.shutdown()
s=fixture("HOST",false,false,false,false); s.init(); s.tick()
ImGui={Begin=function() return true end,Text=function() end,End=function() end,Button=function() return true end}
s.overlayOpen(); local activations=#s.activations; s.draw(); s.draw()
assert(#s.activations==activations,"UI draw must not run engine/session cleanup")
s.tick(); assert(#s.activations==activations+2,"queued UI reconnect runs once on update")
ImGui=nil; s.shutdown()
-- A persistent engine lookup error must not let the UI prevent failed-mode cleanup.
do
    local state=fixture("HOST",false,false,false,true)
    state.remotes={{id=2,entity=uint64(1),x=10}}
    state.init(); state.tick(2)
    assert(state.markers[2],"seed an owned marker")
    local getPlayer=Game.GetPlayer
    Game.GetPlayer=function() error("persistent player lookup failure") end
    state.allowBridgeError=true; state.markerCleanupFails=true
    state.tick()
    assert(state.markers[2],"failed cleanup keeps the marker owned")
    state.markerCleanupFails=false
    local ok,reason=pcall(function() state.tick(90) end)
    assert(ok,"UI player lookup must not escape failed-mode cleanup: "..tostring(reason))
    assert(not state.markers[2] and next(state.bridge.markerDiagnostics())==nil,
        "marker retirement must progress even while player lookup keeps failing")
    Game.GetPlayer=getPlayer
    state.shutdown()
end
-- The real entrypoint forwards an admitted baseline without mutating health,
-- and remains usable with a previous DLL that has no life getter.
do
    local state=fixture("JOINER",true,false,false,false)
    state.init();state.tick()
    local observed
    state.npcProjection.step=function(_,_,_,npcs)observed=npcs;return true end
    local entity=uint64(1)
    Game.CP2077Session_NpcCount=function()return 1 end
    Game.CP2077Session_NpcSelect=function(index)return index==0 end
    Game.CP2077Session_NpcEntity=function()return entity end
    Game.CP2077Session_NpcRecord=function()return "123" end
    Game.CP2077Session_NpcX=function()return 1 end
    Game.CP2077Session_NpcY=function()return 2 end
    Game.CP2077Session_NpcZ=function()return 3 end
    Game.CP2077Session_NpcYaw=function()return 0 end
    Game.CP2077Session_NpcLifeKnown=function()return true end
    Game.CP2077Session_NpcLifeHealth=function()return 0 end
    Game.CP2077Session_NpcLifeMaxHealth=function()return 100 end
    Game.CP2077Session_NpcLifeStatus=function()return 3 end
    Game.CP2077Session_NpcLifeRevision=function()return 77 end
    state.tick()
    assert(#observed==1 and observed[1].entity==entity and observed[1].lifeState.status==3
        and observed[1].lifeState.revision==77 and observed[1].lifeState.health==0)
    Game.CP2077Session_NpcLifeKnown=nil
    state.tick()
    assert(#observed==1 and observed[1].x==1 and observed[1].lifeState==nil,
        "old DLL keeps existing movement and unknown life state")
    state.shutdown()
end
print=report
report("session_lifecycle: PASS (startup, stable Uint64 identity, replacement, unload, reconnect, NPC opt-in; " ..
    (hasFfi and "LuaJIT Uint64 cdata" or "opaque Uint64 mock") .. ")")
