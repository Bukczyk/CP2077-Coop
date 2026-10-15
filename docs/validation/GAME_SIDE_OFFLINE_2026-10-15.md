# Combined game-side source validation

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15 08:15. Verification branch:
`work/game-side-offline-20261015`. No main merge, installation or gameplay release.

This branch combines the following reviewable source slices on upstream main
`e19ffb3286efec750b8729487220becf6569ab7b` and the PR5/17 movement source:

| PR | Branch | Validated source |
| --- | --- | --- |
| 15 | feat/teammate-map-markers | d0da56a884aa7c16e0076ad41ceb464592f3c0f2 |
| 16 | feat/player-action-preparation | 75a7a211da8775158a5c6d8f43bb137554dce0dc |
| 19 | tooling/movement-log-analysis | 4bb510e2396a98691f0870fecc450e718b63493a |
| 20 | fix/player-diagnostic-recovery | a4d05313772946d1f3036b218c97e176b094398e |
| 21 | fix/dynamic-npc-lifecycle | 4f56311052bb2949f05aeda036b2a8d0b2883987 |
| 22 | feat/vehicle-seat-observation | 15045bc77567719458110e12c74e5e88d0bd0e7e |
| 23 | feat/vehicle-pose-application | e8070dd74192bf772415790d4e08852638df9b08 |
| 24 | fix/passive-asset-validation | 69f059896fa4049382ca14b06f08ff7d2d9e9bee |

Combined source tested: `af5a24ae6b6324bda24a4846df26424973fff216`.
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

## Passed offline

- Windows x64 Release plugin, session server and core build.
- 42/42 CTests, including existing real-socket/core tests and the new suites.
- 20 focused suites under LuaJIT 2.1, including exact Uint64 identity, cleanup,
  failure clocks, command state, diagnostics, NPCs, vehicle fixtures, player
  action/readiness, marker/UI/facing and native-shaped map capture.
- 23 new passive visual-contract mutation tests and the existing 9 hittable tests
  are included. These validate the fixed reviewed Judy/default assets, not arbitrary
  HOST appearance matching; authored assets and archives remain unchanged.
- Isolated current session, vehicle, player action/aim and map capture REDscript
  compilation together against copied installed 2.31 cache/Codeware inputs.
  Source, compiler and installed reference input hashes unchanged.
- `git diff --check`; no unresolved merge markers.

Private logs: `D:/Downloads/syncfix/bench-artifacts/20261015-game-side-goal`,
`combined-map-build.log`, `combined-readiness-ctest.log`,
`combined-readiness-luajit.log` and `redscript/compile-20261015T081404930677Z.*`.
Hosted branch checks are recorded separately after completion.

## Open gates

This does not establish smooth multiplayer, correct live detachment, passive AI,
matching NPC appearance/life baselines, vehicle physics, passenger motion or camera
correctness. The vehicle experiment remains manually enabled and unoccupied only.
Map capture produces raw native measurements and candidate bases, not qualified
render timing, clipping or arrow facing. Weapon attachment/readback and logical
Aim do not prove visible ADS/grip. Neither source experiment is default-installed.
The full goal and all relevant live/two-PC gates remain open. Continue independent
source work while live testing is deferred and bridge requirements await agreement.

Published `v0.1.0-movement-experiment.1` remains at source `691dc397...`.
Its HOST/JOINER ZIP hashes were reverified unchanged. No games, settings, bindings,
private connection configuration or saves were modified; no Discord message sent.
