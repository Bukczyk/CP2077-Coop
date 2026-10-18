# Local animation synchronization, 2026-10-18

## Render-only locomotion investigation, 2026-10-18 20:28 UTC

The NPC motor path failed the original local acceptance test. The opt-in
`experimentalPlayerLocomotion` path instead uses our authored pure `entEntity`,
an animation controller and a mesh. It has no AI/navigation/collision or root
motion. Existing interpolated SessionBridge XYZ drives the actor, while local
cosmetic inference selects sampled walk, sprint and jump/landing clips, then
neutral idle. This is not replicated crouch/aim/weapon state or a release claim.
Default configuration remains off; protocol v5 and backend source are unchanged.

Compiled entity/graph safety checks, native graph roundtrip, exact two-resource
archive inventory and unpacked payload hashes passed. Only authored resources
are packaged; installed game mesh, rig and animation bytes are external refs.
The same resource bytes were rebuilt twice; archive timestamps differ.

Private evidence folders include:

- `jump-idle-passive-locomotion-1`: rejected. Loaded code preceded the corrected
  ground estimator. Root followed the dot, but the body floated in idle.
- `jump-idle-passive-locomotion-2`: visible takeoff/air/landing and arms-down idle;
  root error <=0.000004 m. Walking and repeated joins were not qualified here.
- `combined-passive-locomotion-1`: rejected. A retained detached reference blocked
  old ownership cleanup and prevented the new replay actor from spawning.
- `combined-passive-locomotion-3` and `rejoin-passive-locomotion-3`: moving/rejoining
  actor observed, <=0.000004 m root error. Camera motion limited visual comparison.
- `matched-fixed-combined-1`: rejected recording. CPU catch-up encoding starved
  capture; this is not visual evidence despite successful transport.
- `matched-fixed-qualification-2`: 15-second sprint/reversal route, two jumps and
  >20-second idle. NVENC VFR recording delivered ~35 fresh callbacks/s with no
  generated duplicate frames. Reviewed frames show running, jump/landing and
  arms-down idle, without the old seconds-long catch-up. Continuous observer
  teleportation delayed visible cleanup; that harness was rejected.
- `matched-one-shot-cleanup-3`: only one initial placement, CET captures mouse
  input without pausing the game. The departed body/marker disappeared without
  the teleport-loop delay. Reviewed late frames leave only the real HOST actor.

Cleanup now requires creator removal plus explicit false attachment on all
exact handles. Unknown, attached, pending or foreign handles still block
replacement. Holding our own detached native reference can keep FindEntityByID
non-nil, so waiting for that reference to destroy itself was a deadlock.

Revision 4 removes an incorrect guessed 180-degree yaw correction: installed
walk/sprint motion metadata travels along rig +Y. Added actual yaw readback and
wrapped error independently of position. A missing optional yaw helper must not
erase a valid position observation. These changes passed all 55 Windows CTests;
new matched in-game calibration/cleanup/time-dilation checks remain pending.
Native DLL source did not change. No fresh Debian/sanitizer result is claimed.

Observer tooling now performs one explicit, role/session-checked placement with
a request-specific submission receipt. It never continuously teleports, locks
controls or claims that a submitted placement is observed success. Keep its
private mod out of release game-root. The recorder uses NVENC VFR with explicit
UTC/PTS, requested rate and measured callback cadence. Callback rate alone does
not prove every image changed or that animation was correct; inspect frames.


## Automated reproduction checkpoint, 2026-10-18T18:09:35.194610+00:00

Owner: KyleBuildsAI / Codex. Task branch `fix/local-sync-presentation-20261018`,
starting checkpoint `2dac5bdbf330e9314322168726126e3d28c71478`.
This is local experimental work, not a qualified multiplayer release.

The user completed the requested manual sprint and reported the same failure.
The earlier stationary sample gate predates that run. No manual input is needed
just to reproduce this defect again. The objective remains incomplete.

### What is implemented and tested

- Optional loopback-only `coop_player_replay`, built with COOP_BUILD_REPLAY=ON.
  It uses the production SessionClient, joins the existing private local room and
  sends transforms through HOST/server routing. No protocol/backend change,
  keyboard injection, HOST impersonation or WAN endpoint override.
- `tools/run_player_replay.py` and `record_game_window.py` record a real existing
  game window, UTC capture timing, callback gaps, route and exact-player logs.
  Transport/capture success and visual success are separate. Fresh diagnostics
  must contain the admitted replay player's numeric rows across the run, not
  merely a newly touched file. Private settings/keys are not copied.
- Explicit bounded diagnostic rearm: `startCapture(label)` and `captureStatus()`.
  Sixteen explicit captures per CET load; each keeps its byte/frame cap and
  monotonic sampling clock. Tests cover invalid labels, limits and no engine
  reads during rearm.
- Optional observations: native policy destination, locomotion action, movement
  type, collision pause, time scale and blackboard state. Observations do not
  certify skeletal animation, native acceptance or visible success.

### Actual local results

Evidence root: `G:/Projects/CP2077-Coop/bench-artifacts/20261018-local-sync`.
Each named replay directory has a recording, replay log and timing/diagnostics.
These are synthetic third-participant fixtures with two real game clients,
not human sprint-capture validation, WAN performance or player-capacity proof.

| Trial | PlayerId | Peak moving error | Result |
| --- | --- | --- | --- |
| auto-replay-off-2 | 3 | 6.04 m | baseline FAIL |
| auto-replay-on-1 | 4 | 4.96 m | scanner-on FAIL |
| auto-replay-alerted-1 | 6 | 4.77 m | running visible, zero correction snaps on route, still FAIL |
| auto-replay-destination-1 | 8 | 5.94 m | current engine destination confirmed; still FAIL |
| auto-replay-dynamic-timer-1 | 10 | 6.01 m | timer-only FAIL |
| auto-replay-dynamic-provider-1 | 12 | 6.53 m | provider trial failed; setter-reapplication confound |
| auto-replay-dynamic-entity-provider-1 | 14 | 6.33 m | same setter-reapplication confound |
| auto-replay-dynamic-entity-provider-once-1 | 16 | 5.63 m | corrected once-per-command trial still FAIL |
| auto-replay-speed-only-1 | 18 | 6.08 m | walking improved, sprint reversals FAIL |
| auto-replay-speed-only-on-1 | 19 | 5.29 m | scanner-on sprint still FAIL |

The gait-only candidate stops position error from promoting Walk -> Run -> Sprint.
Initial admission uses the current sample speed; later transitions use filtered
speed/hysteresis. Final catch-up holds its current gait instead of immediately
requesting two lower gait transitions. Focused regression tests cover those rules.
The first walking phase's peak error fell from about 3.50 to 1.72 m scanner off,
and from 3.43 to 1.93 m scanner on. These are exploratory single-route comparisons,
with phases aligned to first moving diagnostics, not a statistically established
fix. Held pose/animation quality and sprint lag remain unacceptable.

The native destination and policy gait update while the body enters Stop/Start;
collisionPaused was false in sampled moving rows. Scanner tests observed normal
actor time scale in this view. Do not blame scanner, a stale network target or
an idle policy without current evidence. Exact engine/root-motion cause remains
unproven. Investigate gait transitions and active animation ownership next.

The provider fixture initially compared CET Lua reference wrappers and repeatedly
installed its provider. That is a test-fixture flaw, not proof of a defect in
REDscript's native NotEquals reference comparison. A corrected trial configured
once per observed move admission; it still failed. Preserve both results.

### Installed state and cleanup

Games HOST PID 81768, JOINER PID 53864 and local server PID 15872 were alive at
checkpoint. HOST remains PlayerId 1, JOINER is now PlayerId 17 in session 1 after
controlled CET reloads. Replays 18/19 disconnected; verify one remote and zero
retiring before the next lifecycle mutation. Scanner returned off visually.

Native DLL/protocol remain unchanged. JOINER alone currently runs the gait-only
Lua candidate; HOST keeps the earlier motor for intentional receiving-side A/B.
Both retain the idempotent REDscript candidate plus diagnostic files on disk;
HOST's loaded diagnostics are older until its next safe reload. This is not a
matched distribution package. Exact installed/config hashes are private in
`end-of-turn-installed-manifest.json`; original backups remain intact.

The private timer/provider fixture is unloaded and its init.lua is archived outside
the game. A locked log-only stub remains in its old directory until normal exit.
No active fixture entrypoint or callback remains. No control/key/configuration
reset, old save restoration, backend deployment, PR merge or Discord message.
No new version or release assets were published; preserve the verified package.

### Validation and remaining work

Windows Release replay build passed. One attempted relink overlapped an active
replay process and hit LNK1104; rebuilding after it exited succeeded. This is a
test-tool file lock, not a game/plugin or networking failure. Full final CTest
result: 52/52 passed in 33.40 seconds, recorded in private `ctest-final.log`.
Updated focused motor/diagnostic/replay evidence checks also passed. Existing script compile evidence
for the REDscript candidate remains unchanged. No Debian/sanitizer rerun is claimed.

Next: use the automated flat route as the repeatable failing baseline. Isolate
native gait-transition stopping and Judy's ambient/locomotion animation ownership;
then qualify continuous walk, sprint, stop and reversal from video plus readback.
Keep repeated automated trials bounded and validate exact retirement/reconnect.
Do not ask for another human sprint solely to reproduce an already recorded bug.
Do not promote the partial walking improvement as a complete animation fix.

Owned source: CMake replay option, tools/* source only, replay tests, session CET
optional diagnostics, diagnostic entrypoint/recorder, player_motor.lua and its
regressions, remote.reds gait candidate, lifecycle tests and this validation note.
No ownership transfer or backend contract request is needed for this local blocker.

## Root-placement isolation and final cleanup

`auto-replay-root-placement-1` exercised replay PlayerId 21 through the same
production route. The private fixture made 375 direct TeleportationFacility
requests only on its identity-guarded disposable actor while its owned move
command reported Executing. Peak moving readback error remained 4.92 m, with a
correction snap. These were requests, not 375 observed placements. This approach
did not keep the body aligned and is rejected as an animation fix.

Its event log, recording, per-frame UTC timestamps and metrics are retained in
that private directory. The experiment entrypoint was archived and callbacks
unloaded after confirmed player removal. Both timer/provider and root fixtures
have no init.lua in the game. Locked log-only stubs may remain until normal game
exit; do not stop the games merely to remove them.

Final local session: HOST PlayerId 1, JOINER PlayerId 22, session 1, generation 10.
The user-facing observer position was restored after the safe CET reload; scanner
and console are off. Both games and server remain running. No keys, session
configuration, graphics or saves were reset. The gait-only candidate remains
JOINER-only for intentional A/B, not a matched release. Full final CTests: 52/52
PASS (33.40 s). Source checkpoint is local/unpublished; no PR or release created.
The automation request is implemented, but the animation/catch-up goal is unfinished.

## Earlier investigation history


Owner: KyleBuildsAI / Codex. Branch: `fix/local-sync-presentation-20261018`.
Base: Claude Code's `da1bafe30a217862998095f0a49030c1b092f988`, merged with
the validated NPC fixture integration `f39cb1fc64816b72c71cb3f495815077545d9088`.
Combined checkpoint: `2dac5bdbf330e9314322168726126e3d28c71478`.
Upstream main: `e19ffb3286efec750b8729487220becf6569ab7b`, protocol v5.

The user authorized local sync work on both game integration and networking on
October 18. This first slice changes the engine adapter and read-only diagnostics.
It does not add a packet or connect weapon/crouch/jump state.

## Baseline

Two local Cyberpunk 2.31 processes joined loopback session 1: HOST PlayerId 1,
JOINER PlayerId 2. Server logs confirm creation/join/SESSION_READY. Each side
reports one remote actor. Both DLLs have SHA256
`c80bd52d36f48d788af5bfd85c159a478af67bd05193c9a57012e470da804eef`.
Installed session scripts matched the `da1bafe` bench after LF normalization.
Movement/diagnostics were enabled; no fixture mod was active.

The user reported good apparent position matching but lagging/incorrect animation.
Screenshots show a visible attached Judy proxy. They do not prove T-pose duration
or cause. The 5 Hz trace additionally records stationary readbacks while a move
reports Executing, corrections and recovery from `turn_readback_timeout` and
`correction_limit`. Position tracking is not certified complete.

Private evidence: `G:\Projects\CP2077-Coop\bench-artifacts\20261018-local-sync`.
The baseline log includes an older appended run; `baseline/analysis.json` splits
them. Manual walk/sprint phase boundaries were not precisely marked. Do not
interpret idle samples as sprint performance or diagnostics as visual proof.

## Candidate and ownership

Previously every retarget (about 80 ms) reapplied native movement type and
start/stop/distance settings. The candidate keeps destination updates but calls
native `ChangeMovementType` only when the retained command's gait changes. A new
top policy gets initial movement/start-stop/distance configuration. Confirmed
command retirement clears the retained policy reference.

Diagnostics add local player locomotion and remote policy locomotion action,
idle/pathfinding status and native gait-transition request count. These are
observations/attempts, not proof of animation playback. Missing/throwing optional
getters preserve transform readback and command ownership.

Owned files: `runtime/session/redscript/CP2077Coop/remote.reds`, session CET
`init.lua`, diagnostics `init.lua`/`recorder.lua`, lifecycle/diagnostics tests,
this record and package instructions. Shared protocol/server/native source,
controls, saves and private configuration remain unchanged in this slice.

## Validation

- PASS: motor, actual CET lifecycle entrypoint and diagnostics under Lua 5.4 and
  LuaJIT, including absent/throwing animation observations.
- PASS: isolated REDscript compilation with matched session scripts, copied game
  cache and Codeware. Compilation does not change installed game scripts.
- PASS: fresh Windows Release plugin/server build and all 50 CTests. After additional time-scale diagnostics, affected lifecycle/diagnostics/analysis/motor tests and LuaJIT suites passed again.
- Pending: installed candidate A/B test. No animation-quality/T-pose fix claimed.

Next test: HOST walks, sprints, stops, turns still and while moving; then swap
roles. Correlate video/visual observation with UTC phases, source locomotion,
requested gait, command lifetime, policy action and corrections. Repeated targets
must not repeatedly request unchanged gait transitions. Test reconnect and policy
replacement separately. Retain one exact actor per remote identity and game-thread
engine operations. Investigate Judy animation resources if this is insufficient.

## Remaining order

1. Qualify walk/run/sprint animation continuity and transition timing locally.
2. Connect source stance/locomotion/held weapon through typed presentation state
   with late-join/reconnect baseline. Current PlayerPose/PlayerState carries only
   transform/time. Weapon/crouch/aim hooks remain experiments; jump is unconnected.
3. Visually prove crouch, jump/land, draw/holster, matching weapons and aim while
   moving. Command admission is not visual completion.
4. Match NPC identity/appearance/life state with HOST authority and no duplicate AI.
5. Match vehicle record/appearance/identity before seats/passengers/ownership.

Local qualification precedes WAN testing. Dynamic multiplayer groups remain the
product goal; a two-process bench establishes no live player capacity.

## User recording reviewed afterward

The 11.33-second recording confirms held arms-crossed idle pose, independent
marker/body motion and roughly 1.6-second catch-up after one marker stop. It does
not clearly show an arms-out T-pose. Scanner UI is active, but actual time dilation
was not logged. Same-minute diagnostics show correction snaps and a correction-limit
fallback; exact frame/log alignment is unverified. The gait-update candidate is
uninstalled and must not be credited with fixing this video. Full private evidence:
`bench-artifacts/20261018-local-sync/video-analysis/ANALYSIS.md`.

Next: measure scanner/focus dilation, locomotion policy and animation ownership;
prove continuous body locomotion and appropriate start/stop transitions. A responsive
marker alone is not acceptance.

## Installed candidate, awaiting manual movement comparison

Candidate content identifier `d823bc383f8ee034` is installed in both game copies.
Private `candidate-install.json` records source/install hashes and external
backups. Only four Lua/REDscript files and diagnostic build_info changed; existing
DLLs, config, keys, CET bindings and input mappings are preserved. Native source
is unchanged. Both installed script stacks compiled successfully at launch.

Run `20261018-170407-401091`: HOST 81768, JOINER 53864, local session 1,
PlayerIds 1/2. Both loaded and a remote actor is observed. Idle diagnostics verify
focusDilation=false, globalTimeScale=1 and actorTimeScale=1. This is a stationary
measurement, not a movement PASS. User was asked for a scanner-off walk/sprint/stop
run; completion is not yet confirmed. Scanner-on comparison remains pending.

Read-only optional fields now include actor time scale and high-level/upper-body
blackboard state. These are not direct skeletal-animation verification. Source
remains uncommitted on the task branch; no new package or PR has been published.
Games remain open. Full objective remains active and unproven.

## Failed candidate and automated reproduction, 2026-10-18T17:39:25.253230+00:00

The user completed the HOST sprint test and reports the same animation failure.
Fresh diagnostics captured 97 moving samples, including Walk/Run/Sprint; the
17:14 UTC stationary gate check predates that run and is no longer a blocker.
The installed candidate d823bc383f8ee034 has FAILED visual acceptance.

An optional loopback-only SessionClient replay now drives a disposable extra
player through the real HOST/server path without game keyboard automation.
Two recorded runs reproduce body/marker lag on a flat route, scanner off and on.
Scanner-off peak logged motor error: 6.04 m; scanner-on: 4.96 m. These are fixture
measurements, not a human sprint or WAN pass. Both runs observed actor time scale
1. Most executing movement samples were not policy-idle; root cause is unproven.

Evidence: `bench-artifacts/20261018-local-sync/user-failed-test`,
`auto-replay-off-2` and `auto-replay-on-1`. Each automated run includes an actual
JOINER window recording, replay timestamps and game diagnostics. Next: controlled
animation-state experiment on the disposable replay actor, with fresh bounded
capture. Do not ask the user to repeat the failed sprint just to reproduce it.
Games remain open; controls, configuration and saves are preserved. Work remains
uncommitted on `fix/local-sync-presentation-20261018`; no replacement release or
completed animation fix is claimed.
