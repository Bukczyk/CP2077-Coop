"""Evidence boundaries for movement test reports, including truncated/reconnected runs."""
import hashlib
import importlib.util
import io
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('analysis', ROOT/'scripts/analyze-movement.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
LUA_RUNNER = sys.argv.pop(1) if len(sys.argv) > 1 and not sys.argv[1].startswith('-') else None
START = '[CP2077Movement] START schema=1 rate_hz=5 target_yaw=radians actual_yaw=degrees\n'


def frame(seq, t, *, session='9007199254740993ULL', generation='1ULL', paused='false', ready='true', remotes=1):
    return (f'[timestamp] [CP2077Movement] t={t} frame={seq} session={session} '
            f'generation={generation} self=3 host=2 paused={paused} ready={ready} remotes={remotes} retiring=0\n')


def player(seq, t, **changes):
    fields = dict(t=t, frame=seq, player='2', actor='9007199254740995ULL',
                  x=10, y=20, z=30, actualX=9, actualY=18, actualZ=28,
                  yaw=math.pi, actualYawDegrees=-179, readback='available',
                  error=999, commands=4, snaps=2, observedSnaps=1, turns=0,
                  lifecycle='ready', fault='na', commandAge='na')
    fields.update(changes)
    return '[CP2077Movement] '+' '.join(f'{k}={v}' for k, v in fields.items())+'\n'


def report(*rows):
    return a.analyze((START+''.join(rows)).splitlines())


class Analysis(unittest.TestCase):
    def test_actual_xyz_error_and_degree_wrap_not_cached_error(self):
        p = report(frame(1, .2), player(1, .2))['runs'][0]['players'][0]
        self.assertEqual(p['position_error_m']['max'], 3)
        self.assertEqual(p['yaw_error_degrees']['max'], 1)
        self.assertEqual(p['actor'] if 'actor' in p else p['actors'][0], '9007199254740995ULL')
        self.assertEqual(p['session'], '9007199254740993ULL')

    def test_pause_unavailable_nonfinite_not_zero_or_stationary(self):
        r = report(frame(1, .2), player(1, .2),
                   frame(2, .4, paused='true'), player(2, .4, x=100),
                   frame(3, .6), player(3, .6, readback='unavailable'),
                   frame(4, .8), player(4, .8, actualX='nan'),
                   frame(5, 1), player(5, 1, x=200))['runs'][0]
        p = r['players'][0]
        self.assertEqual(r['paused_frames'], 1)
        self.assertEqual(p['eligible_samples'], 2)
        self.assertEqual(p['unavailable_readbacks'], 2)
        self.assertEqual(p['actual_sample_step_m']['samples'], 0)

    def test_reconnect_scopes_and_actor_replacement_break_continuity(self):
        r = report(frame(1, .2), player(1, .2),
                   frame(2, .4), player(2, .4, actor='99ULL', commands=40, x=500),
                   frame(3, .6, generation='2ULL'), player(3, .6, commands=99),
                   frame(4, .8, session='9007199254740994ULL'), player(4, .8))['runs'][0]
        self.assertEqual(len(r['context_segments']), 3)
        self.assertEqual(len(r['players']), 3)
        self.assertEqual(r['players'][0]['actors'], ['9007199254740995ULL', '99ULL'])
        self.assertTrue(all(p['actual_sample_step_m']['samples'] == 0 for p in r['players']))
        self.assertTrue(all(not p['counter_increases'] for p in r['players']))

    def test_counters_are_deltas_and_resets_not_cumulative_sums(self):
        p = report(frame(1, .2), player(1, .2), frame(2, .4), player(2, .4, commands=5, snaps=3),
                   frame(3, .6), player(3, .6, commands=0, snaps=3))['runs'][0]['players'][0]
        self.assertEqual(p['counter_increases']['commands'], 1)
        self.assertEqual(p['counter_increases']['snaps'], 1)
        self.assertEqual(p['counter_increases']['observedSnaps'], 0)
        self.assertEqual(p['counter_resets']['commands'], 1)

    def test_gaps_missing_players_and_unready_break_intervals(self):
        p = report(frame(1, .2), player(1, .2), frame(3, .6), player(3, .6, x=50),
                   frame(4, .8, remotes=0), frame(5, 1), player(5, 1, x=70),
                   frame(6, 1.2, ready='false'), player(6, 1.2, x=100),
                   frame(7, 1.4), player(7, 1.4, x=150))['runs'][0]['players'][0]
        self.assertEqual(p['actual_sample_step_m']['samples'], 0)

    def test_stall_candidate_and_jumps_are_sampled_observations(self):
        p = report(frame(1, .2), player(1, .2), frame(2, .4), player(2, .4, x=11),
                   frame(3, .6), player(3, .6, actualX=100))['runs'][0]['players'][0]
        self.assertEqual(p['target_motion_stationary_actor_intervals'], 1)
        self.assertEqual(p['actual_sample_step_m']['max'], 91)
        self.assertFalse(any('ping' in k or 'pass' in k for k in p))

    def test_duplicate_rows_and_actor_aliases_flagged(self):
        r = report(frame(1, .2, remotes=2), player(1, .2), player(1, .2, player='4'),
                   frame(2, .4), player(2, .4), player(2, .4))
        self.assertEqual(r['parse_warnings']['duplicate_player_row'], 1)
        self.assertEqual(r['runs'][0]['anomalies']['actor_bound_to_multiple_players'], 1)
        self.assertEqual(r['runs'][0]['players'][0]['eligible_samples'], 1)

    def test_foreign_and_truncated_rows_not_attached_to_old_header(self):
        r = report(player(1, .2), frame(1, .2, remotes=25), player(1, .2),
                   '[CP2077Movement] ERROR capture_unavailable\n', player(2, .4))
        self.assertEqual(r['parse_warnings']['orphan_player_row'], 2)
        self.assertEqual(r['runs'][0]['incomplete_or_capped_frames'], 1)
        self.assertEqual(r['runs'][0]['capture_errors'], 1)

    def test_restart_stop_and_unknown_schema(self):
        r = report(frame(1, .2), player(1, .2), '[CP2077Movement] STOP reason=byte_limit\n',
                   frame(2, .4), START.replace('schema=1', 'schema=2'), frame(1, .2), player(1, .2),
                   START, frame(1, .2), player(1, .2))
        self.assertEqual([x['frames'] for x in r['runs']], [1, 0, 1])
        self.assertEqual(r['runs'][0]['stop_reason'], 'reason=byte_limit')
        self.assertEqual(r['parse_warnings']['unsupported_schema'], 1)
        self.assertEqual(r['parse_warnings']['rows_after_stop'], 1)

    def test_explicit_capture_restarts_after_stop_without_cross_capture_motion(self):
        cap='[CP2077Movement] CAPTURE label=timing-1 ordinal=1 rate_hz=30 max_bytes=8388608 max_frames=9000\n'
        r=report(frame(1,.2),player(1,.2),'[CP2077Movement] STOP reason=byte_limit\n',
                 cap,frame(1,10),player(1,10,x=100,actualX=100))
        self.assertEqual([x['frames'] for x in r['runs']],[1,1])
        self.assertEqual(r['runs'][1]['capture_label'],'timing-1')
        self.assertEqual(r['runs'][1]['requested_rate_hz'],30)
        self.assertEqual(r['runs'][1]['players'][0]['target_sample_step_m']['samples'],0)
        self.assertNotIn('rows_after_stop',r['parse_warnings'])
        # A current explicit header can also be the first retained rotated log.
        rotated=a.analyze((cap+frame(1,10)+player(1,10)).splitlines())
        self.assertEqual(rotated['runs'][0]['frames'],1)
        for bad in (cap.replace('rate_hz=30','rate_hz=300'),cap.replace('ordinal=1','ordinal=17'),
                    cap.replace('label=timing-1','label=bad/label')):
            rejected=report(bad,frame(1,.2),player(1,.2))
            self.assertEqual(len(rejected['runs']),1)
            self.assertEqual(rejected['parse_warnings']['malformed_capture'],1)

    def test_malformed_and_out_of_order_rows(self):
        r = report(frame(1, .2), player(1, .2), frame(1, .1), player(1, .1),
                   '[CP2077Movement] t=1 frame=3 player=2 t=2\n',
                   '[CP2077Movement] t=nan frame=4 session=1 generation=1\n')
        self.assertEqual(r['runs'][0]['anomalies']['nonmonotonic_frame'], 1)
        self.assertEqual(r['parse_warnings']['malformed_row'], 2)
        self.assertEqual(r['runs'][0]['players'][0]['eligible_samples'], 1)

    def test_zip_reads_only_diagnostic_and_preserves_exact_digest(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'HOST.zip'
            content = (START+frame(1,.2)+player(1,.2)).encode()
            with zipfile.ZipFile(path, 'w') as z:
                z.writestr('capture/'+a.LOG_NAME, content)
                z.writestr('../../access.key', 'MUST_NOT_APPEAR')
                z.writestr('capture/session.log', 'MUST_NOT_APPEAR')
            result = a.read_input(path)
            self.assertEqual(result['diagnostic_sha256'], hashlib.sha256(content).hexdigest())
            self.assertNotIn('MUST_NOT_APPEAR', json.dumps(result))
            self.assertEqual(list(Path(temp).iterdir()), [path])

    def test_empty_or_ambiguous_zip_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'both.zip'
            with zipfile.ZipFile(path, 'w'):
                pass
            with self.assertRaises(ValueError): a.read_input(path)
            with zipfile.ZipFile(path, 'w') as z:
                z.writestr('a/'+a.LOG_NAME, START)
                z.writestr('b/'+a.LOG_NAME, START)
            with self.assertRaises(ValueError): a.read_input(path)

    def test_line_limit_and_no_fake_metrics_without_readback(self):
        with self.assertRaises(ValueError):
            list(a.bounded_lines(io.BytesIO(b'x'*(a.MAX_LINE+1)), hashlib.sha256()))
        p = report(frame(1,.2), player(1,.2, readback='unavailable'))['runs'][0]['players'][0]
        self.assertIsNone(p['position_error_m']['p95'])
        self.assertEqual(p['position_error_m']['samples'], 0)

    def test_finite_inputs_cannot_overflow_report_metrics(self):
        r = report(frame(1,.2), player(1,.2,x='1e308',actualX='-1e308'),
                   frame(2,.4), player(2,.4,x='1e308',actualX='1e308',yaw='1e308'),
                   frame(3,.6), player(3,.6,x='-1e308',actualX='-1e308'))
        p = r['runs'][0]['players'][0]
        self.assertEqual(p['invalid_derived_samples'], 2)
        self.assertEqual(p['actual_sample_step_m']['samples'], 0)
        json.dumps(r, allow_nan=False)
        self.assertTrue(math.isfinite(a.distribution([1e308,1e308])['median']))

    def test_cli_refuses_overwrite_and_separates_two_pc_clocks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            logs = [root/'HOST.log', root/'JOINER.log']
            for log in logs: log.write_text(START+frame(1,.2)+player(1,.2))
            command = [sys.executable, str(ROOT/'scripts/analyze-movement.py'), *map(str,logs)]
            output = root/'report.json'
            subprocess.run(command+['--output', str(output)], check=True, capture_output=True)
            self.assertEqual(len(json.loads(output.read_text())['inputs']), 2)
            before = output.read_bytes()
            failed = subprocess.run(command+['--output', str(output)], capture_output=True)
            self.assertEqual(failed.returncode, 2)
            self.assertEqual(before, output.read_bytes())

    @unittest.skipUnless(LUA_RUNNER, 'pass coop_lua_test executable to validate actual recorder output')
    def test_actual_lua_recorder_format(self):
        result = subprocess.run([LUA_RUNNER, str(ROOT/'tests/movement_analysis_fixture.lua'), str(ROOT)],
                                check=True, capture_output=True, text=True)
        r = a.analyze(result.stdout.splitlines())
        self.assertFalse(r['parse_warnings'])
        p = r['runs'][0]['players'][0]
        self.assertEqual(p['session'], '9007199254740993ULL')
        self.assertEqual(p['position_error_m']['max'], 3)
        self.assertEqual(p['counter_increases']['commands'], 1)


if __name__ == '__main__': unittest.main()
