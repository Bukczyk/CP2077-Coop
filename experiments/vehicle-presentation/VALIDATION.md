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

## Fresh seat-request context correction, 2026-10-15

The real CET entrypoint accepted a mount after the game became paused between its
last ready observation and the request. The existing native helper also lacked a
pause/menu gate. An actual-entrypoint regression fails against `f95cacc` and passes
with this correction under Lua 5.4 and LuaJIT 2.1.

The adapter now requires explicit false pause/pregame flags, the exact attached
creator and a completed managed spawn immediately before requesting a seat. A
missing/throwing context read or incomplete identity/readiness returns a definite
rejection before the native request, with no pending request left behind. The
native helper independently checks pause/pregame. An exception after entering the
native helper still retains ambiguous request ownership. No queued call is treated
as a completed seat transition.

Validation on this source:

- Compiled Lua 5.4 and LuaJIT 2.1 each pass all four suites: 353 fixture, 1645 engine
  adapter, 111 movement and 69 movement-integration checks. The adapter suite uses
  the actual `init.lua`, `Engine` and `Fixture`, covering pause/pregame true or
  unknown, missing/throwing reads, detached creator and unknown spawn flags after
  the last ready update. It verifies rejection without a pending lock, subsequent
  exact-event/relationship mount and unmount recovery, and retained ownership
  after a native exception.
- 29/29 branch CTests pass using the existing Windows Release build. This is not a
  fresh C++ build; no C++ source changed.
- Isolated session plus vehicle REDscript compilation passes against the installed
  game 2.31 cache and Codeware scripts. Original source/game/compiler input hashes
  remain unchanged. Evidence:
  `D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-seat-preflight-audit\redscript\compile-20261015T100956741471Z.json`.

Private evidence under `D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-seat-preflight-audit`:
`before-after-results.json`, `before-after-entrypoint-repro.lua`, `validation.json`
and `ctest.log`. No game was launched or installed/configuration file changed.

### Cosmetic issue discovered at that checkpoint

An actual-entrypoint reproduction changes the observed car's appearance from the
supported default after a ready sample but before mounting. The baseline accepts
the request using that stale sample (`appearance-seat-repro.lua` and
`appearance-results.json`, both interpreters). The fresh pause/context correction
does not address appearance or color changes and does not certify those values
at seat-request time.

The following correction addresses this separate issue. The original evidence is
preserved; those earlier tests do not establish the newer behavior.

## Fresh cosmetic admission and safe exit correction, 2026-10-15

Base: `c129eb384e96b0d780c9f6a56bcdd2ce0959935d`. Exact follow-up ownership:
`fixture.lua`, `engine.lua`, `engine_hooks.reds`, `README.md`, `VALIDATION.md` in this
folder, plus `tests/vehicle_fixture_tests.lua` and
`tests/vehicle_engine_adapter_tests.lua`. No entrypoint, movement-controller,
CMake, backend/protocol, package or installed-file change.

The original actual-entrypoint reproduction also established that, after an exact
completed mount, observing a cosmetic mismatch made injected unmount return
`not_ready`. Restoring the original cosmetics did not clear that refusal. This
was a fixture API defect, not proof of physical entrapment; manual exit was not
tested.

New mount admission checks the exact record, current default, frozen creation
appearance, actual appearance and supported color immediately before submission.
The native helper receives that frozen appearance and repeats the mount-only
check. Missing or throwing cosmetic reads reject before the helper, without a
pending owner. The helper and Lua adapter must be staged from the same checkpoint
because the helper now takes a fourth expected-appearance argument.

Cosmetic quarantine is deliberately sticky until safe empty-car cleanup. It
prevents new mounts and motion, but permits an exact safe unmount even after the
original cosmetics return. The current creator, lifecycle, pause/menu, speed,
pending-request and exact seat gates remain. Player and vehicle relationships are
checked freshly in Lua and again in native code. Missing/throwing cosmetic binding
lookups or calls no longer discard otherwise valid identity/seat observations.
Exit completion still requires its finished event plus on-foot/occupancy readback.
An exception after entering the native request retains uncertain ownership.

A wrong record is a persistent noncosmetic fault. Observation checks it before
the native ownership helper can reject and hide the evidence; fresh request
preflight also retains that fault. Native ownership independently retains a record
mismatch. Restoring the record cannot authorize later requests or cleanup.

Passed on the corrected source:

- Compiled Lua 5.4 and LuaJIT 2.1: 544 fixture, 3655 engine adapter, 111 movement
  and 69 movement-integration checks per interpreter. The new adapter scenarios
  run the actual entrypoint and modules, with only engine/native boundaries mocked.
- Five focused actual-entrypoint scenarios fail against `c129eb3` and pass on
  this source in both runtimes: changed cosmetic mount admission, safe cosmetic
  exit, throwing cosmetic read, fresh record restoration and observed record
  restoration.
- Independent read-only review passes both focused suites and 18 additional
  actual-entrypoint scenarios per runtime. It identified and verified fixes for
  a record fault hidden by the ownership helper and a cosmetic method lookup
  outside its exception guard.
- 29/29 branch CTests pass against the existing Windows Release build. No C++
  source changed and no fresh C++ build is claimed for this correction.
- Parent-run isolated session plus vehicle REDscript compilation passes against
  installed 2.31/Codeware inputs, with source/game/compiler input hashes unchanged:
  `redscript/compile-20261015T103546240408Z.json` and its matching log.
- `git diff --check` passes. No live test or camera restoration is claimed;
  `cameraVerified=false` remains explicit.

New private evidence directory:
`D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-cosmetic-exit-fix`.
It contains `baseline.json`, frozen baseline adapter/controller copies,
`before-after-repro.lua`, `before-after-results.json`, `validation.json`,
`ctest.log`, independent review evidence and the isolated compile JSON/log.
Earlier evidence remains unchanged.

## Fresh movement descriptor/context correction, 2026-10-15

Base: `cc66fb9ae1683d3bf5b7384e45578ffcbf9f8a5b`. Exact six-file scope:
`engine.lua`, `engine_hooks.reds`, `README.md`, `VALIDATION.md`,
`tests/vehicle_engine_adapter_tests.lua` and
`tests/vehicle_movement_integration_tests.lua`. The fixture, movement controller,
entrypoint, seat policy, native plugin, protocol and package contents are unchanged.

The preceding actual-entrypoint audit reproduced two gaps after a valid ready
sample: pregame becoming true still admitted movement; and the actual car
appearance plus current record default could both change away from the frozen
creation appearance and still admit movement. The native boundary was modeled
from inspected source, not executed in a game.

Movement now uses fresh explicit loaded/unpaused context, the retained creator
system's ready/managed/spawned/not-spawning flags, attached car and creator IDs,
exact supported record and the frozen appearance/color contract. All those Lua
reads and native argument construction occur before helper entry in a protected
preflight. A failure returns false without pending/ambiguous movement ownership.
The native helper gains a final `expectedAppearance: CName` argument and
independently checks pause/pregame and current record/appearance/color against it.
Use matched Lua/helper files. The actual native invocation remains outside the
preflight exception guard: a native exception may follow submission and must
retain unknown outcome ownership. Existing safe-exit, occupied-car and cleanup
rules are unchanged.

Private evidence:
`D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-movement-preflight`.

- `baseline-fixed-reproductions.json` / `validate_focused.py`: the exact preceding
  source is preserved in `baseline-cc66fb9`. Five cases run against old and fixed
  actual entrypoints in both Lua runtimes. The changed-default/current-appearance
  and pregame admissions reproduce on the old source, then reject before helper
  entry on the fix. The same inspected old-helper boundary model is used on both
  sources, isolating the Lua correction. Valid, paused and appearance-only
  controls retain their expected outcomes.
- `focused-lua-validation.json`: all four vehicle suites pass under compiled
  Lua 5.4 and LuaJIT, with 544 fixture, 6,846 engine adapter, 111 movement and
  69 movement-integration checks per runtime. These include assertion checks in
  the native mocks, not 7,570 separate scenarios. The new actual-entrypoint cases
  cover nil/non-Boolean/throwing context, missing/throwing cosmetics, matched but
  changed defaults, original creator readiness, exact identities, fresh record
  faults, changes after Lua preflight, explicit recovery, constructor failure,
  full quaternion forwarding and unknown native result/cleanup exclusion.
- `redscript/compile-20261015T120933800908Z.json` and its log: isolated compilation
  of matched session and experimental vehicle scripts against copied actual
  game 2.31 cache/compiler and Codeware succeeds. Source, installed and compiler
  input hashes are unchanged. No installed files were written and no game ran.
- `independent-final-review.json` and `independent-entrypoint-final-review.json`:
  independent review reran all four suites in both runtimes and 20 additional
  actual-entrypoint scenarios (920 checks per runtime). It verified the current
  helper hash against the successful compilation and rechecked the installed
  input hashes. The source, tests and matched-file documentation passed review.
- `branch-validation.json` and `branch-{configure,build,ctest}.log`: reconfigure
  and incremental Windows x64 Release build passed using the existing Visual
  Studio 17 2022 configuration, `COOP_BUILD_PLUGIN=ON`. All 29/29 CTests passed;
  the same 29 tests remain registered. Executable source/test hashes stayed
  unchanged. This was an incremental validation, not a fresh C++ implementation.
  `frozen-source-manifest.json` pins all six scoped files. Hosted CI is checked
  separately after publication.

The native guard behavior in the Lua cases is a model of inspected REDscript.
Successful compilation does not execute its runtime checks. Actual teleport,
appearance, physics settling, seats and camera behavior remain live gates.
`movementQualified=false` and `cameraVerified=false` remain explicit. This fixes
admission for the existing supported local fixture; it does not synchronize cars
between PCs or add vehicle authority.

## Original checkpoint passed locally

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
