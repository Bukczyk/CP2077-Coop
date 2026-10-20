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

For the separate, private crouch/upper-body pose test and real source-state
capture, read [ACTION_FIXTURE.md](ACTION_FIXTURE.md). That fixture is not player
action synchronization and its game-derived animation cache must stay private.

`build_assets.py` builds only two authored resources in a new output folder.
It requires official WolvenKit Console 9.0.1 with the pinned executable hash.
It validates graph wiring and safety before compilation, validates the compiled
roundtrip, verifies the exact archive inventory and extracted resource hashes.
It never installs or activates the result.

```powershell
python experiments/player-locomotion/build_assets.py --wolvenkit '<path-to-WolvenKit.CLI.exe>' --output-dir '<new-private-output-folder>'
```

Use `--model full` to select the inspected 2.31 clothed Judy reference recipe.
The default remains the earlier proxy profile. Full uses separate head, eyes,
teeth, body, clothing and hair references with matching deformation/facial/
hair/pants rigs and explicit LOD settings. It still packs only two authored
resources. A single full-detail skinned body without its supporting rigs was
rejected in recorded testing because it visibly deformed. Do not substitute
that earlier candidate or treat a native roundtrip as visual validation.

Revision 6 filters gait selection only, adds walk/sprint hysteresis and holds
short zero-motion gaps. It does not delay network/body XYZ. A source teleport
resets the inferred ground baseline, and a sustained vertical stop can settle
a landing on a higher ledge. These are cosmetic inference with bounded tests,
not an authoritative ground/stance signal. Real crouch remains separate work.

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

The private action renderer additionally supports the default-off
`experimentalPlayerDirectionalWalk` candidate. It requires matching action AND
weapon assets built with `--directional-walk`, the separate uniquely aliased
private direction cache, and experimental presentation. Fresh standing supported
Igla walking selects four directions relative to unchanged body yaw. Crouch,
unarmed, unsupported and stale state retain the original walk path. Direction
retargeting blends over80 real milliseconds with hysteresis; short zero-motion
samples retain the existing50ms walk hold and freeze progress. Real stops still
select idle promptly. This is cosmetic inference, with no protocol/server or
position/yaw authority change. See
[recorded connected results](../../docs/validation/CONNECTED_ARMED_WALK_2026-10-20.md).
Matched action graphs additionally support real presentation-clock80ms lower
idle/walk/sprint transitions with a frozen departing sample. Crouch, jumps,
stale state, teleports and long gaps clear that layer. The locomotion-only graph
keeps its original inputs. The loopback replay's `--gaits` mode isolates walk,
stop and sprint transitions before its existing repair/rejoin tail. See
[qualification record](../../docs/validation/LOWER_GAIT_BLEND_2026-10-20.md).
The direction builder's separate `--profile crouch` and private controller model
`crouch-directions` qualify corrected forward/backward crouch clips. They require
the existing corrected stealth cache and uniquely aliased backward cache; no
generated animation bytes are distributable. Ordinary sideways crouch is not
supported by this inspected bank. See
[isolated crouch evidence](../../docs/validation/ISOLATED_BACKWARD_CROUCH_2026-10-20.md).
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
The runner retains up to three bounded CET diagnostic rotations plus the current
log. It still validates timestamps and the exact admitted replay participant;
a touched file or log from another player cannot satisfy freshness.

Revision 4 passed recorded local flat-ground walk/sprint/reversal, two replay
jumps, real HOST jumps, extended neutral idle, four-way turning and repeated
participant cleanup. Scanner dilation at 0.03 did not reproduce the old delay.
See `docs/validation/LOCAL_ANIMATION_SYNC_2026-10-18.md` for exact evidence and
limits. This is still an optional experiment, with no new distributable version.
