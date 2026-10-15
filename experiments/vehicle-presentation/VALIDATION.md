# Vehicle fixture validation

UTC checkpoint: 2026-10-15. Owner: KyleBuildsAI. Branch:
`feat/vehicle-pose-application`, based on vehicle fixture
`15045bc77567719458110e12c74e5e88d0bd0e7e`, retaining upstream main
`e19ffb3286efec750b8729487220becf6569ab7b`.

Owned changes: this experiment folder, `tests/vehicle_fixture_tests.lua`,
`tests/vehicle_engine_adapter_tests.lua`, `tests/vehicle_movement_tests.lua`,
`tests/vehicle_movement_integration_tests.lua`, and their CMake registrations only.
No shared protocol/server, production runtime or installation changes.

## Creator and retained-handle follow-up

2026-10-15 UTC, base `e8070dd74192bf772415790d4e08852638df9b08`.
Two additional actual Engine + Fixture fault-injection regressions failed that
source under both Lua 5.4 and LuaJIT 2.1:

- After accepted deletion, replace the global dynamic-system getter with a ready
  empty system while the original creator's population still contains the
  detached actor. The fixture incorrectly reached `closed`, despite original
  `GetEntity` being nonempty and `IsSpawned` being true. Keeping the original
  getter as a negative control correctly kept cleanup pending.
- Return a different exact-ID wrapper with a truthy, non-Boolean attachment value.
  The adapter replaced its retained handle before the fixture rejected the
  sample. After that wrapper detached and both lookups disappeared, cleanup
  incorrectly reached `closed` while the first actor was still attached.

`Engine` now captures the creating DynamicEntitySystem before `CreateEntity` and
uses that reference for all lifecycle queries and deletion. An unready or unknown
creator blocks observation, even if a current global system is ready. Every
candidate attachment must be an explicit Boolean before retention changes; the
first exact attached actor remains retained and cannot be replaced by later
wrappers. Existing native request/ownership gates remain unchanged.

This is conditional source-defect evidence, not a claim that either injected
transition occurred in Cyberpunk. The pinned
[Codeware v1.18.0 implementation](https://github.com/psiberx/cp2077-codeware/blob/v1.18.0/src/App/World/DynamicEntitySystem.cpp)
separates managed state, population lookup and spawning status. `DeleteEntity`
removes its managed state before population removal is fully observed. The
regression therefore models management removal separately from population
absence; it does not equate an accepted delete with completed cleanup.

Fresh follow-up checks passed under each interpreter: engine adapter 596,
fixture 353, movement 111, movement integration 69. These include valid recovery,
unknown/unready original creator, detached/attached/malformed later wrappers,
and the two private actual-adapter regressions plus the negative control.
Private evidence: `D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-followup-audit`
(`creator-system-replacement-results.json`, `followup-baseline-results.json`,
`fixed-validation.json`, reproducer scripts and the pinned Codeware source).
`git diff --check` passed. No REDscript/native code changed, no new compiler/build
claim is made for this Lua-only correction, and no game was launched.

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
