# Proposed player presentation state

KyleBuildsAI owns the game-side hooks. Bukczyk owns the shared wire, client and
server route. This is a review proposal, not an implemented or accepted contract.
It complements the movement adapter using the existing position/yaw interface.

## Offline preparation checkpoint, 2026-10-09 UTC

The current base is `b1f054ed67c0bb03f1b8e290c2b5fd62a621307c`, protocol v5,
on the player movement/presentation contribution. Protocol v5 has a generic
reliable GameplaySubmit route, but that is **not an agreed player action or
appearance contract**.
No packet, backend, native declaration, current runtime or installed game file
changes in this preparation.

KyleBuildsAI owns these preparation files:

- `experiments/player-presentation/action_hooks.reds`: local capture, firearm
  allowlist, exact right-hand slot readback, stance request/readback and owned
  equip/unequip command release.
- `experiments/player-presentation/actions.lua`: game-thread local adapter.
- `tests/player_actions_tests.lua` and its `tests/CMakeLists.txt` registration.
- This contract note and `experiments/player-presentation/README.md`.

Read the experiment README for API, evidence and limitations. Capturing held aim
is implemented. Applying remote ADS animation, sight alignment or pitch is **not
implemented**. A true aiming state returns `partial / ads_unavailable` after
supported equipment/stance readback; it cannot produce an observed ADS result.

The [opt-in local Aim-state probe](validation/PLAYER_AIM_PROBE.md) now exercises
the installed NPC upper-body signal and logical readback under an exclusive
actor lease. This adds no remote aim direction or ADS guarantee. Normal/Aim
blackboard values, command submission and visible weapon/sight pose are separate
evidence. The normal action adapter still returns `partial / ads_unavailable` for
held aim; probe completion cannot upgrade that to observed ADS.

## Information and decisions needed from Bukczyk

These are requirements to agree together, not a request to adopt a Lua wire format:

| Boundary | Needed data / decision | Direction and recovery |
| --- | --- | --- |
| Persistent actions | Drawn/holstered, exact supported weapon record, standing/crouched, held aim; agree valid combinations, record encoding, units/ranges for any future pitch | Local owning player -> authenticated accepted state -> relevant peers; specify reliable changes or periodic repair snapshots, order and freshness |
| Appearance | Canonical supported player descriptor, appearance/equipment slot identities and revisions, asset/capability mismatch behavior | Owning player's supported appearance -> agreed validation -> peer projection; include latest baseline on late join, reconnect and restream |
| Identity | Session, epoch, membership generation, PlayerId and owned SessionEntityId, accepted revision | State may wait before exact projection binding; despawn/removal invalidates it; stale generations must not affect a replacement |
| Reliability | Delivery channel, coalescing/rate/queue bounds, overload outcome, loss deadline and resync trigger | Latest held state must recover after loss; define what peer hides/neutralizes/removes when freshness expires |
| One-shot actions | Separate shot/reload/melee identity, ordering/expiry and correlation to accepted gameplay | Do not derive shots from held aiming or persist `firing=true`; reconnect does not replay expired animation or gameplay |

Please provide the supported field/descriptor schema and native snapshot or event
read/write entry points, their direction, lifetime/order guarantees and baseline
recovery semantics. KyleBuildsAI can then connect these game-side hooks to the
accepted interface. GameplaySubmit's generic body and reliable delivery alone do
not specify those meanings. No new gameplay kind or private network message is
allocated here. Body/face/clothing matching, full animation and inventory parity
remain separate engine and contract work.

## Why guns and crouching disappeared

The older playable prototype carried weapon/stance flags. The current typed
PlayerPose/PlayerState carries position, rotation and sample time only. Copying
the old equipment code does not make that state available to the other clients.
The new route must keep multiple players, ownership and reconnect semantics.

## Proposed boundary for agreement

Add a typed `PlayerPresentation` state, separate from transform data:

| Value | Meaning |
| --- | --- |
| session, epoch, sender, sequence | Existing validated header identity/order |
| entity | The sender's server-assigned player entity only |
| stance | Explicit Standing/Crouching enum; no arbitrary integer |
| weaponRecord | Portable TweakDB identifier for supported held weapon, zero when holstered; never inventory instance ID |
| aiming | Held aiming state; visual pose only |
| aimPitch | Finite bounded angle in radians for future aim pose |
| locomotion | Grounded/Airborne/Swimming/Mounted enum; unsupported adapters explicitly report a fallback |

Do not use weapon-class stand-ins when an exact supported model is available.
Unsupported/cyberware records need an explicit unarmed fallback. Presentation
does not grant inventory, damage, a seat, or authority over world NPCs.

The sender supplies its own presentation. The server checks membership, epoch,
entity ownership, enum/range validity and ordering before caching/routing it.
Late join/reconnect receives the latest accepted state for visible players.
State received before a projection spawns stays pending under exact entity and
epoch; it applies when the matching actor becomes ready. Despawn/epoch reset
clears it. Loss cannot leave an old weapon or crouch state latched indefinitely.

Use reliable state changes with bounded coalescing and explicit overflow policy,
or an agreed periodic snapshot route. Select the wire packet number, protocol
version/capability behavior and rate with Bukczyk before changing both ends.
Older incompatible clients must reject the session rather than parse new bytes
as old fields. This document does not reserve a packet number or change protocol v5.

One-shot fire/reload/melee emotes require separate sequenced events. A persistent
`firing=true` flag is insufficient for exactly-once events. Visual muzzle/aim
animation is distinct from host-authoritative projectile/hit/damage resolution.

## Combined acceptance tests

- Three independent clients show each other's weapon and stance without sharing
  a single global actor tag or command handle.
- Draw, holster, switch weapon, crouch/stand and held aim match on the receiver.
- Changes while the body is streaming apply to that body once, after binding.
- Reconnect and late join recover current held state; old epochs cannot restore
  an old weapon, replay a shot or mutate a different player.
- Spoofed entities, invalid enums/records, oversized packets, reordered state and
  disconnect cleanup are tested at the shared boundary.
- Confirm exact model, posture and aim animation in both game windows. Mocked
  tests and state flags alone do not qualify visual animation.

## Immediate independent work

Player movement can be improved now with unchanged v5 position/yaw data. Weapon,
stance and aiming engine hooks can be exercised using a private local fixture,
but must not be advertised as multiplayer sync until the accepted route exists.
Keep the v0.0.37 package as the tested rollback while the typed preview is qualified.
