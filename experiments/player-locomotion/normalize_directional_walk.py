"""PRIVATE owned-game derivative: forward-facing hips with original foot paths.

Inputs are inspected2.31 rifle locomotion and relaxed unarmed GLB exports.
Generated GLB/native animation data must never be committed or distributed.
Mathematical validation is not an in-game quality verdict.
"""
from __future__ import annotations
import argparse
import bisect
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct

spec=importlib.util.spec_from_file_location('crouch_math',Path(__file__).with_name('lower_crouch_walk.py'))
pose_math=importlib.util.module_from_spec(spec);spec.loader.exec_module(pose_math)
CLIPS=('walk_0','walk_090','walk_180','walk_270')
PREFIX='cp_coop_directional_neutral_'


def sample_times(duration,original):
    # Nearby double/native-float times can become the same serialized float.
    # Deduplicate in the actual GLB representation before evaluating the pose.
    steps=math.ceil(duration*60)
    return sorted({struct.unpack('<f',struct.pack('<f',v))[0]
                   for v in [*original,*(duration*i/steps for i in range(steps+1))]})


def sanitize_native(document):
    result=copy.deepcopy(document);root=result['Data']['RootChunk']
    if document['Header']['GameVersion']!=2310 or root['$type']!='animAnimSet' \
        or root['rig']['DepotPath']['$value']!=r'base\characters\base_entities\woman_base\woman_base.rig':
        raise ValueError('Inspected native2.31 skeleton required')
    entries=root['animations']
    if [e['Data']['animation']['Data']['name']['$value'] for e in entries]!=[PREFIX+n for n in CLIPS]:
        raise ValueError('Four exact normalized aliases required')
    for entry in entries:
        a=entry['Data']['animation']['Data']
        if a['$type']!='animAnimation' or a['animBuffer']['Data']['numJoints']!=71 or not .1<a['duration']<5:
            raise ValueError('Unexpected native animation')
        entry['Data']['events']={'HandleRefId':'-1'}
        a['motionExtraction']={'HandleRefId':'-1'}
    return result


class Animation:
    def __init__(self,path,name):
        raw=path.read_bytes()
        if not 28<=len(raw)<=64*1024*1024 or struct.unpack_from('<III',raw)!=(0x46546c67,2,len(raw)):
            raise ValueError('Bounded embedded GLB2 required')
        size,kind=struct.unpack_from('<II',raw,12)
        if kind!=0x4e4f534a or 28+size>len(raw):raise ValueError('Missing JSON chunk')
        self.doc=json.loads(raw[20:20+size]);length,kind=struct.unpack_from('<II',raw,20+size)
        if kind!=0x004e4942 or 28+size+length!=len(raw):raise ValueError('One embedded BIN chunk required')
        self.binary=bytearray(raw[28+size:]);self.nodes=self.doc['nodes']
        if len(self.nodes)!=72 or len(self.doc['skins'])!=1 or len(self.doc['skins'][0]['joints'])!=71:
            raise ValueError('Inspected71-joint skeleton required')
        if len(self.doc['buffers'])!=1 or 'uri' in self.doc['buffers'][0]:raise ValueError('External buffers forbidden')
        self.names={n['name']:i for i,n in enumerate(self.nodes)}
        if len(self.names)!=len(self.nodes):raise ValueError('Ambiguous node names')
        self.parents=[-1]*len(self.nodes)
        for i,n in enumerate(self.nodes):
            if 'matrix' in n or any(abs(v-1)>0.00002 for v in n.get('scale',[1,1,1])):
                raise ValueError('Unexpected node matrix/scale')
            for child in n.get('children',[]):
                if not i<child<len(self.nodes) or self.parents[child]>=0:raise ValueError('Parent-first tree required')
                self.parents[child]=i
        selected=[a for a in self.doc['animations'] if a['name']==name]
        if len(selected)!=1:raise ValueError('One exact animation required')
        self.animation=selected[0];self.channels={}
        for channel in self.animation['channels']:
            key=(channel['target']['node'],channel['target']['path'])
            sampler=self.animation['samplers'][channel['sampler']]
            if key in self.channels or key[1] not in ('translation','rotation') or sampler.get('interpolation','LINEAR') not in ('LINEAR','STEP'):
                raise ValueError('Unexpected/ambiguous animation channel')
            times=[v[0] for v in self.array(sampler['input'])];values=self.array(sampler['output'])
            if not times or len(times)!=len(values) or times[0]<0 or any(a>=b for a,b in zip(times,times[1:])):
                raise ValueError('Invalid animation sample times')
            if any(len(v)!=(4 if key[1]=='rotation' else 3) for v in values):raise ValueError('Wrong transform width')
            self.channels[key]=(times,values,channel,sampler)
        self.times=sorted({t for ts,_,_,_ in self.channels.values() for t in ts})
        self.duration=self.times[-1]
        if not .1<self.duration<5 or len(self.times)>1000:raise ValueError('Unexpected walk duration/sample count')

    def array(self,index):
        a=self.doc['accessors'][index];view=self.doc['bufferViews'][a['bufferView']]
        width={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
        if a['componentType']!=5126 or 'sparse' in a or 'byteStride' in view or not 0<a['count']<=2048:
            raise ValueError('Unexpected animation accessor')
        offset=view.get('byteOffset',0)+a.get('byteOffset',0)
        if offset<0 or offset+a['count']*width*4>len(self.binary):raise ValueError('Accessor out of bounds')
        values=[struct.unpack_from('<'+'f'*width,self.binary,offset+i*width*4) for i in range(a['count'])]
        if any(not math.isfinite(v) for row in values for v in row):raise ValueError('Nonfinite transform')
        return values

    def value(self,key,time,default):
        if key not in self.channels:return default
        times,values,_,sampler=self.channels[key]
        i=max(0,min(len(times)-1,bisect.bisect_right(times,time)-1))
        if i==len(times)-1 or sampler.get('interpolation')=='STEP':return values[i]
        weight=(time-times[i])/(times[i+1]-times[i])
        if key[1]=='rotation':return pose_math.slerp(values[i],values[i+1],weight)
        return pose_math.add(pose_math.mul(values[i],1-weight),pose_math.mul(values[i+1],weight))

    def pose(self,time):
        return ([self.value((i,'translation'),time,n.get('translation',[0,0,0])) for i,n in enumerate(self.nodes)],
                [self.value((i,'rotation'),time,n.get('rotation',[0,0,0,1])) for i,n in enumerate(self.nodes)])


def normalize_pose(translations,rotations,parents,hips,legs,reference_hip_world,drop=.005,poles=None):
    m=pose_math
    if not math.isfinite(drop) or not 0<=drop<=.02:raise ValueError('Constant drop outside qualification bound')
    if any(parents[u]!=hips or parents[k]!=u or parents[f]!=k for u,k,f in legs):raise ValueError('Unexpected leg hierarchy')
    before,old=m.world(translations,rotations,parents)
    t,q=copy.deepcopy(translations),copy.deepcopy(rotations);parent=parents[hips]
    target_orientation=m.unit(reference_hip_world)
    q[hips]=m.qmul(m.inv(old[parent]),target_orientation) if parent>=0 else target_orientation
    delta=(0,-drop,0)
    t[hips]=m.add(t[hips],m.rotate(m.inv(old[parent]),delta) if parent>=0 else delta)
    if poles is not None and len(poles)!=len(legs):raise ValueError('One stable knee pole per leg required')
    for index,(upper,knee,foot) in enumerate(legs):
        positions,world_rot=m.world(t,q,parents);hip=positions[upper];target=before[foot]
        pole=before[knee] if poles is None else m.add(hip,m.unit(poles[index]))
        solved=m.solve_knee(hip,target,pole,m.length(m.sub(before[knee],before[upper])),m.length(m.sub(before[foot],before[knee])))
        upper_world=m.qmul(m.between(m.sub(before[knee],before[upper]),m.sub(solved,hip)),old[upper])
        q[upper]=m.unit(m.qmul(m.inv(world_rot[parents[upper]]),upper_world))
        leg_world=m.qmul(m.between(m.sub(before[foot],before[knee]),m.sub(target,solved)),old[knee])
        q[knee]=m.unit(m.qmul(m.inv(upper_world),leg_world))
        q[foot]=m.unit(m.qmul(m.inv(leg_world),old[foot]))
    after,world_rot=m.world(t,q,parents)
    error=max(m.length(m.sub(after[f],before[f])) for _,_,f in legs)
    orientation=max(abs(1-abs(m.dot(world_rot[f],old[f]))) for _,_,f in legs)
    hip_error=abs(1-abs(m.dot(world_rot[hips],target_orientation)))
    if error>1e-5 or orientation>1e-5 or hip_error>1e-5:raise ValueError('Pose correction failed its geometric invariants')
    return t,q,error,orientation,hip_error


def compare_paths(source,reference,candidate):
    """Also accepts a GLB exported back out of the compiled native animation."""
    ref=Animation(reference,'walk_0');hips=ref.names['Hips']
    legs=[tuple(ref.names[s+n] for n in ('UpLeg','Leg','Foot')) for s in ('Left','Right')]
    reports={}
    for clip in CLIPS:
        old=Animation(source,clip);new=Animation(candidate,PREFIX+clip)
        if old.names!=ref.names or new.names!=ref.names or old.parents!=ref.parents or new.parents!=ref.parents:
            raise ValueError('Comparison skeleton mismatch')
        error=orientation=hip_error=0;steps=math.ceil(old.duration*120)
        for i in range(steps+1):
            time=old.duration*i/steps;ot,oq=old.pose(time);nt,nq=new.pose(time);rt,rq=ref.pose(time/old.duration*ref.duration)
            op,orr=pose_math.world(ot,oq,old.parents);np,nrr=pose_math.world(nt,nq,new.parents);_,reference_rot=pose_math.world(rt,rq,ref.parents)
            error=max(error,*(pose_math.length(pose_math.sub(op[f],np[f])) for _,_,f in legs))
            orientation=max(orientation,*(abs(1-abs(pose_math.dot(orr[f],nrr[f]))) for _,_,f in legs))
            hip_error=max(hip_error,abs(1-abs(pose_math.dot(nrr[hips],reference_rot[hips]))))
        reports[clip]={'dense_samples':steps+1,'max_foot_error_m':error,
                       'max_foot_orientation_error':orientation,'max_reference_hip_error':hip_error}
    return reports


def bake(source,reference,output,drop=.005):
    root=Path(__file__).resolve().parents[2]
    if output.exists() or root in output.resolve().parents or any((p/'.git').exists() for p in output.resolve().parents):
        raise ValueError('Choose a new private output file outside Git')
    if source.name!='wa_gang_rifle_locomotion_combat.anims.glb' or reference.name!='wa_gang_unarmed_locomotion_relaxed.anims.glb':
        raise ValueError('Inspected rifle/relaxed exports required')
    ref=Animation(reference,'walk_0');first=Animation(source,'walk_0')
    doc,binary=first.doc,first.binary;names=first.names;hips=names['Hips']
    legs=[tuple(names[s+n] for n in ('UpLeg','Leg','Foot')) for s in ('Left','Right')]
    if ref.names!=names or ref.parents!=first.parents:raise ValueError('Source/reference skeleton mismatch')
    # The old source knee can cross the newly rotated leg axis and flip the
    # two-bone solution between keys. Derive a stable anatomical bend pole from
    # the reference's strongest observed knee bend, separately for each leg.
    poles=[]
    for upper,knee,foot in legs:
        candidates=[]
        for time in ref.times:
            t,q=ref.pose(time);p,_=pose_math.world(t,q,ref.parents)
            axis=pose_math.unit(pose_math.sub(p[foot],p[upper]));delta=pose_math.sub(p[knee],p[upper])
            bend=pose_math.sub(delta,pose_math.mul(axis,pose_math.dot(delta,axis)))
            candidates.append(bend)
        pole=max(candidates,key=pose_math.length)
        if pose_math.length(pole)<.001:raise ValueError('Reference has no qualified knee bend plane')
        poles.append(pose_math.unit(pole))
    selected=[];reports={}
    def append(values,kind):
        while len(binary)%4:binary.append(0)
        offset=len(binary)
        for v in values:binary.extend(struct.pack('<'+'f'*len(v),*v))
        view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset})
        index=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(values),'type':kind,
            'min':[min(v[i] for v in values) for i in range(len(values[0]))], 'max':[max(v[i] for v in values) for i in range(len(values[0]))]})
        return index
    for clip in CLIPS:
        a=Animation(source,clip)
        # Use the first document's indexes and buffer. All four source animations
        # share it, and newly appended data never changes original offsets.
        animation=next(v for v in doc['animations'] if v['name']==clip)
        channels={(c['target']['node'],c['target']['path']):c for c in animation['channels']}
        times=sample_times(a.duration,a.times+[t/ref.duration*a.duration for t in ref.times])
        modified={(hips,'translation'):[],(hips,'rotation'):[]}
        for leg in legs:
            for index in leg:modified[(index,'rotation')]=[]
        maximum=0
        for time in times:
            t,q=a.pose(time);rt,rq=ref.pose(time/a.duration*ref.duration)
            _,original=pose_math.world(t,q,a.parents);_,target=pose_math.world(rt,rq,ref.parents)
            parent=a.parents[hips]
            if abs(1-abs(pose_math.dot(original[parent],target[parent])))>1e-5:
                raise ValueError('Different parent-root orientation bases')
            t,q,error,_,_=normalize_pose(t,q,a.parents,hips,legs,target[hips],drop,poles);maximum=max(maximum,error)
            for key,values in modified.items():
                v=t[key[0]] if key[1]=='translation' else q[key[0]]
                if key[1]=='rotation' and values and pose_math.dot(values[-1],v)<0:v=pose_math.mul(v,-1)
                values.append(v)
        time_index=append([(v,) for v in times],'SCALAR')
        for key,values in modified.items():
            if key not in channels:raise ValueError('Required baked channel missing')
            sampler=animation['samplers'][channels[key]['sampler']]
            sampler.update(interpolation='LINEAR',input=time_index,output=append(values,'VEC3' if key[1]=='translation' else 'VEC4'))
        animation['name']=PREFIX+clip
        animation['extras']['animEvents']=None;animation['extras']['rootMotionType']='Unknown'
        selected.append(animation);reports[clip]={'samples':len(times),'key_foot_error_m':maximum}
    doc['animations']=selected;doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);binary.extend(b'\0'*((-len(binary))%4))
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
    # Evaluate interpolated output between baked keys too. Key-only validation
    # cannot detect resampling error along a foot path.
    for clip,measurements in compare_paths(source,reference,output).items():reports[clip].update(measurements)
    passed=all(v['max_foot_error_m']<.005 and v['max_foot_orientation_error']<.0001 and v['max_reference_hip_error']<.0001 for v in reports.values())
    report={'scope':'PRIVATE geometric prerequisite, not native import or live proof','passed':passed,'pelvis_drop_m':drop,'reference_knee_poles':poles,
            'builder_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(reference.read_bytes()).hexdigest(),'clips':reports}
    output.with_suffix('.validation.json').write_text(json.dumps(report,indent=2)+'\n')
    if not passed:raise ValueError('Dense interpolation validation failed; retain rejected output')
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--reference',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--drop',type=float,default=.005)
    args=parser.parse_args();print(json.dumps(bake(args.source,args.reference,args.output,args.drop),indent=2))
