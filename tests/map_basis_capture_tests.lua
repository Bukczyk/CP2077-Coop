local root = assert(arg[1], "repository root required")
local M = dofile(root .. "/experiments/player-presentation/map_basis_capture.lua")
local checks = 0
local function check(value, label)
    checks = checks + 1
    assert(value, label)
end
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
local function transform(p, a, b, c, d, x, y)
    return { x = a * p.x + b * p.y + x, y = c * p.x + d * p.y + y }
end
local function fixture(surface, matrix)
    surface = surface or "minimap"
    matrix = matrix or { 2, 1, -0.5, 3 }
    local e = { probe = "probe", owner = "owner", distance = 5, points = {} }
    local r = { surface = surface, container = surface .. "container", viewRoot = surface .. "view",
        blockedContainer = surface == "minimap" and "clamped" or nil,
        controller = "target-controller", root = "target-root", data = "target-data",
        id = "99", poseRevision = 6, generation = 7 }
    local s = { probe = e.probe, owner = e.owner, token = 1, surface = surface,
        container = r.container, blockedContainer = r.blockedContainer, viewRoot = r.viewRoot,
        targetData = r.data, poseRevision = r.poseRevision, distance = e.distance,
        complete = true, layoutVerified = false, onscreenVerified = false,
        projectionAnchorVerified = false, facingQualified = false, before = {}, after = {} }
    for i, offsets in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
        e.points[i] = { data = "probe-data" .. i, id = "1844674407370955100" .. i,
            position = { x = 100 + offsets[1] * 5, y = -20 + offsets[2] * 5, z = 10 } }
    end
    for i = 1, 5 do
        local p = e.points[i - 1]
        local x = p and p.position.x - 100 or 0
        local y = p and p.position.y + 20 or 0
        local row = { controller = i == 1 and r.controller or "probe-controller" .. i,
            root = i == 1 and r.root or "probe-root" .. i,
            data = i == 1 and r.data or p.data, mappin = "mappin" .. i,
            id = i == 1 and r.id or p.id, world = p and copy(p.position) or { x = 90, y = -21, z = 10 },
            update = 7, eligible = true, ancestryValid = true,
            size = { x = 20, y = 30 }, anchorPoint = { x = 0.5, y = 0.5 },
            pivotPoint = { x = 0.25, y = 0.25 }, localPoints = { { x = 0, y = 0 },
                { x = 10, y = 15 }, { x = 5, y = 7.5 }, { x = 1, y = 0 }, { x = 0, y = 1 } },
            globalPoints = {}, parentPoints = {}, roundtripPoints = {} }
        row.ancestry = { row.root, "intermediate" .. i, s.container, s.viewRoot }
        local offset = transform({ x = x, y = y }, matrix[1], matrix[2], matrix[3], matrix[4], 0, 0)
        for j, localPoint in ipairs(row.localPoints) do
            -- Rotated/sheared/scaled ancestor changes screen coordinates. The
            -- native inverse returns exact destination-local coordinates.
            local parentPoint = { x = localPoint.x + offset.x, y = localPoint.y + offset.y }
            row.parentPoints[j] = parentPoint
            row.globalPoints[j] = transform(parentPoint, 0, -2, 3, 0.25, 1000, 500)
            row.roundtripPoints[j] = copy(localPoint)
        end
        s.before[i] = row
    end
    s.after = copy(s.before)
    return e, s, r
end
local function analyze(change, surface)
    local e, s, r = fixture(surface)
    if change then change(e, s, r) end
    local tracker, err = M.new(e)
    if not tracker then return { provenanceValid = false, reason = err } end
    return tracker:analyze(s, r)
end
for _, surface in ipairs({ "minimap", "fullmap" }) do
    local report = analyze(nil, surface)
    check(report.provenanceValid, surface .. " native measurement provenance")
    for _, name in ipairs({ "origin", "anchor_size", "pivot_size" }) do
        local c = report.candidates[name]
        check(c.geometryValid and c.residual == 0, surface .. " affine residual " .. name)
        check(c.basis.xx == 2 and c.basis.xy == -0.5 and c.basis.yx == 1 and c.basis.yy == 3,
            surface .. " destination basis preserves world axes " .. name)
    end
    check(report.layoutVerified == false and report.onscreenVerified == false
        and report.projectionAnchorVerified == false and report.facingQualified == false,
        "synthetic geometry cannot qualify facing")
end
for _, matrix in ipairs({ { 0, -2, 3, 0 }, { -1, 0, 0, 1 }, { 0.25, 2, -3, 0.5 } }) do
    local e, s, r = fixture("fullmap", matrix)
    local report = assert(M.new(e)):analyze(s, r)
    check(report.candidates.origin.geometryValid, "rotated/reflected/sheared map candidate")
    local b = report.candidates.origin.basis
    check(b.xx == matrix[1] and b.yx == matrix[2] and b.xy == matrix[3] and b.yy == matrix[4],
        "no assumed camera-yaw sign")
end
local bad = {
    function(e) e.points[2].id = e.points[1].id end,
    function(e) e.points[2].data = e.points[1].data end,
    function(e) e.points[2].id = "0" end,
    function(e) e.points[2].id = "0ULL" end,
    function(e) e.points[2].id = "18446744073709551616" end,
    function(e) e.points[4].position.z = 11 end,
    function(e) e.points[4].position.x = 107 end,
    function(e) e.distance = 0 end,
    function(e) e.distance = 0/0 end,
    function(e, s) s.owner = "replaced-owner" end,
    function(e, s) s.probe = "different-lifetime" end,
    function(e, s) s.token = 0 end,
    function(e, s) s.token = 4294967295 end,
    function(e, s) s.surface = "fullmap" end,
    function(e, s) s.container = "other-map-container" end,
    function(e, s) s.blockedContainer = nil end,
    function(e, s) s.viewRoot = "replacement-view" end,
    function(e, s) s.complete = false end,
    function(e, s) s.poseRevision = s.poseRevision + 1 end,
    function(e, s) s.targetData = "new-member-data" end,
    function(e, s) s.distance = 6 end,
    function(e, s) s.before[3] = nil end,
    function(e, s) s.before[0] = s.before[1] end,
    function(e, s) s.after[2].world.x = s.after[2].world.x + 1 end,
    function(e, s) s.after[2].root = "new-root" end,
    function(e, s) s.after[2].mappin = "new-mappin" end,
    function(e, s) s.after[2].update = s.after[2].update + 1 end,
    function(e, s) s.after[2].ancestry[2] = "new-parent" end,
    function(e, s) s.after[2].parentPoints[1].x = 50 end,
    function(e, s) s.before[2].eligible = false end,
    function(e, s) s.before[2].ancestryValid = false end,
    function(e, s) s.before[2].ancestry[2] = s.blockedContainer end,
    function(e, s) s.before[2].ancestry[2] = s.before[2].root end,
    function(e, s) s.before[2].ancestry[3] = "foreign-container" end,
    function(e, s) s.before[2].ancestry[4] = "foreign-view" end,
    function(e, s) s.before[2].ancestry[5] = "unbounded-tail" end,
    function(e, s) s.before[2].update = 0 end,
    function(e, s) s.before[2].update = 4294967295 end,
    function(e, s) s.before[2].size.x = 0 end,
    function(e, s) s.before[2].parentPoints[1].x = math.huge end,
    function(e, s) s.before[2].globalPoints[1].x = 0/0 end,
    function(e, s) s.before[2].roundtripPoints[1].x = 0.1 end,
    function(e, s) s.before[2].localPoints[2].x = 99 end,
    function(e, s, r) r.controller = "replaced-target" end,
    function(e, s, r) r.root = "replaced-target-root" end,
    function(e, s, r) r.data = "replaced-target-data" end,
    function(e, s, r) r.id = "reused-player-id" end,
    function(e, s, r) r.generation = 8 end,
}
for i, mutate in ipairs(bad) do check(not analyze(mutate).provenanceValid, "invalid case " .. i) end
for _, field in ipairs({ "layoutVerified", "onscreenVerified", "projectionAnchorVerified", "facingQualified" }) do
    check(not analyze(function(e, s) s[field] = true end).provenanceValid, "no qualification override " .. field)
end
local function both(s, fn)
    fn(s.before)
    s.after = copy(s.before)
end
check(not analyze(function(e, s)
    both(s, function(rows) rows[3].controller = rows[2].controller end)
end).provenanceValid, "duplicate controllers")
check(not analyze(function(e, s)
    both(s, function(rows) rows[3].id = rows[2].id end)
end).provenanceValid, "duplicate IDs")
check(not analyze(function(e, s)
    both(s, function(rows) rows[3].world.x = rows[3].world.x + 1 end)
end).provenanceValid, "coherent but wrong requested world readback")
check(not analyze(function(e, s)
    both(s, function(rows) rows[1].parentPoints[4].x = 2 end)
end).provenanceValid, "wrong destination inverse")
check(not analyze(function(e, s)
    both(s, function(rows) rows[2].parentPoints[5] = copy(rows[2].parentPoints[4]) end)
end).provenanceValid, "singular destination conversion")
check(not analyze(function(e, s)
    both(s, function(rows) rows[2].globalPoints[5] = copy(rows[2].globalPoints[4]) end)
end).provenanceValid, "singular source conversion")
for _, matrix in ipairs({ { 0, 0, 0, 0 }, { 1, 2, 1, 2 }, { 1e-6, 0, 0, 1e-6 } }) do
    local e, s, r = fixture("minimap", matrix)
    local report = assert(M.new(e)):analyze(s, r)
    check(report.provenanceValid and not report.candidates.origin.geometryValid,
        "raw provenance does not bless degenerate world basis")
end
local report = analyze(function(e, s)
    both(s, function(rows)
        for _, p in ipairs(rows[5].parentPoints) do p.x = p.x + 5 end
    end)
end)
check(report.provenanceValid and not report.candidates.origin.geometryValid
    and report.candidates.origin.residual == 5, "non-affine diagonal residual rejected")
report = analyze(function(e, s)
    both(s, function(rows) rows[5].parentPoints[2].x = rows[5].parentPoints[2].x + 5 end)
end)
check(report.candidates.origin.geometryValid and not report.candidates.anchor_size.geometryValid
    and report.candidates.pivot_size.geometryValid, "landmarks independently reported, not chosen")
do
    local e, s, r = fixture()
    local tracker = assert(M.new(e))
    check(tracker:analyze(s, r).provenanceValid, "first capture")
    check(not tracker:analyze(s, r).provenanceValid, "same token replay")
    s.token = 2; s.complete = false
    check(not tracker:analyze(s, r).provenanceValid, "incomplete capture")
    s.complete = true
    check(not tracker:analyze(s, r).provenanceValid, "repair cannot reuse rejected token")
    s.token = 3
    check(tracker:analyze(s, r).provenanceValid, "unchanged roots are raw observations, never layout freshness")
    e.points[1].position.x = 666
    s.token = 4
    check(tracker:analyze(s, r).provenanceValid, "expectation copied at bind")
end

-- Run the real CET adapter against native-shaped objects. The transform
-- oracle above is synthetic; this checks actual field/call interoperability.
local function native_fixture(surface)
    local e, s, r = fixture(surface)
    local function native_vec(v) return { X = v.x, Y = v.y, Z = v.z } end
    local function native_row(row)
        local out = copy(row)
        out.id = { value = row.id }
        out.world, out.size = native_vec(row.world), native_vec(row.size)
        out.anchorPoint, out.pivotPoint = native_vec(row.anchorPoint), native_vec(row.pivotPoint)
        for _, f in ipairs({ "localPoints", "globalPoints", "parentPoints", "roundtripPoints" }) do
            out[f] = {}
            for i, v in ipairs(row[f]) do out[f][i] = native_vec(v) end
        end
        return out
    end
    local probe = { active = true, owner = e.owner, distance = e.distance, points = {} }
    for i, p in ipairs(e.points) do
        probe.points[i] = { id = { value = p.id }, position = native_vec(p.position) }
    end
    local data = { poseRevision = r.poseRevision }
    local target = { GetMappin = function() return {
        GetScriptData = function() return data end, GetNewMappinID = function() return { value = r.id } end } end,
        GetRootWidget = function() return r.root end,
        CP2077Session_GetFacingPreviewGeneration = function() return r.generation end }
    local view = { GetRootWidget = function() return r.viewRoot end,
        CP2077MapBasis_UnclampedContainer = function() return r.container end,
        CP2077MapBasis_ClampedContainer = function() return r.blockedContainer end,
        CP2077MapBasis_SpawnContainer = function() return r.container end }
    local native = copy(s)
    native.probe, native.targetData = probe, data
    for _, pass in ipairs({ "before", "after" }) do
        for i, row in ipairs(s[pass]) do
            native[pass][i] = native_row(row)
            native[pass][i].data = i == 1 and data or probe.points[i - 1]
            native[pass][i].controller = i == 1 and target or row.controller
        end
    end
    probe.CaptureMinimap = function() check(surface ~= "fullmap", "fullmap never calls minimap"); return native end
    probe.CaptureFullmap = function() check(surface == "fullmap", "minimap never calls fullmap"); return native end
    return probe, target, view, native
end
for _, surface in ipairs({ "minimap", "fullmap" }) do
    local probe, target, view, native = native_fixture(surface)
    local tracker = assert(M.bind(probe))
    local report, raw = tracker:capture(surface, target, view)
    check(report.provenanceValid and raw.before[2].id == "18446744073709551001", "native-shaped capture and exact large IDs")
    check(report.facingQualified == false, "real adapter does not preview or qualify")
    check(not tracker:capture(surface, target, view).provenanceValid, "real adapter replay")
    native.token = 2; native.after[3].controller = "replacement-controller"
    check(not tracker:capture(surface, target, view).provenanceValid, "native-shaped controller change")
    view.GetRootWidget = function() error("unavailable") end
    check(tracker:capture(surface, target, view).reason == "native_read_failed", "native exception closed")
end
do
    local probe = native_fixture("minimap")
    probe.active = false
    check(M.bind(probe) == nil, "partial/inactive registration cannot bind")
    probe.active = true; probe.points[4] = nil
    check(M.bind(probe) == nil, "partial probe cannot bind")
end
if type(jit) == "table" then
    local ffi = require("ffi")
    local probe, target, view, native = native_fixture("minimap")
    for i = 1, 4 do
        -- Adjacent values above 2^53 must not collapse through a Lua number.
        local value = ffi.new("uint64_t", 9007199254740992) + i
        probe.points[i].id.value = value
        native.before[i + 1].id.value, native.after[i + 1].id.value = value, value
    end
    local tracker = assert(M.bind(probe))
    check(tracker:capture("minimap", target, view).provenanceValid, "real LuaJIT Uint64 IDs remain distinct")
    probe.points[1].id.value = ffi.new("uint64_t", 0)
    check(M.bind(probe) == nil, "zero Uint64 cdata cannot bind")
end
print("map basis capture: " .. checks .. " checks passed")
