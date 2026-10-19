-- PRIVATE read-only engine capture. It does not deliver state to another game.
local clock,due,rows,bytes=0,0,0,0
registerForEvent("onUpdate",function(dt)
    if type(dt)~="number" or dt<=0 or dt~=dt or dt==math.huge or rows>=9000 or bytes>=2*1024*1024 then return end
    clock=clock+dt;if clock<due then return end;due=clock+0.2
    local ok,sample=pcall(function()
        local p=Game.GetPlayer();if not p or not p:CP2077Capture_Ready() then return end
        local requests=Game.GetSystemRequestsHandler()
        if not requests or requests:IsGamePaused()~=false or Game.CP2077Session_Phase()~=4 then return end
        local templateOk,template=pcall(function()return p:CP2077Capture_HeldTemplate() end)
        return {time=clock,utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),
            self=Game.CP2077Session_Self(),session=tostring(Game.CP2077Session_Session()),
            crouched=p:CP2077Capture_Crouched(),aiming=p:CP2077Capture_Aiming(),
            held=p:CP2077Capture_HasWeapon(),record=tostring(p:CP2077Capture_HeldRecord()),
            template=templateOk and template or nil,
            scope="read-only local source, not synchronized"}
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
