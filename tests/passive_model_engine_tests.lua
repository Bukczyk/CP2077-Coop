local root=assert(arg[1])
local folder=root.."/experiments/passive-models/"
package.path=folder.."?.lua;"..package.path
-- Test-only loader for the exact production subfolder names. The standalone
-- CET loader review separately stages these files with no package fallback.
for _,name in ipairs({"presentation","presentation_state"}) do
    package.preload["cp2077_passive_encounter/"..name]=assert(loadfile(root.."/experiments/shared-encounter/"..name..".lua"))
end
local checks=0
local function check(value,why) checks=checks+1;assert(value,why) end
local function id(value) return {hash=value} end
local function make()
    local f={native=0,creates=0,moves=0,deletes=0,tokens={},actors={},globals={},tags={},logs={},paused=false,
        ready=true,resources={},nextId=0,playerId="9007199254740997ULL",playerNative={},requests=true,events={}}
    local refs,serial={},0
    local function ref(path)
        if not refs[path] then serial=serial+1;refs[path]="18014398509482"..string.format("%03d",serial).."ULL" end
        return {path=path,hash=refs[path]}
    end
    local function native()
        if f.requireUpdate then assert(f.inUpdate,"engine access outside onUpdate") end
        f.native=f.native+1
    end
    local function actor(value,spec)
        local a={attached=true,id=value,template=spec.templatePath,root=true,nativeRef={},
            position={x=spec.position.x,y=spec.position.y,z=spec.position.z},orientation=spec.orientation,
            appearance=spec.appearanceName,appearanceHash="9007199254740995",color="None",colorHash="0"}
        function a:GetEntityID() native();return id(self.id) end
        function a:IsAttached() native();return self.attached end
        function a:GetTemplatePath() native();return self.template end
        function a:IsExactlyA(name) native();assert(name=="entEntity");return self.root end
        function a:CP2077PassiveModelFixture_OwnedIdentity(context,original,expected)
            native()
            if f.identityThrows then error("identity_read_failed") end
            if f.identityUnknown then return 0 end
            if not original or not expected then return 0 end
            if self.nativeRef~=original.nativeRef or self.id~=expected.hash or original.id~=expected.hash then return -1 end
            if not context or not self.attached or not f.globals[self.id] then return 0 end
            if f.globals[self.id].nativeRef~=original.nativeRef then return -1 end
            return 1
        end
        function a:CP2077PassiveModelFixture_CurrentVisualState(context,originalContext,originalActor,expected)
            native()
            assert(expected.hash==self.id,"opaque exact ID passed unchanged")
            if self.appearanceError then error("appearance_read_failed") end
            if self.colorError then error("color_read_failed") end
            local function same(left,right) return left and right and left.nativeRef==right.nativeRef end
            if not same(context,originalContext) or not same(self,originalActor)
                or not self.attached or not same(f.globals[self.id],self) then return {valid=false} end
            local raw={valid=true,entityDecimal=self.id:gsub("ULL$",""),
                contextDecimal=f.playerId:gsub("ULL$",""),appearance=self.appearance,
                appearanceHash=self.appearanceHash,color=self.color,colorHash=self.colorHash}
            if f.visualHook then f.visualHook(self,raw) end
            -- Mock of the compiled native contract, not execution of REDscript.
            if not self.attached or not same(f.globals[self.id],self) or not same(self,originalActor)
                or not same(context,originalContext) or context.nativeRef~=f.playerNative
                or self.appearance~=raw.appearance
                or self.color~=raw.color or self.appearanceHash~=raw.appearanceHash
                or self.colorHash~=raw.colorHash then return {valid=false} end
            if f.visualTransform then return f.visualTransform(raw) end
            return raw
        end
        function a:GetWorldPosition() native();if self.readError then error("pose_read_failed") end;return self.position end
        function a:GetWorldOrientation() native();return self.orientation end
        function a:SetWorldTransform(world)
            native();f.moves=f.moves+1;self.submitted=world
            if f.applyMove then self.position=world.position;self.orientation=world.orientation end
            if f.moveThrows then error("native_move_outcome_unknown") end
        end
        function a:QueueEvent(event)
            native();f.events[#f.events+1]={actor=self.nativeRef,id=self.id,key=event.key,value=event.value}
            if f.queueHook then f.queueHook(self,event,#f.events) end
            if f.queueThrows then error("native_queue_outcome_unknown") end
        end
        return a
    end
    local s={}
    function s:IsReady() native();return f.ready end
    function s:GetTaggedIDs() native();if f.tagsError then error("tags_failed") end;return f.tags end
    function s:SpawnEntity(spec)
        native();f.creates=f.creates+1;f.nextId=f.nextId+1
        local value="900719925474099"..(f.nextId+2).."ULL"
        f.tokens[value]={spec=spec};f.tags[#f.tags+1]=id(value)
        if f.spawnThrows then error("native_spawn_outcome_unknown") end
        if f.invalidId then return id(f.invalidId) end
        return id(value)
    end
    function s:IsManaged(value)
        native();if f.unknownFlags then return nil end
        return f.tokens[value.hash]~=nil or f.actors[value.hash]~=nil
    end
    function s:IsSpawning(value) native();return f.tokens[value.hash]~=nil end
    function s:IsSpawned(value) native();return f.actors[value.hash]~=nil end
    function s:GetEntity(value)
        native();if f.creatorError then error("creator_read_failed") end
        if f.lookupHook then return f.lookupHook(value,f.actors) end
        return f.actors[value.hash]
    end
    function s:DespawnEntity(value)
        native();f.deletes=f.deletes+1
        assert(f.actors[value.hash] and not f.tokens[value.hash],"pending token was cancelled")
        f.actors[value.hash].disposed=true
        if f.despawnThrows then error("despawn_outcome_unknown") end
        return true
    end
    f.system=s
    f.complete=function(value)
        local token=assert(f.tokens[value]);local a=actor(value,token.spec)
        f.actors[value],f.globals[value]=a,a;f.tokens[value]=nil;return a
    end
    f.finish=function(value)
        local a=f.actors[value] or f.globals[value];if a then a.attached=false end
        f.actors[value],f.globals[value],f.tokens[value]=nil,nil,nil
        local out={};for _,tagged in ipairs(f.tags) do if tagged.hash~=value then out[#out+1]=tagged end end;f.tags=out
    end
    Game={
        GetStaticEntitySystem=function() native();return f.replacementSystem or s end,
        FindEntityByID=function(value) native();return f.globals[value.hash] end,
        GetSystemRequestsHandler=function()
            native();if not f.requests then return nil end
            return {IsGamePaused=function() native();return f.paused end,IsPreGame=function() native();return f.preGame==true end}
        end,
        GetPlayer=function()
            native();return {nativeRef=f.playerNative,id=f.playerId,
                IsAttached=function() native();return true end,
                GetEntityID=function(self) native();return id(self.id) end,
                GetWorldPosition=function() native();return {x=0,y=0,z=0} end}
        end,
        GetResourceDepot=function()
            native();return {ResourceExists=function(_,r)
                native();if f.resourceUnknown==r.path then return nil end
                if f.resources[r.path]~=nil then return f.resources[r.path] end
                return true
            end}
        end,
    }
    StaticEntitySpec={new=function() native();return {} end}
    ResRef={FromName=function(path) native();return ref(path) end,
        GetHash=function(r) native();return r.hash end,ToString=function(r) native();return r.path end}
    CName={new=function(value) native();return value end}
    NewObject=function(name) native();assert(name=="entAnimInputSetterFloat");if f.constructorThrows then error("event_constructor_failed") end;return {} end
    Vector4={new=function(x,y,z,w) native();return {x=x,y=y,z=z,w=w} end}
    Quaternion={new=function(i,j,k,r) native();return {i=i,j=j,k=k,r=r} end}
    EulerAngles={new=function(roll,pitch,yaw) native();return {roll=roll,pitch=pitch,yaw=yaw} end}
    WorldTransform={new=function() native();return {} end,
        SetPosition=function(w,p) native();w.position=p end,
        SetOrientationEuler=function(w,e) native();local r=math.rad(e.yaw)/2;w.orientation={i=0,j=0,k=math.sin(r),r=math.cos(r)} end}
    f.ref=ref
    package.loaded.engine=nil
    f.engine=require("engine").new()
    f.entry=function(name,slot,x)
        return {profile=name or "judy_default",slot=slot or "first",generation="fixture:1",target={x=x or 2,y=0,z=0,yaw=0}}
    end
    return f
end
-- Shared native shim for the separate real-entrypoint suite. No checks run in
-- helper mode; each caller creates a fresh engine/world.
if arg[2]=="helper" then return make end

do
    local f=make();local a,b=f.entry(),f.entry("mitch_default","second",4)
    check(f.engine:create(a) and f.engine:create(b),"simultaneous profiles")
    check(f.creates==2 and a.idKey~=b.idKey,"exact distinct IDs")
    check(f.tokens[a.id.hash].spec.appearanceName=="default","requested appearance only")
    check(not f.engine:retire(a) and f.deletes==0,"never cancel pending spawn")
    local aa,bb=f.complete(a.id.hash),f.complete(b.id.hash)
    local oa,ob=f.engine:observe(a),f.engine:observe(b)
    check(oa.ready and oa.templateVerified and oa.rootVerified and ob.templateVerified,"both profiles observed")
    check(oa.template~=ob.template and not oa.visualQualified,"observed exact template is not visual proof")
    a.retiring=true
    check(not f.engine:retire(a) and f.deletes==1 and not bb.disposed,"isolated cleanup")
    f.finish(a.id.hash);check(f.engine:retire(a),"completed cleanup")
    check(f.engine:observe(b).ready,"other profile survives")
end

for _,name in ipairs({"judy_default","mitch_default"}) do
    for _,field in ipairs({"template","graph","mesh","rig","animset"}) do
        for _,unknown in ipairs({false,true}) do
            local f=make();local e=f.entry(name);local p=f.engine:profile(name)
            if unknown then f.resourceUnknown=p[field] else f.resources[p[field]]=false end
            local ok,why=pcall(f.engine.create,f.engine,e)
            check(not ok and f.creates==0 and not e.spawnAttempted,"resource gate before spawn")
            check(tostring(why):find(unknown and "resource_observation_unknown" or "missing_resource",1,true),"unknown is not missing")
        end
    end
end
for _,invalid in ipairs({{}, {value=nil}, {value="false"}, {value=0}}) do
    local f=make();f.tags=invalid.value
    local e=f.entry();check(not pcall(f.engine.create,f.engine,e) and f.creates==0,"unknown tags")
end
do
    local f=make();f.tags={id("9007199254740998ULL")}
    check(not pcall(f.engine.create,f.engine,f.entry()) and f.creates==0,"historical tag blocks spawn")
    f.tags={};f.tagsError=true
    check(not pcall(f.engine.create,f.engine,f.entry()) and f.creates==0,"tag error blocks spawn")
end
do
    local f=make();local e=f.entry();f.engine:create(e)
    local token=f.tokens[e.id.hash];f.tokens[e.id.hash]=nil
    check(not f.engine:retire(e) and f.deletes==0,"empty maps cannot settle pending callback")
    f.tokens[e.id.hash]=token;local a=f.complete(e.id.hash)
    f.unknownFlags=true;check(not pcall(f.engine.retire,f.engine,e) and f.deletes==0,"unknown flags")
    f.unknownFlags=false;check(not f.engine:retire(e) and f.deletes==1,"late callback retired")
    f.actors[e.id.hash]=nil
    check(not f.engine:retire(e),"global actor survives")
    f.globals[e.id.hash]=nil
    check(not f.engine:retire(e),"retained attached actor survives")
    a.attached=false;check(f.engine:retire(e),"exact detached actor releases")
end
for _,fault in ipairs({"template","root","pose"}) do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    if fault=="template" then a.template=f.ref("foreign.ent") elseif fault=="root" then a.root=false else a.readError=true end
    local o=f.engine:observe(e)
    check(o.ready and o.visualFault,"lifetime independent of visual fault")
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0}) and f.moves==0,"bad visual cannot move")
    check(not f.engine:retire(e) and f.deletes==1,"bad owned visual can retire")
end
for _,field in ipairs({"x","y","z"}) do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    a.position[field]=nil
    local o=f.engine:observe(e)
    check(o.ready and not o.pose and o.visualFault=="visual_readback_unavailable","missing pose field: "..field)
end
do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    local count=0
    f.lookupHook=function(value)
        count=count+1
        if count==1 then return a end
        return {GetEntityID=function() return id("9007199254740999ULL") end}
    end
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0}) and f.moves==0,
        "replaced final getter actor cannot receive transform")
end
do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    a.id="9007199254740999ULL"
    check(not pcall(f.engine.observe,f.engine,e),"wrong exact ID")
    check(not pcall(f.engine.retire,f.engine,e) and f.deletes==0,"wrong ID cannot delete")
end
do
    local f=make();local e=f.entry();f.engine:create(e);f.complete(e.id.hash)
    f.replacementSystem={IsReady=function() error("wrong creator") end}
    check(f.engine:observe(e).ready,"pinned creator survives fresh Game system")
    f.engine:move(e,{x=3,y=0,z=0,yaw=0.5})
    local o=f.engine:observe(e)
    check(f.moves==1 and o.pose.x==2,"accepted move is not observed pose")
    f.playerId="9007199254740998ULL"
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0}) and f.moves==1,"player change")
end
-- Appearance is an actual readback, separate from lifecycle and visual quality.
for _,fault in ipairs({"missing","throwing","nil","None","empty","number","boolean","table","wrong"}) do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    local getter=a.CP2077PassiveModelFixture_CurrentVisualState
    if fault=="missing" then a.CP2077PassiveModelFixture_CurrentVisualState=nil
    elseif fault=="throwing" then a.appearanceError=true
    elseif fault=="nil" then a.appearance=nil
    elseif fault=="None" then a.appearance="None"
    elseif fault=="empty" then a.appearance=""
    elseif fault=="number" then a.appearance=1
    elseif fault=="boolean" then a.appearance=true
    elseif fault=="table" then a.appearance={name="default"}
    else a.appearance="other" end
    local o=f.engine:observe(e)
    check(o.ready and o.templateVerified and o.rootVerified and not o.appearanceVerified and o.visualFault,
        "appearance fault does not hide ready owned lifetime: "..fault)
    check(not o.visualQualified,"appearance never proves visible quality")
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0}) and f.moves==0 and not e.moveAttempted,
        "bad appearance cannot submit movement: "..fault)
    a.CP2077PassiveModelFixture_CurrentVisualState=getter;a.appearanceError=false;a.appearance="default"
    o=f.engine:observe(e)
    check(o.observedAppearance=="default" and o.appearanceVerified and not o.visualFault,"appearance recovery")
    check(f.engine:move(e,{x=3,y=0,z=0,yaw=0}) and f.moves==1,"recovered exact appearance can submit")
    a.appearance="other"
    check(not f.engine:retire(e) and f.deletes==1,"mismatched appearance never blocks exact retirement")
    f.finish(e.id.hash);check(f.engine:retire(e),"appearance mismatch cleanup completes")
end

do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    local lookups=0
    local changed=setmetatable({appearance="other"},{__index=a})
    f.lookupHook=function()
        lookups=lookups+1
        return lookups==1 and a or changed
    end
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0})
        and f.moves==0 and not e.moveAttempted,"final exact-ID actor appearance revalidated before mutation")
end
-- Native-produced hash strings retain full precision; None is observed data,
-- while an absent/throwing getter or malformed pair is not a coherent sample.
for _,color in ipairs({"None","","variant_blue"}) do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    a.color=color;a.colorHash=color=="None" and "0" or "18446744073709551615"
    local o=f.engine:observe(e)
    check(o.visualStateObserved and o.colorObserved and o.appearanceVerified,"coherent tuple observed")
    check(o.observedColor==color and o.observedColorHash==a.colorHash,"exact current color and Uint64 string")
    check(o.observedAppearanceHash=="9007199254740995","appearance hash above 2^53 preserved")
    check(o.colorNameAvailable==(color~="") and not o.colorMatchVerified and not o.visualQualified,
        "symbol availability is not a supported color or visual match")
end
local colorFaults={
    function(a) a.colorError=true end,
    function(a) a.color=nil end,
    function(a) a.color=3 end,
    function(a) a.color=false end,
    function(a) a.color={} end,
    function(a) a.colorHash=nil end,
    function(a) a.colorHash=9007199254740992 end,
    function(a) a.colorHash="00" end,
    function(a) a.colorHash="-1" end,
    function(a) a.colorHash="18446744073709551616" end,
    function(a) a.colorHash="123ULL" end,
    function(a) a.appearanceHash=nil end,
    function(a) a.appearanceHash={} end,
    function(a) a.appearanceHash="1.5" end,
}
for _,fault in ipairs(colorFaults) do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash);fault(a)
    local o=f.engine:observe(e)
    check(o.ready and not o.visualStateObserved and not o.colorObserved and not o.appearanceVerified,
        "bad pair readback does not erase owned lifecycle readiness")
    check(o.observedAppearance==nil and o.observedColor==nil and not o.colorMatchVerified,
        "malformed pair cannot publish a partial or matching tuple")
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0}) and f.moves==0,
        "unknown color prevents coherent default movement qualification")
    check(not f.engine:retire(e) and f.deletes==1,"color readback cannot block exact retirement")
    f.finish(e.id.hash);check(f.engine:retire(e),"color-fault cleanup finishes")
end
for _,fault in ipairs({"appearance","color","identity","detach"}) do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    f.visualHook=function(target)
        if fault=="appearance" then target.appearance="changed"
        elseif fault=="color" then target.color="changed"
        elseif fault=="identity" then f.globals[target.id]=setmetatable({nativeRef={}},{__index=target})
        else target.attached=false end
    end
    local o=f.engine:observe(e)
    check(not o.visualStateObserved and not o.appearanceVerified,"incoherent pair not admitted: "..fault)
    check(not o.colorObserved and not o.observedColor,"no partial color from rejected native sample")
end
for _,fault in ipairs({"valid","entity","context"}) do
    local f=make();local e=f.entry();f.engine:create(e);f.complete(e.id.hash)
    f.visualTransform=function(raw)
        if fault=="valid" then raw.valid=1
        elseif fault=="entity" then raw.entityDecimal="9007199254740992"
        else raw.contextDecimal="9007199254740992" end
        return raw
    end
    local o=f.engine:observe(e)
    check(not o.visualStateObserved and not o.appearanceVerified,"strict native sample identity/validity")
end
do
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    local lookups=0
    f.lookupHook=function()
        lookups=lookups+1
        if lookups==2 then a.color="changed_before_move";a.colorHash="9007199254740997" end
        return a
    end
    check(not pcall(f.engine.move,f.engine,e,{x=3,y=0,z=0,yaw=0}) and f.moves==0 and not e.moveAttempted,
        "same exact actor color changing before final mutation rejects move")
    f.lookupHook=nil
    local o=f.engine:observe(e)
    check(o.observedColor=="changed_before_move" and o.colorObserved and not o.colorMatchVerified,
        "later coherent changed color remains observed without claiming a match")
end
local ffiOk,ffi=pcall(require,"ffi")
if ffiOk then
    local f=make();local e=f.entry();f.engine:create(e);local a=f.complete(e.id.hash)
    a.colorHash=ffi.new("uint64_t",9007199254740992)+ffi.new("uint64_t",1)
    check(not f.engine:observe(e).visualStateObserved,"do not parse CName hash cdata in Lua")
    a.colorHash="9007199254740993"
    check(f.engine:observe(e).observedColorHash=="9007199254740993","accept exact native decimal export")
end
-- Readable source drift guard for the reviewed Python builder's exact catalogs.
do
    local f=make()
    local file=assert(io.open(root.."/scripts/build-passive-idle-archive.py","r"));local idle=file:read("*a");file:close()
    local j=f.engine:profile("judy_default")
    for field,constant in pairs({template="ENTITY",mesh="MESH",rig="RIG",animset="ANIMSET",graph="GRAPH"}) do
        check(idle:match(constant..' = r"(.-)"')==j[field],"Judy builder drift: "..field)
    end
    file=assert(io.open(folder.."build_profile.py","r"));local builder=file:read("*a");file:close()
    local start=assert(builder:find('"mitch_default": Profile',1,true));local m=f.engine:profile("mitch_default")
    local block=builder:sub(start,assert(builder:find("\n})",start,true)))
    for _,field in ipairs({"template","mesh","rig","animset"}) do check(block:find(m[field],1,true),"Mitch builder drift: "..field) end
    j.template="mutated";check(f.engine:profile("judy_default").template~="mutated","catalog returns copy")
end
for _,name in ipairs({"judy_encounter","mitch_encounter"}) do
    local f=make();local profile=f.engine:profile(name)
    check(profile.encounter and profile.graph:find("encounter",1,true),"explicit encounter profile and graph")
    for _,field in ipairs({"template","graph","mesh","rig","animset","impact","death"}) do
        f.resources[profile[field]]=false
        check(not pcall(f.engine.create,f.engine,f.entry(name)) and f.creates==0,"encounter dependency gate: "..field)
        f.resources[profile[field]]=nil
    end
    local e=f.entry(name);check(f.engine:create(e),"encounter creation uses same owned lifecycle")
    local actor=f.complete(e.id.hash);f.engine:observe(e)
    check(f.engine:presentationReady(e),"exact passive encounter preflight")
    for _,sample in ipairs({{"reaction",0.3,"cp_coop_hit_progress",1},{"death",0.7,"cp_coop_death_progress",2},{"dead",1,"cp_coop_death_progress",2}}) do
        f.events={}
        check(f.engine:present(e,{localKey=e.idKey,phase=sample[1],progress=sample[2]},function() return true end),"existing adapter accepts guarded sample")
        check(#f.events==2 and f.events[1].key==sample[3] and f.events[1].value==sample[2]
            and f.events[2].key=="cp_coop_phase" and f.events[2].value==sample[4],"actual progress then phase setter sequence")
        check(f.events[1].actor==actor.nativeRef and f.events[2].actor==actor.nativeRef
            and e.presentationSubmission=="queued_not_observed","exact actor submission is not animation evidence")
    end
    e.retiring=true;check(not f.engine:retire(e) and f.deletes==1,"encounter retirement reuses exact cleanup")
end
for _,fault in ipairs({"paused","pause_unknown","requests_missing","pregame","player","actor","detached","appearance","color","template","root","binding"}) do
    local f=make();local e=f.entry("judy_encounter");f.engine:create(e);local a=f.complete(e.id.hash);f.engine:observe(e)
    local current=true
    f.queueHook=function()
        if fault=="paused" then f.paused=true
        elseif fault=="pause_unknown" then f.paused=nil
        elseif fault=="requests_missing" then f.requests=false
        elseif fault=="pregame" then f.preGame=true
        elseif fault=="player" then f.playerNative={}
        elseif fault=="actor" then local other=setmetatable({nativeRef={}},{__index=a});f.actors[a.id],f.globals[a.id]=other,other
        elseif fault=="detached" then a.attached=false
        elseif fault=="appearance" then a.appearance="other"
        elseif fault=="color" then a.colorError=true
        elseif fault=="template" then a.template=f.ref("foreign.ent")
        elseif fault=="root" then a.root=false
        else current=false end
    end
    check(not f.engine:present(e,{localKey=e.idKey,phase="reaction",progress=0.2},function() return current end),"mid-pair failure rejected: "..fault)
    check(#f.events==1 and f.events[1].key=="cp_coop_hit_progress" and e.presentationForwarded==1,
        "fresh guard blocks phase after "..fault)
    check(e.presentationSubmission=="failed_or_partial","partial is never called completed")
end
for _,fault in ipairs({"constructor","first_setter","second_setter"}) do
    local f=make();local e=f.entry("mitch_encounter");f.engine:create(e);f.complete(e.id.hash);f.engine:observe(e)
    if fault=="constructor" then f.constructorThrows=true
    elseif fault=="first_setter" then f.queueThrows=true
    else f.queueHook=function(_,_,count) if count==2 then error("second setter unknown") end end end
    local sample={localKey=e.idKey,phase="reaction",progress=0.4}
    check(not f.engine:present(e,sample,function() return true end),"event construction/forwarding failure returned")
    check(#f.events==(fault=="constructor" and 0 or fault=="first_setter" and 1 or 2),"accurate attempted setter count")
    f.constructorThrows=false;f.queueThrows=false;f.queueHook=nil;f.events={}
    check(f.engine:present(e,sample,function() return true end) and #f.events==2,"normalized sample can safely retry after fresh preflight")
end
do
    local f=make();local e=f.entry();f.engine:create(e);f.complete(e.id.hash);f.engine:observe(e)
    check(not f.engine:present(e,{localKey=e.idKey,phase="reaction",progress=0},function() return true end)
        and #f.events==0,"idle graph never receives encounter setters")
end
print("Passive model actual engine adapter checks: "..checks)
