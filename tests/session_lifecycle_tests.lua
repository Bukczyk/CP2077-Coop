-- Executes the real CET entrypoint, including lifecycle registration. Engine
-- mocks deliberately return a new EntityID wrapper on every read.
local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local report = print
local hasFfi, ffi = pcall(require, "ffi")
local function uint64(offset)
    if hasFfi then return ffi.new("uint64_t", 9007199254740992) + offset end
    -- Lua 5.4 fallback preserves the opaque-value behavior; LuaJIT uses real
    -- uint64_t cdata, like CET, to check precision beyond the double boundary.
    return setmetatable({}, {__tostring=function()
        return offset == 1 and "9007199254740993ULL" or "9007199254740994ULL"
    end})
end

local function fixture(role, experimental)
    local state = {
        attached=true, pregame=false, hasPlayer=true, hash=uint64(1),
        activations={}, bindings={}, logs={}, observations=0, cleared=0,
        npcReads=0, npcOffers=0, npcSpawns=0, pushes=0, ready=false, paused=false, npcClocks={},
    }
    local events, hotkeys = {}, {}
    Game, Observe, CName = nil, nil, nil
    package.loaded.npc_runtime, package.loaded.npc_population = nil, nil
    package.loaded.config = nil
    if experimental ~= nil then package.loaded.config={experimentalNpcReplication=experimental} end
    print = function(message) state.logs[#state.logs+1] = tostring(message) end
    registerForEvent = function(name, callback)
        assert(events[name] == nil, "duplicate lifecycle registration")
        events[name] = callback
    end
    registerHotkey = function(name, _, callback) hotkeys[name] = callback end
    assert(loadfile(root .. "/runtime/session/cet/CP2077Coop/init.lua"))()
    local population=package.loaded.npc_population
    local observe=population.observe
    population.observe=function(now,paused)
        state.npcClocks[#state.npcClocks+1]={now=now,paused=paused}
        return observe(now,paused)
    end
    assert(events.onInit, "entrypoint must register onInit")
    assert(state.observations == 0, "no engine observation during module load")
    -- These callbacks must also be harmless before the engine API is ready.
    events.onUpdate(1/60)
    hotkeys.cp2077_session_reconnect()
    events.onShutdown()
    assert(#state.activations == 0)

    local system = {}
    function system:IsReady() return true end
    function system:DeleteTagged() state.cleared=state.cleared+1 end
    function system:GetTagged() return {} end
    function system:IsTagged() return false end
    function system:CreateEntity() state.npcSpawns=state.npcSpawns+1; error("unexpected NPC creation") end
    local player = {}
    function player:IsAttached() return state.attached end
    function player:GetEntityID() return {hash=state.hash} end
    function player:GetWorldPosition() return {x=1,y=2,z=3} end
    function player:GetWorldOrientation()
        return {ToEulerAngles=function() return {yaw=30} end}
    end
    local native = {
        GetPlayer=function()
            if state.playerUnavailable then error("player lookup unavailable") end
            if state.hasPlayer then return player end
        end,
        GetSystemRequestsHandler=function()
            if state.requestsUnavailable then error("requests handler unavailable") end
            return {IsPreGame=function() return state.pregame end,
                IsGamePaused=function()
                    if state.pauseUnavailable then error("pause observation unavailable") end
                    return state.paused
                end}
        end,
        GetDynamicEntitySystem=function() return system end,
        CP2077Session_SetActive=function(value)
            state.activations[#state.activations+1]=value
        end,
        CP2077Session_PushLocal=function() state.pushes=state.pushes+1 end,
        CP2077Session_BeginFrame=function()
            if state.bridgeFailure then error("test bridge failure") end
            return 0
        end,
        CP2077Session_Generation=function() return 1 end,
        CP2077Session_Session=function() return uint64(1) end,
        CP2077Session_Epoch=function() return 1 end,
        CP2077Session_Phase=function() return 4 end,
        CP2077Session_Bind=function(_, id)
            state.bindings[#state.bindings+1]=tostring(id.hash); return true
        end,
        CP2077Session_SelfEntity=function() return uint64(2) end,
        CP2077Session_BubbleRadius=function() return 100 end,
        CP2077Session_Self=function() return role == "HOST" and 1 or 2 end,
        CP2077Session_Host=function() return 1 end,
        CP2077Session_NpcCapacity=function() state.npcReads=state.npcReads+1; return 128 end,
        CP2077Session_NpcCount=function() state.npcReads=state.npcReads+1; return 0 end,
        CP2077Session_NpcOffer=function() state.npcOffers=state.npcOffers+1; return true end,
    }
    state.init = function()
        state.ready=true
        Game, CName = native, {new=function(value) return value end}
        Observe = function(class, method, callback)
            assert(state.ready and class == "NPCPuppet" and method == "OnGameAttached")
            state.observations=state.observations+1
            state.observeNpc=callback
        end
        events.onInit()
        assert(state.observations == 1, "register observer when CET is ready")
    end
    state.tick = function(count)
        for _=1,(count or 1) do events.onUpdate(1/60) end
        for _, message in ipairs(state.logs) do
            assert(not message:find("BRIDGE_ERROR",1,true), message)
        end
    end
    state.reconnect=hotkeys.cp2077_session_reconnect
    state.rawTick=events.onUpdate
    state.shutdown=events.onShutdown
    return state
end

for _, role in ipairs({"HOST","JOINER"}) do
    local s=fixture(role)
    s.init()
    s.tick(180)
    assert(#s.activations == 1 and s.activations[1], role .. ": wrapper churn must not restart session")
    assert(#s.bindings == 180 and s.pushes == 180)
    assert(s.npcReads == 0 and s.npcOffers == 0 and s.npcSpawns == 0,
        "experimental NPC replication must default off")

    -- Real entity replacement still reconnects, even for adjacent opaque 64-bit
    -- hashes that would collapse if converted to a Lua double.
    local previous=s.bindings[#s.bindings]
    s.hash=uint64(2)
    s.tick(60)
    assert(#s.activations == 3 and not s.activations[2] and s.activations[3])
    assert(previous ~= s.bindings[#s.bindings], "must not round Uint64 identities")

    s.reconnect()
    assert(#s.activations == 4 and not s.activations[4])
    s.tick(120)
    assert(#s.activations == 5 and s.activations[5])
    for _, reason in ipairs({"detached","pregame","no-player"}) do
        local before=#s.activations
        if reason == "detached" then s.attached=false
        elseif reason == "pregame" then s.pregame=true
        else s.hasPlayer=false end
        s.tick(3)
        assert(#s.activations == before+1 and not s.activations[#s.activations], reason)
        s.attached, s.pregame, s.hasPlayer=true, false, true
        s.tick(3)
        assert(#s.activations == before+2 and s.activations[#s.activations], reason)
    end
    local before=#s.activations
    s.shutdown()
    assert(#s.activations == before+1 and not s.activations[#s.activations])
end

-- Opt-in still registers the observer in onInit and reaches the NPC bridge.
for _, role in ipairs({"HOST","JOINER"}) do
    local s=fixture(role,true)
    s.init()
    s.observeNpc({IsAttached=function() return false end})
    s.tick(3)
    assert(s.npcReads > 0 and #s.activations == 1)
end

-- Disabled mode ignores even real attachment notifications on both roles.
for _, role in ipairs({"HOST","JOINER"}) do
    local s=fixture(role,false)
    s.init()
    s.observeNpc({IsAttached=function() error("disabled NPC was inspected") end})
    s.tick()
    assert(s.npcReads == 0 and s.npcOffers == 0 and s.npcSpawns == 0)
end
-- The actual entrypoint supplies one timestamp and explicit pause state to NPC
-- retirement even after unload or a latched bridge failure. Unknown is not false.
do
    local s=fixture("JOINER",false); s.init(); s.tick()
    local first=s.npcClocks[#s.npcClocks]
    assert(first.paused==false and first.now>0,"normal NPC pump is explicitly unpaused")
    s.paused=true; s.tick()
    local paused=s.npcClocks[#s.npcClocks]
    assert(paused.paused==true and paused.now>first.now)
    s.pauseUnavailable=true; s.tick()
    assert(s.npcClocks[#s.npcClocks].paused==nil,"unknown pause must reach fail-closed adapter")
    s.pauseUnavailable=false; s.paused=false; s.hasPlayer=false; s.tick(3)
    local unloaded=s.npcClocks[#s.npcClocks]
    assert(unloaded.now>paused.now and unloaded.paused==false,"unloaded game still pumps retained NPCs")
    s.hasPlayer=true; s.bridgeFailure=true; s.rawTick(1/60)
    local failed=s.npcClocks[#s.npcClocks]
    s.rawTick(1/60)
    assert(s.npcClocks[#s.npcClocks].now>failed.now,"latched failure still pumps NPC retirement")
end

-- A throwing handler getter must still invalidate the real dynamic adapter's
-- pending observations, on both the first failed update and latched-error ticks.
for _,phase in ipairs({"attachment","absence","early-engine-error"}) do
    local s=fixture("JOINER",false); s.init(); s.tick()
    local population=package.loaded.npc_population
    local system=Game.GetDynamicEntitySystem()
    local localId={hash="123ULL"}
    local gone,deletes=false,0
    local actor={GetEntityID=function() return localId end,IsAttached=function() return not gone end}
    function system:CreateEntity() return localId end
    function system:GetEntity() if not gone then return actor end end
    function system:IsManaged() return not gone end
    function system:IsSpawning() return false end
    function system:IsSpawned() return not gone end
    function system:DeleteEntity() deletes=deletes+1; return true end
    Game.FindEntityByID=function() if not gone then return actor end end
    TweakDB={GetRecord=function() return {} end}
    DynamicEntitySpec={new=function() return {} end}
    Vector4={new=function() return {} end}
    Quaternion={new=function() return {} end}
    local id=assert(population.spawn({entity="456ULL",record=123,x=0,y=0,z=0,yaw=0}))
    assert(not population.remove(id) and deletes==0,"one attachment sample must not delete")
    if phase=="absence" then
        s.rawTick(0.01)
        assert(not population.remove(id) and deletes==1)
        gone=true; s.rawTick(0.1)
        assert(not population.remove(id),"one absence sample must not release ownership")
    end
    local deletesBefore,pushesBefore=deletes,s.pushes
    if phase=="early-engine-error" then
        s.playerUnavailable=true
        local count=#s.npcClocks
        local before=s.npcClocks[count].now
        s.rawTick(5)
        assert(#s.npcClocks==count+1,"error before pause lookup must invalidate NPC observations")
        local sample=s.npcClocks[#s.npcClocks]
        assert(sample.paused==nil and math.abs(sample.now-before-5)<1e-9)
        assert(not population.remove(id) and deletes==0,"early engine error cannot qualify deletion")
        s.playerUnavailable=false
    end
    s.requestsUnavailable=true
    for _,delta in ipairs({5,7}) do
        local count=#s.npcClocks
        local before=s.npcClocks[count].now
        s.rawTick(delta)
        assert(#s.npcClocks>count,"getter failure must still pump NPC retirement")
        local sample=s.npcClocks[#s.npcClocks]
        assert(sample.paused==nil,"throwing handler getter supplies unknown pause")
        assert(math.abs(sample.now-before-delta)<1e-9,"failed tick advances clock by exactly one delta")
        for index=count+1,#s.npcClocks do
            assert(s.npcClocks[index].now==sample.now,"error invalidation reuses the current timestamp")
        end
        assert(not population.remove(id) and deletes==deletesBefore,"unknown interval cannot retire NPC")
        assert(s.pushes==pushesBefore,"handler failure must not continue normal session work")
    end
    s.requestsUnavailable=false
    local before=s.npcClocks[#s.npcClocks].now
    s.rawTick(0.01)
    local recovered=s.npcClocks[#s.npcClocks]
    assert(recovered.paused==false and math.abs(recovered.now-before-0.01)<1e-9)
    assert(not population.remove(id) and deletes==deletesBefore,"recovery requires fresh qualification")
    if phase~="absence" then
        s.rawTick(0.01)
        assert(not population.remove(id) and deletes==1,"second recovered observation may submit deletion")
    else
        s.rawTick(0.2)
        assert(not population.remove(id),"unknown interval cannot satisfy absence quiet time")
        s.rawTick(0.06)
        assert(population.remove(id),"fresh unpaused quiet interval can complete retirement")
    end
end

print=report
report("session_lifecycle: PASS (startup, stable Uint64 identity, replacement, unload, reconnect, NPC opt-in; " ..
    (hasFfi and "LuaJIT Uint64 cdata" or "opaque Uint64 mock") .. ")")
