-- PRIVATE read-only engine capture. It does not deliver state to another game.
local clock,due,rows,bytes=0,0,0,0
local aimAvailable,aimDirection=pcall(require,"aim_direction")
local visualSignature,visualAttempts,visualCaptured,visualPending=nil,0,false,nil
local function opaque(value)
    if type(value)=="number" then return end
    local id=tostring(value):match("^(%d+)[uUlL]*$")
    if id and id:match("^[1-9][0-9]*$") and (#id<20 or #id==20 and id<="18446744073709551615") then return id end
end
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function sourcePose(player,session,self)
    local entity=opaque(player:GetEntityID().hash)
    local generation=opaque(Game.CP2077Session_Generation())
    local networkEntity=opaque(Game.CP2077Session_SelfEntity())
    local epoch=Game.CP2077Session_Epoch()
    if not entity or not generation or not networkEntity or not finite(epoch)
        or epoch<1 or epoch>4294967295 or epoch%1~=0 then return end
    local p=player:GetWorldPosition()
    local x,y,z=p.x,p.y,p.z
    local yaw=player:GetWorldOrientation():ToEulerAngles().yaw
    if not finite(x) or not finite(y) or not finite(z) or not finite(yaw)
        or math.max(math.abs(x),math.abs(y),math.abs(z))>1000000 or math.abs(yaw)>360 then return end
    local locomotion=tostring(PlayerPuppet.GetCurrentLocomotionState(player)):sub(1,96)
    if Game.CP2077Session_Phase()~=4 or player:CP2077Capture_Ready()~=true or opaque(player:GetEntityID().hash)~=entity
        or tostring(Game.CP2077Session_Session())~=session or Game.CP2077Session_Self()~=self
        or opaque(Game.CP2077Session_Generation())~=generation or Game.CP2077Session_Epoch()~=epoch
        or opaque(Game.CP2077Session_SelfEntity())~=networkEntity then return end
    return {localEntity=entity,sessionEntity=networkEntity,generation=generation,epoch=epoch,
        x=x,y=y,z=z,yawDegrees=yaw,locomotion=locomotion}
end
local function visuals(player,signature)
    if visualSignature~=signature then visualSignature,visualAttempts,visualCaptured,visualPending=signature,0,false,nil end
    if visualCaptured or visualAttempts>=10 then return end
    visualAttempts=visualAttempts+1
    local ok,items=pcall(function()return player:CP2077Capture_HeldVisuals() end)
    if not ok or type(items)~="table" or #items>128 then return end
    local result,identity,meshes={},{},0
    for _,item in ipairs(items) do
        if type(item.kind)~="string" or type(item.path)~="string" then return end
        local row={name=item.name,kind=item.kind,path=item.path,appearance=item.appearance,
            enabled=item.enabled,parent=item.parent,slot=item.slot,skin=item.skin,
            transformDiagnostic=tostring(item.localTransform):sub(1,2048)}
        if item.kind=="static" or item.kind=="skinned" then
            if item.mask==nil or type(item.mask)=="number" then return end -- never round an opaque native mask
            row.mask=tostring(item.mask):gsub("[uUlL]+$","")
            if item.enabled and item.path:match("%.mesh$") and not item.path:match("weapon_placeholder%.mesh$") then meshes=meshes+1 end
        end
        result[#result+1]=row
        identity[#identity+1]=table.concat({tostring(row.name),row.kind,row.path,tostring(row.appearance),
            tostring(row.enabled),tostring(row.parent),tostring(row.slot),tostring(row.skin),tostring(row.mask)},"|")
    end
    if meshes==0 then return end -- a generic root rig is not a complete weapon visual
    local stable=table.concat(identity,"\n")
    if visualPending~=stable then visualPending=stable;return end
    visualCaptured=true
    return result
end
registerForEvent("onUpdate",function(dt)
    if type(dt)~="number" or dt<=0 or dt~=dt or dt==math.huge or rows>=9000 or bytes>=2*1024*1024 then return end
    clock=clock+dt;if clock<due then return end;due=clock+0.2
    local ok,sample=pcall(function()
        local p=Game.GetPlayer();if not p or not p:CP2077Capture_Ready() then return end
        local requests=Game.GetSystemRequestsHandler()
        if not requests or requests:IsGamePaused()~=false or Game.CP2077Session_Phase()~=4 then return end
        local templateOk,template=pcall(function()return p:CP2077Capture_HeldTemplate() end)
        local appearanceOk,appearance=pcall(function()return tostring(p:CP2077Capture_HeldAppearance()) end)
        local record=tostring(p:CP2077Capture_HeldRecord())
        local held=p:CP2077Capture_HasWeapon()
        local sample={time=clock,utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),
            captureRevision="20261020-source-pose-1",observation=rows+1,
            self=Game.CP2077Session_Self(),session=tostring(Game.CP2077Session_Session()),
            crouched=p:CP2077Capture_Crouched(),aiming=p:CP2077Capture_Aiming(),
            held=held,record=record,
            template=templateOk and template or nil,
            appearanceDiagnostic=appearanceOk and appearance or nil,
            scope="read-only local source, not synchronized"}
        -- Optional source context in this same game-thread callback. The local
        -- clock/ordinal are diagnostic only, not a network capture timestamp or
        -- packet sequence. An enum such as Default does not prove ground contact.
        local poseOk,pose=pcall(sourcePose,p,sample.session,sample.self)
        sample.sourcePoseStatus=poseOk and pose~=nil and "observed" or "unavailable"
        if poseOk then sample.sourcePose=pose end
        if aimAvailable and type(aimDirection)=="table" then
            local directionOk,direction=pcall(function()
                return aimDirection.fromPlayer(p)
            end)
            if directionOk then sample.cameraAim=direction end
        end
        if held then
            local visualOk,observed=pcall(visuals,p,record.."|"..tostring(template).."|"..tostring(appearance))
            if visualOk then sample.visuals=observed end
        else visualSignature=nil end
        return sample
    end)
    if not ok then
        spdlog.info("[ActionCapture] unavailable "..tostring(sample));rows=9000;return
    end
    if sample then
        local line=json.encode(sample).."\n"
        if bytes+#line>2*1024*1024 then return end
        local f=assert(io.open("capture.jsonl","a"))
        if f:seek("end")+#line>2*1024*1024 then f:close();rows=9000;return end
        f:write(line);f:close()
        rows,bytes=rows+1,bytes+#line
    end
end)
return {}
