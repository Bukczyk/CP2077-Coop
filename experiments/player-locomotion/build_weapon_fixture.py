"""Author an isolated passive Igla visual from verified local resource metadata.

No weapon object, damage, physics, AI, firing or reload behavior. Only authored
entity/reference-pose graph bytes are packed; game meshes and rigs are references.
The local action fixture and private action-clip cache are separate prerequisites.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

spec=importlib.util.spec_from_file_location('actions',Path(__file__).with_name('build_action_fixture.py'))
actions=importlib.util.module_from_spec(spec);spec.loader.exec_module(actions)
base=actions.base
ENTITY=r'base\cp2077coop\entities\player_weapon_igla_fixture.ent'
GRAPHS={name:rf'base\cp2077coop\animations\weapon_hand_{name.lower()}.animgraph' for name in ('Receiver','Barrel','Magazine')}
ROOT_BONES={'Receiver':'Root','Barrel':'barrel_plug','Magazine':'mag_plug'}
CONTROLLER='CP2077Coop_WeaponRestController'
SLOTS='CP2077Coop_WeaponSlots'
SLOT='CP2077Coop_WeaponRight'
RIGS={
    'Receiver':r'base\weapons\firearms\shotgun_dual\rig\w_shotgun_dual__rcv1.rig',
    'Barrel':r'base\weapons\firearms\shotgun_dual\rostovic_igla\rig\w_shotgun_dual__rostovic_igla__base1.rig',
    'Magazine':r'base\weapons\firearms\shotgun_dual\rostovic_satara\rig\w_shotgun_dual__rostovic_satara__mag_std.rig'}
MESHES=(
    (r'base\weapons\firearms\shotgun_dual\rostovic_igla\entities\meshes\w_shotgun_dual__rostovic_igla__base1_01.mesh','Barrel','pimp'),
    (r'base\weapons\firearms\shotgun_dual\rostovic_satara\entities\meshes\w_shotgun_dual__rostovic_satara__rcv1_01.mesh','Receiver','receiver'),
    (r'base\weapons\firearms\shotgun_dual\rostovic_satara\entities\meshes\w_shotgun_dual__rostovic_satara__mag_std_01_left_01.mesh','Magazine','default'),
    (r'base\weapons\firearms\shotgun_dual\rostovic_satara\entities\meshes\w_shotgun_dual__rostovic_satara__mag_std_01_right_01.mesh','Magazine','default'),
    (r'base\weapons\firearms\shotgun_dual\rostovic_satara\entities\meshes\w_shotgun_dual__rostovic_satara__rcv1_01_decal_n01_default.mesh','Receiver','default'))


def record(value):
    match=re.search(r'hash\s*=\s*0x([0-9a-fA-F]{8}),\s*length\s*=\s*(\d+)',value)
    if not match:raise ValueError('No exact native record observation')
    length=int(match[2]);hashed=int(match[1],16)
    if not 0<length<=255 or not hashed:raise ValueError('Invalid record identity')
    return (length<<32)|hashed


def recipe(sample):
    if record(sample['record'])!=(22<<32)|0xAC119774:raise ValueError('Only the verified Igla Pimp profile is supported')
    rows=sample['visuals']
    if not 1<=len(rows)<=128:raise ValueError('Unbounded or empty resource observation')
    rigs={row['name']:row['path'] for row in rows if row['kind']=='rig'}
    if any(rigs.get(name)!=path for name,path in RIGS.items()):raise ValueError('Wrong weapon skeleton references')
    selected=[]
    for path,parent,appearance in MESHES:
        matches=[row for row in rows if row['kind']=='skinned' and row['path']==path and row['enabled'] is True]
        if len(matches)!=1:raise ValueError('Required weapon part missing or ambiguous')
        row=matches[0]
        if row['skin']!=parent or row['parent']!=parent or row.get('slot') not in ('None',''):
            raise ValueError('Unexpected weapon part binding')
        if row['mask']!='18446744073709551615':raise ValueError('Unsupported masked weapon variant')
        selected.append(copy.deepcopy(row))
    variant=selected[0]['appearance']
    if variant not in ('pimp1','pimp2') or selected[1]['appearance']!=variant+'_igla':
        raise ValueError('Unsupported or inconsistent material variant')
    if any(row['appearance']!='default' for row in selected[2:]):raise ValueError('Unsupported chamber/decal appearance')
    allowed={path for path,_,_ in MESHES}
    for row in rows:
        if row['kind']=='rig' or not row['enabled'] or row['path'] in allowed:continue
        if '_shadow' in row['path'] or row['path'].endswith('weapon_placeholder.mesh') or row.get('skin')=='MagazineReload':continue
        raise ValueError('Unsupported additional weapon part; do not substitute or omit it silently')
    return selected


def reference_graph(name):
    _,graph=base.sources()
    gr=graph['Data']['RootChunk']
    proto={v.get('$type'):copy.deepcopy(v) for v in base.walk(gr)}
    terminal={'HandleId':'2','Data':{'$type':'animAnimNode_ReferencePoseTerminator','id':4294967295}}
    parent={'HandleId':'3','Data':{'$type':'animAnimNode_ParentTransform','id':4294967295,
        'inputLink':{'$type':'animPoseLink','node':terminal},
        'mapping':[{'$type':'animAnimTransformMappingEntry','from':base.cname('WeaponRight'),'to':base.cname(ROOT_BONES[name])}]}}
    output=copy.deepcopy(proto['animAnimNode_Output']);output['node']={'$type':'animPoseLink','node':parent}
    root=copy.deepcopy(proto['animAnimNode_Root']);root['nodes']=[{'HandleId':'1','Data':output},{'HandleRefId':'2'},{'HandleRefId':'3'}]
    gr['nodesToInit']=[{'HandleId':'0','Data':root},{'HandleRefId':'1'},{'HandleRefId':'2'},{'HandleRefId':'3'}]
    gr['rootNode']={'HandleRefId':'0'}
    variables=copy.deepcopy(proto['animAnimVariableContainer'])
    for key,value in variables.items():
        if isinstance(value,list):variables[key]=[]
    gr['variables']={'HandleId':'4','Data':variables}
    return actions.inline_first_use(graph)


def sources(sample):
    selected=recipe(sample)
    entity,body_graph=actions.sources();actions.validate(entity,body_graph)
    er=entity['Data']['RootChunk'];components=er['components']
    animated=components[0];mesh=components[1+len(base.DETAIL_RIGS)];controller=components[-1]
    prototypes={v.get('$type'):copy.deepcopy(v) for v in base.walk(er)}
    next_id=max(int(v['HandleId']) for v in base.walk(er) if 'HandleId' in v)+100
    def binding(kind,target,slot=None):
        nonlocal next_id
        value=copy.deepcopy(prototypes[kind]);value['bindName']=base.cname(target)
        if slot is not None:value['slotName']=base.cname(slot)
        next_id+=1;return {'HandleId':str(next_id),'Data':value}
    slots={'$type':'entSlotComponent','name':base.cname(SLOTS),
        'localTransform':copy.deepcopy(mesh['localTransform']),
        'parentTransform':binding('entHardTransformBinding','root','None'),
        'slots':[{'$type':'entSlot','slotName':base.cname(SLOT),'boneName':base.cname('WeaponRight'),
            'relativePosition':{'$type':'Vector3','X':0,'Y':0,'Z':0},
            'relativeRotation':{'$type':'Quaternion','i':0,'j':0,'k':0,'r':1}}], 'fallbackSlots':[]}
    components.append(slots)
    for name,path in RIGS.items():
        part=copy.deepcopy(animated);part['name']=base.cname('CP2077WeaponRig_'+name)
        part['rig']=base.resource(path,'Obligatory');part['graph']=base.resource(GRAPHS[name],'Obligatory')
        part['parentTransform']=binding('entHardTransformBinding',SLOTS,SLOT)
        part['controlBinding']=binding('entAnimationControlBinding','root')
        part['animations']['gameplay']=[];part['animations']['cinematics']=[]
        part['animParameters']=[];components.append(part)
    for index,row in enumerate(selected):
        part=copy.deepcopy(mesh);part['name']=base.cname('CP2077WeaponMesh_'+str(index))
        part['mesh']=base.resource(row['path']);part['meshAppearance']=base.cname(row['appearance'])
        part['parentTransform']=binding('entHardTransformBinding','CP2077WeaponRig_'+row['skin'],'None')
        part['skinning']=binding('entSkinningBinding','CP2077WeaponRig_'+row['skin'])
        part['chunkMask']=row['mask'];part['acceptDismemberment']=0;part['isEnabled']=0
        part['forceLODLevel']=0;components.append(part)
    weapon_controller=copy.deepcopy(controller);weapon_controller['name']=base.cname(CONTROLLER)
    components.append(weapon_controller)
    for index,component in enumerate(components):component['id']=str(3600000000000000000+index)
    er['compiledData']['Data']['Chunks']=[copy.deepcopy(er['entity']['Data']),*copy.deepcopy(components)]
    er['compiledData']['Data']['CruidDict']={str(i):str(c.get('id','0')) for i,c in enumerate(er['compiledData']['Data']['Chunks'])}
    paths=sorted({v['DepotPath']['$value'] for c in components for v in base.walk(c) if isinstance(v.get('DepotPath'),dict)})
    er['resolvedDependencies']=[base.resource(path,'Soft') for path in paths]
    return entity,{name:reference_graph(name) for name in RIGS}


def validate(entity,graphs,sample):
    selected=recipe(sample);er=entity['Data']['RootChunk'];components=er['components']
    if er['entity']['Data']['$type']!='entEntity' or len(components)!=27:raise ValueError('Pure expected component set required')
    allowed={'entAnimatedComponent','entSkinnedMeshComponent','entAnimationControllerComponent','entSlotComponent'}
    if any(c['$type'] not in allowed for c in components):raise ValueError('Gameplay/physics component forbidden')
    ids=[c['id'] for c in components];names=[c['name']['$value'] for c in components]
    if len(set(ids))!=len(ids) or len(set(names))!=len(names):raise ValueError('Duplicate component identity')
    normalized=copy.deepcopy(entity);nr=normalized['Data']['RootChunk']
    nr['components']=nr['components'][:17];nr['compiledData']['Data']['Chunks']=nr['compiledData']['Data']['Chunks'][:18]
    actions.validate(normalized,actions.sources()[1])
    chunks=er['compiledData']['Data']['Chunks']
    if er['compiledData']['Data']['CruidDict']!={str(i):str(c.get('id','0')) for i,c in enumerate(chunks)}:
        raise ValueError('Wrong compiled component identity catalog')
    definitions={}
    for value in base.walk(er):
        if 'HandleId' in value:
            ident=value['HandleId']
            if ident in definitions and definitions[ident]!=value['Data']:raise ValueError('Conflicting binding handle')
            definitions[ident]=value['Data']
    def resolve(v):
        if isinstance(v,list):return [resolve(x) for x in v]
        if not isinstance(v,dict):return v
        if 'HandleId' in v or 'HandleRefId' in v:return resolve(definitions[v.get('HandleId',v.get('HandleRefId'))])
        return {k:resolve(x) for k,x in v.items()}
    if resolve(components)!=resolve(er['compiledData']['Data']['Chunks'][1:]):raise ValueError('Compiled component mismatch')
    for index,row in enumerate(selected):
        part=next(c for c in components if c['name']==base.cname('CP2077WeaponMesh_'+str(index)))
        if (part['mesh']!=base.resource(row['path']) or part['meshAppearance']!=base.cname(row['appearance'])
            or part['isEnabled']!=0 or part['chunkMask']!=row['mask']
            or resolve(part['skinning'])['bindName']!=base.cname('CP2077WeaponRig_'+row['skin'])
            or resolve(part['parentTransform'])['bindName']!=base.cname('CP2077WeaponRig_'+row['skin'])
            or resolve(part['parentTransform'])['slotName']!=base.cname('None')):
            raise ValueError('Unsafe or mismatched weapon part')
    for name,path in RIGS.items():
        part=next(c for c in components if c['name']==base.cname('CP2077WeaponRig_'+name))
        if part['rig']!=base.resource(path,'Obligatory') or part['graph']!=base.resource(GRAPHS[name],'Obligatory'):
            raise ValueError('Wrong passive weapon rig')
        if resolve(part['parentTransform'])['bindName']!=base.cname(SLOTS) or resolve(part['parentTransform'])['slotName']!=base.cname(SLOT):
            raise ValueError('Weapon is not mounted to its own body slot')
        if part['animations']['gameplay'] or part['animations']['cinematics']:raise ValueError('Weapon gameplay animations forbidden')
        if resolve(part['controlBinding'])['bindName']!=base.cname('root'):raise ValueError('Weapon pose must read its own body animation parent')
    slot=next(c for c in components if c['name']==base.cname(SLOTS))
    if (slot['slots'][0]['boneName']!=base.cname('WeaponRight') or len(slot['slots'])!=1
        or slot['slots'][0]['slotName']!=base.cname(SLOT)
        or resolve(slot['parentTransform'])['bindName']!=base.cname('root')):
        raise ValueError('Wrong body mount bone')
    controller=next(c for c in components if c['name']==base.cname(CONTROLLER))
    if controller['animDatabaseCollection']['animDatabases'] or controller['actionAnimDatabaseRef']['DepotPath']['$value']!='0':
        raise ValueError('Weapon action database forbidden')
    if set(graphs)!=set(RIGS):raise ValueError('Exact passive graph set required')
    for name,graph in graphs.items():
        gr=graph['Data']['RootChunk'];nodes=[v for v in base.walk(gr) if v.get('$type','').startswith('animAnimNode_')]
        if sorted(v['$type'] for v in nodes)!=['animAnimNode_Output','animAnimNode_ParentTransform','animAnimNode_ReferencePoseTerminator','animAnimNode_Root']:
            raise ValueError('Only reference pose with a body-parent transform is permitted')
        parent=next(v for v in nodes if v['$type']=='animAnimNode_ParentTransform')
        if parent['mapping']!=[{'$type':'animAnimTransformMappingEntry','from':base.cname('WeaponRight'),'to':base.cname(ROOT_BONES[name])}]:
            raise ValueError('Wrong body-to-weapon root mapping')
        graph_defs={v['HandleId']:v['Data'] for v in base.walk(gr) if 'HandleId' in v}
        def graph_data(handle):return graph_defs[handle.get('HandleId',handle.get('HandleRefId'))]
        output=graph_data(graph_data(gr['rootNode'])['nodes'][0])
        if (output['$type']!='animAnimNode_Output' or graph_data(output['node']['node']) is not parent
            or graph_data(parent['inputLink']['node'])['$type']!='animAnimNode_ReferencePoseTerminator'):
            raise ValueError('Disconnected body-to-weapon pose mapping')
        if any(gr[k] for k in ('useAnimCommands','useAnimCommandsForCrowd','useAnimStaticCommands')) or gr['animFeatures'] or gr['additionalAnimDatabases']:
            raise ValueError('Weapon graph gameplay behavior forbidden')


def build(wolvenkit,snapshot,output):
    if output.exists() or base.ROOT in output.resolve().parents:raise ValueError('Choose a new private output folder outside source')
    if hashlib.sha256(wolvenkit.read_bytes()).hexdigest()!='7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738':raise ValueError('Pinned WolvenKit required')
    if snapshot.stat().st_size>2*1024*1024:raise ValueError('Unbounded private snapshot input')
    samples=json.loads(snapshot.read_text());sample=next((s for s in samples if record(s['record'])==(22<<32)|0xAC119774),None)
    if sample is None:raise ValueError('No verified Igla snapshot')
    entity,graphs=sources(sample);validate(entity,graphs,sample)
    output.mkdir(parents=True);stage=output/'CP2077Coop_WeaponFixture';roundtrip=output/'roundtrip';roundtrip.mkdir()
    logs=[];hashes={}
    def run(*args):
        result=subprocess.run([str(wolvenkit),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        logs.append(result.stdout+result.stderr);(output/'build.log').write_text('\n'.join(logs),encoding='utf-8')
        if result.returncode:raise RuntimeError('Native weapon fixture build failed')
        return result.stdout
    for path,doc in [(ENTITY,entity),*((GRAPHS[name],graphs[name]) for name in RIGS)]:
        dest=stage/path.replace('\\','/');dest.parent.mkdir(parents=True,exist_ok=True)
        raw=output/(dest.name+'.json');raw.write_text(json.dumps(doc),encoding='utf-8')
        run('convert','deserialize',raw,'-o',dest.parent);hashes[path]=hashlib.sha256(dest.read_bytes()).hexdigest()
        run('convert','serialize',dest,'-o',roundtrip)
    validate(json.loads((roundtrip/'player_weapon_igla_fixture.ent.json').read_text()),
             {name:json.loads((roundtrip/(GRAPHS[name].rsplit('\\',1)[-1]+'.json')).read_text()) for name in RIGS},sample)
    packed=output/'out';packed.mkdir();run('pack',stage,'-o',packed);archive=packed/(stage.name+'.archive')
    if sorted(run('archive',archive,'--list').strip().splitlines())!=sorted((ENTITY,*GRAPHS.values())):raise ValueError('Unexpected packed resource')
    unpacked=output/'unpacked';unpacked.mkdir();run('unbundle',archive,'-o',unpacked)
    if any(hashlib.sha256((unpacked/path.replace('\\','/')).read_bytes()).hexdigest()!=sha for path,sha in hashes.items()):raise ValueError('Extracted payload mismatch')
    manifest={'scope':'isolated passive Igla fixture, not synchronized weapons; visual validation pending',
        'archive':str(archive),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'resources':hashes,'snapshot_sha256':hashlib.sha256(snapshot.read_bytes()).hexdigest(),
        'required_body_graph':actions.GRAPH,'bundled_vanilla_resources':[],'builder_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(manifest))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wolvenkit',required=True,type=Path);parser.add_argument('--snapshot',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();build(args.wolvenkit,args.snapshot,args.output)
