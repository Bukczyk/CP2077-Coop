"""Record a real game window while a loopback SessionClient replays a route.

Start a matched local HOST/JOINER bench first. This tool does not launch games,
operate menus, reset settings, read saves, change scanner state or inject keys.
Private session settings and access keys are never copied into the output.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def utc():
    return datetime.now(timezone.utc).isoformat()


def analyze_trace(text, player, started, finished):
    """Require this admitted player's actual timestamped rows, not file mtime."""
    rows = []
    for line in text.splitlines():
        stamp = re.match(r"\[([^\]]+ UTC[+-]\d\d:\d\d)\]", line)
        fields = dict(re.findall(r"(\w+)=([^ ]+)", line))
        if not stamp or fields.get("player") != str(player):
            continue
        try:
            when = datetime.strptime(stamp[1], "%Y-%m-%d %H:%M:%S UTC%z")
            error, speed = float(fields["error"]), float(fields["speed"])
            if not all(math.isfinite(x) for x in (error, speed)) or not started <= when <= finished:
                continue
            rows.append((when, error, speed))
        except (ValueError, KeyError):
            continue
    return {"player": player, "samples": len(rows),
        "moving_samples": sum(speed > 0.5 for _, _, speed in rows),
        "first_sample_utc": rows[0][0].isoformat() if rows else None,
        "last_sample_utc": rows[-1][0].isoformat() if rows else None,
        "max_error": max((error for _, error, _ in rows), default=None),
        "fresh": bool(len(rows) >= 5 and (rows[0][0]-started).total_seconds() <= 10
                      and (finished-rows[-1][0]).total_seconds() <= 3)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replay", type=Path, required=True)
    parser.add_argument("--route", type=Path, required=True)
    parser.add_argument("--game-root", type=Path, required=True, help="Observing game installation")
    parser.add_argument("--window", default="COOP JOINER - SIDE BY SIDE")
    parser.add_argument("--scanner", choices=["off", "on", "unknown"], default="unknown",
                        help="Operator observation, not an automatic scanner check")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output must be a new folder")
    # Validation happens before reading any credentials or starting a recorder.
    check = subprocess.run([str(args.replay), "--route", str(args.route), "--validate-only"],
                           capture_output=True, text=True, timeout=5)
    if check.returncode:
        parser.error(check.stderr.strip())
    duration = float(check.stdout.split("duration=", 1)[1].strip())
    key = args.game_root / "red4ext/plugins/CP2077Coop/access.key"
    settings = dict(line.split("=", 1) for line in (key.parent / "session.ini").read_text().splitlines()
                    if "=" in line and not line.lstrip().startswith(("#", ";")))
    session = settings["session"].strip()
    if not session or not key.is_file():
        parser.error("Missing local session or private key file")
    args.output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(args.route, args.output / "route.csv")
    result = {"started_utc": utc(), "topology": "Loopback replay via production SessionClient and real HOST",
              "scanner_observation": args.scanner, "visual_pass": False}
    mods = args.game_root / "bin/x64/plugins/cyber_engine_tweaks/mods"
    provenance = {"replay_executable": args.replay, "route": args.route,
        "session_cet": mods / "CP2077Coop/init.lua",
        "player_motor": mods / "CP2077Coop/player_motor.lua",
        "diagnostic_entrypoint": mods / "CP2077MovementDiagnostics/init.lua",
        "diagnostic_recorder": mods / "CP2077MovementDiagnostics/recorder.lua",
        "redscript_adapter": args.game_root / "r6/scripts/CP2077Coop/remote.reds"}
    result["sha256"] = {name: hashlib.sha256(path.read_bytes()).hexdigest()
                        for name, path in provenance.items() if path.is_file()}
    recorder = replay = None
    try:
        with (args.output / "capture-output.log").open("w") as capture_log, \
             (args.output / "replay.log").open("w") as replay_log:
            recorder = subprocess.Popen([sys.executable, str(Path(__file__).with_name("record_game_window.py")),
                "--window", args.window, "--output", str(args.output / "video"),
                "--seconds", str(duration + 21)], stdout=capture_log, stderr=subprocess.STDOUT)
            time.sleep(1)
            if recorder.poll() is not None:
                raise RuntimeError("Recorder failed before replay; see capture-output.log")
            result["replay_started_utc"] = utc()
            replay = subprocess.Popen([str(args.replay), "--route", str(args.route),
                "--key-file", str(key), "--session", session], stdout=replay_log, stderr=subprocess.STDOUT)
            result["replay_exit"] = replay.wait(timeout=duration + 30)
            result["replay_finished_utc"] = utc()
            result["capture_exit"] = recorder.wait(timeout=25)
    except Exception as error:
        result["error"] = str(error)
    finally:
        # Only these test-owned children, never the games, launcher or server.
        for process in (replay, recorder):
            if process and process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
        log = args.game_root / "bin/x64/plugins/cyber_engine_tweaks/mods/CP2077MovementDiagnostics/CP2077MovementDiagnostics.log"
        if log.is_file():
            shutil.copy2(log, args.output / "movement.log")
            result["diagnostics_modified_utc"] = datetime.fromtimestamp(log.stat().st_mtime, timezone.utc).isoformat()
            result["diagnostics_fresh"] = log.stat().st_mtime >= datetime.fromisoformat(result["started_utc"]).timestamp()
            replay_log = (args.output / "replay.log").read_text(errors="replace")
            admitted = re.search(r"REPLAY_ACTIVE session=(\d+) player=(\d+)", replay_log)
            if admitted and "replay_finished_utc" in result:
                result["trace"] = analyze_trace(log.read_text(errors="replace"), int(admitted[2]),
                    datetime.fromisoformat(result["replay_started_utc"]),
                    datetime.fromisoformat(result["replay_finished_utc"]))
                result["diagnostics_fresh"] = result["trace"]["fresh"]
            else:
                result["diagnostics_fresh"] = False
        else:
            result["diagnostics_fresh"] = False
        result["finished_utc"] = utc()
        result["capture_and_transport_ok"] = ("error" not in result and result.get("replay_exit") == 0
            and result.get("capture_exit") == 0 and result["diagnostics_fresh"])
        (args.output / "run.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(result))
    return 0 if result["capture_and_transport_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
