"""Foot locking must survive pelvis lowering, turns and malformed poses."""
import copy,importlib.util,math
from pathlib import Path
path=Path(__file__).resolve().parents[1]/'experiments/player-locomotion/lower_crouch_walk.py'
spec=importlib.util.spec_from_file_location('crouch_recipe',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
parents=[-1,0,1,2,3,1,5,6]
t=[(0,0,0),(0,1,0),(-.1,0,0),(0,-.4,.15),(0,-.4,-.15),(.1,0,0),(0,-.4,.15),(0,-.4,-.15)]
legs=[(2,3,4),(5,6,7)]
for heading in (0,.7,-1.6,math.pi):
 q=[(0,math.sin(heading/2),0,math.cos(heading/2))]+[(0,0,0,1)]*7
 before,br=m.world(t,q,parents)
 for drop in (.05,.15,.25,.3):
  adjusted,rot,error=m.lower_pose(t,q,parents,1,legs,drop)
  after,ar=m.world(adjusted,rot,parents)
  assert abs(before[1][1]-after[1][1]-drop)<1e-10
  assert error<1e-10
  for upper,knee,foot in legs:
   assert m.length(m.sub(before[foot],after[foot]))<1e-10
   assert abs(abs(m.dot(br[foot],ar[foot]))-1)<1e-10
   assert abs(m.length(m.sub(after[knee],after[upper]))-m.length(t[knee]))<1e-10
   assert abs(m.length(m.sub(after[foot],after[knee]))-m.length(t[foot]))<1e-10
   assert after[knee][2]!=before[knee][2] or heading!=0
def reject(fn):
 try:fn()
 except ValueError:return
 raise AssertionError('Invalid solve admitted')
for drop in (float('nan'),float('inf'),-.1,0,.31):reject(lambda:m.lower_pose(t,[(0,0,0,1)]*8,parents,1,legs,drop))
reject(lambda:m.solve_knee((0,0,0),(0,2,0),(.1,.5,0),.4,.4))
reject(lambda:m.solve_knee((0,0,0),(0,0,0),(.1,.5,0),.4,.4))
reject(lambda:m.lower_pose(t,[(0,0,0,1)]*8,parents,1,[(2,4,3)],.2))
entries=[{'Data':{'events':{'HandleId':'events'},'animation':{'Data':{'name':{'$value':name},'duration':3,
 'animBuffer':{'Data':{'numJoints':71,'opaque_pose':'must remain exact'}},'motionExtraction':{'HandleId':'root-motion'}}}}}
 for name in ('cp_coop_stealth_idle_low_unarmed','cp_coop_stealth_walk_0')]
native={'Data':{'RootChunk':{'$type':'animAnimSet','rig':{'DepotPath':{'$value':r'base\characters\base_entities\woman_base\woman_base.rig'}},'animations':entries}}}
clean=m.sanitize_native(native)
for before,after in zip(entries,clean['Data']['RootChunk']['animations']):
 assert after['Data']['events']=={'HandleRefId':'-1'}
 assert after['Data']['animation']['Data']['motionExtraction']=={'HandleRefId':'-1'}
 assert before['Data']['animation']['Data']['animBuffer']==after['Data']['animation']['Data']['animBuffer']
 assert before['Data']['events']=={'HandleId':'events'}
wrong=copy.deepcopy(native);wrong['Data']['RootChunk']['animations'][1]['Data']['animation']['Data']['animBuffer']['Data']['numJoints']=72
reject(lambda:m.sanitize_native(wrong))
wrong=copy.deepcopy(native);wrong['Data']['RootChunk']['animations'].reverse();reject(lambda:m.sanitize_native(wrong))
print('Crouch IK: pelvis lowering, exact foot paths/orientations, bone lengths, heading invariance and rejection passed')
