"""Synthetic metadata: exact profile, safe mount and no weapon gameplay."""
import copy
import importlib.util
from pathlib import Path
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('weapon_fixture',root/'experiments/player-locomotion/build_weapon_fixture.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
sample={'record':'ToTweakDBID{ hash = 0xAC119774, length = 22 }','visuals':[
    {'kind':'rig','name':name,'path':path} for name,path in m.RIGS.items()]}
for path,parent,appearance in m.MESHES:
    sample['visuals'].append({'kind':'skinned','name':path.rsplit('\\',1)[-1],
        'path':path,'parent':parent,'skin':parent,'slot':'None','enabled':True,
        'mask':'18446744073709551615','appearance':{'pimp':'pimp1','receiver':'pimp1_igla'}.get(appearance,appearance)})
entity,graph=m.sources(sample);m.validate(entity,graph,sample)
se,sg=m.sources(sample,'shotgundual');m.validate(se,sg,sample,'shotgundual')
try:m.validate(se,sg,sample,'rifle')
except ValueError:pass
else:raise AssertionError('Weapon entity accepted with mismatched pose cache')
de,dg=m.sources(sample,'shotgundual',True);m.validate(de,dg,sample,'shotgundual',True)
try:m.validate(de,dg,sample,'shotgundual')
except ValueError:pass
else:raise AssertionError('Weapon entity accepted without matching directional body cache')


def rejects_sample(change):
    value=copy.deepcopy(sample);change(value)
    try:m.recipe(value)
    except (ValueError,KeyError):return
    raise AssertionError('Unsupported weapon descriptor accepted')


rejects_sample(lambda s:s.update(record='ToTweakDBID{ hash = 0x00000001, length = 22 }'))
rejects_sample(lambda s:s['visuals'].pop())
rejects_sample(lambda s:s['visuals'][3].update(mask=18446744073709551615))
rejects_sample(lambda s:s['visuals'][3].update(appearance='military1'))
rejects_sample(lambda s:s['visuals'][4].update(skin='foreign'))
rejects_sample(lambda s:s['visuals'].append({'kind':'skinned','enabled':True,'path':'base/unsupported.mesh','skin':'Scope'}))


def reject(change):
    e,g=copy.deepcopy(entity),copy.deepcopy(graph);change(e,g)
    try:m.validate(e,g,sample)
    except (ValueError,KeyError,IndexError):return
    raise AssertionError('Unsafe passive weapon asset accepted')


def both(e,index,field,value):
    e['Data']['RootChunk']['components'][index][field]=copy.deepcopy(value)
    e['Data']['RootChunk']['compiledData']['Data']['Chunks'][index+1][field]=copy.deepcopy(value)


reject(lambda e,g:both(e,21,'isEnabled',1))
reject(lambda e,g:both(e,18,'rig',m.base.resource('wrong.rig','Obligatory')))
reject(lambda e,g:both(e,17,'$type','gameAIComponent'))
reject(lambda e,g:g['Receiver']['Data']['RootChunk'].update(useAnimCommands=1))
reject(lambda e,g:next(v for v in m.base.walk(g['Receiver']) if v.get('$type')=='animAnimNode_ParentTransform').update(mapping=[]))
reject(lambda e,g:e['Data']['RootChunk']['compiledData']['Data']['CruidDict'].clear())
print('passive weapon fixture: exact record/materials, native masks, safe mount and no gameplay passed')
