# Proposed player presentation state

KyleBuildsAI owns the game-side hooks. Bukczyk owns the shared wire, client and
server route. This is a review proposal, not an implemented or accepted contract.
It complements the movement adapter using the existing position/yaw interface.

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
as old fields. This document does not reserve a packet number or change v3.

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

Player movement can be improved now with unchanged v3 position/yaw data. Weapon,
stance and aiming engine hooks can be exercised using a private local fixture,
but must not be advertised as multiplayer sync until the accepted route exists.
Keep the v0.0.37 package as the tested rollback while the typed preview is qualified.
