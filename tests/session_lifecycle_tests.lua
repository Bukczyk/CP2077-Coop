-- Executes the real CET entrypoint, including lifecycle registration. Engine
-- mocks deliberately return a new EntityID wrapper on every read.
local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local report = print
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
    }
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
        experimentalPlayerMarkers=markers==true} end
    print = function(message) state.logs[#state.logs+1] = tostring(message) end
    registerForEvent = function(name, callback)
        assert(events[name] == nil, "duplicate lifecycle registration")
        events[name] = callback
    end
    registerHotkey = function(name, _, callback) hotkeys[name] = callback end
    state.bridge=assert(loadfile(root .. "/runtime/session/cet/CP2077Coop/init.lua"))()
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
        GetPlayer=function() if state.hasPlayer then return player end end,
        GetSystemRequestsHandler=function()
            return {IsPreGame=function() return state.pregame end,
                IsGamePaused=function() return state.paused == true end}
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
        CP2077Session_BeginFrame=function() return #state.remotes end,
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
    state.shutdown=events.onShutdown
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
    return {step=function(self,target) self.target=target end,
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
s.shutdown()
package.loaded.player_motor=nil
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
print=report
report("session_lifecycle: PASS (startup, stable Uint64 identity, replacement, unload, reconnect, NPC opt-in; " ..
    (hasFfi and "LuaJIT Uint64 cdata" or "opaque Uint64 mock") .. ")")
