Current implementation uses protocol **v3**. The v1 section below is historical; current NPC additions are specified at the end. The v2 session handshake and timestamped player/vehicle states remain in v3; v1/v2 peers are rejected rather than mixed with v3.

# Historical protocol v1 core contract

Status: implemented foundation, not connected to the legacy plugin or UDP relay. A transport must authenticate members before calling SessionRegistry. Pre-admission handshake, token exchange, retransmission scheduling and snapshot transfer are not implemented in this milestone. No public listener consumes v1 yet.

## Envelope
Every integer is unsigned, network byte order (big endian). Floats are finite IEEE-754 binary32, encoded via bit representation in network byte order. Never transmit a C++ struct. Exact size is required; trailing bytes are rejected. Maximum datagram size: 1200 bytes. All current messages fit one datagram.

| Offset | Bytes | Field |
| --- | --- | --- |
| 0 | 4 | Magic 0x43505331 (CPS1) |
| 4 | 2 | Protocol version = 1 |
| 6 | 2 | Packet type |
| 8 | 4 | Payload byte length |
| 12 | 8 | Session ID, nonzero |
| 20 | 4 | World epoch, nonzero |
| 24 | 4 | Sender player ID, nonzero |
| 28 | 4 | Sequence, zero for reliable events |
| 32 | 8 | Event ID, nonzero only for reliable events |
| 40 | variable | Typed payload |

Session and player IDs come from the registry; connection IDs are opaque transport-side identities and never appear in the wire envelope. Binding an untrusted packet to a ConnectionId requires authenticated transport code, not an IP/claimed-player-ID assumption.

Transform = position x/y/z followed by Euler rotation x/y/z in radians, six f32 values (24 bytes). Positions are bounded to +/-1,000,000; angles to +/-6.283186. These are codec bounds, not gameplay permission. HOST applies movement/combat plausibility rules in the game integration.

## Implemented messages
Fields are encoded in the order listed. Entity IDs and request/event references are u64, owners are u32, kind is u8. A transform is abbreviated T.

| Type | Value | Bytes | Payload | Authority / delivery |
| --- | --- | --- | --- | --- |
| Heartbeat | 0x0001 | 0 | none | Member -> server, sequenced |
| Leave | 0x0002 | 0 | none | Member -> server, reliable |
| Ack | 0x0003 | 8 | acknowledged event | Member -> transport, idempotent |
| PlayerPose | 0x0100 | 32 | entity, T | Owner -> HOST, sequenced report |
| PlayerState | 0x0101 | 32 | entity, T | HOST -> active peers, sequenced |
| VehicleInput | 0x0200 | 20 | entity, throttle, steering, brake (f32) | Owner -> HOST, sequenced intent |
| VehicleState | 0x0201 | 32 | entity, T | HOST -> active peers, sequenced |
| HitRequest | 0x0300 | 20 | attacker, target, proposedDamage (f32) | Attacker owner -> HOST, reliable intent |
| DamageApplied | 0x0301 | 28 | attacker, target, damage (f32), request | HOST -> active peers, reliable result |
| EntitySpawn | 0x0400 | 37 | entity, kind, owner, T | HOST -> active peers, reliable |
| EntityDespawn | 0x0401 | 8 | entity | HOST -> active peers, reliable |
| WorldState | 0x0402 | 32 | entity, T | HOST -> active peers, sequenced |

Kinds: Player=1, Vehicle=2, World=3. Throttle/steering range [-1,1], brake [0,1], damage [0.001,100000]. IDs/references cannot be zero, except owner=0 for an unowned vehicle or world entity. Player entities require a member owner; world entities must have owner=0. One player entity per member. Spawn IDs are allocated monotonically by HOST and never reused in the current epoch. Unknown kinds/types/versions are rejected. Unsupported message families have no usable wire IDs yet; extend the versioned contract and fixtures when implementing them.

PlayerPose is a report, not a server state mutation. Only HOST PlayerState/VehicleState/WorldState update the authoritative transform cache. DamageApplied is routed but does not implement game health simulation. Both entity references must exist; HitRequest attacker must be the sender's player entity. Gameplay hit validation and causal request/result matching belong to HOST integration. Reliable event IDs scope request references to sender + session + epoch; attacker ownership identifies a HitRequest sender. Server-generated membership/disconnect notifications will use a separate envelope contract in stage 3.

## Ordering, routing and lifecycle
Snapshots are sequenced per sender + packet type + entity. Modular u32 sequence comparison accepts wrap (0xffffffff -> 0), rejects duplicates, old values and exactly half-range jumps. First sequence can be any value. Reliable events use a separate contiguous u64 stream per sender and epoch, starting at 1. Reject gaps without mutation; the transport must resend the missing event then retry later events. No silent reliable-event eviction. Event ID exhaustion requires session/world reset, not wrap.

An event <= the accepted watermark returns Duplicate with no routing/state effects. Duplicate is distinct from a new accepted event so a future transport can repeat its acknowledgment without applying it twice. A rejected event never advances the watermark. Ack validates the envelope but is not a receipt scheduler; the transport must match acknowledgments to its own outstanding sends. Fanout to each peer will need independent delivery tracking; sender event IDs alone are not receiver-delivery sequence numbers.

SessionRegistry is a single-threaded deterministic policy object. Create and Join are trusted application APIs, not authenticated wire operations. A created HOST is active; an admitted JOINER is Synchronizing until a trusted snapshot coordinator calls MarkSynchronized with the current epoch. Inputs during synchronization are rejected. HOST traffic reaches active peers in its own session; JOINER intent reaches only its own HOST. Control packets are handled locally.

Limits: 16 sessions, 2 members/session, 1024 live entities/session. Sequence storage is bounded by entity/type limits and removed on despawn. Last accepted reliable ID is a constant-memory replay watermark. There is no retained combat-event history or durable save yet.

Receive requires a monotonic millisecond clock and rejects expired members/HOST before accepting data. The owner must call Expire periodically even without incoming traffic. After 10,000 ms without accepted traffic, membership expires. Disconnecting JOINER removes its owned entities and reports removal IDs for future broadcast. HOST disconnect closes the session and reports peers to notify; no host migration. Rejoin receives a fresh player ID and requires a new baseline. ResetWorld is a trusted HOST operation that increments epoch, clears entities/order state and puts JOINER back into synchronization. The caller must announce the new epoch; the core does not send packets.

## Validation and remaining integration
Tests run without Cyberpunk: fixed golden bytes, all payload round trips, every truncated prefix, unknown fields, NaN/Infinity, deterministic malformed inputs, role/ownership/identity rejection, foreign sessions, sequence wrap, reliable gaps/duplicates, bounded registries, expiry, rejoin and epoch reset. Byte hashes protect imported game scripts from unintended changes.

Next transport stage must add authenticated admission, bounded rate limits and retries, acknowledgment identity, snapshot chunking/baseline revisions, event history/recovery and POSIX/Winsock networking. Vehicle seat transitions and full world/quest state are not represented by these minimal payloads. Do not expose this foundation as a complete or secured multiplayer server.

## v3 NPC extension
NPC IDs are server-issued u64 values starting at 2^32, separate from PlayerId. All fields are encoded in network byte order; T remains 24 bytes. Records are canonical nonzero 40-bit TweakDB names stored in u64, with local database offsets removed. NPC authority is always the authenticated session HOST.

| Type | Value | Bytes | Payload in order | Path |
| --- | --- | --- | --- | --- |
| NpcAdopt | 0x500 | 40 | adoption u64, record u64, T | HOST TCP, ordered event |
| NpcSpawn | 0x501 | 60 | entity u64, adoption u64, record u64, T, sequence u32, sampleTimeMs u64 | Server TCP catalog/ack |
| NpcDespawn | 0x502 | 8 | entity u64 | HOST TCP, ordered event |
| NpcRemoved | 0x503 | 8 | entity u64 | Server TCP |
| NpcState | 0x504 | 40 | entity u64, T, sampleTimeMs u64 | HOST UDP, sequenced |
| NpcSnapshotEnd | 0x505 | 0 | none | Server TCP catalog boundary |
| NpcDenied | 0x506 | 8 | adoption u64 | Server TCP capacity response |

Server controls use sender/sequence/event zero in the header. NpcState uses the HOST sender and stream sequence; stale sequence or source time and foreign epochs are rejected. NpcAdopt/Despawn use contiguous event IDs over TCP. Capacity denial consumes the valid command event but creates no entity. Adoption tokens are HOST request identities, not engine pointers or positional matches; retired tokens remain bounded tombstones for the epoch. JOINER sends Ready only after both player baseline and NPC catalog completion. NPC lifecycle outboxes and client catalogs are bounded; overload fails explicitly. High-frequency NPC routing uses observer distance and configured NPC rates.
