-- PRIVATE LOCAL ENGINE FIXTURE. Not network delivery or real captured actions.
-- Install only as zz_CP2077ActionFixture/init.lua in the controlled bench.
local M={}
local clock,due,count=0,0,0
local seen,active={},nil
local phases={
    {name="standing",stance=0,weight=0,pose=0},
    {name="crouch_idle",stance=1,weight=0,pose=0},
    {name="crouch_walk",stance=1,weight=0,pose=0,moving=true},
    {name="rifle_ready_pose_no_weapon",stance=0,weight=1,pose=0},
    {name="rifle_aim_pose_no_weapon",stance=0,weight=1,pose=3},
    {name="handgun_ready_pose_no_weapon",stance=0,weight=1,pose=5},
    {name="handgun_aim_pose_no_weapon",stance=0,weight=1,pose=8},
    {name="crouch_rifle_aim_pose_no_weapon",stance=1,weight=1,pose=3},
    {name="crouch_handgun_aim_pose_no_weapon",stance=1,weight=1,pose=8},
    {name="standing_return",stance=0,weight=0,pose=0}}
local weaponPhases={
    {name="igla_holstered",stance=0,weight=0,pose=0},
    {name="igla_crouch_holstered",stance=1,weight=0,pose=0},
    {name="igla_ready_mount_test",stance=0,weight=1,pose=0},
    {name="igla_aim_mount_test",stance=0,weight=1,pose=3},
    {name="igla_crouch_ready",stance=1,weight=1,pose=0},
    {name="igla_crouch_aim",stance=1,weight=1,pose=3},
    {name="igla_crouch_walk",stance=1,weight=1,pose=0,moving=true},
    {name="igla_holstered_return",stance=0,weight=0,pose=0}}
local function key(v)return tostring(v):gsub("[uUlL]+$","") end
local function read()
    local f=io.open("action-request.json","r");if not f then return end
    local data=f:read(2049);f:close();if #data>2048 then return end
    local ok,r=pcall(json.decode,data)
    if ok and type(r)=="table" and type(r.request)=="string" and #r.request>0 and #r.request<=64
        and not r.request:find("[^%w%-]") then return r end
end
local prior=read();if prior then seen[prior.request]=true end
local function report(status,detail)
    local result={version=1,request=active and active.request,status=status,detail=detail,
        local_fixture_only=true,elapsed=active and active.started and clock-active.started,
        model=active and active.model,
        actor=active and active.id and key(active.id.hash)}
    local f=assert(io.open("action-receipt.json","w"));f:write(json.encode(result));f:close()
    spdlog.info("[ActionFixture] "..status.." "..tostring(detail))
end
local function cleanup()
    if not active then return end
    local s,id=active.system,active.id
    if not id then active=nil;return end
    local actor=s:GetEntity(id)
    if actor and IsDefined(actor) and actor:IsAttached() and s:IsSpawned(id) and not s:IsSpawning(id) then
        if key(actor:GetEntityID().hash)~=key(id.hash) then error("fixture cleanup identity changed") end
        active.actor,active.seenReady=actor,true
        if not active.removing then active.removing=s:DespawnEntity(id)==true end
    end
    local global=Game.FindEntityByID(id)
    local retained=active.actor
    if active.seenReady and not s:IsManaged(id) and not s:IsSpawned(id) and not s:IsSpawning(id)
        and (not actor or not IsDefined(actor) or actor:IsAttached()==false)
        and (not global or not IsDefined(global) or global:IsAttached()==false)
        and (not retained or not IsDefined(retained) or retained:IsAttached()==false) then
        report("removed","exact fixture actor detached");active=nil
    end
end
local function input(actor,name,value)
    local event=assert(NewObject("entAnimInputSetterFloat"))
    event.key,event.value=CName.new(name),value;actor:QueueEvent(event)
end
local function context(r)
    local p=Game.GetPlayer();local requests=Game.GetSystemRequestsHandler()
    return r.version==1 and r.mode=="action-fixture" and r.session==key(Game.CP2077Session_Session())
        and Game.CP2077Session_Phase()==4 and Game.CP2077Session_Self()~=Game.CP2077Session_Host()
        and p and p:IsAttached() and requests and requests:IsGamePaused()==false
end
registerForEvent("onUpdate",function(dt)
    if type(dt)~="number" or dt<=0 or dt~=dt or dt==math.huge then return end
    clock=clock+dt
    if active then
        if active.finishing or not context(active) then active.finishing=true;cleanup();return end
        local actor=active.system:GetEntity(active.id)
        if not actor or not IsDefined(actor) or not actor:IsAttached() then
            if clock-active.admitted>10 then active.finishing=true;report("failed","spawn not observed");cleanup() end
            return
        end
        if key(actor:GetEntityID().hash)~=key(active.id.hash) then error("fixture identity changed") end
        active.actor,active.seenReady=actor,true;active.started=active.started or clock
        local elapsed=clock-active.started;local index=math.floor(elapsed/5)+1
        local sequence=active.model=="igla" and weaponPhases or phases
        if index>#sequence then active.finishing=true;report("poses_submitted","visual review required");cleanup();return end
        local phase=sequence[index]
        if active.phase~=index then
            if active.model=="igla" then
                local ok,submitted=pcall(function()return actor:CP2077Fixture_SetWeaponVisible(phase.weight==1) end)
                if not ok or submitted~=true then
                    active.finishing=true;report("failed","exact fixture visibility submission rejected");cleanup();return
                end
            end
            active.phase=index;report("phase_submitted",phase.name)
        end
        local world=WorldTransform.new()
        WorldTransform.SetPosition(world,Vector4.new(-813+(phase.moving and math.sin(elapsed*1.5) or 0),821.5,24.4042,1))
        WorldTransform.SetOrientationEuler(world,EulerAngles.new(0,0,phase.moving and (math.cos(elapsed*1.5)>0 and -90 or 90) or 160))
        actor:SetWorldTransform(world)
        input(actor,"cp_coop_stance",phase.stance);input(actor,"cp_coop_crouch_motion",phase.moving and 1 or 0)
        input(actor,"cp_coop_weapon_weight",phase.weight);input(actor,"cp_coop_weapon_pose",phase.pose)
        input(actor,"cp_coop_weapon_previous_pose",phase.pose);input(actor,"cp_coop_weapon_blend",1)
        input(actor,"cp_coop_weapon_previous_progress",0)
        input(actor,"cp_coop_loco_phase",0);input(actor,"cp_coop_loco_progress",(elapsed*0.6)%1)
        return
    end
    if clock>=1800 or count>=3 or clock<due then return end
    due=clock+0.2;local r=read();if not r or seen[r.request] then return end
    seen[r.request]=true;count=count+1
    if r.model~=nil and r.model~="poses" and r.model~="igla" then spdlog.info("[ActionFixture] rejected model");return end
    if not context(r) then spdlog.info("[ActionFixture] rejected context");return end
    local system=Game.GetStaticEntitySystem();if not system or system:IsReady()~=true then return end
    active={version=r.version,mode=r.mode,request=r.request,session=r.session,system=system,admitted=clock,model=r.model or "poses"}
    local spec=StaticEntitySpec.new()
    spec.templatePath=ResRef.FromName(active.model=="igla" and "base\\cp2077coop\\entities\\player_weapon_igla_fixture.ent"
        or "base\\cp2077coop\\entities\\player_actions_fixture.ent")
    spec.position=Vector4.new(-813,821.5,24.4042,1);spec.orientation=Quaternion.new(0,0,1,0)
    spec.attached=true;spec.tags={CName.new("CP2077Coop.PrivateActionFixture"),CName.new(r.request)}
    active.id=system:SpawnEntity(spec)
    if not active.id or key(active.id.hash)=="0" then report("failed","invalid spawn token");active=nil;return end
    report("spawn_submitted","not yet observed")
end)
registerForEvent("onShutdown",function()if active then active.finishing=true;pcall(cleanup) end end)
return M
