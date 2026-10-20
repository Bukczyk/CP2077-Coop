-- Local cosmetic inference from interpolated XYZ, not an authoritative action.
-- This experimental renderer has no AI, navigation, root motion or gameplay.
local M = {}
M.revision = "20261020-locomotion-13"
-- Installed walk/sprint clips travel along rig +Y. Preserve network/entity
-- heading; the earlier guessed 180-degree correction made movement face back.
M.yawOffset = 0
M.template = "base\\cp2077coop\\entities\\cp2077coop_player_locomotion.ent"
function M.new(directional,smooth)
    return {phase=0,progress=0,cycles=0,directional=directional==true,smooth=smooth==true,
        previousPhase=0,previousProgress=0,phaseWeight=0,phaseDirection=0,phaseDirectionWeight=0,
        crouchBackward=0,crouchTarget=0,crouchProgress=0,
        crouchDirection=0,crouchSide=0,crouchPreviousSide=0,crouchSideBlend=1,crouchSideWeight=0,crouchPreviousProgress=0,
        direction=0,previousDirection=0,directionBlend=1,directionWeight=0,directionPreviousProgress=0}
end
-- Corrected rifle locomotion derivatives retain these original motion distances.
-- Their hips follow the relaxed forward reference while solved feet keep paths.
local strides={6.4955267906188965,1.4817253351211548,1.593894124031067,1.4952208995819092}
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function direction_step(state,pose,dt,dx,dy,speed,oldProgress)
    local a=pose.actions
    local supported=a and (a.weapon==1 and a.record=="0000000000" and a.aim==1
        or a.weapon==2 and a.record=="16ac119774" and (a.aim==1 or a.aim==2))
    local eligible=state.phase==1 and a and a.fresh==true and a.stance==1 and supported
        and finite(pose.yaw) and dt>0 and dt<=.25
    if not eligible then
        -- Matched graphs mask the directional bank to lower bones only. Unknown
        -- weapon/crouch/stale state still leaves this bounded experiment.
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
local function crouch_step(state,pose,dt,dx,dy,speed,discontinuity,oldProgress)
    local a=pose.actions
    local eligible=a and a.fresh==true and a.stance==2 and finite(pose.yaw)
        and dt>0 and dt<=.25 and not discontinuity and state.phase<=2
    if not eligible then
        state.crouchBackward,state.crouchTarget=0,0
        state.crouchDirection,state.crouchSideWeight,state.crouchSideBlend=0,0,1
        state.crouchPreviousSide=state.crouchSide
        state.crouchPreviousProgress=state.cycles
        return nil,false
    end
    if speed>.15 then
        local forward=(-math.sin(pose.yaw)*dx+math.cos(pose.yaw)*dy)/(speed*dt)
        local right=(math.cos(pose.yaw)*dx+math.sin(pose.yaw)*dy)/(speed*dt)
        local scores={forward,right,-forward,-right}
        local target=state.crouchDirection
        for i=0,3 do if scores[i+1]>scores[target+1]+.15 then target=i end end
        state.crouchDirection=target
    end
    local amount=dt/.08
    local sideways=state.crouchDirection==1 or state.crouchDirection==3
    if sideways then
        local side=state.crouchDirection==3 and 1 or 0
        if side~=state.crouchSide then
            if state.crouchSideBlend>=.5 then
                state.crouchPreviousSide,state.crouchPreviousProgress=state.crouchSide,oldProgress
            end
            state.crouchSide,state.crouchSideBlend=side,0
        end
        state.crouchSideWeight=math.min(1,state.crouchSideWeight+amount)
    else state.crouchSideWeight=math.max(0,state.crouchSideWeight-amount) end
    state.crouchSideBlend=math.min(1,state.crouchSideBlend+amount)
    state.crouchTarget=state.crouchDirection==2 and 1 or 0
    if state.crouchTarget==1 then state.crouchBackward=math.min(1,state.crouchBackward+amount)
    else state.crouchBackward=math.max(0,state.crouchBackward-amount) end
    -- Installed stealth clips span a different travel distance from standing
    -- walking. Retain the last distance sample during a stop's motion fade.
    return (state.phase==1 or state.phase==2) and
        (sideways and (state.crouchSide==0 and strides[2] or strides[4]) or
        state.crouchTarget==1 and 3.992504835128784 or 6.249844074249268) or nil,true
end
function M.step(state, pose, now)
    local previous = state.previous
    local dt = previous and now-previous.time or 0
    local speed, vertical,dx,dy = 0,0,0,0
    local oldProgress=state.cycles
    local oldPhase,oldSample=state.phase,state.progress
    local oldDirection=state.directionBlend<.5 and state.previousDirection or state.direction
    local oldDirectionProgress=state.directionBlend<.5 and state.directionPreviousProgress or oldSample
    local oldDirectionWeight=state.directionWeight
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
        local crouchStride,crouched=crouch_step(state,pose,dt,dx,dy,speed,discontinuity,oldProgress)
        stride=crouchStride or stride
        if stride then
            state.cycles=(oldProgress+speed*dt/stride)%1
            state.progress=state.cycles
        end
        state.crouchProgress=crouched and state.cycles or 0
    end
    if state.smooth then
        local a=pose.actions
        local eligible=previous and dt>0 and dt<=.25 and not discontinuity
            and a and a.fresh==true and a.stance==1 and state.phase<=2 and oldPhase<=2
        if not eligible then
            -- Jump phases, stale state, crouch and discontinuities never retain
            -- a departing standing pose. Old assets ignore these extra inputs.
            state.previousPhase,state.previousProgress,state.phaseWeight=state.phase,state.progress,0
            state.phaseDirection,state.phaseDirectionWeight=state.direction,0
        else
            if oldPhase~=state.phase then
                -- Bound retargeting to two poses. Keep the dominant departing
                -- pose and freeze its exact sample, including walk direction.
                if state.phaseWeight<=.5 then
                    state.previousPhase=oldPhase
                    state.previousProgress=oldPhase==1 and oldDirectionWeight>0 and oldDirectionProgress or oldSample
                    state.phaseDirection,state.phaseDirectionWeight=oldDirection,oldDirectionWeight
                end
                state.phaseWeight=1
            end
            state.phaseWeight=math.max(0,state.phaseWeight-dt/.08)
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
    if state.smooth then
        for _,v in ipairs({{"cp_coop_loco_previous_phase",state.previousPhase},
            {"cp_coop_loco_previous_progress",state.previousProgress},
            {"cp_coop_loco_blend_weight",state.phaseWeight}})do inputs[#inputs+1]=v end
        if state.directional then
            inputs[#inputs+1]={"cp_coop_loco_previous_direction",state.phaseDirection}
            inputs[#inputs+1]={"cp_coop_loco_previous_direction_weight",state.phaseDirectionWeight}
        end
    end
    if state.directional then
        for _,v in ipairs({{"cp_coop_walk_direction",state.direction},
            {"cp_coop_walk_previous_direction",state.previousDirection},
            {"cp_coop_walk_direction_blend",state.directionBlend},
            {"cp_coop_walk_previous_progress",state.directionPreviousProgress},
            {"cp_coop_walk_direction_weight",state.directionWeight},
            {"cp_coop_crouch_progress",state.crouchProgress},
            {"cp_coop_crouch_backward",state.crouchBackward},
            {"cp_coop_crouch_side",state.crouchSide},
            {"cp_coop_crouch_previous_side",state.crouchPreviousSide},
            {"cp_coop_crouch_side_blend",state.crouchSideBlend},
            {"cp_coop_crouch_side_weight",state.crouchSideWeight},
            {"cp_coop_crouch_previous_progress",state.crouchPreviousProgress}})do inputs[#inputs+1]=v end
    end
    inputs[#inputs+1]={"cp_coop_loco_phase",state.phase}
    for _, input in ipairs(inputs) do
        local event = assert(NewObject("entAnimInputSetterFloat"), "animation input unavailable")
        event.key, event.value = CName.new(input[1]), input[2]
        actor:QueueEvent(event)
    end
end
return M
