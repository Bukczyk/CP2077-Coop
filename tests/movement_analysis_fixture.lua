local root=assert(arg[1])
package.path=root..'/runtime/session/diagnostics/CP2077MovementDiagnostics/?.lua;'..package.path
local Recorder=require('recorder')
local r=Recorder.new(print)
print('[CP2077Movement] START schema=1 rate_hz=5 target_yaw=radians actual_yaw=degrees')
local commands=4
local function capture()
    return {session='9007199254740993ULL',generation='1ULL',self=3,host=2,
        ready=true,paused=false,retiring=0,players={['2']={actor='9007199254740995ULL',
        x=10,y=20,z=30,actualX=9,actualY=18,actualZ=28,readback='available',
        commands=commands,snaps=2,observedSnaps=1,turns=0}}}
end
r:step(.2,capture)
commands=5
r:step(.2,capture)
