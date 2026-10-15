# Vehicle fixture validation

UTC checkpoint: 2026-10-15. Owner: KyleBuildsAI. Branch:
`feat/vehicle-seat-observation`, based on upstream main
`e19ffb3286efec750b8729487220becf6569ab7b`.

Owned changes: this experiment folder, `tests/vehicle_fixture_tests.lua`,
`tests/vehicle_engine_adapter_tests.lua`, and their CMake registrations only.
No shared protocol/server, production runtime or installation changes.

## Passed locally

- Fresh Windows x64 Release plugin/server/core build with MSVC 19.41, VS 2022.
- 27/27 CTests, including both new vehicle suites.
- Lua 5.4 and LuaJIT 2.1: 353 lifecycle assertions and 159 engine adapter/activation
  assertions. Mocked engine evidence, not a running-game result.
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

Private evidence on KyleBuildsAI's machine:
`D:\Downloads\syncfix\bench-artifacts\20261015-vehicle-fixture`:
`windows-build.log`, `ctest.log`, LuaJIT evidence, and timestamped isolated
REDscript compile logs/JSON with input hashes.

## Not performed

No game launch, live car spawn, manual/injected seat transition, visual camera
check, two-PC test, default-package installation, Debian run, sanitizer run,
GitHub publication or release. The experiment is not in any game package.

`cameraVerified=false` is intentional in every fixture status/result/sample.
Vehicle-camera-manager values alone cannot certify actual player camera behavior.
The injected non-instant mount/unmount calls and the default Hella appearance
remain game-dependent gates. No shared-vehicle success is claimed.
