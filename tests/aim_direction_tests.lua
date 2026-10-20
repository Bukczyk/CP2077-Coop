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
do
    local f={ok=true,camera=vector(30,20),enabled=true,attached=true,id="9007199254740993ULL"}
    Matrix={IsOk=function()return f.ok end,GetDirectionVector=function()return f.camera end}
    Game={GetCameraSystem=function()error('unrelated scene camera must never be read')end}
    local player
    player={GetWorldForward=function()return vector(10)end,
        IsAttached=function()return f.attached end,
        GetEntityID=function()return {hash=f.id}end,
        GetFPPCameraComponent=function()
            if f.throw then error('camera unavailable')end
            if f.missing then return nil end
            return {GetLocalToWorld=function()return {}end,
                IsEnabled=function()return f.enabled end,
                GetEntity=function()if f.ownerMissing then return nil end;return f.owner or player end}
        end}
    local angles=assert(M.fromPlayer(player));near(angles.yawDegrees,20);near(angles.pitchDegrees,20)
    assert(angles.source=='player_fpp_component')
    f.ok=false;assert(M.fromPlayer(player)==nil);f.ok=nil;assert(M.fromPlayer(player)==nil);f.ok=true
    f.camera=vector(0,90);assert(M.fromPlayer(player)==nil)
    f.camera=vector(30,20);f.missing=true;assert(M.fromPlayer(player)==nil);f.missing=false
    f.throw=true;assert(M.fromPlayer(player)==nil);assert(M.fromPlayer(nil)==nil)
    f.throw=false;f.enabled=false;assert(M.fromPlayer(player)==nil)
    f.enabled=nil;assert(M.fromPlayer(player)==nil);f.enabled=true
    f.attached=false;assert(M.fromPlayer(player)==nil);f.attached=true
    f.ownerMissing=true;assert(M.fromPlayer(player)==nil);f.ownerMissing=false
    f.owner={IsAttached=function()return true end,GetEntityID=function()return {hash="9007199254740992ULL"}end}
    assert(M.fromPlayer(player)==nil,"adjacent IDs above2^53 must remain distinct")
    f.owner=nil
    for _,id in ipairs({0,9007199254740992,"0ULL","invalid",string.rep("9",21)})do
        f.id=id;assert(M.fromPlayer(player)==nil,"unsafe/missing identity cannot admit an own camera")
    end
    f.id="9007199254740993ULL";assert(M.fromPlayer(player))
end
print('Aim direction: axes, pitch, wraparound, normalization and unavailable/nonfinite rejection passed')
