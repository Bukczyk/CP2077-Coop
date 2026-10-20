"""PRIVATE local crouch-walk recipe, applied to an owned-game GLB export.

Lower the moving pelvis and solve both legs back to their original foot paths.
This retains the walking cycle, rather than sliding a stationary crouch pose.
Generated GLB/anims contain game data: never commit, upload or distribute them.
"""
from __future__ import annotations
import argparse,bisect,copy,json,math,struct
from pathlib import Path


def add(a,b):return tuple(x+y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def mul(a,s):return tuple(x*s for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def length(a):return math.sqrt(dot(a,a))
def unit(a):
    size=length(a)
    if not math.isfinite(size) or size<1e-9:raise ValueError('Degenerate vector/quaternion')
    return mul(a,1/size)
def qmul(a,b):return (*add(add(mul(b[:3],a[3]),mul(a[:3],b[3])),cross(a[:3],b[:3])),a[3]*b[3]-dot(a[:3],b[:3]))
def inv(q):return (-q[0],-q[1],-q[2],q[3])
def rotate(q,v):return qmul(qmul(q,(*v,0)),inv(q))[:3]
def between(a,b):
    a,b=unit(a),unit(b);d=dot(a,b)
    if d<-0.999999:
        axis=cross(a,(1,0,0) if abs(a[0])<0.8 else (0,1,0))
        return (*unit(axis),0)
    return unit((*cross(a,b),1+d))
def slerp(a,b,t):
    a,b=unit(a),unit(b);d=dot(a,b)
    if d<0:b=mul(b,-1);d=-d
    if d>0.9995:return unit(add(mul(a,1-t),mul(b,t)))
    angle=math.acos(min(1,d));s=math.sin(angle)
    return add(mul(a,math.sin((1-t)*angle)/s),mul(b,math.sin(t*angle)/s))


def solve_knee(hip,foot,old_knee,thigh,calf):
    """Two-bone solve in the original bend plane, with exact segment lengths."""
    delta=sub(foot,hip);distance=length(delta)
    if not abs(thigh-calf)+1e-6<distance<thigh+calf-1e-6:
        raise ValueError('Unreachable foot target')
    axis=unit(delta);side=sub(sub(old_knee,hip),mul(axis,dot(sub(old_knee,hip),axis)))
    side=unit(side)
    along=(thigh*thigh-calf*calf+distance*distance)/(2*distance)
    height=math.sqrt(max(0,thigh*thigh-along*along))
    return add(add(hip,mul(axis,along)),mul(side,height))


def world(translations,rotations,parents):
    positions=[];orientations=[]
    for i,(t,q,parent) in enumerate(zip(translations,rotations,parents)):
        if parent>=i:raise ValueError('Skeleton must be parent-first')
        positions.append(t if parent<0 else add(positions[parent],rotate(orientations[parent],t)))
        orientations.append(unit(q if parent<0 else qmul(orientations[parent],q)))
    return positions,orientations


def lower_pose(translations,rotations,parents,hips,legs,drop):
    if not 0.05<=drop<=0.3:raise ValueError('Pelvis drop outside inspected range')
    before,old_rot=world(translations,rotations,parents)
    t,q=copy.deepcopy(translations),copy.deepcopy(rotations)
    parent=parents[hips];delta=(0,-drop,0)
    t[hips]=add(t[hips],rotate(inv(old_rot[parent]),delta) if parent>=0 else delta)
    for upper,knee,foot in legs:
        if parents[upper]!=hips or parents[knee]!=upper or parents[foot]!=knee:
            raise ValueError('Unexpected leg hierarchy')
        positions,orientations=world(t,q,parents)
        target=before[foot];h=positions[upper]
        k=solve_knee(h,target,before[knee],length(sub(before[knee],before[upper])),length(sub(before[foot],before[knee])))
        upper_world=qmul(between(sub(before[knee],before[upper]),sub(k,h)),old_rot[upper])
        q[upper]=unit(qmul(inv(orientations[parents[upper]]),upper_world))
        lower_world=qmul(between(sub(before[foot],before[knee]),sub(target,k)),old_rot[knee])
        q[knee]=unit(qmul(inv(upper_world),lower_world))
        q[foot]=unit(qmul(inv(lower_world),old_rot[foot]))
    after,after_rot=world(t,q,parents)
    errors=[length(sub(after[foot],before[foot])) for _,_,foot in legs]
    if max(errors)>1e-5:raise ValueError('Foot path changed during crouch solve')
    if any(abs(abs(dot(after_rot[foot],old_rot[foot]))-1)>1e-5 for _,_,foot in legs):
        raise ValueError('Foot orientation changed during crouch solve')
    return t,q,max(errors)


def sanitize_native(doc):
    """WolvenKit import preserves original events/root extraction by default.

    Remove these from its JSON roundtrip as well as disabling them in our graph.
    Compressed pose buffers are unchanged. Only the two inspected aliases pass.
    """
    result=copy.deepcopy(doc);root=result['Data']['RootChunk']
    if root['$type']!='animAnimSet' or root['rig']['DepotPath']['$value']!=r'base\characters\base_entities\woman_base\woman_base.rig':
        raise ValueError('Wrong native animation skeleton')
    entries=root['animations'];names=[e['Data']['animation']['Data']['name']['$value'] for e in entries]
    if names!=['cp_coop_stealth_idle_low_unarmed','cp_coop_stealth_walk_0']:raise ValueError('Wrong native animation aliases')
    for entry in entries:
        animation=entry['Data']['animation']['Data']
        if animation['animBuffer']['Data']['numJoints']!=71 or not 0<animation['duration']<=20:
            raise ValueError('Invalid native clip')
        entry['Data']['events']={'HandleRefId':'-1'}
        animation['motionExtraction']={'HandleRefId':'-1'}
    return result


def build(source:Path,output:Path,drop=0.25):
    if output.exists():raise ValueError('Choose a new private output file')
    repo=Path(__file__).resolve().parents[2]
    if repo in output.resolve().parents or any((p/'.git').exists() for p in output.resolve().parents):
        raise ValueError('Generated game data must stay outside Git')
    raw=source.read_bytes()
    if len(raw)>64*1024*1024 or struct.unpack_from('<III',raw)!=(0x46546c67,2,len(raw)):
        raise ValueError('Bounded GLB v2 required')
    size,kind=struct.unpack_from('<II',raw,12)
    if kind!=0x4e4f534a:raise ValueError('Missing JSON chunk')
    doc=json.loads(raw[20:20+size]);start=20+size
    binsize,kind=struct.unpack_from('<II',raw,start)
    if kind!=0x004e4942 or start+8+binsize!=len(raw):raise ValueError('One embedded BIN chunk required')
    binary=bytearray(raw[start+8:]);nodes=doc['nodes']
    if len(doc['buffers'])!=1 or 'uri' in doc['buffers'][0] or len(nodes)!=72 or len(doc['skins'])!=1 or len(doc['skins'][0]['joints'])!=71:
        raise ValueError('Inspected 71-joint NPC skeleton required')
    names={n['name']:i for i,n in enumerate(nodes)}
    if len(names)!=len(nodes):raise ValueError('Ambiguous skeleton node names')
    parents=[-1]*len(nodes)
    for i,n in enumerate(nodes):
        if 'matrix' in n or any(abs(s-1)>0.00002 for s in n.get('scale',[1,1,1])):raise ValueError('Unexpected skeleton scale/matrix')
        for child in n.get('children',[]):
            if parents[child]>=0:raise ValueError('Multiple skeleton parents')
            parents[child]=i
    hips=names['Hips'];legs=[tuple(names[side+x] for x in ('UpLeg','Leg','Foot')) for side in ('Left','Right')]
    selected={a['name']:a for a in doc['animations'] if a['name'] in ('idle_low_unarmed','walk_0')}
    if len(selected)!=2:raise ValueError('Expected inspected stealth animations')
    walking=selected['walk_0'];channels={}
    def accessor(index):
        a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']]
        count={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
        if a['componentType']!=5126 or 'sparse' in a or 'byteStride' in v or a['count']>2000:raise ValueError('Unexpected animation accessor')
        offset=v.get('byteOffset',0)+a.get('byteOffset',0)
        if offset<0 or offset+a['count']*count*4>len(binary):raise ValueError('Animation accessor out of bounds')
        return [tuple(struct.unpack_from('<'+'f'*count,binary,offset+i*count*4)) for i in range(a['count'])]
    used_samplers=set()
    for c in walking['channels']:
        key=(c['target']['node'],c['target']['path']);sampler=walking['samplers'][c['sampler']]
        if c['sampler'] in used_samplers or key in channels or key[1] not in ('translation','rotation') or sampler.get('interpolation','LINEAR') not in ('LINEAR','STEP'):
            raise ValueError('Unsupported/ambiguous animation channel')
        used_samplers.add(c['sampler'])
        times=[v[0] for v in accessor(sampler['input'])];values=accessor(sampler['output'])
        if len(times)!=len(values) or not times or any(not math.isfinite(v) for row in values for v in row) or any(not math.isfinite(v) for v in times) or any(a>=b for a,b in zip(times,times[1:])):
            raise ValueError('Invalid animation samples')
        channels[key]=(times,values,c)
    times=sorted({v for ts,_,_ in channels.values() for v in ts})
    if not 2<=len(times)<=500 or times[0]<0 or not 1<times[-1]<5:raise ValueError('Unexpected walk duration/sample count')
    modified={(hips,'translation'):[]}
    for leg in legs:
        for i in leg:modified[(i,'rotation')]=[]
    max_error=0
    def evaluate(key,time,default):
        if key not in channels:return default
        ts,vs,_=channels[key];index=max(0,min(len(ts)-1,bisect.bisect_right(ts,time)-1))
        if index==len(ts)-1 or walking['samplers'][channels[key][2]['sampler']].get('interpolation')=='STEP':return vs[index]
        fraction=(time-ts[index])/(ts[index+1]-ts[index])
        return slerp(vs[index],vs[index+1],fraction) if key[1]=='rotation' else add(mul(vs[index],1-fraction),mul(vs[index+1],fraction))
    for time in times:
        translations=[evaluate((i,'translation'),time,n.get('translation',[0,0,0])) for i,n in enumerate(nodes)]
        rotations=[evaluate((i,'rotation'),time,n.get('rotation',[0,0,0,1])) for i,n in enumerate(nodes)]
        t,q,error=lower_pose(translations,rotations,parents,hips,legs,drop);max_error=max(max_error,error)
        for key,values in modified.items():
            value=t[key[0]] if key[1]=='translation' else q[key[0]]
            if key[1]=='rotation' and values and dot(values[-1],value)<0:value=mul(value,-1)
            values.append(value)
    def append(values,kind):
        while len(binary)%4:binary.append(0)
        offset=len(binary)
        for value in values:binary.extend(struct.pack('<'+'f'*len(value),*value))
        view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(binary)-offset})
        result=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(values),'type':kind,
            'min':[min(v[i] for v in values) for i in range(len(values[0]))], 'max':[max(v[i] for v in values) for i in range(len(values[0]))]})
        return result
    time_accessor=append([(v,) for v in times],'SCALAR')
    for key,values in modified.items():
        if key not in channels:raise ValueError('Required baked channel missing')
        sampler=walking['samplers'][channels[key][2]['sampler']]
        sampler['interpolation']='LINEAR'
        sampler['input']=time_accessor;sampler['output']=append(values,'VEC3' if key[1]=='translation' else 'VEC4')
    for name,animation in selected.items():
        animation['name']='cp_coop_stealth_'+name
        animation['extras']['animEvents']=None
        animation['extras']['rootMotionType']='Unknown'
    doc['animations']=[selected['idle_low_unarmed'],walking]
    doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    binary.extend(b'\0'*((-len(binary))%4))
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
    print(json.dumps({'scope':'PRIVATE owned-game derivative; never distribute','pelvis_drop_m':drop,'frames':len(times),'max_foot_error_m':max_error,'output':str(output),'visual_validation':'pending'}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path);parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--drop',type=float,default=0.25)
    args=parser.parse_args();build(args.source,args.output,args.drop)
