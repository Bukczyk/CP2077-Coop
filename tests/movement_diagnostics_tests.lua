local root=assert(arg[1])
package.path=root.."/runtime/session/diagnostics/CP2077MovementDiagnostics/?.lua;"..package.path
local R=require("recorder")
local lines, calls={},0
local r=R.new(function(s) lines[#lines+1]=s end)
local function capture()
    calls=calls+1
    return {session="9007199254740993ULL", generation="2ULL", self=3, host=2,
        paused=false,ready=true,retiring=1,players={
        ["2"]={actor="100ULL",x=10,actualX=9,error=1,mode="motor",fault="test\nforged"}}}
end
r:step(0,capture); r:step(0/0,capture); r:step(math.huge,capture)
assert(calls==0)
r:step(0.01,capture)
assert(calls==1 and #lines==2)
assert(lines[1]:find("session=9007199254740993ULL",1,true))
assert(lines[2]:find("actualX=9.000000",1,true))
assert(not lines[2]:find("\n",1,true))
r:step(0.01,capture); assert(calls==1)
r:step(10,capture); assert(calls==2) -- no backlog burst
r:step(1,function() error("engine unavailable") end)
assert(lines[#lines]:find("capture_unavailable",1,true))
r:step(1,capture); assert(calls==3) -- capture failure is isolated
local bounded={}
local small=R.new(function(s) bounded[#bounded+1]=s end,40)
small:step(1,capture); small:step(1,capture)
assert(small.stopped and #bounded==1 and bounded[1]:find("byte_limit",1,true))
local cap={}
local capped=R.new(function(s) cap[#cap+1]=s end)
capped:step(1,function()
    local p={}; for i=1,30 do p[tostring(i)]={x=0/0,actor={}} end
    return {players=p}
end)
assert(#cap==17 and cap[1]:find("remotes=30",1,true))
assert(cap[2]:find("x=invalid",1,true) and cap[2]:find("actor=na",1,true))
capped.frames=9000; capped:step(1,capture)
assert(capped.stopped and cap[#cap]:find("frame_limit",1,true))
-- Execute actual CET wrapper: module load/pre-init do not read engine state.
local events, reads={},0
registerForEvent=function(name,fn) events[name]=fn end
GetMod=function(name) assert(name=="CP2077Coop"); reads=reads+1
    return {playerDiagnostics=function() return {} end,
        playerRetirementDiagnostics=function() return {} end} end
Game={CP2077Session_Session=function() return "5ULL" end,
    CP2077Session_Generation=function() return "6ULL" end,
    CP2077Session_Self=function() return 2 end,CP2077Session_Host=function() return 1 end,
    CP2077Session_Phase=function() return 4 end,GetSystemRequestsHandler=function() return nil end}
local report=print
print=function(s) lines[#lines+1]=s end
assert(loadfile(root.."/runtime/session/diagnostics/CP2077MovementDiagnostics/init.lua"))()
events.onUpdate(1); assert(reads==0)
events.onInit(); events.onUpdate(1); assert(reads==1)
assert(lines[#lines]:find("session=5ULL",1,true))
print=report
print("movement diagnostics: bounded rate/size, capture failure, exact IDs and CET lifecycle passed")
