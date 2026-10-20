"""Authored skeleton only: low side-step solve and metadata boundaries."""
import copy,importlib.util,math
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'experiments/player-locomotion/lower_side_crouch.py'
s=importlib.util.spec_from_file_location('side_crouch',p);n=importlib.util.module_from_spec(s);s.loader.exec_module(n);m=n.m
parents=[-1,0,1,2,3,1,5,6,1];legs=[(2,3,4),(5,6,7)]
def yaw(v):return (0,math.sin(v/2),0,math.cos(v/2))
def pitch(v):return (math.sin(v/2),0,0,math.cos(v/2))
for angle in (0,.4,-.4):
    t=[[0,0,0],[0,1,0],[-.1,-.05,0],[0,-.45,0],[0,-.45,0],
       [.1,-.05,0],[0,-.45,0],[0,-.45,0],[0,.3,0]]
    q=[yaw(0),yaw(angle),pitch(.6),pitch(-1.2),pitch(.6),pitch(.6),pitch(-1.2),pitch(.6),yaw(0)]
    original=copy.deepcopy((t,q));before,rot=m.world(t,q,parents)
    facing=pitch(.25);nt,nq=n.lower_pose(t,q,parents,1,legs,.55,facing)
    after,r=m.world(nt,nq,parents)
    assert (t,q)==original and nt[0]==t[0] and nq[0]==q[0]
    assert abs(after[1][1]-.55)<1e-8 and abs(1-abs(m.dot(r[1],facing)))<1e-8
    for upper,knee,foot in legs:
        assert m.length(m.sub(after[foot],before[foot]))<1e-8
        assert abs(1-abs(m.dot(r[foot],rot[foot])))<1e-8
        for a,b in [(upper,knee),(knee,foot)]:
            assert abs(m.length(m.sub(after[b],after[a]))-m.length(m.sub(before[b],before[a])))<1e-8
for height in (.44,.66,float('nan'),float('inf')):
    try:n.lower_pose(t,q,parents,1,legs,height,yaw(0))
    except ValueError:pass
    else:raise AssertionError('unqualified crouch height accepted')
bad=copy.deepcopy(t);bad[1][1]=.7
try:n.lower_pose(bad,q,parents,1,legs,.55,yaw(0))
except ValueError:pass
else:raise AssertionError('unqualified drop accepted')
doc={'Header':{'GameVersion':2310},'Data':{'RootChunk':{'$type':'animAnimSet',
    'rig':{'DepotPath':{'$value':r'base\characters\base_entities\woman_base\woman_base.rig'}},
    'animations':[{'Data':{'events':{'HandleId':'9'},'animation':{'Data':{'$type':'animAnimation',
        'name':{'$value':n.PREFIX+c},'duration':.566666663,'animBuffer':{'Data':{'numJoints':71,'test':'authored'}},
        'motionExtraction':{'HandleId':'8'}}}}} for c in n.CLIPS]}}}
original=copy.deepcopy(doc);clean=n.sanitize_native(doc);assert doc==original
for e,old in zip(clean['Data']['RootChunk']['animations'],doc['Data']['RootChunk']['animations']):
    assert e['Data']['events']=={'HandleRefId':'-1'} and e['Data']['animation']['Data']['motionExtraction']=={'HandleRefId':'-1'}
    assert e['Data']['animation']['Data']['animBuffer']==old['Data']['animation']['Data']['animBuffer']
for change in [lambda d:d['Header'].update(GameVersion=2300),
               lambda d:d['Data']['RootChunk']['animations'].reverse(),
               lambda d:d['Data']['RootChunk']['animations'][0]['Data']['animation']['Data'].update(duration=3)]:
    bad=copy.deepcopy(doc);change(bad)
    try:n.sanitize_native(bad)
    except ValueError:pass
    else:raise AssertionError('wrong native recipe accepted')
print('Side crouch IK: original feet/rotations/lengths/root, low forward hips, input isolation and fail-closed metadata passed')
