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
unarmed=run('--validate-only','--unarmed-directions','--origin','-813,821.5,24.4042,0')
assert unarmed.returncode==0 and 'HELLO' not in unarmed.stdout and unarmed.stdout.count('PHASE ')==15
for name in ['unarmed_walk_forward','unarmed_walk_right','unarmed_walk_backward','unarmed_walk_left']:
    assert 'name='+name+' ' in unarmed.stdout
for flag in ('--directions','--gaits','--crouch-directions'):
    assert run('--validate-only','--unarmed-directions',flag).returncode!=0
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
sides=run('--validate-only','--crouch-sides','--origin','0,0,0,0')
assert sides.returncode==0 and 'HELLO' not in sides.stdout and sides.stdout.count('PHASE ')==15
for name in ('crouch_side_unarmed_idle','crouch_side_unarmed_right','crouch_side_unarmed_stop','crouch_side_aim_left','crouch_side_aim_stop','crouch_side_armed_out_and_back'):
    assert 'name='+name+' ' in sides.stdout
for t,x in [(6,0),(12,3),(18,3),(21,1.5),(24,0),(30,0),(33,1.5),(35,.5)]:
    assert f'CROUCH_SIDE_POINT t={t} x={x} y=0 yaw=0' in sides.stdout
for flag in ('--directions','--gaits','--unarmed-directions','--crouch-directions'):
    assert run('--validate-only','--crouch-sides',flag).returncode!=0
diagonals=run('--validate-only','--crouch-diagonals','--origin','0,0,0,0')
assert diagonals.returncode==0 and 'HELLO' not in diagonals.stdout and diagonals.stdout.count('PHASE ')==15
for name in ('crouch_diagonal_idle','crouch_diagonal_unarmed_ne','crouch_diagonal_unarmed_se',
             'crouch_diagonal_armed_sw','crouch_diagonal_aim_nw','crouch_diagonal_aim_stop'):
    assert 'name='+name+' ' in diagonals.stdout
import math,re
def diagonal_points(text):
    return {float(t):(float(x),float(y),float(yaw)) for t,x,y,yaw in re.findall(
        r'CROUCH_DIAGONAL_POINT t=(\S+) x=(\S+) y=(\S+) yaw=(\S+)',text)}
points=diagonal_points(diagonals.stdout)
rotated=diagonal_points(run('--validate-only','--crouch-diagonals','--origin','0,0,0,1.57079632679').stdout)
assert len(points)==10 and points[6]==(0,0,0)
for t in range(9,31,3):
    dx,dy=points[t][0]-points[t-3][0],points[t][1]-points[t-3][1]
    assert abs(math.hypot(dx,dy)-1.5)<.0001,'each diagonal leg must retain 0.5 m/s'
    assert points[t][2]==0,'direction fixture cannot rotate the body'
    assert abs(rotated[t][0]+points[t][1])<.0001 and abs(rotated[t][1]-points[t][0])<.0001
assert math.hypot(*points[30][:2])<.0001 and points[30]==points[36],'closed route must stop without teleporting'
for flag in ('--directions','--gaits','--unarmed-directions','--crouch-directions','--crouch-sides'):
    assert run('--validate-only','--crouch-diagonals',flag).returncode!=0
jumps=run('--validate-only','--jump-actions','--origin','0,0,10,0')
assert jumps.returncode==0 and 'HELLO' not in jumps.stdout and jumps.stdout.count('PHASE ')==15
for name in ('jump_armed_standing','jump_crouch_settle','jump_late_crouch_unarmed','jump_late_crouch_aim','jump_standing_aim'):
    assert 'name='+name+' ' in jumps.stdout
jump_points={float(t):(float(x),float(y),float(z),float(yaw)) for t,x,y,z,yaw in re.findall(
    r'JUMP_POINT t=(\S+) x=(\S+) y=(\S+) z=(\S+) yaw=(\S+)',jumps.stdout)}
for t in (8.6,20.6,26.6,32.6):
    assert abs(jump_points[t][2]-10.9)<.00001 and jump_points[t][3]==0
for t in (6,8,9.2,12,18,20,21.2,24,30,36):assert abs(jump_points[t][2]-10)<.00001
assert jump_points[6]==jump_points[12]==jump_points[18]==jump_points[24]==jump_points[30]==jump_points[36]
for flag in ('--directions','--gaits','--unarmed-directions','--crouch-directions','--crouch-sides','--crouch-diagonals'):
    assert run('--validate-only','--jump-actions',flag).returncode!=0
for origin in ('nan,1,2,3','0,inf,2,3','0,1,2,1001','1000001,1,2,0','0,1,2,0,5','0,1,2','0,1,2,0trailing'):
    bad=run('--validate-only','--origin',origin)
    assert bad.returncode!=0 and 'HELLO' not in bad.stdout,(origin,bad.stdout)
for args in (('--server','example.org'),('--origin',),('--session',''),('--session','x'*65),('--session','a\nb')):
    bad=run('--validate-only',*args)
    assert bad.returncode!=0 and 'HELLO' not in bad.stdout,args
print('Experimental action fixture: bounded CLI and offline preflight passed')
assert subprocess.run([exe,'--validate-only'],capture_output=True,timeout=5).returncode!=0
