# Combined game-side source validation

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15. Verification branch:
`work/game-side-offline-20261015`. No main merge, installation or gameplay release.

This branch combines the following reviewable source slices on upstream main
`e19ffb3286efec750b8729487220becf6569ab7b` and the PR5/17 movement source:

| PR | Branch | Validated source |
| --- | --- | --- |
| 15 | feat/teammate-map-markers | d0da56a884aa7c16e0076ad41ceb464592f3c0f2 |
| 16 | feat/player-action-preparation | 75a7a211da8775158a5c6d8f43bb137554dce0dc |
| 19 | tooling/movement-log-analysis | 4bb510e2396a98691f0870fecc450e718b63493a |
| 20 | fix/player-diagnostic-recovery | 4d12c1c270eff26f152afda2a57ed39fb745bc15 |
| 21 | fix/dynamic-npc-lifecycle | bd6d941e785b418f5e32370f0258a67241a759eb |
| 22 | feat/vehicle-seat-observation | 15045bc77567719458110e12c74e5e88d0bd0e7e |
| 23 | feat/vehicle-pose-application | cc66fb9ae1683d3bf5b7384e45578ffcbf9f8a5b |
| 24 | fix/passive-asset-validation | 69f059896fa4049382ca14b06f08ff7d2d9e9bee |
| 25 | feat/passive-mitch-profile | 2a8bb541d59ba47596e5f66a65ad2fc38e77e197 |
| 26 | feat/passive-model-fixture | d6ae28f4018ddf2f95f385270759e6c638997d70 |
| 27 | feat/npc-appearance-observation | ab9d106729ba2485d5449c34b1a0314cde93161a |

Combined source tested: `41a24f69511e83000cebe6287d2d9de38fc7e5ab`.
PR12 restoration is not merged into this verification branch. Its earlier
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

## Passed offline

- Windows x64 Release plugin, session server and core build at the preceding
  checkpoint. C++ source and target definitions are unchanged by this follow-up;
  CMake was regenerated for the new test and matching existing binaries were used.
- 47/47 CTests, including existing real-socket/core tests and the new suites.
- 24 focused suites under LuaJIT 2.1, including exact Uint64 identity, cleanup,
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
- 479 focused model-fixture checks in Lua 5.4 and 481 in LuaJIT: 60 controller,
  248/250 actual adapter and 171 real entrypoint checks. Independent review covered
  per-slot failure isolation, late callbacks, unknown/duplicate creation,
  stale generations, wrong templates, observed pose and bounded diagnostics.
  Current-name mismatch/unavailability, sibling isolation, recovery, exact
  cleanup and final-actor appearance/color changes are covered by the actual modules.
  Thirty independent scenarios per runtime additionally cover native replacements,
  fresh wrappers, current context, None/zero versus unknown, and cleanup isolation.
  The original a105a22 retirement regression deletes a different same-ID actor;
  the corrected actual entrypoint refuses that deletion in both Lua runtimes.
  The real Lua resource catalog matches the Python builder for both profiles.
- Vehicle follow-up: 3655 adapter, 544 fixture, 111 movement and 69 integration
  checks per Lua interpreter, including retained creator/actor recovery and the
  actual-entrypoint paused-request regression. Five additional cosmetic/record
  regressions fail c129eb3 and pass this correction under both interpreters;
  eighteen independent scenarios per interpreter also passed. The earlier
  pause regression against f95cacc remains preserved.
- NPC observation: 431 focused Lua 5.4 and 434 LuaJIT checks passed on its branch,
  plus 14 independent probes per interpreter. The new actual-entrypoint suite is
  also included in the combined CTest/LuaJIT runs. Its separate branch passed a
  fresh Windows Release build and 26 CTests; native execution remains untested.
- Isolated current session, vehicle, player action/aim, map capture and the new
  passive-model current-appearance and exact NPC observation helpers' REDscript
  compilation together against copied installed 2.31 cache/Codeware inputs.
  Source, compiler and installed reference input hashes unchanged.
- `git diff --check`; no unresolved merge markers.

Current combined logs:
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
