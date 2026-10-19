"""Catch unsafe native graph wiring before a local game loads the asset."""
import copy
import importlib.util
from pathlib import Path

root=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('locomotion_assets',root/'experiments/player-locomotion/build_assets.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
entity,graph=m.sources();m.validate(entity,graph)
def rejects(change):
    e,g=copy.deepcopy(entity),copy.deepcopy(graph)
    change(e,g)
    try:m.validate(e,g)
    except (ValueError,KeyError):return
    raise AssertionError('Unsafe mutation accepted')
def node(graph,kind):
    return next(v for v in m.walk(graph) if v.get('$type')==kind)
rejects(lambda e,g:node(g,'animAnimNode_SkFrameAnim').update(applyMotion=1))
rejects(lambda e,g:node(g,'animAnimNode_SkAnim').update(collectEvents=1))
rejects(lambda e,g:node(g,'animAnimNode_Switch').update(numInputs=5))
rejects(lambda e,g:node(g,'animAnimNode_FloatVariable').update(variableName=m.cname('wrong')))
rejects(lambda e,g:e['Data']['RootChunk']['compiledData']['Data']['Chunks'].append({'$type':'gameAIComponent'}))
rejects(lambda e,g:e['Data']['RootChunk']['entity']['Data'].update({'$type':'gameNPCPuppet'}))
rejects(lambda e,g:g['Data']['RootChunk']['nodesToInit'].pop())
rejects(lambda e,g:g['Data']['RootChunk']['rootNode'].update(HandleRefId='9999'))
full,full_graph=m.sources('full');m.validate(full,full_graph,'full')
full_components=full['Data']['RootChunk']['components']
assert len(full_components)==2+len(m.DETAIL_RIGS)+len(m.DETAIL_MESHES)
assert not any('proxy' in str(c.get('mesh','')) for c in full_components)
assert len({c['id'] for c in full_components})==len(full_components)
for where,field,value in [(1,'parentTransform',{'HandleRefId':'9999'}),
                           (1+len(m.DETAIL_RIGS),'forceLODLevel',-1),(0,'clientForcedLod',-1)]:
    e,g=copy.deepcopy(full),copy.deepcopy(full_graph)
    e['Data']['RootChunk']['components'][where][field]=value
    e['Data']['RootChunk']['compiledData']['Data']['Chunks'][where+1][field]=copy.deepcopy(value)
    try:m.validate(e,g,'full')
    except (ValueError,KeyError):pass
    else:raise AssertionError('Unbound or downgraded detail model accepted')
print('player_locomotion_asset: PASS (native graph reachability, no AI/root motion, unsafe mutations rejected)')
