-- Capture-only experiment. No runtime import, drawing, scheduling or preview.
local M = {}
local Tracker = {}
Tracker.__index = Tracker
local names = { "origin", "anchor_size", "pivot_size" }
local function id64(value)
    -- CET uses uint64 cdata. Decimal strings are also useful for offline
    -- records. Reject lossy/exponential numeric representations and zero.
    if type(value) == "number" and (value < 1 or value > 9007199254740991 or value % 1 ~= 0) then return nil end
    local text = tostring(value):gsub("ULL$", "")
    if not text:match("^%d+$") then return nil end
    text = text:gsub("^0+", "")
    if text == "" or #text > 20 or (#text == 20 and text > "18446744073709551615") then return nil end
    return text
end

local function finite(n, limit)
    return type(n) == "number" and n >= -limit and n <= limit
end
local function uint(n)
    return finite(n, 4294967294) and n >= 1 and n % 1 == 0
end
local function point(p)
    return type(p) == "table" and finite(p.x, 1e9) and finite(p.y, 1e9)
end
local function near(a, b, tolerance)
    return point(a) and point(b) and math.abs(a.x - b.x) <= tolerance
        and math.abs(a.y - b.y) <= tolerance
end
local function world(a, b)
    return near(a, b, 0.001) and finite(a.z, 1e6) and finite(b.z, 1e6)
        and math.abs(a.z - b.z) <= 0.001
end
local function array(t, count)
    if type(t) ~= "table" or #t ~= count then return false end
    for k in pairs(t) do
        if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > count then return false end
    end
    for i = 1, count do if t[i] == nil then return false end end
    return true
end
local function basis(o, x, y, d)
    if not point(o) or not point(x) or not point(y) then return nil end
    local b = { xx = (x.x - o.x) / d, xy = (x.y - o.y) / d,
        yx = (y.x - o.x) / d, yy = (y.y - o.y) / d }
    local xl, yl = b.xx ^ 2 + b.xy ^ 2, b.yx ^ 2 + b.yy ^ 2
    local det = b.xx * b.yy - b.xy * b.yx
    if not finite(xl, 1e8) or not finite(yl, 1e8) or xl < 1e-8 or yl < 1e-8
        or det ^ 2 < 1e-6 * xl * yl then return nil end
    return b
end
local function rejected(reason)
    return { provenanceValid = false, reason = reason, candidates = {},
        layoutVerified = false, onscreenVerified = false,
        projectionAnchorVerified = false, facingQualified = false }
end

-- Expected native references/IDs are pinned when this one probe lifetime is
-- bound, never substituted from a later sample. IDs remain exact strings.
function M.new(expected)
    if type(expected) ~= "table" or expected.probe == nil or expected.owner == nil
        or not finite(expected.distance, 100) or expected.distance < 0.1
        or not array(expected.points, 4) then return nil, "invalid_probe" end
    local copy = { probe = expected.probe, owner = expected.owner,
        distance = expected.distance, points = {} }
    local ids, data = {}, {}
    for i, p in ipairs(expected.points) do
        if type(p) ~= "table" or p.data == nil or type(p.id) ~= "string" or id64(p.id) ~= p.id
            or ids[p.id] or data[p.data]
            or not world(p.position, p.position) then return nil, "invalid_probe" end
        ids[p.id], data[p.data] = true, true
        copy.points[i] = { data = p.data, id = p.id,
            position = { x = p.position.x, y = p.position.y, z = p.position.z } }
    end
    local o, d = copy.points[1].position, copy.distance
    for i, offsets in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
        if not world(copy.points[i].position, { x = o.x + offsets[1] * d,
            y = o.y + offsets[2] * d, z = o.z }) then return nil, "probe_geometry" end
    end
    return setmetatable({ expected = copy, lastToken = 0 }, Tracker)
end

local function ancestry(r, s)
    if r.ancestryValid ~= true or type(r.ancestry) ~= "table"
        or #r.ancestry < 2 or #r.ancestry > 64 or not array(r.ancestry, #r.ancestry)
        or r.ancestry[1] ~= r.root or r.ancestry[#r.ancestry] ~= s.viewRoot then return false end
    local seen, found = {}, false
    for _, ref in ipairs(r.ancestry) do
        if ref == s.blockedContainer or seen[ref] then return false end
        seen[ref] = true
        if ref == s.container then found = true end
    end
    return found
end

local function reading(r, s)
    if type(r) ~= "table" or r.controller == nil or r.root == nil or r.data == nil
        or r.mappin == nil or type(r.id) ~= "string" or id64(r.id) ~= r.id
        or not uint(r.update) or r.eligible ~= true or not ancestry(r, s)
        or not world(r.world, r.world) or not point(r.size) or r.size.x <= 0 or r.size.y <= 0
        or not point(r.anchorPoint) or not point(r.pivotPoint) then return false end
    for _, field in ipairs({ "localPoints", "globalPoints", "parentPoints", "roundtripPoints" }) do
        if not array(r[field], 5) then return false end
        for _, p in ipairs(r[field]) do if not point(p) then return false end end
    end
    local expected = { { x = 0, y = 0 },
        { x = r.anchorPoint.x * r.size.x, y = r.anchorPoint.y * r.size.y },
        { x = r.pivotPoint.x * r.size.x, y = r.pivotPoint.y * r.size.y },
        { x = 1, y = 0 }, { x = 0, y = 1 } }
    for i = 1, 5 do
        if not near(r.localPoints[i], expected[i], 0.001)
            or not near(r.roundtripPoints[i], r.localPoints[i], 0.001) then return false end
    end
    -- A valid inverse roundtrip alone could hide a singular destination map.
    return basis(r.globalPoints[1], r.globalPoints[4], r.globalPoints[5], 1) ~= nil
        and basis(r.parentPoints[1], r.parentPoints[4], r.parentPoints[5], 1) ~= nil
end

local function same(a, b)
    for _, k in ipairs({ "controller", "root", "data", "mappin", "id", "update" }) do
        if a[k] ~= b[k] then return false end
    end
    if not world(a.world, b.world) or #a.ancestry ~= #b.ancestry then return false end
    for i = 1, #a.ancestry do if a.ancestry[i] ~= b.ancestry[i] then return false end end
    for _, k in ipairs({ "size", "anchorPoint", "pivotPoint" }) do
        if not near(a[k], b[k], 0.0001) then return false end
    end
    for _, k in ipairs({ "localPoints", "globalPoints", "parentPoints", "roundtripPoints" }) do
        for i = 1, 5 do if not near(a[k][i], b[k][i], 0.0001) then return false end end
    end
    return true
end

function Tracker:analyze(s, request)
    if type(s) ~= "table" or s.probe ~= self.expected.probe or s.owner ~= self.expected.owner
        or not uint(s.token) or s.token <= self.lastToken then return rejected("identity_or_replay") end
    -- Consume even a rejected capture so it cannot be repaired and replayed.
    self.lastToken = s.token
    if type(request) ~= "table" or (request.surface ~= "minimap" and request.surface ~= "fullmap")
        or s.surface ~= request.surface or s.container == nil or s.viewRoot == nil
        or s.container ~= request.container or s.viewRoot ~= request.viewRoot
        or s.blockedContainer ~= request.blockedContainer
        or (s.surface == "minimap" and (s.blockedContainer == nil or s.blockedContainer == s.container))
        or (s.surface == "fullmap" and s.blockedContainer ~= nil)
        or s.complete ~= true or s.targetData ~= request.data
        or not uint(s.poseRevision) or s.poseRevision ~= request.poseRevision
        or s.distance ~= self.expected.distance
        or not array(s.before, 5) or not array(s.after, 5) then return rejected("capture_context") end
    -- A future/native caller cannot silently upgrade this diagnostic's policy.
    if s.layoutVerified ~= false or s.onscreenVerified ~= false
        or s.projectionAnchorVerified ~= false or s.facingQualified ~= false then
        return rejected("unexpected_qualification")
    end
    local roots, ids, controllers = {}, {}, {}
    for i = 1, 5 do
        local a, b = s.before[i], s.after[i]
        if not reading(a, s) or not reading(b, s) then return rejected("reading_invalid") end
        if not same(a, b) then return rejected("capture_changed") end
        if roots[a.root] or ids[a.id] or controllers[a.controller] then return rejected("duplicate_identity") end
        roots[a.root], ids[a.id], controllers[a.controller] = true, true, true
        if i == 1 then
            if a.data ~= request.data or a.root ~= request.root or a.controller ~= request.controller
                or a.id ~= request.id or a.update ~= request.generation then return rejected("target_identity") end
            -- Destination is this exact root. Native conversion of its own
            -- points should be identity, including both independent axes.
            for j = 1, 5 do
                if not near(a.parentPoints[j], a.localPoints[j], 0.001) then return rejected("destination_inverse") end
            end
        else
            local p = self.expected.points[i - 1]
            if a.data ~= p.data or a.id ~= p.id or not world(a.world, p.position) then
                return rejected("probe_identity_or_position")
            end
        end
    end
    local report = rejected("raw_capture_only")
    report.provenanceValid, report.token, report.surface = true, s.token, s.surface
    for landmark, name in ipairs(names) do
        local o, x, y, diagonal = s.before[2].parentPoints[landmark], s.before[3].parentPoints[landmark],
            s.before[4].parentPoints[landmark], s.before[5].parentPoints[landmark]
        local b = basis(o, x, y, s.distance)
        local dx, dy = diagonal.x - x.x - y.x + o.x, diagonal.y - x.y - y.y + o.y
        local residual = math.sqrt(dx * dx + dy * dy)
        local span = math.max(math.sqrt((x.x - o.x) ^ 2 + (x.y - o.y) ^ 2),
            math.sqrt((y.x - o.x) ^ 2 + (y.y - o.y) ^ 2))
        local limit = 0.05 + 0.005 * span
        report.candidates[name] = { basis = b, residual = residual, residualLimit = limit,
            geometryValid = b ~= nil and residual <= limit }
    end
    return report
end

-- CET boundary. Keep native references and Uint64 identity intact; never use
-- tonumber on mappin IDs. All sampling is synchronous on the calling game/UI
-- thread. No polling thread or cached controller registry is created in Lua.
local function vec(v, z)
    local p = { x = v.X, y = v.Y }
    if z then p.z = v.Z end
    return p
end
local function list(values, convert)
    local result = {}
    for i, value in ipairs(values) do result[i] = convert and convert(value) or value end
    return result
end
local function normalize(r)
    return { controller = r.controller, root = r.root, data = r.data, mappin = r.mappin,
        id = id64(r.id.value), world = vec(r.world, true), update = r.update,
        eligible = r.eligible, ancestryValid = r.ancestryValid, ancestry = list(r.ancestry),
        size = vec(r.size), anchorPoint = vec(r.anchorPoint), pivotPoint = vec(r.pivotPoint),
        localPoints = list(r.localPoints, vec), globalPoints = list(r.globalPoints, vec),
        parentPoints = list(r.parentPoints, vec), roundtripPoints = list(r.roundtripPoints, vec) }
end

function M.bind(probe)
    local ok, expected = pcall(function()
        if probe.active ~= true then return nil end
        return { probe = probe, owner = probe.owner, distance = probe.distance,
            points = list(probe.points, function(p)
                return { data = p, id = id64(p.id.value), position = vec(p.position, true) }
            end) }
    end)
    if not ok then return nil, "native_read_failed" end
    return M.new(expected)
end

function Tracker:capture(surface, target, view)
    local ok, sample, request = pcall(function()
        if surface ~= "minimap" and surface ~= "fullmap" then error("surface") end
        local mappin = target:GetMappin()
        local data = mappin:GetScriptData()
        local request = { surface = surface, controller = target, root = target:GetRootWidget(),
            data = data, id = id64(mappin:GetNewMappinID().value), poseRevision = data.poseRevision,
            generation = target:CP2077Session_GetFacingPreviewGeneration(), viewRoot = view:GetRootWidget() }
        local probe = self.expected.probe
        local native
        if surface == "minimap" then
            request.container = view:CP2077MapBasis_UnclampedContainer()
            request.blockedContainer = view:CP2077MapBasis_ClampedContainer()
            native = probe:CaptureMinimap(target, view)
        else
            request.container = view:CP2077MapBasis_SpawnContainer()
            native = probe:CaptureFullmap(target, view)
        end
        if probe.active ~= true then error("inactive") end
        local s = { probe = native.probe, owner = native.owner, token = native.token,
            surface = native.surface, container = native.container, blockedContainer = native.blockedContainer,
            viewRoot = native.viewRoot, targetData = native.targetData, poseRevision = native.poseRevision,
            distance = native.distance, complete = native.complete,
            layoutVerified = native.layoutVerified, onscreenVerified = native.onscreenVerified,
            projectionAnchorVerified = native.projectionAnchorVerified, facingQualified = native.facingQualified,
            before = list(native.before, normalize), after = list(native.after, normalize) }
        return s, request
    end)
    if not ok then return rejected("native_read_failed") end
    local analyzed, report = pcall(self.analyze, self, sample, request)
    if not analyzed then return rejected("native_read_failed") end
    return report, sample -- One bounded raw sample; caller owns any persistence.
end

return M
