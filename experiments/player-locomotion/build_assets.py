"""Build an isolated no-AI locomotion asset from our authored encounter resource.

Not a package or production selection. Only authored entity/graph bytes are packed;
mesh, skeleton and animation sets are references to the installed game.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENTITY = r'base\cp2077coop\entities\cp2077coop_player_locomotion.ent'
GRAPH = r'base\cp2077coop\animations\player_locomotion.animgraph'
SETS = tuple(r'base\animations\npc\gameplay\woman_average\gang\unarmed\wa_gang_unarmed_' + s + '.anims'
             for s in ('locomotion_relaxed', 'exploration_relaxed'))
CLIPS = ('idle_stand', 'walk_0', 'sprint_0', 'jump_walk_loop', 'jump_walk_recover', 'jump_walk_startup')
CONTROLLER = 'CP2077Coop_LocomotionController'

def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values(): yield from walk(child)
    elif isinstance(value, list):
        for child in value: yield from walk(child)

def cname(value): return {'$type':'CName', '$storage':'string', '$value':value}
def resource(value, flags='Default'):
    return {'DepotPath':{'$type':'ResourcePath','$storage':'string','$value':value},'Flags':flags}

def validate(entity, graph):
    """Validate native wiring as well as the no-AI/no-root-motion boundary."""
    def require(value, message):
        if not value: raise ValueError(message)
    for doc in (entity, graph):
        require(doc['Data']['EmbeddedFiles']==[], 'No embedded resources')
    er=entity['Data']['RootChunk']; gr=graph['Data']['RootChunk']
    require(er['entity']['Data']['$type']=='entEntity','Pure entity required')
    types=['entAnimatedComponent','entSkinnedMeshComponent','entAnimationControllerComponent']
    require([v['$type'] for v in er['components']]==types,'Unexpected template components')
    require([v['$type'] for v in er['compiledData']['Data']['Chunks']]==['entEntity',*types],
            'Unexpected compiled components')
    definitions={}
    for v in walk(er):
        if 'HandleId' in v:
            k=v['HandleId']
            require(k not in definitions or definitions[k]==v['Data'],'Conflicting entity handle')
            definitions[k]=v['Data']
    def resolve(v):
        if isinstance(v,list): return [resolve(x) for x in v]
        if not isinstance(v,dict): return v
        if 'HandleId' in v or 'HandleRefId' in v:
            return resolve(definitions[v.get('HandleId',v.get('HandleRefId'))])
        return {k:resolve(x) for k,x in v.items()}
    require(resolve(er['components'])==resolve(er['compiledData']['Data']['Chunks'][1:]),
            'Template/compiled component mismatch')
    for a,mesh,c in (er['components'],er['compiledData']['Data']['Chunks'][1:]):
        require(a['graph']==resource(GRAPH,'Obligatory'),'Wrong animation graph')
        require(a['rig']==resource(r'base\characters\base_entities\woman_base\woman_base.rig','Obligatory'),'Wrong rig')
        require(mesh['mesh']==resource(r'base\characters\appearances\main_npc\proxy\judy_default\judy_default.mesh'),
                'Wrong model reference')
        require(resolve(a['controlBinding'])['bindName']==cname(CONTROLLER)
                and c['name']==cname(CONTROLLER),'Controller not bound to graph')
        require(c['animDatabaseCollection']['animDatabases']==[]
                and c['actionAnimDatabaseRef']['DepotPath']['$value']=='0','No action/AI database')
        require([v['animSet'] for v in a['animations']['gameplay']]==[resource(x) for x in SETS],
                'Unexpected installed animation references')
        require(a['animations']['cinematics']==[],'No cinematic behavior')
    hs={}
    for v in walk(gr):
        if 'HandleId' in v:
            require(v['HandleId'] not in hs,'Duplicate graph handle definition')
            hs[v['HandleId']]=v['Data']
    for v in walk(gr):
        if 'HandleRefId' in v:require(v['HandleRefId'] in hs,'Unresolved graph handle')
    def data(h):return hs[h.get('HandleId',h.get('HandleRefId'))]
    nodes=[v for v in hs.values() if v.get('$type','').startswith('animAnimNode_')]
    require(len(nodes)==11,'Unexpected graph topology')
    root=data(gr['rootNode']);output=data(root['nodes'][0]);switch=data(output['node']['node'])
    require(root['$type']=='animAnimNode_Root' and output['$type']=='animAnimNode_Output'
            and switch['$type']=='animAnimNode_Switch','Wrong active output path')
    require(len(root['nodes'])==10 and {id(data(h)) for h in root['nodes']}=={id(n) for n in nodes if n is not root},
            'Root omits or duplicates graph nodes')
    require(len(gr['nodesToInit'])==len(nodes)
            and {id(data(h)) for h in gr['nodesToInit']}=={id(n) for n in nodes},'Wrong initialized nodes')
    require(switch['numInputs']==6 and len(switch['inputNodes'])==6
            and abs(switch['blendTime']-0.08)<0.000001,'Wrong selector size/blend')
    require(data(switch['weightNode']['node'])['variableName']==cname('cp_coop_loco_phase'),'Wrong pose selector')
    clips=[data(h['node']) for h in switch['inputNodes']]
    require([c['animation']['$value'] for c in clips]==list(CLIPS),'Wrong clip selection')
    for i,c in enumerate(clips):
        require(c['$type']==('animAnimNode_SkAnim' if i==0 else 'animAnimNode_SkFrameAnim'),'Wrong clip sampling')
        require(all(c[k]==0 for k in ('applyMotion','collectEvents','fireAnimLoopEvent','resume')),
                'Root motion and gameplay animation events forbidden')
        require(c['isLooped']==int(i==0),'Only neutral idle loops')
        if i:require(data(c['progressLink']['node'])['variableName']==cname('cp_coop_loco_progress'),
                     'Wrong sampled progress reader')
    variables=[data(h) for h in data(gr['variables'])['floatVariables']]
    require([(v['name']['$value'],v['min'],v['max'],v['default'],v['value']) for v in variables]
            ==[('cp_coop_loco_phase',0,5,0,0),('cp_coop_loco_progress',0,1,0,0)],'Unsafe variable defaults')
    require(gr['animFeatures']==[] and gr['additionalAnimDatabases']==[]
            and all(gr[k]==0 for k in ('useAnimCommands','useAnimCommandsForCrowd','useAnimStaticCommands')),
            'No gameplay graph features or command execution')
def sources():
    original = ROOT/'experiments/shared-encounter/assets/raw/base/cp2077coop'
    e = json.loads((original/'entities/cp2077coop_networkhumanoid_encounter.ent.json').read_text())
    g = json.loads((original/'animations/networkhumanoid_encounter.animgraph.json').read_text())
    er = e['Data']['RootChunk']
    for components in (er['components'], er['compiledData']['Data']['Chunks'][1:]):
        animated, _, controller = components
        animated['graph'] = resource(GRAPH,'Obligatory')
        if 'Data' in animated['controlBinding']:
            animated['controlBinding']['Data']['bindName'] = cname(CONTROLLER)
        setup = copy.deepcopy(animated['animations']['gameplay'][0])
        animated['animations']['gameplay'] = []
        for path in SETS:
            item=copy.deepcopy(setup); item['animSet']=resource(path)
            animated['animations']['gameplay'].append(item)
        controller['name']=cname(CONTROLLER)
    er['resolvedDependencies'] = [resource(x,'Soft') for x in (
        er['components'][1]['mesh']['DepotPath']['$value'], GRAPH, *SETS)]
    gr=g['Data']['RootChunk']
    proto={}
    for value in walk(gr): proto.setdefault(value.get('$type'),copy.deepcopy(value))
    definitions={}; next_id=0
    def node(data):
        nonlocal next_id
        ident=str(next_id); next_id+=1; definitions[ident]=data
        return {'HandleId':ident,'Data':data}
    def ref(handle): return {'HandleRefId':handle['HandleId']}
    def link(handle, kind='animPoseLink'):return {'$type':kind,'node':handle}
    root=node(copy.deepcopy(proto['animAnimNode_Root']))
    output=node(copy.deepcopy(proto['animAnimNode_Output']))
    switch=node(copy.deepcopy(proto['animAnimNode_Switch']))
    pose=copy.deepcopy(proto['animAnimNode_FloatVariable']);pose['variableName']=cname('cp_coop_loco_phase')
    progress=copy.deepcopy(pose);progress['variableName']=cname('cp_coop_loco_progress')
    phase_node=node(pose); progress_node=node(progress)
    clips=[]
    for i,name in enumerate(CLIPS):
        clip=copy.deepcopy(proto['animAnimNode_SkAnim' if i==0 else 'animAnimNode_SkFrameAnim'])
        clip['animation']=cname(name);clip['isLooped']=int(i==0)
        for k in ('applyMotion','collectEvents','fireAnimLoopEvent','resume'):clip[k]=0
        if i:
            clip['progressLink']=link(progress_node if i==1 else ref(progress_node),'animFloatLink')
            clip['timeLink']={'$type':'animFloatLink','node':None}
            clip['frameLink']={'$type':'animFloatLink','node':None}
        clips.append(node(clip))
    switch['Data']['inputNodes']=[link(c) for c in clips]
    switch['Data']['numInputs']=len(clips);switch['Data']['blendTime']=0.08
    switch['Data']['weightNode']=link(phase_node,'animFloatLink')
    output['Data']['node']=link(switch)
    root['Data']['nodes']=[output]+[ref(definitions_handle) for definitions_handle in [switch,phase_node,progress_node,*clips]]
    gr['nodesToInit']=[root]+[{'HandleRefId':str(i)} for i in range(1,next_id)]
    gr['rootNode']=ref(root)
    # Definition of the progress reader was inserted before its first reference.
    # Its root-list entry must be a reference, as are all nodes outside output.
    variables=copy.deepcopy(gr['variables']['Data']); variable_proto=copy.deepcopy(variables['floatVariables'][0]['Data'])
    variables['floatVariables']=[]
    for name,maximum in [('cp_coop_loco_phase',len(CLIPS)-1),('cp_coop_loco_progress',1)]:
        v=copy.deepcopy(variable_proto);v['name']=cname(name);v.update(value=0,default=0,min=0,max=maximum)
        variables['floatVariables'].append(node(v))
    gr['variables']=node(variables)
    return e,g

def build(wolvenkit,output):
    if output.exists(): raise ValueError('Choose a new output folder')
    if hashlib.sha256(wolvenkit.read_bytes()).hexdigest()!='7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738':
        raise ValueError('Pinned official WolvenKit 9.0.1 required')
    output.mkdir(parents=True); stage=output/'CP2077Coop_PlayerLocomotion'; packed=output/'out';packed.mkdir()
    logs=[]; binary_hashes={}
    def run(*args):
        r=subprocess.run([str(wolvenkit),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        logs.append(r.stdout+r.stderr);(output/'build.log').write_text('\n'.join(logs),encoding='utf-8')
        if r.returncode:raise RuntimeError('WolvenKit failed; see build.log')
        return r.stdout
    e,g=sources()
    validate(e,g)
    input_paths=[pathlib.Path(__file__), *(
        ROOT/'experiments/shared-encounter/assets/raw/base/cp2077coop'/p
        for p in ['entities/cp2077coop_networkhumanoid_encounter.ent.json',
                  'animations/networkhumanoid_encounter.animgraph.json'])]
    source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in input_paths}
    for path,doc in [(ENTITY,e),(GRAPH,g)]:
        rel=pathlib.Path(path.replace('\\','/')); raw=output/'raw'/(str(rel)+'.json');raw.parent.mkdir(parents=True,exist_ok=True)
        raw.write_text(json.dumps(doc,indent=2)+'\n',encoding='utf-8')
        dest=stage/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        run('convert','deserialize',raw,'-o',dest.parent)
        if not dest.is_file():raise RuntimeError('No binary '+str(dest))
        binary_hashes[path]=hashlib.sha256(dest.read_bytes()).hexdigest()
    roundtrip=output/'roundtrip';roundtrip.mkdir()
    for path in (ENTITY,GRAPH):
        run('convert','serialize',stage/path.replace('\\','/'),'-o',roundtrip)
    validate(json.loads((roundtrip/'cp2077coop_player_locomotion.ent.json').read_text()),
             json.loads((roundtrip/'player_locomotion.animgraph.json').read_text()))
    run('pack',stage,'-o',packed)
    archive=packed/(stage.name+'.archive')
    listing=run('archive',archive,'--list').strip().splitlines()
    if sorted(listing)!=sorted((ENTITY,GRAPH)):raise RuntimeError('Unexpected packed files '+repr(listing))
    unpack=output/'unpacked';unpack.mkdir();run('unbundle',archive,'-o',unpack)
    for path in (ENTITY,GRAPH):
        f=unpack/path.replace('\\','/')
        if hashlib.sha256(f.read_bytes()).hexdigest()!=binary_hashes[path]:raise RuntimeError('Payload mismatch')
    record={'scope':'isolated local fixture, not a release or verified animation fix',
        'archive':str(archive),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'resources':binary_hashes,'clips':CLIPS,'bundled_vanilla_resources':[],
        'source_sha256':source_hashes,'roundtrip_native_contract':'PASS'}
    (output/'manifest.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--wolvenkit',required=True,type=pathlib.Path)
    p.add_argument('--output-dir',required=True,type=pathlib.Path);a=p.parse_args();build(a.wolvenkit,a.output_dir)
