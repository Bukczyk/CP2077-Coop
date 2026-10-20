"""Keep experimental aim local, bounded and above the pelvis/root."""
import copy
import importlib.util
from pathlib import Path

root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('aim_fixture',root/'experiments/player-locomotion/build_action_fixture.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
entity,graph=m.sources('shotgundual',True);m.validate(entity,graph,'shotgundual',True)
ordinary_entity,ordinary_graph=m.sources('shotgundual')
assert entity==ordinary_entity,'aim qualification must not change entity ownership or component bindings'
assert not any(v.get('$type')=='animAnimNode_RotateBone' for v in m.base.walk(ordinary_graph))

def reject(change):
    e,g=copy.deepcopy(entity),copy.deepcopy(graph)
    rotations=[v for v in m.base.walk(g) if v.get('$type')=='animAnimNode_RotateBone']
    change(e,g,rotations)
    try:m.validate(e,g,'shotgundual',True)
    except (ValueError,KeyError,IndexError):return
    raise AssertionError('Unsafe aim fixture accepted')

reject(lambda e,g,r:r[0]['bone'].update(name=m.base.cname('Hips')))
reject(lambda e,g,r:r[0].update(inModelSpace=0))
reject(lambda e,g,r:r[0].update(useIncrementalMode=1))
reject(lambda e,g,r:r[0].update(clampRotation=0))
reject(lambda e,g,r:r[0].update(maxAngle=180))
reject(lambda e,g,r:r[0].update(axis='Y_Axis'))
reject(lambda e,g,r:r[0].update(scale=2))
reject(lambda e,g,r:r[0]['angleNode']['node'].update(HandleRefId='99999'))
try:m.validate(entity,graph,'shotgundual')
except ValueError:pass
else:raise AssertionError('Aim graph silently accepted without explicit opt-in')
print('Isolated aim fixture: explicit opt-in, unchanged actor, bounded model-space spine rotations passed')
