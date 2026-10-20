"""Reject stale/wrong-player/malformed traces even when a log file was touched."""
from datetime import datetime, timezone, timedelta
import importlib.util
from pathlib import Path
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("replay_runner", root / "tools/run_player_replay.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
start = datetime(2026, 10, 18, 18, 0, tzinfo=timezone.utc)
finish = start + timedelta(seconds=20)


def row(second, player=3, error="1", speed="2"):
    stamp = (start + timedelta(seconds=second)).strftime("%Y-%m-%d %H:%M:%S UTC%z")
    stamp = stamp[:-2] + ":" + stamp[-2:]
    return f"[{stamp}] [123] [CP2077Movement] player={player} error={error} speed={speed}"


valid = "\n".join(row(t) for t in range(3, 21))
result = runner.analyze_trace(valid, 3, start, finish)
assert result["fresh"] and result["samples"] == 18 and result["moving_samples"] == 18
assert not runner.analyze_trace(valid, 4, start, finish)["fresh"]
assert not runner.analyze_trace(valid, 3, finish, finish+timedelta(seconds=20))["fresh"]
assert not runner.analyze_trace("\n".join(row(t) for t in range(15,21)), 3, start, finish)["fresh"]
assert not runner.analyze_trace("\n".join(row(t) for t in range(3,10)), 3, start, finish)["fresh"]
assert not runner.analyze_trace(row(19), 3, start, finish)["fresh"]
bad = "\n".join(row(t, error="nan") for t in range(3,21))
assert not runner.analyze_trace(bad, 3, start, finish)["fresh"]
assert runner.analyze_trace(valid+"\n[partial row", 3, start, finish)["fresh"]
with tempfile.TemporaryDirectory() as folder:
    directory = Path(folder)
    log = directory / "CP2077MovementDiagnostics.log"
    old = log.with_name("CP2077MovementDiagnostics.1.log")
    old.write_text("\n".join(row(t) for t in range(3, 15)))
    log.write_text("\n".join(row(t) for t in range(15, 21)))
    output = directory / "capture"
    output.mkdir()
    text, hashes = runner.collect_trace(log, output)
    assert not runner.analyze_trace(log.read_text(), 3, start, finish)["fresh"]
    assert runner.analyze_trace(text, 3, start, finish)["fresh"]
    assert set(hashes) == {"movement.1.log", "movement.log"}
    assert (output / "movement.1.log").read_text() == old.read_text()
    assert not runner.analyze_trace(text, 4, start, finish)["fresh"]
    with old.open("wb") as oversized:
        oversized.truncate(8*1024*1024+1)
    try:
        runner.collect_trace(log, output)
        raise AssertionError("Oversized diagnostics accepted")
    except ValueError:
        pass
print("replay evidence: freshness, exact identity, invalid numeric and truncated rows passed")

spec=importlib.util.spec_from_file_location("window_recorder",root/"tools/record_game_window.py")
recorder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)
errors,gaps=recorder.capture_quality([2.7,2.74,2.78,2.82,3.01],3)
assert not errors and max(gaps)<0.2, "Recorder initialization is not an inter-frame gap"
errors,gaps=recorder.capture_quality([0.2,0.3,4.0,4.1],4)
assert max(gaps)>3 and any('Fresh capture' in e for e in errors)
assert any('startup' in e for e in recorder.capture_quality([11,11.1,12],12)[0])
assert any('early' in e for e in recorder.capture_quality([0.1,0.2,0.3],4)[0])
assert any('Window closed' in e for e in recorder.capture_quality([0.1,0.2],4,True)[0])
assert recorder.capture_quality([],4)[0]
assert recorder.capture_quality([4],4)[0], "One frame cannot establish fresh cadence"
print("window capture: startup, actual stalls, early closure and missing frames distinguished")
