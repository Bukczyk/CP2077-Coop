-- Default-off, controlled HOST-current-weapon diagnostic orchestration.
-- No production combat/weapon parity; no attributed damage delta is reported.
local Codec = assert(require("connected/codec"), "Cannot load connected/codec")
local M = {}
local reasons = {malformed=1, unsupported=2, mapping=3, busy=4, full=5,
    ray=6, engine_rejected=7, unresolved=8, stale=9, invalid_sender=10}
M.reasons = reasons
local function copyContext(c)
    return {session=c.session, epoch=c.epoch, generation=c.generation, self=c.self, host=c.host}
end
local function same(a,b)
    return a.session == b.session and a.epoch == b.epoch and a.generation == b.generation
        and a.self == b.self and a.host == b.host
end
local function validContext(c)
    return type(c) == "table" and c.active == true and Codec.id(c.session)
        and Codec.id(c.generation) and Codec.integer(c.epoch,4294967295)
        and Codec.integer(c.self,4294967295) and c.self == c.host
end
local function mapping(t, target, host)
    return type(t) == "table" and t.sessionEntity == target and Codec.id(t.localKey)
        and t.attached == true and t.managed == true and t.tagged == true and t.owner == host
end
local function observation(o)
    return type(o) == "table" and o.valid == true and Codec.finite(o.health,100000000)
        and Codec.finite(o.maximum,100000000) and o.health >= 0 and o.maximum > 0
        and o.health <= o.maximum and type(o.dead) == "boolean" and type(o.defeated) == "boolean"
end
function M.new(config)
    if type(config) ~= "table" then return nil,"invalid_config" end
    for _, name in ipairs({"context","resolveSender","resolveTarget","validateRay","observe","apply","reply"}) do
        if type(config[name]) ~= "function" then return nil,"missing_" .. name end
    end
    local capacity, timeout, settle = config.capacity or 64, config.timeout or 3, config.settle or 0.25
    if not Codec.integer(capacity,256) or not Codec.finite(timeout,30) or timeout <= 0
        or not Codec.finite(settle,2) or settle < 0.1 or settle >= timeout then return nil,"invalid_limits" end
    local enabled = config.enabled == true
    local scope, entries, occupied, lastRequest, count, serial, clock, fault = nil, {}, {}, {}, 0, 0, 0, nil
    local controller = {}
    local function context(now)
        if not enabled then return nil,"disabled" end
        if fault then return nil,fault end
        if not Codec.finite(now,1e15) or now < clock then return nil,"invalid_time" end
        local ok,c = pcall(config.context)
        if not ok or not validContext(c) then return nil,"inactive" end
        if scope and not same(scope,c) then return nil,"stale_scope_requires_reset" end
        scope,clock = scope or copyContext(c),now
        return c
    end
    local function emit(entry)
        if entry.sent then return true end
        local ok,queued = pcall(config.reply,entry.envelope,entry.disposition,entry.reason,entry.body)
        if ok and queued == true then entry.sent=true; return true end
        -- Retain the completed result verbatim for retry; never invoke the engine again.
        return false
    end
    local function finish(entry, disposition, reason, body, release)
        entry.disposition,entry.reason,entry.body = disposition,reason,body or ""
        entry.state = disposition == 2 and "observed" or "rejected"
        if release then
            if entry.target and occupied[entry.target] == entry.key then occupied[entry.target]=nil end
        else entry.state="unresolved" end
        emit(entry)
    end
    local function reject(entry, reason)
        finish(entry,3,reason,"",true)
        return false,"rejected"
    end
    function controller:reset(now)
        if not Codec.finite(now,1e15) or now < 0 then return false,"invalid_time" end
        local ok,c = pcall(config.context)
        if not ok or not validContext(c) then return false,"inactive" end
        if scope and same(scope,c) then return false,"same_scope" end
        -- Explicit activation change only. Caller must abandon engine observers too.
        scope,entries,occupied,lastRequest,count,serial,clock,fault = copyContext(c),{},{},{},0,0,now,nil
        return true
    end
    function controller:accept(packet,now)
        local c,why=context(now); if not c then return false,why end
        if type(packet) ~= "table" or packet.session ~= c.session or packet.epoch ~= c.epoch
            or packet.generation ~= c.generation or not Codec.integer(packet.sender,4294967295)
            or packet.sender == c.host or not Codec.id(packet.event)
            or not Codec.integer(packet.kind,65535) then return false,"invalid_envelope" end
        local key = packet.session .. ":" .. tostring(packet.epoch) .. ":" .. tostring(packet.sender) .. ":" .. packet.event
        if entries[key] then return false,"duplicate" end
        local envelope={session=packet.session,epoch=packet.epoch,generation=packet.generation,
            sender=packet.sender,event=packet.event,kind=packet.kind}
        if count >= capacity then
            -- Native reply reservation owns delivery retention for this no-effect denial.
            local ok,queued=pcall(config.reply,envelope,5,reasons.full,"")
            if not ok or queued~=true then fault="full_denial_not_queued" end
            return false,"full"
        end
        local entry={key=key,envelope=envelope,state="reserved",started=now}
        entries[key],count=entry,count+1
        local prior=lastRequest[packet.sender]
        if prior and (#packet.event<#prior or (#packet.event==#prior and packet.event<prior)) then
            return reject(entry,reasons.stale)
        end
        lastRequest[packet.sender]=packet.event
        if packet.kind ~= Codec.kind then finish(entry,4,reasons.unsupported,"",true); return false,"unsupported" end
        local intent = Codec.readIntent(packet.body)
        if not intent then return reject(entry,reasons.malformed) end
        entry.target=intent.target
        if occupied[entry.target] then return reject(entry,reasons.busy) end
        local ok,sender=pcall(config.resolveSender,packet.sender)
        if not ok or type(sender)~="table" or sender.player~=packet.sender or sender.attached~=true
            or not Codec.id(sender.localKey) or not Codec.id(sender.sessionEntity) then return reject(entry,reasons.invalid_sender) end
        local senderLocal,senderEntity=sender.localKey,sender.sessionEntity
        local targetOk,target=pcall(config.resolveTarget,entry.target)
        if not targetOk or not mapping(target,entry.target,c.host) then return reject(entry,reasons.mapping) end
        local targetLocal=target.localKey
        local observed,before=pcall(config.observe,target,nil)
        if not observed or not observation(before) or before.dead or before.defeated or before.health<=0
            or before.ambiguous or before.pending then return reject(entry,reasons.mapping) end
        local rayOk,hit=pcall(config.validateRay,sender,target,intent)
        if not rayOk or hit~=true then return reject(entry,reasons.ray) end
        local nowOk,current=pcall(config.context)
        local mapOk,rechecked=pcall(config.resolveTarget,entry.target)
        local senderOk,currentSender=pcall(config.resolveSender,packet.sender)
        if not nowOk or not validContext(current) or not same(scope,current) or not mapOk
            or not mapping(rechecked,entry.target,scope.host) or rechecked.localKey~=targetLocal
            or not senderOk or type(currentSender)~="table" or currentSender.attached~=true
            or currentSender.player~=packet.sender or currentSender.localKey~=senderLocal
            or currentSender.sessionEntity~=senderEntity then return reject(entry,reasons.stale) end
        if serial >= 2147483647 then return reject(entry,reasons.full) end
        serial=serial+1
        entry.serial,entry.localKey,entry.before,entry.handle=serial,targetLocal,{health=before.health},target
        entry.state,occupied[entry.target]="pending",key -- Reserve BEFORE any mutation.
        local applied,result=pcall(config.apply,target,serial)
        if not applied then finish(entry,3,reasons.unresolved,"",false); return false,"unresolved" end
        if result~="queued_host_weapon_pipeline_fixture_not_observed" then
            -- A returned explicit rejection precedes mutation in the verified fixture.
            if type(result)=="string" and result:match("^rejected_") then return reject(entry,reasons.engine_rejected) end
            finish(entry,3,reasons.unresolved,"",false); return false,"unresolved"
        end
        return true,"pending"
    end
    function controller:step(now)
        local c,why=context(now); if not c then return false,why end
        for _,entry in pairs(entries) do
            if entry.state=="pending" then
                local ok,target=pcall(config.resolveTarget,entry.target)
                if not ok or not mapping(target,entry.target,c.host) or target.localKey~=entry.localKey then
                    finish(entry,3,reasons.unresolved,"",false)
                else
                    local read,o=pcall(config.observe,target,entry.serial)
                    if not read or not observation(o) or o.ambiguous then
                        finish(entry,3,reasons.unresolved,"",false)
                    elseif o.correlated == true and (o.health < entry.before.health or o.dead)
                        and (not o.dead or o.health == 0) and (o.health > 0 or o.dead or o.defeated) then
                        local life=o.dead and "dead" or (o.defeated and "defeated" or "alive")
                        if not entry.sample or entry.sample.health~=o.health or entry.sample.maximum~=o.maximum
                            or entry.sample.life~=life then
                            entry.sample={health=o.health,maximum=o.maximum,life=life}; entry.changedAt=now
                        elseif now-entry.changedAt>=settle then
                            local body=Codec.result({target=entry.target,health=o.health,maximum=o.maximum,life=life})
                            if body then finish(entry,2,0,body,true) else finish(entry,3,reasons.unresolved,"",false) end
                        end
                        if entry.state=="pending" and now-entry.started>=timeout then finish(entry,3,reasons.unresolved,"",false) end
                    elseif now-entry.started>=timeout then
                        finish(entry,3,reasons.unresolved,"",false)
                    end
                end
            elseif not entry.sent then emit(entry) end
        end
        return true
    end
    function controller:inspect()
        local pending,unresolved,unsent=0,0,0
        for _,entry in pairs(entries) do
            if entry.state=="pending" then pending=pending+1 end
            if entry.state=="unresolved" then unresolved=unresolved+1 end
            if entry.disposition and not entry.sent then unsent=unsent+1 end
        end
        return {count=count,pending=pending,unresolved=unresolved,unsent=unsent,fault=fault}
    end
    return controller
end
return M
