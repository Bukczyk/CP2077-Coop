#!/usr/bin/env python3
"""Read schema-1 movement logs or collector ZIPs without extracting/installing files."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile

MARKER = '[CP2077Movement] '
LOG_NAME = 'CP2077MovementDiagnostics.log'
MAX_BYTES = 64 * 1024 * 1024
MAX_LINE = 32 * 1024
COUNTERS = ('commands', 'snaps', 'observedSnaps', 'turns')
LIMITATIONS = [
    'Local sampled readback, not a visual smoothness or multiplayer PASS verdict.',
    'Recorder time is local to each run; it cannot measure RTT or align two PCs.',
    'Bounded sampling, normally5Hz or explicitly requested30Hz, can miss short transitions and orphan actors.',
    'Counters report increases within one actor lifetime; initial totals are excluded.',
    'Cached motor error/speed are not used as fresh position measurements.',
]


def number(value):
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (ValueError, TypeError):
        return None


def integer(value):
    result = number(value)
    return int(result) if result is not None and result >= 0 and result.is_integer() else None


def identity(value):
    # Keep Uint64 identity opaque. Floats lose precision above 2**53.
    return value if value and re.fullmatch(r'[0-9]+(?:ULL)?', value) else None


def vector(fields, names):
    values = [number(fields.get(name)) for name in names]
    return values if all(v is not None for v in values) else None


def distribution(values):
    if not values:
        return {'samples': 0, 'median': None, 'p95': None, 'max': None}
    ordered = sorted(values)
    middle = len(ordered)//2
    median = ordered[middle] if len(ordered) % 2 else ordered[middle-1]/2+ordered[middle]/2
    return {'samples': len(values), 'median': median,
            'p95': ordered[math.ceil(len(values)*0.95)-1], 'max': ordered[-1]}


def fields_from(text):
    result = {}
    for token in text.split():
        if '=' not in token:
            continue
        key, value = token.split('=', 1)
        if key in result:
            raise ValueError('duplicate field')
        result[key] = value
    return result


def analyze(lines):
    """Frames are contiguous header/player groups emitted by the existing recorder."""
    runs, run, frame = [], None, None
    warnings = Counter()
    pending_build = None

    def flush():
        nonlocal frame
        if frame is not None:
            run['frames'].append(frame)
            frame = None

    for raw in lines:
        if len(raw) > MAX_LINE:
            warnings['oversized_line'] += 1
            continue
        if MARKER not in raw:
            continue
        text = raw.split(MARKER, 1)[1].strip()
        if text.startswith('BUILD '):
            pending_build = text[6:][:256]
            continue
        if text.startswith('CAPTURE '):
            # An explicit restart is a new bounded recording, even after STOP
            # or when preceding START bytes have rotated out of the retained log.
            try:
                metadata=fields_from(text)
                rate=integer(metadata.get('rate_hz','5'))
                ordinal=integer(metadata.get('ordinal'))
                label=metadata.get('label','')
                if rate not in (5,30) or ordinal is None or not 1<=ordinal<=16 or not re.fullmatch(r'[\w-]{1,48}',label,flags=re.ASCII):
                    raise ValueError('invalid capture header')
            except ValueError:
                warnings['malformed_capture']+=1
                continue
            flush()
            build=pending_build if pending_build is not None else run['build'] if run else None
            run={'build':build,'schema':'1','capture_label':label,'requested_rate_hz':rate,
                 'frames':[],'errors':0,'stop_reason':None}
            pending_build=None
            runs.append(run)
            continue
        if text.startswith('START '):
            flush()
            try:
                metadata = fields_from(text)
            except ValueError:
                metadata = {}
            run = {'build': pending_build, 'schema': metadata.get('schema'),
                   'frames': [], 'errors': 0, 'stop_reason': None,
                   'capture_label': None, 'requested_rate_hz': integer(metadata.get('rate_hz'))}
            pending_build = None
            runs.append(run)
            if run['schema'] != '1':
                warnings['unsupported_schema'] += 1
            continue
        if run is None or run['schema'] != '1':
            warnings['rows_without_supported_start'] += 1
            continue
        if run['stop_reason'] is not None:
            warnings['rows_after_stop'] += 1
            continue
        if text.startswith('STOP '):
            flush()
            run['stop_reason'] = text[5:]
            continue
        if text.startswith('ERROR '):
            flush()
            run['errors'] += 1
            continue
        try:
            f = fields_from(text)
        except ValueError:
            warnings['malformed_row'] += 1
            continue
        t, seq = number(f.get('t')), integer(f.get('frame'))
        if t is None or t < 0 or seq is None or seq == 0:
            warnings['malformed_row'] += 1
            continue
        if 'session' in f:
            flush()
            if not all(identity(f.get(k)) for k in ('session', 'generation')):
                warnings['malformed_header'] += 1
                continue
            frame = {'fields': f, 't': t, 'seq': seq, 'players': {}}
        elif 'player' in f:
            if frame is None or t != frame['t'] or seq != frame['seq']:
                warnings['orphan_player_row'] += 1
            elif not identity(f['player']):
                warnings['malformed_player_id'] += 1
            elif f['player'] in frame['players']:
                warnings['duplicate_player_row'] += 1
                # Ambiguous samples must not select whichever row came first.
                frame['players'][f['player']] = None
            else:
                frame['players'][f['player']] = f
        else:
            warnings['unrecognized_row'] += 1
    flush()
    return {'runs': [summarize_run(r) for r in runs], 'parse_warnings': dict(warnings),
            'limitations': LIMITATIONS}


def summarize_run(run):
    players, previous, contexts = {}, {}, []
    previous_header = None
    anomalies = Counter()
    paused = not_ready = gaps = truncated = retiring_peak = 0
    for frame in run['frames']:
        h, t, seq = frame['fields'], frame['t'], frame['seq']
        context = tuple(h.get(k) for k in ('session', 'generation', 'self', 'host'))
        if not contexts or contexts[-1] != context:
            contexts.append(context)
            previous.clear()
        chronological = True
        if previous_header:
            old_t, old_seq = previous_header
            if t <= old_t or seq <= old_seq:
                anomalies['nonmonotonic_frame'] += 1
                chronological = False
            if seq != old_seq+1 or not 0 < t-old_t <= 0.6:
                gaps += 1
                previous.clear()
        previous_header = (t, seq)
        paused += h.get('paused') == 'true'
        not_ready += h.get('ready') != 'true'
        retiring_peak = max(retiring_peak, integer(h.get('retiring')) or 0)
        remotes = integer(h.get('remotes'))
        if remotes is None or remotes != len(frame['players']):
            truncated += 1
        seen_actors, present = {}, set()
        active = h.get('ready') == 'true' and h.get('paused') == 'false' and chronological
        for player, f in frame['players'].items():
            if f is None:
                continue
            key = context + (player,)
            present.add(key)
            if key not in players:
                players[key] = {'session': context[0], 'generation': context[1],
                    'self': context[2], 'host': context[3], 'player': player,
                    'samples': 0, 'eligible_samples': 0, 'unavailable_readbacks': 0,
                    'invalid_derived_samples': 0,
                    'actors': [], 'fault_samples': Counter(), 'lifecycle_samples': Counter(),
                    'position_errors': [], 'yaw_errors': [], 'actual_steps': [],
                    'target_steps': [], 'counter_increases': Counter(),
                    'counter_resets': Counter(), 'pending_command_age_max': None,
                    'target_motion_stationary_actor_intervals': 0}
            p = players[key]
            p['samples'] += 1
            actor = identity(f.get('actor'))
            if actor:
                if actor not in p['actors']:
                    p['actors'].append(actor)
                if actor in seen_actors and seen_actors[actor] != player:
                    anomalies['actor_bound_to_multiple_players'] += 1
                seen_actors[actor] = player
            for field, dest in (('fault', 'fault_samples'), ('lifecycle', 'lifecycle_samples')):
                value = f.get(field)
                if value and value not in ('na', 'false'):
                    p[dest][value] += 1
            target = vector(f, ('x', 'y', 'z'))
            actual = vector(f, ('actualX', 'actualY', 'actualZ')) if f.get('readback') == 'available' else None
            if actual is None:
                p['unavailable_readbacks'] += 1
            # Inactive/faulted actors remain visible in report, but never inherit
            # a motion interval from an old handle or a paused/not-ready sample.
            eligible = active and actor and target is not None and actual is not None
            if not eligible:
                previous.pop(key, None)
                continue
            error = math.dist(target, actual)
            if not math.isfinite(error):
                p['invalid_derived_samples'] += 1
                previous.pop(key, None)
                continue
            p['eligible_samples'] += 1
            p['position_errors'].append(error)
            yaw, actual_yaw = number(f.get('yaw')), number(f.get('actualYawDegrees'))
            if yaw is not None and actual_yaw is not None:
                p['yaw_errors'].append(abs((math.degrees(yaw % math.tau)-(actual_yaw % 360)+180) % 360-180))
            age = number(f.get('commandAge'))
            if age is not None and age >= 0:
                p['pending_command_age_max'] = max(p['pending_command_age_max'] or 0, age)
            counters = {name: integer(f.get(name)) for name in COUNTERS}
            old = previous.get(key)
            if old and old['actor'] == actor:
                a_step, t_step = math.dist(actual, old['actual']), math.dist(target, old['target'])
                if math.isfinite(a_step) and math.isfinite(t_step):
                    p['actual_steps'].append(a_step)
                    p['target_steps'].append(t_step)
                    if t_step >= 0.10 and a_step <= 0.01:
                        p['target_motion_stationary_actor_intervals'] += 1
                else:
                    p['invalid_derived_samples'] += 1
                for name in COUNTERS:
                    a, b = old['counters'][name], counters[name]
                    if a is not None and b is not None:
                        if b >= a:
                            p['counter_increases'][name] += b-a
                        else:
                            p['counter_resets'][name] += 1
            previous[key] = {'actor': actor, 'actual': actual, 'target': target, 'counters': counters}
        previous = {key: value for key, value in previous.items() if key in present}
    for p in players.values():
        for source, dest in (('position_errors', 'position_error_m'), ('yaw_errors', 'yaw_error_degrees'),
                             ('actual_steps', 'actual_sample_step_m'), ('target_steps', 'target_sample_step_m')):
            p[dest] = distribution(p.pop(source))
    return {'build': run['build'], 'schema': run['schema'], 'frames': len(run['frames']),
        'capture_label': run['capture_label'], 'requested_rate_hz': run['requested_rate_hz'],
        'capture_errors': run['errors'], 'stop_reason': run['stop_reason'],
        'context_segments': [dict(zip(('session', 'generation', 'self', 'host'), c)) for c in contexts],
        'paused_frames': paused, 'not_ready_frames': not_ready, 'gaps': gaps,
        'incomplete_or_capped_frames': truncated, 'retiring_peak': retiring_peak,
        'anomalies': dict(anomalies), 'players': list(players.values())}


def bounded_lines(stream, digest):
    total = 0
    while True:
        raw = stream.readline(MAX_LINE+1)
        if not raw:
            break
        total += len(raw)
        digest.update(raw)
        if total > MAX_BYTES:
            raise ValueError('diagnostic log exceeds 64 MiB')
        if len(raw) > MAX_LINE:
            raise ValueError('diagnostic line exceeds 32 KiB')
        yield raw.decode('utf-8-sig', errors='replace')


def read_input(path):
    path = Path(path)
    digest = hashlib.sha256()
    if path.suffix.lower() == '.zip':
        with zipfile.ZipFile(path) as archive:
            candidates = [i for i in archive.infolist() if PurePosixPath(i.filename).name == LOG_NAME]
            if len(candidates) != 1:
                raise ValueError('collector ZIP must contain exactly one movement diagnostic log')
            member = candidates[0]
            if member.file_size > MAX_BYTES:
                raise ValueError('diagnostic log exceeds 64 MiB')
            # Only read the selected diagnostic stream. No extraction or reading
            # session logs, connection configuration, access keys or other files.
            with archive.open(member) as stream:
                report = analyze(bounded_lines(stream, digest))
    else:
        with path.open('rb') as stream:
            report = analyze(bounded_lines(stream, digest))
    return {'diagnostic_sha256': digest.hexdigest(), **report}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', nargs='+', type=Path, help='diagnostic .log or Collect-Logs ZIP, one per PC')
    parser.add_argument('--output', type=Path, help='write JSON to a new file (never overwrite)')
    args = parser.parse_args()
    reports = []
    for path in args.logs:
        try:
            reports.append({'input': path.name, **read_input(path)})
        except (OSError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
            parser.exit(2, f'{path.name}: {error}\n')
    result = json.dumps({'report_schema': 1, 'inputs': reports}, indent=2, allow_nan=False)+'\n'
    if args.output:
        try:
            with args.output.open('x', encoding='utf-8') as out:
                out.write(result)
        except OSError as error:
            parser.exit(2, f'Output: {error}\n')
    else:
        sys.stdout.write(result)


if __name__ == '__main__':
    main()
