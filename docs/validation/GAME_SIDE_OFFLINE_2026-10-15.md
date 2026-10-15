# Combined game-side source validation

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15. Verification branch:
`work/game-side-offline-20261015`. No main merge, installation or gameplay release.

This branch combines the following reviewable source slices on upstream main
`e19ffb3286efec750b8729487220becf6569ab7b` and the PR5/17 movement source:

| PR | Branch | Validated source |
| --- | --- | --- |
| 15 | feat/teammate-map-markers | d0da56a884aa7c16e0076ad41ceb464592f3c0f2 |
| 16 | feat/player-action-preparation | 1e32756846ea35e76f43df02769ca81a43af7567 |
| 19 | tooling/movement-log-analysis | 4bb510e2396a98691f0870fecc450e718b63493a |
| 20 | fix/player-diagnostic-recovery | 4d12c1c270eff26f152afda2a57ed39fb745bc15 |
| 21 | fix/dynamic-npc-lifecycle | bd6d941e785b418f5e32370f0258a67241a759eb |
| 22 | feat/vehicle-seat-observation | 15045bc77567719458110e12c74e5e88d0bd0e7e |
| 23 | feat/vehicle-pose-application | d0f8654e5a2b8742968837b078574593d843355d |
| 24 | fix/passive-asset-validation | 69f059896fa4049382ca14b06f08ff7d2d9e9bee |
| 25 | feat/passive-mitch-profile | 2a8bb541d59ba47596e5f66a65ad2fc38e77e197 |
| 26 | feat/passive-model-fixture | 97fd12f12a15257b76b92ecff102203743c601d9 |
| 27 | feat/npc-appearance-observation | ab9d106729ba2485d5449c34b1a0314cde93161a |

Combined source tested: `4b29a040ff1c8b4a2f98492ad0067f43887cb56f`.
PR12's connected controller is not integrated here. Only its existing pure
presentation-state `restore` method is reused by the local fixture. Its connected
evidence remains separate, and the life-baseline bridge request awaits coordination.

## Actual conflict resolution

`init.lua` and `tests/session_lifecycle_tests.lua` overlap between the player
and NPC cleanup fixes. Retain both owners and every regression, use one protected
pause query per tick, and increment the clock exactly once in ordinary/failed
updates. Missing/malformed pause context becomes unknown for NPCs and paused for
players. A throwing handler getter remains fatal after observation invalidation;
a throwing pause method is nonfatal unknown. Other early engine errors invalidate
both owners at the same timestamp. A failure in player cleanup must not prevent
the independent NPC pump. The combined real-entrypoint tests cover these cases.

The latest two-NPC regression additionally invalidates cached observations before
`stop/reset`, preventing cleanup from qualifying a skipped actor with the preceding
frame's context. Both invalidations reuse one timestamp. Merge resolution retains
all player regressions and the actual NPC runtime/adapter fixture.

PR15's marker lifecycle and session UI are now integrated with the player/NPC
cleanup changes. Its failed-mode player lookup is protected so a persistent
engine error cannot prevent cleanup. All marker/UI and actor regressions remain.
PR16's experiments stay opt-in and separate from ordinary movement; native action
and aim sources must remain matched because the lease pins an exact weapon ID.

PR16 now includes a usable local CET entrypoint for those existing controllers.
Explicit start creates one disposable Judy per fixture activation, fresh capture
follows weapon/stance changes and an explicitly injected Aim test exercises the
existing lease/Normal path. These local intents are not network input or observed
physical aiming. Exact native actor/creator ownership survives uncertain outcomes;
cleanup requires observed disappearance. Shutdown alone cannot promise cleanup.
The only new merge conflict was adjacent test registrations; all previous tests
and the new player fixture registration are retained. See
`PLAYER_PRESENTATION_FIXTURE.md` for staging and the remaining visual gates.

Test registrations merged without dropping any existing suite. No networking,
protocol, server or shared bridge behavior was changed to resolve integration.

The static player/NPC follow-ups now preserve creator, token and first observed
actor through unknown observations and pending callbacks. Creation must be
confirmed by the exact creator before later absence can release ownership.
Both actual-entrypoint regressions fail against their preceding adapters.
The new NPC reconnect test initially lacked the empty `GetTaggedIDs` method used
by the existing PR5 player-discovery path; the fixture now provides that method
alongside `GetTagged`. No runtime behavior was weakened to make the test pass.

The vehicle follow-up pins the original creating system and first attached exact
actor. A replacement system or malformed later wrapper cannot certify the old
car's disappearance. Both fault-injection regressions fail the preceding adapter
and pass the fix. This does not establish that either injected transition occurs
in a running game.

The separate model fixture selects Judy/Mitch through explicit local slots,
queues all engine work to onUpdate, checks the exact template and pose, and
retains pending/unknown lifetimes until observed retirement. It does not bind
network entities or change production selection. Model and vehicle follow-ups
merged without conflicts; all prior registrations and regressions remain.

The appearance follow-up adds a separate read-only Entity helper. The local
fixture requires an observed current name exactly matching requested `default`;
missing/wrong names block readiness and movement while exact retirement remains
available. The final mutation actor is rechecked, and rejected preflight clears
cached qualification. A current name is not proof of visible mesh/animation.

PR27 adds a separate read-only observation tool, not a production selector. It
captures an explicit NPC's exact record/template/current appearance/color on
the game thread, preserves native-produced decimal identifiers and copies
historical samples. Exact native references distinguish fresh Lua wrappers from
real replacement. Invalid scope/identity/readback cannot qualify a sample.
The only integration conflict was adjacent additions in tests/CMakeLists.txt;
both the four vehicle tests and new NPC observation registration were retained.

The vehicle seat follow-up checks fresh pause/menu/creator/spawn context before
native submission, with a second native pause/menu guard. Definite preflight
failure leaves no pending transition; a native exception still retains unknown
ownership. The new cosmetic correction checks frozen supported appearance/color
before mounting and permits safe exact unmount during cosmetic quarantine. Both
seat relationship views are checked freshly; completion still needs matching
events and actual exit. Wrong record remains a separate persistent identity fault.

The passive model follow-up observes coherent current appearance/color names and
exact native hashes, without claiming a supported color or visual match. Native
reference checks distinguish fresh Lua wrappers from different same-ID actors.
Movement and cleanup cannot target a replacement. Separate identity checks let
exact cleanup continue when only cosmetic readback fails; unknown native removal
is not automatically retried. Both follow-ups merged without conflicts, leaving
all existing suites and shared contracts intact.

The next PR26 follow-up adds a pure historical comparison between PR27 source
observations and an explicit local fixture slot. Exact record/template/appearance
identifiers establish only the reviewed Judy/Mitch resource relationship; source
and proxy appearance names deliberately differ. Contradictory or unsupported
tuples and stale slot generations cannot become candidates. Observed color
equality remains separate from visual qualification. Copied snapshots are neither
authenticated nor simultaneous/current evidence. No model selection, engine call,
native helper, lifecycle mutation, shared interface or asset changed. This merged
without conflicts; the seven contributed files match the exact PR26 source.

The encounter-asset follow-up adds a separately named Mitch entity for the
existing phase/progress graph and a strict Judy/Mitch private builder. Both
component copies require the reviewed male mesh/rig/three animation sets and
dependency metadata; full normalized Data must match the pinned Judy reference
after only checked profile substitutions. Disabled/mistyped control bindings
cannot hide in matching copies. Existing assets, graph, Lua fixture and PR12
remained unchanged by that asset slice. It merged without conflicts and preserved
every existing test registration.

The latest fixture extension explicitly selects Judy/Mitch encounter profiles,
stages reaction/death onUpdate and checks original native identity before every
setter. Logical terminal death survives body retirement/replacement in this
fixture instance; old nonlethal hits do not replay. Fresh commands admitted before
binding keep their own serial. Per-slot effective clocks freeze on pause or failed
observation without blocking siblings. Partial setters can retry only the latest
normalized sample. Queue submission remains unobserved animation, not health or
network synchronization. The ten files merged without conflicts; native helpers,
assets, production runtime and shared network contracts are unchanged.

The latest vehicle movement correction rejects stale ready observations at the
Lua/native boundary. Loaded/unpaused context, original creator/lifecycle and the
frozen creation appearance are checked again before entry. The matched native
helper independently checks context and the supplied expected appearance. A
changed record default plus changed actual appearance cannot admit a move.
Definite preflight failure creates no pending command; native exceptions retain
uncertain ownership. Position/rotation/settling readback remains required. The
six files merged without conflicts; seat policy and the controller are unchanged.

## Passed offline

- Fresh configure and incremental Windows x64 Release plugin, session server
  and core build passed. Native inputs are unchanged; all previous 48 tests remain
  registered alongside the new player action fixture.
- 49/49 CTests, including existing real-socket/core tests and the new suites.
- 28 focused suites under LuaJIT 2.1, including exact Uint64 identity, cleanup,
  failure clocks, command state, diagnostics, NPCs, vehicle fixtures, player
  action/readiness, marker/UI/facing and native-shaped map capture.
- 23 new passive visual-contract mutation tests and the existing 9 hittable tests
  are included. These validate the fixed reviewed Judy/default assets, not arbitrary
  HOST appearance matching; authored assets and archives remain unchanged.
- 22 profile tests cover the separate Mitch/default authored entity and explicit
  Judy/Mitch builder, including exact dependency tables and LF/CRLF source pins.
  Private WolvenKit builds of both profiles passed serialization roundtrip,
  single-resource archive listing and extracted-byte parity. The existing Judy
  entity, authored idle graph and production builders remain unchanged.
- 23 new encounter-profile tests and 37 independent controls passed. Pinned
  WolvenKit 9.0.1 compiled and roundtripped both encounter profiles; direct
  archive listing, singleton extracted-byte parity and existing-output refusal
  passed. Judy entity bytes match the earlier encounter build. Fourteen protected
  asset/runtime files remain unchanged. These private archives contain only one
  authored entity; the unchanged graph and installed resources are external.
- 811 focused model-fixture checks in Lua 5.4 and 813 in LuaJIT: 180 controller,
  334/336 actual adapter and 297 real entrypoint checks. Independent review covered
  per-slot failure isolation, late callbacks, unknown/duplicate creation,
  stale generations, wrong templates, observed pose and bounded diagnostics.
  Current-name mismatch/unavailability, sibling isolation, recovery, exact
  cleanup and final-actor appearance/color changes are covered by the actual modules.
  Thirty independent scenarios per runtime additionally cover native replacements,
  fresh wrappers, current context, None/zero versus unknown, and cleanup isolation.
  The original a105a22 retirement regression deletes a different same-ID actor;
  the corrected actual entrypoint refuses that deletion in both Lua runtimes.
  The real Lua resource catalog matches the Python builder for both profiles.
  The comparison adds 54 independent actual-PR27-producer-to-PR26-consumer checks
  per runtime, with mocked native boundaries. Four audited resource SHA256s and
  seven computed native identifiers agree with metadata and the pinned SDK.
- New encounter integration: 237 controller and 305 engine checks per runtime
  passed in independent literal-path CET-style sandboxes with no package/global
  module fallback. These use the actual staged modules and mocked native APIs.
  Initial/replacement binding, retained death, stale commands, per-slot pause,
  setter ordering, exact reference checks and partial retry are covered. Shared
  state/adapter and connected-encounter suites also pass with the reused method.
- Vehicle follow-up: 6846 adapter, 544 fixture, 111 movement and 69 integration
  checks per Lua interpreter, including retained creator/actor recovery and the
  actual-entrypoint paused-request regression. Five additional cosmetic/record
  regressions fail c129eb3 and pass this correction under both interpreters;
  eighteen independent scenarios per interpreter also passed. The earlier
  pause regression against f95cacc remains preserved.
- Movement admission: five old/fixed actual-entrypoint controls reproduce both
  pregame and changed-default/current-appearance admissions at cc66fb9, then
  reject them before helper entry. Twenty independent scenarios per interpreter
  cover fresh rejection/recovery, changes after Lua preflight, full arguments,
  observed settling and uncertain native outcome retention. Native behavior is
  modeled in Lua; compilation does not execute it in the game.
- NPC observation: 431 focused Lua 5.4 and 434 LuaJIT checks passed on its branch,
  plus 14 independent probes per interpreter. The new actual-entrypoint suite is
  also included in the combined CTest/LuaJIT runs. Its separate branch passed a
  fresh Windows Release build and 26 CTests; native execution remains untested.
- Player action fixture: 432 Lua 5.4 / 442 LuaJIT actual-entrypoint checks pass;
  the unchanged action/probe suite still passes 328 checks per runtime. Independent
  review passes 14 scenarios with 39 additional assertions per runtime. Native
  boundaries are mocked; this does not demonstrate visible ADS, weapon grip or
  competing NPC AI behavior. Branch Release core/session checks pass 30 CTests
  with plugin OFF; the combined build above includes the plugin.
- Isolated current session, vehicle, player action/aim, map capture and the new
  passive-model current-appearance and exact NPC observation helpers' REDscript
  compilation together against copied installed 2.31 cache/Codeware inputs.
  Source, compiler and installed reference input hashes unchanged.
- `git diff --check`; no unresolved merge markers.

Current player action fixture logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-player-action-fixture`,
`combined-validation.json` and configure/build/CTest/LuaJIT logs: 49 CTests and
28 LuaJIT suites pass at `4b29a04`, retaining all prior registrations. Windows
Release includes the plugin; measured source/test hashes stayed unchanged.
`combined-compile-20261015T124520549916Z.json` records matched session scripts plus
vehicle, player/map (including the new fixture helper), passive-model and NPC
observation scripts compiling in isolation against copied game inputs. All
compiler/source/reference hashes stayed unchanged. Hosted results are recorded
against final published heads in GitHub and the vault. No live validation,
installation or package release occurred.

Previous vehicle movement-preflight logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-vehicle-movement-preflight`,
`combined-validation.json` and configure/build/CTest/LuaJIT logs: 48 CTests and
27 LuaJIT suites pass at `447a3ae`. Windows Release includes the plugin. All 117
tracked source hashes stayed unchanged during validation. The branch passed
29 CTests with its Release plugin build. `combined-compile-20261015T121749844034Z.json`
and its log record successful isolated compilation of session scripts plus the
vehicle, player/map, passive-model and NPC-observation experiment groups.
Separate connected-combat scripts were not added to that compilation. Source,
installed and compiler inputs stayed unchanged. Final hosted checks are tracked
against published heads in GitHub and the vault. No package or game was changed.

Previous encounter-fixture logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-passive-encounter-fixture`,
`combined-validation.json`, configure/build/CTest/LuaJIT logs: 48 CTests and
27 LuaJIT suites passed at `3d2f4fe1`. The separate branch passed 31 CTests and
six LuaJIT suites. Exact source/test hashes stayed unchanged. Native and REDscript
inputs remain identical, so the prior isolated script compilation still applies.
Independent staged-module reviews and the frozen ten-file manifest are retained
there. Hosted final-head checks are recorded separately in GitHub and the vault.
No game was launched or installed and no package version was published.

Previous encounter-asset logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-mitch-encounter-profile`,
`combined-validation.json`, `combined-build.log`, `combined-ctest.log` and
`combined-luajit.log`: 48 CTests and 24 LuaJIT suites pass at `d49d750c`.
The separate branch passed 31 CTests and its core/session Release build with
plugin excluded. Source hashes stayed unchanged during validation. Native,
Lua and REDscript inputs are unchanged from `54eba8c`; the previous isolated
script compilation still applies. Independent build/review evidence and frozen
source hashes are in the same folder. Final hosted checks are recorded against
published heads in GitHub and the vault. No live game behavior is established.

Previous comparison logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-passive-appearance-comparison`,
`combined-validation.json`, `combined-ctest.log` and `combined-luajit.log`:
47 CTests and 24 LuaJIT suites pass at `8329c8e`. Branch validation passes 30
CTests. Native, build-definition and REDscript inputs are unchanged from
`cfa8c38362ac8ff0b0be96cd6c156877ab9fb4d2`; its matching Release build and the
prior isolated compilation apply without repeating them. Hosted final-head
results are recorded separately in GitHub and the vault. The focused and
independent comparison evidence and frozen hashes are in this same folder.

Previous coherent-color combined logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-passive-profile-color-observation`,
`combined-validation.json`, `combined-ctest.log` and `combined-luajit.log`:
47 CTests and 24 LuaJIT suites pass at `41a24f6`. Native source, runtime and target
definitions are unchanged from the preceding verified head, so matching existing
Release binaries were reused. `combined-compile-20261015T104911230079Z.json` and
its log record all current session/experiment REDscript sources compiling together
with unchanged inputs. The independent branch checks and historical failures are
in that folder and `20261015-vehicle-cosmetic-exit-fix`. These results do not execute
the native engine or prove visible matching. Final hosted validation is tracked
against the published commit in GitHub Actions and the vault handoff.

Previous NPC-observer combined logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-npc-appearance-observation`,
`combined-ctest.log` and `combined-luajit.log`: 47 CTests and 24 LuaJIT suites pass
at d2ea170. The prior native Release build is recorded
in `20261015-passive-model-fixture-audit/combined-build.log`. The current folder
contains `combined-compile-20261015T101444214928Z.json` and `.log`:
all current session and selected experiment REDscript sources compile together,
with distinct experiment folders preventing same-name source overwrites.
Original inputs remained unchanged. Compilation does not execute engine behavior.

Previous appearance checkpoint logs remain in `20261015-passive-model-appearance`
(46 CTests/23 LuaJIT suites), with its compiler evidence in
`20261015-passive-model-fixture-audit/combined-compile-20261015T094012683483Z.*`.

Earlier static cleanup logs: `D:/Downloads/syncfix/bench-artifacts/20261015-game-side-goal`,
`combined-static-cleanup-build.log`, `combined-static-cleanup-ctest-final.log`,
`combined-static-cleanup-luajit-final.log` and
`redscript/compile-20261015T081404930677Z.*`. The 43 CTests and all 20 LuaJIT suites
were rerun on the combined corrected source. REDscript compilation remains the
verified `af5a24a` result: every REDscript byte is unchanged. The initial combined
fixture failure remains in the unsuffixed static-cleanup logs. Hosted branch
checks are recorded separately after completion.

## Open gates

This does not establish smooth multiplayer, correct live detachment, passive AI,
matching NPC appearance/life baselines, vehicle physics, passenger motion or camera
correctness. The vehicle experiment remains manually enabled and unoccupied only.
Map capture produces raw native measurements and candidate bases, not qualified
render timing, clipping or arrow facing. Weapon attachment/readback and logical
Aim do not prove visible ADS/grip. Neither source experiment is default-installed.
The full goal and all relevant live/two-PC gates remain open. Continue independent
source work while live testing is deferred and bridge requirements await agreement.
PR26 supplies the separate explicit local profile selection fixture. It still
needs deferred live model/idle/cleanup qualification and an agreed supported
HOST descriptor mapping before connected production use. Resource presence and
an exact template hash do not certify the installed mesh or visible appearance.
PR27 must still sample real NPCs in a future authorized test. Its local scope is
not a network epoch; network-only reconnect requires an explicit harness reset.
Unknown never-completed static spawns remain held if terminal cancellation cannot
be established; no timeout is treated as evidence of safe cleanup. Actual callback
scheduling, scene teardown and recovery still need the deferred live validation.

Published `v0.1.0-movement-experiment.1` remains at source `691dc397...`.
Its HOST/JOINER ZIP hashes were reverified unchanged. No games, settings, bindings,
private connection configuration or saves were modified; no Discord message sent.
