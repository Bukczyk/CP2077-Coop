local root=assert(arg[1])
local Actions=assert(loadfile(root.."/experiments/player-presentation/actions.lua"))()
local checks=0
local function check(v,message) checks=checks+1; assert(v,message) end
local function actor(id)
    local a={id=id,attached=true,ready=true,crouched=false,drawn=false,weapon="",commands={},stops=0,stances=0,cancel=true,items={},grants=0}
    function a:GetEntityID() return {hash=self.id} end
    function a:IsAttached() return self.attached end
    function a:CP2077Session_PoseReady() return self.ready end
    function a:CP2077Session_StanceMatches(crouched) return self.crouched==crouched end
    function a:CP2077Session_HeldPresentationMatches(weapon,drawn)
        return self.drawn==drawn and (not drawn or self.weapon==weapon)
    end
    function a:CP2077Session_ApplyStance(crouched)
        if self.probeLocked then return false end
        self.stances=self.stances+1; self.requestedCrouch=crouched; return true
    end
    function a:CP2077Session_HasPresentationItem(weapon) return self.items[weapon]==true end
    function a:CP2077Session_PresentationGrantCount() return self.grants end
    function a:CP2077Session_EquipPresentation(weapon,drawn)
        if self.reject or self.probeLocked then return nil end
        if self.throw then error("uncertain queue result") end
        if drawn and not self.items[weapon] then self.items[weapon]=true; self.grants=self.grants+1 end
        local command={weapon=weapon,drawn=drawn}; self.commands[#self.commands+1]=command; return command
    end
    function a:CP2077Session_StopPresentation(command) self.stops=self.stops+1; return self.cancel end
    function a:complete()
        self.crouched=self.requestedCrouch or false
        local c=self.commands[#self.commands]; if c then self.weapon,self.drawn=c.weapon,c.drawn end
    end
    function a:CP2077Session_ActionCaptureReady() return self.ready end
    function a:CP2077Session_IsCrouched() return self.crouched end
    function a:CP2077Session_IsAiming() return self.aiming or false end
    function a:CP2077Session_HeldWeapon() return self.weapon end
    function a:CP2077Session_HasPresentationWeapon() return self.drawn end
    return a
end
local function supported(weapon) return weapon=="Items.Pistol" or weapon=="Items.Rifle" end
local function state(weapon,crouched,aiming)
    return {weapon=weapon or "",drawn=weapon~=nil,crouched=crouched or false,aiming=aiming or false}
end
local function fixture(config)
    local map={}; config=config or {}; config.resolve=function(k) return map[k] end; config.supported=config.supported or supported
    local controller=assert(Actions.new(config)); assert(controller:reset("session:epoch:membership",0))
    return controller,map
end
local scope="session:epoch:membership"
local p,map=fixture()
local a,b,c=actor("9007199254740993ULL"),actor("9007199254740994ULL"),actor("9007199254740995ULL")
for i,entry in ipairs({a,b,c}) do
    local id=tostring(i); map[id]=entry
    check(p:stage(scope,id,1,state("Items.Pistol",i~=2),0),"stage independent player")
    check(p:step(scope,id,0)=="queued" and #entry.commands==0,"pre-bind state stays pending")
    check(p:bind(scope,id,entry,0),"bind exact large local ID")
    check(p:step(scope,id,0)=="queued" and #entry.commands==1,"queue per-player handle")
    check(p:inspect(id).weapon=="queued","queued equip is not observed")
end
a:complete(); p:step(scope,"1",0.1)
check(p:step(scope,"1",0.1)=="observed","readback confirms first player only")
check(p:inspect("2").commandOwned and p:inspect("3").commandOwned,"other handles untouched")
check(a.stops==1 and b.stops==0 and c.stops==0,"cancel exact completed command only")
b:complete(); c:complete()
for _,id in ipairs({"2","3"}) do p:step(scope,id,0.2); check(p:step(scope,id,0.2)=="observed","three independent readbacks") end

-- Draw -> switch -> holster, coalescing many updates without queue flooding.
check(p:stage(scope,"1",2,state("Items.Rifle",false),0.3),"switch weapon/stand")
p:step(scope,"1",0.3)
for i=3,50 do check(p:stage(scope,"1",i,state(nil,true),0.3),"coalesce latest state") end
p:step(scope,"1",0.4)
check(#a.commands==2 and a.commands[2].weapon=="Items.Rifle","newest state does not replace owned command")
a:complete(); p:step(scope,"1",0.5); p:step(scope,"1",0.5)
check(#a.commands==3 and not a.commands[3].drawn,"latest holster is queued after switch readback")
a:complete(); p:step(scope,"1",0.6)
check(p:step(scope,"1",0.6)=="observed" and a.crouched and not a.drawn,"holster plus crouch observed")
local original=p:inspect("1"); original.serial=0
check(p:inspect("1").serial==50,"diagnostics are detached")
check(not p:stage(scope,"1",50,state(),0.6),"duplicate serial rejected")
check(not p:stage(scope,"1",49,state(),0.6),"reordered serial rejected")
check(not p:stage("old epoch","1",51,state(),0.6),"old scope rejected")
check(not p:stage(scope,"1",0/0,state(),0.6),"nonfinite serial rejected")
check(not p:stage(scope,"1",51,{weapon="Items.Pistol",drawn=1,crouched=false,aiming=false},0.6),"invalid boolean rejected")
for _,weapon in ipairs({"Clothing.Coat","Items.Fists","Items.MantisBlades","Items.QuestProp","Items.Missing"}) do
    local ok,reason=p:stage(scope,"1",51,state(weapon),0.6)
    check(not ok and reason=="unsupported_weapon","unsupported record explicitly rejected")
end
check(#a.commands==3,"invalid state never mutates actor")

-- Aim transitions are captured but receiver explicitly lacks ADS animation.
a.weapon,a.drawn,a.aiming="Items.Pistol",true,true
local capture=assert(Actions.capture(a,supported))
check(capture.aiming and capture.drawn and capture.weapon=="Items.Pistol","capture held aim and exact record")
check(p:stage(scope,"1",51,capture,0.7),"prepare captured aim")
local status,reason=p:step(scope,"1",0.7)
check(status=="partial" and reason=="ads_unavailable","matching equipment never invents ADS success")
check(p:inspect("1").aim=="unsupported" and p:inspect("1").weapon=="observed","separate supported readback and unsupported aim")
a.aiming=false; check(p:stage(scope,"1",52,assert(Actions.capture(a,supported)),0.8),"capture aim release")
check(p:step(scope,"1",0.8)=="observed","aim release does not claim an ADS animation hook")
a.ready=false; check(Actions.capture(a,supported)==nil,"unready capture not false standing")
a.ready=true; a.weapon="Items.Fists"; check(Actions.capture(a,supported)==nil,"unsupported capture explicit")

-- Pause does not spend readback deadlines. Fresh updates cannot extend a stuck command.
p,map=fixture(); a=actor("100ULL"); map.a=a
p:stage(scope,"a",1,state("Items.Pistol"),0); p:bind(scope,"a",a,0); p:step(scope,"a",0)
p:step(scope,"a",0.2,true); p:step(scope,"a",20,true); p:step(scope,"a",20.1,false)
check(p:inspect("a").status=="queued" and #a.commands==1,"pause retains one command")
p:stage(scope,"a",2,state("Items.Rifle"),21); p:step(scope,"a",21)
check(p:step(scope,"a",22.2)=="failed" and p:inspect("a").reason=="readback_timeout","admitted deadline remains bounded")
check(#a.commands==1 and a.stops==1,"timeout retires command without retries")
check(not p:stage(scope,"a",3,state(),22.3),"failed lifetime cannot silently restart")

-- Cleanup must retire exact command; failure blocks replacement and scope reset.
p,map=fixture(); a=actor("101ULL"); map.a=a
p:stage(scope,"a",1,state("Items.Pistol"),0); p:bind(scope,"a",a,0); p:step(scope,"a",0); a.cancel=false
check(not p:unbind(scope,"a",a.id,0.1),"failed cancellation refuses unbind")
check(not p:reset("new scope",0.1) and p:inspect("a").commandOwned,"failed cancellation refuses scope reset")
a.cancel=true
check(p:unbind(scope,"a",a.id,0.2),"explicit release retry")
check(not p:stage(scope,"a",1,state(),0.2),"unbound serial tombstone rejects replay")
b=actor("102ULL"); map.a=b
check(p:bind(scope,"a",b,0.2),"replacement can bind only after release")
check(p:step(scope,"a",0.2)=="queued" and #b.commands==0,"replacement requires fresh state")
check(p:stage(scope,"a",2,state("Items.Rifle"),0.2),"fresh replacement state")
p:step(scope,"a",0.2)
check(#b.commands==1,"fresh state applied to replacement")
check(p:reset("new scope",0.3) and p:size()==0 and b.stops==1,"reset retires owned commands and pending state")
check(not p:stage(scope,"a",3,state(),0.3),"old membership cannot mutate fresh scope")

-- Replacement mapping and mutable IDs are never used to target a nearby actor.
for _,mode in ipairs({"replacement","identity"}) do
    p,map=fixture(); a=actor("200ULL"); b=actor("201ULL"); map.a=a
    p:stage(scope,"a",1,state("Items.Pistol"),0); p:bind(scope,"a",a,0); p:step(scope,"a",0)
    if mode=="replacement" then map.a=b else a.id="202ULL" end
    check(p:step(scope,"a",0.1)=="failed" and p:inspect("a").reason=="mapping_changed","exact mapping guard")
    check(#b.commands==0 and b.stops==0,"replacement never mutated")
end
p,map=fixture({capacity=2}); a=actor("300ULL"); map.a=a; map.b=a
p:stage(scope,"a",1,state(),0); p:stage(scope,"b",1,state(),0); p:bind(scope,"a",a,0)
check(not p:bind(scope,"b",a,0),"two players cannot own one actor")
check(not p:stage(scope,"c",1,state(),0) and p:size()==2,"capacity rejects without eviction")
check(p:step(scope,"b",5)=="failed" and p:inspect("b").reason=="state_expired","unbound state expires")

-- Exceptions and rejection have explicit outcomes, not observed equipment.
for _,mode in ipairs({"reject","throw","readback"}) do
    p,map=fixture(); a=actor("400ULL"); map.a=a
    if mode=="readback" then function a:CP2077Session_HeldPresentationMatches() error("unavailable") end else a[mode]=true end
    p:stage(scope,"a",1,state("Items.Pistol"),0); p:bind(scope,"a",a,0)
    check(p:step(scope,"a",0)=="failed","adapter error explicitly fails")
    if mode=="throw" then check(not p:reset("next scope",1),"uncertain submission retains ownership barrier") end
end
p,map=fixture(); p:stage(scope,"a",1,state(),0)
check(p:step(scope,"a",-1)=="failed","backward clock rejected")
check(p:step(scope,"a",math.huge)=="failed","infinite clock rejected")
check(Actions.new({resolve=function() end,capacity=0})==nil,"invalid bounds rejected")

-- CET can return distinct wrappers for the same exact native entity.
p,map=fixture(); a=actor("500ULL")
map.a=setmetatable({}, {__index=a})
p:stage(scope,"a",1,state("Items.Pistol"),0)
check(p:bind(scope,"a",a,0),"bind accepts exact-ID wrapper churn")
map.a=setmetatable({}, {__index=a})
check(p:step(scope,"a",0)=="queued" and #a.commands==1,"step accepts replacement wrapper of same native actor")
a:complete(); map.a=setmetatable({}, {__index=a}); p:step(scope,"a",0.1)
check(p:step(scope,"a",0.1)=="observed","wrapper churn preserves exact command ownership")

-- Grant cap is actor-local, survives rebinding, and excludes existing inventory.
p,map=fixture({supported=function(record) return type(record)=="string" end})
a=actor("600ULL"); map.a=a
a.items["Items.Existing"]=true
for i=1,8 do
    p:stage(scope,"a",i,state("Items.Allowed"..i),i/10)
    if i==1 then p:bind(scope,"a",a,i/10) end
    check(p:step(scope,"a",i/10)=="queued","bounded new item grant")
    a:complete(); p:step(scope,"a",i/10); p:step(scope,"a",i/10)
end
check(a.grants==8 and #a.commands==8,"exact actor has eight tracked grants")
p:stage(scope,"a",9,state("Items.Existing"),0.9); p:step(scope,"a",0.9); a:complete(); p:step(scope,"a",0.9); p:step(scope,"a",0.9)
check(a.grants==8 and a.items["Items.Existing"],"existing inventory is neither removed nor counted as a grant")
check(p:unbind(scope,"a",a.id,1),"retire command before rebind")
check(p:bind(scope,"a",setmetatable({}, {__index=a}),1),"rebind new wrapper of original actor")
p:stage(scope,"a",10,state("Items.Ninth"),1)
check(p:step(scope,"a",1)=="failed" and p:inspect("a").reason=="inventory_capacity","ninth grant fails closed even after rebind")
check(#a.commands==9 and not a.items["Items.Ninth"] and a.items["Items.Existing"],"capacity rejection makes no equipment or inventory mutation")
p,map=fixture(); p:stage(scope,"a",1,state(),0)
check(not p:unbind(scope,"a",nil,0),"unbound nil-key release is rejected without an exception")
for _,id in ipairs({0,9007199254740992,"0ULL"}) do
    a=actor(id); map.a=a
    check(not p:bind(scope,"a",a,0),"zero/numeric native identity cannot bind")
end
local reentry
p=assert(Actions.new({resolve=function() end,supported=function()
    local ok,reason=p:stage(scope,"other",1,state(),0)
    reentry=not ok and reason=="callback_busy"; return true
end}))
p:reset(scope,0); p:stage(scope,"a",1,state("Items.Pistol"),0)
check(reentry and p:size()==1,"callback cannot recursively mutate the controller")
local Probe=assert(loadfile(root.."/experiments/player-presentation/aim_probe.lua"))()
local function aimActor(key)
    local a=actor(key); a.weapon,a.drawn,a.upper="Items.Pistol",true,0
    a.aimRequests,a.restoreRequests=0,0
    function a:CP2077Session_AcquireAimProbe(record)
        if self.lease or self.upper~=0 or not self.attached or self.weapon~=record then return nil end
        self.lease={}; self.probeLocked=true
        if self.throwAcquire then error("after acquiring native lease") end
        return self.lease
    end
    function a:CP2077Session_ReadAimProbe(lease)
        if self.lease~=lease or not self.attached then return -1 end
        if self.upper==1 and lease.requested then lease.seen=true end
        return self.upper
    end
    function a:CP2077Session_RequestAimProbe(lease,aim)
        local actual=self:CP2077Session_ReadAimProbe(lease)
        if aim then
            if actual~=0 or lease.requested then return false end
            lease.requested=true; self.aimRequests=self.aimRequests+1
            self.probeLocked=true
        else
            if actual~=1 or not lease.seen or lease.restore then return false end
            lease.restore=true; self.restoreRequests=self.restoreRequests+1
        end
        if self.throwAim then error("after possible mutation") end
        return true
    end
    function a:CP2077Session_ReleaseAimProbe(lease)
        if self:CP2077Session_ReadAimProbe(lease)~=0 or (lease.requested and not lease.restore) then return false end
        if self.refuseRelease then return false end
        self.lease=nil; self.probeLocked=false; return true
    end
    return a
end
local function prepareProbe(a,entity,controller,mapping)
    if not controller then controller,mapping=fixture() end
    mapping[entity]=a
    assert(controller:stage(scope,entity,1,state("Items.Pistol",false,true),0))
    assert(controller:bind(scope,entity,a,0))
    assert(controller:step(scope,entity,0)=="partial")
    local probe=assert(Probe.new({enabled=true,actions=controller,resolve=function(k) return mapping[k] end,hold=0.5}))
    return probe,controller,mapping
end
check(Probe.new({})==nil,"aim probe requires explicit opt-in")
local probe
p,map=fixture()
local trials={}
for i=1,3 do
    local entity="aim"..i
    local a=aimActor("700"..i.."ULL")
    probe=prepareProbe(a,entity,p,map)
    trials[i]={probe=probe,actor=a,entity=entity}
    check(probe:start(scope,entity,0),"three independent aim leases")
    check(probe:step(0)=="queued" and not probe:inspect().logicalAimObserved,"submission is not readback")
end
probe,a=trials[1].probe,trials[1].actor
check(not p:stage(scope,"aim1",2,state(),0),"probe reservation blocks state changes")
check(not p:unbind(scope,"aim1",a.id,0),"probe reservation blocks projection release")
check(not p:reset("replacement scope",0),"probe reservation blocks reset")
a.upper=1
check(probe:step(0.1)=="partial" and probe:inspect().logicalAimObserved,"logical Aim remains partial")
check(probe:inspect().visual=="unverified","logical readback never claims visible ADS")
map.aim1=setmetatable({}, {__index=a})
check(probe:step(0.6)=="queued" and a.restoreRequests==1,"same-ID wrapper churn permits bounded restore")
a.upper=0
check(probe:step(0.7)=="queued","Normal first readback does not release early")
check(probe:step(1)=="complete" and probe:inspect().cleanupConfirmed,"stable Normal releases exact lease")
check(a.lease==nil and trials[2].actor.lease~=nil,"other actors retain their leases")
check(p:inspect("aim1").reason=="awaiting_fresh_state","after probe old desired state is invalidated")
check(not probe:start(scope,"aim1",1),"one fixture instance cannot restart itself")

-- A second independent Actions controller cannot bypass the native actor lease.
a=aimActor("800ULL"); local first,firstActions=prepareProbe(a,"a")
check(first:start(scope,"a",0),"first fixture gets actor lease")
local second,secondActions=prepareProbe(a,"a")
check(not second:start(scope,"a",0) and a.aimRequests==1,"second controller cannot command the leased actor")
check(not second:inspect().retirementRequired and not second:inspect().reservationHeld,
    "known lease rejection cannot retire another controller's actor")
check(secondActions:inspect("a").reason=="awaiting_fresh_state","safe lease rejection clears only its own reservation")
secondActions:stage(scope,"a",2,state("Items.Rifle",true),0.1)
check(secondActions:step(scope,"a",0.1)=="failed" and a.stances==0 and #a.commands==0,
    "a second controller cannot submit stance or equipment while actor probe lease is held")
local _,thirdActions=prepareProbe(a,"a")
thirdActions:stage(scope,"a",2,state("Items.Rifle",false),0.1)
check(thirdActions:step(scope,"a",0.1)=="failed" and #a.commands==0,
    "actor probe lease also blocks equipment when no stance change was requested")

-- Stop before queued Aim drains must not force Normal or fabricate cancellation.
check(first:stop(),"early stop requested")
check(first:step(0.4)=="queued" and a.restoreRequests==0,"pending Aim cannot be cancelled through equal Normal setter")
a.upper=1
check(first:step(0.5)=="queued" and a.restoreRequests==1,"early stop restores only after Aim readback")
a.upper=0; first:step(0.6)
check(first:step(0.9)=="complete","early stop can finish after verified restoration")

-- Pause and timeout: no signal flood, no detached or replacement actor mutation.
probe,p,map=prepareProbe(aimActor("801ULL"),"a"); a=map.a
probe:start(scope,"a",0); probe:step(0.1,true); probe:step(50,true); probe:step(50.1,false)
check(probe:inspect().phase=="awaiting_aim" and a.aimRequests==1,"pause does not consume probe deadline")
check(probe:step(51.2)=="failed" and probe:inspect().retirementRequired,"unobserved queued Aim requires exact retirement")
check(a.restoreRequests==0 and not p:reset("new scope",51.2),"timeout retains ownership rather than falsely canceling")
for _,mode in ipairs({"different_actor","detached","external_state","weapon_change"}) do
    probe,p,map=prepareProbe(aimActor("802ULL"),"a"); a=map.a
    probe:start(scope,"a",0); a.upper=1; probe:step(0.1)
    if mode=="different_actor" then map.a=aimActor("803ULL")
    elseif mode=="detached" then a.attached=false
    elseif mode=="external_state" then a.upper=2
    else a.weapon="Items.Rifle" end
    check(probe:step(0.2)=="failed" and a.restoreRequests==0,"competing state/identity is never overwritten: "..mode)
    check(probe:inspect().retirementRequired,"uncertain cleanup retains retirement barrier")
end
probe,p,map=prepareProbe(aimActor("804ULL"),"a"); a=map.a
probe:start(scope,"a",0); a.upper=1; probe:step(0.1); probe:step(0.6)
check(probe:step(1.7)=="failed" and a.restoreRequests==1,"restore timeout is bounded without repeated Normal signals")
check(not p:unbind(scope,"a",a.id,1.7),"unconfirmed restoration retains projection ownership")
probe,p,map=prepareProbe(aimActor("805ULL"),"a"); a=map.a; a.throwAim=true
check(not probe:start(scope,"a",0) and probe:inspect().retirementRequired,"throw after possible signal retains native lease")
check(not p:stage(scope,"a",2,state(),0),"uncertain submission cannot be overwritten")
probe,p,map=prepareProbe(aimActor("806ULL"),"a"); a=map.a; a.upper=2
check(not probe:start(scope,"a",0) and a.aimRequests==0,"non-Normal baseline is rejected before mutation")
check(not probe:inspect().retirementRequired,"rejected non-Normal actor is not ours to retire")
probe,p,map=prepareProbe(aimActor("807ULL"),"a")
check(not probe:start("old epoch","a",0),"old scope cannot reserve current actor")
check(not probe:start(scope,"a",5),"stale desired state cannot start an aim probe")
probe,p,map=prepareProbe(aimActor("808ULL"),"a"); a=map.a
probe:start(scope,"a",0); a.upper=1; probe:step(0.1); probe:step(0.6)
a.upper=0; probe:step(0.7)
check(probe:step(3)=="failed" and probe:inspect().reason=="late_restore_readback",
    "gapped late restoration never reports an on-time cycle")
check(probe:inspect().cleanupConfirmed and not probe:inspect().retirementRequired,
    "late observed cleanup may release safely while recording the missed deadline")
probe,p,map=prepareProbe(aimActor("809ULL"),"a"); a=map.a; a.upper=2
function p:releaseAimProbe() return false end
check(not probe:start(scope,"a",0) and probe:inspect().reason=="reservation_release_unconfirmed",
    "known rejection still reports an unconfirmed action reservation release")
check(probe:inspect().reservationHeld and not probe:inspect().retirementRequired,
    "controller reservation failure does not authorize retiring an actor we never leased")
probe,p,map=prepareProbe(aimActor("810ULL"),"a"); a=map.a
probe:start(scope,"a",0); a.upper=1; probe:step(0.1); probe:step(0.6); a.upper=0; probe:step(0.7)
function p:releaseAimProbe() return false end
check(probe:step(1)=="failed" and probe:inspect().cleanupConfirmed and not probe:inspect().retirementRequired,
    "verified native cleanup followed by local reservation failure does not request actor retirement")
probe,p,map=prepareProbe(aimActor("811ULL"),"a"); a=map.a; a.throwAcquire=true
check(not probe:start(scope,"a",0) and probe:inspect().reason=="lease_uncertain",
    "throw after possible lease acquisition is explicitly uncertain")
check(probe:inspect().reservationHeld and probe:inspect().retirementRequired and a.lease~=nil,
    "uncertain native acquisition retains both ownership barriers")
check(a.aimRequests==0 and a.restoreRequests==0 and not p:reset("new scope",0),
    "uncertain acquisition does not submit Aim/Normal or reset ownership")
check(not p:unbind(scope,"a",a.id,0),"uncertain acquisition blocks exact actor unbind")
print("player action checks: "..checks)
