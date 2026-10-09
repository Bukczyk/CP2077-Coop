local root = assert(arg[1])
package.path = root .. "/runtime/session/cet/CP2077Coop/?.lua;" .. package.path
local Lifetime = require("player_lifetime")
local checks = 0
local function check(value, message) checks=checks+1; assert(value, message) end
local function fixture()
    local f={id={hash="9007199254740993ULL"}, visible=false, populated=false,
        attached=false, managed=true, spawning=true, spawned=false,
        deletes=0, releases=0, logs={}, ready=true, deleteResult=true, releaseResult=true}
    local function exact(id) check(id==f.id,"every lookup/deletion uses the original opaque ID") end
    f.actor={GetEntityID=function() return f.actorId or {hash=f.id.hash} end,
        IsAttached=function() return f.attached end}
    f.system={
        IsReady=function() return f.ready end,
        GetEntity=function(_,id) exact(id); return f.populated and f.actor or nil end,
        IsManaged=function(_,id) exact(id); return f.managed end,
        IsSpawning=function(_,id) exact(id); return f.spawning end,
        IsSpawned=function(_,id) exact(id); return f.spawned end,
        DeleteEntity=function(_,id)
            exact(id); f.deletes=f.deletes+1
            check(f.attached and f.managed and f.spawned and not f.spawning,"never delete a pending actor")
            if f.deleteError then error("delete failure") end
            if f.deleteResult then f.managed=false end
            return f.deleteResult
        end,
    }
    Game={GetDynamicEntitySystem=function() return not f.noManager and f.system or nil end,
        FindEntityByID=function(id)
            exact(id); if f.lookupError then error("lookup unavailable") end
            return f.visible and f.actor or nil
        end}
    f.owner=Lifetime.new(f.id,function(message) f.logs[#f.logs+1]=message end,function()
        f.releases=f.releases+1
        if f.releaseError then error("release failure") end
        return f.releaseResult
    end)
    function f:attach()
        self.visible,self.populated,self.attached,self.managed,self.spawned,self.spawning=true,true,true,true,true,false
    end
    function f:gone()
        self.visible,self.populated,self.attached,self.managed,self.spawned,self.spawning=false,false,false,false,false,false
    end
    function f:pump(now,paused) return self.owner:pump(now,paused) end
    return f
end

local f=fixture()
check(f.owner:actor()==nil,"pending actor is not fabricated")
check(not f:pump(-1) and f.deletes==0,"an owned active lifetime does not retire itself")
check(not f.owner:retire() and not f:pump(0),"departure retains pending ID")
f:pump(0.5); f:pump(4)
check(f.deletes==0 and f.owner.status=="spawn_retirement_unconfirmed","timeout never deletes pending spawn")
local logs=#f.logs
for i=1,20 do f:pump(4+i/10) end
check(#f.logs==logs and f.deletes==0,"timeout has bounded logs and no deletion flood")
f:attach()
check(f.owner:actor()==f.actor,"attached lookup verifies exact opaque ID")
check(not f:pump(7) and f.deletes==0,"first stable attachment does not delete")
f:pump(7)
check(f.deletes==0,"same update timestamp does not count as a second observation")
check(not f:pump(7.1) and f.deletes==1 and f.releases==1,"second stable observation requests deletion once")
for i=1,20 do check(not f:pump(7.1+i/10),"attached unmanaged actor still occupies its slot") end
check(f.deletes==1,"accepted deletion is not repeated while waiting")
f:gone()
check(not f:pump(10) and not f:pump(10.2),"empty observations need a quiet period")
check(f:pump(10.3) and f.owner.done and f.owner.status=="retired","complete observations retire exact actor")
check(f:pump(11) and f.owner:actor()==nil,"completed lifetime is idempotent")

-- Reproduce the dangerous observation sequence: no managed/populated entity,
-- followed by a late attached orphan. Never drop the token or delete blindly.
f=fixture(); f.owner:retire(); f:gone()
check(not f:pump(0) and not f:pump(1),"absence before ever attached is not retirement")
f.visible,f.populated,f.attached,f.spawned=true,true,true,true
check(not f:pump(2) and not f:pump(5),"late unmanaged actor remains tracked")
check(f.deletes==0 and not f.owner.done and f.owner.blocked,"unknown ownership never permits deletion or replacement")
local previousStatus=f.owner.status
f.owner:retire()
check(f.owner.blocked and f.owner.status==previousStatus,"repeated retirement retains its uncertainty")
f.managed=true
f:pump(6); f:pump(6.1)
check(f.deletes==1,"recovered managed late actor can retire safely")
f:gone(); f:pump(6.2); check(f:pump(6.5),"late attachment can finish after actual cleanup")

-- After delete, one clean sample is insufficient and a reappearing actor resets
-- the quiet interval even when Codeware no longer owns its ID.
f=fixture(); f:attach(); f.owner:retire(); f:pump(0); f:pump(0.1); f:gone(); f:pump(0.2)
f.visible,f.populated,f.attached,f.spawned=true,true,true,true
check(not f:pump(0.4),"late actor cancels provisional absence")
f:gone(); check(not f:pump(0.5) and not f:pump(0.7),"quiet window restarts after late actor")
check(f:pump(0.8),"only later stable absence confirms cleanup")

f=fixture(); f:attach(); f.spawning=true; f.owner:retire()
f:pump(0); f:pump(1)
check(f.deletes==0,"visible attached actor is not qualified while IsSpawning remains true")
f.spawning=false; f:pump(1.1); check(f.deletes==0,"first settled observation still waits")
f:pump(1.2); check(f.deletes==1,"second settled observation permits exact deletion")

f=fixture(); f:attach(); f.owner:retire(); f:pump(0); f:pump(0.1); f:gone(); f:pump(0.2)
f.lookupError=true; check(not f:pump(1),"readback failure never confirms removal")
f.lookupError=false; check(not f:pump(2),"recovered readback restarts the quiet interval")
check(f:pump(2.3),"fresh quiet observations can resolve a prior error")

for _,failure in ipairs({"lookupError","noManager","notReady"}) do
    f=fixture(); f:attach(); f.owner:retire(); f:pump(0)
    if failure=="notReady" then f.ready=false else f[failure]=true end
    check(not f:pump(0.1) and f.deletes==0,"engine uncertainty does not mutate: "..failure)
    if failure=="notReady" then f.ready=true else f[failure]=false end
    f:pump(0.2); check(f.deletes==0,"uncertainty resets attachment qualification")
    f:pump(0.3); check(f.deletes==1,"observation can recover without losing ownership")
end

f=fixture(); f:attach(); f.owner:retire(); f.releaseResult=false
f:pump(0); f:pump(0.1)
check(f.releases==1 and f.deletes==0,"failed release initially blocks deletion")
f.releaseResult=true; f:pump(0.2)
check(f.releases==1 and f.deletes==0,"release retry respects its interval")
f:pump(0.7)
check(f.releases==2 and f.deletes==1,"a confirmed release within retry budget permits cleanup")

f=fixture(); f:attach(); f.actorId={hash="9007199254740994ULL"}; f.owner:retire()
check(f.owner:actor()==nil and not f:pump(0) and not f:pump(1),"adjacent 64-bit ID cannot substitute for owned actor")
check(f.deletes==0 and f.owner.blocked,"identity mismatch stays fail closed")
for _,id in ipairs({{hash=9007199254740992},{hash="0ULL"},{hash="18446744073709551616ULL"},123}) do
    check(not pcall(Lifetime.new,id),"reject invalid or rounded ownership IDs")
end

for _,failure in ipairs({"releaseFalse","releaseError","deleteFalse","deleteError"}) do
    f=fixture(); f:attach(); f.owner:retire()
    if failure=="releaseFalse" then f.releaseResult=false
    elseif failure=="releaseError" then f.releaseError=true
    elseif failure=="deleteFalse" then f.deleteResult=false
    else f.deleteError=true end
    for i=0,100 do f:pump(i/10) end
    check(not f.owner.done and f.owner.blocked,"failed operation keeps ownership: "..failure)
    if failure:find("release",1,true) then
        check(f.releases==3 and f.deletes==0,"failed release is bounded and precedes any deletion")
    else check(f.releases==1 and f.deletes==3,"rejected/throwing deletion has a bounded retry budget") end
    check(#f.logs<=5,"operation failure does not log every frame")
end

f=fixture(); f:attach(); f.owner:retire(); f:pump(0)
for i=1,10 do check(not f:pump(i,true),"paused retirement stays pending") end
check(f.deletes==0 and f.releases==0,"paused engine gets no release/deletion calls")
f:pump(11,false); check(f.deletes==0,"resume requires a fresh pair of stable observations")
f:pump(11.1,false); check(f.deletes==1,"resume permits qualified cleanup")
f:gone(); f:pump(11.2); f:pump(20,true)
check(not f:pump(21,false),"paused wall time cannot satisfy the quiet interval")
check(f:pump(21.3,false),"unpaused observations finish the interval")

f=fixture(); f:attach(); f.owner:retire(); f:pump(1)
check(not f:pump(0/0) and not f:pump(0) and f.deletes==0,"invalid/backward time cannot authorize mutation")
f:pump(2); check(f.deletes==0,"bad clock resets stable attachment")
f:pump(2.1); check(f.deletes==1,"valid clock recovers the retained lifetime")

f=fixture(); f:attach(); f.owner:retire(); f:pump(0)
check(not f:pump(0.1,"unknown") and f.deletes==0,"non-boolean pause observation cannot authorize deletion")
f:pump(0.2,false); check(f.deletes==0,"invalid pause resets stable attachment")
f:pump(0.3,false); check(f.deletes==1,"valid pause observations can recover safely")

-- IsSpawned or a population handle is independent evidence, even if global
-- lookup and tag/managed state no longer expose an actor.
for _,remaining in ipairs({"spawned","populated","spawning","managed"}) do
    f=fixture(); f:attach(); f.owner:retire(); f:pump(0); f:pump(0.1); f:gone(); f[remaining]=true
    check(not f:pump(1) and not f:pump(2),"remaining evidence blocks cleanup: "..remaining)
    f[remaining]=false; f:pump(3); check(f:pump(3.3),"last evidence must disappear: "..remaining)
end

print("player_lifetime: PASS ("..checks.." checks; exact IDs, pending cancellation, observed retirement, bounded retries)")
