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
for profile in ['rifle','shotgundual']:
    for aim in [False,True]:
        de,dg=m.sources(profile,aim,True);m.validate(de,dg,profile,aim,True)
        try:m.validate(de,dg,profile,aim)
        except ValueError:pass
        else:raise AssertionError('Directional cache/graph silently accepted without opt-in')
        bad=copy.deepcopy(dg)
        node=next(v for v in m.base.walk(bad) if v.get('$type')=='animAnimNode_SkFrameAnim'
                  and v['animation']['$value']=='cp_coop_directional_neutral_walk_090')
        node['animation']=m.base.cname('walk_090')
        try:m.validate(de,bad,profile,aim,True)
        except ValueError:pass
        else:raise AssertionError('Non-aliased wrong directional clip accepted')
        bad=copy.deepcopy(dg)
        definitions={v['HandleId']:v['Data'] for v in m.base.walk(bad) if 'HandleId' in v}
        back=next(v for v in definitions.values() if v.get('$type')=='animAnimNode_SkFrameAnim'
            and v['animation']['$value']=='cp_coop_crouch_backward_walk_180')
        live=next(k for k,v in definitions.items() if v.get('$type')=='animAnimNode_FloatVariable'
            and v['variableName']==m.base.cname('cp_coop_loco_progress'))
        back['progressLink']['node']={'HandleRefId':live}
        try:m.validate(de,bad,profile,aim,True)
        except ValueError:pass
        else:raise AssertionError('Backward crouch may not reset feet to ordinary idle progress')


de,dg=m.sources('shotgundual',True,True)
lower=[v for v in m.base.walk(dg) if v.get('$type')=='animAnimNode_BlendOverride'
       and v['bones'][0]['transformIndex']['name']['$value']=='Hips']
assert len(lower)==3 and all([b['transformIndex']['name']['$value'] for b in v['bones']]==list(m.LOWER_BONES) for v in lower)
for change in (lambda n:n['bones'][0]['transformIndex'].update(name=m.base.cname('Spine')),
               lambda n:n.update(blendAllTracks=1),lambda n:n.update(getDeltaMotionFromOverride=1)):
    bad=copy.deepcopy(dg)
    node=next(v for v in m.base.walk(bad) if v.get('$type')=='animAnimNode_BlendOverride'
              and v['bones'][0]['transformIndex']['name']['$value']=='Hips')
    change(node)
    try:m.validate(de,bad,'shotgundual',True,True)
    except ValueError:pass
    else:raise AssertionError('Directional legs may not replace the relaxed upper body or root motion')

for alias in ('cp_coop_crouch_side_walk_090','cp_coop_crouch_side_walk_270'):
    bad=copy.deepcopy(dg)
    node=next(v for v in m.base.walk(bad) if v.get('$type')=='animAnimNode_SkFrameAnim' and v['animation']['$value']==alias)
    node['animation']=m.base.cname('walk_090')
    try:m.validate(de,bad,'shotgundual',True,True)
    except ValueError:pass
    else:raise AssertionError('Unqualified sideways crouch clip accepted')


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
reject(lambda e,g:find(g,'animAnimNode_Switch').update(blendTime=.08))
reject(lambda e,g:find(g,'animAnimNode_Blend2').update(timeWarpingEnabled=1))
reject(lambda e,g:find(g,'animAnimNode_Blend2').update(maxInputValue=2))
reject(lambda e,g:find(g,'animAnimVariableFloat').update(default=1))
reject(lambda e,g:find(g,'animAnimNode_BlendOverride')['weightNode']['node'].update(HandleRefId='99999'))
reject(lambda e,g:e['Data']['RootChunk']['entity']['Data'].update({'$type':'gameNPCPuppet'}))
def departing_progress_change(e,g):
    nodes={v['HandleId']:v['Data'] for v in m.base.walk(g) if 'HandleId' in v}
    for node in nodes.values():
        if node.get('$type')=='animAnimNode_SkFrameAnim':
            link=node['progressLink']['node'];reader=nodes[link.get('HandleId',link.get('HandleRefId'))]
            if reader['variableName']==m.base.cname('cp_coop_loco_previous_progress'):
                reader['variableName']=m.base.cname('cp_coop_loco_progress');return
    raise AssertionError('Missing departing gait sample')
reject(departing_progress_change)
print('action fixture asset: neutral defaults, active graph, no root motion/events, upper-body mask passed')
