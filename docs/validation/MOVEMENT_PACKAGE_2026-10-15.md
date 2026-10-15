# PR #5 + PR #17 experimental package validation

UTC: 2026-10-15. Owner: KyleBuildsAI. Branch: `fix/player-motor-reliability`.
Goal: prepare matching experimental HOST/JOINER files for Bukczyk's two-PC
walking, stopping, turning and reconnect test. No game installation or live test
is authorized by this packaging task.

## Exact scope

- PR #5 foundation: `b1f054ed67c0bb03f1b8e290c2b5fd62a621307c`.
- PR #17 motor: `0b71aff258d595c645ef07e0ade3ad4b39847a31`, already contains PR #5.
- Main: `e19ffb3286efec750b8729487220becf6569ab7b`.
- New package source revision is the full commit recorded inside both manifests
  and BUILD.txt. Version: `v0.1.0-movement-experiment.1`.
- Owned files: value-only player diagnostics in `runtime/session/cet/CP2077Coop/init.lua`,
  `runtime/session/diagnostics/CP2077MovementDiagnostics/`,
  `scripts/package-movement.py`, `scripts/movement-dependencies.json`,
  `scripts/collect-movement-logs.ps1`, focused tests/CTest registration, package
  instructions, this record and README link. Ownership retained by KyleBuildsAI.
- No movement-algorithm, protocol v5, server, interpolation or shared contract
  changes. PR #15/#16/#18 and combat/NPC experiments are not added to the package.

## Offline evidence

- Fresh Visual Studio 2022 x64 Release plugin/server build passed, MSVC 19.41.
- All 30 CTests passed, including command-driven motor simulation, lifecycle,
  diagnostic rate/size limits, Lua wrapper lifecycle and public-package checks.
- CET-compatible LuaJIT 2.1 passed the session lifecycle, 105-check motor and
  diagnostic suites; all 11 source runtime/diagnostic Lua files parsed.
- Five packaging tests exercise matching role game files, input hash rejection,
  legacy/foreign build rejection, dirty-source rejection and preservation of
  existing output. Private/unlisted files are excluded.
- Matched native declarations and remote movement REDscript compiled against
  installed 2.31 cache/Codeware in isolation; all source/game inputs unchanged.
- PowerShell collector syntax passed. Collector uses an allowlist of logs and
  package metadata, never private session.ini or access.key.
- Actual release generation validates all 38 pinned dependency files before
  writing, checks the typed build's source root, then reopens both ZIPs and
  compares every entry. SHA256SUMS.txt and manifests identify delivered bytes.
- Hosted Windows, Debian and sanitizer results are linked from PR #17 for the
  exact published head; do not substitute an older green run.

Local evidence directory (private):
`D:/Downloads/syncfix/bench-artifacts/20261014-movement-package`.
The directory uses the local October 14 date; records use October 15 UTC.

## Deferred gates and handoff

This is a prerelease test artifact, not promotion over the qualified v0.0.37
package. Preserve the old complete package. Put these role ZIPs in a versioned
experimental subfolder of local `game-files/latest`. No games launched, settings
or saves changed, server deployed, main branch merged or live success claimed.

Next: both maintainers install the same experimental package, preserve their
private connection configuration, follow `docs/MOVEMENT_TEST_PACKAGE.md`, and
return both logs plus video. Inspect actual versus target positions and command
failures before changing movement behavior. There is no confirmed missing backend
interface blocking this test. PR #18 contract work remains deferred.
