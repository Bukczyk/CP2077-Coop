"""Isolated standing directions or forward/backward crouch. No wire change.

Packs only authored references. Its separately generated, game-derived cache
must remain private and must not replace the existing action-cache archive.
"""
from __future__ import annotations
import argparse,copy,hashlib,importlib.util,json,subprocess
from pathlib import Path

spec=importlib.util.spec_from_file_location('direction_base',Path(__file__).with_name('build_assets.py'))
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
ENTITY=r'base\cp2077coop\entities\player_direction_fixture.ent'
GRAPH=r'base\cp2077coop\animations\player_direction_fixture.animgraph'
CACHE=r'base\cp2077coop\private\player_directional.anims'
CLIPS=tuple('cp_coop_directional_'+s for s in ('idle_stand','walk_0','walk_090','walk_180','walk_270','sprint_0'))
# Measured2.31 motion-extraction endpoints, metres per cycle. Graph root motion
# is disabled; these are fixture timing references, not movement authority.
DISTANCES=(0,5.960565090179443,5.90962028503418,1.6499662399291992,1.7075181007385254,3.064943552017212)

def recipe(profile):
    if profile=='standing':return ENTITY,GRAPH,CACHE,CLIPS,DISTANCES,'CP2077Coop_DirectionFixture'
    if profile!='crouch':raise ValueError('Unknown isolated direction profile')
    idle='cp_coop_stealth_idle_low_unarmed'
    return (r'base\cp2077coop\entities\player_crouch_direction_fixture.ent',
        r'base\cp2077coop\animations\player_crouch_direction_fixture.animgraph',
        (r'base\cp2077coop\private\player_stealth.anims',r'base\cp2077coop\private\player_crouch_backward.anims'),
        (idle,'cp_coop_stealth_walk_0','cp_coop_crouch_backward_walk_180',idle,idle,idle),
        (0,6.249844074249268,3.992504835128784,0,0,0),'CP2077Coop_CrouchDirectionFixture')

def selectors(graph):
    defs={v['HandleId']:v['Data'] for v in base.walk(graph) if 'HandleId' in v}
    data=lambda h:defs[h.get('HandleId',h.get('HandleRefId'))]
    switch=next(v for v in defs.values() if v.get('$type')=='animAnimNode_Switch')
    return switch,[data(h['node']) for h in switch['inputNodes']]

def sources(profile='standing'):
    entity_path,graph_path,cache,clip_names,_,_=recipe(profile)
    caches=(cache,) if isinstance(cache,str) else cache
    entity,graph=base.sources('full');base.validate(entity,graph,'full')
    er=entity['Data']['RootChunk']
    for components in (er['components'],er['compiledData']['Data']['Chunks'][1:]):
        a=components[0];a['graph']=base.resource(graph_path,'Obligatory')
        for path in caches:
            setup=copy.deepcopy(a['animations']['gameplay'][0]);setup['animSet']=base.resource(path)
            a['animations']['gameplay'].append(setup)
    er['resolvedDependencies']=[base.resource(graph_path,x['Flags']) if x['DepotPath']['$value']==base.GRAPH else x
                                for x in er['resolvedDependencies']]+[base.resource(path,'Soft') for path in caches]
    switch,clips=selectors(graph);switch['blendTime']=0
    for clip,name in zip(clips,clip_names):clip['animation']=base.cname(name)
    return entity,graph

def validate(entity,graph,profile='standing'):
    _,graph_path,cache,clip_names,_,_=recipe(profile)
    caches=(cache,) if isinstance(cache,str) else cache
    e,g=copy.deepcopy(entity),copy.deepcopy(graph);er=e['Data']['RootChunk']
    for components in (er['components'],er['compiledData']['Data']['Chunks'][1:]):
        a=components[0]
        if (a['graph']!=base.resource(graph_path,'Obligatory') or len(a['animations']['gameplay'])!=2+len(caches)
            or [v['animSet'] for v in a['animations']['gameplay'][-len(caches):]]!=[base.resource(path) for path in caches]):
            raise ValueError('Wrong isolated direction graph/cache')
        a['graph']=base.resource(base.GRAPH,'Obligatory');a['animations']['gameplay']=a['animations']['gameplay'][:-len(caches)]
    if any(er['resolvedDependencies'].count(base.resource(path,'Soft'))!=1 for path in caches):raise ValueError('Ambiguous direction cache')
    er['resolvedDependencies']=[base.resource(base.GRAPH,x['Flags']) if x['DepotPath']['$value']==graph_path else x
                                for x in er['resolvedDependencies'] if x['DepotPath']['$value'] not in caches]
    switch,clips=selectors(g)
    if switch['blendTime']!=0 or [v['animation']['$value'] for v in clips]!=list(clip_names):
        raise ValueError('Wrong direction selector or engine-time blending')
    switch['blendTime']=.08
    for clip,name in zip(clips,base.CLIPS):clip['animation']=base.cname(name)
    # Preserve all existing full-model, graph-binding, root-motion/event and
    # command-execution checks after normalizing only this explicit recipe.
    base.validate(e,g,'full')

def build(wolvenkit,output,profile='standing'):
    entity_path,graph_path,cache,clip_names,distances,archive_name=recipe(profile)
    if output.exists() or base.ROOT in output.resolve().parents:raise ValueError('Choose a new private output folder')
    if hashlib.sha256(wolvenkit.read_bytes()).hexdigest()!='7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738':
        raise ValueError('Pinned WolvenKit required')
    entity,graph=sources(profile);validate(entity,graph,profile)
    output.mkdir(parents=True);stage=output/archive_name;roundtrip=output/'roundtrip';roundtrip.mkdir()
    logs=[];hashes={}
    def run(*args):
        result=subprocess.run([str(wolvenkit),*map(str,args)],capture_output=True,text=True,encoding='utf-8',errors='replace')
        logs.append(result.stdout+result.stderr);(output/'build.log').write_text('\n'.join(logs))
        if result.returncode:raise RuntimeError('Native direction fixture failed; see private build.log')
        return result.stdout
    for path,doc in [(entity_path,entity),(graph_path,graph)]:
        target=stage/path.replace('\\','/');target.parent.mkdir(parents=True,exist_ok=True)
        raw=output/(target.name+'.json');raw.write_text(json.dumps(doc))
        run('convert','deserialize',raw,'-o',target.parent);hashes[path]=hashlib.sha256(target.read_bytes()).hexdigest()
        run('convert','serialize',target,'-o',roundtrip)
    validate(json.loads((roundtrip/(entity_path.rsplit('\\',1)[-1]+'.json')).read_text()),
             json.loads((roundtrip/(graph_path.rsplit('\\',1)[-1]+'.json')).read_text()),profile)
    packed=output/'out';packed.mkdir();run('pack',stage,'-o',packed);archive=packed/(stage.name+'.archive')
    if sorted(run('archive',archive,'--list').strip().splitlines())!=sorted((entity_path,graph_path)):raise ValueError('Unexpected authored inventory')
    unpacked=output/'unpacked';unpacked.mkdir();run('unbundle',archive,'-o',unpacked)
    if any(hashlib.sha256((unpacked/path.replace('\\','/')).read_bytes()).hexdigest()!=sha for path,sha in hashes.items()):
        raise ValueError('Unpacked resource mismatch')
    manifest={'scope':'PRIVATE isolated directional clip test, not production direction synchronization',
        'archive':str(archive),'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
        'resources':hashes,'profile':profile,'required_private_cache':cache,'clips':clip_names,'metres_per_cycle':distances,
        'bundled_vanilla_resources':[],'visual_validation':'pending'}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2));print(json.dumps(manifest))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--wolvenkit',required=True,type=Path)
    p.add_argument('--output',required=True,type=Path);p.add_argument('--profile',choices=('standing','crouch'),default='standing')
    a=p.parse_args();build(a.wolvenkit,a.output,a.profile)
