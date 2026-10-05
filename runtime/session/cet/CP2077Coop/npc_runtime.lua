-- Session Bubble policy, deliberately independent of REDengine for mock testing.
-- Position determines relevance only. Projection identity is always SessionEntityId.
local M = {}
function M.contains(bubble, p)
    if not bubble or not bubble.radius or bubble.radius <= 0 then return false end
    for _, center in ipairs(bubble.centers or {}) do
        local x, y, z = p.x-center.x, p.y-center.y, p.z-center.z
        if x*x+y*y+z*z <= bubble.radius*bubble.radius then return true end
    end
    return false
end
function M.new(adapter)
    local self = { adapter = adapter, owned = {}, identity = nil, lease = false }
    function self:reset()
        local complete = true
        for id, projection in pairs(self.owned) do
            if self.adapter.remove(projection.localId) then
                self.adapter.unbind(projection.entity)
                self.owned[id] = nil
            else complete = false end
        end
        -- Do not restore competing ambient population while a projection remains.
        if not complete then return false end
        if self.lease and not self.adapter.release() then return false end
        self.lease, self.identity = false, nil
        return true
    end
    function self:step(identity, bubble, npcs)
        if self.identity ~= identity then
            if not self:reset() then return false end
            self.identity = identity
        end
        local desired, any = {}, false
        for _, npc in ipairs(npcs) do
            if M.contains(bubble, npc) then
                local id = tostring(npc.entity) -- keep the exact opaque Uint64, never tonumber()
                if desired[id] then error("Duplicate SessionEntityId in NPC frame") end
                desired[id], any = npc, true
            end
        end
        if not any or not self.adapter.available() then return self:reset() and false end
        -- Remove departing projections BEFORE restoring ambient population there.
        for id, projection in pairs(self.owned) do
            if not desired[id] then
                if not self.adapter.remove(projection.localId) then return false end
                self.adapter.unbind(projection.entity); self.owned[id] = nil
            end
        end
        local exclusions = {}
        for _, localId in ipairs(bubble.exclusions or {}) do exclusions[#exclusions+1] = localId end
        for _, projection in pairs(self.owned) do exclusions[#exclusions+1] = projection.localId end
        -- acquire is a transactional refresh: restores population leaving the boundary
        -- and suppresses new entrants before any network projection is shown.
        self.lease = true -- release is required even after a partially failed acquisition
        if not self.adapter.acquire(bubble, exclusions) then self:reset(); return false end
        for id, npc in pairs(desired) do
            local projection = self.owned[id]
            if not projection then
                local localId = self.adapter.spawn(npc)
                if localId ~= nil then
                    projection = { entity = npc.entity, localId = localId }
                    self.owned[id] = projection
                    if not self.adapter.bind(npc.entity, localId) then self:reset(); return false end
                end
            end
            if projection and not self.adapter.move(projection.localId, npc) then self:reset(); return false end
        end
        return true
    end
    return self
end
return M
