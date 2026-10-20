"""Record both existing local game windows before admitting an action replay.

Private bench only. No game launch, input, settings, saves or backend changes.
Start diagnostics and position both observers before running this tool.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import time

from run_player_replay import collect_trace


def utc():
    return datetime.now(timezone.utc).isoformat()


def recorder_warmup(folder,wall_time=time.time):
    """The first PNG precedes NVENC initialization; require stable encoded frames."""
    try:
        if not (folder/'first.png').is_file():return None
        with (folder/'frames.jsonl').open('rb') as stream:data=stream.read(512*1024+1)
        if len(data)>512*1024:return None
        complete=data.rsplit(b'\n',1)[0].splitlines()
        rows=[json.loads(line) for line in complete[-16:]]
        rows=[v for v in rows if v.get('encoded_this_callback') is True]
        if len(rows)<6:return None
        stamp=datetime.fromisoformat(rows[-1]['utc'])
        if stamp.utcoffset() is None or not -.05<=wall_time()-stamp.timestamp()<=.5:return None
        # At60Hz six frames span only83ms. Accept a longer recent window rather
        # than refusing a faster recorder forever or counting duplicated frames.
        for count in range(6,len(rows)+1):
            sample=rows[-count:]
            elapsed=[float(v['elapsed']) for v in sample]
            pts=[int(v['video_pts']) for v in sample]
            counts=[int(v['encoded_frames']) for v in sample]
            gaps=[b-a for a,b in zip(elapsed,elapsed[1:])]
            if not all(math.isfinite(v) and v>=0 for v in elapsed) or not .15<=elapsed[-1]-elapsed[0]<=1:continue
            if not all(0<g<=.15 for g in gaps) or not all(a<b for a,b in zip(pts,pts[1:])) \
                or not all(0<a<b for a,b in zip(counts,counts[1:])):continue
            return {'encoded_frames_observed':len(sample),'last_frame_utc':rows[-1]['utc'],
                    'last_frame_elapsed':elapsed[-1],'max_recent_gap_s':max(gaps)}
        return None
    except (OSError,ValueError,TypeError,KeyError,AttributeError,OverflowError):return None


def wait_for_frames(processes, folders, timeout=10, clock=time.monotonic, sleep=time.sleep):
    deadline=clock()+timeout
    while True:
        if any(p.poll() is not None for p in processes):
            raise RuntimeError("A recorder exited before replay admission")
        receipts=[recorder_warmup(p) for p in folders]
        if all(receipts):return receipts
        if clock()>=deadline:
            raise RuntimeError("Both recorders must encode six stable fresh frames before replay admission")
        sleep(.05)


def covers_replay(metadata, started, finished):
    """Use actual capture timestamps, never requested duration or file mtime."""
    try:
        begin=datetime.fromisoformat(metadata['video_started_utc']).timestamp()
        end=datetime.fromisoformat(metadata['started_utc']).timestamp()+float(metadata['last_frame_seconds'])
        return all(math.isfinite(v) for v in (begin,end,started,finished)) and started<=finished \
            and metadata.get('capture_ok') is True and begin<=started and end>=finished
    except (KeyError,ValueError,TypeError):
        return False


def replay_cadence(folder,metadata,started,finished):
    """Reject blind intervals inside the replay, including its first actor frames."""
    try:
        with (folder/'frames.jsonl').open('rb') as stream:data=stream.read(4*1024*1024+1)
        if len(data)>4*1024*1024:raise ValueError('Oversized frame trace')
        epoch=datetime.fromisoformat(metadata['started_utc']).timestamp()
        rows=[json.loads(line) for line in data.splitlines()]
        times=[epoch+float(v['elapsed']) for v in rows if v.get('encoded_this_callback') is True]
        if not all(math.isfinite(t) for t in times) or any(a>=b for a,b in zip(times,times[1:])):
            raise ValueError('Invalid frame timing')
        gaps=[b-a for a,b in zip(times,times[1:]) if a<finished and b>started]
        passed=bool(times and times[0]<=started<=finished<=times[-1] and gaps and max(gaps)<=.25)
        return {'passed':passed,'max_replay_gap_s':max(gaps) if gaps else None}
    except (OSError,ValueError,TypeError,KeyError,AttributeError):
        return {'passed':False,'max_replay_gap_s':None}


def capture_pair(output, replay_command, roots, duration=92, popen=subprocess.Popen):
    # A new parent folder prevents stale first frames or metadata satisfying gates.
    output.mkdir(parents=True,exist_ok=False)
    result={'started_utc':utc(),'topology':'private loopback synthetic participant in two real games',
            'visual_pass':False,'recording_complete':False,'errors':[]}
    processes=[];streams=[];folders=[];replay=None
    recorder=Path(__file__).with_name('record_game_window.py')
    try:
        for role in ('HOST','JOINER'):
            folder=output/role.lower();folders.append(folder)
            stream=(output/('recorder-'+role.lower()+'.log')).open('wb');streams.append(stream)
            command=[sys.executable,str(recorder),'--window','COOP '+role+' - SIDE BY SIDE',
                     '--output',str(folder),'--seconds',str(duration+25),'--fps','60']
            processes.append(popen(command,stdout=stream,stderr=subprocess.STDOUT,
                                   creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)))
        result['recorder_warmup']=dict(zip(('host','joiner'),wait_for_frames(processes,folders)))
        result['replay_started_utc']=utc()
        with (output/'replay.log').open('wb') as stream:
            replay=popen(replay_command,stdout=stream,stderr=subprocess.STDOUT,
                         creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            try:
                result['replay_exit']=replay.wait(timeout=duration+15)
            except subprocess.TimeoutExpired:
                replay.terminate();replay.wait(timeout=5)
                raise RuntimeError('Replay exceeded its bounded duration')
        result['replay_finished_utc']=utc()
        # Collect promptly, before the last recorder finishes and logs rotate.
        result['diagnostics']={}
        for role,root in roots.items():
            log=root/'bin/x64/plugins/cyber_engine_tweaks/mods/CP2077MovementDiagnostics/CP2077MovementDiagnostics.log'
            target=output/('diagnostics-'+role);target.mkdir()
            _,hashes=collect_trace(log,target)
            result['diagnostics'][role]=hashes
        deadline=time.monotonic()+40
        for p in processes:
            if p.wait(timeout=max(.1,deadline-time.monotonic()))!=0:
                raise RuntimeError('A recorder failed; preserve its log and partial capture')
        started=datetime.fromisoformat(result['replay_started_utc']).timestamp()
        finished=datetime.fromisoformat(result['replay_finished_utc']).timestamp()
        result['coverage']={}
        result['cadence']={}
        for role,folder in zip(('host','joiner'),folders):
            metadata=json.loads((folder/'capture.json').read_text())
            result['coverage'][role]=covers_replay(metadata,started,finished)
            result['cadence'][role]=replay_cadence(folder,metadata,started,finished)
        result['recording_complete']=result['replay_exit']==0 and all(result['coverage'].values()) \
            and all(v['passed'] for v in result['cadence'].values())
        if not result['recording_complete']:
            raise RuntimeError('Replay failed, video coverage incomplete, or a replay frame gap exceeds250ms')
    except Exception as error:
        result['errors'].append(str(error))
    finally:
        # Only these read-only recorder workers are owned here. Never stop games
        # or server, and never turn a partial MP4 into a quality pass.
        for p in processes+([replay] if replay is not None else []):
            if p.poll() is None:
                p.terminate()
                try:p.wait(timeout=5)
                except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
        for stream in streams:stream.close()
        result['finished_utc']=utc()
        (output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay',type=Path,required=True)
    parser.add_argument('--host-root',type=Path,required=True)
    parser.add_argument('--joiner-root',type=Path,required=True)
    parser.add_argument('--session',required=True)
    parser.add_argument('--key-file',type=Path,required=True)
    parser.add_argument('--origin',default='-813,821.5,24.4042,0')
    parser.add_argument('--mode',choices=('actions','gaits','sprint-loop','directions','crouch-directions','unarmed-directions','crouch-sides','crouch-diagonals','jump-actions'),default='actions')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():parser.error('Output must be a new folder')
    if args.host_root.resolve()==args.joiner_root.resolve():parser.error('Two distinct game roots are required')
    command=[str(args.replay.resolve()),'--session',args.session,'--origin',args.origin]
    if args.mode!='actions':command+=['--'+args.mode]
    # Preflight does not read credentials, start capture, or admit a participant.
    check=subprocess.run(command+['--validate-only'],capture_output=True,text=True,timeout=5)
    if check.returncode or 'duration=92 protocol=32773' not in check.stdout:
        parser.error('A validated private32773 action replay is required')
    if not args.key_file.is_file():parser.error('Private local key file is missing')
    tracked={'source_sha256':Path(__file__),'replay_sha256':args.replay,
             'recorder_sha256':Path(__file__).with_name('record_game_window.py')}
    before={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in tracked.items()}
    command+=['--key-file',str(args.key_file.resolve())]
    result=capture_pair(args.output,command,{'host':args.host_root,'joiner':args.joiner_root})
    result.update(before)
    try:after={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in tracked.items()}
    except OSError:after={}
    result['tool_hashes_unchanged']=before==after
    if not result['tool_hashes_unchanged']:
        result['recording_complete']=False
        result['errors'].append('Capture tools changed during recording; retain as diagnostic evidence only')
    (args.output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'recording_complete':result['recording_complete'],'visual_pass':False,'errors':result['errors']}))
    return 0 if result['recording_complete'] else 1


if __name__=='__main__':sys.exit(main())
