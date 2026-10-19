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
