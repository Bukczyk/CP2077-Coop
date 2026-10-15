-- Actual CET entrypoint + actual actions/Aim modules. Only native boundaries mocked.
local root=assert(arg[1]);local checks=0
local function check(value,message)checks=checks+1;assert(value,message)end
local function native(id)
    local a={id=id,attached=true,ready=true,crouched=false,drawn=false,weapon="",aiming=false,
        commands={},stops=0,stances=0,items={},grants=0,cancel=true,upper=0}
    function a:GetEntityID()return {hash=self.id}end
    function a:IsAttached()return self.attached end
    function a:GetWorldPosition()return {x=0,y=0,z=0}end
    function a:CP2077Session_ActionCaptureReady()return self.ready end
    function a:CP2077Session_IsCrouched()return self.crouched end
    function a:CP2077Session_IsAiming()return self.aiming end
    function a:CP2077Session_HeldWeapon()return self.weapon end
    function a:CP2077Session_HasPresentationWeapon()return self.drawn end
    function a:CP2077Session_PoseReady()return self.ready end
    function a:CP2077Session_StanceMatches(c) return self.crouched==c end
    function a:CP2077Session_ApplyStance(c)
        if self.probeLocked then return false end
        self.stances=self.stances+1;self.requestedCrouch=c
        if self.afterStance then self.afterStance() end
        return true
    end
    function a:CP2077Session_HasPresentationItem(w)return self.items[w]==true end
    function a:CP2077Session_PresentationGrantCount()return self.grants end
    function a:CP2077Session_EquipPresentation(w,d)
        if self.probeLocked then return nil end
        local cmd={weapon=w,drawn=d};self.commands[#self.commands+1]=cmd
        if self.equipThrow then error("after_possible_equip")end
        if d and not self.items[w] then self.items[w]=true;self.grants=self.grants+1 end
        return cmd
    end
    function a:CP2077Session_StopPresentation(command)
        self.stops=self.stops+1;self.stopped=command;return self.cancel
    end
    function a:complete()
        if self.requestedCrouch~=nil then self.crouched=self.requestedCrouch end
        local c=self.commands[#self.commands];if c then self.weapon,self.drawn=c.weapon,c.drawn end
    end
    function a:CP2077Session_ReadPresentationWeapon(w,d)
        if self.readThrow then error("weapon_read_unknown")end
        return {ownerID=self:GetEntityID(),entityID={hash=self.item or "18446744073709551614ULL"},
            record=self.weapon,appearance="default",spawning=self.slotSpawning==true,
            slotEmpty=not self.drawn,hasItem=self.drawn,attached=self.drawn and self.weaponAttached~=false,
            matches=not self.slotSpawning and self.drawn==d and (not d or self.weapon==w),
            muzzleAvailable=self.drawn,muzzlePosition={x=1,y=2,z=3},muzzleRotation={i=0,j=0,k=0,r=1}}
    end
    function a:CP2077Session_AcquireAimProbe(w,item)
        if self.lease or self.upper~=0 or self.weapon~=w or item.hash~=(self.item or "18446744073709551614ULL") then return nil end
        self.lease={};self.probeLocked=true
        if self.acquireThrow then error("after_possible_lease")end
        return self.lease
    end
    function a:CP2077Session_ReadAimProbe(lease)
        if lease~=self.lease or not self.attached then return -1 end
        if self.upper==1 and lease.requested then lease.seen=true end
        return self.upper
    end
    function a:CP2077Session_RequestAimProbe(lease,aim)
        local state=self:CP2077Session_ReadAimProbe(lease)
        if aim then
            if state~=0 or lease.requested then return false end
            lease.requested=true;self.aimRequests=(self.aimRequests or 0)+1
        else
            if state~=1 or not lease.seen or lease.restore then return false end
            lease.restore=true;self.normalRequests=(self.normalRequests or 0)+1
        end
        if self.aimThrow then error("after_possible_aim")end
        return true
    end
    function a:CP2077Session_ReleaseAimProbe(lease)
        if self:CP2077Session_ReadAimProbe(lease)~=0 or (lease.requested and not lease.restore) then return false end
        self.lease=nil;self.probeLocked=false;return true
    end
    return a
end
local function unref(a)return a and (a.native or a)end
local function wrapper(a)
    if not a then return nil end
    return setmetatable({native=a},{__index=function(_,k)
        local value=a[k]
        if type(value)=="function" then return function(_,...)return value(a,...)end end
        return value
    end})
end
local function setup()
    local w={calls=0,events={},logs={},player=native("9007199254740993ULL"),actor=native("9007199254740995ULL"),
        paused=false,pregame=false,managed=true,spawning=true,spawned=false,creates=0,deletes=0}
    local function touch()w.calls=w.calls+1 end
    local system={}
    function system:IsReady()touch();return not w.systemUnready end
    function system:IsPopulated()touch();return w.oldTag==true end
    function system:CreateEntity(spec)
        touch();w.creates=w.creates+1;w.spec=spec
        if w.createThrow then error("after_possible_creation")end
        if w.createInvalid then return {hash=0}end
        return w.actor:GetEntityID()
    end
    function system:IsManaged()touch();return w.managed end
    function system:IsSpawning()touch();return w.spawning end
    function system:IsSpawned()touch();return w.spawned end
    function system:GetEntity()touch();return w.wrappers and wrapper(w.population) or w.population end
    function system:DeleteEntity(id)
        touch();check(tostring(id.hash)==tostring(w.actor.id),"delete original exact token")
        w.deletes=w.deletes+1;w.deleteId=id
        if w.deleteThrow then error("after_possible_delete")end
        return not w.deleteReject
    end
    w.system=system
    local env={assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,pcall=pcall,
        select=select,setmetatable=setmetatable,tostring=tostring,type=type,math=math,string=string,table=table}
    env.print=function(s)w.logs[#w.logs+1]=s end
    env.registerForEvent=function(name,fn)w.events[name]=fn end
    env.CName={new=function(v)touch();return v end};env.TweakDBID=env.CName
    env.DynamicEntitySpec={new=function()touch();return {}end}
    env.Vector4={new=function(x,y,z,t)touch();return {x=x,y=y,z=z,w=t}end}
    env.Quaternion={new=function(i,j,k,r)touch();return {i=i,j=j,k=k,r=r}end}
    env.Game={
        GetPlayer=function()touch();if w.playerThrow then error("player getter")end;return w.wrappers and wrapper(w.player) or w.player end,
        GetSystemRequestsHandler=function()
            touch();if w.handlerThrow then error("handler getter")end
            return {IsGamePaused=function()return w.paused end,IsPreGame=function()return w.pregame end}
        end,
        GetDynamicEntitySystem=function()touch();return w.currentSystem or system end,
        FindEntityByID=function(id)touch();return w.wrappers and wrapper(w.world) or w.world end}
    env.CP2077PlayerPresentation={SupportedWeapon=function(v)touch();return v=="Items.Pistol" or v=="Items.Rifle" end}
    env.CP2077ActionFixture={
        Same=function(a,b)touch();return unref(a)==unref(b)end,
        Context=function(current,original)
            touch();if not current or not original or not unref(current).attached then return -1 end
            return unref(current)==unref(original) and 1 or 0
        end,
        Actor=function(context,original,id,population)
            touch();if w.identityUnknown then return -1 end
            if not context or not original or not w.world or not population or not unref(original).attached then return -1 end
            return unref(original)==unref(w.world) and unref(original)==unref(population)
                and tostring(original:GetEntityID().hash)==tostring(id.hash) and 1 or 0
        end}
    -- CET resolves literal mod-local filenames, with no package or global fallback.
    local cache={}
    env.require=function(name)
        check(name:match("^[a-z_]+$")~=nil,"literal bounded local module path")
        if cache[name] then return cache[name]end
        local path=root.."/experiments/player-presentation/"..name..".lua"
        local fn
        if setfenv then fn=assert(loadfile(path));setfenv(fn,env)else fn=assert(loadfile(path,"t",env))end
        cache[name]=fn();return cache[name]
    end
    w.api=env.require("init");w.env=env
    check(env.package==nil and w.calls==0 and w.creates==0,"loading entrypoint performs no engine operation")
    function w:tick(dt)self.events.onUpdate(dt==nil and 0.1 or dt)end
    function w:attach()self.world,self.population=self.actor,self.actor;self.spawning=false;self.spawned=true end
    function w:disappear()
        self.actor.attached=false;self.world,self.population=nil,nil
        self.managed,self.spawning,self.spawned=false,false,false
    end
    function w:start()
        self.g=assert(self.api.start({x=4,y=0,z=0,yaw=45}));self:tick();self:attach();self:tick();self:tick()
        check(self.api.status().phase=="ready" and self.creates==1,"one explicit owned actor becomes ready")
    end
    function w:capture(weapon,crouched,aiming)
        self.player.weapon,self.player.drawn=weapon or "",weapon~=nil
        self.player.crouched,self.player.aiming=crouched==true,aiming==true
        check(self.api.capture(self.g),"capture admitted")
        self:tick();self.actor:complete();self:tick();self:tick()
    end
    function w:finish()
        self:disappear();self:tick();self:tick();self:tick();self:tick()
        check(self.api.status().phase=="retired","exact absent lifecycle observed")
    end
    return w
end

if arg[2]=="helper" then return {setup=setup,native=native,check=check} end

local w=setup()
check(not w.api.start({x=0/0,y=0,z=0,yaw=0}),"invalid public pose")
local calls=w.calls;local g=assert(w.api.start({x=4,y=0,z=0,yaw=45}))
check(w.calls==calls and w.creates==0,"start is queued only")
check(not w.api.start({x=4,y=0,z=0,yaw=45}),"second activation cannot overwrite ownership")
check(w.api.stop() and w.calls==calls,"stop is queued only")
w:tick();check(w.creates==0 and w.api.status().phase=="retired","cancel before native creation")
w:start();w:capture("Items.Pistol",true,false)
check(w.api.status().actions.status=="observed" and w.actor.crouched and w.actor.drawn,"actual controller draws and crouches")
w:capture("Items.Rifle",false,false)
check(w.actor.weapon=="Items.Rifle" and not w.actor.crouched,"actual controller switches and stands")
w:capture(nil,true,false)
check(not w.actor.drawn and w.actor.crouched,"actual controller holsters")
local s=w.api.status();s.actions.serial=-2
check(w.api.status().actions.serial==3 and w.api.status().visualQualified==false,"copied status and no visual claim")
calls=w.calls;check(w.api.capture(w.g) and w.api.capture(w.g),"coalesced captures admitted")
check(w.calls==calls,"capture/status API has no engine calls")
w:tick();check(w.api.status().serial==4,"coalesced captures use one fresh native sample")
check(not w.api.capture(w.g-1) and not w.api.aim(w.g-1),"stale generation rejected")
w.api.stop();w:tick();check(w.deletes==1 and w.api.status().phase=="stopping","acceptance is not disappearance")
w:tick();check(w.deletes==1 and w.api.status().owned,"no repeated deletion")
w:finish();w.actor=native("9007199254740997ULL");w.managed=true;w.spawning=true;w.spawned=false
w.g=assert(w.api.start({x=4,y=0,z=0,yaw=0}));w:tick();w:attach();w:tick();w:tick();w:capture("Items.Pistol")
w.api.stop();w:tick();check(w.api.status().reason=="delete_submitted","new generation has monotonic fresh module clock")

-- Actual Aim lease, pending stop must drain Aim before restoring Normal.
w=setup();w:start();w:capture("Items.Pistol",false,true)
check(w.api.status().actions.reason=="ads_unavailable","captured held aim does not claim ADS")
calls=w.calls;check(w.api.aim(w.g) and w.calls==calls,"Aim is explicit and queued")
w:tick();check(w.actor.aimRequests==1 and w.api.status().probe.phase=="awaiting_aim","actual probe submits Aim")
w.api.stop();w:tick()
check(w.deletes==0 and not w.actor.normalRequests,"pending Aim must drain, no early deletion")
w.actor.upper=1;w:tick();check(w.actor.normalRequests==1 and w.deletes==0,"stop requests Normal only after Aim readback")
w.actor.upper=0;for _=1,4 do w:tick()end
check(w.deletes==1 and w.api.status().probe.cleanupConfirmed,"settled Normal releases lease before exact retirement")
w:finish();check(w.api.status().probe==nil and w.api.status().actions==nil,"module references released only after actor retirement")

-- Freeze all work for pause, pregame, unknown/throwing context and invalid delta.
for _,mode in ipairs({"paused","pregame","pause_unknown","pregame_unknown","handler_throw","player_throw","invalid_delta"}) do
    w=setup();w:start();w:capture("Items.Pistol",false,true);assert(w.api.aim(w.g));w:tick()
    local age=w.api.status().probe.activeSeconds
    if mode=="paused" then w.paused=true elseif mode=="pregame" then w.pregame=true
    elseif mode=="pause_unknown" then w.paused=nil elseif mode=="pregame_unknown" then w.pregame=nil
    elseif mode=="handler_throw" then w.handlerThrow=true elseif mode=="player_throw" then w.playerThrow=true end
    w.api.stop();for _=1,5 do w:tick(mode=="invalid_delta" and math.huge or 1)end
    check(w.deletes==0 and w.api.status().probe.activeSeconds==age,"unknown interval freezes module "..mode)
    w.paused,w.pregame,w.handlerThrow,w.playerThrow=false,false,false,false
    w.actor.upper=1;w:tick();check(w.actor.normalRequests==1,"fresh context drains instead of consuming skipped time "..mode)
    w.actor.upper=0;for _=1,4 do w:tick()end
    check(w.deletes==1,"clean stop recovers after "..mode)
end

-- Late creation is retained, even if all creator flags temporarily report false.
w=setup();w.g=assert(w.api.start({x=4,y=0,z=0,yaw=0}));w:tick();w.api.stop()
w.managed,w.spawning,w.spawned=false,false,false
for _=1,5 do w:tick()end
check(w.deletes==0 and w.api.status().owned,"absent never-attached token is never canceled early")
w.managed=true;w:attach();w:tick();check(w.deletes==0,"first attachment observation insufficient")
w:tick(0);check(w.deletes==0,"same-time observation cannot qualify deletion")
w:tick();check(w.deletes==0,"same-time break requires fresh pair")
w:tick();check(w.deletes==1,"stable completed creation permits retirement")
w:finish()
for _,field in ipairs({"managed","spawning","spawned"})do
    w=setup();w:start();w.api.stop();local prior=w[field];w[field]=nil;w:tick()
    check(w.deletes==0 and w.api.status().owned,"nil lifecycle blocks "..field)
    w[field]=prior;w:tick();check(w.deletes==0,"fresh pair after unknown "..field)
    w:tick();check(w.deletes==1,"explicit lifecycle recovers "..field)
end
for _,field in ipairs({"createThrow","createInvalid"})do
    w=setup();w[field]=true;assert(w.api.start({x=4,y=0,z=0,yaw=0}));w:tick();w.api.stop()
    for _=1,5 do w:tick()end
    check(w.creates==1 and w.deletes==0 and w.api.status().owned,"unknown creation retained "..field)
end
w=setup();w.oldTag=true;assert(w.api.start({x=4,y=0,z=0,yaw=0}));w:tick();w.api.stop();w:tick()
check(w.creates==0 and w.deletes==0 and w.api.status().phase=="retired","old tag blocks spawn without adoption/deletion")

-- Original creator and native references, including large IDs and fresh wrappers.
w=setup();w.wrappers=true;w:start();w.currentSystem={IsReady=function()error("replacement manager touched")end}
w:capture("Items.Pistol");w.api.stop();w:tick();check(w.deletes==1,"creator remains pinned despite global system replacement")
w:finish()
for _,where in ipairs({"world","population","both","player"})do
    w=setup();w:start();local original=w.actor
    local replacement=native(where=="player" and w.player.id or original.id)
    if where=="world" then w.world=replacement elseif where=="population" then w.population=replacement
    elseif where=="both" then w.world,w.population=replacement,replacement else w.player=replacement end
    check(w.api.capture(w.g),"cached admission remains queued before replacement read")
    w:tick();w.api.stop();w:tick();w:tick()
    check(w.deletes==0 and #replacement.commands==0 and #original.commands==0,"same-ID replacement never mutated "..where)
end
w=setup();w:start();w.actor.afterStance=function()w.world=native(w.actor.id)end
w.player.weapon,w.player.drawn,w.player.crouched="Items.Pistol",true,true;assert(w.api.capture(w.g));w:tick()
check(w.actor.stances==1 and #w.actor.commands==0,"native actor guard repeats between stance and equip")
w=setup();w:start();w:capture("Items.Pistol");w.api.stop();w:tick()
w.world,w.population=nil,nil;w.managed,w.spawning,w.spawned=false,false,false
for _=1,8 do w:tick()end
check(w.api.status().owned and w.actor.attached,"retained attached handle blocks false absence")
w.actor.attached=false;w:tick();w.paused=true;w:tick();w.paused=false;w:tick();w:tick()
check(w.api.status().phase=="stopping","pause invalidates quiet interval")
w:tick();w:tick();check(w.api.status().phase=="retired","fresh uninterrupted absence recovers")

-- Explicit uncertain module retirement, with all module handles retained until proof.
for _,mode in ipairs({"equip","acquire","aim","cancel","delete"})do
    w=setup();w:start()
    if mode=="equip" then w.actor.equipThrow=true
    elseif mode=="acquire" then w.actor.acquireThrow=true
    elseif mode=="aim" then w.actor.aimThrow=true
    elseif mode=="cancel" then w.actor.cancel=false
    else w.deleteThrow=true end
    if mode=="cancel" then
        w.player.weapon,w.player.drawn="Items.Pistol",true;assert(w.api.capture(w.g));w:tick()
    else w:capture("Items.Pistol",false,mode=="acquire" or mode=="aim")end
    if mode=="acquire" or mode=="aim" then assert(w.api.aim(w.g));w:tick()end
    w.api.stop();w:tick();w:tick()
    check(w.deletes==1 and w.api.status().actions~=nil and w.api.status().owned,"uncertain ownership retained "..mode)
    if mode=="acquire" or mode=="aim" then check(w.api.status().probe.retirementRequired,"failed lease retained "..mode)end
    w:finish();check(w.api.status().actions==nil and w.api.status().probe==nil,"exact retirement releases uncertain "..mode)
end
w=setup();w:start();w:capture("Items.Katana")
check(w.api.status().reason=="awaiting_capture" or w.api.status().reason=="unsupported_weapon","unsupported capture remains explicit")
check(#w.actor.commands==0,"unsupported weapon never substituted")
w.events.onShutdown();calls=w.calls
check(not w.api.start({x=4,y=0,z=0,yaw=0}) and not w.api.capture(w.g),"shutdown closes public admission")
check(w.calls==calls and w.deletes==0,"shutdown callback is queue-only and cannot claim cleanup")
w:tick();check(w.deletes==1,"continued update can retire shutdown-owned actor")
check(#w.logs<=64,"bounded diagnostics")

-- Follow is a fresh bounded producer, not replay of an expired captured state.
w=setup();w:start();w:capture("Items.Pistol",false,false)
local originalSerial=w.api.status().serial
for _=1,70 do w:tick()end
check(w.api.status().phase=="ready" and w.api.status().actions.status=="observed",
    "fresh follow remains usable beyond original five-second freshness")
check(w.api.status().serial>originalSerial and w.api.status().serial<35,"capture cadence is bounded")
check(#w.actor.commands==1,"unchanged follow never floods equipment commands")
local serial=w.api.status().serial;w.player.ready=false
for _=1,4 do w:tick()end
check(w.api.status().phase=="failed" and w.api.status().serial==serial,"failed capture never refreshes stale desired state")
check(w.api.status().reason=="capture_unavailable","failed capture reason remains explicit")
w=setup();w:start();w:capture("Items.Pistol",false,false)
check(w.api.aim(w.g),"aim request needs no physical held aim")
w:tick()
check(w.api.status().captureIntent=="injected_local_aim" and w.actor.aimRequests==1,
    "injected fixture Aim is labeled and uses actual current local weapon")
w.player.weapon,w.player.crouched="Items.Rifle",true
local commands=#w.actor.commands;serial=w.api.status().serial
w.actor.upper=1;w:tick();for _=1,9 do w:tick()end
check(#w.actor.commands==commands and w.api.status().serial==serial,"following stops while Aim lease owns actor")
w:tick();w:tick();check(w.actor.normalRequests==1,"explicit probe hold eventually requests Normal")
w.actor.upper=0;for _=1,4 do w:tick()end
check(w.api.status().probe.cleanupConfirmed and #w.actor.commands==commands,"Normal cleanup precedes follow resumption")
w:tick();w.actor:complete();w:tick();w:tick()
check(w.actor.weapon=="Items.Rifle" and w.actor.crouched and w.api.status().captureIntent=="observed_local_state",
    "fresh changed local state follows only after probe releases")

-- Pre-create failures happen before native submission and do not claim an unknown creation.
for _,mode in ipairs({"pause","player","id"})do
    w=setup()
    function w.player:GetWorldPosition()
        if mode=="pause" then w.paused=true elseif mode=="player" then w.player=native(self.id) else self.id="9007199254740994ULL" end
        return {x=0,y=0,z=0}
    end
    assert(w.api.start({x=4,y=0,z=0,yaw=0}));w:tick()
    check(w.creates==0 and not w.api.status().creationAttempted,"fresh final create preflight rejects "..mode)
    w.api.stop();w:tick()
    check(w.api.status().phase=="retired" and w.deletes==0,"definitely unsubmitted work closes without original context "..mode)
end
w=setup();w:start();w.player.id="9007199254740994ULL";assert(w.api.capture(w.g));w:tick();w.api.stop();w:tick()
check(w.deletes==0 and #w.actor.commands==0,"original player reference cannot change its frozen ID")

w=setup();w:start();w:capture("Items.Pistol",false,true);assert(w.api.aim(w.g));w:tick()
local probe=w.api.status().probe;check(probe.reservationHeld,"external removal starts with real probe ownership")
w:disappear();w.api.stop();w:tick();w:tick()
check(w.api.status().owned and w.api.status().probe~=nil and w.deletes==0,"external completed removal retains handles while qualifying")
w.paused=true;w:tick();w.paused=false;w:tick();w:tick()
check(w.api.status().owned,"external absence qualification resets after pause")
w:tick();w:tick()
check(w.api.status().phase=="retired" and w.api.status().probe==nil and w.deletes==0
    and w.api.status().cleanupRoute=="completed_actor_external_removal","proven completed external disappearance releases without deletion")
w=setup();w:start();w:disappear();w.api.stop();w:tick();w:tick()
w.world=w.actor;w:tick();w.world=nil;w:tick();w:tick()
check(w.api.status().owned,"present detached lookup interrupts external absence")
w:tick();w:tick();check(w.api.status().phase=="retired" and w.deletes==0,"external absence needs fresh continuous interval")
w=setup();w:start();w:capture("Items.Pistol",false,true);assert(w.api.aim(w.g));w:tick()
w:disappear();w.api.stop();w:tick()
w.actor.attached=true;w.managed=true;w:attach();w:tick();w:tick()
check(w.deletes==0 and w.api.status().reason=="draining_aim_probe"
    and w.api.status().cleanupRoute==nil,"interrupted external route cannot skip returned actor's Aim drain")
w.actor.upper=1;w:tick();w.actor.upper=0;for _=1,4 do w:tick()end
check(w.deletes==1 and w.api.status().probe.cleanupConfirmed,"returned exact actor follows normal cleanup")

-- IDs cross the native boundary without Lua double conversion.
local ffiOk,ffi=pcall(require,"ffi")
if ffiOk then
    w=setup();w.player.id=ffi.new("uint64_t",9007199254740992)+1
    w.actor.id=ffi.new("uint64_t",9007199254740992)+3
    w:start();w:capture("Items.Pistol");w.api.stop();w:tick()
    check(w.api.status().entity=="9007199254740995" and w.deletes==1,"real LuaJIT Uint64 remains exact")
end
print("player_presentation_fixture: "..checks.." checks")
