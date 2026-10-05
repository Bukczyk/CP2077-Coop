-- Network-owned NPC projection lifecycle. Position controls relevance only;
-- stable projection identity is the opaque SessionEntityId.
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
    local self = { adapter = adapter, owned = {}, identity = nil }
    local function cleanup(projection)
        if projection.bound then
            if not adapter.unbind(projection.entity) then return false end
            projection.bound = false
        end
        return adapter.remove(projection.localId)
    end
    function self:reset()
        local complete = true
        for id, projection in pairs(self.owned) do
            if cleanup(projection) then
                self.owned[id] = nil
            else
                complete = false
            end
        end
        if complete then self.identity = nil end
        return complete
    end
    function self:step(identity, bubble, npcs)
        if self.identity ~= identity then
            if not self:reset() then return false end
            self.identity = identity
        end
        local desired, any = {}, false
        for _, npc in ipairs(npcs) do
            if M.contains(bubble, npc) then
                local id = tostring(npc.entity) -- preserve Uint64 identity; never convert to Lua number
                if desired[id] then error("Duplicate SessionEntityId in NPC frame") end
                desired[id], any = npc, true
            end
        end
        if not any or not self.adapter.available() then return self:reset() and false end
        for id, projection in pairs(self.owned) do
            if not desired[id] then
                if not cleanup(projection) then return false end
                self.owned[id] = nil
            end
        end
        for id, npc in pairs(desired) do
            local projection = self.owned[id]
            if not projection then
                local localId = self.adapter.spawn(npc)
                if localId == nil then self:reset(); return false end
                projection = { entity = npc.entity, localId = localId, bound = false }
                self.owned[id] = projection
            end
            if not projection.bound then
                local bound, reason = self.adapter.bind(npc.entity, projection.localId)
                if bound == nil and reason == "pending" then
                    -- DynamicEntitySystem streams asynchronously; keep the exact returned ID.
                elseif not bound then
                    self:reset(); return false
                else
                    projection.bound = true
                end
            end
            if projection.bound and not self.adapter.move(projection.localId, npc) then
                self:reset(); return false
            end
        end
        return true
    end
    return self
end
return M
