local root=assert(arg[1]);local M=assert(loadfile(root.."/experiments/player-locomotion/aim_direction.lua"))()
local function vector(yaw,pitch)
    yaw,pitch=yaw*math.pi/180,(pitch or 0)*math.pi/180
    return {x=-math.sin(yaw)*math.cos(pitch),y=math.cos(yaw)*math.cos(pitch),z=math.sin(pitch)}
end
local function near(a,b)assert(math.abs(a-b)<0.000001,tostring(a).." != "..tostring(b))end
local function test(cameraYaw,pitch,bodyYaw,expectedYaw)
    local v=assert(M.fromVectors(vector(cameraYaw,pitch),vector(bodyYaw)))
    near(v.yawDegrees,expectedYaw);near(v.pitchDegrees,pitch)
end
test(0,0,0,0);test(30,45,0,30);test(-70,-60,10,-80)
test(179,0,-179,-2);test(-179,0,179,2);test(18.43494882,0,18.43494882,0)
for _,bad in ipairs({{x=0,y=0,z=0},{x=0,y=0,z=1},{x=0,y=100,z=0},{x=0/0,y=1,z=0},{x=math.huge,y=1,z=0},{x="0",y=1,z=0},{}})do
    assert(M.fromVectors(bad,vector(0))==nil)
    assert(M.fromVectors(vector(0),bad)==nil)
end
assert(M.fromVectors(nil,vector(0))==nil)
assert(M.fromVectors(vector(0),nil)==nil)
local scaled=vector(30,20);scaled.x,scaled.y,scaled.z=scaled.x*.9,scaled.y*.9,scaled.z*.9
local result=assert(M.fromVectors(scaled,vector(0)));near(result.yawDegrees,30);near(result.pitchDegrees,20)
print('Aim direction: axes, pitch, wraparound, normalization and unavailable/nonfinite rejection passed')
