local root=assert(arg[1])
package.path=root.."/runtime/session/cet/CP2077Coop/?.lua;"..package.path
local Pose=assert(require("player_pose"))
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function actor(key)
    local a={key=key or "9007199254740993ULL",position={x=1,y=2,z=3},yaw=0,
        attached=true,ready=true,accept=true,cancel=true,commands={},stops=0}
    function a:GetEntityID() return {hash=setmetatable({},{__tostring=function() return self.key end})} end
    function a:IsAttached() return self.attached end
    function a:CP2077Session_PoseReady() return self.ready end
    function a:GetWorldPosition() return self.position end
    function a:GetWorldOrientation() return {ToEulerAngles=function() return {yaw=self.yaw} end} end
    function a:CP2077Session_SubmitPose(x,y,z,yaw)
        if not self.accept then return nil end
        local c={x=x,y=y,z=z,yaw=yaw,state=1}
        self.commands[#self.commands+1]=c
        return c
    end
    function a:CP2077Session_PoseState(c) return c.state end
    function a:CP2077Session_StopPose(c)
        self.stops=self.stops+1
        if self.cancel then c.state=3; return true end
        return false
    end
    function a:complete(c)
        self.position={x=c.x,y=c.y,z=c.z}; self.yaw=c.yaw; c.state=5
    end
    return a
end
local target={x=10,y=20,z=30,yaw=math.pi/2}
local a,p=actor(),Pose.new()
check(p:step(a,target,0)=="pending","first exact actor command")
check(#a.commands==1 and a.commands[1].yaw==90,"one radians to degrees conversion")
local latest={x=14,y=20,z=30,yaw=math.pi}
for i=1,50 do p:step(a,latest,i/100) end
check(#a.commands==1,"queued command must not be overwritten every frame")
a.commands[1].state=5
check(p:step(a,latest,0.6)=="pending" and #a.commands==1,"engine Success alone cannot prove movement")
a:complete(a.commands[1]); p:step(a,latest,0.7)
check(#a.commands==2 and a.commands[2].x==14 and a.commands[2].yaw==180,"next command uses newest target")
a:complete(a.commands[2]); a.yaw=-180
check(p:step(a,latest,0.8)=="observed","shortest wrapped yaw readback")
check(p.failures==0 and p.command==nil,"only readback retires completed command")

-- Actor creation may precede placement or AI availability. Neither is success.
for _, unavailable in ipairs({"origin","controller","attachment"}) do
    a,p=actor(),Pose.new()
    if unavailable=="origin" then a.position={x=0,y=0,z=0}
    elseif unavailable=="controller" then a.ready=false else a.attached=false end
    for i=0,20 do p:step(a,target,i/10) end
    check(#a.commands==0 and p.fault==nil,unavailable.." waits without a command queue")
    if unavailable=="origin" then a.position={x=1,y=2,z=3}
    elseif unavailable=="controller" then a.ready=true else a.attached=true end
    check(p:step(a,target,2.1)=="pending" and #a.commands==1,unavailable.." recovers before deadline")
end
a,p=actor(),Pose.new(); a.position={x=0,y=0,z=0}
p:step(a,target,0); p:step(a,target,3.1)
check(p.fault=="placement_timeout" and #a.commands==0,"placement failure is bounded")

-- Dropped commands receive at most three attempts, then require a lifetime reset.
a,p=actor(),Pose.new()
for _, now in ipairs({0,1.01,1.2,2.21,2.4,3.41,9}) do p:step(a,target,now) end
check(#a.commands==3 and p.fault=="readback_timeout","no indefinite teleport flood")
p:reset(); check(p:step(a,target,10)=="pending","explicit lifecycle reset permits a new diagnostic")
a,p=actor(),Pose.new(); a.accept=false
for _, now in ipairs({0,1,2}) do p:step(a,target,now) end
check(p.fault==nil,"initial submission rejection allows bounded AI initialization")
for _, now in ipairs({3.01,3.12,3.23,9}) do p:step(a,target,now) end
check(p.fault=="submission_rejected" and #a.commands==0,"rejected submissions are bounded")

-- Failed cancellation cannot silently drop ownership and stack another command.
a,p=actor(),Pose.new(); p:step(a,target,0); a.cancel=false; a.commands[1].state=0
p:step(a,latest,1.01); p:step(a,latest,9)
check(p.fault=="cancellation_unconfirmed" and #a.commands==1 and p.command==a.commands[1],"retain unretired command")
local replacement=actor("9007199254740994ULL")
p:step(replacement,latest,10)
check(#replacement.commands==1 and p.key==replacement.key,"adjacent opaque IDs reset exactly")
check(a.stops>=2,"replacement attempts cleanup only on its old exact actor")
p:reset(); check(replacement.stops==1,"reset cancels own pending command")
a,p=actor(),Pose.new(); p:step(a,{x=0/0,y=0,z=1,yaw=0},0)
check(p.fault=="invalid_pose" and #a.commands==0,"nonfinite target fails closed")

-- Run the real entrypoint: a silent TeleportationFacility NPC no-op must not
-- freeze the remote actor again. Interpolation changes while a command is pending.
local callbacks,hotkeys,logs={},{},{}
local originalPrint=print
print=function(v) logs[#logs+1]=v end
registerForEvent=function(k,v) callbacks[k]=v end
registerHotkey=function(k,_,v) hotkeys[k]=v end
Observe=function() end
CName={new=function(v) return v end}
package.loaded.config={experimentalNpcReplication=false}
a=actor(); local localPlayer=actor("101ULL")
local remoteVisible,frameGeneration,wireEntity,desiredX=true,1,"2ULL",10
local deleted,calls=0,0
local system={}
function system:IsReady() return true end
function system:GetTagged() return remoteVisible and {a} or {} end
function system:DeleteTagged() deleted=deleted+1 end
Game={
    GetPlayer=function() return localPlayer end,
    GetSystemRequestsHandler=function() return nil end,
    GetDynamicEntitySystem=function() return system end,
    GetTeleportationFacility=function() return {Teleport=function() calls=calls+1 end} end,
    CP2077Session_ExperimentalStaticNpcProjection=function() return false end,
    CP2077Session_SetActive=function() end, CP2077Session_PushLocal=function() end,
    CP2077Session_BeginFrame=function() return remoteVisible and 1 or 0 end,
    CP2077Session_Generation=function() return frameGeneration end,
    CP2077Session_Session=function() return "10ULL" end, CP2077Session_Epoch=function() return 1 end,
    CP2077Session_Phase=function() return 4 end, CP2077Session_Bind=function() return true end,
    CP2077Session_SelfEntity=function() return "1ULL" end,
    CP2077Session_BubbleRadius=function() return 100 end,
    CP2077Session_Select=function() return true end, CP2077Session_Player=function() return 2 end,
    CP2077Session_Entity=function() return wireEntity end,
    CP2077Session_X=function() return desiredX end, CP2077Session_Y=function() return 2 end,
    CP2077Session_Z=function() return 3 end, CP2077Session_Yaw=function() return math.pi/2 end,
    CP2077Session_Self=function() return 1 end, CP2077Session_Host=function() return 1 end,
}
assert(loadfile(root.."/runtime/session/cet/CP2077Coop/init.lua"))()
callbacks.onInit(); callbacks.onUpdate(0.01)
check(#a.commands==1 and calls==0,"entrypoint uses AI actuator, not silent facility no-op")
desiredX=13; callbacks.onUpdate(0.2)
check(#a.commands==1,"entrypoint preserves pending command")
a:complete(a.commands[1]); callbacks.onUpdate(0.2)
check(#a.commands==2 and a.commands[2].x==13,"entrypoint follows latest native sample")
remoteVisible=false; callbacks.onUpdate(0.2)
check(a.stops==2 and deleted>=2,"interest removal retires pending handle before deletion")
remoteVisible=true; callbacks.onUpdate(0.2)
local before=a.stops; frameGeneration=2; callbacks.onUpdate(0.2)
check(a.stops>before,"session generation reset retires old handle")
before=a.stops; wireEntity="9007199254740993ULL"; callbacks.onUpdate(0.2)
check(a.stops>before,"same PlayerId with different exact session identity retires old handle")
before=a.stops; callbacks.onShutdown()
check(a.stops>before,"shutdown retires owned handle")
for _,line in ipairs(logs) do check(not line:find("BRIDGE_ERROR",1,true),line) end
print=originalPrint
print("player_pose: PASS ("..checks.." checks; scheduling is not movement; bounded retries and exact lifecycle)")
