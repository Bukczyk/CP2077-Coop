-- Experimental CPEX1 diagnostic body proposal, NOT a production combat schema.
-- PR11 owns the envelope and delivery. All u64 identities stay decimal strings.
local M = {kind = 32513, maxBody = 1024}
local MAX_U64 = "18446744073709551615"

function M.id(value, zero)
    return type(value) == "string" and ((zero and value == "0")
        or (value:match("^[1-9]%d*$") ~= nil and #value <= 20
            and (#value < 20 or value <= MAX_U64)))
end
function M.integer(value, limit)
    return type(value) == "number" and value == value and value >= 1
        and value <= limit and value == math.floor(value)
end
function M.finite(value, bound)
    return type(value) == "number" and value == value and value >= -bound and value <= bound
end
function M.hex(value)
    if type(value) ~= "string" or #value > M.maxBody then return nil end
    return (value:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end
function M.unhex(value)
    if type(value) ~= "string" or #value > M.maxBody * 2 or #value % 2 ~= 0
        or value:find("[^%x]") then return nil end
    return (value:gsub("..", function(c) return string.char(tonumber(c, 16)) end))
end
local function split(value, count)
    if type(value) ~= "string" or #value > M.maxBody or value:find("[^%w|%.%+%-]") then return nil end
    local result = {}
    for part in (value .. "|"):gmatch("([^|]*)|") do result[#result + 1] = part end
    if #result ~= count then return nil end
    return result
end
local function number(value, bound)
    if type(value) ~= "string" or #value > 32
        or not value:match("^[%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*$") then return nil end
    local parsed = tonumber(value)
    if not M.finite(parsed, bound) then return nil end
    return parsed
end
local function geometry(value)
    if type(value) ~= "table" then return false end
    for _, axis in ipairs({"x", "y", "z"}) do
        if not M.finite(value.origin and value.origin[axis], 1000000)
            or not M.finite(value.direction and value.direction[axis], 2) then return false end
    end
    local d = value.direction
    local length = d.x*d.x + d.y*d.y + d.z*d.z
    return length >= 0.01 and length <= 4
end
function M.intent(value)
    if type(value) ~= "table" or not M.id(value.target)
        or not M.integer(value.shot, 4294967295) or not geometry(value) then return nil end
    local p, d = value.origin, value.direction
    return M.hex(string.format("CPEX1I|%s|%.0f|%.9g|%.9g|%.9g|%.9g|%.9g|%.9g",
        value.target, value.shot, p.x, p.y, p.z, d.x, d.y, d.z))
end
function M.readIntent(value)
    local p = split(M.unhex(value), 9)
    if not p or p[1] ~= "CPEX1I" or not M.id(p[2]) or not p[3]:match("^[1-9]%d*$") then return nil end
    local result = {target=p[2], shot=tonumber(p[3]), origin={}, direction={}}
    if not M.integer(result.shot, 4294967295) then return nil end
    for i, axis in ipairs({"x", "y", "z"}) do
        result.origin[axis] = number(p[3+i], 1000000)
        result.direction[axis] = number(p[6+i], 2)
    end
    return geometry(result) and result or nil
end
function M.result(value)
    if type(value) ~= "table" or not M.id(value.target)
        or not M.finite(value.health, 100000000) or value.health < 0
        or not M.finite(value.maximum, 100000000) or value.maximum <= 0
        or value.health > value.maximum
        or (value.life ~= "alive" and value.life ~= "defeated" and value.life ~= "dead")
        or (value.life == "dead" and value.health ~= 0) then return nil end
    return M.hex(string.format("CPEX1R|%s|%.9g|%.9g|%s", value.target, value.health, value.maximum, value.life))
end
function M.readResult(value)
    local p = split(M.unhex(value), 5)
    if not p or p[1] ~= "CPEX1R" then return nil end
    local result = {target=p[2], health=number(p[3],100000000), maximum=number(p[4],100000000), life=p[5]}
    return M.result(result) and result or nil
end
return M
