# Analyze the Poland movement test

KyleBuildsAI owns this offline tool. It reads the existing schema-1 diagnostics
from `v0.1.0-movement-experiment.1`. It does not install anything or change the
published HOST/JOINER packages, game code, protocol or server.

Run with Python 3.9 or newer from this source checkout:

```powershell
python scripts/analyze-movement.py 'D:\TestLogs\HOST.zip' 'D:\TestLogs\JOINER.zip' --output 'D:\TestLogs\movement-report.json'
```

Inputs can be the ZIP produced by `Collect-Logs.ps1` or the individual
`CP2077MovementDiagnostics.log`. Each ZIP must contain exactly one diagnostic
log. The tool streams that member without extraction and ignores all other
files, including session logs and credentials. The output must be a new file.
Each input has its own report and diagnostic SHA256. Local elapsed clocks are
not synchronized between PCs; compare the recorded scenario/video manually.

## Read the report

- `position_error_m`: fresh target versus actual 3D position from the same sample,
  with median, nearest-rank P95 and maximum. Cached motor `error` is not used.
- `yaw_error_degrees`: shortest angle between target radians and observed degrees.
- `actual_sample_step_m` / `target_sample_step_m`: distance between adjacent
  observations, not instantaneous speed or proof of a teleport. Continuity breaks
  on gaps over 0.6 seconds, missing frames/players, pause, not-ready, unavailable
  readback, actor replacement and session/generation/self/HOST changes.
- `target_motion_stationary_actor_intervals`: adjacent eligible samples where
  target moves at least 0.10 m but observed actor moves at most 0.01 m. This is a
  candidate interval to inspect in video, not a confirmed freeze diagnosis.
- `counter_increases`: observed increments of requested commands/corrections,
  observed corrections and turns on the same actor. Initial totals are excluded.
  Resets are reported separately. Missing intervals make counts lower bounds.
- `fault_samples` counts sampled fault labels, not independent fault incidents.
  `actors` lists exact local bodies observed for one session/generation/player;
  multiple bodies over time can be normal replacement and do not prove duplicates.
- Capture errors, incomplete/capped frames, missing readbacks, malformed rows,
  duplicate player rows and a sampled actor assigned to multiple players remain
  explicit. Missing position data produces null metrics, never zero error.

The published recorder logs at most 16 remotes per frame and up to 5 Hz. The tool
cannot see every animation frame, identify untracked orphan actors, measure RTT,
prove camera/seat correctness, or award a multiplayer PASS. A byte/frame STOP is
the end of that recording, not proof of disconnection. Multiple STARTs are separate
recording runs, including CET reinitialization. Explicit CAPTURE headers also
start separate runs after a STOP, so counters and motion are never compared
across operator restarts. Current30Hz timing captures report their requested rate
and label; legacy headers without a rate retain5Hz. A valid CAPTURE can begin a
retained rotated log. This does not recover bytes already lost to rotation.

Known diagnostic caveats in the published test build: the command-state field can
temporarily retain the preceding handle's state; a recovered actor can retain an
old observation-error label. The analyzer does not use commandState to certify
completion. Those source fixes are separate from the frozen test package.

## Evidence still needed

Record the same build version and a video from each observing PC. Walk, stop,
turn, walk sideways/backward, then reconnect twice. Match these moments to each
local report. Actual orientation while moving is a separate acceptance check:
the current move-command path does not explicitly apply the network facing yaw.
That source finding alone does not establish the running engine's behavior.

## Tool validation

`tests/movement_analysis_tests.py` covers actual recorder output, radians/degrees,
exact IDs above 2^53, invalid/missing readback, reset/counter handling, sampling
gaps, reconnects, actor replacement, duplicate rows, malformed/unsupported data,
ZIP isolation, output overwrite protection and separate PC clocks. CTest passes
the built Lua interpreter so the actual Lua recorder runs during the parser test.
These fixtures validate the tool, not the Poland gameplay test.
