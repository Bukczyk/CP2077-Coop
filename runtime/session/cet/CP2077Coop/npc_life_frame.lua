-- Read-only selected-NPC data from the frozen BeginFrame snapshot, game thread.
-- No actor APIs, application/replay of life outcomes, or new networking route.
local M={}
local function key(v)
    if v==nil or type(v)=="number" then return nil end
    local s=tostring(v):gsub("[uUlL]+$","")
    if s:match("^[1-9][0-9]*$") and (#s<20 or #s==20 and s<="18446744073709551615") then return s end
end
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
function M.read(entity)
    local expected=key(entity)
    if not expected then return nil end
    local ok,value=pcall(function()
        -- An older DLL has no getter. Absence/error is unknown, not Alive/Dead.
        if Game.CP2077Session_NpcLifeKnown()~=true then return nil end
        if key(Game.CP2077Session_NpcEntity())~=expected then return nil end
        local health,maxHealth=Game.CP2077Session_NpcLifeHealth(),Game.CP2077Session_NpcLifeMaxHealth()
        local status,revision=Game.CP2077Session_NpcLifeStatus(),Game.CP2077Session_NpcLifeRevision()
        if not finite(health) or not finite(maxHealth) or maxHealth<=0 or maxHealth>10000000
            or health<0 or health>maxHealth or not finite(status) or status%1~=0 or status<1 or status>3
            or not finite(revision) or revision%1~=0 or revision<1 or revision>4294967295 then return nil end
        if key(Game.CP2077Session_NpcEntity())~=expected or Game.CP2077Session_NpcLifeKnown()~=true
            or Game.CP2077Session_NpcLifeRevision()~=revision then return nil end
        return {entity=entity,health=health,maxHealth=maxHealth,status=status,revision=revision}
    end)
    return ok and value or nil
end
return M
