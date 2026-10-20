"""Authored geometry only: foot targets, facing basis and rejection boundaries."""
import copy
import importlib.util
import math
import struct
from pathlib import Path
import tempfile

root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('neutral_walk',root/'experiments/player-locomotion/normalize_directional_walk.py')
n=importlib.util.module_from_spec(spec);spec.loader.exec_module(n);m=n.pose_math
parents=[-1,0,1,2,3,1,5,6,1]
legs=[(2,3,4),(5,6,7)]
def yaw(angle):return (0,math.sin(angle/2),0,math.cos(angle/2))
def pitch(angle):return (math.sin(angle/2),0,0,math.cos(angle/2))
for angle in (0,.4,math.pi/2,-math.pi/2):
    t=[[0,0,0],[0,1,0],[-.1,-.05,0],[0,-.45,0],[0,-.45,0],
       [.1,-.05,0],[0,-.45,0],[0,-.45,0],[0,.3,0]]
    q=[yaw(0),yaw(angle),pitch(.6),pitch(-1.2),pitch(.6),pitch(.6),pitch(-1.2),pitch(.6),yaw(-angle)]
    original=copy.deepcopy((t,q));positions,orientations=m.world(t,q,parents)
    target=yaw(.1)
    nt,nq,*errors=n.normalize_pose(t,q,parents,1,legs,target,.005)
    assert (t,q)==original,'normalization must not mutate source/reference inputs'
    assert nt[0]==t[0] and nq[0]==q[0],'entity/root transform cannot be changed'
    after,rot=m.world(nt,nq,parents)
    for upper,knee,foot in legs:
        assert m.length(m.sub(after[foot],positions[foot]))<1e-9
        assert abs(1-abs(m.dot(rot[foot],orientations[foot])))<1e-9
        for a,b in ((upper,knee),(knee,foot)):
            assert abs(m.length(m.sub(after[b],after[a]))-m.length(m.sub(positions[b],positions[a])))<1e-9
    assert max(errors)<1e-9 and abs(1-abs(m.dot(rot[1],target)))<1e-9
    pt,pq,*pe=n.normalize_pose(t,q,parents,1,legs,target,.005,[(0,0,-1),(0,0,-1)])
    assert max(pe)<1e-9,'stable reference poles must retain the same exact geometric targets'
    # The runtime's lower-bone mask retains the baseline upper-body local pose.
    nq[8]=yaw(0);_,masked=m.world(nt,nq,parents)
    assert abs(1-abs(m.dot(masked[8],target)))<1e-9,'upper body must follow the reference facing, not the old side-facing pelvis'
for drop in (-.001,.021,float('nan'),float('inf')):
    try:n.normalize_pose(t,q,parents,1,legs,yaw(0),drop)
    except ValueError:pass
    else:raise AssertionError('unqualified pelvis drop accepted')
times=n.sample_times(struct.unpack('<f',struct.pack('<f',.6))[0],[0,struct.unpack('<f',struct.pack('<f',.2))[0],.6])
serialized=[struct.unpack('<f',struct.pack('<f',v))[0] for v in times]
assert all(a<b for a,b in zip(serialized,serialized[1:])),'float32 serialization cannot create duplicate key times'
try:n.normalize_pose(t,q,parents,1,[(2,5,4)],yaw(0))
except ValueError:pass
else:raise AssertionError('foreign leg hierarchy accepted')
with tempfile.TemporaryDirectory() as temp:
    bad=Path(temp)/'bad.glb';bad.write_bytes(b'not a GLB')
    try:n.Animation(bad,'walk_0')
    except ValueError:pass
    else:raise AssertionError('malformed GLB accepted')
document={'Header':{'GameVersion':2310},'Data':{'RootChunk':{'$type':'animAnimSet',
    'rig':{'DepotPath':{'$value':r'base\characters\base_entities\woman_base\woman_base.rig'}},
    'animations':[{'Data':{'events':{'HandleId':'99'},'animation':{'Data':{
        '$type':'animAnimation','name':{'$value':n.PREFIX+clip},'duration':1,
        'animBuffer':{'Data':{'numJoints':71,'owned_fixture_bytes':'authored-test-only'}},
        'motionExtraction':{'HandleId':'98'}}}}} for clip in n.CLIPS]}}}
original=copy.deepcopy(document);clean=n.sanitize_native(document)
assert document==original
for entry,before in zip(clean['Data']['RootChunk']['animations'],original['Data']['RootChunk']['animations']):
    assert entry['Data']['events']=={'HandleRefId':'-1'}
    assert entry['Data']['animation']['Data']['motionExtraction']=={'HandleRefId':'-1'}
    assert entry['Data']['animation']['Data']['animBuffer']==before['Data']['animation']['Data']['animBuffer']
bad=copy.deepcopy(document);bad['Data']['RootChunk']['animations'][0]['Data']['animation']['Data']['name']['$value']='walk_0'
try:n.sanitize_native(bad)
except ValueError:pass
else:raise AssertionError('unaliased native bank accepted')
print('Normalized direction: exact feet/orientation, fixed heading/root, limb lengths, input isolation and bounded failure passed')
