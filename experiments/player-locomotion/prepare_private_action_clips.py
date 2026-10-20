"""Prepare uniquely named action clips from the operator's installed game.

PRIVATE LOCAL CACHE ONLY. Generated files contain game animation data and must
never be committed, uploaded or included in a distributable package. This tool
changes clip names only; it does not author animations or prove engine behavior.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WOLVENKIT_SHA = '7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738'
RIG = r'base\characters\base_entities\woman_base\woman_base.rig'
PROFILES = {
    'stealth': ('wa_gang_unarmed_locomotion_stealth.anims',
                ('idle_low_unarmed', 'walk_0')),
    'rifle': ('wa_gang_rifle_action_combat.anims',
              ('ovr_idle', 'ovr_walk', 'ovr_sprint', 'aim_ovr_idle', 'aim_ovr_walk')),
    'handgunboth': ('wa_gang_handgunboth_action_combat.anims',
                    ('ovr_idle', 'ovr_walk', 'ovr_sprint', 'aim_ovr_idle', 'aim_ovr_walk')),
    'shotgundual': ('wa_gang_shotgun_dual_rostovic_palica_action_combat.anims',
                    ('ovr_idle', 'ovr_walk', 'ovr_sprint', 'aim_ovr_idle', 'aim_ovr_walk')),
}


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values(): yield from walk(child)
    elif isinstance(value, list):
        for child in value: yield from walk(child)


def buffer_hashes(doc):
    return [hashlib.sha256(v['Bytes'].encode('ascii')).hexdigest()
            for v in walk(doc['Data']) if isinstance(v.get('Bytes'), str)]


def animation(entry):
    return entry['Data']['animation']['Data']


def alias(profile, name):
    return f'cp_coop_{profile}_{name}'


def prepare(doc, profile):
    """Retain exact compressed data and selected entries; rename only names."""
    if profile not in PROFILES:
        raise ValueError('Unknown clip profile')
    if doc['Header']['GameVersion'] != 2310:
        raise ValueError('Only inspected game 2.31 exports are supported')
    root = doc['Data']['RootChunk']
    if root['$type'] != 'animAnimSet' or root['rig']['DepotPath']['$value'] != RIG:
        raise ValueError('Wrong animation type or skeleton')
    names = [animation(e)['name']['$value'] for e in root['animations']]
    if len(names) != len(set(names)):
        raise ValueError('Ambiguous source clip name')
    required = PROFILES[profile][1]
    if any(names.count(n) != 1 for n in required):
        raise ValueError('Required installed clip missing')
    output = copy.deepcopy(doc)
    selected = []
    for name in required:
        entry = copy.deepcopy(root['animations'][names.index(name)])
        item = animation(entry)
        if (item['$type'] != 'animAnimation' or not 0 < item['duration'] <= 60
                or item['animBuffer']['Data']['numJoints'] != 71):
            raise ValueError('Invalid animation entry')
        item['name']['$value'] = alias(profile, name)
        selected.append(entry)
    output['Data']['RootChunk']['animations'] = selected
    return output


def require_private_output(output):
    output = output.resolve()
    if output == ROOT or ROOT in output.parents:
        raise ValueError('Game-derived cache must stay outside the source checkout')
    if any((parent / '.git').exists() for parent in [output, *output.parents]):
        raise ValueError('Game-derived cache must stay outside Git checkouts')
    if output.exists():
        raise ValueError('Choose a new private cache folder')


def build(wolvenkit, inputs, output):
    require_private_output(output)
    if hashlib.sha256(wolvenkit.read_bytes()).hexdigest() != WOLVENKIT_SHA:
        raise ValueError('Pinned WolvenKit 9.0.1 required')
    prepared = []
    for profile, source in inputs.items():
        if source.name != PROFILES[profile][0] + '.json' or source.stat().st_size > 128*1024*1024:
            raise ValueError('Wrong or oversized local export')
        original = json.loads(source.read_text(encoding='utf-8'))
        prepared.append((profile, source, original, prepare(original, profile)))
    output.mkdir(parents=True)
    stage = output / 'PRIVATE_DO_NOT_DISTRIBUTE_ActionClips'
    records = {}
    log = []
    def run(*args):
        result = subprocess.run([str(wolvenkit), *map(str, args)], capture_output=True,
                                text=True, encoding='utf-8', errors='replace')
        log.append(result.stdout + result.stderr)
        (output / 'build.log').write_text('\n'.join(log), encoding='utf-8')
        if result.returncode:
            raise RuntimeError('WolvenKit failed; see private build.log')
        return result.stdout
    for profile, source, original, doc in prepared:
        depot = rf'base\cp2077coop\private\player_{profile}.anims'
        target = stage / depot.replace('\\', '/')
        target.parent.mkdir(parents=True, exist_ok=True)
        raw = output / (target.name + '.json')
        raw.write_text(json.dumps(doc), encoding='utf-8')
        run('convert', 'deserialize', raw, '-o', target.parent)
        roundtrip = output / ('roundtrip-' + profile)
        roundtrip.mkdir()
        run('convert', 'serialize', target, '-o', roundtrip)
        checked = json.loads((roundtrip / raw.name).read_text(encoding='utf-8'))
        names = [animation(e)['name']['$value'] for e in checked['Data']['RootChunk']['animations']]
        if names != [alias(profile, name) for name in PROFILES[profile][1]]:
            raise ValueError('Native roundtrip lost aliases')
        if buffer_hashes(checked) != buffer_hashes(doc):
            raise ValueError('Native roundtrip changed animation buffers')
        records[profile] = {'resource': depot, 'aliases': names,
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'binary_sha256': hashlib.sha256(target.read_bytes()).hexdigest()}
    packed = output / 'out'
    packed.mkdir()
    run('pack', stage, '-o', packed)
    archive = packed / (stage.name + '.archive')
    if sorted(run('archive', archive, '--list').strip().splitlines()) != sorted(r['resource'] for r in records.values()):
        raise ValueError('Unexpected cache archive content')
    unpacked = output / 'unpacked'
    unpacked.mkdir()
    run('unbundle', archive, '-o', unpacked)
    for record in records.values():
        if hashlib.sha256((unpacked / record['resource'].replace('\\', '/')).read_bytes()).hexdigest() != record['binary_sha256']:
            raise ValueError('Extracted cache payload mismatch')
    manifest = {'scope': 'PRIVATE LOCAL GAME-DERIVED CACHE; DO NOT DISTRIBUTE',
        'game_version': '2.31', 'profiles': records,
        'archive': str(archive), 'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'builder_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'visual_validation': 'pending; names and buffers only'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps(manifest))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wolvenkit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--private-local-cache', action='store_true', required=True)
    for name in PROFILES:
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    inputs = {name: getattr(args, name) for name in PROFILES if getattr(args, name)}
    if not inputs: parser.error('At least one installed-game export is required')
    build(args.wolvenkit, inputs, args.output)
