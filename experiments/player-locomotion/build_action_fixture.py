"""Author a separate render-only action fixture. Not connected multiplayer.

References a separately generated PRIVATE action-clip cache. This archive packs
only authored entity/graph resources; the cache must never be redistributed.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location('base_locomotion', Path(__file__).with_name('build_assets.py'))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
ENTITY = r'base\cp2077coop\entities\player_actions_fixture.ent'
GRAPH = r'base\cp2077coop\animations\player_actions_fixture.animgraph'
CACHE = tuple(r'base\cp2077coop\private\player_'+name+'.anims' for name in ('stealth','rifle','handgunboth'))
UPPER_BONES = ('Spine','Spine1','Spine2','Spine3','LeftShoulder','RightShoulder',
    'Neck','Neck1','Head','LeftArm','RightArm','LeftForeArm','RightForeArm',
    'LeftHand','RightHand','WeaponLeft','WeaponRight','LeftEye','RightEye') + tuple(
        side+'InHand'+finger for side in ('Left','Right') for finger in ('Thumb','Index','Middle','Ring','Pinky')) + tuple(
        side+'Hand'+finger+str(index) for side in ('Left','Right')
        for finger in ('Thumb','Index','Middle','Ring','Pinky') for index in (1,2,3)
        if finger!='Thumb' or index<3)
UPPER_CLIPS = tuple('cp_coop_'+profile+'_'+clip for profile in ('rifle','handgunboth')
    for clip in ('ovr_idle','ovr_walk','ovr_sprint','aim_ovr_idle','aim_ovr_walk'))


def sources():
    entity,graph=base.sources('full')
    base.validate(entity,graph,'full')
    er=entity['Data']['RootChunk']
    for components in (er['components'],er['compiledData']['Data']['Chunks'][1:]):
        a=components[0]
        a['graph']=base.resource(GRAPH,'Obligatory')
        for path in CACHE:
            setup=copy.deepcopy(a['animations']['gameplay'][0])
            setup['animSet']=base.resource(path)
            a['animations']['gameplay'].append(setup)
    er['resolvedDependencies'] += [base.resource(x,'Soft') for x in (GRAPH,*CACHE)]
    er['resolvedDependencies'] = [x for x in er['resolvedDependencies'] if x['DepotPath']['$value'] != base.GRAPH]
    gr=graph['Data']['RootChunk']
    definitions={v['HandleId']:v['Data'] for v in base.walk(gr) if 'HandleId' in v}
    next_id=max(map(int,definitions))+1
    def data(h): return definitions[h.get('HandleId',h.get('HandleRefId'))]
    root=data(gr['rootNode']);output=data(root['nodes'][0]);standing=output['node']
    proto={v.get('$type'):copy.deepcopy(v) for v in definitions.values()}
    new_nodes=[]
    def add(value,is_node=True):
        nonlocal next_id
        handle={'HandleId':str(next_id),'Data':value};next_id+=1
        definitions[handle['HandleId']]=value
        if is_node:new_nodes.append(handle)
        return {'HandleRefId':handle['HandleId']} if is_node else handle
    def link(h,kind='animPoseLink'):return {'$type':kind,'node':h}
    variables=data(gr['variables'])
    def variable(name,maximum):
        value=copy.deepcopy(proto['animAnimVariableFloat'])
        value['name']=base.cname(name);value.update(min=0,max=maximum,default=0,value=0)
        variables['floatVariables'].append(add(value,False))
        reader=copy.deepcopy(proto['animAnimNode_FloatVariable']);reader['variableName']=base.cname(name)
        return add(reader)
    stance=variable('cp_coop_stance',1)
    moving=variable('cp_coop_crouch_motion',1)
    weapon=variable('cp_coop_weapon_pose',len(UPPER_CLIPS)-1)
    weight=variable('cp_coop_weapon_weight',1)
    progress=next({'HandleRefId':k} for k,v in definitions.items()
        if v.get('$type')=='animAnimNode_FloatVariable' and v['variableName']==base.cname('cp_coop_loco_progress'))
    def clip(name,sampled=False):
        value=copy.deepcopy(proto['animAnimNode_SkFrameAnim' if sampled else 'animAnimNode_SkAnim'])
        value['animation']=base.cname(name);value['isLooped']=int(not sampled)
        for key in ('applyMotion','collectEvents','fireAnimLoopEvent','resume'):value[key]=0
        if sampled:
            value['progressLink']=link(progress,'animFloatLink')
            for key in ('timeLink','frameLink'):value[key]={'$type':'animFloatLink','node':None}
        return link(add(value))
    def switch(inputs,reader):
        value=copy.deepcopy(proto['animAnimNode_Switch'])
        value.update(inputNodes=inputs,numInputs=len(inputs),blendTime=0.08,weightNode=link(reader,'animFloatLink'))
        return link(add(value))
    crouch=switch([clip('cp_coop_stealth_idle_low_unarmed'),clip('cp_coop_stealth_walk_0',True)],moving)
    lower=switch([standing,crouch],stance)
    upper=switch([clip(name) for name in UPPER_CLIPS],weapon)
    override={'$type':'animAnimNode_BlendOverride','id':4294967295,
        'inputNode':lower,'overrideInputNode':upper,'weightNode':link(weight,'animFloatLink'),
        'bones':[{'$type':'animOverrideBlendBoneInfo','transformIndex':{'$type':'animTransformIndex','name':base.cname(name)},'weight':1}
                 for name in UPPER_BONES],
        'blendAllTracks':0,'blendTrackMode':'AGBT_Interpolate','tracks':[],
        'getDeltaMotionFromOverride':0,'timeWarpingEnabled':0,'syncMethod':None,'blendMethod':None,'postProcess':None}
    output['node']=link(add(override))
    root['nodes'] += new_nodes
    gr['nodesToInit'] += [{'HandleRefId':h['HandleId']} for h in new_nodes]
    # WolvenKit's JSON reader resolves references as it reads, so definitions
    # must occur at first use rather than later in the root registration list.
    graph=inline_first_use(graph)
    return entity,graph


def inline_first_use(doc):
    definitions={v['HandleId']:v['Data'] for v in base.walk(doc) if 'HandleId' in v}
    emitted=set()
    def visit(value):
        if isinstance(value,list):return [visit(v) for v in value]
        if not isinstance(value,dict):return value
        if 'HandleId' in value or 'HandleRefId' in value:
            ident=value.get('HandleId',value.get('HandleRefId'))
            if ident in emitted:return {'HandleRefId':ident}
            emitted.add(ident)
            return {'HandleId':ident,'Data':visit(definitions[ident])}
        return {k:visit(v) for k,v in value.items()}
    return visit(doc)


def validate(entity,graph):
    er=entity['Data']['RootChunk'];gr=graph['Data']['RootChunk']
    # Reuse the base profile's binding/LOD/no-AI checks without weakening them.
    normalized=copy.deepcopy(entity)
    for components in (normalized['Data']['RootChunk']['components'],normalized['Data']['RootChunk']['compiledData']['Data']['Chunks'][1:]):
        animated=components[0]
        if [s['animSet'] for s in animated['animations']['gameplay'][-3:]] != [base.resource(x) for x in CACHE]:
            raise ValueError('Private clip cache references missing')
        animated['animations']['gameplay']=animated['animations']['gameplay'][:-3]
        animated['graph']=base.resource(base.GRAPH,'Obligatory')
    base.validate(normalized,base.sources('full')[1],'full')
    if er['entity']['Data']['$type']!='entEntity':raise ValueError('Pure entity required')
    allowed={'entAnimatedComponent','entSkinnedMeshComponent','entAnimationControllerComponent'}
    if any(c['$type'] not in allowed for c in er['components']):raise ValueError('Gameplay component forbidden')
    if er['components'][0]['graph']!=base.resource(GRAPH,'Obligatory'):raise ValueError('Wrong action graph')
    definitions={}
    for value in base.walk(gr):
        if 'HandleId' in value:
            if value['HandleId'] in definitions:raise ValueError('Duplicate graph handle')
            definitions[value['HandleId']]=value['Data']
    if any(v['HandleRefId'] not in definitions for v in base.walk(gr) if 'HandleRefId' in v):
        raise ValueError('Unresolved graph handle')
    def data(h):return definitions[h.get('HandleId',h.get('HandleRefId'))]
    root=data(gr['rootNode']);output=data(root['nodes'][0])
    if root['$type']!='animAnimNode_Root' or output['$type']!='animAnimNode_Output':raise ValueError('Wrong active root/output')
    variables=data(gr['variables'])['floatVariables']
    expected=[('cp_coop_loco_phase',5),('cp_coop_loco_progress',1),('cp_coop_stance',1),
        ('cp_coop_crouch_motion',1),('cp_coop_weapon_pose',len(UPPER_CLIPS)-1),('cp_coop_weapon_weight',1)]
    if [(data(v)['name']['$value'],data(v)['max']) for v in variables]!=expected:
        raise ValueError('Wrong action variables')
    if any(data(v)[k]!=0 for v in variables for k in ('min','default','value')):
        raise ValueError('Non-neutral action defaults')
    for value in definitions.values():
        if value.get('$type') in ('animAnimNode_SkAnim','animAnimNode_SkFrameAnim'):
            if any(value[k] for k in ('applyMotion','collectEvents','fireAnimLoopEvent','resume')):
                raise ValueError('Gameplay/root motion forbidden')
    overrides=[v for v in definitions.values() if v.get('$type')=='animAnimNode_BlendOverride']
    if len(overrides)!=1:raise ValueError('One upper-body overlay required')
    overlay=overrides[0]
    if data(output['node']['node']) is not overlay:raise ValueError('Upper-body layer disconnected')
    if (overlay['getDeltaMotionFromOverride'] or overlay['blendAllTracks']
        or [v['transformIndex']['name']['$value'] for v in overlay['bones']]!=list(UPPER_BONES)
        or any(v['weight']!=1 for v in overlay['bones'])):raise ValueError('Unsafe upper-body mask')
    if data(overlay['weightNode']['node'])['variableName']!=base.cname('cp_coop_weapon_weight'):
        raise ValueError('Wrong overlay weight')
    stance=data(overlay['inputNode']['node']);upper=data(overlay['overrideInputNode']['node'])
    def selector(value,name,count):
        if (value['$type']!='animAnimNode_Switch' or value['numInputs']!=count
            or len(value['inputNodes'])!=count or abs(value['blendTime']-0.08)>0.000001
            or data(value['weightNode']['node'])['variableName']!=base.cname(name)):
            raise ValueError('Wrong action selector')
    selector(stance,'cp_coop_stance',2);selector(upper,'cp_coop_weapon_pose',len(UPPER_CLIPS))
    standing=data(stance['inputNodes'][0]['node']);crouch=data(stance['inputNodes'][1]['node'])
    selector(standing,'cp_coop_loco_phase',len(base.CLIPS));selector(crouch,'cp_coop_crouch_motion',2)
    for switch,names in [(standing,base.CLIPS),(crouch,('cp_coop_stealth_idle_low_unarmed','cp_coop_stealth_walk_0')),(upper,UPPER_CLIPS)]:
        if [data(link['node'])['animation']['$value'] for link in switch['inputNodes']]!=list(names):
            raise ValueError('Wrong animation names')
    nodes={k for k,v in definitions.items() if v.get('$type','').startswith('animAnimNode_')}
    init=[v.get('HandleId',v.get('HandleRefId')) for v in gr['nodesToInit']]
    if set(init)!=nodes or len(init)!=len(nodes):raise ValueError('Incomplete graph initialization')
    registered=[v.get('HandleId',v.get('HandleRefId')) for v in root['nodes']]
    if set(registered)!=nodes-{gr['rootNode'].get('HandleId',gr['rootNode'].get('HandleRefId'))} or len(registered)!=len(nodes)-1:
        raise ValueError('Incomplete root node registration')
    if gr['animFeatures'] or gr['additionalAnimDatabases'] or any(gr[k] for k in ('useAnimCommands','useAnimCommandsForCrowd','useAnimStaticCommands')):
        raise ValueError('Gameplay graph command execution forbidden')


def build(wolvenkit,output):
    if output.exists():raise ValueError('Choose a new output folder')
    if hashlib.sha256(wolvenkit.read_bytes()).hexdigest()!='7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738':
        raise ValueError('Pinned WolvenKit required')
    entity,graph=sources();validate(entity,graph)
    output.mkdir(parents=True);stage=output/'CP2077Coop_ActionFixture';records={};logs=[]
    def run(*args):
        result=subprocess.run([str(wolvenkit),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        logs.append(result.stdout+result.stderr);(output/'build.log').write_text('\n'.join(logs),encoding='utf-8')
        if result.returncode:raise RuntimeError('Native fixture build failed; see build.log')
        return result.stdout
    roundtrip=output/'roundtrip';roundtrip.mkdir()
    for path,doc in ((ENTITY,entity),(GRAPH,graph)):
        dest=stage/path.replace('\\','/');dest.parent.mkdir(parents=True,exist_ok=True)
        raw=output/(dest.name+'.json');raw.write_text(json.dumps(doc),encoding='utf-8')
        run('convert','deserialize',raw,'-o',dest.parent)
        records[path]=hashlib.sha256(dest.read_bytes()).hexdigest()
        run('convert','serialize',dest,'-o',roundtrip)
    validate(json.loads((roundtrip/'player_actions_fixture.ent.json').read_text()),
             json.loads((roundtrip/'player_actions_fixture.animgraph.json').read_text()))
    packed=output/'out';packed.mkdir();run('pack',stage,'-o',packed)
    archive=packed/(stage.name+'.archive')
    if sorted(run('archive',archive,'--list').strip().splitlines())!=sorted((ENTITY,GRAPH)):
        raise ValueError('Unexpected fixture archive content')
    unpacked=output/'unpacked';unpacked.mkdir();run('unbundle',archive,'-o',unpacked)
    if any(hashlib.sha256((unpacked/path.replace('\\','/')).read_bytes()).hexdigest()!=sha for path,sha in records.items()):
        raise ValueError('Extracted fixture payload mismatch')
    manifest={'scope':'local render-only pose fixture, not synchronized actions',
        'archive':str(archive),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'resources':records,'required_private_cache':list(CACHE),'bundled_vanilla_resources':[],
        'builder_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'visual_validation':'pending'}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(manifest))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wolvenkit',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();build(args.wolvenkit,args.output)
