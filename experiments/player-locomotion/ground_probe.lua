-- PRIVATE bounded read-only engine probe. Never changes state-machine returns,
-- player inputs, transforms, physics, network state, configuration or saves.
local clock,calls,rows,bytes,started,stopped=0,0,0,0,false,false
local last,lastEmit,errors=nil,-1,0
local function opaque(v)
    if type(v)=="number" then return end
    local s=tostring(v):gsub("[uUlL]+$","")
    if s:match("^[1-9][0-9]*$") and (#s<20 or #s==20 and s<="18446744073709551615") then return s end
end
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function record(row)
    if stopped or rows>=1800 or bytes>=1048576 then stopped=true;return end
    local text=json.encode(row).."\n"
    if bytes+#text>1048576 then stopped=true;return end
    local file=assert(io.open("ground.jsonl","a"))
    if file:seek("end")+#text>1048576 then file:close();stopped=true;return end
    file:write(text);file:close();rows,bytes=rows+1,bytes+#text
end
local function observe(class,_,delta,context,interface)
    if not started or stopped then return end
    calls=calls+1
    if calls>36000 or clock>300 then stopped=true;return end
    local ok,row=pcall(function()
        if not finite(delta) or delta<=0 or not interface or Game.CP2077Session_Phase()~=4 then return end
        local player=Game.GetPlayer()
        if not player or player:CP2077Capture_Ready()~=true then return end
        local requests=Game.GetSystemRequestsHandler()
        if not requests or requests:IsGamePaused()~=false then return end
        local id=opaque(player:GetEntityID().hash)
        local owner=interface.executionOwner
        if not id or not owner or owner:IsAttached()~=true or opaque(owner:GetEntityID().hash)~=id then return end
        local generation=opaque(Game.CP2077Session_Generation())
        local entity=opaque(Game.CP2077Session_SelfEntity())
        local session=opaque(Game.CP2077Session_Session())
        local epoch=Game.CP2077Session_Epoch()
        if not generation or not entity or not session or not finite(epoch) or epoch<1 or epoch%1~=0 then return end
        local ground=interface:IsOnGround()
        if type(ground)~="boolean" then return end
        if Game.CP2077Session_Phase()~=4 or opaque(Game.CP2077Session_Generation())~=generation
            or opaque(Game.CP2077Session_SelfEntity())~=entity or Game.CP2077Session_Epoch()~=epoch
            or opaque(Game.CP2077Session_Session())~=session
            or opaque(player:GetEntityID().hash)~=id or opaque(owner:GetEntityID().hash)~=id then return end
        local p=player:GetWorldPosition()
        if not finite(p.x) or not finite(p.y) or not finite(p.z) then return end
        return {revision="ground-probe-1",time=clock,utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),
            observer=class,calls=calls,localEntity=id,sessionEntity=entity,session=session,
            generation=generation,epoch=epoch,self=Game.CP2077Session_Self(),grounded=ground,
            x=p.x,y=p.y,z=p.z,locomotion=tostring(PlayerPuppet.GetCurrentLocomotionState(player)),
            scope="PRIVATE current local player ground observation; not synchronized"}
    end)
    if not ok then
        errors=errors+1
        if errors<=2 then spdlog.info("[GroundProbe] unavailable "..tostring(row)) end
        return
    end
    if not row then return end
    local signature=row.session..":"..row.epoch..":"..row.generation..":"..row.localEntity..":"..tostring(row.grounded)
    if signature~=last or clock-lastEmit>=.2 then
        local written,why=pcall(record,row)
        if not written then stopped=true;spdlog.info("[GroundProbe] stopped "..tostring(why));return end
        last,lastEmit=signature,clock
    end
end
registerForEvent("onInit",function()
    local ok,why=pcall(function()
        local c=assert(Reflection.GetClass(CName.new("gamestateMachineGameScriptInterface")))
        local f=assert(c:GetFunction(CName.new("IsOnGround")))
        assert(f:IsNative() and #f:GetParameters()==0 and tostring(f:GetReturnType():GetName()):find("Bool"))
        local count=0
        for _,name in ipairs({"LocomotionEventsTransition","CrouchEvents","LocomotionAirEvents"})do
            local cls=Reflection.GetClass(CName.new(name))
            local fn=cls and cls:GetFunction(CName.new("OnUpdate"))
            if fn and #fn:GetParameters()==3 then
                local observerName=name
                ObserveAfter(observerName,"OnUpdate",function(...)observe(observerName,...)end)
                count=count+1
            end
        end
        assert(count>0,"no registered locomotion observer")
        started=true;spdlog.info("[GroundProbe] observers="..count.." max_seconds=300 max_calls=36000 max_rows=1800 max_bytes=1048576")
    end)
    if not ok then stopped=true;spdlog.info("[GroundProbe] init unavailable "..tostring(why))end
end)
registerForEvent("onUpdate",function(dt)
    if finite(dt) and dt>0 then clock=clock+dt;if clock>300 then stopped=true end end
end)
return {status=function()return {started=started,stopped=stopped,calls=calls,rows=rows,bytes=bytes,errors=errors,time=clock}end}
