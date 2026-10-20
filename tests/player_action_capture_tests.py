"""Both actual capture gates must pass before a synthetic participant is admitted."""
from datetime import datetime,timezone,timedelta
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'tools'))
spec=importlib.util.spec_from_file_location('action_capture',root/'tools/run_player_action_capture.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class Worker:
    def __init__(self,code=None,on_wait=None):self.code=code;self.terminated=False;self.on_wait=on_wait
    def poll(self):return self.code
    def wait(self,timeout):
        if self.on_wait:self.on_wait()
        self.code=0;return 0
    def terminate(self):self.terminated=True;self.code=-1

with tempfile.TemporaryDirectory() as temp:
    folder=Path(temp);a=folder/'a';b=folder/'b';a.mkdir();b.mkdir()
    (a/'first.png').touch()
    def warmup(dest,elapsed=None,stamp=None):
        elapsed=elapsed or [1+i*.04 for i in range(6)]
        stamp=stamp or datetime.now(timezone.utc).isoformat()
        rows=[{'utc':stamp,'elapsed':v,'encoded_this_callback':True,'encoded_frames':i+1,'video_pts':i*2}
              for i,v in enumerate(elapsed)]
        (dest/'frames.jsonl').write_text(''.join(json.dumps(v)+'\n' for v in rows))
        return rows
    assert m.recorder_warmup(a) is None,'first PNG alone hides encoder startup'
    warmup(a)
    t=[0];workers=[Worker(),Worker()]
    def sleep(delta):
        t[0]+=delta
        if t[0]>=.15:
            (b/'first.png').touch();warmup(b)
    receipts=m.wait_for_frames(workers,[a,b],timeout=1,clock=lambda:t[0],sleep=sleep)
    assert t[0]>=.15,'one ready window must never admit replay'
    assert len(receipts)==2 and all(r['encoded_frames_observed']==6 for r in receipts)
    warmup(a,[1,2,2.04,2.08,2.12,2.16]);assert m.recorder_warmup(a) is None,'NVENC startup stall must finish first'
    warmup(a,[2+i*.04 for i in range(6)]);assert m.recorder_warmup(a)
    warmup(a,[2+i/60 for i in range(16)])
    assert m.recorder_warmup(a)['encoded_frames_observed']>=10,'a fast recorder must qualify without duplicated frames'
    warmup(a,stamp=(datetime.now(timezone.utc)-timedelta(seconds=2)).isoformat())
    assert m.recorder_warmup(a) is None,'old encoded frames cannot admit replay'
    warmup(a,stamp=(datetime.now(timezone.utc)+timedelta(seconds=2)).isoformat())
    assert m.recorder_warmup(a) is None,'future timestamps cannot admit replay'
    rows=warmup(a);rows[-1]['elapsed']=float('nan')
    (a/'frames.jsonl').write_text(''.join(json.dumps(v)+'\n' for v in rows));assert m.recorder_warmup(a) is None
    rows=warmup(a);rows[-1]['video_pts']=rows[-2]['video_pts']
    (a/'frames.jsonl').write_text(''.join(json.dumps(v)+'\n' for v in rows));assert m.recorder_warmup(a) is None
    warmup(a)
    with (a/'frames.jsonl').open('a') as stream:stream.write('{"partial')
    assert m.recorder_warmup(a),'partial live row cannot invalidate preceding complete fresh frames'
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
    def cadence(dest,times):
        (dest/'frames.jsonl').write_text(''.join(json.dumps({'elapsed':v,'encoded_this_callback':True})+'\n' for v in times))
    cadence(a,[i*.05 for i in range(2001)])
    assert m.replay_cadence(a,metadata,stamp,stamp+92)['passed']
    cadence(a,[i*.05 for i in range(2001) if not 2.05<i*.05<3.2])
    assert not m.replay_cadence(a,metadata,stamp,stamp+92)['passed'],'first-actor blind interval accepted'
    cadence(a,[i*.05 for i in range(2001) if not .05<i*.05<1.2])
    assert m.replay_cadence(a,metadata,stamp,stamp+92)['passed'],'pre-replay encoder initialization is outside the claim'
    cadence(a,[0,.1,.2]);assert not m.replay_cadence(a,metadata,stamp,stamp+92)['passed']
    cadence(a,[0,.1,float('nan'),99]);assert not m.replay_cadence(a,metadata,stamp,stamp+92)['passed']

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
            warmup(dest)
            (dest/'capture.json').write_text(json.dumps(metadata))
            worker.on_wait=lambda:cadence(dest,[i*.05 for i in range(2001)])
        else:
            assert all((folder/'success'/role/'first.png').is_file() for role in ('host','joiner'))
        return worker
    result=m.capture_pair(folder/'success',['fixture-replay'],roots,popen=popen)
    assert result['recording_complete'] and not result['visual_pass'] and len(calls)==3
    assert len(result['recorder_warmup'])==2 and all(v['passed'] for v in result['cadence'].values())
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
    # Exercise the actual CLI completion path with private temporary tool files.
    # A source edit during capture must not be labelled with its later hash.
    tracked=folder/'tools';tracked.mkdir()
    source=tracked/'runner.py';recorder=tracked/'record_game_window.py';replay=tracked/'replay.exe'
    key=tracked/'test-key';key.write_text('fixture only, no real credentials')
    old_file,old_parse,old_run,old_capture=m.__file__,m.argparse.ArgumentParser.parse_args,m.subprocess.run,m.capture_pair
    try:
        m.__file__=str(source)
        for changed in (None,source,replay,recorder):
            for path in (source,recorder,replay):path.write_bytes(b'original fixture tool')
            output=folder/('main-'+('unchanged' if changed is None else changed.name))
            args=SimpleNamespace(output=output,replay=replay,host_root=roots['host'],joiner_root=roots['joiner'],
                session='fixture',key_file=key,origin='0,0,0,0',mode='actions')
            m.argparse.ArgumentParser.parse_args=lambda _:args
            m.subprocess.run=lambda *a,**kw:SimpleNamespace(returncode=0,stdout='duration=92 protocol=32773')
            def capture(*a,**kw):
                output.mkdir()
                if changed==recorder:recorder.unlink()
                elif changed is not None:changed.write_bytes(b'changed during capture')
                return {'recording_complete':True,'errors':[]}
            m.capture_pair=capture
            status=m.main();record=json.loads((output/'result.json').read_text())
            assert status==(0 if changed is None else 1)
            assert record['recording_complete']==(changed is None) and record['tool_hashes_unchanged']==(changed is None)
            import hashlib
            assert record['source_sha256']==hashlib.sha256(b'original fixture tool').hexdigest()
    finally:
        m.__file__,m.argparse.ArgumentParser.parse_args,m.subprocess.run,m.capture_pair=old_file,old_parse,old_run,old_capture
print('Action capture: stable encoded warmup, replay cadence, complete coverage, failed admission and owned cleanup passed')
