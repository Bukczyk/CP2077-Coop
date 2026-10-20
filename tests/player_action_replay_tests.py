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
for origin in ('nan,1,2,3','0,inf,2,3','0,1,2,1001','1000001,1,2,0','0,1,2,0,5','0,1,2','0,1,2,0trailing'):
    bad=run('--validate-only','--origin',origin)
    assert bad.returncode!=0 and 'HELLO' not in bad.stdout,(origin,bad.stdout)
for args in (('--server','example.org'),('--origin',),('--session',''),('--session','x'*65),('--session','a\nb')):
    bad=run('--validate-only',*args)
    assert bad.returncode!=0 and 'HELLO' not in bad.stdout,args
print('Experimental action fixture: bounded CLI and offline preflight passed')
assert subprocess.run([exe,'--validate-only'],capture_output=True,timeout=5).returncode!=0
