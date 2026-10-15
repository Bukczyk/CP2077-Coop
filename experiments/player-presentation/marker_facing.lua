-- Developer calibration fixture. Never loaded by the session entrypoint.
-- Basis columns are world +X/+Y projected into the exact arrow parent's local
-- coordinates. This module discovers neither the view nor the basis for you.
local M = {}

local function bounded(value, limit)
    return type(value) == "number" and value >= -limit and value <= limit
end

function M.valid_basis(basis)
    if type(basis) ~= "table" then return false end
    for _, name in ipairs({ "xx", "xy", "yx", "yy" }) do
        if not bounded(basis[name], 10000) then return false end
    end
    local x_length = basis.xx ^ 2 + basis.xy ^ 2
    local y_length = basis.yx ^ 2 + basis.yy ^ 2
    local determinant = basis.xx * basis.yy - basis.yx * basis.xy
    return x_length >= 1e-8 and y_length >= 1e-8
        and determinant ^ 2 >= 1e-6 * x_length * y_length
end

-- Three synchronized, unclamped points in the SAME parent's coordinates.
-- x_point/y_point correspond to origin_world + (distance,0)/(0,distance).
-- Screen pixels are insufficient when ancestors rotate/scale the parent.
function M.basis_from_points(origin, x_point, y_point, distance)
    if not bounded(distance, 1000000) or distance <= 0 then return nil end
    if not origin or not x_point or not y_point then return nil end
    for _, point in ipairs({ origin, x_point, y_point }) do
        if type(point) ~= "table" or not bounded(point.x, 1e9)
            or not bounded(point.y, 1e9) then return nil end
    end
    local basis = {
        xx = (x_point.x - origin.x) / distance,
        xy = (x_point.y - origin.y) / distance,
        yx = (y_point.x - origin.x) / distance,
        yy = (y_point.y - origin.y) / distance,
    }
    return M.valid_basis(basis) and basis or nil
end

local function calibration_valid(sign, zero)
    return (sign == 1 or sign == -1) and bounded(zero, 180)
end

-- Portable across the test Lua 5.4 and CET LuaJIT: do not rely on a second
-- math.atan argument which Lua 5.1 can silently ignore.
local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

function M.angle_from_forward(fx, fy, basis, sign, zero)
    if not M.valid_basis(basis) or not calibration_valid(sign, zero)
        or not bounded(fx, 1) or not bounded(fy, 1)
        or fx * fx + fy * fy < 1e-8 then return nil end
    local dx = basis.xx * fx + basis.yx * fy
    local dy = basis.xy * fx + basis.yy * fy
    -- Matches the REDscript formula, with zero pointing up in parent space.
    return sign * math.deg(atan2(dx, -dy)) + zero
end

-- The caller supplies the engine yaw-to-forward conversion. There is no
-- guessed native handedness here. REDscript uses Quaternion.GetForward after
-- EulerAngles.ToQuat with Rad2Deg(yawRadians).
function M.angle_from_yaw(yaw, basis, sign, zero, engine_forward)
    if not bounded(yaw, 6.283186) or type(engine_forward) ~= "function" then return nil end
    local ok, fx, fy = pcall(engine_forward, math.deg(yaw))
    if not ok then return nil end
    return M.angle_from_forward(fx, fy, basis, sign, zero)
end

function M.clear(controller)
    return pcall(function() controller:CP2077Session_ClearFacingPreview() end)
end

-- Every invocation requires an explicit opt-in and a fresh complete sample.
-- expected_root and expected_data are the exact native references captured
-- from this controller; pose_revision and generation are captured before
-- measuring the basis. Native code validates all four again before drawing.
-- No controller, basis, generation, pose or authorization is retained here.
function M.preview(controller, sample)
    if type(sample) ~= "table" or sample.enabled ~= true
        or sample.expected_root == nil or sample.expected_data == nil
        or not bounded(sample.pose_revision, 4294967294) or sample.pose_revision < 1
        or sample.pose_revision % 1 ~= 0
        or not bounded(sample.generation, 4294967294) or sample.generation < 1
        or sample.generation % 1 ~= 0 or not M.valid_basis(sample.basis)
        or not calibration_valid(sample.rotation_sign, sample.zero_degrees) then
        M.clear(controller)
        return false
    end
    local b = sample.basis
    local ok, accepted = pcall(function()
        return controller:CP2077Session_PreviewFacingBasis(sample.expected_root, sample.expected_data,
            sample.pose_revision, sample.generation, b.xx, b.xy, b.yx, b.yy,
            sample.rotation_sign, sample.zero_degrees)
    end)
    if not ok or accepted ~= true then
        M.clear(controller)
        return false
    end
    return true -- Request accepted, not evidence of correct rendered facing.
end

return M
