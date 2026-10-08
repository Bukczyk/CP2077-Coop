-- Strict adapter for the existing local engine_hooks.reds evidence format.
-- Run only on the game thread, on references owned by the private test harness.
-- HostWeaponHit uses HOST weapon/credit and synthetic geometry, without ammo use.
local Codec = assert(require("connected/codec"), "Cannot load connected/codec")
local M = {}
local knownKinds = {enabled=true,readback=true,fixture_observed_change=true,
    host_weapon_fixture_queued=true,candidate_before_preprocess=true,after_preprocess=true,
    after_deal_await_readback=true,death_callback=true,on_died_after_vanilla=true,
    gunshot_stimulus_received=true,fixture_abandoned=true}
local function fields(line, prefix)
    if type(line)~="string" or #line>4096 then return nil end
    if prefix then
        if line:sub(1,#prefix)~=prefix then return nil end
        line=line:sub(#prefix+1)
    end
    local result,duplicates,count,deathMarker={},{},0,false
    for token in line:gmatch("%S+") do
        local name,value=token:match("^([%w_]+)=([^%s=]+)$")
        if deathMarker then return nil end -- Verified marker is the final token.
        if not name then
            if token~="await_persistent_flag" or result.kind~="death_callback" then return nil end
            deathMarker=true
        else
            if result[name] then
                if duplicates[name] or not (result.kind=="readback" and result[name]==value
                    and (name=="healthPoints" or name=="persistentDead" or name=="defeated" or name=="healthMin")) then return nil end
                duplicates[name]=true
            end
            result[name]=value
        end
        count=count+1
        if count>64 then return nil end
    end
    if result.kind=="death_callback" and not deathMarker then return nil end
    return count>0 and result or nil
end
local function boolean(v)
    if v=="true" then return true elseif v=="false" then return false end
end
local function decimal(v)
    if type(v)~="string" or (v~="0" and not v:match("^[1-9]%d*$")) then return nil end
    local n=tonumber(v)
    return Codec.finite(n,4294967295) and n or nil
end
local function completeHit(v)
    if v.instigatorDefined~="true" or v.weaponDefined~="true"
        or not Codec.id(v.instigatorLocal) or not Codec.id(v.weaponLocal)
        or decimal(v.attackType)~=10 or not Codec.integer(decimal(v.hitShapes),256) then return false end
    for _,prefix in ipairs({"hit","origin","direction"}) do
        for _,axis in ipairs({"X","Y","Z"}) do
            if not Codec.finite(tonumber(v[prefix..axis]),1000000) then return false end
        end
    end
    return Codec.finite(tonumber(v.computedNotObserved),100000000)
end
local function health(s)
    local h,m=tonumber(s.healthPoints),tonumber(s.healthMaxPoints)
    local d,f,p=boolean(s.persistentDead),boolean(s.defeated),boolean(s.pending)
    if not Codec.finite(h,100000000) or not Codec.finite(m,100000000) or h<0 or m<=0 or h>m
        or d==nil or f==nil or p==nil then return nil end
    return {valid=true,health=h,maximum=m,dead=d,defeated=f,pending=p}
end
function M.new(context,capacity)
    if type(context)~="function" then return nil,"invalid_context" end
    capacity=capacity or 64
    if not Codec.integer(capacity,256) then return nil,"invalid_capacity" end
    local states,captured,count={},{},0
    local adapter={}
    function adapter:reset() states,captured,count={},{},0 end
    -- Root's private harness remains the sole owner of Readback/Drain and logs.
    -- Call once for every new sample before host:accept/step. Accumulation is bounded.
    function adapter:ingest(target,readback,lines)
        if type(target)~="table" or not Codec.id(target.localKey) or type(lines)~="table" then return false end
        local previous=captured[target.localKey]
        if not previous then
            if count>=capacity then return false end
            count=count+1
        end
        local nextSample={readback=readback,lines={}}
        if previous then
            if previous.invalid then nextSample.invalid=true end
            for _,line in ipairs(previous.lines) do nextSample.lines[#nextSample.lines+1]=line end
        end
        if #lines>256 or #nextSample.lines+#lines>256 then nextSample.invalid=true
        else for _,line in ipairs(lines) do nextSample.lines[#nextSample.lines+1]=line end end
        captured[target.localKey]=nextSample
        return not nextSample.invalid
    end
    function adapter:observe(target, serial)
        if type(target)~="table" or not Codec.id(target.localKey) or not Codec.id(target.sessionEntity)
            or target.object==nil then return {valid=false} end
        local sample=captured[target.localKey]
        if not sample or sample.invalid then return {valid=false} end
        local s=fields(sample.readback)
        local result=s and health(s)
        if not result then return {valid=false} end
        local c=context()
        local lines=sample.lines
        sample.lines={}
        if type(lines)~="table" or #lines>256 then return {valid=false} end
        local state=states[target.localKey]
        if serial==nil then
            -- The harness can consume an idle baseline, then admission reads
            -- that same sample again. Preserve the sequence watermark while
            -- clearing the previous fixture's causal counters.
            state={serial=nil,candidate=0,deal=0,ambiguous=false,lastSeq=state and state.lastSeq or 0}
            states[target.localKey]=state
        elseif not state or state.serial~=serial then return {valid=false} end
        for _,line in ipairs(lines) do
            local v=fields(line,"encounter ")
            if not v or not knownKinds[v.kind] or v["local"]~=target.localKey
                or (v.entity~=target.sessionEntity and not (serial==nil and v.entity=="0" and v.kind=="enabled"))
                or v.session~=c.session or decimal(v.epoch)~=c.epoch or decimal(v.self)~=c.self
                or decimal(v.host)~=c.host then return {valid=false} end
            local sequence=decimal(v.seq)
            if not Codec.integer(sequence,4294967295) or sequence<=state.lastSeq
                or (serial and sequence~=state.lastSeq+1) then return {valid=false} end
            state.lastSeq=sequence
            if serial then
                if v.kind=="candidate_before_preprocess" or v.kind=="after_preprocess" or v.kind=="after_deal_await_readback" then
                    if not completeHit(v) then return {valid=false} end
                    if decimal(v.fixtureRequest)~=serial or v.syntheticFixture~="true" or v.projectionPipeline~="false" then
                        state.ambiguous=true
                    elseif v.kind=="candidate_before_preprocess" then
                        state.candidate=state.candidate+1
                        if state.candidate~=1 or state.deal~=0 then state.ambiguous=true end
                    elseif v.kind=="after_deal_await_readback" then
                        state.deal=state.deal+1
                        if state.candidate~=1 or state.deal~=1 then state.ambiguous=true end
                    end
                elseif v.kind=="fixture_abandoned" then state.ambiguous=true end
            end
        end
        result.correlated=state.candidate==1 and state.deal==1 and not state.ambiguous
        result.ambiguous=state.ambiguous
        return result
    end
    function adapter:apply(target,serial)
        local state=states[target.localKey]
        if not state or state.serial or not Codec.integer(serial,2147483647) then return "rejected_adapter_state" end
        state.serial=serial -- Reserve correlation before calling an effectful native method.
        return target.object:CP2077Encounter_HostWeaponHit(serial)
    end
    return adapter
end
return M
