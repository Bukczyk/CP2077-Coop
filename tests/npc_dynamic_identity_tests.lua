local root = assert(arg[1], "repository path required")
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local Runtime = require("npc_runtime")
local checks, wrapperSerial = 0, 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message)
end
local function entityId(hash)
    wrapperSerial = wrapperSerial + 1
    local serial = wrapperSerial
    local opaque = setmetatable({}, {__tostring = function() return hash end})
    return setmetatable({hash=opaque}, {__tostring=function() return "EntityID wrapper #" .. serial end})
end
local function hashOf(id) return tostring(id.hash) end
local FIRST, SECOND, THIRD = "9007199254740993ULL", "9007199254740994ULL", "9007199254740995ULL"
local TARGET, OTHER = "18014398509481985ULL", "18014398509481986ULL"
local function npc(target)
    return {entity=target or TARGET,record=123,x=1,y=2,z=3,yaw=0.5}
end
local bubble = {radius=20,centers={{x=0,y=0,z=0}}}

local function fixture(hashes)
    hashes = hashes or {FIRST,SECOND,THIRD}
    local f = {entries={},mapped={},creates=0,deletes=0,binds=0,unbinds=0,moves=0}
    local system = {}
    function system:IsReady() return not f.unavailable end
    function system:CreateEntity(spec)
        f.creates = f.creates + 1
        local hash = assert(hashes[f.creates], "unexpected duplicate creation")
        local entry = {managed=true,spawning=false,spawned=true,visible=true,global=true,attached=true,spec=spec}
        entry.actor = {GetEntityID=function() return entityId(entry.actualHash or hash) end,
            IsAttached=function() return entry.attached end}
        f.entries[hash] = entry
        return entityId(hash)
    end
    function system:IsManaged(id)
        if f.observationError then error("temporarily unavailable") end
        return assert(f.entries[hashOf(id)]).managed
    end
    function system:IsSpawning(id) return assert(f.entries[hashOf(id)]).spawning end
    function system:IsSpawned(id) return assert(f.entries[hashOf(id)]).spawned end
    function system:GetEntity(id)
        local entry = assert(f.entries[hashOf(id)])
        return entry.visible and entry.actor or nil
    end
    function system:DeleteEntity(id)
        assert(f.entries[hashOf(id)], "must not delete an unrelated entity")
        f.deletes = f.deletes + 1
        local entry=f.entries[hashOf(id)]
        if not entry.attached or not entry.managed or entry.spawning then
            -- Model the dangerous native sequence: accepted early deletion
            -- forgets the token, but CreateStub can still complete later.
            entry.managed,entry.spawning,entry.spawned,entry.visible,entry.global=false,false,false,false,false
            f.earlyDelete=true
        end
        if f.deleteError then error("delete failed") end
        return not f.denyDelete -- accepted does not mean gone
    end
    function f:gone(hash)
        local entry = self.entries[hash]
        entry.managed,entry.spawning,entry.spawned,entry.visible,entry.global,entry.attached = false,false,false,false,false,false
    end
    function f:at(now,paused)
        if paused==nil then paused=false end
        return self.adapter.observe(now,paused)
    end
    function f:remove(id,now,paused) self:at(now,paused); return self.adapter.remove(id) end
    Game = {
        GetDynamicEntitySystem=function() return system end,
        FindEntityByID=function(id)
            if f.lookupError then error("lookup unavailable") end
            local entry=assert(f.entries[hashOf(id)])
            return entry.global and entry.actor or nil
        end,
        CP2077Session_Bind=function(target,id)
            f.binds=f.binds+1
            assert(not f.mapped[target], "duplicate binding")
            if f.denyBind then return false end
            f.mapped[target]=hashOf(id); return true
        end,
        CP2077Session_Unbind=function(target)
            f.unbinds=f.unbinds+1
            if f.denyUnbind or not f.mapped[target] then return false end
            f.mapped[target]=nil; return true
        end,
        CP2077Session_Resolve=function(id)
            if f.resolveError then error("mapping unavailable") end
            for target,hash in pairs(f.mapped) do if hash==hashOf(id) then return target end end
            return "0ULL"
        end,
        GetTeleportationFacility=function()
            return {Teleport=function(_,actor,position,angles)
                f.moves=f.moves+1
                f.entries[hashOf(actor:GetEntityID())].position=position
                f.lastYaw=angles.yaw
            end}
        end
    }
    TweakDB={GetRecord=function(_,record) return record==123 and {} or nil end}
    DynamicEntitySpec={new=function() return {} end}
    CName={new=function(value) return value end}
    Vector4={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
    Quaternion={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
    EulerAngles={new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end}
    package.loaded.npc_population=nil
    f.adapter=require("npc_population")
    return f
end

-- Fresh wrappers and adjacent opaque IDs above 2^53 keep exact ownership.
do
    local f=fixture(); local a=f.adapter
    local one,two=assert(a.spawn(npc())),assert(a.spawn(npc(OTHER)))
    check(hashOf(one)==FIRST and hashOf(two)==SECOND,"opaque IDs must not round")
    check(not a.bind(TARGET,entityId(SECOND)) and f.binds==0,"foreign local ID rejected")
    f.entries[FIRST].actualHash=SECOND
    check(not a.bind(TARGET,entityId(FIRST)) and f.binds==0,"resolved actor identity rechecked")
    f.entries[FIRST].actualHash=nil
    check(a.bind(TARGET,entityId(FIRST)) and a.bind(OTHER,entityId(SECOND)),"same hashes bind through fresh wrappers")
    check(a.bind(TARGET,entityId(FIRST)) and f.binds==2,"repeat bind is idempotent")
    check(a.move(entityId(FIRST),npc()) and a.move(entityId(SECOND),npc(OTHER)),"owned movement accepts fresh wrappers")
    check(f.moves==2 and f.lastYaw==math.deg(0.5),"exact transform applied")
    check(math.abs(f.entries[FIRST].spec.orientation.z-math.sin(0.25))<1e-6,"spawn uses supplied facing")
    check(a.spawn(npc())==one and f.creates==2,"same session identity never duplicates")
    f.entries[FIRST].actualHash=SECOND
    check(not a.move(entityId(FIRST),npc()) and f.moves==2,"changed handle receives no move")
    check(not a.remove(entityId(FIRST)) and f.deletes==0,"bound actor must first unbind")
    check(a.remove(entityId("18446744073709551614ULL")) and f.deletes==0,"unowned removal has no side effect")
end

-- Async deletion requires stable attachment; every source of visible or
-- managed lifetime evidence blocks completion, including an unmanaged orphan.
for _,remaining in ipairs({"managed","spawning","spawned","visible","global","attached"}) do
    local f=fixture(); local a=f.adapter
    local id=assert(a.spawn(npc())); assert(a.bind(TARGET,id)); assert(a.unbind(TARGET))
    check(not f:remove(id,0) and f.deletes==0,"first attachment observation does not delete")
    check(not f:remove(id,0) and f.deletes==0,"same frame cannot qualify attachment twice")
    check(not f:remove(id,0.1) and f.deletes==1,"second distinct attachment submits delete")
    check(not a.bind(TARGET,id) and not a.move(id,npc()),"retiring actor cannot be driven")
    check(a.spawn(npc())==id and f.creates==1,"pending old actor reserves session identity")
    f:gone(FIRST); f.entries[FIRST][remaining]=true
    check(not f:remove(entityId(FIRST),1) and f.deletes==1,"remaining "..remaining.." blocks completion")
    f.entries[FIRST][remaining]=false
    check(not f:remove(id,2) and not f:remove(id,2.2),"absence needs a quiet interval")
    check(a.spawn(npc())==id and f.creates==1,"single absent frame cannot release identity")
    check(f:remove(entityId(FIRST),2.3) and f.deletes==1,"stable disappearance retires without another delete")
    check(hashOf(a.spawn(npc()))==SECOND and f.creates==2,"gone old actor permits replacement")
end

-- Unknown observations are not false, and malformed values cannot qualify
-- attachment or satisfy the quiet interval after deletion.
for _,unknown in ipairs({"managed","spawning","spawned","attached"}) do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    f:remove(id,0); f:remove(id,0.1); f:gone(FIRST)
    f.entries[FIRST][unknown]=nil
    check(not f:remove(id,1) and not f:remove(id,2),"unknown "..unknown.." must not count as absent")
    check(a.spawn(npc())==id,"invalid observation retains identity")
    f.entries[FIRST][unknown]=false
    check(not f:remove(id,3) and f:remove(id,3.3),"known false restarts stable absence")
end
for _,field in ipairs({"managed","spawning","spawned","attached"}) do
    for _,kind in ipairs({"nil","string"}) do
        local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
        f:remove(id,0)
        local original=f.entries[FIRST][field]
        if kind=="nil" then f.entries[FIRST][field]=nil else f.entries[FIRST][field]="false" end
        check(not f:remove(id,1) and not f:remove(id,2) and f.deletes==0,"invalid qualification field "..field)
        f.entries[FIRST][field]=original
        check(not f:remove(id,3) and f.deletes==0,"recovery needs a new stable pair")
        check(not f:remove(id,3.1) and f.deletes==1,"valid qualification can recover")
    end
end

-- A never-attached token can disappear and subsequently create a late actor.
-- Never delete that token early or conclude absence proves cancellation.
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    local entry=f.entries[FIRST]
    entry.visible,entry.global,entry.attached,entry.spawned,entry.spawning=false,false,false,false,true
    local bound,reason=a.bind(TARGET,id)
    check(bound==nil and reason=="pending","in-flight create is pending")
    check(not f:remove(id,0) and not f:remove(id,1) and f.deletes==0,"pending create cannot be deleted")
    f:gone(FIRST)
    check(not f:remove(id,2) and not f:remove(id,5) and f.deletes==0,"missing never-attached token remains owned")
    check(a.spawn(npc())==id and f.creates==1,"uncertain token blocks duplicate creation")
    entry.visible,entry.global,entry.attached,entry.spawned=true,true,true,true
    check(not f:remove(id,6) and not f:remove(id,7) and f.deletes==0,"late unmanaged actor remains owned")
    entry.managed=true
    check(not f:remove(id,8) and f.deletes==0,"recovered managed actor needs stable attachment")
    check(not f:remove(id,8.1) and f.deletes==1 and not f.earlyDelete,"only safely attached actor is deleted")
    f:gone(FIRST)
    check(not f:remove(id,8.2) and f:remove(id,8.5),"late actor can retire after real disappearance")
end

-- Prove the fixture represents accepted early deletion dropping its token,
-- followed by a late actor. That dangerous API path must never be used above.
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    local entry=f.entries[FIRST]; entry.attached,entry.spawning=false,true
    check(Game.GetDynamicEntitySystem():DeleteEntity(id)==true and f.earlyDelete,"fixture reproduces accepted early deletion")
    check(not entry.managed and not entry.global,"early deletion drops manager and global observations")
    check(not f:remove(id,0) and a.spawn(npc())==id,"adapter cannot release externally canceled pending token")
    entry.global,entry.attached=true,true
    check(not f:remove(id,1) and f.creates==1,"late global-only orphan still reserves identity")
end

-- Managed pre-stream tokens remain pending; failed/absent tokens report bind
-- failure but retain cleanup ownership because completion is not observable.
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    local entry=f.entries[FIRST]
    entry.visible,entry.global,entry.attached,entry.spawned=false,false,false,false
    local bound,reason=a.bind(TARGET,id)
    check(bound==nil and reason=="pending","managed pre-stream token remains pending")
    f:gone(FIRST)
    check(a.bind(TARGET,id)==false,"absent creation does not wait indefinitely in bind")
    check(not f:remove(id,0) and not f:remove(id,10) and f.deletes==0,"cleanup reports uncertainty rather than erasing pending identity")
end

-- Pauses, repeated timestamps and failed/unknown observations cannot advance
-- attachment or absence qualification. A reappearing handle resets absence.
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    f:remove(id,0); f:remove(id,0); check(f.deletes==0,"same timestamp never qualifies twice")
    f:remove(id,10,true); check(f.deletes==0,"paused engine receives no deletion")
    f:remove(id,11,false); check(f.deletes==0,"resume starts fresh qualification")
    f:remove(id,11.1,false); check(f.deletes==1,"next unpaused frame permits deletion")
    f:gone(FIRST); f:remove(id,11.2)
    check(not f:remove(id,20,true),"pause cannot satisfy absence window")
    check(not f:remove(id,21,false) and not f:remove(id,21.2,false),"resume restarts quiet observations")
    f.entries[FIRST].global=true
    check(not f:remove(id,21.3),"global actor reappearance cancels provisional absence")
    f.entries[FIRST].global=false; f:remove(id,22)
    f.lookupError=true; check(not f:remove(id,23),"lookup failure cancels provisional absence")
    f.lookupError=false; check(not f:remove(id,24) and f:remove(id,24.3),"fresh evidence recovers after lookup failure")
end
for _,bad in ipairs({0/0,math.huge,-1}) do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    f:remove(id,1)
    check(not f:remove(id,bad) and f.deletes==0,"invalid/backward clock cannot delete")
    f:remove(id,2); check(f.deletes==0,"invalid clock resets qualification")
    f:remove(id,2.1); check(f.deletes==1,"fresh clock can recover")
end
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    f:remove(id,0); a.observe(1,nil)
    check(not a.remove(id) and f.deletes==0,"unknown pause state blocks deletion")
    f:remove(id,2); check(f.deletes==0,"known pause state needs fresh pair")
    f:remove(id,2.1); check(f.deletes==1,"known pause state recovers")
end

-- Failed deletes retain ownership, with bounded attempts and no per-frame flood.
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc()))
    f.observationError=true
    check(not f:remove(id,0) and f.deletes==0,"failed observation cannot erase ownership")
    f.observationError=false; f.denyDelete=true
    f:remove(id,1); f:remove(id,1.1)
    check(f.deletes==1 and not f:remove(id,1.2) and f.deletes==1,"retry delay bounds rejected delete")
    f.denyDelete=false; f.deleteError=true
    f:remove(id,2); check(f.deletes==2,"throwing delete retains ownership")
    f.deleteError=false
    f:remove(id,3); check(f.deletes==3,"third attempt may succeed")
    f:gone(FIRST); f:remove(id,4)
    check(f:remove(id,4.3) and f.deletes==3,"accepted deletion is never repeated")
end
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc())); f.denyDelete=true
    for i=0,10 do f:remove(id,i) end
    check(f.deletes==3 and a.spawn(npc())==id,"exhausted deletes retain identity without unbounded calls")
end

-- Exact native mappings protect unrelated actors; missing mappings permit
-- retirement but never prove engine disappearance on their own.
do
    local f=fixture(); local a=f.adapter; local id=assert(a.spawn(npc())); assert(a.bind(TARGET,id))
    f.resolveError=true
    check(not a.unbind(TARGET) and not f:remove(id,0) and f.unbinds==0,"failed resolve retains bound actor")
    f.resolveError=false; f.mapped[TARGET]=nil; f.mapped[OTHER]=FIRST
    check(not a.unbind(TARGET) and not f:remove(id,1) and f.unbinds==0,"foreign mapping untouched")
    f.mapped[OTHER]=nil; f.mapped[TARGET]=FIRST; f.denyUnbind=true
    check(not a.unbind(TARGET) and not f:remove(id,2) and f.deletes==0,"rejected unbind prevents delete")
    f.denyUnbind=false; f.mapped={}
    check(a.unbind(TARGET) and f.unbinds==1,"missing native binding does not require another unbind")
    f:remove(id,3); f:remove(id,3.1); f:gone(FIRST); f:remove(id,4)
    check(f:remove(id,4.3),"native reset still waits for exact actor cleanup")
end

-- Existing runtime retirement persists across resets and same-epoch reentry.
for _,newScope in ipairs({"same-epoch","new-generation"}) do
    local f=fixture(); local controller=Runtime.new(f.adapter)
    controller:pump(0,false); assert(controller:step("same-epoch",bubble,{npc()}))
    if newScope=="same-epoch" then check(not controller:reset(),"same-scope reset waits")
    else f.mapped={} end
    for i=1,3 do
        controller:pump(i/10,false)
        check(not controller:step(newScope,bubble,{npc()}),"retirement remains pending")
        check(f.creates==1 and f.binds==1 and f.moves==1,"no old movement or duplicate while retiring")
    end
    check(f.deletes==1,"only one qualified deletion")
    f:gone(FIRST); controller:pump(1,false)
    check(not controller:step(newScope,bubble,{npc()}),"first absence cannot replace")
    controller:pump(1.3,false)
    check(controller:step(newScope,bubble,{npc()}) and f.mapped[TARGET]==SECOND,"quiet disappearance allows replacement")
end

-- Bubble reentry cannot revive pending removal while another NPC survives.
do
    local f=fixture(); local controller=Runtime.new(f.adapter)
    controller:pump(0,false); assert(controller:step("scope",bubble,{npc(),npc(OTHER)}))
    local retiring,survivor=f.mapped[TARGET],f.mapped[OTHER]
    check(not controller:step("scope",bubble,{npc(OTHER)}),"bubble exit waits")
    local binds,moves=f.binds,f.moves
    controller:pump(0.1,false)
    check(not controller:step("scope",bubble,{npc(),npc(OTHER)}) and f.binds==binds and f.moves==moves,"reentry cannot cancel retirement")
    f:gone(retiring); controller:pump(1,false)
    check(not controller:step("scope",bubble,{npc(),npc(OTHER)}),"reentry awaits quiet disappearance")
    controller:pump(1.3,false)
    check(controller:step("scope",bubble,{npc(),npc(OTHER)}) and f.mapped[TARGET]==THIRD and f.mapped[OTHER]==survivor,"surviving unrelated actor remains owned")
end

for _,field in ipairs({"x","y","z","yaw"}) do
    for _,value in ipairs({0/0,math.huge,-math.huge,false,"invalid"}) do
        local f=fixture(); local a=f.adapter; local invalid=npc(); invalid[field]=value
        check(a.spawn(invalid)==nil and f.creates==0,"nonfinite/invalid spawn "..field)
        local id=assert(a.spawn(npc())); assert(a.bind(TARGET,id))
        check(not a.move(id,invalid) and f.moves==0,"nonfinite/invalid move "..field)
    end
    local f=fixture(); local invalid=npc(); invalid[field]=nil
    check(f.adapter.spawn(invalid)==nil and f.creates==0,"missing transform component")
end
for _,zero in ipairs({"0","0ULL","0ull"}) do
    local f=fixture({zero,FIRST})
    check(f.adapter.spawn(npc())==nil and f.binds==0,"zero opaque ID rejected")
    check(hashOf(f.adapter.spawn(npc()))==FIRST and f.creates==2,"zero ID cannot reserve mapping")
end
print("Dynamic NPC identity/observed-cleanup checks passed: "..checks)
