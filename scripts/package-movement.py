"""Build the PR5+PR17 experiment. Never reads game installs or private config."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def collect_inputs(bundle, build, version):
    lock = json.loads((ROOT/'scripts/movement-dependencies.json').read_text(encoding='utf-8'))
    payload, origins = {}, {}

    def put(path, data, origin):
        if path in payload:
            raise ValueError(f'duplicate payload: {path}')
        payload[path], origins[path] = data, origin

    for item in lock['files']:
        path = item['path']
        if not path.startswith('game-root/') or '..' in Path(path).parts:
            raise ValueError('invalid dependency path')
        data = (bundle/path).read_bytes()
        if sha(data) != item['sha256'] or len(data) != item['bytes']:
            raise ValueError(f'dependency mismatch: {path}')
        put(path, data, lock['source_release'])
    cache = (build/'CMakeCache.txt').read_text()
    if 'COOP_LEGACY_PLUGIN:BOOL=OFF' not in cache:
        raise ValueError('typed Release plugin required')
    source_line = next(s for s in cache.splitlines() if s.startswith('CMAKE_HOME_DIRECTORY:INTERNAL='))
    if Path(source_line.split('=',1)[1]).resolve() != ROOT:
        raise ValueError('build belongs to another checkout')
    put('game-root/red4ext/plugins/CP2077Coop/CP2077Coop.dll',
        (build/'CoopPlugin/Release/CP2077Coop.dll').read_bytes(), 'Windows Release build')
    for folder, destination in [
        ('runtime/session/cet/CP2077Coop', 'game-root/bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop'),
        ('runtime/session/diagnostics/CP2077MovementDiagnostics', 'game-root/bin/x64/plugins/cyber_engine_tweaks/mods/CP2077MovementDiagnostics'),
        ('runtime/session/redscript/CP2077Coop', 'game-root/r6/scripts/CP2077Coop')]:
        for src in sorted((ROOT/folder).iterdir()):
            if src.suffix not in ('.lua', '.reds'):
                continue
            data = src.read_bytes()
            if src.name == 'config.lua':
                text = data.decode('utf-8')
                if text.count('experimentalPlayerMovement = false') != 1:
                    raise ValueError('unexpected default movement config')
                data = text.replace('experimentalPlayerMovement = false',
                                    'experimentalPlayerMovement = true').encode('utf-8')
            put(destination+'/'+src.name, data, str(src.relative_to(ROOT)).replace('\\','/'))
    put('BUILD.txt', f'{version}\nSource: {git("rev-parse", "HEAD")}\nProtocol: 5\nLocomotion: enabled\nDiagnostics: enabled (5 Hz, bounded)\nLive qualification: PENDING\n'.encode(), 'generated')
    put('game-root/bin/x64/plugins/cyber_engine_tweaks/mods/CP2077MovementDiagnostics/build_info.lua',
        f'return "{version} source={git("rev-parse", "HEAD")}"\n'.encode(), 'generated')
    for src, dst in [('docs/MOVEMENT_TEST_PACKAGE.md', 'README.md'),
                     ('scripts/collect-movement-logs.ps1','Collect-Logs.ps1')]:
        put(dst, (ROOT/src).read_bytes(), src)
    for name in payload:
        if Path(name).name.lower() in ('access.key','session.ini','bindings.json','userSettings.json'.lower()) or name.endswith(('.log','.sqlite3')):
            raise ValueError(f'private/generated file in payload: {name}')
    return payload, origins, lock


def package(bundle, build, output, version):
    if not re.fullmatch(r'v0\.1\.0-movement-experiment\.[1-9][0-9]*', version):
        raise ValueError('use v0.1.0-movement-experiment.N')
    if git('status','--porcelain','--untracked-files=normal'):
        raise ValueError('commit exact source before packaging')
    if output.exists():
        raise ValueError('output must not exist; preserve previous builds')
    payload, origins, lock = collect_inputs(bundle, build, version)
    output.mkdir(parents=True)
    revision = git('rev-parse','HEAD')
    archives = []
    for role in ('HOST','JOINER'):
        files = dict(payload)
        config = f'''# Example only. Keep your existing session.ini and access.key.
role={role}
server_ip=127.0.0.1
server_port=11779
session=first-test
access_key_file=access.key
player_snapshot_rate=60
vehicle_snapshot_rate=60
npc_snapshot_rate=20
experimental_static_npc_projection=0
max_npcs=128
bubble_radius=100
interpolation_ms=100
extrapolation_ms=100
snap_distance=6
max_extrapolation_speed=30
'''
        files['config-examples/session.ini.example'] = config.encode()
        manifest = {'version':version,'role':role,'repository':'Bukczyk/CP2077-Coop',
            'source_revision':revision,'pr5_revision':'b1f054ed67c0bb03f1b8e290c2b5fd62a621307c',
            'pr17_motor_revision':'0b71aff258d595c645ef07e0ade3ad4b39847a31',
            'main_revision':'e19ffb3286efec750b8729487220becf6569ab7b',
            'protocol':5,'experimental_player_movement':True,'diagnostics':True,
            'npc_replication':False,'passive_players':False,'live_test':'not performed',
            'runtime_versions':lock['runtime_versions'],
            'files':[{'path':p,'bytes':len(data),'sha256':sha(data),
                      'source':origins.get(p,'generated')} for p,data in sorted(files.items())]}
        files['package-manifest.json'] = (json.dumps(manifest,indent=2)+'\n').encode()
        files['SHA256SUMS.txt'] = ''.join(f'{sha(data)}  {p}\n' for p,data in sorted(files.items())).encode()
        stage = output/role
        for name, data in files.items():
            path = stage/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(data)
        archive = output/f'CP2077-Coop-{version}-{role}.zip'
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for name,data in sorted(files.items()):
                info=zipfile.ZipInfo(name,date_time=(2026,10,15,0,0,0))
                info.compress_type=zipfile.ZIP_DEFLATED
                info.external_attr=0o644<<16
                z.writestr(info,data)
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None
            assert set(z.namelist()) == set(files)
            for name,data in files.items():
                assert z.read(name)==data, name
        archives.append({'file':archive.name,'bytes':archive.stat().st_size,'sha256':sha(archive.read_bytes())})
    result={'version':version,'source_revision':revision,'packages':archives}
    (output/'package-manifest.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    (output/'SHA256SUMS.txt').write_text(''.join(f'{a["sha256"]}  {a["file"]}\n' for a in archives),encoding='utf-8')
    (output/'README.md').write_bytes(payload['README.md'])
    print(json.dumps(result,indent=2))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dependency-bundle',type=Path,required=True)
    parser.add_argument('--build',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--version',required=True)
    args=parser.parse_args()
    package(args.dependency_bundle.resolve(),args.build.resolve(),args.output.resolve(),args.version)
