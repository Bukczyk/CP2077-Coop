-- LOCAL protocol0x8005 candidate. Read-back only on capture; cosmetic pure-entity
-- setters only on application. Never inventory, AI, damage or movement authority.
local M={template="base\\cp2077coop\\entities\\player_weapon_igla_fixture.ent"}
local recordKey="16ac119774"
local sourceDue,sourceSignature,sourceSamples,sourceScope=0,nil,0,nil
local required={
    ["base\\weapons\\firearms\\shotgun_dual\\rostovic_igla\\entities\\meshes\\w_shotgun_dual__rostovic_igla__base1_01.mesh"]={"Barrel","pimp1"},
    ["base\\weapons\\firearms\\shotgun_dual\\rostovic_satara\\entities\\meshes\\w_shotgun_dual__rostovic_satara__rcv1_01.mesh"]={"Receiver","pimp1_igla"},
    ["base\\weapons\\firearms\\shotgun_dual\\rostovic_satara\\entities\\meshes\\w_shotgun_dual__rostovic_satara__mag_std_01_left_01.mesh"]={"Magazine","default"},
    ["base\\weapons\\firearms\\shotgun_dual\\rostovic_satara\\entities\\meshes\\w_shotgun_dual__rostovic_satara__mag_std_01_right_01.mesh"]={"Magazine","default"},
    ["base\\weapons\\firearms\\shotgun_dual\\rostovic_satara\\entities\\meshes\\w_shotgun_dual__rostovic_satara__rcv1_01_decal_n01_default.mesh"]={"Receiver","default"}}
local rigs={
    Receiver="base\\weapons\\firearms\\shotgun_dual\\rig\\w_shotgun_dual__rcv1.rig",
    Barrel="base\\weapons\\firearms\\shotgun_dual\\rostovic_igla\\rig\\w_shotgun_dual__rostovic_igla__base1.rig",
    Magazine="base\\weapons\\firearms\\shotgun_dual\\rostovic_satara\\rig\\w_shotgun_dual__rostovic_satara__mag_std.rig"}
local function integer(value,low,high)
    return type(value)=="number" and value==value and value>=low and value<=high and value%1==0
end
function M.available()
    local ok,version=pcall(function()return Game.CP2077Presentation_Version()end)
    return ok and version==32773
end
function M.iglaVisuals(rows)
    if type(rows)~="table" or #rows>128 then return false end
    local found,seenRigs,count={},{},0
    for _,row in ipairs(rows)do
        if row.kind=="rig" then
            if rigs[row.name] then
                if seenRigs[row.name] or row.path~=rigs[row.name] then return false end
                seenRigs[row.name]=true
            end
        elseif row.enabled==true then
            if type(row.path)~="string" then return false end
            local expected=required[row.path]
            if expected then
                if found[row.path] or row.kind~="skinned" or row.parent~=expected[1] or row.skin~=expected[1]
                    or row.appearance~=expected[2] or row.mask==nil or type(row.mask)=="number"
                    or tostring(row.mask):gsub("[uUlL]+$","")~="18446744073709551615" then return false end
                found[row.path]=true;count=count+1
            elseif not row.path:find("_shadow",1,true) and not row.path:match("weapon_placeholder%.mesh$")
                and row.skin~="MagazineReload" then return false end
        end
    end
    return count==5 and seenRigs.Receiver==true and seenRigs.Barrel==true and seenRigs.Magazine==true
end
function M.capture(player,now)
    if type(now)~="number" or now~=now or math.abs(now)==math.huge or now<sourceDue then return end
    sourceDue=now+0.05
    if not M.available() then return end
    local scopeOk,session,epoch,generation=pcall(function()
        return Game.CP2077Session_Session(),Game.CP2077Session_Epoch(),Game.CP2077Session_Generation()
    end)
    if not scopeOk then return end
    local scope=tostring(session)..":"..tostring(epoch)..":"..tostring(generation)
    if sourceScope~=scope then sourceScope,sourceSignature,sourceSamples=scope,nil,0 end
    local empty=TweakDBID.new("")
    local ok,stance,weapon,record,aim=pcall(function()
        if not player or player:CP2077Capture_Ready()~=true then return 0,0,empty,0 end
        local crouched,aiming=player:CP2077Capture_Crouched(),player:CP2077Capture_Aiming()
        if type(crouched)~="boolean" or type(aiming)~="boolean" then return 0,0,empty,0 end
        local held=player:CP2077Capture_HasWeapon()
        if type(held)~="boolean" then return crouched and 2 or 1,0,empty,0 end
        local item=player:CP2077Capture_HeldRecord()
        local state=held and 3 or 1
        if held and Game.CP2077Presentation_IsIgla(item) then
            local visualOk,rows=pcall(function()return player:CP2077Capture_HeldVisuals()end)
            if visualOk and M.iglaVisuals(rows) then
                if sourceSignature==recordKey then sourceSamples=math.min(2,sourceSamples+1)
                else sourceSignature,sourceSamples=recordKey,1 end
                if sourceSamples>=2 then state=2 end
            else sourceSignature,sourceSamples=nil,0 end
        else sourceSignature,sourceSamples=nil,0 end
        if player:CP2077Capture_Ready()~=true or player:CP2077Capture_HasWeapon()~=held
            or player:CP2077Capture_Crouched()~=crouched or player:CP2077Capture_Aiming()~=aiming then
            sourceSignature,sourceSamples=nil,0;return 0,0,empty,0
        end
        -- The exact canonical Igla record must still be attached at the end.
        if held and not Game.CP2077Presentation_RecordsEqual(item,player:CP2077Capture_HeldRecord()) then
            sourceSignature,sourceSamples=nil,0;return 0,0,empty,0
        end
        return crouched and 2 or 1,state,held and item or empty,held and (aiming and 2 or 1) or 1
    end)
    if not ok then stance,weapon,record,aim=0,0,empty,0;sourceSignature,sourceSamples=nil,0 end
    if weapon==0 or weapon==1 then sourceSignature,sourceSamples=nil,0 end
    -- Native TweakDBID, SessionId and generation are passed directly. No tonumber.
    local submitted,result=pcall(function()
        return Game.CP2077Presentation_Push(session,epoch,generation,stance,weapon,record,aim)
    end)
    return submitted and result or nil
end
function M.decode(raw)
    if type(raw)~="string" or #raw>160 or raw=="" then return nil end
    local fields={};for field in raw:gmatch("[^|]+")do fields[#fields+1]=field end
    if #fields~=8 or table.concat(fields,"|")~=raw or not fields[7]:match("^[0-9a-f]+$") or #fields[7]~=10 then return nil end
    local fresh,revision,sequence,age,stance,weapon,aim=tonumber(fields[1]),tonumber(fields[2]),tonumber(fields[3]),
        tonumber(fields[4]),tonumber(fields[5]),tonumber(fields[6]),tonumber(fields[8])
    if not integer(fresh,0,1) or not integer(revision,1,4294967295) or not integer(sequence,1,4294967295)
        or not integer(age,0,30001) or not integer(stance,0,2) or not integer(weapon,0,3) or not integer(aim,0,2) then return nil end
    if (weapon==0 or weapon==1) and (fields[7]~="0000000000" or aim==2) then return nil end
    if weapon==2 and fields[7]~=recordKey then return nil end
    return {fresh=fresh==1,revision=revision,sequence=sequence,ageMs=age,stance=stance,weapon=weapon,record=fields[7],aim=aim}
end
function M.read()
    local ok,raw=pcall(function()return Game.CP2077Presentation_Read()end)
    return ok and M.decode(raw) or nil
end
local function input(actor,state,name,value)
    state.inputs=state.inputs or {}
    if state.inputs[name]==value then return end
    local event=assert(NewObject("entAnimInputSetterFloat"));event.key,event.value=CName.new(name),value
    actor:QueueEvent(event);state.inputs[name]=value
end
function M.apply(actor,state,observed,gait)
    if not actor or actor:IsAttached()~=true then return "actor_unavailable" end
    local id=tostring(actor:GetEntityID().hash)
    if state.actorKey and state.actorKey~=id then return "actor_changed" end
    state.actorKey=id
    local fresh=observed and observed.fresh==true
    local stance=fresh and observed.stance==2 and 1 or 0
    local show=fresh and observed.weapon==2 and observed.record==recordKey and (observed.aim==1 or observed.aim==2) or false
    local phase=gait and gait.phase or 0
    local moving=phase==1 or phase==2
    local pose=show and (observed.aim==2 and (moving and 4 or 3) or (phase==2 and 2 or moving and 1 or 0)) or 0
    local attemptKey=tostring(show)..":"..tostring(observed and observed.revision or 0)..":"..tostring(fresh)
    if state.visible~=show and state.lastAttempt~=attemptKey then
        state.lastAttempt=attemptKey
        local ok,accepted=pcall(function()return actor:CP2077Fixture_SetWeaponVisible(show)end)
        if not ok or accepted~=true then return "visibility_rejected" end
        state.visible=show
    end
    if state.visible~=show then return "visibility_unavailable" end
    input(actor,state,"cp_coop_stance",stance)
    input(actor,state,"cp_coop_crouch_motion",stance==1 and moving and 1 or 0)
    input(actor,state,"cp_coop_weapon_weight",show and 1 or 0)
    input(actor,state,"cp_coop_weapon_pose",pose)
    state.revision=observed and observed.revision
    if not fresh then return "owned_overrides_neutralized" end
    return (observed.stance==0 or observed.weapon==0 or observed.weapon==3 or observed.aim==0)
        and "presentation_partial" or "presentation_submitted"
end
return M
