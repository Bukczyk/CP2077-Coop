-- Value-only view model and CET overlay. No fabricated RTT or network timing.
local M={}; M.__index=M
local phases={[0]="Disconnected",[1]="Connecting",[2]="Joining session",[3]="Synchronizing",[4]="Connected",[5]="Connection failed"}
function M.new() return setmetatable({state="Load a save to connect",remotes=0,canReconnect=false},M) end
function M:reconnect() self.reconnecting=true; self.state="Reconnecting" end
function M:update(frame)
    self.canReconnect=frame.loaded==true
    self.remotes=0; self.session=nil; self.player=nil; self.role=nil
    if frame.error then self.state="Game bridge stopped"; return end
    if not frame.loaded then self.state="Load a save to connect"; self.reconnecting=false; return end
    self.state=phases[frame.phase] or "Unknown connection state"
    if self.reconnecting and frame.phase~=4 and frame.phase~=5 then self.state="Reconnecting: "..self.state end
    if frame.phase==4 then
        self.reconnecting=false
        self.session=tostring(frame.session); self.player=frame.player
        self.role=frame.player==frame.host and "HOST" or "JOINER"
        self.remotes=math.max(0,frame.remotes or 0)
    elseif frame.phase==5 then self.reconnecting=false end
end
function M:draw(ui,onReconnect)
    local expanded=ui.Begin("CP2077 Co-op session")
    if expanded then
        ui.Text(self.state)
        if self.role then
            ui.Text(self.role.." | Player "..tostring(self.player).." | Session "..self.session)
            ui.Text("Remote player snapshots: "..tostring(self.remotes))
        end
        ui.Text("Ping: unavailable from current game bridge")
        if self.canReconnect and ui.Button("Reconnect session") then onReconnect() end
    end
    ui.End()
end
return M
