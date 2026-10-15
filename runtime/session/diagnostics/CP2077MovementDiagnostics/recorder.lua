-- Read-only, bounded sampling. No game objects, setters, networking or input.
local Recorder = {}
Recorder.__index = Recorder
local function value(v)
    if type(v) == "number" then
        if v ~= v or math.abs(v) == math.huge then return "invalid" end
        return string.format("%.6f", v)
    end
    if type(v) == "boolean" then return tostring(v) end
    if type(v) ~= "string" then return "na" end
    return v:sub(1, 96):gsub("[^%w_%.:%-]", "_")
end
local fields = {"entity", "actor", "mode", "lifecycle", "fault", "motorLastFailure",
    "x", "y", "z", "yaw", "actualX", "actualY", "actualZ", "actualYawDegrees",
    "readback", "error", "speed", "gait", "commands", "snaps", "observedSnaps",
    "turns", "commandKind", "commandState", "commandAge"}
function Recorder.new(emit, maxBytes)
    return setmetatable({emit=emit, maxBytes=maxBytes or 8*1024*1024,
        bytes=0, clock=0, due=0, frames=0}, Recorder)
end
function Recorder:write(line)
    if self.stopped then return end
    if self.bytes+#line+1 > self.maxBytes then
        self.stopped = true
        self.emit("[CP2077Movement] STOP reason=byte_limit")
        return
    end
    self.bytes = self.bytes+#line+1
    self.emit(line)
end
function Recorder:step(delta, capture)
    if self.stopped or type(delta) ~= "number" or delta ~= delta or delta <= 0 or delta == math.huge then return end
    self.clock = self.clock+delta
    if self.clock < self.due then return end
    self.due = self.clock+0.2 -- 5 Hz, never catch up in a burst after a pause.
    if self.frames >= 9000 then
        self:write("[CP2077Movement] STOP reason=frame_limit")
        self.stopped = true
        return
    end
    self.frames = self.frames+1
    local ok, f = pcall(capture)
    if not ok or type(f) ~= "table" then
        self:write("[CP2077Movement] ERROR capture_unavailable")
        return
    end
    local prefix = "[CP2077Movement] t="..value(self.clock).." frame="..self.frames
    local count, ids = 0, {}
    for id in pairs(f.players or {}) do count=count+1; ids[#ids+1]=id end
    table.sort(ids)
    self:write(prefix.." session="..value(f.session).." generation="..value(f.generation)
        .." self="..value(f.self).." host="..value(f.host).." ready="..value(f.ready)
        .." paused="..value(f.paused).." remotes="..count.." retiring="..value(f.retiring))
    -- Sampling cap only, not a gameplay/player-capacity limit.
    for i=1,math.min(#ids,16) do
        local id, parts = ids[i], {prefix, "player="..value(ids[i])}
        local p = f.players[id]
        for _, key in ipairs(fields) do parts[#parts+1]=key.."="..value(p[key]) end
        self:write(table.concat(parts," "))
    end
end
return Recorder
