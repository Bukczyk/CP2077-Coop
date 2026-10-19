"""Record the isolated local pose fixture. This does not test action networking."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid


def request(folder, filename, value):
    temporary=folder/(filename+'.tmp')
    temporary.write_text(json.dumps(value),encoding='ascii')
    temporary.replace(folder/filename)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-root',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    if args.output.exists():parser.error('Choose a new private output folder')
    mods=args.game_root/'bin/x64/plugins/cyber_engine_tweaks/mods'
    fixture=mods/'zz_CP2077ActionFixture'
    observer=mods/'zz_CP2077LocomotionObserver'
    capture=mods/'zz_CP2077ActionCapture/capture.jsonl'
    raw=capture.read_text(encoding='utf-8')
    if len(raw)>2*1024*1024:raise ValueError('Unexpected capture size')
    sample=json.loads(raw.strip().splitlines()[-1])
    stamp=datetime.strptime(sample['utc'],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    if not 0<=(datetime.now(timezone.utc)-stamp).total_seconds()<=5:
        raise ValueError('No fresh in-game source observation')
    session=sample['session'].rstrip('uUlL')
    if not session.isdecimal() or int(session)==0:raise ValueError('Invalid observed session')
    files={
        'fixture':fixture/'init.lua',
        'capture':mods/'zz_CP2077ActionCapture/init.lua',
        'capture_hooks':args.game_root/'r6/scripts/CP2077ActionCapture/player_capture.reds',
        'authored_archive':args.game_root/'archive/pc/mod/CP2077Coop_ActionFixture.archive',
        'private_cache':args.game_root/'archive/pc/mod/PRIVATE_DO_NOT_DISTRIBUTE_ActionClips.archive'}
    hashes={name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in files.items()}
    args.output.mkdir(parents=True)
    result={'started_utc':datetime.now(timezone.utc).isoformat(),
        'scope':'isolated local game-thread pose fixture; NO synchronized actions',
        'installed_sha256':hashes,'session':session,'visual_pass':False,'phase_receipts':[]}
    process=None
    try:
        with (args.output/'recorder.log').open('w') as log:
            process=subprocess.Popen([sys.executable,str(Path(__file__).resolve().parents[2]/'tools/record_game_window.py'),
                '--window','COOP JOINER - SIDE BY SIDE','--output',str(args.output/'video'),
                '--seconds','60','--fps','60'],stdout=log,stderr=subprocess.STDOUT)
            time.sleep(1)
            observer_nonce=str(uuid.uuid4())
            request(observer,'observer-request.json',{'version':1,'mode':'place-observer','session':session,'request':observer_nonce})
            until=time.monotonic()+5
            while time.monotonic()<until:
                try:
                    receipt=json.loads((observer/'observer-receipt.json').read_text())
                    if receipt.get('request')==observer_nonce:
                        result['observer_submission']=receipt
                        if receipt.get('accepted') is not True:raise RuntimeError('Observer context rejected')
                        break
                except (OSError,ValueError):pass
                time.sleep(.05)
            else:raise RuntimeError('No observer submission receipt')
            nonce=str(uuid.uuid4());result['request']=nonce
            request(fixture,'action-request.json',{'version':1,'mode':'action-fixture','session':session,'request':nonce})
            until=time.monotonic()+57
            while time.monotonic()<until:
                try:
                    receipt=json.loads((fixture/'action-receipt.json').read_text())
                    if receipt.get('request')==nonce:
                        if result.get('last_fixture_receipt')!=receipt and len(result['phase_receipts'])<16:
                            result['phase_receipts'].append(receipt)
                        result['last_fixture_receipt']=receipt
                        if receipt['status']=='removed':break
                        if receipt['status']=='failed':raise RuntimeError('Fixture engine operation failed')
                except (OSError,ValueError):pass
                time.sleep(.1)
            else:raise RuntimeError('Fixture did not confirm exact actor removal within capture')
            result['capture_exit']=process.wait(timeout=15)
            for name,path in [('source-capture.jsonl',capture),('fixture.log',fixture/'zz_CP2077ActionFixture.log')]:
                if path.is_file():(args.output/name).write_bytes(path.read_bytes())
    except Exception as error:
        result['error']=str(error)
    finally:
        if process and process.poll() is None:process.terminate();process.wait(timeout=5)
        result['finished_utc']=datetime.now(timezone.utc).isoformat()
        result['capture_and_fixture_ok']='error' not in result and result.get('capture_exit')==0
        (args.output/'run.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))
    return 0 if result['capture_and_fixture_ok'] else 1


if __name__=='__main__':raise SystemExit(main())
