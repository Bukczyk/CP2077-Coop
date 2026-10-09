-- Exact dynamic player ownership. Codeware 1.18.0 can complete a pending
-- CreateEntity callback after an early DeleteEntity has forgotten its token.
-- Never delete before stable attachment, and never treat empty tags as proof.
-- Called only on the game thread; no protocol, session or tag-wide mutations.
local Lifetime = {}
Lifetime.__index = Lifetime
local MAX_ATTEMPTS, RETRY_DELAY, WARNING_AGE, QUIET_PERIOD = 3, 0.5, 3, 0.25

local function key(id)
    if id == nil or type(id) == "number" then return nil end
    local ok, hash = pcall(function() return id.hash end)
    if not ok or hash == nil or type(hash) == "number" then return nil end
    local text = tostring(hash):gsub("[uUlL]+$", "")
    if not text:match("^[1-9][0-9]*$") or #text > 20
        or (#text == 20 and text > "18446744073709551615") then return nil end
    return text
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Lifetime.new(id, log, releaseCallback)
    assert(key(id), "player lifetime requires an exact nonzero EntityID")
    assert(log == nil or type(log) == "function", "invalid player lifetime logger")
    assert(releaseCallback == nil or type(releaseCallback) == "function", "invalid player lifetime release")
    return setmetatable({id=id, key=key(id), log=log, releaseCallback=releaseCallback,
        status="owned", retiring=false, done=false, blocked=false, age=0,
        seenAttached=false, stable=0, deleteIssued=false, deleteAttempts=0,
        releaseAttempts=0, emitted={}}, Lifetime)
end

function Lifetime:_status(status, blocked)
    self.status, self.blocked = status, blocked == true
    -- A stalled or alternating engine observation must not flood the log.
    if not self.emitted[status] then
        self.emitted[status] = true
        if self.log then pcall(self.log, "actor=" .. self.key .. " status=" .. status) end
    end
end

function Lifetime:_find()
    local actor = Game.FindEntityByID(self.id)
    if actor ~= nil and key(actor:GetEntityID()) ~= self.key then
        error("actor_identity_mismatch")
    end
    return actor
end

function Lifetime:actor()
    if self.done then return nil end
    local ok, actor = pcall(self._find, self)
    if not ok then
        self.stable, self.stableAt, self.absentSince = 0, nil, nil
        self:_status("actor_observation_error", true)
        return nil
    end
    return actor
end

function Lifetime:retire()
    if not self.retiring then
        self.retiring = true
        if not self.done then self:_status("retirement_pending") end
    end
    return self.done
end

function Lifetime:_observe()
    local system = Game.GetDynamicEntitySystem()
    if system == nil or not system:IsReady() then return nil end
    local actor = self:_find()
    local populationActor = system:GetEntity(self.id)
    if populationActor ~= nil and key(populationActor:GetEntityID()) ~= self.key then
        error("population_identity_mismatch")
    end
    local attached = actor ~= nil and actor:IsAttached()
    local managed, spawning, spawned = system:IsManaged(self.id),
        system:IsSpawning(self.id), system:IsSpawned(self.id)
    if type(attached) ~= "boolean" or type(managed) ~= "boolean"
        or type(spawning) ~= "boolean" or type(spawned) ~= "boolean" then
        error("invalid_lifetime_observation")
    end
    return {system=system, actor=actor, populationActor=populationActor,
        attached=attached, managed=managed, spawning=spawning, spawned=spawned}
end

function Lifetime:pump(now, paused)
    if self.done then return true end
    if not finite(now) or (self.lastNow ~= nil and now < self.lastNow) then
        self:_status("invalid_clock", true)
        self.stable, self.stableAt, self.absentSince = 0, nil, nil
        return false
    end
    if paused ~= nil and type(paused) ~= "boolean" then
        self.stable, self.stableAt, self.absentSince = 0, nil, nil
        self:_status("invalid_pause", true)
        return false
    end
    paused = paused == true
    if self.lastNow ~= nil and not paused and not self.wasPaused then
        self.age = self.age + now - self.lastNow
    end
    self.lastNow, self.wasPaused = now, paused
    if not self.retiring then return false end
    if self.retiredAt == nil then self.retiredAt = self.age end

    local ok, observation = pcall(self._observe, self)
    if not ok or observation == nil then
        self.stable, self.stableAt, self.absentSince = 0, nil, nil
        self:_status(ok and "manager_unavailable" or "observation_error", true)
        return false
    end
    local o = observation
    if o.attached then self.seenAttached = true end
    if paused then
        self.stable, self.stableAt, self.absentSince = 0, nil, nil
        self:_status("retirement_paused", self.blocked)
        return false
    end

    if self.deleteIssued then
        local absent = o.actor == nil and o.populationActor == nil
            and not o.attached and not o.managed and not o.spawning and not o.spawned
        if absent then
            self.absentSince = self.absentSince or self.age
            if self.seenAttached and self.age - self.absentSince >= QUIET_PERIOD then
                self.done = true
                self:_status("retired")
                return true
            end
            self:_status("absence_observation_pending")
        else
            self.absentSince = nil
            self:_status(self.age - self.retiredAt >= WARNING_AGE
                and "retirement_unconfirmed" or "despawn_pending",
                self.age - self.retiredAt >= WARNING_AGE)
        end
        return false
    end

    -- Neither an absent actor nor IsSpawning=false means the CreateStub callback
    -- finished. Keep a canceled pending ID until its exact attached actor exists.
    local qualified = o.attached and o.managed and o.spawned and not o.spawning
    if not qualified then
        self.stable, self.stableAt = 0, nil
        local reason = not o.managed and "ownership_unconfirmed" or "spawn_pending"
        if self.age - self.retiredAt >= WARNING_AGE then reason = "spawn_retirement_unconfirmed" end
        self:_status(reason, not o.managed or self.age - self.retiredAt >= WARNING_AGE)
        return false
    end
    if self.stableAt ~= now then self.stable = self.stable + 1; self.stableAt = now end
    if self.stable < 2 then self:_status("attachment_observation_pending"); return false end

    if not self.released then
        if self.releaseAttempts >= MAX_ATTEMPTS then self:_status("release_unconfirmed", true); return false end
        if self.nextRelease ~= nil and self.age < self.nextRelease then return false end
        self.releaseAttempts = self.releaseAttempts + 1
        self.nextRelease = self.age + RETRY_DELAY
        local released, accepted = true, true
        if self.releaseCallback then released, accepted = pcall(self.releaseCallback) end
        if not released or accepted ~= true then self:_status("release_unconfirmed", true); return false end
        self.released = true
    end
    if self.deleteAttempts >= MAX_ATTEMPTS then self:_status("delete_unconfirmed", true); return false end
    if self.nextDelete ~= nil and self.age < self.nextDelete then return false end
    self.deleteAttempts = self.deleteAttempts + 1
    self.nextDelete = self.age + RETRY_DELAY
    local deleted, accepted = pcall(function() return o.system:DeleteEntity(self.id) end)
    if not deleted or accepted ~= true then
        self:_status(deleted and "delete_rejected" or "delete_error", true)
        return false
    end
    self.deleteIssued, self.absentSince = true, nil
    self:_status("delete_submitted")
    return false -- API acceptance is not observed removal.
end

return Lifetime
