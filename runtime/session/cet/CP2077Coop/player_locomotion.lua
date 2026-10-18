-- Local cosmetic inference from interpolated XYZ, not an authoritative action.
-- This experimental renderer has no AI, navigation, root motion or gameplay.
local M = {}
M.revision = "20261018-locomotion-4"
-- Installed walk/sprint clips travel along rig +Y. Preserve network/entity
-- heading; the earlier guessed 180-degree correction made movement face back.
M.yawOffset = 0
M.template = "base\\cp2077coop\\entities\\cp2077coop_player_locomotion.ent"
function M.new() return {phase=0, progress=0, cycles=0} end
function M.step(state, pose, now)
    local previous = state.previous
    local dt = previous and now-previous.time or 0
    local speed, vertical = 0, 0
    if previous and dt > 0 and dt <= 0.25 then
        local dx, dy = pose.x-previous.x, pose.y-previous.y
        speed = math.sqrt(dx*dx+dy*dy)/dt
        vertical = (pose.z-previous.z)/dt
    end
    state.ground = state.ground or pose.z
    if previous and (dt <= 0 or dt > 0.25) then
        state.ground, state.airborne, state.landing = pose.z, false, nil
    end
    local height = pose.z-state.ground
    if not state.airborne and height > 0.12 and vertical > 0.8 then
        state.airborne, state.takeoff, state.landing = true, now, nil
    end
    if state.airborne and height <= 0.06 and vertical <= 0 then
        state.airborne, state.landing = false, now
    end
    if state.airborne then
        local age = now-state.takeoff
        if age < 0.12 then state.phase, state.progress = 5, age/0.12
        else state.phase, state.progress = 3, ((age-0.12)/0.566666663)%1 end
    elseif state.landing and now-state.landing < 0.35 then
        state.phase, state.progress = 4, (now-state.landing)/0.35
    elseif speed > 0.15 then
        -- Distance, not correction error, advances gait. Vertical motion never
        -- promotes walking to sprint. Each actor owns its independent phase.
        state.phase = speed > 3.5 and 2 or 1
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
    state.speed, state.vertical = speed, vertical
    state.previous = {x=pose.x,y=pose.y,z=pose.z,time=now}
    return state.phase, state.progress
end
function M.apply(actor, state)
    -- Queue admission is not an animation receipt. Live video must verify the
    -- actual selected pose and the next-frame world/root readback separately.
    for _, input in ipairs({{"cp_coop_loco_progress",state.progress},
                           {"cp_coop_loco_phase",state.phase}}) do
        local event = assert(NewObject("entAnimInputSetterFloat"), "animation input unavailable")
        event.key, event.value = CName.new(input[1]), input[2]
        actor:QueueEvent(event)
    end
end
return M
