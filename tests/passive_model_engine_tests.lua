local root=assert(arg[1])
local folder=root.."/experiments/passive-models/"
package.path=folder.."?.lua;"..package.path
local checks=0
local function check(value,why) checks=checks+1;assert(value,why) end
local function id(value) return {hash=value} end
local function make()
    local f={native=0,creates=0,moves=0,deletes=0,tokens={},actors={},globals={},tags={},logs={},paused=false,
        ready=true,resources={},nextId=0,playerId="9007199254740997ULL",requests=true}
    local refs,serial={},0
    local function ref(path)
        if not refs[path] then serial=serial+1;refs[path]="18014398509482"..string.format("%03d",serial).."ULL" end
        return {path=path,hash=refs[path]}
    end
    local function native() f.native=f.native+1 end
    local function actor(value,spec)
        local a={attached=true,id=value,template=spec.templatePath,root=true,
            position={x=spec.position.x,y=spec.position.y,z=spec.position.z},orientation=spec.orientation,
            appearance=spec.appearanceName}
        function a:GetEntityID() native();return id(self.id) end
        function a:IsAttached() native();return self.attached end
        function a:GetTemplatePath() native();return self.template end
        function a:IsExactlyA(name) native();assert(name=="entEntity");return self.root end
        function a:CP2077PassiveModelFixture_CurrentAppearance()
            native();if self.appearanceError then error("appearance_read_failed") end;return self.appearance
        end
        function a:GetWorldPosition() native();if self.readError then error("pose_read_failed") end;return self.position end
        function a:GetWorldOrientation() native();return self.orientation end
        function a:SetWorldTransform(world)
            native();f.moves=f.moves+1;self.submitted=world
            if f.applyMove then self.position=world.position;self.orientation=world.orientation end
            if f.moveThrows then error("native_move_outcome_unknown") end
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
            return {IsGamePaused=function() native();return f.paused end,IsPreGame=function() native();return false end}
        end,
        GetPlayer=function()
            native();return {IsAttached=function() return true end,GetEntityID=function() return id(f.playerId) end,
                GetWorldPosition=function() return {x=0,y=0,z=0} end}
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
    local getter=a.CP2077PassiveModelFixture_CurrentAppearance
    if fault=="missing" then a.CP2077PassiveModelFixture_CurrentAppearance=nil
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
    a.CP2077PassiveModelFixture_CurrentAppearance=getter;a.appearanceError=false;a.appearance="default"
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
print("Passive model actual engine adapter checks: "..checks)
