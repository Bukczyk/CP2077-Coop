-- PRIVATE LOCAL BENCH ONLY. Install as zz_CP2077LocomotionObserver/init.lua.
-- One explicit request places JOINER once. Never continuously teleport a player:
-- doing so changes engine lifecycle timing and invalidates cleanup tests.
local clock,nextPoll,requests=0,0,0
local seen={}
local function key(value) return tostring(value):gsub("[uUlL]+$", "") end
local function read()
    local f=io.open("observer-request.json","r")
    if not f then return end
    local data=f:read(2049);f:close()
    if #data>2048 then return end
    local ok,r=pcall(json.decode,data)
    if ok and type(r)=="table" and type(r.request)=="string" and #r.request<=64 then return r end
end
local old=read();if old then seen[old.request]=true end
local function receipt(r,accepted,reason)
    local result={version=1,request=r.request,session=r.session,accepted=accepted,reason=reason,
        self=Game.CP2077Session_Self(),host=Game.CP2077Session_Host()}
    local f=assert(io.open("observer-receipt.json","w"),"observer receipt unavailable")
    f:write(json.encode(result));f:close()
    spdlog.info("[LocomotionObserver] request="..r.request.." accepted="..tostring(accepted).." reason="..reason)
end
registerForEvent("onUpdate",function(dt)
    if type(dt)~="number" or dt<=0 or dt~=dt or dt==math.huge then return end
    clock=clock+dt
    if clock>=1800 or clock<nextPoll or requests>=16 then return end
    nextPoll=clock+0.2
    local r=read()
    if not r or seen[r.request] then return end
    seen[r.request]=true;requests=requests+1
    local p=Game.GetPlayer()
    local system=Game.GetSystemRequestsHandler()
    if r.version~=1 or r.mode~="place-observer" or r.session~=key(Game.CP2077Session_Session())
        or Game.CP2077Session_Phase()~=4 or Game.CP2077Session_Self()==Game.CP2077Session_Host()
        or not p or not p:IsAttached() or not system or system:IsGamePaused()~=false then
        receipt(r,false,"context_rejected");return
    end
    -- Offset two metres and face the route centre. A HOST loaded at the old
    -- observer spot otherwise fills the camera with its own projection.
    Game.GetTeleportationFacility():Teleport(p,Vector4.new(-815,817.5,24.4042,1),EulerAngles.new(0,0,-18.43494882))
    GetMod("CP2077MovementDiagnostics").startCapture("observer_placed")
    receipt(r,true,"single_placement_submitted_not_observed")
end)
