"""Check the isolated native ABI rather than weakening the v5 contract gate."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
cpp=(root/'CoopPlugin/src/main.cpp').read_text()
reds=(root/'experiments/player-locomotion/presentation_native.reds').read_text()
actual={}
for name,result,params in re.findall(r'presentationFunction\("(CP2077Presentation_[A-Za-z]+)",&\w+,"(\w+)",(.*?)\);',cpp,re.S):
    assert name not in actual
    actual[name]=(result,[(name,kind) for kind,name in re.findall(r'\{"(\w+)","(\w+)"\}',params)])
declared={}
for name,params,result in re.findall(r'public native func (CP2077Presentation_\w+)\((.*?)\) -> (\w+);',reds):
    assert name not in declared
    declared[name]=(result,re.findall(r'(\w+):\s*(\w+)',params))
assert actual==declared and len(actual)==5,(actual,declared)
assert declared['CP2077Presentation_Push'][1]==[
    ('session','Uint64'),('epoch','Uint32'),('generation','Uint64'),('stance','Uint32'),
    ('weapon','Uint32'),('record','TweakDBID'),('aim','Uint32')]
start=cpp.index('NATIVE(PresentationPush,')
body=cpp[start:cpp.index('\n}',start)]
assert re.findall(r'RED4ext::GetParameter\(f,&(\w+)\)',body)==[name for name,_ in declared['CP2077Presentation_Push'][1]]
assert '#ifdef COOP_EXPERIMENTAL_PLAYER_PRESENTATION' in cpp[:start]
assert 'CP2077Presentation_' not in (root/'runtime/session/redscript/CP2077Coop/natives.reds').read_text()
print('isolated presentation ABI: native names, return/parameter types, opaque identities and read order passed')
