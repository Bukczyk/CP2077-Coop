------------------------------------------------------------
-- CP2077 COOP
--
-- v0.0.26 VEHICLE SYNC
--
-- MANUAL ROLE FOR CURRENT TEST BUILD
-- HOST:   local IS_HOST = true
-- JOINER: local IS_HOST = false
--
-- ABSOLUTE WORLD COORDINATES
-- JOINER TELEPORT TO HOST
-- REMOTE AVATAR
-- WALK / SPRINT / IDLE
-- SIMPLE CLIENT-SIDE PREDICTION
------------------------------------------------------------


------------------------------------------------------------
-- CONFIG
------------------------------------------------------------

-- HOST uses true.
-- JOINER uses false.
local IS_HOST = true

local SEND_INTERVAL = 0.05

-- Jak często aktualizujemy cel AI.
-- 0.08 = 12.5 razy/s.
local COMMAND_INTERVAL = 0.08

-- Predykcja ruchu remote w sekundach.
local PREDICTION_TIME = 0.10

-- Jeżeli avatar odjedzie za daleko, robimy hard correction.
local TELEPORT_DISTANCE = 6.0

local MIN_TARGET_CHANGE = 0.04
local MOVEMENT_EPSILON = 0.02
local IDLE_DELAY = 0.25
local SPRINT_SPEED = 4.2

local ROTATE_INTERVAL = 0.10

-- P2 pojawia się z boku hosta, nie w środku jego postaci.
local JOIN_OFFSET = 1.75

-- Przez krótki czas ponawiamy teleport prawdziwego P2,
-- gdyby pierwszy został odrzucony podczas streamingu świata.
local JOIN_SYNC_INTERVAL = 0.25
local JOIN_SYNC_DURATION = 2.00
local JOIN_SYNC_TOLERANCE = 2.50

-- Po przejęciu Judy również wymuszamy jej właściwy world position.
local SPAWN_SNAP_INTERVAL = 0.10
local SPAWN_SNAP_DURATION = 1.50
local SPAWN_SNAP_TOLERANCE = 0.75

-- ============================================================
-- COMBAT SYNC v1
-- ============================================================
--
-- combat.reds sends a special packet through the existing
-- CP2077Coop_PushPlayerState native:
--
-- forwardY = 9999 -> this packet is a combat hit, NOT movement.
--
-- We match the hit to the nearest local NPC around the remote
-- target's absolute world position.
local COMBAT_MARKER_FORWARD_Y = 9999.0
local COMBAT_MARKER_TOLERANCE = 0.5

-- How far from the local player we ask TargetingSystem for NPCs.
local COMBAT_SCAN_RADIUS = 220.0

-- Maximum difference between the remote target position and
-- our local NPC position for considering them the same NPC.
local COMBAT_MATCH_RADIUS = 4.0

-- Defensive clamp against a broken/modded damage value.
local COMBAT_MAX_DAMAGE = 5000.0

-- MVP visible reaction. If the global ragdoll helper is not
-- exposed to CET on a given build, pcall makes this harmless.

local COMBAT_TRY_RAGDOLL = true


-- ============================================================
-- VEHICLE SYNC v1
-- ============================================================
--
-- We deliberately keep the already-stable CP1/RP1 transport.
--
-- While the local player is in a vehicle:
--
--   x/y/z    = vehicle world position
--   w        = -666.0
--   forwardX = vehicle yaw in degrees
--   forwardY = 8888.0
--
-- The existing native bridge does not need any new native
-- functions. On foot it still sends normal player state.
--
-- v1 syncs the tested vanilla Caliburn proxy.
-- Pitch/roll are intentionally not networked yet; yaw is enough
-- to prove real two-player vehicle transform sync.
local VEHICLE_MARKER_W = -666.0
local VEHICLE_MARKER_FORWARD_Y = 8888.0
local VEHICLE_MARKER_TOLERANCE = 0.5

local VEHICLE_PROXY_RECORD =
    "Vehicle.CP2077CoopProxyCaliburn"

-- Network state arrives at ~20 Hz. We render between snapshots.
local VEHICLE_INTERP_TIME = 0.055

-- Search radius used only while acquiring the spawned proxy.
local VEHICLE_PROXY_SEARCH_RADIUS = 250.0

-- When remote leaves the vehicle, keep the proxy for reuse but
-- move it far below the local world.
local VEHICLE_HIDE_DEPTH = 1000.0


------------------------------------------------------------
-- TIMERS
------------------------------------------------------------

local sendAccumulator = 0.0
local commandAccumulator = 0.0
local rotateAccumulator = 0.0
local idleTimer = 0.0

local spawnSnapPending = false
local spawnSnapElapsed = 0.0
local spawnSnapAccumulator = 0.0

local joinSyncPending = false
local joinSyncElapsed = 0.0
local joinSyncAccumulator = 0.0


------------------------------------------------------------
-- SESSION / NETWORK
------------------------------------------------------------

local syncActive = false

local rolePrinted = false
local lastRemoteSequence = -1


------------------------------------------------------------
-- REMOTE AVATAR
------------------------------------------------------------

local remoteInitialized = false
local remoteHandle = nil

local activeMoveCommand = nil

local remoteMoving = false
local movementType = "Walk"

local remoteForwardX = 0.0
local remoteForwardY = 1.0

local lastFacingX = nil
local lastFacingY = nil


------------------------------------------------------------
-- RAW NETWORK POSITION / VELOCITY
------------------------------------------------------------

local previousRemoteX = nil
local previousRemoteY = nil
local previousRemoteZ = nil

local remoteVelocityX = 0.0
local remoteVelocityY = 0.0
local remoteVelocityZ = 0.0


------------------------------------------------------------
-- ABSOLUTE WORLD TARGET
------------------------------------------------------------

local targetX = 0.0
local targetY = 0.0
local targetZ = 0.0

local lastCommandX = nil
local lastCommandY = nil
local lastCommandZ = nil


------------------------------------------------------------
-- JOINER WORLD SYNC
------------------------------------------------------------

local worldJoinComplete = false

local joinTargetX = 0.0
local joinTargetY = 0.0
local joinTargetZ = 0.0


------------------------------------------------------------
-- REMOTE VEHICLE
------------------------------------------------------------

local vehicleProxyId = nil
local vehicleProxyReady = false
local vehicleProxy = nil
local vehicleSpawnRequested = false

local remoteVehicleActive = false

local vehicleFromX = 0.0
local vehicleFromY = 0.0
local vehicleFromZ = 0.0
local vehicleFromYaw = 0.0

local vehicleTargetX = 0.0
local vehicleTargetY = 0.0
local vehicleTargetZ = 0.0
local vehicleTargetYaw = 0.0

local vehicleRenderYaw = 0.0
local vehicleInterp = 1.0

local vehicleMissingRecordPrinted = false


------------------------------------------------------------
-- MATH
------------------------------------------------------------

local function distance3(
    ax, ay, az,
    bx, by, bz
)
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz

    return math.sqrt(
        dx * dx +
        dy * dy +
        dz * dz
    )
end


local function distance2(
    ax, ay,
    bx, by
)
    local dx = ax - bx
    local dy = ay - by

    return math.sqrt(
        dx * dx +
        dy * dy
    )
end


local function lerp(
    a,
    b,
    t
)
    return a +
        (b - a) *
        t
end


local function normalizeYaw(
    yaw
)
    while yaw > 180.0 do
        yaw = yaw - 360.0
    end

    while yaw < -180.0 do
        yaw = yaw + 360.0
    end

    return yaw
end


local function lerpYaw(
    a,
    b,
    t
)
    local delta =
        normalizeYaw(
            b - a
        )

    return normalizeYaw(
        a +
        delta *
        t
    )
end


------------------------------------------------------------
-- GAME STATE
------------------------------------------------------------

local function isGameplayLoaded()

    local player = Game.GetPlayer()

    if player == nil then
        return false
    end

    if not player:IsAttached() then
        return false
    end

    local requests =
        Game.GetSystemRequestsHandler()

    if requests ~= nil
        and requests:IsPreGame()
    then
        return false
    end

    return true
end


------------------------------------------------------------
-- REMOTE ENTITY
------------------------------------------------------------

local function getRemoteHandle()

    local system =
        Game.GetDynamicEntitySystem()

    if system == nil then
        return nil
    end

    local entities =
        system:GetTagged(
            CName.new(
                "CP2077Coop.Remote"
            )
        )

    if entities == nil or #entities == 0 then
        return nil
    end

    return entities[1]
end


------------------------------------------------------------
-- CANCEL AI MOVE
------------------------------------------------------------

local function cancelMoveCommand()

    if remoteHandle == nil then
        activeMoveCommand = nil
        return
    end

    if activeMoveCommand == nil then
        return
    end

    local controller =
        remoteHandle:
            GetAIControllerComponent()

    if controller == nil then
        activeMoveCommand = nil
        return
    end

    pcall(function()

        controller:
            StopExecutingCommand(
                activeMoveCommand,
                true
            )

    end)

    pcall(function()

        controller:
            CancelCommand(
                activeMoveCommand
            )

    end)

    activeMoveCommand = nil
end


------------------------------------------------------------
-- REMOTE AI MOVE
------------------------------------------------------------

local function moveRemoteAI(
    x,
    y,
    z,
    moveType
)

    if remoteHandle == nil then
        return false
    end

    local controller =
        remoteHandle:
            GetAIControllerComponent()

    if controller == nil then
        return false
    end


    local destination =
        NewObject(
            "WorldPosition"
        )

    destination:SetVector4(
        destination,
        Vector4.new(
            x,
            y,
            z,
            1.0
        )
    )


    local positionSpec =
        NewObject(
            "AIPositionSpec"
        )

    positionSpec:SetWorldPosition(
        positionSpec,
        destination
    )


    local command =
        NewObject(
            "handle:AIMoveToCommand"
        )

    command.movementTarget =
        positionSpec

    command.rotateEntityTowardsFacingTarget =
        false

    command.ignoreNavigation =
        false

    command.desiredDistanceFromTarget =
        0.05

    command.movementType =
        moveType or "Walk"

    command.finishWhenDestinationReached =
        true

    command.alwaysUseStealth =
        false


    cancelMoveCommand()

    controller:
        SendCommand(command)

    activeMoveCommand = command

    return true
end


------------------------------------------------------------
-- ROTATE REMOTE WHILE IDLE
------------------------------------------------------------

local function rotateRemote(
    forwardX,
    forwardY
)

    if remoteHandle == nil then
        return
    end

    local controller =
        remoteHandle:
            GetAIControllerComponent()

    if controller == nil then
        return
    end

    local current =
        remoteHandle:
            GetWorldPosition()


    local facingPoint =
        Vector4.new(
            current.x + forwardX * 5.0,
            current.y + forwardY * 5.0,
            current.z,
            1.0
        )


    local destination =
        NewObject(
            "WorldPosition"
        )

    destination:SetVector4(
        destination,
        facingPoint
    )


    local positionSpec =
        NewObject(
            "AIPositionSpec"
        )

    positionSpec:SetWorldPosition(
        positionSpec,
        destination
    )


    local command =
        NewObject(
            "handle:AIRotateToCommand"
        )

    command.target =
        positionSpec

    command.angleOffset = 0
    command.angleTolerance = 3
    command.speed = 2

    controller:
        SendCommand(command)
end


------------------------------------------------------------
-- TELEPORT REMOTE AVATAR
------------------------------------------------------------

local function hardCorrectRemote(
    player,
    x,
    y,
    z
)

    cancelMoveCommand()

    player:
        CP2077Coop_MoveRemoteTest(
            x,
            y,
            z
        )
end


------------------------------------------------------------
-- TELEPORT REAL LOCAL PLAYER
------------------------------------------------------------

local function teleportLocalPlayer(
    player,
    x,
    y,
    z
)

    local ok, err =
        pcall(function()

            local position =
                Vector4.new(
                    x,
                    y,
                    z,
                    1.0
                )

            local orientation =
                player:
                    GetWorldOrientation()

            Game.GetTeleportationFacility():
                Teleport(
                    player,
                    position,
                    orientation
                )

        end)

    if not ok then

        print(
            "[CP2077Coop] PLAYER TELEPORT ERROR: "
            .. tostring(err)
        )

        return false
    end

    return true
end


------------------------------------------------------------
-- BEGIN P2 -> HOST WORLD SYNC
------------------------------------------------------------

local function beginJoinWorldSync(
    hostX,
    hostY,
    hostZ,
    hostForwardX,
    hostForwardY
)

    if worldJoinComplete
        or joinSyncPending
    then
        return
    end

    --------------------------------------------------------
    -- Perpendicular to host forward vector.
    -- Dzięki temu P2 ląduje ~1.75 m obok hosta.
    --------------------------------------------------------

    local sideX =
        -hostForwardY

    local sideY =
        hostForwardX


    local sideLength =
        math.sqrt(
            sideX * sideX +
            sideY * sideY
        )


    if sideLength < 0.001 then

        sideX = 1.0
        sideY = 0.0

    else

        sideX =
            sideX /
            sideLength

        sideY =
            sideY /
            sideLength
    end


    joinTargetX =
        hostX +
        sideX *
        JOIN_OFFSET

    joinTargetY =
        hostY +
        sideY *
        JOIN_OFFSET

    joinTargetZ =
        hostZ


    joinSyncPending = true
    joinSyncElapsed = 0.0

    -- Pierwsza próba od razu.
    joinSyncAccumulator =
        JOIN_SYNC_INTERVAL


    print(
        string.format(
            "[CP2077Coop] P2 WORLD SYNC -> %.2f %.2f %.2f",
            joinTargetX,
            joinTargetY,
            joinTargetZ
        )
    )
end


------------------------------------------------------------
-- COMBAT SYNC HELPERS
------------------------------------------------------------

local function isCombatPacket(
    forwardY
)
    return math.abs(
        forwardY -
        COMBAT_MARKER_FORWARD_Y
    ) <= COMBAT_MARKER_TOLERANCE
end


local function findNearestNPCAt(
    player,
    x,
    y,
    z
)

    local best = nil
    local bestDistance =
        COMBAT_MATCH_RADIUS +
        0.001


    local ok, err =
        pcall(function()

            local query =
                Game["TSQ_NPC;"]()

            query.maxDistance =
                COMBAT_SCAN_RADIUS


            -- Depending on the exposed overload/build, CET may
            -- return the array directly or as the second value.
            local first, second =
                Game.GetTargetingSystem():
                    GetTargetParts(
                        player,
                        query
                    )

            local parts =
                second or first

            if parts == nil then
                return
            end


            for _, part in ipairs(parts) do

                pcall(function()

                    local component =
                        part:GetComponent()

                    if component == nil then
                        return
                    end

                    local entity =
                        component:GetEntity()

                    if entity == nil then
                        return
                    end

                    if remoteHandle ~= nil
                        and entity == remoteHandle
                    then
                        return
                    end

                    if not entity:IsNPC() then
                        return
                    end

                    if entity:IsDead() then
                        return
                    end


                    local pos =
                        entity:
                            GetWorldPosition()


                    local d =
                        distance3(
                            pos.x,
                            pos.y,
                            pos.z,

                            x,
                            y,
                            z
                        )


                    if d < bestDistance then

                        bestDistance = d
                        best = entity
                    end
                end)
            end

        end)


    if not ok then

        print(
            "[CP2077Coop] COMBAT scan error: "
            .. tostring(err)
        )

        return nil, nil
    end


    return best, bestDistance
end


local function tryRemoteHitReaction(
    target
)

    if not COMBAT_TRY_RAGDOLL then
        return
    end


    -- Verified redscript has CreateForceRagdollEvent().
    -- CET exposure varies, so this is intentionally best-effort.
    pcall(function()

        local event =
            Game.CreateForceRagdollEvent(
                CName.new(
                    "CP2077Coop Remote Hit"
                )
            )

        if event ~= nil then
            target:QueueEvent(event)
        end

    end)
end


local function applyRemoteCombatHit(
    player,
    hitX,
    hitY,
    hitZ,
    rawDamage
)

    local damage =
        math.max(
            0.0,
            math.min(
                rawDamage,
                COMBAT_MAX_DAMAGE
            )
        )


    if damage <= 0.0 then
        return
    end


    local target, targetDistance =
        findNearestNPCAt(
            player,
            hitX,
            hitY,
            hitZ
        )


    if target == nil then

        print(
            string.format(
                "[CP2077Coop] COMBAT HIT no NPC match @ %.2f %.2f %.2f dmg=%.2f",
                hitX,
                hitY,
                hitZ,
                damage
            )
        )

        return
    end


    local applied = false


    local ok, err =
        pcall(function()

            if Game.GetGodModeSystem():
                HasGodMode(
                    target:GetEntityID(),
                    gameGodModeType.Invulnerable
                )
            then
                return
            end


            Game.GetStatPoolsSystem():
                RequestChangingStatPoolValue(
                    target:GetEntityID(),
                    "Health",
                    -damage,
                    player,
                    true,
                    false
                )


            applied = true

        end)


    if not ok then

        print(
            "[CP2077Coop] COMBAT damage error: "
            .. tostring(err)
        )

        return
    end


    if not applied then

        print(
            "[CP2077Coop] COMBAT target invulnerable"
        )

        return
    end


    tryRemoteHitReaction(
        target
    )


    print(
        string.format(
            "[CP2077Coop] COMBAT HIT applied dmg=%.2f match=%.2fm",
            damage,
            targetDistance or -1.0
        )
    )
end


------------------------------------------------------------
-- VEHICLE SYNC HELPERS
------------------------------------------------------------

local function isVehiclePacket(
    forwardY
)
    return math.abs(
        forwardY -
        VEHICLE_MARKER_FORWARD_Y
    ) <= VEHICLE_MARKER_TOLERANCE
end


local function sameTweakId(
    a,
    b
)
    if a == nil or b == nil then
        return false
    end

    return tostring(a) ==
        tostring(b)
end


local function prepareVehicleProxyRecord()

    local ok, err =
        pcall(function()

            vehicleProxyId =
                TweakDBID.new(
                    VEHICLE_PROXY_RECORD
                )

            if vehicleProxyId == nil then
                error(
                    "TweakDBID.new returned nil"
                )
            end


            local record =
                TweakDB:GetRecord(
                    vehicleProxyId
                )

            if record == nil then
                error(
                    "Vehicle.CP2077CoopProxyCaliburn missing - check r6/tweaks/CP2077Coop/vehicle_proxy.yaml"
                )
            end


            vehicleProxyReady = true

        end)


    if ok then

        print(
            "[CP2077Coop] VEHICLE proxy record READY"
        )

        return true
    end


    vehicleProxyReady = false

    print(
        "[CP2077Coop] VEHICLE proxy record ERROR: "
        .. tostring(err)
    )

    return false
end


local function vehicleEntityRecordId(
    entity
)
    if entity == nil then
        return nil
    end


    local ok, result =
        pcall(function()

            return entity:
                GetRecordID()

        end)


    if not ok then
        return nil
    end


    return result
end


local function findVehicleProxy(
    player
)

    if vehicleProxyId == nil then
        return nil
    end


    local best = nil
    local bestDistance =
        999999.0


    local playerPos =
        player:
            GetWorldPosition()


    local ok, err =
        pcall(function()

            local query =
                Game["TSQ_ALL;"]()

            query.maxDistance =
                VEHICLE_PROXY_SEARCH_RADIUS


            local first, second =
                Game.GetTargetingSystem():
                    GetTargetParts(
                        player,
                        query
                    )


            local parts = nil

            if type(second) ==
                "table"
            then

                parts = second

            elseif type(first) ==
                "table"
            then

                parts = first
            end


            if parts == nil then
                return
            end


            for _, part in ipairs(parts) do

                pcall(function()

                    local component =
                        part:
                            GetComponent()

                    if component == nil then
                        return
                    end


                    local entity =
                        component:
                            GetEntity()

                    if entity == nil then
                        return
                    end


                    local recordId =
                        vehicleEntityRecordId(
                            entity
                        )


                    if not sameTweakId(
                        recordId,
                        vehicleProxyId
                    )
                    then
                        return
                    end


                    local pos =
                        entity:
                            GetWorldPosition()


                    local d =
                        distance3(
                            pos.x,
                            pos.y,
                            pos.z,

                            playerPos.x,
                            playerPos.y,
                            playerPos.z
                        )


                    if d <
                        bestDistance
                    then

                        bestDistance = d
                        best = entity
                    end

                end)
            end

        end)


    if not ok then

        print(
            "[CP2077Coop] VEHICLE proxy scan ERROR: "
            .. tostring(err)
        )

        return nil
    end


    return best
end


local function requestVehicleProxySpawn()

    if not vehicleProxyReady
        or vehicleProxyId == nil
    then

        if not vehicleMissingRecordPrinted then

            vehicleMissingRecordPrinted =
                true

            print(
                "[CP2077Coop] VEHICLE proxy not ready"
            )
        end

        return false
    end


    local ok, err =
        pcall(function()

            Game.GetVehicleSystem():
                SpawnPlayerVehicle(
                    vehicleProxyId
                )

        end)


    if not ok then

        print(
            "[CP2077Coop] VEHICLE spawn ERROR: "
            .. tostring(err)
        )

        return false
    end


    vehicleSpawnRequested = true

    print(
        "[CP2077Coop] VEHICLE proxy spawn requested"
    )

    return true
end


local function hideVehicleProxy(
    player
)
    if vehicleProxy == nil
        or player == nil
    then
        return
    end


    pcall(function()

        local pos =
            player:
                GetWorldPosition()

        local hidden =
            Vector4.new(
                pos.x,
                pos.y,
                pos.z -
                    VEHICLE_HIDE_DEPTH,
                1.0
            )

        Game.GetTeleportationFacility():
            Teleport(
                vehicleProxy,
                hidden,
                EulerAngles.new(
                    0.0,
                    0.0,
                    0.0
                )
            )

    end)
end


local function hideRemoteAvatarForVehicle(
    player
)
    if remoteHandle == nil then
        return
    end


    hardCorrectRemote(
        player,

        vehicleTargetX,
        vehicleTargetY,
        vehicleTargetZ -
            VEHICLE_HIDE_DEPTH
    )
end


local function beginRemoteVehicleState(
    player,
    x,
    y,
    z,
    yaw
)

    yaw =
        normalizeYaw(
            yaw
        )


    if not remoteVehicleActive then

        remoteVehicleActive =
            true


        vehicleFromX = x
        vehicleFromY = y
        vehicleFromZ = z
        vehicleFromYaw = yaw

        vehicleTargetX = x
        vehicleTargetY = y
        vehicleTargetZ = z
        vehicleTargetYaw = yaw

        vehicleRenderYaw = yaw
        vehicleInterp = 1.0


        hideRemoteAvatarForVehicle(
            player
        )


        print(
            string.format(
                "[CP2077Coop] VEHICLE remote ENTER @ %.2f %.2f %.2f yaw=%.1f",
                x,
                y,
                z,
                yaw
            )
        )

        return
    end


    --------------------------------------------------------
    -- Start interpolation from the actually rendered proxy
    -- position, not from the previous network packet.
    --------------------------------------------------------

    if vehicleProxy ~= nil then

        local current =
            vehicleProxy:
                GetWorldPosition()

        vehicleFromX =
            current.x

        vehicleFromY =
            current.y

        vehicleFromZ =
            current.z

    else

        vehicleFromX =
            vehicleTargetX

        vehicleFromY =
            vehicleTargetY

        vehicleFromZ =
            vehicleTargetZ
    end


    vehicleFromYaw =
        vehicleRenderYaw

    vehicleTargetX = x
    vehicleTargetY = y
    vehicleTargetZ = z
    vehicleTargetYaw = yaw

    vehicleInterp = 0.0
end


local function endRemoteVehicleState(
    player
)

    if not remoteVehicleActive then
        return
    end


    remoteVehicleActive =
        false

    hideVehicleProxy(
        player
    )


    print(
        "[CP2077Coop] VEHICLE remote EXIT"
    )
end


local function updateRemoteVehicleProxy(
    player,
    delta
)

    if not remoteVehicleActive then
        return false
    end


    --------------------------------------------------------
    -- Spawn once. We keep the same proxy underground after
    -- EXIT so later entries can reuse it.
    --------------------------------------------------------

    if vehicleProxy == nil then

        vehicleProxy =
            findVehicleProxy(
                player
            )


        if vehicleProxy == nil
            and not vehicleSpawnRequested
        then

            requestVehicleProxySpawn()

            return true
        end


        if vehicleProxy == nil then
            return true
        end


        print(
            "[CP2077Coop] VEHICLE proxy acquired"
        )
    end


    --------------------------------------------------------
    -- Smooth between incoming ~20 Hz snapshots.
    --------------------------------------------------------

    vehicleInterp =
        math.min(
            1.0,
            vehicleInterp +
            delta /
            VEHICLE_INTERP_TIME
        )


    local x =
        lerp(
            vehicleFromX,
            vehicleTargetX,
            vehicleInterp
        )

    local y =
        lerp(
            vehicleFromY,
            vehicleTargetY,
            vehicleInterp
        )

    local z =
        lerp(
            vehicleFromZ,
            vehicleTargetZ,
            vehicleInterp
        )

    local yaw =
        lerpYaw(
            vehicleFromYaw,
            vehicleTargetYaw,
            vehicleInterp
        )


    vehicleRenderYaw = yaw


    local ok, err =
        pcall(function()

            Game.GetTeleportationFacility():
                Teleport(
                    vehicleProxy,

                    Vector4.new(
                        x,
                        y,
                        z,
                        1.0
                    ),

                    EulerAngles.new(
                        0.0,
                        0.0,
                        yaw
                    )
                )

        end)


    if not ok then

        print(
            "[CP2077Coop] VEHICLE transform ERROR: "
            .. tostring(err)
        )
    end


    return true
end


------------------------------------------------------------
-- RESET LOCAL SCRIPT SESSION
------------------------------------------------------------

local function resetRemote()

    cancelMoveCommand()

    local resetPlayer =
        Game.GetPlayer()

    if resetPlayer ~= nil then
        hideVehicleProxy(
            resetPlayer
        )
    end

    remoteInitialized = false
    remoteHandle = nil

    lastRemoteSequence = -1

    previousRemoteX = nil
    previousRemoteY = nil
    previousRemoteZ = nil

    remoteVelocityX = 0.0
    remoteVelocityY = 0.0
    remoteVelocityZ = 0.0

    targetX = 0.0
    targetY = 0.0
    targetZ = 0.0

    remoteForwardX = 0.0
    remoteForwardY = 1.0

    lastFacingX = nil
    lastFacingY = nil

    remoteMoving = false
    movementType = "Walk"

    idleTimer = 0.0

    lastCommandX = nil
    lastCommandY = nil
    lastCommandZ = nil

    spawnSnapPending = false
    spawnSnapElapsed = 0.0
    spawnSnapAccumulator = 0.0

    joinSyncPending = false
    joinSyncElapsed = 0.0
    joinSyncAccumulator = 0.0

    worldJoinComplete = IS_HOST

    joinTargetX = 0.0
    joinTargetY = 0.0
    joinTargetZ = 0.0

    sendAccumulator = 0.0
    commandAccumulator = 0.0
    rotateAccumulator = 0.0

    rolePrinted = false

    remoteVehicleActive = false

    vehicleFromX = 0.0
    vehicleFromY = 0.0
    vehicleFromZ = 0.0
    vehicleFromYaw = 0.0

    vehicleTargetX = 0.0
    vehicleTargetY = 0.0
    vehicleTargetZ = 0.0
    vehicleTargetYaw = 0.0

    vehicleRenderYaw = 0.0
    vehicleInterp = 1.0
end


------------------------------------------------------------
-- INIT
------------------------------------------------------------

registerForEvent(
    "onInit",
    function()

        print(
            "[CP2077Coop] client v0.0.26 VEHICLE SYNC loaded"
        )

        prepareVehicleProxyRecord()

    end
)


------------------------------------------------------------
-- UPDATE
------------------------------------------------------------

registerForEvent(
    "onUpdate",
    function(delta)


        ----------------------------------------------------
        -- GAMEPLAY STATE
        ----------------------------------------------------

        local loaded =
            isGameplayLoaded()


        if loaded ~= syncActive then

            syncActive = loaded


            if syncActive then

                print(
                    "[CP2077Coop] sync ON"
                )

                resetRemote()

            else

                print(
                    "[CP2077Coop] sync OFF"
                )

                resetRemote()

            end
        end


        if not syncActive then
            return
        end


        local player =
            Game.GetPlayer()

        if player == nil then
            return
        end


        ----------------------------------------------------
        -- ROLE
        ----------------------------------------------------

        if not rolePrinted then

            rolePrinted = true

            if IS_HOST then

                print(
                    "[CP2077Coop] ROLE = HOST"
                )

            else

                print(
                    "[CP2077Coop] ROLE = JOINER"
                )
            end
        end


        ----------------------------------------------------
        -- LOCAL PLAYER / VEHICLE -> VPS
        ----------------------------------------------------

        sendAccumulator =
            sendAccumulator +
            delta


        if sendAccumulator >=
            SEND_INTERVAL
        then

            sendAccumulator =
                sendAccumulator -
                SEND_INTERVAL


            local localVehicle = nil


            pcall(function()

                local qm =
                    player:
                        GetQuickSlotsManager()

                if qm ~= nil then

                    localVehicle =
                        qm:
                            GetVehicleObject()
                end

            end)


            if localVehicle ~= nil then

                ------------------------------------------------
                -- VEHICLE STATE
                ------------------------------------------------

                local pos =
                    localVehicle:
                        GetWorldPosition()


                local angles =
                    localVehicle:
                        GetWorldOrientation():
                        ToEulerAngles()


                Game.CP2077Coop_PushPlayerState(
                    pos.x,
                    pos.y,
                    pos.z,

                    VEHICLE_MARKER_W,

                    angles.yaw,
                    VEHICLE_MARKER_FORWARD_Y
                )


            else

                ------------------------------------------------
                -- ON-FOOT PLAYER STATE
                ------------------------------------------------

                local pos =
                    player:
                        GetWorldPosition()


                local forward =
                    player:
                        GetWorldForward()


                Game.CP2077Coop_PushPlayerState(
                    pos.x,
                    pos.y,
                    pos.z,
                    pos.w,
                    forward.x,
                    forward.y
                )
            end
        end


        ----------------------------------------------------
        -- NO FRESH REMOTE DATA
        ----------------------------------------------------

        if not Game.CP2077Coop_HasRemotePlayer() then
            return
        end


        ----------------------------------------------------
        -- NEW REMOTE NETWORK STATE
        ----------------------------------------------------

        local sequence =
            Game.CP2077Coop_GetRemoteSequence()


        if sequence ~=
            lastRemoteSequence
        then

            local previousSequence =
                lastRemoteSequence

            lastRemoteSequence =
                sequence


            local rx =
                Game.CP2077Coop_GetRemoteX()

            local ry =
                Game.CP2077Coop_GetRemoteY()

            local rz =
                Game.CP2077Coop_GetRemoteZ()


            remoteForwardX =
                Game.CP2077Coop_GetRemoteForwardX()

            remoteForwardY =
                Game.CP2077Coop_GetRemoteForwardY()


            ------------------------------------------------
            -- COMBAT EVENT
            --
            -- IMPORTANT:
            -- Do not feed hit X/Y/Z into the player movement
            -- interpolator. They are the target NPC coordinates.
            ------------------------------------------------

            if isCombatPacket(
                remoteForwardY
            ) then

                applyRemoteCombatHit(
                    player,
                    rx,
                    ry,
                    rz,
                    remoteForwardX
                )

                return
            end


            ------------------------------------------------
            -- VEHICLE EVENT
            --
            -- IMPORTANT FOR FIRST TEST:
            -- establish normal HOST/JOINER world sync on foot
            -- before either player enters a vehicle.
            ------------------------------------------------

            if isVehiclePacket(
                remoteForwardY
            ) then

                beginRemoteVehicleState(
                    player,
                    rx,
                    ry,
                    rz,
                    remoteForwardX
                )

                return
            end


            ------------------------------------------------
            -- NORMAL PACKET AFTER VEHICLE = REMOTE EXIT
            ------------------------------------------------

            if remoteVehicleActive then

                endRemoteVehicleState(
                    player
                )


                -- If Judy already existed before the drive,
                -- bring her back immediately near the remote
                -- player's first on-foot packet.
                if remoteHandle ~= nil then

                    hardCorrectRemote(
                        player,
                        rx,
                        ry,
                        rz
                    )
                end
            end


            ------------------------------------------------
            -- P2 JOINS P1 WORLD
            ------------------------------------------------

            if not IS_HOST
                and not worldJoinComplete
                and not joinSyncPending
            then

                beginJoinWorldSync(
                    rx,
                    ry,
                    rz,
                    remoteForwardX,
                    remoteForwardY
                )
            end


            ------------------------------------------------
            -- MOVEMENT / VELOCITY
            ------------------------------------------------

            if previousRemoteX ~= nil then

                local sequenceDelta =
                    sequence -
                    previousSequence

                if sequenceDelta <= 0 then
                    sequenceDelta = 1
                end

                local packetTime =
                    SEND_INTERVAL *
                    sequenceDelta

                packetTime =
                    math.max(
                        packetTime,
                        0.001
                    )


                local dx =
                    rx -
                    previousRemoteX

                local dy =
                    ry -
                    previousRemoteY

                local dz =
                    rz -
                    previousRemoteZ


                local packetDistance =
                    math.sqrt(
                        dx * dx +
                        dy * dy +
                        dz * dz
                    )


                local speed =
                    packetDistance /
                    packetTime


                if packetDistance >
                    MOVEMENT_EPSILON
                then

                    remoteMoving = true
                    idleTimer = 0.0

                    remoteVelocityX =
                        dx /
                        packetTime

                    remoteVelocityY =
                        dy /
                        packetTime

                    remoteVelocityZ =
                        dz /
                        packetTime


                    if speed >=
                        SPRINT_SPEED
                    then

                        movementType =
                            "Sprint"

                    else

                        movementType =
                            "Walk"

                    end

                else

                    idleTimer =
                        idleTimer +
                        packetTime

                    remoteVelocityX = 0.0
                    remoteVelocityY = 0.0
                    remoteVelocityZ = 0.0

                    if idleTimer >=
                        IDLE_DELAY
                    then

                        remoteMoving = false
                    end
                end

            else

                remoteVelocityX = 0.0
                remoteVelocityY = 0.0
                remoteVelocityZ = 0.0
            end


            previousRemoteX = rx
            previousRemoteY = ry
            previousRemoteZ = rz


            ------------------------------------------------
            -- ABSOLUTE WORLD SYNC
            --
            -- Koniec relative origin.
            -- Remote używa tych samych world coordinates.
            ------------------------------------------------

            if remoteMoving then

                targetX =
                    rx +
                    remoteVelocityX *
                    PREDICTION_TIME

                targetY =
                    ry +
                    remoteVelocityY *
                    PREDICTION_TIME

                -- Nie przewidujemy Z, żeby nie podbijać NPC
                -- na schodach / spadkach.
                targetZ =
                    rz

            else

                targetX = rx
                targetY = ry
                targetZ = rz
            end


            ------------------------------------------------
            -- SPAWN REMOTE AVATAR ON FIRST PACKET
            ------------------------------------------------

            if not remoteInitialized then

                player:
                    CP2077Coop_SpawnRemoteTest()

                remoteInitialized = true

                print(
                    string.format(
                        "[CP2077Coop] remote spawn requested @ %.2f %.2f %.2f",
                        targetX,
                        targetY,
                        targetZ
                    )
                )
            end
        end


        ----------------------------------------------------
        -- P2 REAL PLAYER WORLD-SYNC TELEPORT
        ----------------------------------------------------

        if joinSyncPending then

            joinSyncElapsed =
                joinSyncElapsed +
                delta

            joinSyncAccumulator =
                joinSyncAccumulator +
                delta


            if joinSyncAccumulator >=
                JOIN_SYNC_INTERVAL
            then

                joinSyncAccumulator = 0.0

                teleportLocalPlayer(
                    player,
                    joinTargetX,
                    joinTargetY,
                    joinTargetZ
                )
            end


            local playerPos =
                player:
                    GetWorldPosition()


            local joinError =
                distance3(
                    playerPos.x,
                    playerPos.y,
                    playerPos.z,

                    joinTargetX,
                    joinTargetY,
                    joinTargetZ
                )


            if joinError <=
                JOIN_SYNC_TOLERANCE
            then

                joinSyncPending = false
                worldJoinComplete = true

                print(
                    string.format(
                        "[CP2077Coop] WORLD SYNC OK error=%.2f",
                        joinError
                    )
                )

            elseif joinSyncElapsed >=
                JOIN_SYNC_DURATION
            then

                joinSyncPending = false

                print(
                    string.format(
                        "[CP2077Coop] WORLD SYNC FAILED error=%.2f",
                        joinError
                    )
                )
            end

            -- W tym ticku nie ruszamy jeszcze remote AI.
            return
        end


        ----------------------------------------------------
        -- REMOTE VEHICLE RUNTIME
        ----------------------------------------------------

        if remoteVehicleActive then

            updateRemoteVehicleProxy(
                player,
                delta
            )

            -- Do not run Judy AI while the remote player is driving.
            return
        end


        ----------------------------------------------------
        -- WAIT FOR REMOTE NPC HANDLE
        ----------------------------------------------------

        if remoteInitialized
            and remoteHandle == nil
        then

            remoteHandle =
                getRemoteHandle()


            if remoteHandle ~= nil then

                print(
                    "[CP2077Coop] remote entity acquired"
                )

                local playerPos =
                    player:
                        GetWorldPosition()

                local remotePos =
                    remoteHandle:
                        GetWorldPosition()


                print(
                    string.format(
                        "[CP2077Coop] LOCAL %.2f %.2f %.2f",
                        playerPos.x,
                        playerPos.y,
                        playerPos.z
                    )
                )

                print(
                    string.format(
                        "[CP2077Coop] REMOTE TARGET %.2f %.2f %.2f",
                        targetX,
                        targetY,
                        targetZ
                    )
                )

                print(
                    string.format(
                        "[CP2077Coop] JUDY BEFORE SNAP %.2f %.2f %.2f",
                        remotePos.x,
                        remotePos.y,
                        remotePos.z
                    )
                )


                spawnSnapPending = true
                spawnSnapElapsed = 0.0
                spawnSnapAccumulator =
                    SPAWN_SNAP_INTERVAL


                lastCommandX = targetX
                lastCommandY = targetY
                lastCommandZ = targetZ
            end
        end


        if remoteHandle == nil then
            return
        end


        ----------------------------------------------------
        -- FORCE INITIAL REMOTE POSITION
        ----------------------------------------------------

        if spawnSnapPending then

            spawnSnapElapsed =
                spawnSnapElapsed +
                delta

            spawnSnapAccumulator =
                spawnSnapAccumulator +
                delta


            if spawnSnapAccumulator >=
                SPAWN_SNAP_INTERVAL
            then

                spawnSnapAccumulator = 0.0

                hardCorrectRemote(
                    player,
                    targetX,
                    targetY,
                    targetZ
                )
            end


            local snapPos =
                remoteHandle:
                    GetWorldPosition()


            local snapError =
                distance3(
                    snapPos.x,
                    snapPos.y,
                    snapPos.z,

                    targetX,
                    targetY,
                    targetZ
                )


            if snapError <=
                SPAWN_SNAP_TOLERANCE
            then

                spawnSnapPending = false

                print(
                    string.format(
                        "[CP2077Coop] REMOTE SNAP OK error=%.2f",
                        snapError
                    )
                )

            elseif spawnSnapElapsed >=
                SPAWN_SNAP_DURATION
            then

                spawnSnapPending = false

                print(
                    string.format(
                        "[CP2077Coop] REMOTE SNAP FAILED error=%.2f target=%.2f %.2f %.2f",
                        snapError,
                        targetX,
                        targetY,
                        targetZ
                    )
                )
            end

            return
        end


        ----------------------------------------------------
        -- REMOTE POSITION ERROR
        ----------------------------------------------------

        local current =
            remoteHandle:
                GetWorldPosition()


        local errorDistance =
            distance3(
                current.x,
                current.y,
                current.z,

                targetX,
                targetY,
                targetZ
            )


        ----------------------------------------------------
        -- LARGE DESYNC
        ----------------------------------------------------

        if errorDistance >=
            TELEPORT_DISTANCE
        then

            hardCorrectRemote(
                player,
                targetX,
                targetY,
                targetZ
            )

            lastCommandX = targetX
            lastCommandY = targetY
            lastCommandZ = targetZ

            return
        end


        ----------------------------------------------------
        -- REMOTE MOVING
        ----------------------------------------------------

        if remoteMoving then

            commandAccumulator =
                commandAccumulator +
                delta


            if commandAccumulator >=
                COMMAND_INTERVAL
            then

                commandAccumulator = 0.0


                local targetChanged =
                    distance3(
                        targetX,
                        targetY,
                        targetZ,

                        lastCommandX,
                        lastCommandY,
                        lastCommandZ
                    )


                if targetChanged >=
                    MIN_TARGET_CHANGE
                then

                    if moveRemoteAI(
                        targetX,
                        targetY,
                        targetZ,
                        movementType
                    ) then

                        lastCommandX = targetX
                        lastCommandY = targetY
                        lastCommandZ = targetZ
                    end
                end
            end


        ----------------------------------------------------
        -- REMOTE IDLE
        ----------------------------------------------------

        else

            commandAccumulator = 0.0

            rotateAccumulator =
                rotateAccumulator +
                delta


            if rotateAccumulator >=
                ROTATE_INTERVAL
            then

                rotateAccumulator = 0.0

                local facingChanged = 999.0


                if lastFacingX ~= nil then

                    facingChanged =
                        distance2(
                            remoteForwardX,
                            remoteForwardY,
                            lastFacingX,
                            lastFacingY
                        )
                end


                if facingChanged > 0.03 then

                    cancelMoveCommand()

                    rotateRemote(
                        remoteForwardX,
                        remoteForwardY
                    )

                    lastFacingX =
                        remoteForwardX

                    lastFacingY =
                        remoteForwardY
                end
            end
        end
    end
)
