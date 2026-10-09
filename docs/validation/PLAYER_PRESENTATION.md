# Player presentation task

Owner: KyleBuildsAI. Started 2026-10-06 UTC.
Branch: `feat/session-player-presentation`, starting local commit `8b95f3d`.
Upstream checked at `7e3826d`; depends on the lifecycle correction in Bukczyk PR #4.

The current typed preview teleports a Judy projection every render frame and
sends no weapon, stance or aiming state. This task restores engine-driven player
movement first, using the existing interpolated position/yaw calls unchanged.
The older v0.0.37 implementation supplies the AI movement/rotation/equipment
reference. It is not installed alongside this runtime.

Owned implementation files: `runtime/session/cet/CP2077Coop/init.lua`, new
`player_motor.lua`, `runtime/session/redscript/CP2077Coop/remote.reds`,
`tests/player_motor_tests.lua`, `tests/session_lifecycle_tests.lua`,
`tests/CMakeLists.txt`, runtime README and this validation note. Local source
provenance, packaging and vault handoffs will be updated with final evidence.
No world-NPC adapter or network/session implementation is claimed.

Acceptance: independently tracked players walk/run/stop/turn; normal movement
does not send teleport commands each frame; corrections are bounded and judged
by observed position; replacement/unload/reconnect stops old commands; existing
session regressions pass. Record actual two-game tracking errors and limitations.

Weapons, crouch and aiming require a shared presentation-state contract. The
current PlayerPose/PlayerState contains only transform and sample time. Do not
overload coordinates/rotation or add a parallel relay. Prepare the contract and
game-side hooks for review before changing Bukczyk's wire/server interfaces.

## Measured result, 2026-10-06 UTC

Status: DRAFT. The frozen-player regression is reproduced and the replacement
moves the player projection. Smooth/accurate tracking acceptance remains FAIL.
Do not merge this as a completed movement fix or promote it to the public package.
[Bukczyk PR #5](https://github.com/Bukczyk/CP2077-Coop/pull/5) is stacked on #4.

Windows 11, Cyberpunk 2.31, one PC, two authorized Baseline/Test B clients,
loopback typed session server, low graphics, 1872x1053 game views. Native plugin
and server were unchanged from the matched lifecycle test. Each private F6 run
moved the local player through a 32-second square/stop/fast-reversal route. It
uses scripted local-player teleport steps, not human keyboard locomotion.
The receiver records actual actor position against the current interpolated
network target at approximately 10 Hz. These distances are not WAN latency.
UTC selection uses one-second boundaries. Different traffic/navigation can
affect runs; this is not a broad performance qualification.

| Run | UTC interval | Samples | Mean error | P95 error | Max error |
| --- | --- | ---: | ---: | ---: | ---: |
| Original transform setter, HOST to JOINER | 06:15:58-06:16:29 | 287 | 4.965 m | 10.191 m | 11.289 m |
| First retained-command candidate | 06:21:35-06:22:07 | 311 | 2.417 m | 5.099 m | 5.940 m |
| Active-policy candidate, HOST to JOINER | 06:39:42-06:40:13 | 299 | 2.822 m | 4.861 m | 5.473 m |
| Active-policy candidate, JOINER to HOST | 06:41:03-06:41:35 | 311 | 2.752 m | 5.355 m | 6.055 m |

The baseline actor had exactly zero x/y/z travel while the transmitted source
moved about 10 m by 8 m. The final receiver moved 8.20 m by 6.73 m; the reverse
receiver moved 8.16 m by 8 m. This proves engine movement resumed, but does not
prove the active-policy revision is uniformly better than the first candidate:
its forward mean error is worse, despite a lower tail error. Keep both records.
Idle facing and path-following animations were exercised, not fully qualified.
Moving/aiming direction, strafing, jumping and exact animation remain open.

An earlier active-policy run at 06:34 was excluded from comparison because the
private recorder could not encode an infinite idle policy destination. The
recorder now omits that diagnostic value and encodes before opening a file.
It does not alter the engine's received target or conceal movement errors.

## Actions and ownership boundary

The local F7 equip/crouch fixture executed (START/FINISHED in CET logs), but
visible gun/crouch acceptance was not established. Experimental capture,
equip/holster and stance hooks are preserved under
`experiments/player-presentation/action_hooks.reds`, outside the shipped runtime.
Their empty weapon result uses an explicit zero ID; the uninitialized local
TweakDBID experiment produced an unrelated record and must not be reused.
No gun, crouch, ADS, fire, reload or damage network synchronization is claimed.
The shared-state proposal is in `docs/PLAYER_PRESENTATION_CONTRACT.md`.

Next bounded work: compare actual engine velocity with the requested gait and
destination, isolate turn/obstacle deceleration, and choose an observed-position
controller with an explicit error gate. Proposed next live gate: P95 < 1 m on
walking routes and < 2 m on running routes, without periodic visible correction
jumps. These are proposed acceptance targets, not measured achievements.
Separately qualify exact held item, crouch/stand and aim visuals before connecting
the agreed typed presentation state. Do not repair this by overloading transforms.

## Verification and handoff

- PASS: native build; 13/13 CTests, including three independent mocked motors,
  pending/terminal commands, bounded failed corrections and real CET lifecycle
  logic with multiple remote bodies, replacement, departure and reconnect.
- PASS: isolated REDscript compilation, final movement-only source at
  2026-10-06T06:44:05Z. Installed compiler inputs stayed unchanged.
- PASS: two-game membership and movement in both directions; JOINER departure
  removed the HOST's body and motor. Fresh live reconnect was not repeated here;
  prior PR #4 has separate live reconnect evidence.
- FAIL: smooth movement and action visual acceptance. No live group/WAN test.
- Final cleanup: both games and test server closed; graphics and bindings restored
  byte for byte; private fixture archived; current saves retained without rollback.
  Baseline/Test B retain matched typed scripts with the movement candidate only.
  The final cleanup removed unused experimental action methods; movement code
  matches the measured run. That removal was compiled but not relaunched.

Private evidence: `D:/Downloads/syncfix/bench-artifacts/20261006-player-presentation`.
See `tracking-comparison.json`, `candidate1-comparison.json`, `final-live/`,
`ctest-final.log`, `redscript/result.json`, `cleanup-and-deployment.json`.
No private session key or complete user log is included in the PR.

KyleBuildsAI retains these exact task files, the experiments folder, validation
and contract documents through PR review. Bukczyk retains network/session/server
ownership. NPC adoption and projection files are unchanged. No gameplay version
was published: `game-files/latest` remains the tested v0.0.37 / alpha.5 package.
