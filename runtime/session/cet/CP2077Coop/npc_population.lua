-- Game-thread-only engine adapter. Do NOT replace these gates with guessed hooks.
-- acquire must reversibly suppress ONLY unassociated ambient NPCs inside the bubble,
-- including newly streamed population; preserve/restore each object's original state.
-- spawn must create a passive projection with local AI disabled BEFORE it becomes visible.
-- active=false in DynamicEntitySpec only defers spawning; it is NOT an AI-disable hook.
local M = {}
function M.available() return false, "population suppression and passive NPC projection hooks are unverified" end
function M.acquire(bubble, networkLocalIds) return false end
function M.spawn(npc) return nil end
function M.move(localId, npc) return false end
function M.remove(localId) return false end -- only adapter-owned projections, never ambient NPCs
function M.bind(entity, localId) return Game.CP2077Session_Bind(entity, localId) end
function M.unbind(entity) return Game.CP2077Session_Unbind(entity) end
function M.release() return true end -- no population was altered by this adapter
return M
