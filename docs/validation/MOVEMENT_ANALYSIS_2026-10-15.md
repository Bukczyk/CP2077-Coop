# Movement log analysis validation

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15.
Branch: `tooling/movement-log-analysis`.
Base: `691dc3975293dec6e4c9114785117f71d3b12389` (PR17 published package).

## Changes and ownership

- `scripts/analyze-movement.py`: offline schema-1 diagnostic reader/report.
- `tests/movement_analysis_tests.py` and `movement_analysis_fixture.lua`: parser
  evidence boundaries and actual recorder interoperability.
- `tests/CMakeLists.txt`: register the tool test with the built Lua interpreter.
- `.github/workflows/build.yml`: install Python3 in Debian so Python tests run
  there rather than silently missing the optional interpreter.
- `docs/MOVEMENT_LOG_ANALYSIS.md` and this evidence note.

No runtime, plugin, protocol, server or package payload changes. Existing release
assets remain byte-for-byte untouched. The tool is separate source tooling, not
a new mod/package version.

## Executed checks

- Python 3.13: 16/16 focused tests passed, including real Lua recorder output and
  finite input values whose derived distance would overflow.
- Fresh Windows x64 CMake configure with VS2022/MSVC19.41; test Lua executable built.
- CTest `movement_analysis`, `movement_diagnostics`, `movement_package`: 3/3 passed.
- Independent read-only review reran the initial 15 tests with the published build's Lua
  executable and found no blocking defect. ZIP member naming was checked against
  the actual collector script. Parent follow-up reproduced and fixed overflow in
  derived metrics; malformed distances remain explicit, never JSON Infinity/NaN.
- `git diff --check` passed before publication.

Hosted native Windows, Debian and sanitizer results must be recorded from the
new PR's actual CI. A new local native plugin build was not necessary or claimed:
all native/runtime sources are unchanged. No game launched, installed bytes,
configuration, controls or saves changed. No Poland logs or video have arrived
in the checked GitHub record, so no real movement measurements are claimed.

## Next evidence

Run the tool on both collector ZIPs when supplied. Use each local recording's
video to identify walking, stopping, turning, sideways/backward motion and two
reconnects. Report actual-readback distributions and explicit missing intervals.
Never turn lower-bound counter changes, a submitted command or a green tool test
into live-game qualification. See the analysis guide for supported measurements
and the known stale diagnostic labels in the frozen test package.
