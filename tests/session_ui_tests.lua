local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local m=require("session_ui").new()
assert(m.state=="Load a save to connect" and not m.canReconnect)
local expected={[0]="Disconnected",[1]="Connecting",[2]="Joining session",[3]="Synchronizing",[4]="Connected",[5]="Connection failed"}
for phase=0,5 do
    m:update({loaded=true,phase=phase,player=3,host=2,session="9007199254740993ULL",remotes=8})
    assert(m.state==expected[phase])
    if phase==4 then assert(m.role=="JOINER" and m.remotes==8 and m.session=="9007199254740993ULL")
    else assert(not m.role and m.remotes==0 and not m.session) end
end
m:reconnect(); m:update({loaded=true,phase=1}); assert(m.state=="Reconnecting: Connecting")
m:update({loaded=true,phase=4,player=2,host=2,session=1,remotes=0}); assert(m.role=="HOST" and not m.reconnecting)
local lines,ended,reconnects={},0,0
local ui={Begin=function() return true end,Text=function(s) lines[#lines+1]=s end,
    End=function() ended=ended+1 end,Button=function() return true end}
m:draw(ui,function() reconnects=reconnects+1 end)
assert(ended==1 and reconnects==1 and lines[#lines]:find("Ping: unavailable",1,true))
m:update({loaded=true,error=true}); assert(m.state=="Game bridge stopped" and not m.role)
m:update({loaded=false}); m:draw(ui,function() reconnects=reconnects+1 end)
assert(reconnects==1 and not m.canReconnect)
ui.Begin=function() return false end; m:draw(ui,function() error("collapsed panel") end); assert(ended==3)
print("session_ui: phases, reconnect, unloaded/error cleanup and honest ping passed")
