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
        npcReads=0, npcOffers=0, npcSpawns=0, pushes=0, ready=false,
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
        GetPlayer=function() if state.hasPlayer then return player end end,
        GetSystemRequestsHandler=function()
            return {IsPreGame=function() return state.pregame end}
        end,
        GetDynamicEntitySystem=function() return system end,
        CP2077Session_SetActive=function(value)
            state.activations[#state.activations+1]=value
        end,
        CP2077Session_PushLocal=function() state.pushes=state.pushes+1 end,
        CP2077Session_BeginFrame=function() return 0 end,
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
print=report
report("session_lifecycle: PASS (startup, stable Uint64 identity, replacement, unload, reconnect, NPC opt-in; " ..
    (hasFfi and "LuaJIT Uint64 cdata" or "opaque Uint64 mock") .. ")")
