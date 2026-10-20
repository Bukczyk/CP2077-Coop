"""Reject invalid fixture inputs before credentials or network activity."""
import subprocess,sys
exe=sys.argv[1]
def run(*args):return subprocess.run([exe,'--session','fixture',*args],capture_output=True,text=True,timeout=5)
result=run('--validate-only','--key-file','does-not-exist')
assert result.returncode==0,(result.stdout,result.stderr)
assert 'protocol=32773' in result.stdout and 'loopback_only=true' in result.stdout
assert 'HELLO' not in result.stdout
assert result.stdout.count('PHASE ')==15
assert 'start=42 until=48 name=action_gap_movement_continues tick_gap=1' in result.stdout
assert 'start=78 until=86 name=reconnected_crouch_aim tick_gap=0' in result.stdout
assert 'start=86 until=92 name=crouch_walk_unarmed tick_gap=0' in result.stdout
direction=run('--validate-only','--directions','--origin','-813,821.5,24.4042,0')
assert direction.returncode==0 and 'HELLO' not in direction.stdout
assert direction.stdout.count('PHASE ')==15 and 'duration=92' in direction.stdout
for name in ['armed_walk_forward','armed_walk_right_aim','armed_walk_backward_aim','armed_walk_left']:
    assert 'name='+name+' ' in direction.stdout
gaits=run('--validate-only','--gaits','--origin','0,0,0,0')
assert gaits.returncode==0 and 'HELLO' not in gaits.stdout and gaits.stdout.count('PHASE ')==15
for name in ['gait_walk_forward','gait_walk_stop','gait_sprint_then_stop','gait_walk_again','gait_second_stop']:
    assert 'name='+name+' ' in gaits.stdout
for t,y in [(6,0),(12,6),(18,6),(18.5,3),(19,0),(24,0),(30,6),(35,6)]:
    assert f'GAIT_POINT t={t} x=0 y={y} ' in gaits.stdout
assert run('--validate-only','--gaits','--directions').returncode!=0
crouches=run('--validate-only','--crouch-directions','--origin','0,0,0,0')
assert crouches.returncode==0 and 'HELLO' not in crouches.stdout and crouches.stdout.count('PHASE ')==15
for name in ['crouch_unarmed_idle','crouch_armed_forward','crouch_armed_stop','crouch_aim_backward','crouch_unarmed_stop','crouch_unarmed_out_and_back']:
    assert 'name='+name+' ' in crouches.stdout
for t,y in [(6,0),(12,3),(18,3),(21,1.5),(24,0),(30,0),(35,.5)]:
    assert f'CROUCH_POINT t={t} x=0 y={y} yaw=0' in crouches.stdout
for flag in ('--directions','--gaits'):
    assert run('--validate-only','--crouch-directions',flag).returncode!=0
for origin in ('nan,1,2,3','0,inf,2,3','0,1,2,1001','1000001,1,2,0','0,1,2,0,5','0,1,2','0,1,2,0trailing'):
    bad=run('--validate-only','--origin',origin)
    assert bad.returncode!=0 and 'HELLO' not in bad.stdout,(origin,bad.stdout)
for args in (('--server','example.org'),('--origin',),('--session',''),('--session','x'*65),('--session','a\nb')):
    bad=run('--validate-only',*args)
    assert bad.returncode!=0 and 'HELLO' not in bad.stdout,args
print('Experimental action fixture: bounded CLI and offline preflight passed')
assert subprocess.run([exe,'--validate-only'],capture_output=True,timeout=5).returncode!=0
