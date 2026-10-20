-- Local cosmetic inference from interpolated XYZ, not an authoritative action.
-- This experimental renderer has no AI, navigation, root motion or gameplay.
local M = {}
M.revision = "20261020-locomotion-8"
-- Installed walk/sprint clips travel along rig +Y. Preserve network/entity
-- heading; the earlier guessed 180-degree correction made movement face back.
M.yawOffset = 0
M.template = "base\\cp2077coop\\entities\\cp2077coop_player_locomotion.ent"
function M.new(directional)
    return {phase=0,progress=0,cycles=0,directional=directional==true,
        direction=0,previousDirection=0,directionBlend=1,directionWeight=0,directionPreviousProgress=0}
end
local strides={5.960565090179443,5.90962028503418,1.6499662399291992,1.7075181007385254}
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function direction_step(state,pose,dt,dx,dy,speed,oldProgress)
    local a=pose.actions
    local eligible=state.phase==1 and a and a.fresh==true and a.stance==1 and a.weapon==2
        and a.record=="16ac119774" and (a.aim==1 or a.aim==2)
        and finite(pose.yaw) and dt>0 and dt<=.25
    if not eligible then
        -- Never expose the combat bank's fists when weapon/crouch/stale state
        -- leaves this narrowly qualified experiment.
        state.directionWeight,state.directionBlend=0,1
        state.previousDirection=state.direction
        state.directionPreviousProgress=oldProgress
        return
    end
    local target=state.direction
    if speed>.15 then
        local forward=(-math.sin(pose.yaw)*dx+math.cos(pose.yaw)*dy)/(speed*dt)
        local right=(math.cos(pose.yaw)*dx+math.sin(pose.yaw)*dy)/(speed*dt)
        local scores={forward,right,-forward,-right}
        for i=0,3 do
            if scores[i+1]>scores[target+1]+.15 then target=i end
        end
    end
    -- The existing walking phase holds a brief zero-motion interpolation sample.
    -- Retain its selected direction too, freezing progress instead of clearing
    -- the layer and blending forward again on the next moving frame.
    local amount=dt/.08
    if target~=state.direction then
        if state.directionBlend>=.5 then
            state.previousDirection,state.directionPreviousProgress=state.direction,oldProgress
        end
        state.direction,state.directionBlend=target,0
    end
    state.directionBlend=math.min(1,state.directionBlend+amount)
    state.directionWeight=math.min(1,state.directionWeight+amount)
    return strides[state.direction+1]
end
function M.step(state, pose, now)
    local previous = state.previous
    local dt = previous and now-previous.time or 0
    local speed, vertical,dx,dy = 0,0,0,0
    local oldProgress=state.cycles
    if previous and dt > 0 and dt <= 0.25 then
        dx,dy=pose.x-previous.x,pose.y-previous.y
        speed = math.sqrt(dx*dx+dy*dy)/dt
        vertical = (pose.z-previous.z)/dt
    end
    local discontinuity = speed > 35 or math.abs(vertical) > 35
    if discontinuity then
        -- A source teleport/correction is a new ground baseline, not takeoff.
        speed,vertical=0,0
        state.ground,state.airborne,state.landing=pose.z,false,nil
        state.airStillSince,state.sprinting,state.gaitSpeed=nil,false,0
        state.phase=0
    end
    -- UDP cadence and interpolation boundaries can briefly cross the gait
    -- threshold. Filter only gait selection, never the network body position.
    if not previous or dt <= 0 or dt > 0.25 then
        state.gaitSpeed, state.sprinting, state.stillSince = speed, false, nil
    else
        state.gaitSpeed = state.gaitSpeed+(speed-state.gaitSpeed)*(1-math.exp(-dt/0.08))
    end
    if speed > 0.15 then state.stillSince = nil
    elseif not state.stillSince then state.stillSince = now end
    if state.sprinting then
        if state.gaitSpeed < 3.0 then state.sprinting = false end
    elseif state.gaitSpeed > 4.0 then state.sprinting = true end
    local moving = speed > 0.15 or dt>0 and dt<=0.25 and (state.phase == 1 or state.phase == 2)
        and state.stillSince and now-state.stillSince < 0.05
    state.ground = state.ground or pose.z
    if previous and (dt <= 0 or dt > 0.25) then
        state.ground, state.airborne, state.landing = pose.z, false, nil
    end
    local height = pose.z-state.ground
    if not state.airborne and height > 0.12 and vertical > 0.8 then
        state.airborne, state.takeoff, state.landing = true, now, nil
        state.airStillSince=nil
    end
    if state.airborne then
        if math.abs(vertical) < 0.1 then state.airStillSince=state.airStillSince or now
        else state.airStillSince=nil end
    end
    if state.airborne and (height <= 0.06 and vertical <= 0
        or state.airStillSince and now-state.airStillSince>=0.2) then
        -- Landing on a higher ledge never crosses the old ground height. A
        -- sustained vertical stop settles it; a normal brief apex does not.
        state.airborne,state.landing,state.ground=false,now,pose.z
        state.airStillSince=nil
    end
    if state.airborne then
        local age = now-state.takeoff
        if age < 0.12 then state.phase, state.progress = 5, age/0.12
        else state.phase, state.progress = 3, ((age-0.12)/0.566666663)%1 end
    elseif state.landing and now-state.landing < 0.35 then
        state.phase, state.progress = 4, (now-state.landing)/0.35
    elseif moving then
        -- Distance, not correction error, advances gait. Vertical motion never
        -- promotes walking to sprint. Each actor owns its independent phase.
        state.phase = state.sprinting and 2 or 1
        state.cycles = (state.cycles+speed*math.max(0, math.min(dt, 0.25))
            -- Installed 2.31 relaxed clip motion endpoints, metres/cycle.
            /(state.phase == 2 and 3.053292989730835 or 3.7953503131866455))%1
        state.progress = state.cycles
        if math.abs(vertical) < 0.35 or pose.z < state.ground then state.ground=pose.z end
        state.landing = nil
    else
        state.phase, state.progress = 0, 0
        if math.abs(vertical) < 0.35 or pose.z < state.ground then state.ground=pose.z end
        state.landing = nil
    end
    if state.directional then
        local stride=direction_step(state,pose,dt,dx,dy,speed,oldProgress)
        if stride then
            state.cycles=(oldProgress+speed*dt/stride)%1
            state.progress=state.cycles
        end
    end
    state.speed, state.vertical = speed, vertical
    state.previous = {x=pose.x,y=pose.y,z=pose.z,time=now}
    return state.phase, state.progress
end
function M.apply(actor, state)
    -- Queue admission is not an animation receipt. Live video must verify the
    -- actual selected pose and the next-frame world/root readback separately.
    local inputs={{"cp_coop_loco_progress",state.progress}}
    if state.directional then
        for _,v in ipairs({{"cp_coop_walk_direction",state.direction},
            {"cp_coop_walk_previous_direction",state.previousDirection},
            {"cp_coop_walk_direction_blend",state.directionBlend},
            {"cp_coop_walk_previous_progress",state.directionPreviousProgress},
            {"cp_coop_walk_direction_weight",state.directionWeight}})do inputs[#inputs+1]=v end
    end
    inputs[#inputs+1]={"cp_coop_loco_phase",state.phase}
    for _, input in ipairs(inputs) do
        local event = assert(NewObject("entAnimInputSetterFloat"), "animation input unavailable")
        event.key, event.value = CName.new(input[1]), input[2]
        actor:QueueEvent(event)
    end
end
return M
