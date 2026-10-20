-- Included only in the movement test package. Reads on CET's game-thread update.
local Recorder = require("recorder")
-- print() reaches only the CET console; spdlog writes this mod's own .log file.
local function emit(line)
    print(line)
    if spdlog then spdlog.info(line) end
end
local recorder = Recorder.new(emit)
local initialized = false
local captures = 0
local function startCapture(label, rateHz)
    -- Explicit operator action only. Never silently loop around the recorder's
    -- byte/frame limits. Each capture remains bounded, as does this CET load.
    if not initialized or type(label) ~= "string" or #label == 0 or #label > 48
        or label:find("[^%w_%-]") or captures >= 16
        or rateHz~=nil and rateHz~=5 and rateHz~=30 then return false end
    local clock = recorder.clock
    recorder = Recorder.new(emit,nil,rateHz)
    recorder.clock = clock
    captures = captures+1
    emit("[CP2077Movement] CAPTURE label="..label.." ordinal="..captures.." rate_hz="..recorder.rateHz.." max_bytes=8388608 max_frames=9000")
    return true
end
registerForEvent("onInit", function()
    initialized = true
    local ok, info = pcall(require, "build_info")
    emit("[CP2077Movement] BUILD "..(ok and info or "unpackaged_source"))
    emit("[CP2077Movement] START schema=1 rate_hz=5 max_bytes=8388608 max_frames=9000 target_yaw=radians actual_yaw=degrees")
end)
registerForEvent("onUpdate", function(delta)
    if not initialized then return end
    recorder:step(delta, function()
        local bridge = assert(GetMod("CP2077Coop"), "session mod not loaded")
        local retirements = bridge.playerRetirementDiagnostics()
        local count = 0
        for _ in pairs(retirements) do count=count+1 end
        local requests = Game.GetSystemRequestsHandler()
        local locomotionOk, locomotion = pcall(function()
            local player = Game.GetPlayer()
            if player and player:IsAttached() then
                return tostring(PlayerPuppet.GetCurrentLocomotionState(player))
            end
        end)
        local timeOk, focusActive, globalScale = pcall(function()
            local system = Game.GetTimeSystem()
            if not system then return end
            return system:IsTimeDilationActive(CName.new("focusMode")),
                system:GetActiveTimeDilation()
        end)
        if not timeOk then focusActive, globalScale = nil, nil end
        return {session=tostring(Game.CP2077Session_Session()),
            generation=tostring(Game.CP2077Session_Generation()),
            self=Game.CP2077Session_Self(), host=Game.CP2077Session_Host(),
            ready=Game.CP2077Session_Phase() == 4,
            paused=requests and requests:IsGamePaused(), retiring=count,
            localLocomotion=locomotionOk and locomotion or nil,
            focusDilation=focusActive, globalTimeScale=globalScale,
            players=bridge.playerDiagnostics()}
    end)
end)
return {startCapture=startCapture, captureStatus=function()
    return {initialized=initialized, stopped=recorder.stopped == true,
        frames=recorder.frames, bytes=recorder.bytes, captures=captures, rateHz=recorder.rateHz}
end}
