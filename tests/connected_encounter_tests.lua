local root=assert(arg[1],"repository path required")
local loader=assert(loadfile(root.."/tests/cet_require.lua"))()
local cetRequire=loader(root.."/experiments/shared-encounter")
local Codec=assert(cetRequire("connected/codec"))
local Bridge=assert(cetRequire("connected/bridge"))
local Host=assert(cetRequire("connected/host"))
local Engine=assert(cetRequire("connected/engine"))
local checks=0
local function eq(actual,expected,why)
    checks=checks+1; assert(actual==expected,(why or "unexpected value")..": "..tostring(actual).." ~= "..tostring(expected))
end
local dotted,dottedError=cetRequire("connected.codec")
eq(dotted,nil,"CET does not translate dots into path separators")
eq(type(dottedError),"string","missing CET module returns an error value")
eq(cetRequire("connected/codec.lua"),Codec,"extension and bare path share CET cache")
eq(cetRequire("connected\\codec"),Codec,"Windows path separator resolves the same module")
local oldImport=loader(root.."/experiments/shared-encounter",function(name,source)
    return name=="connected/engine" and source:gsub('"connected/codec"','"connected.codec"') or source
end)
local broken,brokenError=oldImport("connected/engine")
eq(broken,nil,"regression: original dotted nested import fails under CET")
eq(type(brokenError),"string")
local intent={target="9007199254740993",shot=1,origin={x=1,y=2,z=3},direction={x=1,y=0,z=0}}
local encoded=assert(Codec.intent(intent))
eq(Codec.readIntent(encoded).target,intent.target)
eq(Codec.id("18446744073709551615"),true)
eq(Codec.id("18446744073709551616"),false)
eq(Codec.id("09007199254740993"),false)
eq(Codec.readIntent(Codec.hex("CPEX1I|1|1|nan|0|0|1|0|0")),nil)
eq(Codec.readIntent(Codec.hex("CPEX1I|1|1|0|0|0|0|0|0")),nil)
eq(Codec.readIntent(encoded.."00"),nil)
eq(Codec.readIntent(encoded:sub(2)),nil)
eq(Codec.readResult(Codec.result({target=intent.target,health=0,maximum=100,life="dead"})).life,"dead")
eq(Codec.result({target="1",health=50,maximum=100,life="dead"}),nil)
eq(Bridge.opaque("9007199254740993ULL"),"9007199254740993")
eq(Bridge.opaque(1),nil)
eq(Bridge.scope("1|1|1|1|1|4").active,true)
eq(Bridge.event("intent|1|1|1|2|18446744073709551615|32513|"..encoded).event,"18446744073709551615")
eq(Bridge.event("intent|1|1|1|2|0|32513|"..encoded),nil)
eq(Bridge.event("outcome|1|1|1|1|42|2|21|32513|3|8|").reason,8)
eq(Bridge.event("outcome|1|1|1|1|42|2|21|32513|1|0|"),nil,"Pending is a status, never terminal outcome")
eq(Bridge.event("sent_intent|1|1|1|12|13").ticket,"12")
eq(Bridge.event("sent_result|1|1|1|14|15").event,"15")
eq(Bridge.event("status|1|1|1|42|2|0|1").committed,true)
eq(Bridge.queued("queued|18446744073709551615"),"18446744073709551615")
eq(Bridge.queued("queued|2|extra"),nil)

local function harness(options)
    options=options or {}
    local h={calls=0,replies={},queued=true,
        scope={active=true,session="1",epoch=1,generation="1",self=1,host=1},
        target={sessionEntity=intent.target,localKey="700",attached=true,managed=true,tagged=true,owner=1},
        sender={player=2,sessionEntity="2",localKey="800",attached=true},
        sample={valid=true,health=100,maximum=100,dead=false,defeated=false,pending=false,correlated=false}}
    local config={enabled=options.enabled~=false,capacity=options.capacity or 16,timeout=1,settle=0.1,
        context=function() return h.scope end,
        resolveSender=function() return h.sender end,
        resolveTarget=function() return h.target end,
        validateRay=function() if h.rayCallback then h.rayCallback() end; return h.ray~=false end,
        observe=function() return h.sample end,
        apply=function(_,serial)
            h.calls=h.calls+1; h.serial=serial
            eq(h.host:inspect().pending,1,"reservation must precede engine application")
            if h.applyCallback then return h.applyCallback() end
            return "queued_host_weapon_pipeline_fixture_not_observed"
        end,
        reply=function(envelope,disposition,reason,body)
            h.replies[#h.replies+1]={event=envelope.event,disposition=disposition,reason=reason,body=body}
            return h.queued
        end}
    h.host=assert(Host.new(config))
    function h:packet(event)
        return {session="1",epoch=1,generation="1",sender=2,event=event or "1",kind=Codec.kind,body=encoded}
    end
    function h:finish(health,dead)
        self.sample={valid=true,health=health,maximum=100,dead=dead or false,defeated=false,pending=false,correlated=true}
        self.host:step(0.1); self.host:step(0.21)
    end
    return h
end
do
    local h=harness({enabled=false})
    eq(h.host:accept(h:packet(),0),false); eq(h.calls,0)
end
do
    local h=harness(); eq(h.host:accept(h:packet(),0),true)
    eq(h.host:accept(h:packet(),0.01),false); eq(h.calls,1)
    h.host:step(0.02); eq(#h.replies,0,"queue ack is not damage")
    h:finish(75); eq(#h.replies,1); eq(h.replies[1].disposition,2)
    local result=Codec.readResult(h.replies[1].body)
    eq(result.health,75); eq(result.life,"alive"); eq(result.damage,nil)
    eq(h.host:accept(h:packet(),0.3),false); eq(h.calls,1)
end
do
    local h=harness(); h.host:accept(h:packet(),0)
    h.sample={valid=true,health=0.01,maximum=100,dead=false,defeated=false,correlated=true}
    h.host:step(0.1); eq(#h.replies,0)
    h.sample.health,h.sample.dead=0,true
    h.host:step(0.15); h.host:step(0.26)
    eq(Codec.readResult(h.replies[1].body).life,"dead","settle before sending one terminal snapshot")
end
do
    local h=harness(); h.host:accept(h:packet(),0)
    h.host:accept(h:packet("2"),0.01)
    eq(h.replies[1].reason,Host.reasons.busy)
    h.host:accept(h:packet("3"),0.02)
    eq(h.replies[2].reason,Host.reasons.busy,"busy rejection must not release first reservation")
    eq(h.calls,1); h:finish(75); eq(h.replies[3].disposition,2)
end
do
    local h=harness(); h.queued=false; h.host:accept(h:packet(),0); h:finish(75)
    eq(h.host:inspect().unsent,1); h.queued=true; h.host:step(0.3)
    eq(h.calls,1); eq(h.host:inspect().unsent,0); eq(#h.replies,2)
    eq(h.replies[1].body,h.replies[2].body,"outbox retry must be identical")
end
for _,failure in ipairs({"ambiguous","invalid","timeout","mapping","exception","unknown_return"}) do
    local h=harness()
    if failure=="exception" then h.applyCallback=function() error("possibly applied") end end
    if failure=="unknown_return" then h.applyCallback=function() return "unexpected" end end
    h.host:accept(h:packet(),0)
    if failure=="ambiguous" then h.sample.ambiguous=true
    elseif failure=="invalid" then h.sample.valid=false
    elseif failure=="mapping" then h.target.localKey="701" end
    h.host:step(1.1)
    eq(h.host:inspect().unresolved,1,failure)
    eq(h.replies[1].reason,Host.reasons.unresolved)
    h.host:accept(h:packet("2"),1.2); eq(h.calls,1,"uncertain target must stay blocked")
end
for _,failure in ipairs({"malformed","unsupported","tag","owner","sender","occlusion","stale_during_ray"}) do
    local h=harness(); local p=h:packet()
    if failure=="malformed" then p.body=encoded.."00"
    elseif failure=="unsupported" then p.kind=1
    elseif failure=="tag" then h.target.tagged=false
    elseif failure=="owner" then h.target.owner=2
    elseif failure=="sender" then h.sender.player=3
    elseif failure=="occlusion" then h.ray=false
    else h.rayCallback=function() h.sender.localKey="801" end end
    -- Return a fresh sender value in production. Mutating an object in place is
    -- also tested below through the controller's saved scalar identity.
    h.host:accept(p,0); eq(h.calls,0,failure)
end
do
    local h=harness({capacity=1}); h.host:accept(h:packet(),0)
    local ok,reason=h.host:accept(h:packet("2"),0.1)
    eq(ok,false); eq(reason,"full"); eq(h.calls,1)
    eq(h.replies[1].disposition,5,"overload must reply Full on the reserved request")
    h.queued=false; h.host:accept(h:packet("3"),0.15)
    eq(h.host:inspect().fault,"full_denial_not_queued")
    h.scope.generation="2"
    eq(h.host:step(0.2),false); eq(h.host:reset(0.3),true)
    eq(h.host:accept(h:packet("3"),0.4),false,"old generation rejected")
end
for field,value in pairs({session="2",epoch=2,generation="2",sender=1,event="0",kind=0}) do
    local h=harness(); local p=h:packet(); p[field]=value
    eq(h.host:accept(p,0),false,"invalid envelope "..field); eq(h.calls,0)
end
for field,value in pairs({session="2",epoch=2,generation="2",self=2,host=2}) do
    local h=harness(); h.rayCallback=function() h.scope[field]=value end
    eq(h.host:accept(h:packet(),0),false,"scope changed during validation "..field); eq(h.calls,0)
end
for field,value in pairs({player=3,localKey="801",sessionEntity="3",attached=false}) do
    local h=harness(); h.rayCallback=function() h.sender[field]=value end
    eq(h.host:accept(h:packet(),0),false,"sender changed during validation "..field); eq(h.calls,0)
end
do
    local h=harness(); h.host:accept(h:packet("9007199254740993"),0); h:finish(75)
    h.host:accept(h:packet("9007199254740992"),0.3)
    eq(h.calls,1); eq(h.replies[2].reason,Host.reasons.stale,"stale opaque event order")
end

local scope={session="1",epoch=1,generation="1",self=1,host=1}
local readback="healthPoints=100 healthMaxPoints=100 persistentDead=false defeated=false pending=false"
local function line(seq,kind,extra)
    local hit=""
    if kind=="candidate_before_preprocess" or kind=="after_preprocess" or kind=="after_deal_await_readback" then
        hit=" computedNotObserved=25 instigatorDefined=true weaponDefined=true instigatorLocal=1 weaponLocal=400"
            .." attackType=10 hitX=1 hitY=2 hitZ=3 directionX=1 directionY=0 directionZ=0 originX=0 originY=2 originZ=3 hitShapes=1"
    end
    return "encounter seq="..seq.." kind="..kind.." sim=2 local=700 session=1 epoch=1 entity="..intent.target
        .." self=1 host=1 healthPoints=100 healthMin=false persistentDead=false defeated=false fixtureRequest=1 "..(extra or "")..hit
end
local function engineHarness()
    local object={CP2077Encounter_HostWeaponHit=function() return "queued_host_weapon_pipeline_fixture_not_observed" end}
    local target={localKey="700",sessionEntity=intent.target,object=object}
    local engine=assert(Engine.new(function() return scope end))
    engine:ingest(target,readback,{line(1,"readback")})
    eq(engine:observe(target,nil).valid,true)
    eq(engine:observe(target,nil).valid,true,"admission reuses idle baseline without resetting its sequence watermark")
    eq(engine:apply(target,1),"queued_host_weapon_pipeline_fixture_not_observed")
    return engine,target
end
do
    local engine,target=engineHarness()
    engine:ingest(target,readback,{
        line(2,"candidate_before_preprocess","syntheticFixture=true projectionPipeline=false"),
        line(3,"after_deal_await_readback","syntheticFixture=true projectionPipeline=false")})
    eq(engine:observe(target,1).correlated,true)
    eq(engine:observe(target,1).correlated,true,"consumed logs are not parsed twice")
    engine:ingest(target,readback,{line(4,"readback","healthPoints=100 persistentDead=false defeated=false")})
    eq(engine:observe(target,1).valid,true,"verified Log(readback) repeats equal health/life fields")
end
do
    local engine,target=engineHarness()
    engine:ingest(target,readback,{line(2,"candidate_before_preprocess","syntheticFixture=false projectionPipeline=false")})
    eq(engine:observe(target,1).ambiguous,true)
end
do
    local engine,target=engineHarness()
    engine:ingest(target,readback,{
        line(2,"candidate_before_preprocess","syntheticFixture=true projectionPipeline=false"),
        line(4,"after_deal_await_readback","syntheticFixture=true projectionPipeline=false")})
    eq(engine:observe(target,1).valid,false,"a missing engine observation makes attribution unresolved")
end
for _,bad in ipairs({"encounter log_overflow dropped=1","truncated",line(2,"unknown"),
    line(1,"readback"),line(2,"readback").." local=700",
    (line(2,"candidate_before_preprocess","syntheticFixture=true projectionPipeline=false"):gsub(" hitShapes=1$",""))}) do
    local engine,target=engineHarness(); engine:ingest(target,readback,{bad})
    eq(engine:observe(target,1).valid,false,"strict bounded observer parser")
end
-- Exact engine_hooks.reds Log(Readback) shape, including the fourth repeated
-- header field healthMin. The old stock fixtures omitted that real duplicate.
local aliveReadback="healthPoints=100 healthMaxPoints=100 persistentDead=false healthMin=false defeated=false immortal=false invulnerable=false pending=false highLevelState=5"
local deadReadback="healthPoints=0.000000 healthMaxPoints=100 persistentDead=true healthMin=true defeated=false immortal=false invulnerable=false pending=false highLevelState=5"
local function deadLine(seq,kind,detail,persistent)
    local value=line(seq,kind,detail)
    value=value:gsub("healthPoints=100","healthPoints=0.000000"):gsub("healthMin=false","healthMin=true")
    if persistent then value=value:gsub("persistentDead=false","persistentDead=true") end
    return value
end
do
    local engine,target=engineHarness()
    engine:ingest(target,aliveReadback,{line(2,"readback",aliveReadback)})
    eq(engine:observe(target,1).valid,true,"real readback repeats healthMin as well as health/life fields")
end
do
    local engine,target=engineHarness()
    engine:ingest(target,deadReadback,{
        -- TDBID.ToStringDEBUG in the prior live fixture emitted this unquoted
        -- record path, not a bracketed object or a value containing whitespace.
        line(2,"host_weapon_fixture_queued","attack=Attacks.Bullet_GameEffect physicalShot=false hitGeometry=synthetic source=host_local_player"),
        line(3,"candidate_before_preprocess","syntheticFixture=true projectionPipeline=false"),
        line(4,"after_preprocess","syntheticFixture=true projectionPipeline=false"),
        line(5,"after_deal_await_readback","syntheticFixture=true projectionPipeline=false"),
        deadLine(6,"death_callback","await_persistent_flag",false),
        deadLine(7,"on_died_after_vanilla","",true),
        deadLine(8,"fixture_observed_change","attribution=not_proven",true),
        deadLine(9,"readback",deadReadback,true)})
    local observed=engine:observe(target,1)
    eq(observed.valid,true,"real death callback has one exact bare terminal marker")
    eq(observed.correlated,true,"complete synthetic pipeline remains correlated")
    eq(observed.dead,true,"death requires persistent flag from later readback")
    eq(observed.health,0)
end
for _,bad in ipairs({
    line(2,"readback",aliveReadback).." healthMin=false",
    line(2,"readback",aliveReadback:gsub("healthMin=false","healthMin=true")),
    line(2,"readback","await_persistent_flag"),
    line(2,"death_callback",""),
    line(2,"death_callback","await_persistent_flag trailing=true"),
    line(2,"death_callback","await_persistent_flag await_persistent_flag"),
    line(2,"death_callback","some_other_marker")}) do
    local engine,target=engineHarness(); engine:ingest(target,aliveReadback,{bad})
    eq(engine:observe(target,1).valid,false,"only exact emitted duplicate/marker exceptions are accepted")
end
print("connected encounter diagnostic checks passed: "..checks)
