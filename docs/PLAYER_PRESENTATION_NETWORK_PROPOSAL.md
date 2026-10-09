# Player presentation network proposal

**Status:** draft for joint review; not an accepted wire contract  
**Scope:** persistent player presentation in the existing session architecture  
**Protocol:** v5 remains unchanged  
**Ownership:** Bukczyk owns shared wire/client/server/SessionBridge; KyleBuildsAI owns REDengine capture and projection hooks

This proposal records the approved architectural direction and remaining wire decisions. It does not allocate packet type numbers, gameplay action kinds, or a protocol version. It changes no production packets, routing, runtime scripts, or VPS configuration.

The immediate priority remains smooth player movement and fixing readback_timeout. Presentation is additive and must not gate the existing movement path, session activation, or movement testing.

## Agreed direction

- Keep presentation state separate from PlayerPose and PlayerState.
- The first presentation MVP covers Standing/Crouching, Drawn/Holstered, and the identifier of a supported held weapon.
- The contract may include logical aiming state. Its presence does not promise remote ADS, weapon alignment, or visible aim animation.
- Do not add aimPitch now.
- Send a complete state immediately after an observed local change, then send periodic full snapshots to repair loss. Start by evaluating a configurable 1–2 Hz repair rate; do not assume 10 Hz.
- The server validates membership, ownership, exact player/entity identity, session, epoch, revision, and values. It caches the newest accepted state and provides a current baseline to joining clients.
- One-shot actions remain events, separate from persistent state.

## Existing implementation boundary

Protocol v5 PlayerPose and PlayerState contain only entity ID, body transform, and sample time. There is no typed player presentation payload. The server's player-state cache and relevance routing cover transforms only.

The reliable GameplayIntent / GameplayResult path carries an opaque kind and body (up to 1024 bytes). The server routes JOINER intent to HOST and HOST result to active session members, but this is not a presentation schema or a latest-state cache for late join. Do not use it as a substitute for persistent presentation.

SessionBridge::ReadFrame currently exposes remote PlayerId, SessionEntityId, and interpolated body transform. RemotePlayer internally retains sequence, source time, and local receive time, but the frame exposes none of them. Existing game-facing transform input is separate from action state.

References: [v5 protocol types](https://github.com/Bukczyk/CP2077-Coop/blob/main/shared/include/coop/protocol.hpp), [SessionClient API](https://github.com/Bukczyk/CP2077-Coop/blob/main/shared/include/coop/client.hpp), [SessionBridge API](https://github.com/Bukczyk/CP2077-Coop/blob/main/shared/include/coop/game_bridge.hpp), and [PR #16](https://github.com/Bukczyk/CP2077-Coop/pull/16).

## Proposed semantic schema

Each update is one coherent full state, not a patch. Identity and revision use the existing header; the body describes the current observed presentation of the player's exact session entity.

| Field | Proposed type | Meaning and validation |
| --- | --- | --- |
| Header session | Existing SessionId | Must be the sender's active session. |
| Header epoch | Existing uint32 world epoch | Must match the active session epoch. |
| Header sender | Existing PlayerId | Authenticated member who owns the state. |
| Header sequence | Existing uint32 sequence | Revision for this player/entity presentation stream; use the protocol's modular sequence comparison. |
| Header event | Existing uint64 | Zero for a snapshot. Event IDs are for reliable one-shot/control events. |
| entity | SessionEntityId / uint64 | Must resolve to the exact player entity owned by sender. Never infer from position. |
| stance | uint8 enum | Proposed values: Unavailable, Standing, Crouching. |
| weaponState | uint8 enum | Proposed values: Unavailable, Holstered, DrawnSupported, DrawnUnsupported. |
| weaponRecord | uint64 | Portable canonical weapon record for DrawnSupported; zero otherwise. |
| aiming | uint8 enum | Proposed values: Unavailable, NotAiming, Aiming. Logical state only; no promise of rendered ADS. |

Enum names and values are proposed semantics only. They do not assign a packet type number. The body is 19 bytes; with the current 40-byte header the record would fit within the current 1200-byte packet ceiling. Exact byte encoding, packet type, and protocol compatibility are open decisions.

For weaponRecord, the preferred candidate is a portable canonical TweakDB record identity, not an inventory instance ID, pointer, or local runtime offset. The NPC contract already represents canonical TweakDB names in uint64 form; Kyle must confirm the action hook can expose the same stable identifier for supported weapons. Report DrawnUnsupported rather than inventing a stand-in weapon. A receiver may use a neutral fallback for unknown records.

The producer sends observed/read-back state, not merely a requested command. Unavailable is not equivalent to standing, holstered, or not aiming. A command timeout must never be reported as a successful observed state.

Proposed cross-field rules:

- Holstered, DrawnUnsupported, and Unavailable carry weaponRecord=0.
- DrawnSupported requires a nonzero canonical supported record.
- Aiming=Aiming is accepted only for combinations Kyle confirms are observable locally. Whether aiming requires DrawnSupported is still an engine-contract question.
- Unknown enums, noncanonical records, invalid combinations, invalid future numeric fields, and oversized packets are explicitly rejected.

No pitch or camera direction is included. Body yaw is not aiming direction and must not be repurposed.

## Transport, ordering, and limits

### Live state

Use unreliable UDP. Send a full state when local read-back changes, followed by configurable 1–2 Hz full-state repair snapshots. A periodic snapshot repairs a lost change. These are configuration values, not protocol constants.

The client retains at most one coalesced pending full state for its local player. If a newer full state supersedes an unsent state, retain the newest and expose queue pressure through the API. Persistent state is replaceable; one-shot events are not.

The server validates the authenticated connection, active membership, role policy, session, epoch, exact owner/entity mapping, and revision. It stores one latest state per active player in the bounded session membership collection. It routes accepted updates only to active, relevant same-session peers using the existing interest policy, never unconditional all-player broadcast. Player ownership covers only that player's cosmetic presentation; HOST remains authority for Night City simulation.

The revision uses the existing header sequence for the sender/entity/presentation stream. Reject duplicate and stale sequence values using the existing modular uint32 rule. Epoch/member retirement clears sequence state. Keep server receive time locally; do not rely on unsynchronized sender clocks for one-way age.

### Join baseline and reconnect

For a joining client, provide the newest cached full presentation state for each active relevant player over a reliable bootstrap path, followed by a presentation-baseline completion fence. The packet envelope and type identifiers are deliberately not allocated here. The baseline contains current state only and never replays transient events.

The presentation fence is separate from the current movement/session readiness path. A missing or unsupported presentation field must not block movement, session activation, or the movement test. If a live UDP update races with a baseline copy, keep the newer revision.

Reconnect receives current state for active players and a fresh PlayerId. Retire the old membership's presentation; never assign it to the new ID. The reconnecting client captures its own current read-back state and publishes it under the new identity. Leave, timeout, session close, entity removal, and epoch reset clear matching cache, revision, and adapter bindings.

If state arrives before its exact projection is ready, retain only the newest value under SessionId + epoch + PlayerId + SessionEntityId, bounded by active membership count. Apply it only after exact identity binding. Never search for a nearby actor.

### Freshness and membership lifetime

Agree on the maximum presentation freshness interval and receiver behavior at expiry. The receiver must not leave an old weapon or posture latched indefinitely; it may preserve a neutral/default projection while marking the state stale.

The server must not reuse PlayerId within an epoch. SessionBridge generation is a local activation fence, not a wire membership generation. If the server cannot guarantee PlayerId non-reuse for a membership lifetime, the joint contract must add a membership-generation field before implementation.

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
- PlayerPresentation: those values, weaponRecord, and accepted revision.
- RenderPlayer: PlayerId, SessionEntityId, interpolated Transform, optional PlayerPresentation, freshness flag, and local presentationAgeMs.

Suggested entry points:

- SetLocalPresentation(scope, observedState): checks current SessionId, epoch, local SessionBridge generation, ownership, invariants, and bounded queue admission. Accepts read-back, never a requested state.
- ReadFrame(localMonotonicNow): returns the newest exact-identity remote state alongside the existing transform; no REDengine object crosses the worker boundary.
- ReadNetworkDiagnostics(): returns separate server RTT and per-player snapshot age with validity and measurement-age fields.

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
- Supported values round-trip exactly; unknown enums, invalid weapon IDs, invalid combinations, truncation, oversized data, and invalid revisions are rejected.
- Duplicate and reordered snapshots cannot replace newer state; sequence wrap and epoch reset behave correctly.
- Wrong protocol version/capability fails explicitly.

### Recovery and bounded behavior

- Late join receives latest active-player baselines plus a completion fence; no old shot/reload event is replayed.
- UDP loss is repaired by the next periodic full snapshot; a newer live update racing an older baseline remains authoritative.
- State arriving before projection binding is retained only in the bounded exact-identity cache and applied only to that projection.
- Leave, timeout, reconnect/new PlayerId, session close, and epoch reset remove prior cache, revisions, and bindings.
- Baseline or presentation queue failure does not block movement. Coalescing/capacity outcomes are observable and bounded.

### Game-side behavior and diagnostics

- Kyle's adapter publishes read-back; readback_timeout is not treated as success.
- Aiming state does not assert visible ADS.
- Multiple remote player projections keep separate state/bindings.
- Human in-game review verifies posture, weapon, and aim rendering; unit tests and state flags alone cannot prove animation.
- RTT requires a matching heartbeat echo and local monotonic timestamps. Snapshot age is per-player local receive age. Neither is described as one-way latency; reconnect invalidates old diagnostics.

## Questions for KyleBuildsAI

1. Does the game-side hook provide stable Standing/Crouching and Drawn/Holstered read-back, with a clear unavailable/timeout result?
2. Can it expose a portable canonical TweakDB weapon record for the exact supported held firearm? Which models are supported and what should unknown weapons render as?
3. Can it observe logical aim on the owning player? Can a remote projection apply any aim state today? The wire must not claim ADS until visibly verified.
4. Are the proposed unavailable states and field invariants representable by the current action adapter? Which combinations can the game actually produce?
5. Is PlayerId + SessionEntityId unique for a membership lifetime, and can the server guarantee no PlayerId reuse in an epoch? Does the game adapter require a separate wire membership generation?
6. Is 1 Hz sufficient for repair, or should the first test use 2 Hz? What stale interval and receiver fallback are acceptable?
7. Which one-shot actions are visual-only and which require HOST validation as gameplay intent/result? What expiry is acceptable?

## Staged implementation plan

1. Jointly approve semantic fields/enums, weapon ID encoding, valid combinations, repair rate, expiry/fallback, baseline fence, and compatibility strategy.
2. Add the agreed codec and malformed/version/sequence tests in a separate implementation change. Do not alter v5 bytes or reuse movement/gameplay fields.
3. Add server ownership validation, bounded latest-state cache, relevant-peer routing, baseline/reconnect lifecycle, and real-socket tests. Keep movement activation independent.
4. Add typed SessionClient accessors, bounded SessionBridge state APIs, and local-only RTT/snapshot-age diagnostics.
5. Kyle connects read-back and exact projection handling on the game thread. Validate movement and readback_timeout independently before presentation tests.

Until those decisions are approved, this document remains a proposal only.
