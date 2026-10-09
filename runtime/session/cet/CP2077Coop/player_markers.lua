-- Game-thread only. Uses received transforms, never proxy positions or the
-- navigation waypoint. Uint64 identities remain opaque strings.
local M = {}; M.__index = M
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function key(v)
    if v==nil or type(v)=="number" then return nil end -- never round Uint64 identity
    local s=tostring(v):gsub("[uUlL]+$", "")
    if s:match("^%d+$") and s~="0" then return s end
end
local function valid(s)
    return type(s)=="table" and finite(s.player) and s.player>0 and s.player<=4294967295
        and s.player%1==0 and key(s.entity) and finite(s.x) and finite(s.y)
        and finite(s.z) and finite(s.yaw)
end
function M.new(report)
    return setmetatable({entries={}, owners={}, report=report or function() end}, M)
end
function M:status(e, value)
    if e.status~=value then self.report("player="..tostring(e.player).." status="..value) end
    e.status=value
end
function M:remove(e, now)
    if e.cleanupBlocked or now<(e.nextRemove or 0) then return false end
    local ok, removed=pcall(function() return e.owner:CP2077Session_RemovePlayerMarker(e.player) end)
    if ok and removed==true then return true end
    e.removeAttempts=(e.removeAttempts or 0)+1; e.nextRemove=now+1
    e.cleanupBlocked=e.removeAttempts>=3
    self:status(e,e.cleanupBlocked and "cleanup_blocked" or "cleanup_retry")
    return false
end
function M:reset(now)
    for id,e in pairs(self.entries) do
        e.retiring=true
        if self:remove(e,now) then self.entries[id]=nil end
    end
    return next(self.entries)==nil
end
function M:drain(now)
    for id,e in pairs(self.entries) do
        if e.retiring and self:remove(e,now) then self.entries[id]=nil end
    end
end
function M:recover(owner, now)
    if not finite(now) or not owner then return false end
    local ownerKey=key(owner:GetEntityID().hash)
    if not ownerKey then return false end
    -- REDscript owns handles across CET reload; remove only that script's old
    -- handles before accepting new ones. Never touch the tracked waypoint.
    local recovery=self.owners[ownerKey]
    if not recovery then recovery={attempts=0,nextTry=0}; self.owners[ownerKey]=recovery end
    if not recovery.ready then
        if recovery.attempts>=3 or now<recovery.nextTry then return false end
        local ok, cleared=pcall(function() return owner:CP2077Session_ClearPlayerMarkers() end)
        if not ok or cleared~=true then
            recovery.attempts=recovery.attempts+1; recovery.nextTry=now+1
            self.report("owner="..ownerKey.." status=reload_cleanup_failed attempt="..recovery.attempts)
            return false
        end
        recovery.ready=true
    end
    return true,ownerKey
end
function M:step(scope, owner, samples, now)
    if type(scope)~="string" then return false end
    local recovered,ownerKey=self:recover(owner,now)
    if not recovered then return false end
    local wanted, duplicates={},{}
    for _,s in ipairs(samples) do
        if valid(s) then
            if wanted[s.player] then duplicates[s.player]=true end
            wanted[s.player]=s
        end
    end
    for id in pairs(duplicates) do wanted[id]=nil end -- fail closed on conflicting identity
    for id,e in pairs(self.entries) do
        local s=wanted[id]
        if e.retiring or e.scope~=scope or e.ownerKey~=ownerKey or not s or e.entity~=key(s.entity) then
            e.retiring=true
            if self:remove(e,now) then self.entries[id]=nil end
        end
    end
    for id,s in pairs(wanted) do
        local e=self.entries[id]
        if not e then
            e={player=id,entity=key(s.entity),scope=scope,owner=owner,ownerKey=ownerKey}
            self.entries[id]=e
        end
        if not e.retiring and not e.blocked and now>=(e.nextTry or 0) then
            local ok,updated=pcall(function()
                return owner:CP2077Session_SetPlayerMarker(id,s.x,s.y,s.z,s.yaw)
            end)
            if ok and updated==true then
                e.attempts=0; e.nextTry=now+0.1 -- cap UI work at 10 Hz
                self:status(e,"position_requested") -- Void engine setter has no visual readback
            else
                e.attempts=(e.attempts or 0)+1; e.nextTry=now+1
                e.blocked=e.attempts>=3
                self:status(e,e.blocked and "update_blocked" or "update_retry")
            end
        end
    end
    return true
end
function M:diagnostics()
    local out={}
    for id,e in pairs(self.entries) do out[tostring(id)]={entity=e.entity,scope=e.scope,
        status=e.status,retiring=e.retiring==true,blocked=e.blocked==true or e.cleanupBlocked==true} end
    return out
end
return M
