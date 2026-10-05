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

## Checkpoint continuation — 2026-10-05
Starting point is 20eb125 (preserved), based on stable 0341790. The checkpoint already contained TCP/UDP socket wrappers, v2 admission packets/timestamps, configurable member limits and interpolation. It contained no running session server/client or headless session networking test.
Foundation stabilization now adds transport/handshake/interpolation tests, validates interpolation/session configuration, rejects stale source timestamps in interpolation, and fixes UDP socket setup plus POSIX select bounds. Local portable-core CTest: 5/5 passed. Linux verification runs in CI after this push.
Next: implement server/client session orchestration over the existing real TCP/UDP layer and a CTest headless E2E. RED4ext/CET integration is gated on that test. No game files were changed.

## Headless networking milestone — 2026-10-05
Implemented shared/server.* and shared/client.* using the checkpoint TCP/UDP transport. HELLO authenticates a test access key; CREATE_SESSION/JOIN_SESSION assign SessionId/PlayerId and per-connection UDP tokens. VPS owns membership/player registry; HOST approves owned pose reports before authoritative PLAYER_STATE is routed. Clients use dynamic PlayerId maps, configurable rates up to 60 Hz, and per-player interpolation. Routing applies distance relevance and reduced distant update rate.
Local Windows portable build and all 6 CTest suites pass, including real-socket network_e2e (HOST/JOINER admission, UDP replication, stale sequence/timestamp rejection, reconnect, interpolation, 16 players, capacity/auth rejection and interest filtering). No SessionRegistry calls in E2E. Linux/ASan validation pending this push.
Next gate: verify CI on Linux. Then expose this same tested server as a Debian executable/service and connect the plugin/game bridge. The running game plugin is still legacy; no game installation was modified. Transport access keys/tokens are plaintext test credentials: use a trusted private network until transport encryption is added.

## Server executable checkpoint - 2026-10-05
Headless milestone 31f022e passed all Windows, Debian bookworm and Linux ASan/UBSan CI jobs (run 37284352893); all six suites passed. This completes the prerequisite for game integration.
The same tested server is now exposed through SessionServer/main.cpp with strict file configuration, signal shutdown and a bounded smoke-run mode. deploy/debian supplies configuration, a systemd unit and installation script. Local Windows build and all seven CTest suites passed, including server_smoke. Executable commit a869756 passed Debian bookworm and Linux ASan/UBSan CI (run 37285332799). The full local Windows plugin/relay/core/session-server build also passed all seven suites; Windows CI was still building at this evidence update. No VPS installation was attempted.
Completed: shared net/protocol/session/interpolation, real TCP/UDP client/server, dynamic membership tested at 16 players, admission, host-approved player replication, interest filtering, stale rejection, reconnect and render sampling.
Incomplete: RED4ext plugin still uses frozen legacy runtime; typed native bridge, dynamic in-game avatars, JOINER-to-HOST teleport and HOST/JOINER deployment bundles have not been implemented. Reliable control uses TCP; full gameplay events and vehicle/combat/world replication remain future work. No in-game test is ready or requested.
Files completed in this checkpoint: SessionServer/*, deploy/debian/*, root/test CMake and server smoke fixtures. No partially edited plugin/game files. Next: verify executable CI, then integrate shared SessionClient into the plugin through coherent game-thread snapshots and a new matched CET/REDscript bridge; build packages before requesting the first game test. Preserve runtime/ imported originals and do not modify the game installation.

## Game integration foundation - registry/worker
Added portable game::SessionBridge: worker-owned SessionClient, coherent value handoff, game-frame sampling, explicit activation/reset and unsupported world-action submission. Added game-thread EntityRegistry for Player/NPC/Vehicle/World, exact 64-bit session/local identities, reverse mapping and authority/epoch checks. World action contracts are local interfaces only; no unsupported wire messages are sent. Separate bounded EventInbox rejects overflow, wrong authority and event gaps.
Windows core build and 8/8 CTest suites pass, including bridge workers over real sockets, reconnect/load transition, registry ownership/isolation and bounded queue tests. Plugin adapter and matched runtime are next; no game installation changes.

## Typed plugin and matched bridge
Default RED4ext build now links SessionBridge and exposes only CP2077Session_* natives. Frozen plugin source remains in CoopPlugin/src/legacy_main.cpp behind COOP_LEGACY_PLUGIN=ON; imported legacy bridge remains unchanged. runtime/session contains matched natives, dynamic Judy proxy creation and per-frame CET interpolation/cleanup plus JOINER baseline teleport. Plugin reads role/server/session/key/rates/interpolation from session.ini beside its DLL; packaging/config generation follows next.
Full local Windows plugin/server/core build and 8/8 tests passed. Native game calls only run through the CET/game thread; worker receives plain transforms and publishes copied snapshot buffers. Stable Uint64 IDs remain opaque across Lua. No game files or saves modified. REDscript compilation and actual engine rendering/teleport are NOT verified by these headless tests. NPC/world contracts intentionally return Unsupported; full Shared World Reaction and its engine hooks remain unimplemented.

## Packaging and contract validation checkpoint
Added scripts/package-session.ps1: creates HOST/JOINER/debian configuration and matched plugin/scripts under ignored artifacts only, with generated private key and hashes; no game installation. New bridge contract CTest checks native registration/declarations/CET calls and rejects legacy protocol leaks. Debian CI now syntax-checks Lua and the deploy shell script. Full local Windows build and 9/9 tests passed; role packages generated successfully. runtime/session/README.md lists exact missing authority/AI/stimulus/damage/load hooks and unimplemented wire routes. Remaining: verify CI, validate frozen rollback build, then tackle Shared World Reaction hooks and reliable world routing. REDscript/engine behavior is unverified; no game test requested.

## Final validation for game integration foundation
Code commit d061a10 passed all CI jobs: Windows fresh SDK/plugin build, Debian bookworm and Linux ASan/UBSan (run 37288700643). All nine CTest suites passed; Debian also passed Lua syntax and shell syntax checks. Local typed Release DLL is build/windows/CoopPlugin/Release/CP2077Coop.dll. The separate frozen rollback DLL built successfully at build/rollback/CoopPlugin/Release/CP2077Coop.dll; its source Git blob exactly matches the pre-cutover plugin at 05e8943.
Prepared package: artifacts/session-20261005-111242-467 (HOST/JOINER plus Debian configuration, loopback endpoint; not installed). Matched source bridge: runtime/session. No partial source edits remain. No game files, saves or VPS were changed.
Next work is Shared World Reaction authority plumbing and the missing engine hooks listed in runtime/session/README.md, plus REDscript/engine validation before a gameplay milestone. Registry and player rendering bridge foundation are implemented; NPC ID allocation/adoption, actual AI authority suppression, stimuli and reliable gameplay/world event routing are still unsupported. These interfaces must not be presented as working NPC synchronization.

## Stop checkpoint - 2026-10-05
Stopped at the user's request; no further implementation or CI investigation. All completed implementation was already committed and pushed through fb71e08; the working tree was clean before this checkpoint update. The last typed and rollback build commands both exited successfully; no build command from this task remains pending. Resident MSBuild processes were observed but were not restarted or terminated.
Remaining build/rollback issue: no known compiler failure. REDscript compilation, actual engine behavior and an installed rollback have not been validated; rollback installation automation remains unfinished. Existing build/test evidence above is unchanged and was not rerun.
Next required step when work is explicitly resumed: validate the matched REDscript/native bridge in an isolated setup without modifying the game installation, then address the documented Shared World Reaction authority/hooks and rollback installation preparation before any gameplay milestone. No source files are partially edited.

## NPC milestone: typed transport and server policy
Protocol v3 adds HOST-only NPC adoption/despawn, server-issued spawn/removal and catalog completion controls, plus sequenced NPC transform state. IDs occupy the server-owned 64-bit NPC namespace; adoption is deduplicated and retired tokens cannot resurrect an entity. Reliable lifecycle/catalog queues are bounded; capacity denials consume command ordering without mutating entity state. JOINER reconnect restores the accepted NPC catalog/latest state, and only HOST can publish NPC state. NPC UDP routing uses distance relevance and configurable 20/10 Hz rates; player paths remain 60 Hz.
Windows portable build and 10/10 tests passed, including NPC codec malformed cases, policy/identity/epoch/sequence checks and a real TCP/UDP NPC spawn/state/despawn/reconnect test. No engine work in this stage; next is bounded game-thread NPC handoff and reversible Session Bubble population/projection interfaces. Actual JOINER spawning must remain gated until safe local-population suppression and projection AI control hooks are verified. No combat/stimulus work or game writes.

## NPC milestone: game-thread handoff and Session Bubble
Added bounded HOST NPC offer/release handoff to SessionBridge, server-acknowledged SessionEntityId/local EntityID bindings and NPC frame sampling. RED4ext exposes matched NPC natives; CET discovers NPCPuppet attachments, offers in-bubble HOST NPCs and retires detached sources without modifying game objects. Stable record IDs strip local TweakDB offsets. Player replication is preserved.
JOINER NPC projection lifecycle is connected to a game-thread population adapter with reversible acquire/restore semantics, exact-ID bindings and cleanup before restoring ambient population. The production adapter explicitly reports unavailable: safe ambient suppression and passive-NPC/AI activation hooks are NOT verified, so no competing NPC projections are spawned. This is a deliberate in-game blocker, not a claim of complete engine NPC replication. NPC metadata/state still replicate and restore over the real session stack.
Local full Windows build and 11/11 CTest suites passed, including worker/socket NPC handoff and executable Lua bubble tests with independently generated ambient NPCs, identical-position/different-ID NPCs, lease failure/recovery and epoch cleanup. Lua test interpreter is checksum-pinned and test-only. Networking commit b6682aa passed Windows, Debian and ASan/UBSan CI (37320691172). Next: verify this stage's CI, package updated bridge, and record the precise remaining engine hook gate. No combat/stimulus/vehicle/quest work or game installation changes.

## NPC milestone final hardening checkpoint
Added a 48-NPC real-socket catalog/reconnect/despawn test, NPC distance-filter/re-entry test and failed projection-creation lease recovery test. Denied adoption bookkeeping is released when the game retires a source. Full local Windows plugin/server build and 11/11 tests passed; packages generated at artifacts/session-20261005-161639-867 without installation. Stage f8d6f52 passed Windows, Debian and ASan/UBSan CI (37322816746). Final hardening CI follows this commit.
The transport/policy/registry/bubble foundation is complete for this scope. Actual JOINER engine NPC spawning is still gated, not a completed gameplay milestone: verified reversible ambient suppression and passive AI-disabled projection hooks are missing. Already-attached NPC enumeration and live world-reset signaling are also not implemented. Exact remaining hooks are in runtime/session/README.md. Next required task is to validate/implement these adapters and isolated REDscript compilation, NOT combat or stimuli.

## NPC milestone validation and handoff - 2026-10-05
Final code a0ae81e: full local Windows Release plugin/server build and 11/11 CTest suites passed. CI run 37329564027 passed Windows build/test steps, Debian bookworm and ASan/UBSan tests, including the actual socket tests and Lua population-boundary tests. No game/save/VPS changes were made. Plugin: build/windows/CoopPlugin/Release/CP2077Coop.dll; matched packages: artifacts/session-20261005-161639-867. Packages remain uninstalled.
No partial source edits or pending local builds. Transport and adapter-policy foundation is tested; actual engine NPC projection remains unavailable until reversible population suppression and passive projection creation are verified. Therefore the next task should resolve those hooks and REDscript validation, not PlayerFire/WorldStimulus/HitRequest/DamageApplied/EntityDeath. No in-game test is requested.

Exact changed files relative to 6f328c3:
- CoopPlugin/src/main.cpp
- MIGRATION_PLAN.md
- SessionServer/main.cpp
- build-support/LuaTests.cmake
- deploy/debian/server.ini
- docs/PROTOCOL.md
- runtime/session/README.md
- runtime/session/cet/CP2077Coop/init.lua
- runtime/session/cet/CP2077Coop/npc_population.lua
- runtime/session/cet/CP2077Coop/npc_runtime.lua
- runtime/session/redscript/CP2077Coop/natives.reds
- scripts/package-session.ps1
- shared/include/coop/client.hpp
- shared/include/coop/game_bridge.hpp
- shared/include/coop/protocol.hpp
- shared/include/coop/server.hpp
- shared/include/coop/session.hpp
- shared/src/client.cpp
- shared/src/game_bridge.cpp
- shared/src/protocol.cpp
- shared/src/server.cpp
- shared/src/session.cpp
- tests/CMakeLists.txt
- tests/game_bridge_tests.cpp
- tests/npc_population_tests.lua
- tests/npc_tests.cpp
- tests/protocol_tests.cpp


## JOINER NPC projection creation — 2026-10-05
The JOINER CET adapter now creates an adapter-owned Codeware DynamicEntitySpec from the received TweakDBID, keeps the EntityID returned by DynamicEntitySystem.CreateEntity while streaming completes, and binds only after DynamicEntitySystem.GetEntity(id).GetEntityID() matches exactly. Catalog/bubble removal, session epoch change, disconnect and reconnect unbind and delete only those owned IDs. Projection movement uses the existing CET TeleportationFacility path. The network/session core is unchanged.

Verified against installed Codeware declarations and upstream source: DynamicEntitySpec.recordID/position/orientation/persistState/persistSpawn/alwaysSpawned/spawnInView/active/tags; DynamicEntitySystem.IsReady/CreateEntity/IsSpawning/IsSpawned/GetEntity/DeleteEntity; Entity.GetEntityID. Installed CET scripts confirm TweakDB:GetRecord, TweakDBID.new, Quaternion.new, Vector4.new and the TeleportationFacility:Teleport form. No REDscript source was changed or compiled in this Lua-only step.

Validation: Windows Release plugin/core/server build succeeded; focused npc_population CTest passed with mocked asynchronous creation, exact SessionEntityId binding, duplicate frames, catalog removal, epoch reset and reconnect. Engine execution was not tested. Autonomous AI and local ambient population suppression remain unimplemented; projection creation is not yet safe for a controlled shared-world gameplay test.
