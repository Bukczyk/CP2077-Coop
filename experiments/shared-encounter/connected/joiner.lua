-- Opt-in CPEX1 presentation only. Native routing owns sender authentication;
-- this controller checks its supplied envelope and never applies engine damage.
-- Retained state survives local projection replacement, not a session reset.
local Codec = assert(require("connected/codec"), "Cannot load connected/codec")
local Presentation = assert(require("presentation_state"), "Cannot load presentation_state")
local M = {}

local function copyContext(c)
    return {session=c.session, epoch=c.epoch, generation=c.generation, self=c.self, host=c.host}
end
local function same(a, b)
    return a and b and a.session == b.session and a.epoch == b.epoch
        and a.generation == b.generation and a.self == b.self and a.host == b.host
end
local function identity(c)
    return type(c) == "table" and Codec.id(c.session, true) and Codec.id(c.generation, true)
        and Codec.finite(c.epoch,4294967295) and c.epoch >= 0 and c.epoch == math.floor(c.epoch)
        and Codec.finite(c.self,4294967295) and c.self >= 0 and c.self == math.floor(c.self)
        and Codec.finite(c.host,4294967295) and c.host >= 0 and c.host == math.floor(c.host)
end
local function active(c)
    return identity(c) and c.active == true and Codec.id(c.session) and Codec.id(c.generation)
        and c.epoch > 0 and c.self > 0 and c.host > 0 and c.self ~= c.host
end
local function localKey(k)
    return type(k) == "string" and k ~= "" and #k <= 256
end
local function older(a, b)
    return #a < #b or (#a == #b and a < b)
end
local function copy(t)
    if not t then return nil end
    local result = {}; for k,v in pairs(t) do result[k] = v end
    return result
end

function M.new(config)
    if type(config) ~= "table" then return nil,"invalid_config" end
    for _,name in ipairs({"context","resolve","apply","requestTarget"}) do
        if type(config[name]) ~= "function" then return nil,"missing_" .. name end
    end
    local capacity = config.capacity == nil and 16 or config.capacity
    local eventCapacity = config.eventCapacity == nil and 64 or config.eventCapacity
    if not Codec.integer(capacity,4096) or not Codec.integer(eventCapacity,65536) then
        return nil,"invalid_limits"
    end
    -- Copy callbacks: changing config after construction cannot alter this policy.
    local getContext,resolve,applyFrame,requestTarget = config.context,config.resolve,config.apply,config.requestTarget
    local reactionDuration,deathDuration = config.reactionDuration,config.deathDuration
    local scope,token,clock,busy = nil,nil,0,false
    local entries,seen,count,eventCount = {},{},0,0
    local controller,visual = {},nil
    local function invoke(callback,...)
        busy = true
        local ok,value = pcall(callback,...)
        busy = false
        return ok,value
    end
    local function current()
        local ok,c = invoke(getContext)
        return ok and c or nil
    end
    local function clear(c,now)
        scope = c and copyContext(c) or nil
        entries,seen,count,eventCount = {},{},0,0
        token = {}
        visual:reset(token,now)
    end
    local function synchronize(now)
        if busy then return nil,"callback_busy" end
        if not Codec.finite(now,1e15) or now < 0 or now < clock then return nil,"invalid_time" end
        local c = current()
        if not identity(c) then
            if scope then clear(nil,now) end
            clock = now
            return nil,"inactive"
        end
        if not same(scope,c) then clear(c,now) end
        clock = now
        if not active(c) then return nil,"inactive" end
        return copyContext(c)
    end
    local function stillCurrent(c)
        local value = current()
        return active(value) and same(c,value)
    end
    local function mapped(target)
        local ok,k = invoke(resolve,target)
        if not ok then return nil,"mapping_unavailable" end
        if k == nil then return nil,"mapping_missing" end
        if not localKey(k) then return nil,"invalid_mapping" end
        return k
    end
    visual = Presentation.new({capacity=capacity,maxSerial=eventCapacity,
        reactionDuration=reactionDuration,deathDuration=deathDuration,
        resolve=function(target)
            if not stillCurrent(scope) then return nil end
            return mapped(target)
        end,
        apply=function(frame)
            if not stillCurrent(scope) then return false end
            local entry = entries[frame.sessionKey]
            if not entry then return false end
            frame.health,frame.maximum,frame.life,frame.hostEvent = entry.health,entry.maximum,entry.life,entry.hostEvent
            local ok,accepted = invoke(applyFrame,frame)
            return ok and accepted == true and stillCurrent(scope)
        end})
    if not visual then return nil,"invalid_config" end

    function controller:accept(event,now)
        local c,reason = synchronize(now); if not c then return false,reason end
        if type(event) ~= "table" or event.type ~= "outcome"
            or not Codec.id(event.hostEvent) or not Codec.id(event.requestEvent)
            or not Codec.integer(event.requester,4294967295)
            or not Codec.integer(event.host,4294967295) then return false,"invalid_envelope" end
        if event.session ~= c.session or event.epoch ~= c.epoch or event.generation ~= c.generation then
            return false,"wrong_scope"
        end
        if event.host ~= c.host then return false,"authority" end
        if event.kind ~= Codec.kind then return false,"unsupported_kind" end
        if event.disposition ~= 2 or event.reason ~= 0 then return false,"rejected_outcome" end
        local result = Codec.readResult(event.body)
        if not result or (result.life == "alive" and result.health <= 0) then return false,"invalid_result" end
        if result.life == "defeated" then return false,"unsupported_life" end
        local priorEvent = seen[event.hostEvent]
        local body = event.body:lower()
        if priorEvent then
            if priorEvent.requester ~= event.requester or priorEvent.requestEvent ~= event.requestEvent
                or priorEvent.body ~= body then return false,"conflicting_event" end
            return false,"duplicate"
        end
        local entry = entries[result.target]
        if entry and older(event.hostEvent,entry.hostEvent) then return false,"stale_event" end
        if entry and entry.life == "dead" and result.life ~= "dead" then return false,"terminal_death" end
        if event.requester == c.self then
            local ok,target = invoke(requestTarget,event.requestEvent)
            if not ok or target ~= result.target then return false,"uncorrelated_request" end
        end
        if not entry and count >= capacity then return false,"full" end
        if eventCount >= eventCapacity then return false,"event_full" end
        local resolved = mapped(result.target)
        if not stillCurrent(c) then
            synchronize(now)
            return false,"wrong_scope"
        end
        -- A first result can animate a currently existing body. A replacement or
        -- absent body receives a final state; old transient hits never replay.
        local animateLocal = resolved and ((not entry) or entry.localKey == resolved) and resolved or nil
        if not entry then
            entry = {}; entries[result.target] = entry; count = count + 1
        end
        eventCount = eventCount + 1
        seen[event.hostEvent] = {requester=event.requester,requestEvent=event.requestEvent,body=body}
        entry.health,entry.maximum,entry.life,entry.hostEvent = result.health,result.maximum,result.life,event.hostEvent
        entry.serial,entry.animateLocal,entry.needsState = eventCount,animateLocal,true
        entry.acceptedAt = now
        entry.pending,entry.lastError = true,nil
        return true,"accepted"
    end

    function controller:step(now)
        local c,reason = synchronize(now); if not c then return false,reason end
        local complete,firstReason = true,nil
        for target,entry in pairs(entries) do
            local k,why = mapped(target)
            if not stillCurrent(c) then synchronize(now); return false,"wrong_scope" end
            if entry.localKey and entry.localKey ~= k then
                local ok,unbound = visual:unbind(token,target,entry.localKey,now)
                if not ok then entry.lastError=unbound; return false,unbound end
                entry.localKey,entry.pose,entry.needsState,entry.animateLocal = nil,nil,true,nil
            end
            if not k then
                entry.pending,entry.lastError = true,why
                complete,firstReason = false,firstReason or why
            else
                local ok,status = visual:bind(token,target,k,now)
                if ok then
                    entry.localKey = k
                    if entry.needsState then
                        local state = visual:inspect(token,target)
                        local duration = entry.life == "dead" and deathDuration or reactionDuration
                        if entry.animateLocal == k and not state.dead and now - entry.acceptedAt < duration then
                            ok,status = visual:stage(token,target,k,entry.serial,
                                entry.life == "dead" and "death" or "reaction",now)
                        else
                            ok,status = visual:restore(token,target,k,entry.serial,entry.life,now)
                        end
                        if ok then entry.needsState,entry.animateLocal = false,nil end
                    end
                    if ok then
                        local frame
                        ok,status,frame = visual:apply(token,target,k,now)
                        if ok then
                            frame.health,frame.maximum,frame.life,frame.hostEvent = entry.health,entry.maximum,entry.life,entry.hostEvent
                            entry.pose = copy(frame)
                        end
                    end
                end
                entry.pending,entry.lastError = not ok,not ok and status or nil
                if not ok then complete,firstReason = false,firstReason or status end
            end
        end
        if not stillCurrent(c) then synchronize(now); return false,"wrong_scope" end
        return complete,firstReason or "applied"
    end

    function controller:inspect(target)
        local c,reason = synchronize(clock); if not c then return nil,reason end
        local entry = entries[target]
        if not entry then return nil,"unknown_entity" end
        return {health=entry.health,maximum=entry.maximum,life=entry.life,hostEvent=entry.hostEvent,
            localKey=entry.localKey,pending=entry.pending,lastError=entry.lastError,pose=copy(entry.pose)}
    end
    return controller
end
return M
