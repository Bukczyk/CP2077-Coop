local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local Runtime = require("npc_runtime")
local nextId, specs, spawned, removed, mapped, positioned, reverse = 0, {}, {}, {}, {}, {}, {}
local denyBind = false
local system = {}
function system:IsReady() return true end
function system:IsManaged(id) return specs[id] ~= nil and not removed[id] end
function system:SpawnEntity(spec)
    nextId = nextId + 1
    local id = "static-entity-" .. nextId
    specs[id], spawned[id] = spec, false
    return id
end
function system:IsSpawning(id) return not removed[id] and not spawned[id] end
function system:IsSpawned(id) return not removed[id] and spawned[id] == true end
function system:GetEntity(id)
    if removed[id] or not spawned[id] then return nil end
    return {
        GetEntityID=function() return id end,
        SetWorldTransform=function(_, world) positioned[id]=world end
    }
end
function system:DespawnEntity(id)
    assert(specs[id] ~= nil and not removed[id])
    removed[id] = true
    return true
end
Game = {
    GetStaticEntitySystem=function() return system end,
    CP2077Session_Bind=function(sessionId, localId)
        assert(spawned[localId] and sessionId ~= localId)
        if denyBind then return false end
        assert(not mapped[sessionId])
        mapped[sessionId], reverse[localId] = localId, sessionId
        return true
    end,
    CP2077Session_Unbind=function(sessionId)
        local id = mapped[sessionId]
        if id then reverse[id] = nil end
        mapped[sessionId] = nil
        return true
    end
}
StaticEntitySpec = {new=function() return {} end}
ResRef = {FromName=function(path) return {path=path} end}
CName = {new=function(value) return value end}
Vector4 = {new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
Quaternion = {new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
EulerAngles = {new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end}
WorldTransform = {
    new=function() return {} end,
    SetPosition=function(world, pos) world.position=pos end,
    SetOrientationEuler=function(world, angles) world.angles=angles end
}
local adapter = require("npc_static_population")
assert(adapter.available())
local controller = Runtime.new(adapter)
local bubble = {radius=20,centers={{x=0,y=0,z=0}}}
local npc = {entity="9007199254740993",record=123,x=1,y=2,z=3,yaw=0.5}
assert(controller:step("session:epoch-1",bubble,{npc}))
assert(nextId==1 and next(mapped)==nil) -- exact StaticEntitySystem EntityID retained during spawn
local id="static-entity-1"
assert(specs[id].templatePath.path=="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent")
assert(specs[id].appearanceName==nil and specs[id].attached==true)
assert(specs[id].position.x==1 and math.abs(specs[id].orientation.z-math.sin(0.25))<1e-6)
assert(not adapter.bind(npc.entity,"wrong-id"))
spawned[id]=true
assert(controller:step("session:epoch-1",bubble,{npc}) and mapped[npc.entity]==id)
assert(reverse[id]==npc.entity and positioned[id].position.z==3 and positioned[id].angles.yaw==math.deg(0.5))
assert(controller:step("session:epoch-1",bubble,{npc}) and nextId==1) -- stable ID, no duplicate spawn
assert(not controller:step("session:epoch-1",{radius=1,centers={{x=100,y=0,z=0}}},{npc}))
assert(mapped[npc.entity]==nil and removed[id]) -- bubble exit unbinds, then despawns the owned EntityID
assert(controller:step("session:epoch-2",bubble,{npc}) and nextId==2) -- epoch reset creates a fresh exact projection
spawned["static-entity-2"]=true
assert(controller:step("session:epoch-2",bubble,{npc}) and mapped[npc.entity]=="static-entity-2")
assert(controller:reset() and mapped[npc.entity]==nil and removed["static-entity-2"])
local denied={entity="9007199254740994",record=123,x=0,y=0,z=0,yaw=0}
assert(controller:step("session:epoch-2",bubble,{denied}) and nextId==3)
spawned["static-entity-3"]=true
denyBind=true
assert(not controller:step("session:epoch-2",bubble,{denied}))
denyBind=false
assert(removed["static-entity-3"] and next(mapped)==nil)
assert(not adapter.spawn({entity="bad",x=0/0,y=0,z=0,yaw=0}) and nextId==3)
assert(not adapter.spawn({entity="infinite",x=math.huge,y=0,z=0,yaw=0}) and nextId==3)
print("Experimental StaticEntitySystem projection create, exact binding, move, bubble cleanup and epoch reset passed")
