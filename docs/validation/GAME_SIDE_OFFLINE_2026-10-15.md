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
| 23 | feat/vehicle-pose-application | f95caccb62f0f46ecb48d0b74749c084f4121f38 |
| 24 | fix/passive-asset-validation | 69f059896fa4049382ca14b06f08ff7d2d9e9bee |
| 25 | feat/passive-mitch-profile | 2a8bb541d59ba47596e5f66a65ad2fc38e77e197 |
| 26 | feat/passive-model-fixture | a105a228d2fd5505f071f0e6dd11d05d6493cedd |

Combined source tested: `5f4e409c7422afde60a0762cfa92a3c4f343be10`.
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

## Passed offline

- Windows x64 Release plugin, session server and core build at the preceding
  checkpoint. Native source/build definitions are unchanged by this Lua/REDscript
  follow-up; existing matching binaries were used for the repeated CTests.
- 46/46 CTests, including existing real-socket/core tests and the new suites.
- 23 focused suites under LuaJIT 2.1, including exact Uint64 identity, cleanup,
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
- 299 focused model-fixture checks per Lua 5.4/LuaJIT run: 52 controller, 153
  actual adapter and 94 real entrypoint checks. Independent review covered
  per-slot failure isolation, late callbacks, unknown/duplicate creation,
  stale generations, wrong templates, observed pose and bounded diagnostics.
  Current-name mismatch/unavailability, sibling isolation, recovery, exact
  cleanup and final-actor appearance changes are covered by the actual modules.
  The real Lua resource catalog matches the Python builder for both profiles.
- Vehicle follow-up: 596 adapter, 353 fixture, 111 movement and 69 integration
  checks per Lua interpreter, including retained creator/actor recovery.
- Isolated current session, vehicle, player action/aim, map capture and the new
  passive-model current-appearance helper REDscript
  compilation together against copied installed 2.31 cache/Codeware inputs.
  Source, compiler and installed reference input hashes unchanged.
- `git diff --check`; no unresolved merge markers.

Current combined logs:
`D:/Downloads/syncfix/bench-artifacts/20261015-passive-model-appearance`,
`combined-ctest.log` and `combined-luajit.log`: 46 CTests and 23 LuaJIT suites pass
again at the current tested source. The prior native Release build is recorded
in `20261015-passive-model-fixture-audit/combined-build.log`.
That folder also contains `combined-compile-20261015T094012683483Z.json` and `.log`:
all current session and selected experiment REDscript sources compile together,
with distinct experiment folders preventing same-name source overwrites.
Original inputs remained unchanged. Compilation does not execute engine behavior.

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
Unknown never-completed static spawns remain held if terminal cancellation cannot
be established; no timeout is treated as evidence of safe cleanup. Actual callback
scheduling, scene teardown and recovery still need the deferred live validation.

Published `v0.1.0-movement-experiment.1` remains at source `691dc397...`.
Its HOST/JOINER ZIP hashes were reverified unchanged. No games, settings, bindings,
private connection configuration or saves were modified; no Discord message sent.
