local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
assert(loadfile(root .. "/runtime/session/cet/CP2077Coop/init.lua"))
local Runtime = require("npc_runtime")
local nextId, spawned, specs, removed, mapped, mappedByLocal, positioned, sessionByLocal = 0, {}, {}, {}, {}, {}, {}, {}
local denyBinding = false
local system = {}
function system:IsReady() return true end
function system:CreateEntity(spec)
    nextId = nextId + 1
    local id = "engine-entity-" .. nextId
    specs[id], spawned[id] = spec, false
    sessionByLocal[id] = string.sub(spec.tags[2], #"CP2077Coop.NetworkNpc." + 1)
    return id
end
function system:IsManaged(id) return specs[id] ~= nil and not removed[id] end
function system:IsSpawning(id) return not removed[id] and not spawned[id] end
function system:IsSpawned(id) return not removed[id] and spawned[id] == true end
function system:GetEntity(id)
    if removed[id] or not spawned[id] then return nil end
    return { GetEntityID=function() return id end, IsAttached=function() return not removed[id] and spawned[id] end }
end
function system:DeleteEntity(id)
    assert(specs[id] ~= nil and not removed[id])
    removed[id] = true
    return true
end
Game = {
    GetDynamicEntitySystem=function() return system end,
    FindEntityByID=function(id) return system:GetEntity(id) end,
    CP2077Session_Bind=function(sessionId, localId)
        assert(spawned[localId] and sessionId ~= localId)
        if denyBinding then return false end
        assert(not mapped[sessionId])
        mapped[sessionId] = localId
        return true
    end,
    CP2077Session_Unbind=function(sessionId) mapped[sessionId] = nil; return true end,
    CP2077Session_Resolve=function(localId) return mappedByLocal[localId] or "0ULL" end,
    GetTeleportationFacility=function()
        return { Teleport=function(_, entity, position, angles)
            localId = entity:GetEntityID()
            assert(mappedByLocal[localId])
            positioned[localId] = { position=position, angles=angles }
        end }
    end
}
TweakDB = { GetRecord=function(_, record) return record and record ~= 0 and {} or nil end }
DynamicEntitySpec = { new=function() return {} end }
CName = { new=function(value) return value end }
Vector4 = { new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end }
Quaternion = { new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end }
EulerAngles = { new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end }
local actualBind = Game.CP2077Session_Bind
Game.CP2077Session_Bind=function(sessionId, localId)
    local ok=actualBind(sessionId, localId)
    if ok then mappedByLocal[localId]=sessionId end
    return ok
end
Game.CP2077Session_Unbind=function(sessionId)
    local localId=mapped[sessionId]
    mappedByLocal[localId]=nil
    mapped[sessionId]=nil
    return true
end
local adapter = require("npc_population")
assert(adapter.available())
local controller = Runtime.new(adapter)
local time=0
controller:pump(time,false)
local function settleStep(identity,bubble,npcs)
    for _=1,10 do
        time=time+0.1; controller:pump(time,false)
        if controller:step(identity,bubble,npcs) then return true end
    end
    return false
end
local function settleReset()
    for _=1,10 do
        time=time+0.1; controller:pump(time,false)
        if controller:reset() then return true end
    end
    return false
end
local bubble = {radius=20,centers={{x=0,y=0,z=0}}}
local first={entity="9007199254740993",record=123,x=1,y=0,z=0,yaw=0.5}
local second={entity="9007199254740994",record=123,x=1,y=0,z=0,yaw=1.0}
assert(controller:step("session-a:epoch-1",bubble,{first,second}))
assert(nextId==2 and next(mapped)==nil) -- handles are allocated; Codeware spawn is still pending
for id in pairs(specs) do spawned[id]=true end
assert(controller:step("session-a:epoch-1",bubble,{first,second}))
assert(mapped[first.entity] ~= mapped[second.entity])
assert(sessionByLocal[mapped[first.entity]] == first.entity and sessionByLocal[mapped[second.entity]] == second.entity)
local firstLocal, secondLocal = mapped[first.entity], mapped[second.entity]
assert(specs[firstLocal].recordID==123)
assert(specs[firstLocal].persistState==false and specs[firstLocal].persistSpawn==false)
assert(positioned[firstLocal].position.x==1 and positioned[secondLocal].angles.yaw==math.deg(1.0))
assert(controller:step("session-a:epoch-1",bubble,{first,second}) and nextId==2) -- duplicate frames reuse exact IDs
assert(settleStep("session-a:epoch-1",bubble,{second}))
assert(mapped[first.entity]==nil and removed[firstLocal])
assert(settleStep("session-a:epoch-2",bubble,{second})) -- observed epoch cleanup then respawn
assert(nextId==3 and removed[secondLocal] and mapped[second.entity]==nil)
spawned["engine-entity-3"]=true
assert(controller:step("session-a:epoch-2",bubble,{second}) and mapped[second.entity]=="engine-entity-3")
assert(settleReset() and next(mapped)==nil and removed["engine-entity-3"])
assert(controller:step("session-b:epoch-1",bubble,{second})) -- reconnect uses a fresh local entity
assert(nextId==4 and mapped[second.entity]==nil)
spawned["engine-entity-4"]=true
assert(controller:step("session-b:epoch-1",bubble,{second}) and mapped[second.entity]=="engine-entity-4")
assert(settleReset() and next(mapped)==nil)
assert(not adapter.spawn({entity="bad",record=0,x=0,y=0,z=0,yaw=0}) and nextId==4)
local rejected={entity="9007199254740995",record=123,x=1,y=0,z=0,yaw=0}
assert(controller:step("session-c:epoch-1",bubble,{rejected}) and nextId==5)
spawned["engine-entity-5"]=true
denyBinding=true
assert(not controller:step("session-c:epoch-1",bubble,{rejected}))
denyBinding=false
assert(settleReset())
assert(removed["engine-entity-5"] and next(mapped)==nil) -- bind failure removes the unbound projection
assert(not Runtime.contains(bubble,{x=0/0,y=0,z=0}))
print("Session NPC projection creation, async bind, exact identity, cleanup and reconnect tests passed")
