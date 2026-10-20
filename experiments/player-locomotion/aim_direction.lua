-- PRIVATE read-only aim investigation. No wire fields or actor operations.
-- Camera direction is not proof that the active camera belongs to the player.
local M={}
local atan2=math.atan2 or function(y,x)return math.atan(y,x)end -- CET LuaJIT / test Lua5.4
local function finite(v)return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function vector(value)
    local ok,x,y,z=pcall(function()return value.x,value.y,value.z end)
    if not ok or not finite(x) or not finite(y) or not finite(z) then return end
    local n=math.sqrt(x*x+y*y+z*z)
    if not finite(n) or n<0.5 or n>1.5 then return end
    return x/n,y/n,z/n
end
function M.fromVectors(camera,body)
    local cx,cy,cz=vector(camera);local bx,by=vector(body)
    if not cx or not bx or cx*cx+cy*cy<0.000001 or bx*bx+by*by<0.000001 then return end
    -- Cyberpunk +Y is forward, +Z up; positive yaw rotates forward toward -X.
    local cameraYaw=atan2(-cx,cy);local bodyYaw=atan2(-bx,by)
    local yaw=((cameraYaw-bodyYaw)*180/math.pi+180)%360-180
    local pitch=math.asin(math.max(-1,math.min(1,cz)))*180/math.pi
    return {yawDegrees=yaw,pitchDegrees=pitch,cameraX=cx,cameraY=cy,cameraZ=cz,
        bodyX=bx,bodyY=by,scope="read-only camera/body angles; camera ownership not qualified"}
end
return M
