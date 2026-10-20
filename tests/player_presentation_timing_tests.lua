local root=assert(arg[1]);local M=assert(loadfile(arg[2] or root..'/runtime/session/cet/CP2077Coop/player_presentation.lua'))()
CName={new=function(v)return v end};NewObject=function()return {}end
local function fixture(scale)
    local events={};local actor={IsAttached=function()return true end,GetEntityID=function()return {hash='9007199254740993ULL'}end,
        CP2077Fixture_SetWeaponVisible=function()return true end,QueueEvent=function(_,event)events[#events+1]=event end}
    Game={GetTimeSystem=function()return {GetActiveTimeDilation=function()return scale end}end}
    local state={};local value={fresh=true,revision=1,stance=1,weapon=2,record='16ac119774',aim=1}
    local function tick(time,phase,progress)
        return M.apply(actor,state,value,{phase=phase or 0,progress=progress or 0,previous={time=time}})
    end
    tick(0)
    value.stance,value.aim=2,2
    local weights={}
    for frame=1,6 do
        tick(frame/60,1,frame/60)
        weights[frame]={state.stanceWeight,state.motionWeight,state.poseBlend}
        assert(state.poseTo==4 and state.poseFrom==0)
        assert(state.poseFromProgress==0,'departing gait phase must be frozen during crossfade')
    end
    assert(weights[1][1]>0 and weights[1][1]<1,'real-time crouch transition must blend')
    assert(weights[4][1]<1 and weights[5][1]==1,'crouch must settle within84ms at60Hz')
    assert(weights[5][2]==1 and weights[5][3]==1,'motion and weapon must also settle')
    local count=#events;value.sequence=99;value.ageMs=0;tick(.12,1,.2)
    assert(#events==count,'steady repair must not restart crossfade or requeue inputs')
    value.fresh=false;assert(tick(.14,1,.22)=='owned_overrides_neutralized')
    assert(state.inputs.cp_coop_stance==0 and state.inputs.cp_coop_crouch_motion==0 and state.inputs.cp_coop_weapon_weight==0)
    assert(state.inputs.cp_coop_weapon_pose==0 and state.inputs.cp_coop_weapon_previous_pose==0)
    value.fresh=true;tick(.3,1,.4);assert(state.inputs.cp_coop_stance==1 and state.inputs.cp_coop_weapon_blend==1)
    tick(-1,1,.2);assert(state.inputs.cp_coop_stance==1,'clock discontinuity must settle rather than extrapolate')
    for frame=1,120 do
        value.stance=frame%2==0 and 1 or 2;value.aim=frame%3==0 and 1 or 2
        tick(frame/60,frame%2==0 and 0 or 1,(frame%60)/60)
        for _,key in ipairs({'cp_coop_stance','cp_coop_crouch_motion','cp_coop_weapon_blend','cp_coop_weapon_previous_progress'})do
            local v=state.inputs[key];assert(v==v and v>=0 and v<=1,'retarget weights must stay finite/bounded')
        end
        assert(state.poseFrom>=0 and state.poseFrom<=4 and state.poseFrom%1==0)
    end
    return weights
end
local normal,slow=fixture(1),fixture(.03)
for frame=1,6 do for index=1,3 do assert(normal[frame][index]==slow[frame][index],'world dilation changed pose timing')end end
for _,weapon in ipairs({1,2})do
    local actor={IsAttached=function()return true end,GetEntityID=function()return {hash='9007199254740993ULL'}end,
        CP2077Fixture_SetWeaponVisible=function()return true end,QueueEvent=function()end}
    local state={};local observed={fresh=true,revision=1,stance=2,weapon=weapon,
        record=weapon==2 and '16ac119774' or '0000000000',aim=weapon==2 and 2 or 1}
    local function tick(t,phase)M.apply(actor,state,observed,{phase=phase,progress=.25,previous={time=t}})end
    tick(0,0);assert(state.stanceWeight==1,'grounded crouch must remain admitted')
    tick(.02,5);assert(state.stanceWeight<1,'late crouch cannot fully override takeoff')
    tick(.1,3);assert(state.stanceWeight==0 and state.motionWeight==0,'airborne jump must release the crouch layer within80ms')
    assert(state.visible==(weapon==2),'releasing lower crouch must preserve guarded weapon visibility')
    tick(.12,4);assert(state.stanceWeight==0,'late crouch cannot cover the landing animation')
    tick(.14,0);assert(state.stanceWeight>0 and state.stanceWeight<1,'grounded crouch resumes with a real-clock blend')
    tick(.22,0);assert(state.stanceWeight==1,'grounded crouch must recover after landing')
end
print('Presentation timing: real-time crouch/motion/weapon blend, frozen departing gait, repair stability, stale release and bounded retargeting passed')
