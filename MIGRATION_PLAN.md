# Migration plan — v0.1.0

The current milestone is architecture preparation, not a completed runtime migration. Legacy protocol is frozen. Each stage must leave a buildable, reviewable commit and update this checklist with evidence.

## 0. Audit and baseline
- [x] Review tracked plugin/server sources, build definitions, ignore rules and local dependencies.
- [x] Add AGENTS.md and ARCHITECTURE.md with authority rules and known gaps.
- [x] Build existing plugin and Windows relay in Release successfully.
- [x] Import five installed runtime sources under runtime/ with SHA-256 provenance; vehicle_proxy_v7.yaml is tracked as vehicle_proxy.yaml. Configuration templates remain part of client migration.

## 1. Reproducible foundation
Add root CMake targets for shared protocol/session core, server, tests and optional Windows plugin. Pin RED4ext.SDK revision with a documented bootstrap mechanism; do not require the SDK for Linux server builds. Add build/check scripts and Windows/Linux CI. Keep legacy targets available until cutover.

Gate: fresh configure/build, CTest on Windows and Debian/Linux, plugin baseline builds, no game needed. Local existing builds alone do not satisfy fresh-clone reproducibility.

## 2. Typed protocol and session policy
Implement exact v1 envelope layout and golden byte fixtures, typed families from ARCHITECTURE.md, strict codec validation and limits. Implement session/member/epoch/entity IDs, role checks, event deduplication, sequence wrap and coherent state models without sockets.

Gate: malformed payloads and unknown versions rejected; JOINER authoritative damage/world packets rejected; isolated sessions; duplicate events applied once. Define credential establishment and endpoint binding before public UDP use.

## 3. Debian session/state/relay server
Extract transport adapter with Winsock and POSIX implementations. Add create/join/heartbeat/leave, bounded session registry, authenticated role routing, HOST snapshot cache and expiry. Implement reliable control/events and bounded snapshot chunk recovery. Add structured diagnostics, CLI/config, service example and health checks; deployment requires an identified accessible server.

Gate: automated two-client and multi-session harness on Linux, forged identity and old epoch rejection, HOST loss, packet loss/reordering, reconnect, memory bounds. Server cannot publish simulation results independently of HOST.

## 4. Plugin session client and game bridge
Split RTTI registration, configuration, transport, session client and per-entity buffers. Add explicit HOST/JOINER and session configuration; surface initialization failures. Use coherent snapshot transfer and separate combat/world queues. Add and track explicit native declarations and callers for typed APIs. Do not expose a half-migrated bridge as v0.1.0.

Gate: plugin Release build and headless client integration; preserved shutdown behavior; game-thread-only application. User game check: role selection, join/snapshot completion, remote spawn, continuous movement and disconnect cleanup.

## 5. HOST world authority by domain
Migrate player first, then vehicle, combat and supported world entities. HOST assigns stable entity IDs and validates JOINER intent. Seat transitions are authoritative; combat has request/result IDs and applies damage once; world snapshot and deltas share revisions. Verify applicable game hooks before disabling JOINER simulation.

Gate: automated routing/ownership/event tests plus user game checks for simultaneous seat requests, entering/exiting and driving, movement while fighting, duplicate hit prevention, entity death/despawn and world load/reset.

## 6. Cutover and release
Remove CP1/RP1 and sentinel paths only after bridge and server integration pass. Reject incompatible versions clearly. Provide matched plugin/scripts/config package, automated backup/install script scoped to the verified game path, Debian service package and rollback to the previous complete package. Record supported world entities and known gameplay limitations.

Gate: Windows and Linux builds/tests, two-machine HOST/JOINER game smoke check, loss/reconnect and world reset checks, no sentinel encodings in active paths. Then bump runtime version to 0.1.0, commit release artifacts/config definitions as appropriate and tag only after acceptance.

## Automation and user involvement
Agent owns edits, builds, tests, error repair, scoped commits and preparation of install/server scripts. Ask the user only to execute game-dependent scenarios with packaged builds and return observations/logs. Do not claim Debian deployment or game tests without access/evidence. Filesystem/tool approval prompts may still be required by this environment's read-only policy.

## Baseline validation
2026-10-04: `cmake --build CoopPlugin/build --config Release` and `cmake --build CoopServer/build --config Release` passed with MSBuild 18.11.0. Produced CP2077Coop.dll and CP2077CoopServer.exe. No gameplay changes in this milestone; no in-game test required yet. Debian compilation and fresh-clone dependency setup remain unverified.

## Stage 2 progress (2026-10-04)
- [x] Import installed runtime with source/destination hashes; no game writes.
- [x] Root CMake, optional pinned SDK/plugin, portable core, build scripts and CI definitions.
- [x] Exact binary envelope, 12 typed messages across control/player/vehicle/combat/world, strict codec and golden fixtures.
- [x] Trusted connection/member binding, HOST authority, bounded sessions/entities, ownership, ordered events, snapshot sequences, expiry/rejoin/world epochs.
- [x] Local fresh Windows configure/build of plugin, legacy relay and core; all three CTest suites pass.
- [x] Confirm fresh Windows SDK bootstrap, Debian and sanitizer CI after push (run 37232411396, code commit 6d6ac0034e566468ad7425592014ce2387ba91b9).

The implemented foundation is detailed in docs/PROTOCOL.md. Session creation/admission are trusted in-process APIs; wire authentication, reliable retry scheduling, snapshot transfer and the Debian network service remain stage 3. No game test or deployment is requested in this stage.

## Verified stage 2 build evidence
[GitHub Actions run 37232411396](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37232411396) passed all jobs for code commit 6d6ac0034e566468ad7425592014ce2387ba91b9:
- Windows fresh SDK fetch, Release plugin/legacy relay/core build and 3/3 CTest suites.
- Debian bookworm, GCC 12.2: portable core build and 3/3 CTest suites.
- Linux GCC 13.3 with ASan/UBSan: build and 3/3 CTest suites.

Local Windows MSVC 19.51 Release also passed all three suites. Final read-only verification matched all five game source files and repository copies to import-manifest.json. No installation, game file edits or gameplay tests were performed. This evidence completes the stage 2 foundation checks; it does not certify the future network service or v0.1.0 gameplay release.
