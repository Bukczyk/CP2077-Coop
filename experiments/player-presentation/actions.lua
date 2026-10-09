-- Local game-thread experiment. No transport, admission, gameplay, or wire codec.
-- The fixture owner supplies an exact per-player resolver and a fresh scope token
-- for every session/epoch/membership generation. Records remain native TweakDBID
-- values; serial is a local monotonic counter, never a protocol sequence number.
local M = {}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function key(v) return type(v)=="string" and #v>0 and #v<=256 end
local function integer(v, max) return finite(v) and v>=1 and v<=max and v==math.floor(v) end
local function clone(t) local c={}; for k,v in pairs(t or {}) do c[k]=v end; return c end
local function identity(a)
    local hash=a:GetEntityID().hash
    -- Native Uint64 remains opaque. A Lua number may already have lost bits.
    if hash==nil or type(hash)=="number" then return nil end
    local id=tostring(hash)
    if id=="0" or id=="0ULL" then return nil end
    return id
end
local function supported(record) return CP2077PlayerPresentation.SupportedWeapon(record) end

-- This captures held aim intent, not sight alignment, target, pitch or animation.
function M.capture(player, validate)
    local ok, state = pcall(function()
        if not player:IsAttached() or not player:CP2077Session_ActionCaptureReady() then return nil end
        return {crouched=player:CP2077Session_IsCrouched(), aiming=player:CP2077Session_IsAiming(),
            weapon=player:CP2077Session_HeldWeapon(), drawn=player:CP2077Session_HasPresentationWeapon()}
    end)
    if not ok or not state then return nil,"capture_unavailable" end
    if state.drawn then
        local valid, value = pcall(validate or supported, state.weapon)
        if not valid or value~=true then return nil,"unsupported_weapon" end
    end
    return state,"captured"
end

function M.new(config)
    config=config or {}
    local capacity, timeout, maxAge=config.capacity or 64,config.timeout or 2,config.maxAge or 5
    if not integer(capacity,4096) or not finite(timeout) or timeout<=0 or timeout>30
        or not finite(maxAge) or maxAge<timeout or maxAge>60 or type(config.resolve)~="function"
        or (config.supported~=nil and type(config.supported)~="function") then return nil,"invalid_config" end
    local resolve, validate=config.resolve,config.supported or supported
    local entries, owners, count, scope, clock, busy={}, {}, 0, nil, 0, false
    local self={}
    local function invoke(fn,...)
        busy=true; local ok,a,b=pcall(fn,...); busy=false; return ok,a,b
    end
    local function context(s,now)
        if busy then return false,"callback_busy" end
        if scope==nil or s~=scope then return false,"wrong_scope" end
        if not finite(now) or now<clock then return false,"invalid_time" end
        clock=now; return true
    end
    local function fault(e,reason) e.status,e.reason="failed",reason; return "failed",reason end
    local function release(e)
        if e.uncertain then return false end
        if e.command~=nil then
            local ok, stopped=invoke(function()
                if identity(e.actor)~=e.localKey then return false end
                return e.actor:CP2077Session_StopPresentation(e.command)
            end)
            if not ok or stopped~=true then fault(e,"cancellation_unconfirmed"); return false end
        end
        e.command=nil; return true
    end
    function self:reset(nextScope,now)
        if busy then return false,"callback_busy" end
        if not key(nextScope) or nextScope==scope then return false,"invalid_scope" end
        if not finite(now) or now<clock then return false,"invalid_time" end
        for _,e in pairs(entries) do if not release(e) then return false,e.reason end end
        entries,owners,count,scope,clock={},{},0,nextScope,now
        return true,"reset"
    end
    function self:stage(s,entity,serial,state,now)
        local ok,reason=context(s,now); if not ok then return false,reason end
        if not key(entity) or not integer(serial,9007199254740991) or type(state)~="table"
            or type(state.crouched)~="boolean" or type(state.aiming)~="boolean"
            or type(state.drawn)~="boolean" or state.weapon==nil then return false,"invalid_state" end
        local e=entries[entity]
        if e and serial<=e.serial then return false,"stale_serial" end
        if state.drawn then
            local valid,value=invoke(validate,state.weapon)
            if not valid or value~=true then return false,"unsupported_weapon" end
        end
        if not e then
            if count>=capacity then return false,"capacity" end
            e={serial=0,active=0,last=now,status="queued"}; entries[entity]=e; count=count+1
        end
        if e.status=="failed" then return false,e.reason end
        if not e.paused then e.active=e.active+now-e.last end
        e.last=now
        -- Latest state is bounded to one slot; admitted state/deadline stays fixed.
        e.latest={crouched=state.crouched,aiming=state.aiming,drawn=state.drawn,weapon=state.weapon}
        e.serial,e.freshAt=serial,e.active
        e.status,e.reason="queued",nil
        e.aim=state.aiming and "unsupported" or "not_requested"
        return true,"queued"
    end
    function self:bind(s,entity,actor,now)
        local ok,reason=context(s,now); if not ok then return false,reason end
        local e=entries[entity]; if not e then return false,"unknown_entity" end
        if e.actor then return false,"already_bound" end
        local valid,id=invoke(identity,actor)
        if not valid or not key(id) then return false,"invalid_actor" end
        if owners[id] then return false,"actor_owned" end
        local found,current=invoke(resolve,entity)
        local mapped,currentId=invoke(identity,current)
        if not found or not mapped or currentId~=id then return false,"wrong_mapping" end
        e.actor,e.localKey=actor,id; owners[id]=entity
        return true,"bound"
    end
    function self:unbind(s,entity,localKey,now)
        local ok,reason=context(s,now); if not ok then return false,reason end
        local e=entries[entity]
        if not key(localKey) or not e or not e.actor or e.localKey~=localKey then return false,"wrong_projection" end
        if not release(e) then return false,e.reason end
        owners[e.localKey]=nil
        e.actor,e.localKey,e.latest,e.admitted=nil,nil,nil,nil
        e.status,e.reason="queued","awaiting_fresh_state"
        -- Keep serial tombstone/capacity until scope reset; delayed old state
        -- cannot reappear on a replacement. No arbitrary eviction of ownership.
        return true,"unbound"
    end
    function self:step(s,entity,now,paused)
        local ok,reason=context(s,now); if not ok then return "failed",reason end
        local e=entries[entity]; if not e then return "failed","unknown_entity" end
        if not paused and not e.paused then e.active=e.active+now-e.last end
        e.last,e.paused=now,paused==true
        if e.status=="failed" then return "failed",e.reason end
        if paused then return "queued","paused" end
        if not e.latest then return "queued","awaiting_fresh_state" end
        if e.active-e.freshAt>=maxAge then
            if not release(e) then return "failed",e.reason end
            return fault(e,"state_expired")
        end
        if not e.actor then return "queued","awaiting_projection" end
        local valid,current=invoke(resolve,entity)
        local mapped,currentId=invoke(identity,current)
        local exact,id=invoke(identity,e.actor)
        if not valid or not mapped or currentId~=e.localKey or not exact or id~=e.localKey then
            -- Do not mutate a replacement actor, even to cancel old work.
            return fault(e,"mapping_changed")
        end
        local ready,value=invoke(function() return e.actor:IsAttached() and e.actor:CP2077Session_PoseReady() end)
        if not ready or value~=true then return "queued","awaiting_attachment" end
        local target=e.admitted or e.latest
        local read,stance,weapon=invoke(function()
            return e.actor:CP2077Session_StanceMatches(target.crouched),
                e.actor:CP2077Session_HeldPresentationMatches(target.weapon,target.drawn)
        end)
        if not read then
            if not release(e) then return "failed",e.reason end
            return fault(e,"readback_unavailable")
        end
        e.stance,e.weapon=stance==true and "observed" or "queued",weapon==true and "observed" or "queued"
        if stance==true and weapon==true then
            if not release(e) then return "failed",e.reason end
            if e.admitted then e.admitted=nil; return "queued","checking_latest" end
            e.aim=target.aiming and "unsupported" or "not_requested"
            if target.aiming then
                -- The supported fields are still observed. ADS cannot be claimed.
                e.status,e.reason="partial","ads_unavailable"; return "partial",e.reason
            end
            e.status,e.reason="observed",nil; return "observed"
        end
        if e.admitted then
            if e.active-e.submittedAt>=timeout then
                if not release(e) then return "failed",e.reason end
                return fault(e,"readback_timeout")
            end
            return "queued","awaiting_readback"
        end
        e.admitted=clone(target); e.submittedAt=e.active
        if stance~=true then
            local submitted,accepted=invoke(function() return e.actor:CP2077Session_ApplyStance(target.crouched) end)
            if not submitted or accepted~=true then return fault(e,"stance_rejected") end
        end
        if weapon~=true then
            if target.drawn then
                local inventory,hasItem,grants=invoke(function()
                    return e.actor:CP2077Session_HasPresentationItem(target.weapon),
                        e.actor:CP2077Session_PresentationGrantCount()
                end)
                if not inventory or type(hasItem)~="boolean" or not finite(grants)
                    or grants<0 or grants~=math.floor(grants) then return fault(e,"inventory_unavailable") end
                if not hasItem and grants>=8 then return fault(e,"inventory_capacity") end
            end
            local submitted,command=invoke(function() return e.actor:CP2077Session_EquipPresentation(target.weapon,target.drawn) end)
            if not submitted then e.uncertain=true; return fault(e,"submission_uncertain") end
            if command==nil or command==false then return fault(e,"equipment_rejected") end
            e.command=command
        end
        e.status="queued"; return "queued","submitted"
    end
    function self:inspect(entity)
        local e=entries[entity]; if not e then return nil end
        return {serial=e.serial,localKey=e.localKey,status=e.status,reason=e.reason,
            stance=e.stance,weapon=e.weapon,aim=e.aim,commandOwned=e.command~=nil,
            activeAge=e.freshAt and e.active-e.freshAt or nil,uncertain=e.uncertain==true}
    end
    function self:size() return count end
    return self
end
return M
