# Player weapon readiness and exact held-item lifetime

Owner: KyleBuildsAI. 2026-10-15 UTC. Branch `feat/player-action-preparation`,
base `d735c684e56601b02fd2ec6eaea06254e6dec136`.
This is opt-in local experiment code, with no runtime startup registration,
installation, package, networking or backend change.

## Engine evidence and scope

Installed primary sources were inspected read-only under
`G:\SteamLibrary\steamapps\common\Cyberpunk 2077 - Baseline\tools\redmod\scripts`:

| Source | Verified interface or use |
| --- | --- |
| `core/systems/transactionSystem.script:10` | `GetItemAppearance(owner, ItemID)` reads the actual item appearance name. No fabricated appearance name or setter is used. |
| `core/systems/transactionSystem.script:58-66` | Slot emptiness, pending item spawning, item identity/data and actual attached item are distinct native queries. |
| `core/ai/actions/tweakAISubActions.script:560-578` | Stock NPC equipment logic checks slot emptiness and pending-spawn state before reading/removing the item object. |
| `cyberpunk/items/weapon.script:146` | `WeaponObject.GetMuzzleSlotWorldTransform()` returns the weapon's current muzzle transform. |
| `core/ai/actions/tweakAISubActions.script:3278-3279` | Stock code reads muzzle world position through `Transform.GetPosition`. This experiment only reads the transform; it does not call the shooting logic. |

These establish available calls and the need to distinguish slot state from an
existing item object. Native timing, returned default transforms and rendered
visibility still need live qualification. This change does not bypass AI equip
commands with direct inventory attachment, disable AI, or introduce new Aim calls.

## Changes

The previous held-weapon hook treated a missing object as holstered and matched
a drawn record without checking item attachment/spawning. A pending slot could
therefore be accepted or receive competing equip/stance work.

`CP2077Session_ReadPresentationWeapon` now returns one local observation of:
exact owner/item EntityIDs, actual item record, slot spawning/emptiness, object
presence/attachment, and match result. It repeats the slot and identity reads
after collecting the sample. Changed owner, item EntityID, full inventory ItemID,
attachment or slot flags return unavailable rather than combining lifetimes.
This is a game-thread observation, not an atomic engine transaction guarantee.

The Lua controller distinguishes `spawning`, `attaching` and `slot_pending` from
confirmed `drawn`/`holstered`. Pending observations queue without submitting
equipment or stance changes. Existing admitted commands and deadlines remain
owned and bounded. Unknown/malformed observations fail closed; they never fall
back to the old record-only match. Fresh readback can resume normal work without
inventing new serials or delivery state.

The Aim lease now captures the actual weapon EntityID and record. Native
acquisition, logical reads, signal requests and release reject a different
same-model item or an unready slot. The Lua probe also checks that exact item.
If the weapon becomes unavailable after acquisition, it retains uncertain lease
ownership and requests exact actor retirement through the existing lifecycle;
it does not force Normal or transfer the lease to another item. A known native
acquisition rejection still releases only the local Actions reservation.

`inspect().weaponEvidence` contains detached, timestamped values: owner/item
keys, record, appearance, readiness and available finite muzzle position/rotation.
Invalid/nonfinite/zero-norm muzzle data is labelled invalid and omitted. These
values are evidence only: `sampled` means numeric transform readback, not visible
grip, sight alignment, animation or ADS. The ordinary action result remains
`partial / ads_unavailable` for held aim, and the probe's `visual` stays
`unverified`. Missing readback clears previous weapon evidence; paused samples
retain their original timestamp. No inventory-instance identifier is serialized.

Both experiment REDscript files and Lua modules must be used together because
the local Aim acquisition signature now includes its expected weapon EntityID.
No supported network interface changed.

## Validation

- 328 focused action/probe checks pass under Lua 5.4 and LuaJIT 2.1.
- The readiness regression fails the prior `d735c68` action adapter at
  `empty_spawning`, where it incorrectly reports matched holstered equipment.
- Tests cover empty/occupied spawning slots, detached matching items, pending
  slot data, exact owner/item IDs, malformed flags, delayed readiness, retained
  command deadlines, cloned diagnostic evidence, invalid muzzle data, same-model
  item replacement before/during Aim, and lease retention during pending slots.
- All 29 branch CTests pass. The actual Actions and Probe entrypoints run with
  engine API fixtures; REDscript runtime execution is not claimed from mocks.
- Independent read-only review reran all 328 checks under both Lua runtimes,
  inspected the native source signatures/stock muzzle use and found no blocker
  in exact identity, pending-slot handling or lease ownership.
- Both experimental REDscript files compile with copied installed Test B cache,
  Codeware and matching session scripts. Before/after SHA256 records confirm all
  compiler/game/source inputs stayed unchanged. Final compile evidence:
  `D:\Downloads\syncfix\bench-artifacts\20261009-player-actions\compile-20261015T080734302340Z.json`
  and the matching log. The first compile identified an unsupported Bool `!=`
  overload; replacing those comparisons with `NotEquals` resolved it.
- `git diff --check` passes. Local ignored logs are
  `build/offline-actions/weapon-readiness-{baseline,luajit,ctest}.log`.

## Ownership and remaining gates

Owned files: `experiments/player-presentation/{action_hooks.reds,actions.lua,aim_probe.reds,aim_probe.lua,README.md}`,
`tests/player_actions_tests.lua`, the Aim validation note and this note.
No shared protocol, native session, server, normal runtime/defaults or installed
game files changed. No new native build was needed for these Lua/REDscript edits.

Deferred live checks remain draw/switch/holster with real item streaming,
appearance/muzzle readback against video, standing/crouching grip, Aim entry/hold/
exit and controlled same-record item replacement. A finite muzzle transform can
still be a native default and is not itself a visibility test. Multiplayer
delivery/reconnect awaits the agreed presentation contract; arbitrary player
appearance, inventory, firing and combat parity are not implemented here.
