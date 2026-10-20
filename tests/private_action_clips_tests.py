"""Synthetic data only: alias isolation, payload retention and unsafe inputs."""
import copy
import importlib.util
from pathlib import Path
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('private_clips', root/'experiments/player-locomotion/prepare_private_action_clips.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def entry(name, index):
    return {'HandleId':str(index), 'Data':{'$type':'animAnimSetEntry',
        'animation':{'HandleId':str(index+100), 'Data':{'$type':'animAnimation',
            'name':{'$type':'CName','$storage':'string','$value':name}, 'duration':2,
            'animBuffer':{'Data':{'numJoints':71,'Bytes':'c3ludGhldGlj'}},
            'motionExtraction':None}}, 'events':[]}}


doc = {'Header':{'GameVersion':2310}, 'Data':{'RootChunk':{
    '$type':'animAnimSet','rig':{'DepotPath':{'$value':m.RIG}},
    'animationDataChunks':[{'buffer':{'Bytes':'c3ludGhldGlj'}}],
    'animations':[entry(n,i) for i,n in enumerate(['walk_0','unused','idle_low_unarmed'])]}}}
original = copy.deepcopy(doc)
prepared = m.prepare(doc,'stealth')
assert doc == original
assert [m.animation(e)['name']['$value'] for e in prepared['Data']['RootChunk']['animations']] == [
    'cp_coop_stealth_idle_low_unarmed','cp_coop_stealth_walk_0']
assert prepared['Data']['RootChunk']['animationDataChunks'] == doc['Data']['RootChunk']['animationDataChunks']
for selected,source in zip(prepared['Data']['RootChunk']['animations'],[doc['Data']['RootChunk']['animations'][2],doc['Data']['RootChunk']['animations'][0]]):
    normalized = copy.deepcopy(selected)
    m.animation(normalized)['name'] = copy.deepcopy(m.animation(source)['name'])
    assert normalized == source  # No animation/event/buffer modification hidden by aliasing.
assert m.alias('rifle','ovr_idle') != m.alias('handgunboth','ovr_idle')
shotgun=copy.deepcopy(doc)
shotgun['Data']['RootChunk']['animations']=[entry(n,i) for i,n in enumerate(m.PROFILES['shotgundual'][1])]
selected=m.prepare(shotgun,'shotgundual')
assert [m.animation(e)['name']['$value'] for e in selected['Data']['RootChunk']['animations']]==[
    'cp_coop_shotgundual_'+n for n in m.PROFILES['shotgundual'][1]]
assert m.buffer_hashes(selected)==m.buffer_hashes(shotgun)
directional=copy.deepcopy(doc)
directional['Data']['RootChunk']['animations']=[entry(n,i) for i,n in enumerate(m.PROFILES['directional'][1])]
selected=m.prepare(directional,'directional')
assert [m.animation(e)['name']['$value'] for e in selected['Data']['RootChunk']['animations']]==[
    'cp_coop_directional_'+n for n in m.PROFILES['directional'][1]]
assert m.buffer_hashes(selected)==m.buffer_hashes(directional)


def reject(change):
    bad=copy.deepcopy(doc)
    change(bad)
    try: m.prepare(bad,'stealth')
    except (ValueError,KeyError): return
    raise AssertionError('Unsafe clip bank accepted')


reject(lambda d:d['Header'].update(GameVersion=2300))
reject(lambda d:d['Data']['RootChunk']['rig']['DepotPath'].update({'$value':'wrong.rig'}))
reject(lambda d:d['Data']['RootChunk']['animations'].pop())
reject(lambda d:d['Data']['RootChunk']['animations'].append(copy.deepcopy(d['Data']['RootChunk']['animations'][0])))
reject(lambda d:m.animation(d['Data']['RootChunk']['animations'][0])['animBuffer']['Data'].update(numJoints=72))
for output in [root/'private-test-output',root]:
    try: m.require_private_output(output)
    except ValueError: pass
    else: raise AssertionError('Game-derived cache permitted inside checkout')
with tempfile.TemporaryDirectory() as folder:
    try: m.require_private_output(Path(folder))
    except ValueError: pass
    else: raise AssertionError('Existing output accepted')
print('private action clips: aliases, payload preservation and unsafe-source/output rejection passed')
