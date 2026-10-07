# Shared Encounter typed networking contract

Status: proposal only; this file assigns no wire IDs and changes no code. It defines the authority and message semantics needed before the first shared-encounter implementation. Exact game-side payload fields remain subject to KyleBuildsAI's confirmation.

## Scope and current baseline

The encounter messages in scope are HitRequest, WorldStimulusRequest, DamageApplied, and EntityDeath. HOST remains the only authority that evaluates NPC/world AI, applies damage, and declares death. A JOINER sends intent and renders HOST-approved outcomes; it never sends a damage result or death decision.

Protocol v3 already defines a 40-byte envelope with SessionId, world epoch, authenticated PlayerId, a state sequence, and a reliable event ID. In the current C++ names, the 64-bit session entity identity is EntityId; SessionEntityId is its game/session meaning. HitRequest and DamageApplied appear in the current type declarations, but their existing placeholder fields are not an approved encounter contract. WorldStimulusRequest and EntityDeath are not wire packet types, and SessionBridge::SubmitWorld still returns Unsupported. No current declaration proves an end-to-end game action.

This proposal deliberately leaves message numbers, exact binary layouts, hit evidence, stimulus descriptors, and damage/death engine fields open. If the accepted payload layout changes existing v3 messages, the implementation must make an explicit protocol-version/compatibility decision; peers must never infer a layout from payload contents.

## Identity, request IDs, and ordering

Every request is scoped by this key:

    RequestKey = (SessionId, worldEpoch, authenticated sender PlayerId, Header.event)

For a reliable request, Header.sequence is zero and Header.event is a nonzero EventId. That EventId is also the request ID; callers must not create a second unrelated ID. It is unique and contiguous in the sender's reliable event stream for that session epoch. Retransmission uses the same key and same payload. A new user action uses a new event ID. The server binds the sender from the authenticated connection; a payload cannot claim another PlayerId.

Each HOST-originated DamageApplied, EntityDeath, or request-status event also has its own nonzero HOST Header.event. This result/event ID is distinct from the request ID. A result that answers a request carries the requester's PlayerId and original request EventId; session and epoch are taken from the result envelope. Thus a correlation is unambiguous even when two JOINERs independently use the same numeric event ID.

Use the existing server-issued SessionId, PlayerId, and 64-bit session entity identity. Entity identity is stable for the epoch, is never reused within that epoch, and is never inferred from position. Requests and outcomes from another session, unknown member, non-current epoch, or unowned sender are rejected before gameplay mutation.

Reliable IDs provide ordered, at-least-once delivery semantics across the application boundary, not exactly-once effects by themselves. The server and HOST keep bounded deduplication/outcome records keyed by RequestKey; HOST reserves the key before invoking a game action. Repeated delivery returns the recorded status/outcome and cannot call damage or stimulus logic again. JOINERs deduplicate HOST events by (SessionId, epoch, HOST PlayerId, Header.event) before applying presentation updates.

## Message contract

All four messages use the reliable, ordered TCP event path. None is a high-frequency state snapshot. The session server validates the envelope, membership, sender role, epoch, event ordering, entity namespace/registration, and bounded routing capacity. It routes JOINER intent only to that session's HOST, and HOST outcomes only to active members of that same session. It does not decide whether a hit is valid, apply damage, run AI, or declare death.

| Message | Direction and sender | Required semantic content | Receiver behavior |
| --- | --- | --- | --- |
| HitRequest | JOINER → session server → HOST | Request key from the envelope; target SessionEntityId. Attacker identity is the authenticated sender PlayerId, not a client-supplied owner claim. Additional hit evidence is pending game-side agreement. | HOST resolves the exact target and validates the request against its current encounter/game state. It may accept or reject; it never trusts client-proposed damage. |
| WorldStimulusRequest | JOINER → session server → HOST | Request key from the envelope. The stimulus descriptor/schema is pending game-side agreement. Any entity references in the eventual descriptor use SessionEntityId; coordinates, if agreed, are descriptive data and never identity. | HOST decides whether the stimulus is supported and relevant, then alone causes any NPC/world reaction. |
| DamageApplied | HOST → session server → active JOINERs | New HOST event ID; target SessionEntityId; originating request key when causally related; actual applied-result data pending game-side agreement. | JOINER records/renders the accepted HOST result only. It does not independently apply the encounter damage or recompute the result. |
| EntityDeath | HOST → session server → active JOINERs | New HOST event ID; dead SessionEntityId; causal request key when applicable. Exact death/cause/lifecycle detail is pending game-side agreement. | JOINER records/renders the authoritative death and retires the local projection for that exact entity. It does not decide that the entity died. |

WorldStimulusRequest may lead to zero, one, or multiple authoritative outcomes. A HitRequest may be rejected, may be accepted without damage, or may cause DamageApplied and then EntityDeath. HOST event ordering must put a resulting DamageApplied before a causally resulting EntityDeath. Both remain separate reliable events with separate HOST event IDs.

The session entity registry retains a death tombstone for the rest of the epoch. This lets HOST distinguish a dead target from an unknown target and reject later hit/stimulus requests without resurrecting or damaging it. A world reset increments the epoch and clears epoch-scoped entity/death/dedup records.

## Request status and failure semantics

A small typed EncounterRequestStatus is needed in addition to the four domain messages so callers can distinguish transport/routing from gameplay outcomes. This is a proposed control/result contract, not an existing packet type; no numeric type value is assigned here.

It carries the full request correlation (PlayerId plus request EventId, with session/epoch in the envelope), a status, and a stable reason code when applicable:

- Forwarded: session server accepted and queued the request for HOST. This is only a relay receipt; it does not mean gameplay accepted the request.
- Accepted: HOST consumed and handled the intent. It does not promise damage or a visible world effect; domain outcomes, if any, arrive separately.
- Rejected: the named layer deliberately refused the request. Reasons include invalid/missing target, target already dead, stale epoch, unauthorized sender, malformed/invalid intent, and bounded-queue exhaustion.
- Unsupported: HOST does not implement that request kind or descriptor yet. No gameplay effect occurs.
- RetryLater: optional only for a failure that happened before the request key was committed. The sender retries the exact same request key and pauses later IDs on that reliable stream until it resolves.

The responder/layer must be explicit (session server or HOST). Server-generated control responses follow the existing server-control envelope convention; HOST outcomes use the HOST's reliable event stream. A server receipt or rejection is never presented as a HOST gameplay result.

Queue behavior is part of the contract:

1. Reserve bounded ingress/event-queue capacity before committing a request ID or running game logic. If capacity cannot be reserved, return an explicit queue-failure status and do not mutate the world. If the failure is retryable, do not consume the event ID and require the same ID on retry; otherwise return terminal Rejected(QueueFull) and consume it so the reliable stream can continue.
2. Never evict a committed request or a DamageApplied/EntityDeath event silently. Reserve bounded outbound capacity before HOST commits a gameplay effect. If delivery cannot be guaranteed, do not claim success; retain the committed result for replay or force the affected receiver to resynchronize before it can accept further encounter traffic.
3. A bounded dedup/outcome cache must retain entries for the complete retry/reconnect window. Eviction must not make an old request eligible for a second application; epoch reset is the natural end of the key space.

## Epoch changes, reconnect, and authorization

The server rejects a request with a foreign or stale SessionId/epoch before forwarding it. HOST independently checks the same identity at the game-thread boundary before resolving an entity or applying an effect. A stale DamageApplied or EntityDeath is discarded by JOINER before presentation.

A reconnect gets fresh authenticated connection state and follows the current admission/baseline flow. Traffic from the old connection token is rejected. If the reconnect is assigned a new PlayerId, its old requests are not transferable: replaying the prior key is rejected as an old/nonmember identity, not reinterpreted as an action from the new player. Same-epoch duplicate delivery on a still-valid member key returns the cached result without reapplying. A new world epoch rejects every request and result from the prior epoch and clears the old request/dedup state only after its pending reliable outcomes are resolved or explicitly invalidated.

The server checks that requests originate from an active JOINER, that their references are session-scoped and registered, and that HOST-only result packets originate from the authenticated HOST. It must not approve a hit from proximity, a claimed damage number, or a client-supplied PlayerId. HOST performs final ownership, alive-state, hit/stimulus, and simulation checks against its own entity registry.

All REDengine access stays on the game thread. Network workers transfer immutable decoded values through bounded queues. Queue admission, status, and replay decisions must not read or mutate game objects.

## Acceptance tests before implementation is considered complete

| Test | Setup and action | Required assertion |
| --- | --- | --- |
| Duplicate hit request | Deliver the same HitRequest and RequestKey twice, including retry/duplicate transport delivery. | HOST invokes the damage path at most once; repeated delivery returns the cached status/outcome; one causal DamageApplied/EntityDeath sequence is observed. |
| Duplicate stimulus request | Deliver one WorldStimulusRequest twice with the same key. | HOST stimulus logic runs at most once; the same disposition is returned; no duplicate world reaction is emitted. |
| Stale epoch request | Reset the world, then send a request carrying the previous epoch. | Server rejects before relay; HOST action count remains unchanged; the current epoch and entity catalog remain authoritative. |
| Stale result | Deliver a prior-epoch DamageApplied or EntityDeath to JOINER after reset/reconnect. | JOINER discards it and does not alter the new epoch's entity/presentation state. |
| Reconnect replay | Disconnect a JOINER after request submission, reconnect with a fresh token/identity, and replay the old request key. | Old connection traffic and nonmember identity are rejected; no second action occurs; the JOINER receives the current baseline before new requests are accepted. |
| Dead target | Submit against a SessionEntityId with a HOST death tombstone. | HOST returns Rejected(TargetDead); no damage or second death event is produced. |
| Missing target | Submit an unknown/unregistered SessionEntityId. | Relay or HOST returns Rejected(TargetMissing) at the first layer with enough authority to know; no positional search or gameplay mutation occurs. |
| Unsupported request | Submit an otherwise valid request kind/descriptor not implemented by HOST. | Return Unsupported; no side effect and no success-shaped domain event. |
| Ingress queue failure | Fill the bounded request/game-thread queue, then submit a hit. | Explicit retryable or terminal queue status is returned according to whether its ID was committed; damage count remains zero; the stream either retries the same ID or proceeds with the next ID exactly as specified. |
| Outcome queue failure | Exhaust a bounded reliable result queue before a HOST outcome is committed. | HOST does not report success or apply an effect unless the outcome has reserved delivery capacity; no committed outcome is silently dropped. |
| Authority and isolation | Forge a sender, target another session, send a JOINER DamageApplied/EntityDeath, or send HOST-only results from a JOINER. | Each is rejected before mutation/routing outside its authorized session; legitimate peers in other sessions see nothing. |
| Ordered causal outcomes | Cause a confirmed hit that results in damage and death. | All active JOINERs observe one DamageApplied before one EntityDeath, both with matching session/epoch/target and causal request key. |

## Game-side questions for KyleBuildsAI before implementation

No REDengine-specific hit/stimulus/damage/death field is fixed by this proposal. Please confirm:

1. Which verified HOST-side hook reports a candidate hit before damage is applied, and which verified JOINER-side hook can submit the corresponding intent? What exact hit-context facts are available and trustworthy at those hooks? Confirm the minimum payload beyond the target's SessionEntityId; do not assume that a client damage amount, bone, hit position, weapon ID, or attack tag exists or is authoritative.
2. Which gameplay actions qualify as a WorldStimulusRequest for the first encounter, and which verified JOINER hook observes them? What exact stimulus descriptor can be captured on the JOINER and independently validated by HOST? Confirm whether it references a target/source entity, a world location, or both; these are not wire fields until agreed.
3. Which HOST hook can validate and apply damage exactly once, and how can it observe the actual applied result rather than a proposed amount? Confirm the minimal DamageApplied result fields and whether nonlethal damage, blocked hits, armor, critical outcomes, or damage types need distinct representation for the MVP.
4. Which HOST hook observes the authoritative death transition, and when is it safe to emit EntityDeath relative to damage application and local entity removal? Confirm how duplicate death callbacks, despawn, revive/respawn, and the stable SessionEntityId mapping behave.
5. Which target kinds are in the first encounter (NPC only, or other registered entity kinds), and which exact game-thread mapping resolves each SessionEntityId to the HOST's local entity? Confirm that no nearest-position or name-only lookup is required.
6. What bounded game-thread queue capacity/failure signal can the hooks honor, and what UX-safe behavior should the JOINER see when a request is unsupported, rejected, or delayed by backpressure?

Until these answers and the semantic payloads are reviewed, the wire HitRequest placeholder fields (attacker, target, proposedDamage), the game-bridge HitRequest action field, and the WorldStimulus, DamageApplied, and EntityDeath bridge sketches remain non-contractual. No implementation should treat them as verified engine facts.