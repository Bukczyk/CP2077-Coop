"""Reject pose-fixture graph changes that could bypass safety or lose outputs."""
import copy
import importlib.util
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('action_fixture',root/'experiments/player-locomotion/build_action_fixture.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
e,g=m.sources();m.validate(e,g)
se,sg=m.sources('shotgundual');m.validate(se,sg,'shotgundual')
cache,clips=m.profile_values('shotgundual')
assert len(cache)==4 and clips[:3]==tuple('cp_coop_shotgundual_'+x for x in ('ovr_idle','ovr_walk','ovr_sprint'))
assert clips[3:5]==('cp_coop_rifle_aim_ovr_idle','cp_coop_rifle_aim_ovr_walk')
try:m.validate(se,sg,'rifle')
except ValueError:pass
else:raise AssertionError('Mismatched weapon cache/graph profile accepted')
try:m.sources('unknown')
except ValueError:pass
else:raise AssertionError('Unknown pose profile accepted')


def find(doc,kind):return next(v for v in m.base.walk(doc) if v.get('$type')==kind)


def reject(change):
    entity,graph=copy.deepcopy(e),copy.deepcopy(g)
    change(entity,graph)
    try:m.validate(entity,graph)
    except (ValueError,KeyError,IndexError):return
    raise AssertionError('Unsafe action fixture accepted')


reject(lambda e,g:find(g,'animAnimNode_BlendOverride').update(getDeltaMotionFromOverride=1))
reject(lambda e,g:find(g,'animAnimNode_BlendOverride').update(blendAllTracks=1))
reject(lambda e,g:find(g,'animAnimNode_BlendOverride')['bones'][0]['transformIndex'].update(name=m.base.cname('Hips')))
reject(lambda e,g:find(g,'animAnimNode_SkAnim').update(collectEvents=1))
reject(lambda e,g:find(g,'animAnimNode_SkFrameAnim').update(applyMotion=1))
reject(lambda e,g:g['Data']['RootChunk']['nodesToInit'].pop())
reject(lambda e,g:find(g,'animAnimNode_Switch').update(numInputs=999))
reject(lambda e,g:find(g,'animAnimVariableFloat').update(default=1))
reject(lambda e,g:find(g,'animAnimNode_BlendOverride')['weightNode']['node'].update(HandleRefId='99999'))
reject(lambda e,g:e['Data']['RootChunk']['entity']['Data'].update({'$type':'gameNPCPuppet'}))
print('action fixture asset: neutral defaults, active graph, no root motion/events, upper-body mask passed')
