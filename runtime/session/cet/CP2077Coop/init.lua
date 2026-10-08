-- Matched typed-session bridge. No combat/world side effects or legacy native calls.
local NpcRuntime = require("npc_runtime")
local PlayerPose = assert(require("player_pose"), "player_pose module missing")
local population = require("npc_population")
local config = require("config")
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
local function clear()
    if passivePlayers then passivePlayers:reset() end
    for _, entry in pairs(proxies) do if entry.pose then entry.pose:reset() end end
    ensureNpcProjection()
    npcProjection:reset()
    local system = Game.GetDynamicEntitySystem()
    if system ~= nil and system:IsReady() then
        system:DeleteTagged(CName.new(commonTag))
    end
    proxies = {}
    joined = false
end
local function stop()
    Game.CP2077Session_SetActive(false)
    clear()
    active, generation, localEntity = false, nil, nil
end
local function update(delta)
    time = time + delta
    -- Continue observing asynchronous retirement even while no save is loaded.
    if passivePlayers then passivePlayers:pump() end
    local player = Game.GetPlayer()
    local requests = Game.GetSystemRequestsHandler()
    local loaded = player ~= nil and player:IsAttached() and
        (requests == nil or not requests:IsPreGame())
    if not loaded then
        if active then stop() end
        return
    end
    -- CET returns a fresh EntityID wrapper. Compare its exact Uint64 value,
    -- not the wrapper's address, and never round it through a Lua number.
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
    local system = Game.GetDynamicEntitySystem()
    local dynamicReady = system ~= nil and system:IsReady()
    if not dynamicReady then return end
    if passivePlayers and #system:GetTagged(CName.new(commonTag)) > 0 then
        -- DeleteTagged is asynchronous. Old dynamic bodies must disappear
        -- before the experimental representation can be considered active.
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
            if not joined and Game.CP2077Session_Self() ~= Game.CP2077Session_Host() and id == Game.CP2077Session_Host() then
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
                entry.pose:reset()
                system:DeleteTagged(entry.tag)
                proxies[id], entry = nil, nil
            end
            if entry == nil then
                entry = { tag = CName.new(commonTag .. "." .. tostring(id)), entity = entity, nextSpawn = 0 }
                entry.pose = PlayerPose.new(function(status)
                    print("[CP2077Session] PLAYER_POSE player=" .. tostring(id) .. " " .. status)
                end)
                proxies[id] = entry
            end
            local entities = system:GetTagged(entry.tag)
            local proxy = entities[1]
            if proxy == nil then
                if time >= entry.nextSpawn then
                    player:CP2077Session_SpawnProxy(entry.tag, x, y, z)
                    entry.nextSpawn = time + 1
                end
            else
                if not Game.CP2077Session_Bind(entry.entity, proxy:GetEntityID()) then
                    error("Remote projection binding rejected for player " .. tostring(id))
                end
                bubble.exclusions[#bubble.exclusions+1] = proxy:GetEntityID()
                -- Keep sampling interpolation while one owned engine command is
                -- pending. Only actual transform readback confirms placement.
                entry.pose:step(proxy, {x=x,y=y,z=z,yaw=yaw}, time)
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
        if not seen[id] then entry.pose:reset(); system:DeleteTagged(entry.tag); proxies[id] = nil end
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
    if failed then
        -- A latched bridge failure must not discard still-owned static tokens.
        if passivePlayers then pcall(function() passivePlayers:reset() end) end
        return
    end
    local ok, reason = pcall(update, delta)
    if not ok then
        failed = true
        pcall(stop)
        print("[CP2077Session] BRIDGE_ERROR " .. tostring(reason))
    end
end)
registerForEvent("onShutdown", function() if initialized then pcall(stop) end end)
registerHotkey("cp2077_session_reconnect", "Reconnect coop session", function()
    if not initialized then return end
    pcall(stop)
    failed = false
end)
