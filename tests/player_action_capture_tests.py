"""Both actual capture gates must pass before a synthetic participant is admitted."""
from datetime import datetime,timezone,timedelta
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'tools'))
spec=importlib.util.spec_from_file_location('action_capture',root/'tools/run_player_action_capture.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class Worker:
    def __init__(self,code=None):self.code=code;self.terminated=False
    def poll(self):return self.code
    def wait(self,timeout):self.code=0;return 0
    def terminate(self):self.terminated=True;self.code=-1

with tempfile.TemporaryDirectory() as temp:
    folder=Path(temp);a=folder/'a';b=folder/'b';a.mkdir();b.mkdir()
    (a/'first.png').touch()
    t=[0];workers=[Worker(),Worker()]
    def sleep(delta):
        t[0]+=delta
        if t[0]>=.15:(b/'first.png').touch()
    m.wait_for_frames(workers,[a,b],timeout=1,clock=lambda:t[0],sleep=sleep)
    assert t[0]>=.15,'one ready window must never admit replay'
    (b/'first.png').unlink()
    try:m.wait_for_frames(workers,[a,b],timeout=.2,clock=lambda:t[0],sleep=lambda delta:t.__setitem__(0,t[0]+delta))
    except RuntimeError:pass
    else:raise AssertionError('missing second frame admitted')
    try:m.wait_for_frames([Worker(1),Worker()],[a,b])
    except RuntimeError:pass
    else:raise AssertionError('exited recorder admitted')

    now=datetime.now(timezone.utc);stamp=now.timestamp()
    metadata={'capture_ok':True,'video_started_utc':(now-timedelta(seconds=1)).isoformat(),
              'started_utc':(now-timedelta(seconds=2)).isoformat(),'last_frame_seconds':100}
    assert m.covers_replay(metadata,stamp,stamp+92)
    assert not m.covers_replay(metadata,stamp,stamp+99),'requested seconds cannot hide an incomplete tail'
    assert not m.covers_replay({**metadata,'capture_ok':False},stamp,stamp+92)
    assert not m.covers_replay({**metadata,'video_started_utc':(now+timedelta(seconds=1)).isoformat()},stamp,stamp+92)
    assert not m.covers_replay({},stamp,stamp+92)
    assert not m.covers_replay({**metadata,'last_frame_seconds':float('inf')},stamp,stamp+92)

    roots={}
    for role in ('host','joiner'):
        roots[role]=folder/role
        log=roots[role]/'bin/x64/plugins/cyber_engine_tweaks/mods/CP2077MovementDiagnostics/CP2077MovementDiagnostics.log'
        log.parent.mkdir(parents=True);log.write_text('[CP2077Movement] START schema=1 rate_hz=5\n')
    calls=[];created=[]
    def popen(command,**kwargs):
        calls.append(command)
        worker=Worker();created.append(worker)
        if '--window' in command:
            dest=Path(command[command.index('--output')+1]);dest.mkdir();(dest/'first.png').touch()
            (dest/'capture.json').write_text(json.dumps(metadata))
        else:
            assert all((folder/'success'/role/'first.png').is_file() for role in ('host','joiner'))
        return worker
    result=m.capture_pair(folder/'success',['fixture-replay'],roots,popen=popen)
    assert result['recording_complete'] and not result['visual_pass'] and len(calls)==3
    assert all(p.code==0 for p in created) and len(result['diagnostics'])==2
    before=len(calls)
    try:m.capture_pair(folder/'success',['fixture-replay'],roots,popen=popen)
    except FileExistsError:pass
    else:raise AssertionError('existing evidence overwritten')
    assert len(calls)==before
    failed=[]
    def bad_recorder(command,**kwargs):
        assert '--window' in command,'failed startup must never launch replay'
        worker=Worker(1 if not failed else None);failed.append(worker);return worker
    result=m.capture_pair(folder/'failure',['fixture-replay'],roots,popen=bad_recorder)
    assert not result['recording_complete'] and result['errors'] and failed[1].terminated
    assert (folder/'failure/result.json').is_file(),'failure evidence retained'
print('Action capture: both first frames, actual complete coverage, failed admission and owned cleanup passed')
