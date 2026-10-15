local root = assert(arg[1], "repository root required")
local directory = root .. "/experiments/npc-appearance-observation/"
package.path = directory .. "?.lua;" .. package.path
local Observer = require("observer")
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, message or ("check " .. checks))
end
local function eq(actual, expected, message)
    check(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

-- Real init.lua callbacks and real observer logic, with native-helper-facing mocks.
-- Mock native refs are distinct from Lua wrappers, just as fresh CET wrappers can be.
local function fixture()
    local f = { callbacks = {}, logs = {}, reads = 0, captures = 0, inside = false,
        lookup = {}, paused = false, preGame = false, nativeCalls = {}, playerCalls = 0 }
    function f:read(name)
        assert(self.inside, "engine access outside onUpdate: " .. name)
        self.reads = self.reads + 1
        self.nativeCalls[name] = (self.nativeCalls[name] or 0) + 1
        if self.throwAt == name then error("injected " .. name) end
    end
    function f:newNative(id)
        local native = { id = id, opaque = {}, attached = true, npc = true,
            record = "63110975482", template = "18446744073709551614",
            path = "base/quest/secondary_characters/judy.ent", appearance = "judy_default",
            appearanceHash = "9007199254740995", color = "None", colorHash = "0" }
        self.lookup[id] = native
        return native
    end
    function f:wrapper(native)
        if not native then return nil end
        local wrapper = { native = native }
        function wrapper:GetEntityID()
            f:read("GetEntityID")
            return self.native.opaque
        end
        function wrapper:CP2077NpcAppearanceObservation_ContextIdentity(other)
            f:read("ContextIdentity")
            local n = self.native
            if not other or other.native ~= n or not n.attached or f.lookup[n.id] ~= n then return "" end
            return n.id
        end
        function wrapper:CP2077NpcAppearanceObservation_Identity(context)
            f:read("Identity")
            if f.identityCallback then f.identityCallback(self.native) end
            local n = self.native
            if not context or not context.native.attached or not n.npc or not n.attached
                or f.lookup[n.id] ~= n then return "" end
            return n.id
        end
        function wrapper:CP2077NpcAppearanceObservation_Capture(context, expected)
            f:read("Capture")
            f.captures = f.captures + 1
            local n, c = self.native, context.native
            eq(expected, n.opaque, "opaque EntityID forwarded unchanged")
            if not n.npc then return { valid = false, reason = "unsupported_root" } end
            if not n.attached or f.lookup[n.id] ~= n then return { valid = false, reason = "target_unavailable" } end
            local raw = { valid = true, reason = "captured", contextDecimal = c.id,
                entityDecimal = n.id, recordDecimal = n.record, templateHash = n.template,
                templatePath = n.path, appearance = n.appearance, appearanceHash = n.appearanceHash,
                color = n.color, colorHash = n.colorHash }
            if f.captureCallback then f.captureCallback(n, raw) end
            -- Emulates the verified helper contract, not proof of native execution.
            if f.lookup[n.id] ~= n or not n.attached or f.lookup[c.id] ~= c or not c.attached
                or n.record ~= raw.recordDecimal or n.template ~= raw.templateHash
                or n.appearance ~= raw.appearance or n.color ~= raw.color then
                return { valid = false, reason = "incoherent_capture" }
            end
            if f.rawTransform then return f.rawTransform(raw) end
            return raw
        end
        if f.omitHelper then wrapper[f.omitHelper] = nil end
        return wrapper
    end
    f.player = f:newNative("9007199254740993")
    f.target = f:newNative("18446744073709551615")
    f.game = {
        GetSystemRequestsHandler = function()
            f:read("GetSystemRequestsHandler")
            if f.missingRequests then return nil end
            return {
                IsGamePaused = function() f:read("IsGamePaused"); return f.paused end,
                IsPreGame = function() f:read("IsPreGame"); return f.preGame end,
            }
        end,
        GetPlayer = function()
            f:read("GetPlayer")
            f.playerCalls = f.playerCalls + 1
            if f.playerCallback then f.playerCallback(f.playerCalls) end
            return f:wrapper(f.player) -- Deliberately fresh Lua wrapper on every read.
        end,
    }
    local oldRegister, oldPrint, oldGame = registerForEvent, print, Game
    registerForEvent = function(name, callback) f.callbacks[name] = callback end
    print = function(line) f.logs[#f.logs + 1] = line end
    Game = f.game
    f.api = assert(loadfile(directory .. "init.lua"))()
    registerForEvent, print, Game = oldRegister, oldPrint, oldGame
    function f:step(dt)
        local previous = Game
        Game, self.inside = self.game, true
        local ok, err = pcall(self.callbacks.onUpdate, dt == nil and 0.016 or dt)
        self.inside, Game = false, previous
        assert(ok, err)
    end
    function f:request(label, native) return self.api.request(label or "npc", self:wrapper(native or self.target)) end
    function f:status(label) return self.api.status(label or "npc") end
    return f
end

do
    local f = fixture()
    eq(f.reads, 0, "loading is inert")
    f:step(); eq(f.reads, 0, "idle callback is inert")
    local queued, state, ticket = f:request()
    check(queued); eq(state, "queued"); eq(ticket, 1); eq(f.reads, 0, "request does not read engine")
    eq(f:status().valid, false); eq(f:status().reason, "queued")
    f:step()
    local s = f:status()
    check(s.valid); check(s.historical); eq(s.visualQualified, false)
    eq(s.observed.entityId, "18446744073709551615")
    eq(s.observed.contextId, "9007199254740993")
    eq(s.observed.appearanceHash, "9007199254740995")
    eq(s.observed.color, "None"); eq(s.observed.colorHash, "0")
    eq(type(s.observed.entityId), "string")
    s.observed.entityId = "changed"; s.valid = false
    eq(f:status().observed.entityId, "18446744073709551615", "copied cached tuple")
    local all = f.api.status(); all.targets.npc.observed.appearance = "changed"
    eq(f:status().observed.appearance, "judy_default", "nested snapshot immutable")
    local frame = f:status().frame
    f.target.appearance = "later_appearance"
    f:step()
    check(f:status().valid, "fresh Lua player wrappers preserve native scope")
    eq(f.captures, 1, "no repeated appearance capture")
    eq(f:status().frame, frame, "historical capture frame preserved")
    eq(f:status().observed.appearance, "judy_default", "one-shot observation is historical")
    f:request(); f:step(); eq(f.captures, 2); eq(f:status().observed.appearance, "later_appearance")
end

do
    local f = fixture()
    local second = f:newNative("9007199254740997")
    f:request(); local ok, reason, ticket = f:request("npc", second)
    check(ok); eq(reason, "coalesced"); eq(ticket, 2)
    f:step(); eq(f.captures, 1); eq(f:status().observed.entityId, second.id)
    f:request("other"); f:step(); check(f:status("other").valid); check(f:status().valid)
    f.lookup[second.id] = f:newNative(second.id)
    f:step(); eq(f:status().reason, "target_identity_lost"); check(f:status("other").valid)
end

do
    local f = fixture()
    for i = 1, 8 do check(f:request("npc" .. i)) end
    local ok, reason = f:request("ninth")
    eq(ok, false); eq(reason, "capacity"); eq(f.reads, 0)
    for _, label in ipairs({ "", "white space", "line\nbreak", string.rep("a", 49) }) do
        local accepted, failure = f:request(label)
        eq(accepted, false); eq(failure, "invalid_label")
    end
    for _, ref in ipairs({ false, 123, "EntityID(1)", function() end }) do
        local accepted, failure = f.api.request("bad", ref)
        eq(accepted, false); eq(failure, "invalid_target_reference")
    end
    eq(f.api.request("bad", nil), false)
    f:step(); eq(f.captures, 8)
    f.api.reset(); eq(f:status("npc1").reason, "reset_pending")
    eq(f.api.request("fresh", f:wrapper(f.target)), false)
    local reads = f.reads
    f:step(); eq(f.reads, reads, "reset performs no engine reads")
    eq(f.api.status().scope, 2); eq(f:status("npc1").reason, "not_requested")
    check(f:request("fresh")); f:step(); check(f:status("fresh").valid)
end

local contextFaults = {
    { "paused", function(f) f.paused = true end, "paused" },
    { "unknown pause", function(f) f.paused = nil end, "context_unknown" },
    { "numeric pause", function(f) f.paused = 0 end, "context_unknown" },
    { "pregame", function(f) f.preGame = true end, "unloaded" },
    { "unknown pregame", function(f) f.preGame = nil end, "context_unknown" },
    { "unloaded", function(f) f.player = nil end, "unloaded" },
    { "missing requests", function(f) f.missingRequests = true end, "context_unavailable" },
    { "detached player", function(f) f.player.attached = false end, "context_unavailable" },
    { "player replacement same ID", function(f) f.player = f:newNative(f.player.id) end, "context_changed" },
    { "player replacement new ID", function(f) f.player = f:newNative("9007199254740999") end, "context_changed" },
}
for _, case in ipairs(contextFaults) do
    local f = fixture(); f:request(); f:step(); check(f:status().valid)
    case[2](f); f:step()
    eq(f:status().valid, false, case[1]); eq(f:status().reason, case[3], case[1])
    eq(f:status().observed, nil, "invalidated tuple removed")
    eq(f.api.status().scope, 2)
    f:step(); eq(f.api.status().scope, 2, "no repeated invalidation spam")
end

for _, getter in ipairs({ "GetSystemRequestsHandler", "IsGamePaused", "IsPreGame", "GetPlayer", "ContextIdentity" }) do
    local f = fixture(); f:request(); f:step(); f.throwAt = getter; f:step()
    eq(f:status().valid, false, getter); eq(f:status().reason, "context_read_failed")
    f.throwAt = nil; f:step(); eq(f.captures, 1, "no automatic replay")
    f:request(); f:step(); check(f:status().valid, "explicit retry after context recovery")
end

for _, getter in ipairs({ "GetEntityID", "Identity", "Capture" }) do
    local f = fixture(); f.throwAt = getter; f:request(); f:step()
    eq(f:status().valid, false, getter); eq(f:status().reason, "engine_read_failed")
    f.throwAt = nil; f:request(); f:step(); check(f:status().valid)
end
for _, helper in ipairs({ "CP2077NpcAppearanceObservation_Identity", "CP2077NpcAppearanceObservation_Capture" }) do
    local f = fixture(); f.omitHelper = helper; f:request(); f:step()
    eq(f:status().valid, false); eq(f:status().reason, "engine_read_failed")
end
do
    local f = fixture(); f.omitHelper = "CP2077NpcAppearanceObservation_ContextIdentity"
    f:request(); f:step(); eq(f:status().reason, "context_read_failed")
end

for _, change in ipairs({
    function(f) f.target.attached = false end,
    function(f) f.lookup[f.target.id] = f:newNative(f.target.id) end,
}) do
    local f = fixture(); f:request(); change(f); f:step()
    eq(f:status().valid, false); eq(f:status().reason, "target_unavailable")
end
do
    local f = fixture(); f.target.npc = false; f:request(); f:step()
    eq(f:status().reason, "unsupported_root"); eq(f:status().observed, nil)
end

for _, change in ipairs({
    function(f, n) n.record = "2" end,
    function(f, n) n.template = "3" end,
    function(f, n) n.appearance = "other" end,
    function(f, n) n.color = "other" end,
    function(f, n) n.attached = false end,
    function(f, n) f.lookup[n.id] = f:newNative(n.id) end,
}) do
    local f = fixture(); f.captureCallback = function(n) change(f, n) end
    f:request(); f:step(); eq(f:status().valid, false); eq(f:status().reason, "incoherent_capture")
end

local malformed = {
    function(r) r.valid = 1 end,
    function(r) r.entityDecimal = "9007199254740992" end,
    function(r) r.contextDecimal = "9007199254740992" end,
    function(r) r.recordDecimal = 63110975482 end,
    function(r) r.recordDecimal = "0" end,
    function(r) r.recordDecimal = "01" end,
    function(r) r.templateHash = "0" end,
    function(r) r.templateHash = "18446744073709551616" end,
    function(r) r.templateHash = "123ULL" end,
    function(r) r.appearanceHash = nil end,
    function(r) r.appearanceHash = "-1" end,
    function(r) r.appearance = nil end,
    function(r) r.appearance = {} end,
    function(r) r.color = nil end,
    function(r) r.colorHash = "1.0" end,
    function(r) r.templatePath = nil end,
    function(r) r.templatePath = string.rep("p", 2049) end,
    function(r) r.appearance = string.rep("a", 257) end,
}
for _, mutate in ipairs(malformed) do
    local f = fixture(); f.rawTransform = function(raw) mutate(raw); return raw end
    f:request(); f:step(); eq(f:status().valid, false); eq(f:status().observed, nil)
end
for _, raw in ipairs({ false, "unexpected", 5 }) do
    local f = fixture(); f.rawTransform = function() return raw end
    f:request(); f:step(); eq(f:status().valid, false)
end
do
    local f = fixture(); f.rawTransform = function() return nil end
    f:request(); f:step(); eq(f:status().reason, "invalid_native_sample")
end
for _, name in ipairs({ "None", "", "alternate_appearance" }) do
    local f = fixture(); f.target.appearance = name; f.target.color = name
    f.target.appearanceHash, f.target.colorHash, f.target.path = "0", "0", ""
    f:request(); f:step(); local s = f:status(); check(s.valid)
    eq(s.observed.appearance, name); eq(s.observed.color, name)
    eq(s.observed.appearanceNameAvailable, name ~= "")
    eq(s.observed.templatePathAvailable, false); eq(s.observed.templateHash, f.target.template)
end

do
    local f = fixture(); local other = f:newNative("9007199254740997")
    f.captureCallback = function(n)
        if n == f.target then f.api.request("npc", f:wrapper(other)) end
    end
    f:request(); f:step(); eq(f:status().reason, "queued"); eq(f:status().ticket, 2)
    eq(f:status().observed, nil, "old result cannot publish under replacement ticket")
    f.captureCallback = nil; f:step(); check(f:status().valid)
    eq(f:status().observed.entityId, other.id)
end
for _, action in ipairs({ "reset", "shutdown" }) do
    local f = fixture()
    f.captureCallback = function()
        if action == "reset" then f.api.reset() else f.callbacks.onShutdown() end
    end
    f:request(); f:step(); eq(f:status().valid, false, "capture invalidated during " .. action)
    if action == "reset" then
        eq(f:status().reason, "reset_pending"); f:step(); eq(f:status().reason, "not_requested")
    else check(f.api.status().closed); eq(f.api.request("npc", f:wrapper(f.target)), false) end
end

do
    local f = fixture()
    f.playerCallback = function(n)
        if n == 2 then f.player = f:newNative(f.player.id) end
    end
    f:request(); f:step(); eq(f:status().reason, "context_changed")
end
do
    local f = fixture()
    f.captureCallback = function() f.paused = true end
    f:request(); f:step(); eq(f:status().reason, "paused")
end
do
    local f = fixture(); local calls = 0
    f.identityCallback = function(n)
        calls = calls + 1
        if calls == 2 then f.lookup[n.id] = f:newNative(n.id) end
    end
    f:request(); f:step(); eq(f:status().reason, "identity_mismatch")
end

for _, dt in ipairs({ -1, 2, math.huge, 0/0, "0.1" }) do
    local f = fixture(); f:request(); f:step(dt)
    eq(f:status().reason, "update_gap"); eq(f.captures, 0); eq(f.reads, 0)
end
do
    local f = fixture(); f:request(); f:step(0); check(f:status().valid)
    local reads = f.reads
    f.callbacks.onShutdown(); f.api.status(); f.api.reset(); f:step()
    eq(f.reads, reads, "shutdown/status/reset on closed API remain engine-free")
    eq(f.api.status().closedReason, "shutdown")
end
do
    local f = fixture()
    for i = 1, 70 do f:request(); f:step() end
    eq(#f.logs, 64); eq(f.api.status().logCount, 64)
    f.api.reset(); f:step(); f:request(); f:step()
    eq(#f.logs, 64, "reset cannot reopen log flood")
end

-- Direct counter boundary setup complements real-entrypoint tests without billions of frames.
do
    local o = Observer.new({ getGame = function() error("must remain inert") end })
    o.ticket = 2147483647
    local ok, reason = o:request("npc", {})
    eq(ok, false); eq(reason, "counter_exhausted"); eq(o.ticket, 2147483647)
    o.scope = 2147483647
    eq(o:reset(), false); o:_invalidate("paused")
    check(o:status().closed); eq(o:status().scope, 2147483647)
    local frameBound = Observer.new({ getGame = function() error("must remain inert") end })
    frameBound.frame = 2147483647; frameBound:update(0.016)
    eq(frameBound:status().closedReason, "counter_exhausted")
end

local ffiOk, ffi = pcall(require, "ffi")
if ffiOk then
    local f = fixture()
    f.target.opaque = ffi.new("uint64_t", 9007199254740992) + ffi.new("uint64_t", 1)
    f:request(); f:step(); check(f:status().valid)
    eq(f:status().observed.entityId, "18446744073709551615", "native-produced ID independent of opaque wrapper shape")
end

print("npc_appearance_observation_tests: " .. checks .. " checks passed")
