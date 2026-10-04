# v0.1.0 Session Architecture

Status: proposed target; legacy runtime unchanged. Audit baseline: 95b89e2, 2026-10-04.

## Project audit
All tracked text sources and build definitions were reviewed. The repository has two independent CMake projects and no root CMakeLists.txt. The tracked empty `cmake` file is not a build entry point. `_VehicleProbe_OFF.rar` is an opaque archived probe, not reviewed executable source and not a build input.

| Area | Current behavior | Consequence |
| --- | --- | --- |
| CoopPlugin/src/main.cpp | RED4ext DLL v0.0.25; static native functions; one UDP worker | RTTI, configuration, codec, queues and lifecycle are coupled |
| Local state | Six independent float atomics plus sequence | A transmitted state can mix values from different updates |
| Combat | PushPlayerState detects w <= -700 and forwardY >= 9000; queues up to 256 hits; sends -777/9999 | Damage and target position masquerade as movement; overflow silently drops oldest hit |
| Remote state | One remote player slot; combat shares getters and blocks movement for 140 ms | No per-player registry, reliable event delivery or coherent snapshot consumption |
| UDP client | CP1 send, RP1 sscanf parse; 2 ms polling; sender address unused | No version negotiation, server verification, deduplication or stale-state rejection |
| Configuration | Game-root red4ext/plugins/CP2077Coop/server.ini; IPv4 and port; default loopback:11778 | No HOST/JOINER role, session identity or credentials |
| Lifecycle | Starts on plugin load; Main ignores StartNetwork result | Initialization errors are not surfaced; no session lifecycle |
| CoopServer/main.cpp | Winsock UDP :11778; endpoint-based ID on any datagram; WELCOME; CP1 text forwarded as RP1 to every other endpoint | No rooms, authentication, payload validation, role policy, expiry or state storage |
| Dependencies | Ignored local RED4ext.SDK and RedLib checkouts | Fresh clone cannot reproduce plugin build |
| Integration | CET/REDscript sources absent | Actual game-side spawn, vehicle and combat behavior cannot be audited here |

Only -777/9999 are implemented in the tracked plugin. -666/8888 are prohibited migration patterns, not confirmed tracked implementations. The server's comment describes fewer CP1 fields than the plugin sends, but its string relay preserves the suffix.

Local dependency revisions: RED4ext.SDK ad7277714ad30d6885d7050c5ba24fa0102f6920; RedLib 6822105d15d1b8bd1e6aae5e57827835e585cfe8. Both existing Release targets built successfully on Windows. This does not verify game behavior or Linux compatibility.

## Responsibility and trust
HOST runs the game's world simulation: NPC lifecycle, world entities, vehicle ownership/seats, combat outcomes and supported world state. JOINER produces player input and interaction requests and renders accepted session state. JOINER must not directly commit damage, spawns, ownership or world changes.

Debian runs no Cyberpunk simulation. It allocates sessions/player identities, authenticates membership, enforces role and routing rules, stores the latest accepted HOST snapshots and bounded event history, and relays data within one session. Server validation establishes identity and permissions; HOST validation establishes gameplay outcomes. A compromised HOST remains outside the gameplay trust model for this cooperative MVP.

Player pose can initially be client reported and bounded/approved by HOST; this is not permission for a JOINER to publish authoritative world state. Relay forwards client intent only to HOST and accepted HOST state to session members. No cross-session broadcast.

## Module boundaries
- Shared protocol: versioned envelope, typed payloads, byte codec and validation; no socket/game dependencies.
- Shared session core: IDs, roles, lifecycle, authority checks, sequence/event bookkeeping; deterministic tests without sockets.
- Server: session registry, membership credentials, endpoint binding, rate limits, state cache, reconnect/snapshot workflow; separate POSIX/Windows transport adapter.
- Plugin: session client, transport worker, coherent per-entity state store and bounded event queues.
- Game bridge: explicit player/vehicle/combat/world native APIs and tracked REDscript/CET callers; game-thread application only.

Legacy code is isolated during replacement. No new packet is encoded through PushPlayerState float markers. Cutover requires matched plugin, bridge and server versions; legacy and v1 traffic are never guessed from payload values.

## Proposed protocol contract
Use an explicitly encoded binary envelope with fixed-width integers in network byte order and IEEE-754 binary32 float payloads encoded field by field. Proposed header fields: magic, protocolVersion, packetType, payloadLength, sessionId, sessionEpoch, senderPlayerId, sequence, correlation/eventId. IDs are server issued; the sender's claimed ID is checked against its authenticated membership. Define precise field widths and byte fixtures in the first protocol implementation before runtime integration. Keep each datagram at most 1200 bytes; larger snapshots use bounded numbered chunks with timeout and total-size limits.

| Family | Explicit messages | Policy |
| --- | --- | --- |
| Session | Hello, CreateSession, JoinSession, SessionAccepted, Reject, Heartbeat, Leave, SessionClosed, Ack, SnapshotRequest/Begin/Chunk/End | Debian issues membership and epoch; duplicate requests are idempotent |
| Player | PlayerInput, PlayerPoseReport, PlayerState, PlayerSpawn, PlayerDespawn | JOINER reports intent/pose to HOST; HOST publishes accepted state |
| Vehicle | VehicleEnterRequest, VehicleExitRequest, VehicleInput, VehicleState, VehicleSeatChanged, VehicleSpawn/Despawn | HOST resolves entity identity, driver and seat conflicts |
| Combat | AttackRequest, HitRequest, DamageApplied, EntityDied | HOST validates attacker, target, damage and timing; results carry unique event IDs |
| World | EntitySpawn/Despawn, WorldSnapshot, WorldDelta | HOST only; stable session entity IDs and revisions |

Position is data, never entity identity. Entity IDs are session scoped and never reused within an epoch. Spawn/despawn is reliable and ordered before dependent state. State contains entity ID, revision/tick, position and explicit orientation; no overloaded w/forward fields.

Movement snapshots are sequenced and replace older state per entity/channel, with wrap-aware comparison. Control, ownership, combat results and lifecycle events use acknowledgment, bounded retry, deduplication and explicit failure. Acknowledgment does not mean a game action was applied; accepted results correlate to requests separately. Reliable event queues cannot silently discard committed damage. Under overload, reject/throttle new intent and resynchronize rather than fabricate success.

Reject unknown versions/types, truncated/trailing bytes, excessive lengths, non-finite numbers, invalid roles, foreign IDs and old epochs before mutation. Bound peers, queues, history, retries and snapshot memory. Membership credentials must not appear in logs; initial UDP handshake and endpoint binding need a documented authentication mechanism before remote deployment.

## Session lifecycle and state
Server session: Created -> WaitingForHost -> Active -> Closing -> Closed. Client: Disconnected -> Connecting -> Admitted -> Synchronizing -> Active -> Disconnecting; every transitional state has timeout and explicit failure. Admission alone does not allow JOINER world updates. Snapshot captures one HOST revision; buffer subsequent deltas and apply them only after snapshot completeness is checked.

Heartbeat expiry removes members and publishes despawn/seat cleanup through HOST. HOST departure closes or suspends the session and notifies JOINER; automatic HOST migration is out of scope. Reconnect authenticates a fresh membership, rejects previous endpoint/epoch traffic and requests a complete baseline. Increment epoch on world reset/load and invalidate old entity mappings/events.

The initial state cache is in memory and only holds accepted HOST state. It is not a durable game save. Server restart ends sessions in v0.1.0. Persistent recovery and host migration are future work.

## v0.1.0 scope and acceptance
One HOST plus one JOINER first; separate sessions on one Debian server. Acceptance requires handshake and reconnect, player replication, explicit vehicle ownership/seats, HOST-approved combat, stable world entity lifecycle and snapshot recovery. Limit world replication to a documented supported entity set. Full quest synchronization, arbitrary save merging and complete NPC AI replication are out of scope.

Automated gates cover codec fixtures, malformed/fuzzed input, authority rejection, session isolation, loss/reordering/duplicates, expiry and baseline/delta recovery on Windows and Linux. In-game gates cover spawn/despawn, movement during combat, vehicle conflicts, world reset and reconnect. Do not suppress JOINER local world behavior until supported game hooks and reversible cleanup are verified in game.

## Runtime import update
The installed bridge is now captured under runtime/ with exact hashes. Its Lua v0.0.26 confirms vehicle markers -666/8888, Caliburn proxy interpolation and manual IS_HOST configuration. Combat matches nearby NPCs by position; remote.reds spawns a Judy proxy; natives.reds declares the existing eight functions. This supersedes the baseline audit's missing-source observation. No runtime behavior was changed during import.

## Stage 2 implementation
Root CMake now builds a platform-independent shared protocol/session library and headless tests. The implemented subset and exact envelope are in docs/PROTOCOL.md. It enforces trusted connection bindings, HOST authority, owned entities, bounded sessions and sequence/event ordering. Admission remains an in-process API; authentication, actual reliable transport and snapshot transfer are stage 3. The game plugin and legacy Windows relay are not wired to this core. CMake pins the RED4ext SDK; Windows, Debian and sanitizer CI validate the build.
