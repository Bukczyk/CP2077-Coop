-- Matched typed-session bridge. No combat/world side effects or legacy native calls.
local proxies = {} -- PlayerId -> { tag, SessionEntityId (opaque Uint64), nextSpawn }
local generation, localEntity, joined = nil, nil, false
local active, failed, time = false, false, 0
local commonTag = "CP2077Session.Projection"
local function clear()
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
    local nextGeneration = tostring(Game.CP2077Session_Generation()) .. ":" .. tostring(Game.CP2077Session_Session())
    if generation ~= nextGeneration then clear(); generation = nextGeneration end
    -- ClientPhase::Active; admission/baseline is handled by the SessionClient.
    if Game.CP2077Session_Phase() ~= 4 then clear(); return end
    if not Game.CP2077Session_Bind(Game.CP2077Session_SelfEntity(), player:GetEntityID()) then
        error("Local player projection binding rejected")
    end
    local system = Game.GetDynamicEntitySystem()
    if system == nil or not system:IsReady() then return end
    local seen = {}
    for index = 0, count - 1 do
        if Game.CP2077Session_Select(index) then
            local id = Game.CP2077Session_Player()
            local entity = Game.CP2077Session_Entity() -- keep Uint64 opaque; never tonumber()
            local x, y, z = Game.CP2077Session_X(), Game.CP2077Session_Y(), Game.CP2077Session_Z()
            local yaw = Game.CP2077Session_Yaw()
            seen[id] = true
            if not joined and Game.CP2077Session_Self() ~= Game.CP2077Session_Host() and id == Game.CP2077Session_Host() then
                Game.GetTeleportationFacility():Teleport(player, Vector4.new(x + 1.75, y, z, 1), EulerAngles.new(0, 0, math.deg(yaw)))
                -- Update the coherent local snapshot immediately after the baseline teleport.
                Game.CP2077Session_PushLocal(x + 1.75, y, z, yaw)
                joined = true
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
                -- Each render frame samples the shared interpolation buffer. This is not
                -- packet-triggered teleportation; extrapolation/snap policy lives in C++.
                Game.GetTeleportationFacility():Teleport(proxy, Vector4.new(x, y, z, 1), EulerAngles.new(0, 0, math.deg(yaw)))
            end
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
