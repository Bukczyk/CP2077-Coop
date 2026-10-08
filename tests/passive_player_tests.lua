local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local Passive = assert(require("player_passive"))
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
local function text(value) return tostring(value):gsub("[uUlL]+$", "") end
local function id(value)
    return {hash = setmetatable({}, {__tostring = function() return value .. "ULL" end})}
end
local function pose(player, entity, x)
    return {player=player, entity=entity or "9007199254740993ULL", x=x or 1, y=2, z=3, yaw=math.pi/2}
end
local function fixture()
    local f = {entries={}, mapped={}, spawnCalls=0, binds=0, unbinds=0, despawns=0,
        moves=0, ready=true, mode="immediate", dynamic={}, logs={}}
    local s = {}
    function s:IsReady() return f.ready end
    function s:SpawnEntity(spec)
        f.spawnCalls = f.spawnCalls + 1
        local hash = "900719925474099" .. tostring(f.spawnCalls)
        local e = {id=hash, spec=spec, managed=f.mode~="abort", spawning=f.mode=="pending",
            spawned=f.mode=="immediate", visible=f.mode=="immediate", attached=true}
        e.actor = {
            GetEntityID=function() return id(e.wrongId or hash) end,
            IsAttached=function() return e.attached end,
            GetWorldPosition=function() return e.position or spec.position end,
            SetWorldTransform=function(_, world)
                if f.moveError then error("move rejected") end
                f.moves=f.moves+1; e.position=world.position; e.angles=world.angles
            end,
        }
        f.entries[hash]=e
        return f.zeroId and id("0") or id(hash)
    end
    local function entry(token)
        if f.observationError then error("unavailable") end
        return assert(f.entries[text(token.hash)], "unowned token")
    end
    function s:GetEntity(token) local e=entry(token); return e.visible and e.actor or nil end
    function s:IsManaged(token) return entry(token).managed end
    function s:IsSpawning(token) return entry(token).spawning end
    function s:IsSpawned(token) return entry(token).spawned end
    function s:DespawnEntity(token)
        entry(token); f.despawns=f.despawns+1
        if f.despawnError then error("despawn rejected") end
        return not f.denyDespawn
    end
    function s:GetTagged(tag)
        local actors={}
        for _,e in pairs(f.entries) do
            for _,candidate in ipairs(e.spec.tags) do
                if candidate==tag and e.visible then actors[#actors+1]=e.actor end
            end
        end
        return actors
    end
    Game = {
        GetStaticEntitySystem=function() return s end,
        CP2077Session_Bind=function(session, token)
            if f.denyBind then return false end
            local sid, hash=text(session),text(token.hash)
            check(f.mapped[sid]==nil or f.mapped[sid]==hash, "no duplicate session binding")
            for other,actual in pairs(f.mapped) do check(actual~=hash or other==sid, "no local ID alias") end
            f.mapped[sid]=hash; f.binds=f.binds+1; return true
        end,
        CP2077Session_Resolve=function(token)
            if f.resolveError then error("registry unavailable") end
            for session,hash in pairs(f.mapped) do if hash==text(token.hash) then return session.."ULL" end end
            return "0ULL"
        end,
        CP2077Session_Unbind=function(session)
            f.unbinds=f.unbinds+1
            if f.denyUnbind then return false end
            f.mapped[text(session)]=nil; return true
        end,
    }
    StaticEntitySpec={new=function() return {} end}
    ResRef={FromName=function(v) return v end}; CName={new=function(v) return v end}
    Vector4={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
    Quaternion={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
    EulerAngles={new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end}
    WorldTransform={new=function() return {} end,
        SetPosition=function(world,p) world.position=p end,
        SetOrientationEuler=function(world,a) world.angles=a end}
    function f:gone(hash)
        local e=assert(self.entries[hash])
        e.managed,e.spawning,e.spawned,e.visible=false,false,false,false
    end
    function f:goneAll() for hash in pairs(self.entries) do self:gone(hash) end end
    f.system=s
    f.controller=Passive.new(function(status) f.logs[#f.logs+1]=status end)
    return f
end

-- More than two independent players, with adjacent opaque network and local IDs.
do
    local f=fixture(); local players={pose(2),pose(3,"9007199254740994ULL",8),pose(4,"9007199254740995ULL",12)}
    check(f.controller:step("scope-a",players,0),"three players bound and submitted")
    check(f.spawnCalls==3 and #f.controller:boundIds()==3,"independent dynamic membership")
    for _,p in ipairs(players) do
        local hash=assert(f.mapped[text(p.entity)]); local e=f.entries[hash]
        check(e.spec.templatePath=="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent","original cosmetic asset")
        check(#e.spec.tags==2 and e.spec.tags[1]=="CP2077Session.PassivePlayer"
            and e.spec.tags[2]=="CP2077Session.PassivePlayer."..p.player,"dedicated exact player tags")
        check(e.angles.yaw==90 and e.position.x==p.x,"per-player transform and one radians conversion")
        check(#f.system:GetTagged(e.spec.tags[2])==1,"private probe can find exactly one player")
    end
    check(#f.system:GetTagged("CP2077Coop.ExperimentalStaticNpc")==0,"never enters physical NPC target selector")
    players[2].x=32; f.controller:step("scope-a",players,0.1)
    check(f.spawnCalls==3 and f.entries[f.mapped[text(players[2].entity)]].position.x==32,"updates reuse exact token")
    local oldHash=f.mapped[text(players[1].entity)]
    check(not f.controller:step("scope-a",{players[2],players[3]},0.2),"leave starts observed retirement")
    check(f.despawns==1 and f.mapped[text(players[1].entity)]==nil,"unbind precedes despawn")
    local before=f.moves
    check(not f.controller:step("scope-a",players,0.3) and f.spawnCalls==3 and f.moves==before,"rejoin cannot revive retiring actor")
    f:gone(oldHash)
    check(f.controller:step("scope-a",players,1.2) and f.spawnCalls==4,"only observed disappearance permits replacement")
end

-- Scope change with a pending spawn must retain its exact token and tags.
do
    local f=fixture(); f.mode="pending"; local p=pose(2)
    check(not f.controller:step("scope-a",{p},0) and f.spawnCalls==1,"pending token tracked")
    local old=f.controller.owned[2].id
    f.mapped={} -- native generation reset runs before Lua cleanup
    check(not f.controller:step("scope-b",{p},0.1),"new scope waits for old token")
    check(f.despawns==1 and f.binds==0 and f.spawnCalls==1,"pending creation never bound or respawned")
    f.entries[text(old.hash)].spawning=false
    check(not f.controller:step("scope-b",{p},0.2),"managed-only transition is still owned")
    f:gone(text(old.hash)); f.mode="immediate"
    check(f.controller:step("scope-b",{p},0.3),"new scope proceeds only after disappearance")
    check(f.spawnCalls==2 and f.controller.scope=="scope-b","fresh token and scope")
    local replacement=f.controller.owned[2].id
    check(not f.controller:reset(),"same-scope reset retains asynchronous token")
    check(not f.controller:step("scope-b",{p},0.4) and f.spawnCalls==2,"same-scope reset cannot resurrect actor")
    f:gone(text(replacement.hash)); check(f.controller:pump(),"unloaded game can finish retirement without a snapshot")
    check(next(f.controller.owned)==nil and f.controller.scope==nil,"scope cleared only after complete retirement")
end

-- Each disappearance observation matters; errors and a stale visible handle fail closed.
do
    local f=fixture(); f.controller:step("scope",{pose(2)},0)
    local token=f.controller.owned[2].id; local e=f.entries[text(token.hash)]
    f.denyUnbind=true
    check(not f.controller:reset() and f.despawns==0,"failed unbind retains ownership before delete")
    f.denyUnbind=false; f.denyDespawn=true
    check(not f.controller:pump() and f.despawns==1,"rejected deletion retained")
    f.denyDespawn=false
    check(not f.controller:pump() and f.despawns==2,"accepted deletion still pending")
    e.managed,e.spawning,e.spawned=false,false,false
    check(not f.controller:pump() and f.despawns==2,"visible stale handle prevents completion")
    e.visible=false; f.observationError=true
    check(not f.controller:pump(),"observation failure cannot certify disappearance")
    f.observationError=false
    check(f.controller:pump() and next(f.controller.owned)==nil,"complete observed retirement")
end

-- Native mapping theft must never unbind or delete the other exact owner.
do
    local f=fixture(); f.controller:step("scope",{pose(2)},0)
    local hash=f.mapped["9007199254740993"]
    f.mapped={["9007199254740994"]=hash}
    check(not f.controller:reset() and f.unbinds==0 and f.despawns==0,"different exact mapping preserved")
    f.mapped={}; check(not f.controller:pump() and f.despawns==1,"already missing mapping allows retirement")
end

-- Asset failures and failed binding must not flood SpawnEntity every frame.
for _,mode in ipairs({"abort","binding"}) do
    local f=fixture(); f.mode=mode=="abort" and "abort" or "immediate"; f.denyBind=mode=="binding"
    for frame=0,59 do
        f.controller:step("scope",{pose(2)},frame/60)
        if mode=="binding" then f:goneAll() end
    end
    check(f.spawnCalls==1,mode.." retry gate survives token retirement")
    f.controller:step("scope",{pose(2)},1.01)
    check(f.spawnCalls==2,mode.." may retry after one second")
end

do
    local f=fixture(); f.mode="pending"; f.controller:step("scope",{pose(2)},0)
    local e=f.entries[text(f.controller.owned[2].id.hash)]
    e.visible,e.spawned,e.spawning=true,true,false; e.wrongId="9007199254740999"
    check(not f.controller:step("scope",{pose(2)},0.1) and f.binds==0 and f.despawns==1,"wrong handle identity retires exact original token")
end

do
    local f=fixture()
    for _,bad in ipairs({0,2,"0ULL","18446744073709551616ULL"}) do
        check(not pcall(function() f.controller:step("scope",{pose(2,bad)},0) end),"reject invalid or numeric opaque identity")
    end
    for _,field in ipairs({"x","y","z","yaw"}) do
        local p=pose(2); p[field]=0/0
        check(not pcall(function() f.controller:step("scope",{p},0) end),"reject nonfinite pose before engine")
    end
    check(not pcall(function() f.controller:step("scope",{pose(2),pose(2,"7ULL")},0) end),"duplicate PlayerId rejected")
    check(not pcall(function() f.controller:step("scope",{pose(2),pose(3)},0) end),"duplicate SessionEntityId rejected")
    check(f.spawnCalls==0,"invalid snapshots have no spawn side effects")
end

-- Real entrypoint: opt-in must avoid dynamic Judy, wait for old dynamic bodies,
-- and pump asynchronous static cleanup through unload, reconnect and failure.
do
    local f=fixture(); local events,hotkeys={},{}
    local log=print; print=function(v) f.logs[#f.logs+1]=v end
    registerForEvent=function(name,fn) events[name]=fn end
    registerHotkey=function(name,_,fn) hotkeys[name]=fn end
    Observe=function() end
    package.loaded.config={experimentalNpcReplication=false,experimentalPassivePlayers=true}
    local dyn={}
    function dyn:IsReady() return true end
    function dyn:GetTagged() return f.dynamic end
    function dyn:DeleteTagged() f.dynamicDeletes=(f.dynamicDeletes or 0)+1 end
    local player={}
    function player:IsAttached() return true end
    function player:GetEntityID() return id("101") end
    function player:GetWorldPosition() return {x=1,y=2,z=3} end
    function player:GetWorldOrientation() return {ToEulerAngles=function() return {yaw=0} end} end
    function player:CP2077Session_SpawnProxy() error("dynamic Judy must never spawn in passive mode") end
    f.generation=1; f.loaded=true; f.remotes={pose(2),pose(3,"9007199254740994ULL")}
    local selected
    Game.GetPlayer=function() return f.loaded and player or nil end
    Game.GetSystemRequestsHandler=function() return nil end
    Game.GetDynamicEntitySystem=function() return dyn end
    Game.CP2077Session_ExperimentalStaticNpcProjection=function() return false end
    Game.CP2077Session_SetActive=function(on) if not on then f.mapped={} end end
    Game.CP2077Session_PushLocal=function() end
    Game.CP2077Session_BeginFrame=function() return #f.remotes end
    Game.CP2077Session_Generation=function() return f.generation end
    Game.CP2077Session_Session=function() return "50ULL" end
    Game.CP2077Session_Epoch=function() return 1 end
    Game.CP2077Session_Phase=function() return 4 end
    Game.CP2077Session_SelfEntity=function() return "1ULL" end
    Game.CP2077Session_Self=function() return 1 end
    Game.CP2077Session_Host=function() return 1 end
    Game.CP2077Session_BubbleRadius=function() return 100 end
    Game.CP2077Session_Select=function(i) selected=f.remotes[i+1]; return selected~=nil end
    Game.CP2077Session_Player=function() return selected.player end
    Game.CP2077Session_Entity=function() return selected.entity end
    for _,field in ipairs({"X","Y","Z","Yaw"}) do
        Game["CP2077Session_"..field]=function() return selected[field:lower()] end
    end
    assert(loadfile(root.."/runtime/session/cet/CP2077Coop/init.lua"))()
    events.onInit(); f.dynamic={{old=true}}; events.onUpdate(0.01)
    check(f.spawnCalls==0 and f.dynamicDeletes>0,"old dynamic handle must disappear before static activation")
    f.dynamic={}; events.onUpdate(0.01)
    check(f.spawnCalls==2 and #f.system:GetTagged(Passive.tag)==2,"entrypoint selects only static players")
    local old={}; for hash in pairs(f.entries) do old[#old+1]=hash end
    f.generation=2; f.mapped={}; events.onUpdate(0.01)
    check(f.spawnCalls==2 and f.despawns==2,"generation reset defers replacements")
    for _,hash in ipairs(old) do f:gone(hash) end
    events.onUpdate(0.01); check(f.spawnCalls==4,"new generation starts after actual retirement")
    f.loaded=false; events.onUpdate(0.01)
    check(f.despawns==4,"unload requests owned static retirement")
    f:goneAll(); events.onUpdate(0.01)
    f.loaded=true; events.onUpdate(0.01)
    check(f.spawnCalls==6,"unloaded cleanup is pumped before next save")
    -- Invalid input trips the bridge latch; cleanup must still continue afterward.
    f.remotes[1].x=0/0; events.onUpdate(0.01)
    local atFailure=f.despawns
    check(atFailure==6,"bridge failure starts retirement")
    f:goneAll(); events.onUpdate(0.01)
    f.remotes[1].x=1; hotkeys.cp2077_session_reconnect(); events.onUpdate(0.01)
    check(f.spawnCalls==8,"explicit reconnect recovers after failed-mode cleanup")
    events.onShutdown(); check(f.despawns==8,"shutdown requests exact owned cleanup")
    print=log
end
local defaults=assert(loadfile(root.."/runtime/session/cet/CP2077Coop/config.lua"))()
check(defaults.experimentalPassivePlayers==false,"packaged config stays explicitly false")
print("passive_player: PASS ("..checks.." checks; opt-in exact static identity and observed lifecycle, no live collision claim)")
