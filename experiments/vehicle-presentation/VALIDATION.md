# Vehicle fixture validation

UTC checkpoint: 2026-10-15. Owner: KyleBuildsAI. Branch:
`feat/vehicle-pose-application`, based on vehicle fixture
`15045bc77567719458110e12c74e5e88d0bd0e7e`, retaining upstream main
`e19ffb3286efec750b8729487220becf6569ab7b`.

Owned changes: this experiment folder, `tests/vehicle_fixture_tests.lua`,
`tests/vehicle_engine_adapter_tests.lua`, `tests/vehicle_movement_tests.lua`,
`tests/vehicle_movement_integration_tests.lua`, and their CMake registrations only.
No shared protocol/server, production runtime or installation changes.

## Passed locally

- Fresh Windows x64 Release plugin/server/core build with MSVC 19.41, VS 2022.
- 29/29 CTests, including all four vehicle suites.
- Lua 5.4 and LuaJIT 2.1: 353 lifecycle assertions and 159 engine adapter/activation
  assertions, plus 111 movement and 69 movement integration assertions.
  Mocked engine evidence, not a running-game result.
- Isolated REDscript compilation of the current session scripts plus
  `engine_hooks.reds`, using installed game 2.31 cache/compiler and Codeware
  scripts. All source/game/compiler input hashes were unchanged.
- `git diff --check`.

Meaningful regressions cover: exact IDs beyond double precision, invalid poses,
quaternion sign equivalence, wrong appearance/custom color, wrong parent/child,
seat substring lookalikes, unavailable/occupied seats, duplicate requests,
two-sided relationship consistency, missing/late finished events, paused timeout,
ambiguous request exceptions, changed local player, unknown observation, bounded
event queues, deferred spawn deletion, retained attachment after empty lookups,
and rejection of cleanup while a player remains mounted or a request unresolved.
Independent review caught and fixed event loss after camera read failure,
incomplete-spawn cleanup, and local-player replacement before first attachment.
Additional tests cover replay after event acknowledgement failure and rejection
of changed replay payloads. LuaJIT tests use actual Uint64 cdata identifiers.
The CET adapter test checks false pause observations, no automatic activation,
request opt-in, no deletion at shutdown, and blocking a second fixture tag.

The follow-up movement regressions cover full quaternion and sign equivalence,
invalid/too-large/no-op poses, single-request and total origin bounds, stale
generation/creator/actor rejection, paused or failed pause query immediately before
native application, mode mutual exclusion, no automatic application/retry,
settling reset on pause, observed pose versus queued command, timeout/unknown
outcome retention, late reconciliation, occupied/unsafe readback, deferred cleanup,
invalid-clock propagation, and requalification after a read failure beyond the
original spawn's angular tolerance. An independent read-only review reran all four
suites under both interpreters and found no remaining blocker in this scope.

Private evidence on KyleBuildsAI's machine:
`D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-movement`:
`windows-build.log`, `ctest.log`, LuaJIT evidence, and timestamped isolated
REDscript compile logs/JSON with input hashes, including
`redscript/compile-20261015T073603065098Z.log`.

## Not performed

No game launch, live car spawn/application, manual/injected seat transition, visual camera
check, two-PC test, default-package installation, Debian run, sanitizer run,
GitHub publication or release. The experiment is not in any game package.

`cameraVerified=false` is intentional in every fixture status/result/sample.
Vehicle-camera-manager values alone cannot certify actual player camera behavior.
The injected non-instant mount/unmount calls and the default Hella appearance
remain game-dependent gates. No shared-vehicle success is claimed.
The vanilla whole-vehicle teleport signature compiles, but collision/physics
settling and continuous movement suitability are not proven. This is not a driving
controller or connected pose route. `movementQualified=false` remains intentional.
