-- Opt-in render-only adapter. Caller owns entity identity, authority, event order,
-- deduplication, terminal death and cleanup. Never infer approval from this module.
local M = {}

M.template = "base\\cp2077coop\\entities\\cp2077coop_networkhumanoid_encounter.ent"
M.clipDuration = { reaction = 0.466666669, hit = 0.466666669, death = 1.93333328 }

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function queue(entity, key, value)
    -- CET NewObject resolves native RTTI names, not REDscript aliases.
    local event = NewObject("entAnimInputSetterFloat")
    if not event then error("entAnimInputSetterFloat unavailable") end
    event.key = CName.new(key)
    event.value = value
    entity:QueueEvent(event)
end

-- progress is normalized clip progress [0,1], not seconds. A repeated identical
-- call samples the same reaction/death pose; it does not restart a one-shot clip.
-- Restore an accepted dead entity with apply(entity, "death", 1). On a completed
-- non-lethal reaction the caller must explicitly select "idle" again.
function M.apply(entity, kind, progress)
    if entity == nil then return false, "entity_unavailable" end
    local phase = ({idle = 0, reaction = 1, hit = 1, death = 2})[kind]
    if phase == nil then return false, "unsupported_kind" end
    if not finite(progress) or progress < 0 or progress > 1 then
        return false, "invalid_progress"
    end
    local ok, reason = pcall(function()
        -- Queue progress before selecting the branch. QueueEvent has no receipt;
        -- exceptions can leave a partial pair and callers must handle that case.
        if phase == 1 then queue(entity, "cp_coop_hit_progress", progress) end
        if kind == "death" then queue(entity, "cp_coop_death_progress", progress) end
        queue(entity, "cp_coop_phase", phase)
    end)
    if not ok then return false, "queue_failed_or_partial: " .. tostring(reason) end
    return true, "queued_not_observed"
end

return M
