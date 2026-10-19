# Automated local player replay

`coop_player_replay` is a loopback-only test participant using the production
SessionClient. It joins an existing HOST session and publishes player transforms
through the unchanged typed protocol. Real game clients spawn and animate its
proxy normally. It never moves the local player or sends keyboard input.

Build with `-DCOOP_BUILD_REPLAY=ON`, then build target `coop_player_replay`.
Pass `--route PATH.csv --key-file PRIVATE_ACCESS_KEY --session EXISTING_SESSION`.
Use the session name from the active game configuration, not an assumed room.
The only endpoint is 127.0.0.1:11779. Credentials are read from a private file;
do not commit them. The tool cannot create a HOST session or connect to a VPS.

CSV columns are `seconds,x,y,z,yaw`, with Euler yaw in radians. Start at zero,
use increasing times, at most 120 seconds/20,000 samples, finite coordinates and
segments at most 30 m/s. The tool holds the first point for eight seconds to
allow a proxy to spawn, interpolates the route at the configured 60 Hz state
rate, holds its final point five seconds, then disconnects. Record the admitted
PlayerId to distinguish its disposable proxy from real remote players.

Run `--route PATH.csv --validate-only` to check input without reading credentials
or connecting. Invalid routes fail before admission. Keep routes short and on
known ground; navigation obstacles and stairs are separate test cases.

Record the observing game window with UTC frame timing and retain both game
diagnostics. Compare repeated scanner-off/on runs of the same route. Route
completion proves only that state was sent, not correct engine placement or
animation. Inspect video for held poses, foot motion, starts/stops and snaps;
match these to target/readback/policy/clock traces. Verify proxy retirement after
disconnect. A synthetic participant is not a human sprint-input test, but it
exercises the actual session, interpolation, identity and engine rendering path.
## Repeatable video and diagnostic capture

Install the optional Windows capture dependencies in the bench Python environment:
`python -m pip install windows-capture opencv-python pywin32`.

With the matched local games already loaded, use the observing game's exact title
and private configuration. For example, from this checkout:

```powershell
python tools/run_player_replay.py --replay build/local-sync/Release/coop_player_replay.exe --route <validated-route.csv> --game-root "G:/SteamLibrary/steamapps/common/Cyberpunk 2077 - Test B" --scanner off --output <new-private-evidence-folder>
```

The route must be in a known, clear area visible to the observer. The test tool
does not position the observer or validate navigation. Scanner state is an operator
observation. Use the same route, observer, settings and build for each comparison.
The replay is a synthetic third participant. It does not verify capture of a real
player's input, sprint state or weapon. It does exercise the production JOINER to
HOST player-state path and the receiving game's presentation.

Outputs include a real window recording (`video/game.mp4`), per-frame UTC timing,
route, transport log and a private copy of the movement log. Neither private
session configuration nor access-key contents are copied. Keep these artifacts
private until inspected. The recorder reports callback gaps and repeated encoded
frames. A successful encoder/transport exit is not a visual animation PASS.

Before a run, the existing CET console can explicitly rearm the diagnostic budget:

```lua
GetMod("CP2077MovementDiagnostics").startCapture("walk-off-1")
```

This returns false before initialization, for invalid labels or after 16 explicit
captures in one CET load. Each capture retains the 8 MiB/9000-frame limits.
Sampling time remains monotonic between captures. Check `captureStatus()` and
fresh log timestamps. Do not silently loop around the limits or reload during
pending actor retirement. A CET reload reconnects and can reposition the local
JOINER; restore and verify the observer before comparing video.

When reviewing, check body motion and pose independently from the circle marker.
Measure tracking error, stop-to-settle delay, native locomotion action and correction
counts. Preserve rejected attempts. Do not label a patch fixed from unit tests,
marker motion, synthetic replay completion or native command acceptance alone.
