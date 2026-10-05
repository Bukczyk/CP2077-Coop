-- Matched typed-session bridge. No combat/world side effects or legacy native calls.
local NpcRuntime = require("npc_runtime")
local population = require("npc_population")
local npcProjection = NpcRuntime.new(population)
local pendingNpcs, hostNpcs = {}, {}
local npcLimit, npcWarning = 128, false
Observe("NPCPuppet", "OnGameAttached", function(npc)
    if #pendingNpcs < npcLimit then pendingNpcs[#pendingNpcs+1] = npc end
end)
local proxies = {} -- PlayerId -> { tag, SessionEntityId (opaque Uint64), nextSpawn }
local generation, localEntity, joined = nil, nil, false
local active, failed, time = false, false, 0
local commonTag = "CP2077Session.Projection"
local function clear()
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
    local player = Game.GetPlayer()
    local requests = Game.GetSystemRequestsHandler()
    local loaded = player ~= nil and player:IsAttached() and
        (requests == nil or not requests:IsPreGame())
    if not loaded then
        if active then stop() end
        return
    end
    local currentEntity = tostring(player:GetEntityID())
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
    if system == nil or not system:IsReady() then return end
    local seen = {}
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
            local entry = proxies[id]
            if entry == nil then
                entry = { tag = CName.new(commonTag .. "." .. tostring(id)), entity = entity, nextSpawn = 0 }
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
                -- Each render frame samples the shared interpolation buffer. This is not
                -- packet-triggered teleportation; extrapolation/snap policy lives in C++.
                Game.GetTeleportationFacility():Teleport(proxy, Vector4.new(x, y, z, 1), EulerAngles.new(0, 0, math.deg(yaw)))
            end
        end
    end
    npcLimit = Game.CP2077Session_NpcCapacity()
    if Game.CP2077Session_Self() == Game.CP2077Session_Host() then
        local countNpc = 0
        for _ in pairs(hostNpcs) do countNpc = countNpc + 1 end
        for _, npc in ipairs(pendingNpcs) do
            if npc ~= nil and npc:IsAttached() then
                local localId = npc:GetEntityID()
                if not system:IsTagged(localId, CName.new(commonTag)) and countNpc < npcLimit then
                    local key = tostring(localId)
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
            local ready, reason = population.available()
            if ready then
                print("[CP2077Session] NPC_PROJECTION_ACTIVE: creation enabled; AI and ambient suppression are not implemented")
            else
                print("[CP2077Session] NPC_PROJECTION_UNAVAILABLE: " .. tostring(reason))
            end
        end
        if not npcProjection:step(generation, bubble, npcs) and #npcs > 0 then
            print("[CP2077Session] NPC_PROJECTION_RETRY: create, bind or cleanup did not complete")
        end
    end
    for id, entry in pairs(proxies) do
        if not seen[id] then system:DeleteTagged(entry.tag); proxies[id] = nil end
    end
end
registerForEvent("onUpdate", function(delta)
    if failed then return end
    local ok, reason = pcall(update, delta)
    if not ok then
        failed = true
        pcall(stop)
        print("[CP2077Session] BRIDGE_ERROR " .. tostring(reason))
    end
end)
registerForEvent("onShutdown", function() pcall(stop) end)
registerHotkey("cp2077_session_reconnect", "Reconnect coop session", function()
    pcall(stop)
    failed = false
end)
