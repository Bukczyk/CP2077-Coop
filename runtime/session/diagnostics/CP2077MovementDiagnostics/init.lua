-- Included only in the movement test package. Reads on CET's game-thread update.
local Recorder = require("recorder")
local recorder = Recorder.new(print)
local initialized = false
registerForEvent("onInit", function()
    initialized = true
    local ok, info = pcall(require, "build_info")
    print("[CP2077Movement] BUILD "..(ok and info or "unpackaged_source"))
    print("[CP2077Movement] START schema=1 rate_hz=5 max_bytes=8388608 max_frames=9000 target_yaw=radians actual_yaw=degrees")
end)
registerForEvent("onUpdate", function(delta)
    if not initialized then return end
    recorder:step(delta, function()
        local bridge = assert(GetMod("CP2077Coop"), "session mod not loaded")
        local retirements = bridge.playerRetirementDiagnostics()
        local count = 0
        for _ in pairs(retirements) do count=count+1 end
        local requests = Game.GetSystemRequestsHandler()
        return {session=tostring(Game.CP2077Session_Session()),
            generation=tostring(Game.CP2077Session_Generation()),
            self=Game.CP2077Session_Self(), host=Game.CP2077Session_Host(),
            ready=Game.CP2077Session_Phase() == 4,
            paused=requests and requests:IsGamePaused(), retiring=count,
            players=bridge.playerDiagnostics()}
    end)
end)
