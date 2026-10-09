# Player presentation network proposal

**Status:** draft for joint review; not an accepted wire contract  
**Scope:** persistent player presentation in the existing session architecture  
**Protocol:** v5 remains unchanged  
**Ownership:** Bukczyk owns shared wire/client/server/SessionBridge; KyleBuildsAI owns REDengine capture and projection hooks

This proposal records the approved architectural direction and remaining wire decisions. It does not allocate packet type numbers, gameplay action kinds, or a protocol version. It changes no production packets, routing, runtime scripts, or VPS configuration.

The immediate priority remains smooth player movement and fixing readback_timeout. Presentation is additive and must not gate the existing movement path, session activation, or movement testing.

## Agreed direction

- Keep presentation state separate from PlayerPose and PlayerState.
- The first presentation MVP covers Standing/Crouching, Drawn/Holstered, and the exact identifier of a supported held weapon.
- The contract may carry local logical aiming state. Remote ADS and sight alignment are experimental and are not promised by this state.
- Do not add aimPitch in this stage.
- Send a complete state immediately after an observed and locally accepted state change, then send periodic complete repair snapshots. Use 2 Hz as the initial test proposal; this rate is not validated.
- The server validates membership, ownership, exact player/entity identity, session, epoch, transport sequence, state revision, and values. It caches the latest accepted state and provides a current baseline to joining clients.
- Distinguish state revision (semantic content change) from transport sequence and local receipt freshness (a fresh copy of unchanged state).
- One-shot actions remain events, separate from persistent state.
- Keep smooth movement and readback_timeout work independent and higher priority.

## Existing implementation boundary

Protocol v5 PlayerPose and PlayerState contain only entity ID, body transform, and sample time. There is no typed player presentation payload. The server's player-state cache and relevance routing cover transforms only.

The reliable GameplayIntent / GameplayResult path carries an opaque kind and body (up to 1024 bytes). The server routes JOINER intent to HOST and HOST result to active session members, but this is not a presentation schema or a latest-state cache for late join. Do not use it as a substitute for persistent presentation.

SessionBridge::ReadFrame currently exposes remote PlayerId, SessionEntityId, and interpolated body transform. RemotePlayer internally retains sequence, source time, and local receive time, but the frame exposes none of them. Existing game-facing transform input is separate from action state.

References: [v5 protocol types](https://github.com/Bukczyk/CP2077-Coop/blob/main/shared/include/coop/protocol.hpp), [SessionClient API](https://github.com/Bukczyk/CP2077-Coop/blob/main/shared/include/coop/client.hpp), [SessionBridge API](https://github.com/Bukczyk/CP2077-Coop/blob/main/shared/include/coop/game_bridge.hpp), and [PR #16](https://github.com/Bukczyk/CP2077-Coop/pull/16).

## Proposed semantic schema

Each update is one coherent full state, not a patch. Identity and transport ordering use the existing packet header; a separate body revision identifies semantic state changes.

| Field | Proposed type | Meaning and validation |
| --- | --- | --- |
| Header session | Existing SessionId | Must be the sender's active session. |
| Header epoch | Existing uint32 world epoch | Must match the active session epoch. |
| Header sender | Existing PlayerId | Authenticated member that owns the state. |
| Header sequence | Existing uint32 transport sequence | Advances for every transmitted snapshot, including identical repair snapshots. Reject duplicate/older datagrams by the existing modular sequence rule. |
| Header event | Existing uint64 | Zero for a state snapshot. Event IDs are for reliable one-shot/control events. |
| entity | SessionEntityId / uint64 | Must resolve to the exact player entity owned by sender. Never infer from position. |
| stateRevision | uint32 | Advances only when observed presentation values or their availability change. Uses modular ordering; same revision is valid only with byte-equivalent semantic state. |
| stance | uint8 enum | Proposed values: Unavailable, Standing, Crouching. Failed or timed-out crouch read-back is Unavailable, never Standing by default. |
| weaponState | uint8 enum | Holstered, DrawnSupported, DrawnUnsupported, Unavailable. |
| weaponRecord | uint64 | Exact native TweakDBID value when capture has one; zero when no ID is available. Never an inventory instance ID or guessed replacement. |
| aiming | uint8 enum | Unavailable, NotAiming, Aiming. Local logical capture may be sent; this does not assert remote ADS or sight alignment. |

The enum labels and numeric assignments are proposed semantics only. They do not allocate a packet type number. The body is 23 bytes; with the current 40-byte header the record fits within the current 1200-byte packet ceiling. Exact byte encoding, packet type, and protocol compatibility remain open.

### Lossless weapon ID path

The capture API provides a native TweakDBID. Preserve its full 64-bit value end-to-end:

1. RED4ext/C++ keeps the native TweakDBID value as uint64_t without masking, narrowing, or converting through float/double.
2. The network codec serializes exactly 8 bytes using the protocol's explicit byte order; never serialize native struct memory.
3. Across Lua/CET, expose the ID as a decimal or fixed-width hexadecimal string and parse it with checked integer conversion in C++. Lua/CET must not call tonumber or otherwise route the value through an imprecise floating-point number.
4. The receiver may render only records it recognizes and supports. An unknown ID remains that exact ID with DrawnUnsupported; never substitute a guessed record.

Kyle must confirm that the full native TweakDBID value is stable and meaningful on both game installations for the supported records. Lossless representation prevents numeric corruption; it does not itself guarantee the recipient has the corresponding asset. Inventory instance IDs, runtime handles, pointers, and local offsets are never transmitted.

Proposed cross-field rules:

- Holstered and Unavailable carry weaponRecord=0.
- DrawnSupported requires a nonzero record on the supported-record allowlist.
- DrawnUnsupported may carry the exact nonzero native ID if it was read successfully; use zero only if no ID was available. Never map it to another weapon.
- Unavailable stance/weapon/aim values mean the source could not reliably read that field. A timeout must not become a successful default.
- Aiming=Aiming is accepted only for combinations Kyle confirms are observable. Whether aiming requires DrawnSupported is still an engine-contract question.
- Unknown enum values, invalid combinations, truncated or oversized packets are explicitly rejected.

No pitch or camera direction is included. Body yaw is not aiming direction and must not be repurposed.

## Transport, ordering, and limits

### Live state

Use unreliable UDP. Send a full state immediately after the local adapter observes and accepts a semantic change, then send complete repair snapshots at a configurable 2 Hz for the initial test. This is a starting proposal, not a validated rate. Any later rate change is configuration, not a protocol constant.

The client retains at most one coalesced pending full state for its local player. If a newer semantic state supersedes an unsent value, retain the newest and expose queue pressure through the API. Persistent state is replaceable; one-shot events are not.

The server validates the authenticated connection, active membership, role policy, session, epoch, exact owner/entity mapping, transport sequence, state revision, and field invariants. It stores one latest state per active player in the bounded session membership collection. A fresh repair packet with a newer transport sequence and the same stateRevision is accepted only if its semantic body is identical; it updates receipt freshness and may be forwarded without reapplying game commands. A packet with an older stateRevision, or changed contents under the same revision, is rejected.

The server routes accepted state only to active, relevant same-session peers using the existing interest policy, never unconditional all-player broadcast. Player ownership covers only that player's cosmetic presentation; HOST remains authority for Night City simulation.

### State revision versus receipt freshness

These values have different jobs:

- **Transport sequence** advances for every emitted UDP snapshot. It orders datagrams and rejects duplicated/reordered packets.
- **State revision** advances only when the complete observed state changes, including a transition to or from Unavailable. It tells the game adapter whether a new state must be applied.
- **Receipt freshness** is local monotonic time recorded whenever a newer transport sequence carrying the current or newer state is accepted. It tells the receiver how recently a valid copy arrived.

An unchanged but fresh repair snapshot refreshes receipt freshness but does not trigger equip, stance, or aiming commands. Apply command changes once per new stateRevision and exact actor/session generation. A stale transport sequence does not refresh freshness. A newer transport sequence carrying an older stateRevision is rejected. A repeated stateRevision with different contents is invalid.

### Join baseline and reconnect

For a joining client, provide the newest cached full presentation state for each active relevant player over a reliable bootstrap path, followed by a presentation-baseline completion fence. The packet envelope and type identifiers are deliberately not allocated here. The baseline contains current state only and never replays transient events.

The presentation fence is separate from the current movement/session readiness path. A missing or unsupported presentation field must not block movement, session activation, or the movement test. If a live UDP update races with a baseline copy, keep the newer revision.

Reconnect receives current state for active players and a fresh PlayerId. Retire the old membership's presentation; never assign it to the new ID. The reconnecting client captures its own current read-back state and publishes it under the new identity. Leave, timeout, session close, entity removal, and epoch reset clear matching cache, revision, and adapter bindings.

If state arrives before its exact projection is ready, retain only the newest value under SessionId + epoch + PlayerId + SessionEntityId, bounded by active membership count. Apply it only after exact identity binding. Never search for a nearby actor.

### Freshness, stale interval, and membership lifetime

Make the stale interval configurable, for example as presentation_stale_after_ms, and evaluate it in the client using local monotonic receipt time. Candidate values for the first test are 1500–3000 ms; a 2500 ms initial candidate gives about five missed repair intervals at 2 Hz. These values are not final and require agreement with Kyle and observation under real network jitter/loss.

Trade-off: a shorter interval stops showing stale weapon/stance sooner but can mark valid state stale during brief packet loss or a hitch. A longer interval tolerates jitter but can leave an old visual state displayed longer after a disconnect or stalled sender.

Proposed safe fallback when the interval expires:

1. Keep the remote player's movement transform and body projection alive; presentation staleness must not block movement.
2. Mark presentation fields Unavailable/stale in the game-thread frame, stop treating the last values as current, and do not issue commands from an expired snapshot.
3. Release or neutralize only presentation overrides owned by the exact adapter/session generation, and only through a reversible cleanup hook Kyle verifies. Do not force Standing, equip a guessed weapon, mutate inventory, or invoke gameplay authority as a generic fallback.
4. If an owned reversible cleanup cannot be verified, keep the player visible, mark the presentation degraded/stale, and do not retry commands on every repair tick. Exact neutralization versus retaining the last rendered visual until a fresh state or projection removal is an open game-side decision.

The server must not reuse PlayerId within an epoch. SessionBridge generation is a local activation fence, not a wire membership generation. If the server cannot guarantee PlayerId non-reuse for a membership lifetime, the joint contract must add a membership-generation value before implementation.

## One-shot actions remain separate

A shot, reload, melee action, or other one-time event is not a persistent flag and never belongs in the late-join baseline.

Gameplay-affecting intent remains JOINER-to-HOST and HOST-authoritative. Existing GameplayIntent / GameplayResult transport may carry an agreed action schema after the parties agree on semantics, authorization, correlation, deduplication, expiry, and receiver presentation. Its current opaque body is not an accepted action contract.

A presentation-only one-shot event also needs a stable identity, bounded deduplication, ordering, expiry, and a rule that reconnect does not replay expired animation. This proposal allocates no action kind or packet ID.

## Proposed SessionBridge API

Keep typed C++ values as the shared API and REDengine object access on the game thread. The network worker transfers bounded value snapshots only.

Suggested semantic types:

- PresentationStance: Unavailable, Standing, Crouching.
- PresentationWeaponState: Unavailable, Holstered, DrawnSupported, DrawnUnsupported.
- PresentationAim: Unavailable, NotAiming, Aiming.
- PlayerPresentation: these observed values, exact uint64 weaponRecord, and stateRevision.
- RenderPlayer: PlayerId, SessionEntityId, interpolated Transform, optional PlayerPresentation, last transport sequence, stateRevision, freshness status, and local presentationAgeMs.

Suggested entry points:

- SetLocalPresentation(scope, observedState): checks current SessionId, epoch, local SessionBridge generation, ownership, invariants, and bounded queue admission. Accepts read-back, never a requested command. The bridge owns stateRevision and increments it only when semantic content changes.
- ReadFrame(localMonotonicNow): returns the newest exact-identity remote state alongside the existing transform. A fresh repeated stateRevision updates age/sequence only; it does not replay game commands.
- ReadNetworkDiagnostics(): returns separate server RTT and per-player snapshot age with validity and measurement-age fields.

Across the Lua/CET boundary, represent weaponRecord as an exact decimal or fixed-width hexadecimal string. Keep it a string in Lua and parse it with checked uint64_t conversion in C++; do not use Lua numbers or floating-point JSON numbers for TweakDBID. Prefer passing/holding the RED4ext native TweakDBID entirely in C++ where practical.

SetActive(false), epoch changes, membership removal, and disconnect clear associated pending/remote state. Presentation queues remain separate from movement snapshots and reliable gameplay queues. Presentation overflow may coalesce to the newest full state and must be observable. It must not stall SetLocal, ReadFrame, movement snapshots, or active session state.

The proposed scope-generation parameter can reuse the semantic pattern of GameplayScope, but this is not an ABI commitment. The final native/Lua interface should follow Kyle's game-thread adapter needs after contract approval.

## CET RTT and snapshot-age diagnostics

It is safe to expose these as read-only local diagnostics without adding a presentation packet, provided the names and clocks are explicit.

- **Server RTT** is locally measured round-trip duration to the VPS. V5 UDP Heartbeat is sent every 500 ms and echoed by the server. The current client uses echoes for liveness but does not retain send times or calculate RTT. A bounded sequence-to-local-monotonic-send-time table can calculate it without a wire change. Expose value, measurement age, and validity; invalidate it on disconnect/reconnect. It is RTT to the VPS, not to another player.
- **Player snapshot age** is local monotonic time since the last accepted snapshot from that remote player. It is not one-way latency and must not subtract a remote sampleTimeMs. It is separate per player from server RTT and interpolation-buffer delay.

Suggested CET labels: “Server RTT: 42 ms” and “Player state received: 85 ms ago”. Do not label both simply “ping”. Show “unknown” rather than zero when invalid. Keep stale/invalid age telemetry visible even when an expired render state is omitted from the sampled frame.

## Compatibility

The current codec requires protocol version 5 and has no negotiated presentation capability. V5 has no typed presentation payload. Do not append fields to PlayerState or overload GameplayIntent.

Before wire implementation, agree one compatibility strategy:

1. a separately versioned contract with explicit rejection of incompatible peers; or
2. explicitly designed capability negotiation and extension framing if backward compatibility is required.

No version number or packet type number is chosen in this proposal. Existing v5 clients and movement tests remain unchanged until both client and server implement the agreed contract. A mixed client must never parse an unknown payload as v5 state.

## Acceptance tests

### Identity, authority, and validation

- HOST and JOINER can publish only their own current server-owned player entity.
- Spoofed PlayerId, SessionEntityId, owner, session, epoch, token, retired membership, or role is rejected without cache mutation/fanout.
- A player presentation update cannot target NPC/world entities.
- Supported values round-trip exactly, including TweakDBID values across the high and low uint32 ranges; tests prove no float/double or narrowing conversion occurs.
- Inventory instance IDs, guessed weapon records, unknown enums, invalid combinations, truncation, oversized data, and invalid revisions are rejected or handled by the explicit unsupported state.
- Duplicate and reordered transport sequences cannot refresh freshness or replace state. Sequence wrap and epoch reset behave correctly.
- A newer transport sequence with identical stateRevision and identical content updates receipt freshness only; same revision with different content and a newer packet carrying an older stateRevision are rejected.
- Wrong protocol version/capability fails explicitly.

### Recovery and bounded behavior

- Late join receives latest active-player baselines plus a completion fence; no old shot/reload event is replayed.
- UDP loss is repaired by the next periodic 2 Hz full snapshot proposal; a newer live update racing an older baseline remains authoritative.
- State arriving before projection binding is retained only in the bounded exact-identity cache and applied only to that projection.
- Leave, timeout, reconnect/new PlayerId, session close, and epoch reset remove prior cache, revisions, and bindings.
- Stale interval is configurable. Tests cover just-before/at/after expiry and verify presentation falls back safely while movement continues.
- Baseline or presentation queue failure does not block movement. Coalescing/capacity outcomes are observable and bounded.

### Game-side behavior and diagnostics

- Kyle's adapter publishes read-back; failed crouch/stance readback is Unavailable, not Standing. readback_timeout is not treated as success.
- Aiming state does not assert visible ADS or sight alignment.
- A fresh unchanged snapshot updates age but does not replay equip, stance, or aiming commands; a changed stateRevision is applied once.
- Unknown weapon IDs remain exact and unsupported; they are never replaced by guessed records. Inventory instance IDs never cross the network.
- Multiple remote player projections keep separate state/bindings.
- Human in-game review verifies posture, weapon, and aim rendering; unit tests and state flags alone cannot prove animation.
- RTT requires a matching heartbeat echo and local monotonic timestamps. Snapshot age is per-player local receive age. Neither is described as one-way latency; reconnect invalidates old diagnostics.

## Questions for KyleBuildsAI

1. Does the local hook provide stable Standing/Crouching and Drawn/Holstered read-back, with a distinct Unavailable result for failure and readback_timeout?
2. Can the bridge preserve the full native TweakDBID as uint64_t, and can CET/Lua receive it as an exact string? Is the raw value stable and meaningful on both installations for the supported weapons?
3. Which exact weapon records are supported? For a recognized-but-unsupported record, should the receiver retain the exact ID and use a neutral visual, or hide only the weapon projection? No guessed mapping is acceptable.
4. Can the hook observe logical aim on the owning player? What does the remote experimental hook actually apply today? The wire must not claim ADS or sight alignment.
5. Are Unavailable stance/weapon/aim values and the proposed field invariants representable by the current action adapter? Which combinations can the engine actually produce?
6. Is 2 Hz a suitable initial repair proposal under expected two-player and 8–16-player use? It is not validated. What stale interval and reversible fallback are acceptable? Should a stale held-weapon visual be hidden, reset only through an owned adapter cleanup, or retained with a degraded marker?
7. Is PlayerId + SessionEntityId unique for a membership lifetime, and can the server guarantee no PlayerId reuse in an epoch? Does the game adapter require a separate wire membership generation?
8. Which one-shot actions are visual-only and which require HOST validation as gameplay intent/result? What expiry is acceptable?

## Staged implementation plan

1. Jointly approve semantic fields/enums, weapon ID encoding, valid combinations, repair rate, expiry/fallback, baseline fence, and compatibility strategy.
2. Add the agreed codec and malformed/version/sequence tests in a separate implementation change. Do not alter v5 bytes or reuse movement/gameplay fields.
3. Add server ownership validation, bounded latest-state cache, relevant-peer routing, baseline/reconnect lifecycle, and real-socket tests. Keep movement activation independent.
4. Add typed SessionClient accessors, bounded SessionBridge state APIs, and local-only RTT/snapshot-age diagnostics.
5. Kyle connects read-back and exact projection handling on the game thread. Validate movement and readback_timeout independently before presentation tests.

Until those decisions are approved, this document remains a proposal only.
