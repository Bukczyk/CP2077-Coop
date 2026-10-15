-- Pure historical evidence report. Never an actor selector or mutation gate.
-- Resource metadata: read-only game 2.31 extraction, 2026-10-15. SHA-256 below
-- identifies the audited resource bytes, not the resource currently loaded by a
-- user's mod stack. Decimal CName/ResRef constants use the pinned RED4ext SDK
-- ad7277714ad30d6885d7050c5ba24fa0102f6920 CName.hpp / Hashing/FNV1a.hpp.
-- ASCII FNV1a64 independently reproduces both extracted quest-template hashes.
-- These computed constants are not live observations. No color rule is inferred.
local M = {}
local DEFAULT_HASH = "16982411286042166782"
local profiles = {
    judy_default = {
        recordId="63110975482", sourceTemplate="base\\quest\\secondary_characters\\judy.ent",
        sourceTemplateHash="18351684596531345670", appearance="judy_default",
        appearanceHash="14696382396136616853",
        templateSha256="b9f9a819544377810d984b09b93a65868b76ce8f35db62252e139929a11952f9",
        appearanceResource="base\\characters\\appearances\\main_npc\\judy.app",
        appearanceResourceSha256="034221b63be2ae3f4572e3dbe21b800722ec01f3d83cb1b50bacfa52a2d09cad",
        proxyMesh="base\\characters\\appearances\\main_npc\\proxy\\judy_default\\judy_default.mesh",
        targetTemplate="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid.ent",
        targetTemplateHash="4410265881089470268",
    },
    mitch_default = {
        recordId="67785639286", sourceTemplate="base\\quest\\tertiary_characters\\mitch.ent",
        sourceTemplateHash="15874478119190254727", appearance="mitch_default",
        appearanceHash="14305357555168828196",
        templateSha256="da6aee9e602551673e0afd9823a70630a8038408c1788c6cd7f363075a71c9a1",
        appearanceResource="base\\characters\\appearances\\main_npc\\mitch.app",
        appearanceResourceSha256="c77ac7cd21e73278211642d3e7ebd1ec14f860816263fd0e9dad9297d25864e2",
        proxyMesh="base\\characters\\appearances\\main_npc\\proxy\\mitch_default\\mitch_default.mesh",
        targetTemplate="base\\cp2077coop\\entities\\cp2077coop_networkhumanoid_mitch.ent",
        targetTemplateHash="5362881734093004222",
    },
}
local function plain(v) return type(v)=="table" and getmetatable(v)==nil end
local function text(v,n) return type(v)=="string" and #v<=n end
local function decimal(v,zero)
    return type(v)=="string" and v:match("^%d+$")~=nil
        and (#v==1 or v:sub(1,1)~="0") and #v<=20
        and (#v<20 or v<="18446744073709551615") and (zero or v~="0")
end
local function counter(v,zero)
    return type(v)=="number" and v==math.floor(v) and v<2147483648 and v>=(zero and 0 or 1)
end
local function named(name,hash,available)
    return text(name,256) and decimal(hash,true) and type(available)=="boolean"
        and available==(#name>0) and (name~="None" or hash=="0")
end
local function copyFields(input,fields)
    local out={};for _,field in ipairs(fields) do out[field]=input[field] end;return out
end
local sourceFields={"entityId","contextId","recordId","templateHash","templatePath","templatePathAvailable",
    "appearance","appearanceHash","appearanceNameAvailable","color","colorHash","colorNameAvailable"}
local targetFields={"slot","profile","generation","entity","state","retiring","requestedAppearance",
    "observedAppearance","observedAppearanceHash","observedColor","observedColorHash",
    "appearanceNameAvailable","colorNameAvailable","visualStateObserved","colorObserved",
    "identityVerified","identityFault","appearanceVerified"}
local duplicateFields={"observedAppearance","observedAppearanceHash","observedColor","observedColorHash",
    "appearanceNameAvailable","colorNameAvailable","visualStateObserved","colorObserved","identityVerified",
    "appearanceVerified"}
local function result(status,reason)
    return {status=status,reason=reason,historical=true,sourceAuthenticated=false,
        freshnessVerified=false,simultaneousCapture=false,resourceBytesVerified=false,
        colorMatchVerified=false,visualQualified=false}
end
local function finish(r,status,reason) r.status,r.reason=status,reason;return r end

function M.report(slot,generation,source,target)
    local r=result("invalid_input","invalid_arguments")
    if not text(slot,32) or not slot:match("^[A-Za-z][A-Za-z0-9_-]*$")
        or not text(generation,256) or #generation==0 or not plain(source) then return r end
    -- Never recurse over caller input: unknown keys, cycles and opaque handles
    -- cannot enter a report. Only validated, bounded primitive fields are copied.
    if type(source.valid)~="boolean" or not text(source.reason,256) then return finish(r,"invalid_input","source_status") end
    if source.valid==false then return finish(r,"unknown","source_"..source.reason) end
    if source.reason~="captured" or source.historical~=true or source.visualQualified~=false
        or not counter(source.scope,false) or not counter(source.ticket,false) or not counter(source.frame,true)
        or not plain(source.observed) then return finish(r,"invalid_input","source_provenance") end
    local s=source.observed
    for _,field in ipairs({"entityId","contextId","recordId","templateHash"}) do
        if not decimal(s[field],false) then return finish(r,"invalid_input","source_"..field) end
    end
    if not text(s.templatePath,1024) or type(s.templatePathAvailable)~="boolean"
        or s.templatePathAvailable~=(#s.templatePath>0)
        or not named(s.appearance,s.appearanceHash,s.appearanceNameAvailable)
        or not named(s.color,s.colorHash,s.colorNameAvailable) then return finish(r,"invalid_input","source_tuple") end
    r.source={scope=source.scope,ticket=source.ticket,frame=source.frame,observed=copyFields(s,sourceFields)}
    -- Check contradictions only against reviewed constants. Other names/hashes
    -- are unsupported, not guessed, hashed with Lua doubles, or debug-parsed.
    if (s.appearance=="default" and s.appearanceHash~=DEFAULT_HASH)
        or (s.appearanceHash==DEFAULT_HASH and s.appearanceNameAvailable and s.appearance~="default") then
        return finish(r,"invalid_input","source_known_name_hash_conflict")
    end
    for _,p in pairs(profiles) do
        if (s.templatePath==p.sourceTemplate and s.templateHash~=p.sourceTemplateHash)
            or (s.templateHash==p.sourceTemplateHash and s.templatePathAvailable and s.templatePath~=p.sourceTemplate)
            or (s.appearance==p.appearance and s.appearanceHash~=p.appearanceHash)
            or (s.appearanceHash==p.appearanceHash and s.appearanceNameAvailable and s.appearance~=p.appearance) then
            return finish(r,"invalid_input","source_known_name_hash_conflict")
        end
    end
    if not plain(target) then return finish(r,"unknown","target_unavailable") end
    if target.slot~=slot or target.generation~=generation then return finish(r,"unknown","stale_generation") end
    if not text(target.profile,32) or not profiles[target.profile] then return finish(r,"invalid_input","target_profile") end
    if target.state~="ready" or target.retiring~=false then return finish(r,"unknown","target_not_ready") end
    if target.identityFault~=false or target.identityVerified~=true then return finish(r,"unknown","target_identity_unconfirmed") end
    if target.visualQualified~=false or target.colorMatchVerified~=false
        or not decimal(target.entity,false) or not plain(target.observed) then return finish(r,"invalid_input","target_provenance") end
    local o=target.observed
    if o.visualQualified~=false or o.colorMatchVerified~=false then
        return finish(r,"invalid_input","target_unsupported_qualification")
    end
    for _,field in ipairs(duplicateFields) do
        if target[field]~=o[field] then return finish(r,"invalid_input","target_duplicate_"..field) end
    end
    if o.ready~=true or o.identityFault~=false or o.templateVerified~=true or o.rootVerified~=true
        or o.visualStateObserved~=true or o.colorObserved~=true or o.appearanceVerified~=true then
        return finish(r,"unknown","target_observation_unconfirmed")
    end
    if not named(target.observedAppearance,target.observedAppearanceHash,target.appearanceNameAvailable)
        or not named(target.observedColor,target.observedColorHash,target.colorNameAvailable)
        or not text(o.template,1024) or not decimal(o.templateHash,false) then return finish(r,"invalid_input","target_tuple") end
    local p=profiles[target.profile]
    if target.requestedAppearance~="default" or target.observedAppearance~="default"
        or target.observedAppearanceHash~=DEFAULT_HASH or o.templateHash~=p.targetTemplateHash
        or (#o.template>0 and o.template~=p.targetTemplate) then return finish(r,"invalid_input","target_profile_conflict") end
    r.target=copyFields(target,targetFields)
    r.target.template,r.target.templateHash=o.template,o.templateHash
    r.target.captureFrameAvailable=false -- existing fixture does not record one
    r.colorObservedEqual=s.color==target.observedColor and s.colorHash==target.observedColorHash
    local candidate
    for name,profile in pairs(profiles) do
        if s.recordId==profile.recordId and s.templateHash==profile.sourceTemplateHash
            and s.appearanceHash==profile.appearanceHash then candidate=name;break end
    end
    if not candidate then return finish(r,"unsupported_source","source_resource_tuple_not_reviewed") end
    r.sourceCandidateProfile=candidate
    local chain=profiles[candidate]
    r.resourceChain={gameVersion="2.31",auditDate="2026-10-15",profile=candidate,
        sourceTemplate=chain.sourceTemplate,sourceTemplateHash=chain.sourceTemplateHash,
        sourceTemplateSha256=chain.templateSha256,appearance=chain.appearance,
        appearanceHash=chain.appearanceHash,appearanceResource=chain.appearanceResource,
        appearanceResourceSha256=chain.appearanceResourceSha256,appearanceEntry="default",
        proxyMesh=chain.proxyMesh,targetTemplate=chain.targetTemplate,targetTemplateHash=chain.targetTemplateHash,
        targetAppearance="default",targetAppearanceHash=DEFAULT_HASH,
        hashSdkRevision="ad7277714ad30d6885d7050c5ba24fa0102f6920"}
    if candidate~=target.profile then return finish(r,"different_profile","selected_target_profile_differs") end
    return finish(r,"candidate_resource_match","reviewed_resource_chain_only")
end
return M
