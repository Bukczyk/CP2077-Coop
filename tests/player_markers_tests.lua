local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local Markers=require("player_markers")
local visible, updates, removals={},0,0
local failRemove, failUpdate=false,false
local owner={}
function owner:GetEntityID() return {hash="9007199254740999ULL"} end
function owner:CP2077Session_ClearPlayerMarkers() visible={}; return true end
function owner:CP2077Session_SetPlayerMarker(id,x,y,z,yaw)
    updates=updates+1
    if failUpdate then return false end
    visible[id]={x=x,y=y,z=z,yaw=yaw}; return true
end
function owner:CP2077Session_RemovePlayerMarker(id)
    removals=removals+1
    if failRemove then return false end
    visible[id]=nil; return true
end
local function sample(id,entity,x) return {player=id,entity=entity or "9007199254740993ULL",x=x or 1,y=2,z=3,yaw=math.pi} end
local m=Markers.new()
assert(m:step("a",owner,{sample(2),sample(3,"9007199254740994ULL",4)},0))
assert(visible[2].x==1 and visible[3].x==4)
assert(m:diagnostics()["2"].entity=="9007199254740993")
-- Refresh coherent target, suppress high-frequency UI updates.
m:step("a",owner,{sample(2,nil,8),sample(3)},0.05); assert(visible[2].x==1)
m:step("a",owner,{sample(2,nil,8),sample(3)},0.2); assert(visible[2].x==8)
-- Departure removes only that marker; the unrelated player's remains.
m:step("a",owner,{sample(3)},0.4); assert(not visible[2] and visible[3])
-- Reused PlayerId must finish exact old marker cleanup before replacement.
failRemove=true
m:step("a",owner,{sample(3,"9007199254740995ULL",19)},0.5)
assert(visible[3].x==1 and m:diagnostics()["3"].retiring)
failRemove=false
m:step("a",owner,{sample(3,"9007199254740995ULL",19)},1.6)
assert(visible[3].x==19 and m:diagnostics()["3"].entity=="9007199254740995")
-- Reconnect uses fresh scope, not matching coordinates as identity.
local before=removals
m:step("b",owner,{sample(3,"9007199254740995ULL",19)},2)
assert(removals==before+1 and m:diagnostics()["3"].scope=="b")
-- Ambiguous duplicate or non-finite transform never creates a misleading pin.
m:step("b",owner,{sample(3),sample(3,"9007199254740996ULL")},3); assert(not visible[3])
m:step("b",owner,{sample(4,nil,0/0)},4); assert(not visible[4])
-- Engine exceptions/rejections cannot create endless commands.
failUpdate=true
for t=5,12 do m:step("b",owner,{sample(8)},t) end
assert(m:diagnostics()["8"].blocked)
local stopped=updates
m:step("b",owner,{sample(8)},13); assert(updates==stopped)
assert(m:reset(14)) -- failed update does not prevent cleanup
failUpdate=false
m:step("c",owner,{sample(9)},15)
failRemove=true
for t=16,22 do assert(not m:reset(t)) end
assert(m:diagnostics()["9"].blocked and visible[9])
local attempts=removals
m:step("d",owner,{sample(9,"999ULL",99)},23)
assert(removals==attempts and visible[9].x==1, "uncertain cleanup must block replacement")
-- Reload recovers only the REDscript-owned handles.
failRemove=false
local reloaded=Markers.new(); reloaded:step("d",owner,{},24); assert(next(visible)==nil)
print("player_markers: multi-player identity, lifecycle, failure bounds and reload passed")
