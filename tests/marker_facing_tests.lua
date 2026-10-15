local root = assert(arg[1], "repository root required")
local facing = dofile(root .. "/experiments/player-presentation/marker_facing.lua")
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local function near(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        (message or "angle") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local north_up = { xx = 1, xy = 0, yx = 0, yy = -1 }
for _, case in ipairs({ {0,1,0}, {1,0,90}, {0,-1,180}, {-1,0,-90} }) do
    near(facing.angle_from_forward(case[1], case[2], north_up, 1, 0), case[3], "cardinal vector")
end
local measured = facing.basis_from_points({x=50,y=80}, {x=70,y=80}, {x=50,y=60}, 10)
near(measured.xx, 2); near(measured.yy, -2)
near(facing.angle_from_forward(0.6, 0.8, measured, 1, 0), math.deg(math.atan(0.75)))
check(facing.basis_from_points(nil, {}, {}, 1) == nil, "missing points")
check(facing.basis_from_points({}, {}, {}, 0) == nil, "zero sampling distance")
check(facing.basis_from_points({x=0,y=0}, {x=1,y=1}, {x=2,y=2}, 1) == nil, "collinear probes")

-- This SYNTHETIC converter is a declared reference convention, not evidence
-- of native Euler handedness. The adapter must delegate the conversion.
local requested_degrees
local function synthetic_forward(degrees)
    requested_degrees = degrees
    return -math.sin(math.rad(degrees)), math.cos(math.rad(degrees))
end
near(facing.angle_from_yaw(math.pi / 2, north_up, 1, 0, synthetic_forward), -90)
near(requested_degrees, 90, "radians converted once")
near(facing.angle_from_yaw(math.pi * 2, north_up, 1, 0, synthetic_forward), 0)
near(facing.angle_from_yaw(-math.pi * 2, north_up, 1, 0, synthetic_forward), 0)
check(facing.angle_from_yaw(0, north_up, 1, 0) == nil, "no implicit native convention")
check(facing.angle_from_yaw(7, north_up, 1, 0, synthetic_forward) == nil, "protocol yaw bound")
check(facing.angle_from_yaw(0, north_up, 1, 0, function() error("native missing") end) == nil)

-- View rotation and zoom act on the projected vector, not body yaw or
-- velocity. Translating all samples cancels; arbitrary uniform zoom cancels.
for _, body in ipairs({ -2.9, -1.2, 0, 0.7, 2.9 }) do
    local fx, fy = math.sin(body), math.cos(body)
    for _, view in ipairs({ -170, -90, 0, 45, 123 }) do
        local c, s = math.cos(math.rad(view)), math.sin(math.rad(view))
        for _, zoom in ipairs({ 0.01, 1, 100 }) do
            local basis = { xx=zoom*c, xy=zoom*s, yx=zoom*s, yy=-zoom*c }
            local angle = facing.angle_from_forward(fx, fy, basis, 1, 0)
            -- Compare unit directions across the +/-180 representation seam.
            near(math.sin(math.rad(angle)), math.sin(body + math.rad(view)), "rotating view X")
            near(-math.cos(math.rad(angle)), -math.cos(body + math.rad(view)), "rotating view Y")
        end
    end
end
near(facing.angle_from_forward(0.6, 0.8, {xx=2,xy=0,yx=0,yy=-1}, 1, 0), math.deg(math.atan(1.5)), "anisotropic scale")
near(facing.angle_from_forward(0.6, 0.8, north_up, -1, 15), 15-math.deg(math.atan(0.75)), "calibrated widget convention")
near(facing.angle_from_forward(1, 0, {xx=-1,xy=0,yx=0,yy=-1}, 1, 0), -90, "reflection")
for _, invalid in ipairs({ {}, {xx=0,xy=0,yx=0,yy=1}, {xx=1,xy=0,yx=1,yy=0.00001},
    {xx=math.huge,xy=0,yx=0,yy=1}, {xx=0/0,xy=0,yx=0,yy=1} }) do
    check(not facing.valid_basis(invalid), "reject degenerate/nonfinite basis")
end
check(facing.angle_from_forward(0,0,north_up,1,0) == nil)
check(facing.angle_from_forward(0,1,north_up,0,0) == nil)
check(facing.angle_from_forward(0,1,north_up,1,math.huge) == nil)

local data = {}
local mini_root, map_root = {}, {}
local received, clears = nil, 0
local minimap = {
    CP2077Session_ClearFacingPreview = function() clears = clears + 1 end,
    CP2077Session_PreviewFacingBasis = function(_, ...) received = {...}; return true end,
}
local sample = { expected_root=mini_root, expected_data=data, pose_revision=4, generation=12, basis=north_up, rotation_sign=1, zero_degrees=0 }
check(not facing.preview(minimap, sample), "default disabled")
check(received == nil and clears == 1, "disabled removes prior preview only")
sample.enabled = true
check(facing.preview(minimap, sample))
check(received[1] == mini_root and received[2] == data and received[3] == 4 and received[4] == 12, "exact root, ownership, pose revision and generation forwarded")
check(received[5] == 1 and received[6] == 0 and received[7] == 0 and received[8] == -1, "matrix order matches native")
check(received[9] == 1 and received[10] == 0, "calibration forwarded")
local map_received
local full_map = {
    CP2077Session_PreviewFacingBasis = function(_, ...) map_received={...}; return true end,
    CP2077Session_ClearFacingPreview = function() end,
}
local map_sample = { enabled=true, expected_root=map_root, expected_data=data, pose_revision=4, generation=99,
    basis={xx=0,xy=2,yx=2,yy=0}, rotation_sign=-1, zero_degrees=15 }
check(facing.preview(full_map, map_sample))
check(map_received[1] == map_root and map_received[4] == 99 and map_received[6] == 2
    and received[1] == mini_root and received[4] == 12, "surfaces independent; no cached basis")
minimap.CP2077Session_PreviewFacingBasis = function() return false end
check(not facing.preview(minimap, sample), "native stale/replay rejection propagated")
check(clears == 2, "rejected sample cleared")
minimap.CP2077Session_PreviewFacingBasis = function() error("expired controller") end
check(not facing.preview(minimap, sample), "native exception contained")
sample.generation = 4294967295
check(not facing.preview(minimap, sample), "saturated generation rejected")
sample.generation = 0
check(not facing.preview(minimap, sample), "uninitialized generation rejected")
check(not facing.preview(nil, sample), "destroyed controller contained")
print("marker_facing: " .. checks .. " checks passed")
