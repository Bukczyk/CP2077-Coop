-- Matched typed-session bridge. No combat/world side effects or legacy native calls.
local NpcRuntime = require("npc_runtime")
local PlayerPose = assert(require("player_pose"), "player_pose module missing")
local PlayerLifetime = assert(require("player_lifetime"), "player_lifetime module missing")
local population = require("npc_population")
local config = require("config")
local PlayerMotor = require("player_motor")
local sessionUI = require("session_ui").new()
local overlayOpen = false
local reconnect, reconnectRequested
local usePlayerMotor = config.experimentalPlayerMovement == true
local markers = require("player_markers").new(function(status)
    print("[CP2077Session] PLAYER_MARKER " .. status)
end)
local passivePlayers = nil
if config.experimentalPassivePlayers == true then
    local PassivePlayers = assert(require("player_passive"), "player_passive module missing")
    passivePlayers = PassivePlayers.new(function(status)
        print("[CP2077Session] PASSIVE_PLAYER " .. status)
    end)
end
local staticPopulation = require("npc_static_population")
local npcProjection = nil
local staticProjectionEnabled = false
local activePopulation = population
local function ensureNpcProjection()
    if npcProjection ~= nil then return end
    local ok, enabled = pcall(function() return Game.CP2077Session_ExperimentalStaticNpcProjection() end)
    staticProjectionEnabled = ok and enabled == true
    activePopulation = staticProjectionEnabled and staticPopulation or population
    npcProjection = NpcRuntime.new(activePopulation)
    if staticProjectionEnabled then print("[CP2077Session] EXPERIMENTAL_STATIC_NPC_PROJECTION enabled; requires imported asset base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent") end
end
local pendingNpcs, hostNpcs = {}, {}
local npcLimit, npcWarning = 128, false
local initialized = false
local proxies = {} -- PlayerId -> { tag, SessionEntityId (opaque Uint64), nextSpawn }
local generation, localEntity, joined = nil, nil, false
local active, failed, time = false, false, 0
local commonTag = "CP2077Session.Projection"
local retiring, recoveryPending = {}, true
local function own(entry, id)
    entry.life = PlayerLifetime.new(id, function(status)
        print("[CP2077Session] PLAYER_LIFETIME " .. status)
    end, function()
        -- Never unbind a different exact mapping after a session transition.
        if entry.bound then
            local resolved = tostring(Game.CP2077Session_Resolve(id)):gsub("[uUlL]+$", "")
            local expected = tostring(entry.entity):gsub("[uUlL]+$", "")
            if resolved == expected then
                if not Game.CP2077Session_Unbind(entry.entity) then return false end
            elseif resolved ~= "0" then return false end
            entry.bound = false
        end
        if entry.pose and not entry.pose:release() then return false end
        if entry.motor then entry.motor:stop(); entry.motor = nil end
        return true
    end)
end
local function retire(entry)
    if entry.life then
        entry.life:retire()
        retiring[entry.life.key] = entry
    end
end
local function actorStatus(entry, status)
    entry.actorState = status
    entry.actorReports = entry.actorReports or {}
    if not entry.actorReports[status] then
        entry.actorReports[status] = true
        print("[CP2077Session] PLAYER_ACTOR entity=" .. tostring(entry.entity)
            .. " actor=" .. (entry.life and entry.life.key or "pending") .. " status=" .. status)
    end
end
local function shutdownCommands(entry)
    -- Shutdown has no later update callback. Release only commands we already
    -- own, without trying to delete a not-yet-attached dynamic entity.
    if entry.bound then
        local resolved = tostring(Game.CP2077Session_Resolve(entry.life.id)):gsub("[uUlL]+$", "")
        local expected = tostring(entry.entity):gsub("[uUlL]+$", "")
        if resolved ~= "0" and resolved ~= expected then error("shutdown binding changed") end
    end
    local function exactCommandActor(command, actor)
        if command == nil then return end
        if actor == nil or tostring(actor:GetEntityID().hash):gsub("[uUlL]+$", "") ~= entry.life.key then
            error("shutdown command actor identity mismatch")
        end
    end
    local errors = {}
    if entry.pose then
        local ok, released = pcall(function()
            exactCommandActor(entry.pose.command, entry.pose.actor)
            return entry.pose:release()
        end)
        if not ok or released ~= true then errors[#errors+1] = "pose release: " .. tostring(released) end
    end
    if entry.motor then
        local ok, reason = pcall(function()
            exactCommandActor(entry.motor.command, entry.motor.actor)
            entry.motor:stop()
        end)
        if not ok then errors[#errors+1] = "motor stop: " .. tostring(reason) end
    end
    if #errors > 0 then error(table.concat(errors, "; ")) end
end
local function pumpRetirement(paused)
    -- Managed tags recover pending actors across reload. In-flight deletions
    -- require draining before reload; tags alone cannot recover lost tombstones.
    if recoveryPending then
        local s = Game.GetDynamicEntitySystem()
        if s and s:IsReady() then
            for _, id in ipairs(s:GetTaggedIDs(CName.new(commonTag))) do
                local entry = {}
                own(entry, id); retire(entry)
            end
            recoveryPending = false
        end
    end
    for key, entry in pairs(retiring) do
        if entry.life:pump(time, paused) then
            if entry.pose then entry.pose:reset() end
            retiring[key] = nil
        end
    end
end
local function retainDynamicRetirement()
    -- This part is independent of engine/native cleanup. Even a failed native
    -- deactivation or a different representation's reset must retain our IDs.
    for _, entry in pairs(proxies) do retire(entry) end
    proxies = {}
    joined = false
end
local function clear()
    retainDynamicRetirement()
    if markers then markers:reset(time) end
    local errors = {}
    if passivePlayers then
        local ok, reason = pcall(function() passivePlayers:reset() end)
        if not ok then errors[#errors+1] = "passive reset: " .. tostring(reason) end
    end
    local ok, reason = pcall(function()
        ensureNpcProjection()
        npcProjection:reset()
    end)
    if not ok then errors[#errors+1] = "NPC reset: " .. tostring(reason) end
    if #errors > 0 then error(table.concat(errors, "; ")) end
end
local function stop()
    retainDynamicRetirement()
    active, generation, localEntity = false, nil, nil
    local deactivated, reason = pcall(function() Game.CP2077Session_SetActive(false) end)
    local cleared, cleanupReason = pcall(clear)
    local errors = {}
    if not deactivated then errors[#errors+1] = "native deactivation: " .. tostring(reason) end
    if not cleared then errors[#errors+1] = tostring(cleanupReason) end
    if #errors > 0 then error(table.concat(errors, "; ")) end
end
local function update(delta)
    time = time + delta
    if markers then markers:drain(time) end
    -- Continue observing asynchronous retirement even while no save is loaded.
    if passivePlayers then passivePlayers:pump() end
    local player = Game.GetPlayer()
    local requests = Game.GetSystemRequestsHandler()
    local paused = requests ~= nil and requests:IsGamePaused()
    pumpRetirement(paused)
    local loaded = player ~= nil and player:IsAttached() and
        (requests == nil or not requests:IsPreGame())
    if not loaded then
        sessionUI:update({loaded=false})
        if active then stop() end
        return
    end
    -- CET returns a fresh EntityID wrapper. Compare its exact Uint64 value,
    -- not the wrapper's address, and never round it through a Lua number.
    markers:recover(player,time) -- also clean our retained handles when disabled/disconnected
    local currentEntity = tostring(player:GetEntityID().hash)
    if active and currentEntity ~= localEntity then stop() end
    if not active then
        clear()
        active, localEntity = true, currentEntity
        Game.CP2077Session_SetActive(true)
    end
    local position = player:GetWorldPosition()
    local angles = player:GetWorldOrientation():ToEulerAngles()
    Game.CP2077Session_PushLocal(position.x, position.y, position.z, math.rad(angles.yaw))
    local count = Game.CP2077Session_BeginFrame()
    sessionUI:update({loaded=true,phase=Game.CP2077Session_Phase(),session=Game.CP2077Session_Session(),
        player=Game.CP2077Session_Self(),host=Game.CP2077Session_Host(),remotes=count})
    local nextGeneration = tostring(Game.CP2077Session_Generation()) .. ":" .. tostring(Game.CP2077Session_Session()) .. ":" .. tostring(Game.CP2077Session_Epoch())
    if generation ~= nextGeneration then
        clear(); generation = nextGeneration
        for _, entry in pairs(hostNpcs) do entry.adopted = false end
    end
    -- ClientPhase::Active; admission/baseline is handled by the SessionClient.
    if Game.CP2077Session_Phase() ~= 4 then clear(); return end
    if not Game.CP2077Session_Bind(Game.CP2077Session_SelfEntity(), player:GetEntityID()) then
        error("Local player projection binding rejected")
    end
    -- Same coherent native frame, independent of actor creation/readback.
    if config.experimentalPlayerMarkers == true then
        local frame = {}
        for index = 0, count - 1 do
            if Game.CP2077Session_Select(index) and Game.CP2077Session_Player() ~= Game.CP2077Session_Self() then
                frame[#frame+1] = {player=Game.CP2077Session_Player(),entity=Game.CP2077Session_Entity(),
                    x=Game.CP2077Session_X(),y=Game.CP2077Session_Y(),z=Game.CP2077Session_Z(),yaw=Game.CP2077Session_Yaw()}
            end
        end
        markers:step(generation, player, frame, time)
    end
    local system = Game.GetDynamicEntitySystem()
    local dynamicReady = system ~= nil and system:IsReady()
    if not dynamicReady then return end
    if passivePlayers and (recoveryPending or next(retiring) ~= nil) then
        passivePlayers:reset()
        passivePlayers:status("dynamic_retirement_pending")
        return
    end
    local seen = {}
    local passiveFrame = {}
    local bubble = { radius = Game.CP2077Session_BubbleRadius(), centers = { {x=position.x,y=position.y,z=position.z} }, exclusions = {player:GetEntityID()} }
    for index = 0, count - 1 do
        if Game.CP2077Session_Select(index) then
            local id = Game.CP2077Session_Player()
            local entity = Game.CP2077Session_Entity() -- keep Uint64 opaque; never tonumber()
            local x, y, z = Game.CP2077Session_X(), Game.CP2077Session_Y(), Game.CP2077Session_Z()
            local yaw = Game.CP2077Session_Yaw()
            seen[id] = true
            bubble.centers[#bubble.centers+1] = {x=x,y=y,z=z}
            if not paused and not joined and Game.CP2077Session_Self() ~= Game.CP2077Session_Host() and id == Game.CP2077Session_Host() then
                Game.GetTeleportationFacility():Teleport(player, Vector4.new(x + 1.75, y, z, 1), EulerAngles.new(0, 0, math.deg(yaw)))
                -- Update the coherent local snapshot immediately after the baseline teleport.
                Game.CP2077Session_PushLocal(x + 1.75, y, z, yaw)
                joined = true
                bubble.centers[1] = {x=x+1.75,y=y,z=z}
                print("[CP2077Session] JOINER_BASELINE_TELEPORT player=" .. tostring(id))
            end
            if passivePlayers then
                passiveFrame[#passiveFrame + 1] = {player=id, entity=entity, x=x, y=y, z=z, yaw=yaw}
            else
            local entry = proxies[id]
            if entry ~= nil and tostring(entry.entity) ~= tostring(entity) then
                retire(entry)
                proxies[id], entry = nil, nil
            end
            if entry == nil then
                entry = { tag = CName.new(commonTag .. "." .. tostring(id)), entity = entity, nextSpawn = 0 }
                entry.pose = PlayerPose.new(function(status)
                    print("[CP2077Session] PLAYER_POSE player=" .. tostring(id) .. " " .. status)
                end)
                proxies[id] = entry
            end
            entry.target = {x=x,y=y,z=z,yaw=yaw}
            local proxy = entry.life and entry.life:actor()
            if proxy == nil then
                if entry.life and entry.life.blocked then
                    actorStatus(entry, entry.life.status)
                elseif entry.localKey then
                    actorStatus(entry, "actor_missing")
                else
                    actorStatus(entry, entry.life and "spawn_pending" or "spawn_waiting")
                end
                if not entry.life and not recoveryPending and next(retiring) == nil
                    and not paused and time >= entry.nextSpawn then
                    local created = player:CP2077Session_SpawnProxy(entry.tag, x, y, z)
                    local key = created and tostring(created.hash):gsub("[uUlL]+$", "")
                    if key and key ~= "0" then own(entry, created); actorStatus(entry, "spawn_pending") end
                    entry.nextSpawn = time + 1
                end
            else
                actorStatus(entry, proxy:IsAttached() and "actor_present" or "attachment_pending")
                local localKey = tostring(proxy:GetEntityID().hash)
                if entry.localKey ~= localKey then
                    entry.pose:reset()
                    if entry.motor then entry.motor:stop() end
                    entry.localKey = localKey
                    if usePlayerMotor then entry.motor = PlayerMotor.new(proxy) end
                end
                if not Game.CP2077Session_Bind(entry.entity, proxy:GetEntityID()) then
                    error("Remote projection binding rejected for player " .. tostring(id))
                end
                entry.bound = true
                bubble.exclusions[#bubble.exclusions+1] = proxy:GetEntityID()
                -- Keep sampling interpolation while one owned engine command is
                -- pending. Only actual transform readback confirms placement.
                if entry.motor then
                    if not paused then entry.motor:step({x=x,y=y,z=z,yaw=yaw}, delta) end
                else
                    entry.pose:step(proxy, {x=x,y=y,z=z,yaw=yaw}, time, paused)
                end
            end
            end -- selected player representation
        end
    end
    if passivePlayers then
        passivePlayers:step(generation, passiveFrame, time)
        for _, id in ipairs(passivePlayers:boundIds()) do bubble.exclusions[#bubble.exclusions+1] = id end
    end
    if config.experimentalNpcReplication and dynamicReady then
        npcLimit = Game.CP2077Session_NpcCapacity()
        if Game.CP2077Session_Self() == Game.CP2077Session_Host() then
            local countNpc = 0
            for _ in pairs(hostNpcs) do countNpc = countNpc + 1 end
            for _, npc in ipairs(pendingNpcs) do
                if npc ~= nil and npc:IsAttached() then
                    local localId = npc:GetEntityID()
                    if not system:IsTagged(localId, CName.new(commonTag)) and countNpc < npcLimit then
                        local key = tostring(localId.hash)
                        if not hostNpcs[key] then
                            hostNpcs[key] = { object = npc, localId = localId, adopted = false }
                            countNpc = countNpc + 1
                        end
                    end
                end
            end
            pendingNpcs = {}
            for key, entry in pairs(hostNpcs) do
                local npc = entry.object
                if npc == nil or not npc:IsAttached() then
                    Game.CP2077Session_NpcForget(entry.localId)
                    hostNpcs[key] = nil
                else
                    local p = npc:GetWorldPosition()
                    if entry.adopted or NpcRuntime.contains(bubble, p) then
                        local yaw = math.rad(npc:GetWorldOrientation():ToEulerAngles().yaw)
                        if Game.CP2077Session_NpcOffer(entry.localId, npc:GetRecordID(), p.x, p.y, p.z, yaw) then entry.adopted = true end
                    end
                end
            end
        else
            pendingNpcs, hostNpcs = {}, {}
            local npcs = {}
            for index = 0, Game.CP2077Session_NpcCount()-1 do
                if Game.CP2077Session_NpcSelect(index) then
                    npcs[#npcs+1] = {
                        entity = Game.CP2077Session_NpcEntity(), record = Game.CP2077Session_NpcRecord(),
                        x = Game.CP2077Session_NpcX(), y = Game.CP2077Session_NpcY(), z = Game.CP2077Session_NpcZ(), yaw = Game.CP2077Session_NpcYaw()
                    }
                end
            end
            if #npcs > 0 and not npcWarning then
                npcWarning = true
                local ready, reason = activePopulation.available()
                if ready then
                    if staticProjectionEnabled then
                        print("[CP2077Session] EXPERIMENTAL_STATIC_NPC_PROJECTION_ACTIVE: render-only prototype; not a gameplay NPC")
                    else
                        print("[CP2077Session] NPC_PROJECTION_ACTIVE: creation enabled; AI and ambient suppression are not implemented")
                    end
                else
                    print("[CP2077Session] NPC_PROJECTION_UNAVAILABLE: " .. tostring(reason))
                end
            end
            if not npcProjection:step(generation, bubble, npcs) and #npcs > 0 then
                print("[CP2077Session] NPC_PROJECTION_RETRY: create, bind or cleanup did not complete")
            end
        end
    end -- experimentalNpcReplication; player cleanup always runs
    for id, entry in pairs(proxies) do
        if not seen[id] then
            retire(entry); proxies[id] = nil
        end
    end
end
registerForEvent("onInit", function()
    -- Engine observation is unavailable while CET loads the module.
    Observe("NPCPuppet", "OnGameAttached", function(npc)
        if config.experimentalNpcReplication and #pendingNpcs < npcLimit then
            pendingNpcs[#pendingNpcs+1] = npc
        end
    end)
    initialized = true
    print("[CP2077Session] INIT npc_replication=" .. tostring(config.experimentalNpcReplication)
        .. " passive_players=" .. tostring(passivePlayers ~= nil))
end)
registerForEvent("onUpdate", function(delta)
    if not initialized then return end
    if reconnectRequested then reconnectRequested=false; reconnect() end
    if failed then
        sessionUI:update({loaded=Game.GetPlayer()~=nil,error=true})
        -- A latched bridge failure must not discard still-owned static tokens.
        if passivePlayers then pcall(function() passivePlayers:reset() end) end
        time = time + delta
        if markers then pcall(function() markers:reset(time) end) end
        pcall(function()
            local requests = Game.GetSystemRequestsHandler()
            pumpRetirement(requests ~= nil and requests:IsGamePaused())
        end)
        return
    end
    local ok, reason = pcall(update, delta)
    if not ok then
        failed = true
        sessionUI:update({loaded=true,error=true})
        local stopped, cleanupReason = pcall(stop)
        print("[CP2077Session] BRIDGE_ERROR " .. tostring(reason)
            .. (stopped and "" or "; cleanup: " .. tostring(cleanupReason)))
    end
end)
registerForEvent("onShutdown", function()
    if not initialized then return end
    local ok, reason = pcall(stop)
    if not ok then
        failed = true
        print("[CP2077Session] BRIDGE_ERROR shutdown: " .. tostring(reason))
    end
    for key, entry in pairs(retiring) do
        local released, reason = pcall(shutdownCommands, entry)
        if not released then
            failed = true
            print("[CP2077Session] PLAYER_SHUTDOWN_RELEASE actor=" .. key
                .. " status=unconfirmed reason=" .. tostring(reason))
        else
            print("[CP2077Session] PLAYER_SHUTDOWN_RELEASE actor=" .. key .. " status=requested")
        end
    end
end)
reconnect = function()
    if not initialized then return end
    sessionUI:reconnect()
    local ok, reason = pcall(stop)
    failed = not ok
    if not ok then print("[CP2077Session] BRIDGE_ERROR reconnect: " .. tostring(reason)) end
end
registerHotkey("cp2077_session_reconnect", "Reconnect coop session", reconnect)
registerForEvent("onOverlayOpen", function() overlayOpen=true end)
registerForEvent("onOverlayClose", function() overlayOpen=false end)
registerForEvent("onDraw", function()
    if not initialized or not overlayOpen or config.showSessionUI~=true then return end
    sessionUI:draw(ImGui,function()
        -- Draw only requests the action. Engine cleanup stays on onUpdate.
        reconnectRequested=true
        sessionUI:reconnect()
    end)
end)

-- Value-only diagnostics for local test tooling. No engine handles or setters.
return { markerDiagnostics = function() return markers and markers:diagnostics() or {} end,
playerRetirementDiagnostics = function()
    local result = {}
    for key, entry in pairs(retiring) do
        result[key] = {status=entry.life.status, blocked=entry.life.blocked,
            deleteIssued=entry.life.deleteIssued, deleteAttempts=entry.life.deleteAttempts}
    end
    return result
end, playerDiagnostics = function()
    local result = {}
    for id, entry in pairs(proxies) do
        local t, m = entry.target, entry.motor
        result[tostring(id)] = {
            entity=tostring(entry.entity), actor=entry.localKey,
            x=t and t.x, y=t and t.y, z=t and t.z, yaw=t and t.yaw,
            mode=m and "motor" or "pose", fault=entry.pose and entry.pose.fault,
            pose=entry.pose and entry.pose:diagnostics(),
            lifecycle=entry.life and (entry.life.status == "owned" and entry.actorState or entry.life.status),
            actorState=entry.actorState,
            error=m and m.error, speed=m and m.speed, gait=m and m.gait,
            commands=m and m.commands, snaps=m and m.snaps,
        }
    end
    return result
end }
