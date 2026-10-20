"""PRIVATE owned-game derivative: low side steps with forward-facing hips.

Only two inspected rifle side clips and the qualified lowered forward crouch
reference are accepted. Generated GLB/native animation data stays outside Git.
Geometry is a prerequisite, not a visual qualification.
"""
from __future__ import annotations
import argparse,copy,hashlib,importlib.util,json,math,struct
from pathlib import Path

spec=importlib.util.spec_from_file_location('side_direction_base',Path(__file__).with_name('normalize_directional_walk.py'))
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
m=base.pose_math
CLIPS=('walk_090','walk_270')
PREFIX='cp_coop_crouch_side_'


def lower_pose(t,q,parents,hips,legs,height,facing):
    if not math.isfinite(height) or not .45<=height<=.65:
        raise ValueError('Inspected forward crouch hip height required')
    before,old=m.world(t,q,parents)
    drop=before[hips][1]-height
    if not .3<=drop<=.55:raise ValueError('Unqualified side crouch drop')
    # Lower first. Rotating standing hips directly to the pitched low reference
    # can make a straight leg unreachable before the later lowering step.
    nt,nq,_=m.lower_pose(t,q,parents,hips,legs,.2)
    nt,nq,*_=base.normalize_pose(nt,nq,parents,hips,legs,facing,.005)
    p,_=m.world(nt,nq,parents);remaining=p[hips][1]-height
    if not .05<=remaining<=.35:raise ValueError('Unexpected remaining crouch drop')
    steps=math.ceil(remaining/.3)
    for _ in range(steps):nt,nq,_=m.lower_pose(nt,nq,parents,hips,legs,remaining/steps)
    final,rot=m.world(nt,nq,parents)
    error=max(m.length(m.sub(final[f],before[f])) for _,_,f in legs)
    orientation=max(abs(1-abs(m.dot(rot[f],old[f]))) for _,_,f in legs)
    if error>1e-5 or orientation>1e-5 or abs(final[hips][1]-height)>1e-5:
        raise ValueError('Side crouch solve lost a geometric invariant')
    return nt,nq


def sanitize_native(document):
    result=copy.deepcopy(document);root=result['Data']['RootChunk']
    if document['Header']['GameVersion']!=2310 or root['$type']!='animAnimSet' \
        or root['rig']['DepotPath']['$value']!=r'base\characters\base_entities\woman_base\woman_base.rig':
        raise ValueError('Inspected native 2.31 skeleton required')
    entries=root['animations']
    if [e['Data']['animation']['Data']['name']['$value'] for e in entries]!=[PREFIX+c for c in CLIPS]:
        raise ValueError('Two exact side crouch aliases required')
    for entry in entries:
        a=entry['Data']['animation']['Data']
        if a['$type']!='animAnimation' or a['animBuffer']['Data']['numJoints']!=71 or not .5<a['duration']<.7:
            raise ValueError('Unexpected native side clip')
        entry['Data']['events']={'HandleRefId':'-1'};a['motionExtraction']={'HandleRefId':'-1'}
    return result


def compare_paths(source,reference,candidate):
    ref=base.Animation(reference,'cp_coop_stealth_walk_0');hips=ref.names['Hips']
    legs=[tuple(ref.names[s+n] for n in ('UpLeg','Leg','Foot')) for s in ('Left','Right')]
    reports={}
    for name in CLIPS:
        old=base.Animation(source,name);new=base.Animation(candidate,PREFIX+name)
        if old.names!=ref.names or new.names!=ref.names or old.parents!=ref.parents or new.parents!=ref.parents:
            raise ValueError('Comparison skeleton mismatch')
        foot=orientation=height=facing=head=0;steps=math.ceil(old.duration*120)
        for i in range(steps+1):
            time=old.duration*i/steps;ot,oq=old.pose(time);nt,nq=new.pose(time);rt,rq=ref.pose(time/old.duration*ref.duration)
            op,orr=m.world(ot,oq,old.parents);np,nrr=m.world(nt,nq,new.parents);rp,rr=m.world(rt,rq,ref.parents)
            foot=max(foot,*(m.length(m.sub(op[f],np[f])) for _,_,f in legs))
            orientation=max(orientation,*(abs(1-abs(m.dot(orr[f],nrr[f]))) for _,_,f in legs))
            height=max(height,abs(np[hips][1]-rp[hips][1]))
            facing=max(facing,abs(1-abs(m.dot(nrr[hips],rr[hips]))))
            head=max(head,abs(1-abs(m.dot(nrr[new.names['Head']],rr[ref.names['Head']]))))
        reports[name]={'dense_samples':steps+1,'max_foot_error_m':foot,'max_foot_orientation_error':orientation,
                       'max_reference_hip_height_error_m':height,'max_reference_hip_orientation_error':facing,
                       'max_reference_head_orientation_error':head}
    return reports


def bake(source,reference,output):
    root=Path(__file__).resolve().parents[2]
    if output.exists() or root in output.resolve().parents or any((p/'.git').exists() for p in output.resolve().parents):
        raise ValueError('Choose a new private output file outside Git')
    if source.name!='wa_gang_rifle_locomotion_combat.anims.glb' or reference.name!='player_stealth.anims.glb':
        raise ValueError('Inspected rifle and lowered crouch exports required')
    ref=base.Animation(reference,'cp_coop_stealth_walk_0');first=base.Animation(source,CLIPS[0])
    if first.names!=ref.names or first.parents!=ref.parents:raise ValueError('Source/reference skeleton mismatch')
    doc,binary=first.doc,first.binary;hips=first.names['Hips']
    legs=[tuple(first.names[s+n] for n in ('UpLeg','Leg','Foot')) for s in ('Left','Right')]
    spine=first.names['Spine'];upper=[]
    for index in range(len(first.nodes)):
        ancestor=index
        while ancestor>=0 and ancestor!=spine:ancestor=first.parents[ancestor]
        if ancestor==spine:upper.append(index)
    def append(values,kind):
        while len(binary)%4:binary.append(0)
        offset=len(binary)
        for v in values:binary.extend(struct.pack('<'+'f'*len(v),*v))
        view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset})
        index=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(values),'type':kind,
            'min':[min(v[i] for v in values) for i in range(len(values[0]))],'max':[max(v[i] for v in values) for i in range(len(values[0]))]})
        return index
    selected=[]
    for name in CLIPS:
        a=base.Animation(source,name)
        animation=next(v for v in doc['animations'] if v['name']==name)
        channels={(c['target']['node'],c['target']['path']):c for c in animation['channels']}
        times=base.sample_times(a.duration,a.times+[t/ref.duration*a.duration for t in ref.times])
        changed={(hips,'translation'):[],(hips,'rotation'):[]}
        for leg in legs:
            for index in leg:changed[(index,'rotation')]=[]
        for index in upper:
            changed[(index,'translation')]=[];changed[(index,'rotation')]=[]
        for time in times:
            t,q=a.pose(time);rt,rq=ref.pose(time/a.duration*ref.duration);rp,rr=m.world(rt,rq,ref.parents)
            nt,nq=lower_pose(t,q,a.parents,hips,legs,rp[hips][1],rr[hips])
            # The native isolated clip must match the eventual lower-body
            # composition too. Combat spine counter-rotation/fists cannot leak.
            for index in upper:nt[index],nq[index]=rt[index],rq[index]
            for key,values in changed.items():
                value=nt[key[0]] if key[1]=='translation' else nq[key[0]]
                if key[1]=='rotation' and values and m.dot(values[-1],value)<0:value=m.mul(value,-1)
                values.append(value)
        time_index=append([(v,) for v in times],'SCALAR')
        for key,values in changed.items():
            if key not in channels:
                channel={'sampler':len(animation['samplers']),'target':{'node':key[0],'path':key[1]}}
                animation['channels'].append(channel);animation['samplers'].append({});channels[key]=channel
            animation['samplers'][channels[key]['sampler']].update(interpolation='LINEAR',input=time_index,
                output=append(values,'VEC3' if key[1]=='translation' else 'VEC4'))
        animation['name']=PREFIX+name;animation['extras']['animEvents']=None;animation['extras']['rootMotionType']='Unknown'
        selected.append(animation)
    doc['animations']=selected;doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);binary.extend(b'\0'*((-len(binary))%4))
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
    clips=compare_paths(source,reference,output)
    passed=all(v['max_foot_error_m']<.005 and v['max_foot_orientation_error']<.0001 and
        v['max_reference_hip_height_error_m']<.003 and v['max_reference_hip_orientation_error']<.0001 and
        v['max_reference_head_orientation_error']<.0001 for v in clips.values())
    report={'scope':'PRIVATE geometric prerequisite, no native/game qualification','passed':passed,'clips':clips,
        'builder_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(reference.read_bytes()).hexdigest()}
    output.with_suffix('.validation.json').write_text(json.dumps(report,indent=2)+'\n')
    if not passed:raise ValueError('Dense side crouch validation failed; retain rejected output')
    return report


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True)
    p.add_argument('--reference',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();print(json.dumps(bake(a.source,a.reference,a.output),indent=2))
