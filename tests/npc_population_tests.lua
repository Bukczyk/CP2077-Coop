local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local Runtime = require("npc_runtime")
local default = require("npc_population")
assert(default.available() == false) -- unverified production hooks must stay fail-closed
assert(loadfile(root .. "/runtime/session/cet/CP2077Coop/init.lua"))
local log, visible, hidden, mapped = {}, {}, {}, {}
local ambient = { a={x=1,y=0,z=0}, b={x=500,y=0,z=0} }
local bubble = {radius=20,centers={{x=0,y=0,z=0}},exclusions={"player-proxy"}}
local enabled, failAcquire, failRemove, nextId = false, false, false, 0
local adapter = {
    available=function() return enabled end,
    acquire=function(boundary, exclusions)
        assert(exclusions[1]=="player-proxy")
        log[#log+1]="acquire"
        for id,p in pairs(ambient) do hidden[id]=Runtime.contains(boundary,p) end
        return not failAcquire
    end,
    release=function() log[#log+1]="restore"; hidden={}; return true end,
    spawn=function(npc)
        assert(hidden.a or hidden.b)
        nextId=nextId+1; local localId="projection-"..nextId
        visible[localId]=npc.entity; log[#log+1]="spawn"; return localId
    end,
    move=function(localId,npc) assert(visible[localId]==npc.entity); return true end,
    remove=function(localId)
        if failRemove then return false end
        visible[localId]=nil; log[#log+1]="remove"; return true
    end,
    bind=function(entity,localId) assert(not mapped[entity]); mapped[entity]=localId; return true end,
    unbind=function(entity) mapped[entity]=nil; return true end
}
local controller=Runtime.new(adapter)
local first={entity="9007199254740993",record=123,x=1,y=0,z=0}
local second={entity="9007199254740994",record=123,x=1,y=0,z=0} -- SAME position, distinct identity
assert(not controller:step("session1:epoch1",bubble,{first,second}))
assert(next(visible)==nil and next(hidden)==nil)
enabled=true
assert(controller:step("session1:epoch1",bubble,{first,second}))
assert(nextId==2 and mapped[first.entity]~=mapped[second.entity])
assert(hidden.a and not hidden.b)
assert(controller:step("session1:epoch1",bubble,{first,second}) and nextId==2) -- no duplicate spawn
-- New independently generated JOINER ambient population is covered by lease refresh.
ambient.c={x=2,y=0,z=0}
assert(controller:step("session1:epoch1",bubble,{first,second}) and hidden.c)
assert(controller:step("session1:epoch1",bubble,{second}))
assert(not mapped[first.entity] and mapped[second.entity])
local oldProjection=mapped[second.entity]
assert(controller:step("session1:epoch2",bubble,{second}))
assert(mapped[second.entity]~=oldProjection) -- epoch reset invalidates local mappings
assert(controller:reset()); assert(next(visible)==nil and next(hidden)==nil and next(mapped)==nil)
assert(log[#log]=="restore") -- projections removed before population restored
assert(controller:reset()) -- idempotent leave
assert(controller:step("session2:epoch1",bubble,{second}))
failRemove=true
assert(not controller:reset()); assert(hidden.a) -- cannot restore competing ambient while cleanup failed
failRemove=false; assert(controller:reset()); assert(next(hidden)==nil)
failAcquire=true
assert(not controller:step("session3:epoch1",bubble,{second}))
assert(next(visible)==nil and next(hidden)==nil) -- failed partial lease must recover
failAcquire=false
assert(controller:step("session3:epoch1",bubble,{second}))
local moved={radius=20,centers={{x=500,y=0,z=0}},exclusions={"player-proxy"}}
assert(not controller:step("session3:epoch1",moved,{second}))
assert(next(visible)==nil and next(hidden)==nil) -- leave bubble restores original population
assert(not Runtime.contains(bubble,{x=0/0,y=0,z=0}))
print("Session Bubble identity, suppression gating, recovery and projection lifecycle tests passed")
