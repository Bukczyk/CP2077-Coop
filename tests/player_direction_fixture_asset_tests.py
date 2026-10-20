"""Isolated directional assets retain all full-model and safe-graph checks."""
import copy,importlib.util
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'experiments/player-locomotion/build_direction_fixture.py'
s=importlib.util.spec_from_file_location('direction_fixture',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
e,g=m.sources();m.validate(e,g)
assert m.GRAPH!=m.base.GRAPH and m.ENTITY!=m.base.ENTITY
assert len(m.CLIPS)==6 and len(set(m.CLIPS))==6
assert all(0<d<7 for d in m.DISTANCES[1:])
def reject(change):
    entity,graph=copy.deepcopy(e),copy.deepcopy(g);change(entity,graph)
    try:m.validate(entity,graph)
    except (ValueError,KeyError,StopIteration):return
    raise AssertionError('Unsafe direction fixture accepted')
reject(lambda e,g:m.selectors(g)[0].update(blendTime=.08))
reject(lambda e,g:m.selectors(g)[1][1].update(applyMotion=1))
reject(lambda e,g:m.selectors(g)[1][1].update(collectEvents=1))
reject(lambda e,g:m.selectors(g)[1][2].update(animation=m.base.cname('walk_090')))
reject(lambda e,g:e['Data']['RootChunk']['entity']['Data'].update({'$type':'gameNPCPuppet'}))
reject(lambda e,g:e['Data']['RootChunk']['components'][0]['animations']['gameplay'].pop())
reject(lambda e,g:g['Data']['RootChunk']['nodesToInit'].pop())
print('Direction fixture: separate paths, exact aliased cache, no AI/root motion/events and safe graph passed')
