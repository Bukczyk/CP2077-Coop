# Local no-AI player locomotion experiment

Opt-in game-side renderer for the local animation-sync investigation. This is
not a release, a validated multiplayer appearance system, or replicated action
state. Default configuration remains off. No protocol/server changes.

The custom `entEntity` has only animation, skin and animation-controller
components. Root position comes from the existing interpolated SessionBridge
XYZ. Animation clips have root motion and gameplay events disabled. The graph
selects neutral idle, distance-sampled walk/sprint, takeoff, airborne and landing
poses through `cp_coop_loco_phase` and `cp_coop_loco_progress` float inputs.
No vanilla mesh, rig, graph or animation bytes are packaged.

`build_assets.py` builds only two authored resources in a new output folder.
It requires official WolvenKit Console 9.0.1 with the pinned executable hash.
It validates graph wiring and safety before compilation, validates the compiled
roundtrip, verifies the exact archive inventory and extracted resource hashes.
It never installs or activates the result.

```powershell
python experiments/player-locomotion/build_assets.py --wolvenkit '<path-to-WolvenKit.CLI.exe>' --output-dir '<new-private-output-folder>'
```

A controlled local install additionally requires `player_locomotion.lua`, the
matching session entrypoint/passive controller, and the generated
`CP2077Coop_PlayerLocomotion.archive`. Set `experimentalPlayerLocomotion=true`
in the matched private test installs. Keep `experimentalNpcReplication=false`.
Record exact installed hashes and the live `loadedPresentationVersion`; hashes
of files changed after game launch do not prove those scripts were loaded.

Use the loopback production `SessionClient` replay and record the actual game
window. Review jump frames, walking/sprint/reversals, stop-to-idle, facing and a
second join after disconnect. A successful native call or green unit test is
not visual success. Keep previous failures, the original recording and config
backups. The normal tested package stays separate until a matched replacement
passes the required gates.

Current inference derives cosmetic gait from horizontal movement and jumping
from vertical displacement. It does not identify crouch, aim, weapon, climbing,
falling or authoritative action changes. Stairs/terrain and network gaps need
additional qualification. The projection has no collision, damage or PvP role.
The installed 2.31 relaxed walk/sprint clip motion distances are 3.795350313 m
and 3.053292990 m per cycle, both along rig +Y. Preserve network/entity yaw.
An earlier guessed 180-degree correction was rejected during calibration.

Cleanup waits for creator removal and explicit false attachment on the original,
creator and global exact handles. A retained detached native object can remain
findable after removal. Never require its reference to destroy itself; never
replace a still-attached, unknown, pending or foreign actor. Positive weak-ref
expiry is also absent, while unknown/failed reference queries stay blocked.

The optional private observer helper accepts `--place-observer` requests from
`tools/run_player_replay.py`. It places JOINER once and writes a nonce-specific
submission receipt. Keep CET's overlay open with the console hidden if mouse
movement would disturb the observer; this does not pause the game. Do not loop
teleports to freeze a camera: that invalidated actor-removal timing. The helper
is private local test control and must never enter a distributable game-root.
Use a route about six metres ahead and verify the camera/scene in the recording.
NVENC recording requests 60 FPS and reports actual callback cadence separately.

Revision 4 passed recorded local flat-ground walk/sprint/reversal, two replay
jumps, real HOST jumps, extended neutral idle, four-way turning and repeated
participant cleanup. Scanner dilation at 0.03 did not reproduce the old delay.
See `docs/validation/LOCAL_ANIMATION_SYNC_2026-10-18.md` for exact evidence and
limits. This is still an optional experiment, with no new distributable version.
