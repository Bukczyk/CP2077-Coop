# Offline player action preparation

Experiment only. No startup registration, transport, package inclusion or game
installation. The current runtime does not require this Lua file or load these
REDscript hooks. Work branch: `feat/player-action-preparation`; base:
`b1f054ed67c0bb03f1b8e290c2b5fd62a621307c`.

## What the boundary does

`actions.lua` captures local standing/crouched, held aim and exact native weapon
record through the existing player hooks. Capture refuses an unavailable player
blackboard and unsupported drawn weapon. The initial presentation allowlist is
ordinary handheld firearms only. Fists, cyberware, melee, heavy mounted weapons,
clothing, consumables, quest props and unknown records are rejected explicitly.
An item record existing in TweakDB is insufficient evidence of support. No
weapon-class substitute is used. The eventual protocol must agree its explicit
unarmed fallback for unsupported records.

One controller holds bounded state for multiple exact player identities. It has
one newest desired state and at most one admitted equipment command per player.
States received before binding remain pending. The owner must supply an exact
resolver from session entity key to **owned disposable projection**, never the
local player, an ambient actor or a proximity search. `bind` also rejects sharing
one exact local EntityID between players. Keep native Uint64 identities opaque;
Lua number IDs are rejected. A native TweakDBID is kept local and is not serialized
or converted into an invented wire representation.

Minimal fixture use on the game thread:

```lua
local Actions = require("actions") -- explicitly load from this experiment
local controller = assert(Actions.new({resolve = resolveOwnedProjection}))
assert(controller:reset("fresh session/epoch/membership token", monotonicSeconds))
local state, result = Actions.capture(Game.GetPlayer())
-- Check capture result, then stage with a local monotonically increasing serial.
controller:stage(scope, opaqueEntityKey, serial, state, monotonicSeconds)
controller:bind(scope, opaqueEntityKey, exactProjection, monotonicSeconds)
controller:step(scope, opaqueEntityKey, monotonicSeconds, worldPaused)
local evidence = controller:inspect(opaqueEntityKey)
```

The caller must validate sender ownership and admission before `stage`. The local
serial is a bounded, nonwrapping fixture counter, not a wire sequence algorithm.
A fresh nonempty opaque scope string is required for every epoch or membership
generation. The resolver must be scoped to that same generation. Calls use a
finite nondecreasing monotonic clock; this API is not thread-safe. Callback
reentry into mutations is rejected.

`step` reports `queued`, `observed`, `partial` or `failed`, plus a reason. A queued
command and a changed blackboard are not proof of animation. Equipment reaches
`observed` only when `TransactionSystem.GetItemInSlot(WeaponRight)` contains the
requested exact record, or is empty for holster. Stance readback uses
`GetStanceStateFromBlackboard`, requiring exact Stand/Crouch. Those are engine
state observations only; both still need visual checks. An owned AICommand is
retired through its controller before a replacement is submitted.

Held aim capture uses the PlayerStateMachine upper-body Aim state. It does not
distinguish detailed sight alignment, provide target/pitch, or apply an NPC ADS
pose. Aiming true can produce only `partial / ads_unavailable` after supported
fields match. Aiming false reports `not_requested`; it does not prove the remote
actor exited a previously externally applied ADS animation. No fire/reload/melee
hook, damage, shot replay, custom appearance or inventory synchronization exists.

## Bounded lifecycle and failure

Defaults are 64 retained player entries, two active seconds per admitted request
and five active seconds of desired-state freshness. Capacity is configurable
1..4096 for offline tests, not a live player-capacity claim. A command is submitted
once. Frequent new states coalesce without extending its original deadline.
Pause retains ownership and stops consuming deadlines. The caller must keep
calling `step` for tracked entries, including missing/not-yet-bound projections,
and supply actual pause state. No timer runs in the background.

Readback timeout/expiry stops owned equipment work and reports failure. It does
not secretly reset an actor's stance/equipment or certify a safe visible fallback.
The fixture owner must retire/hide the exact failed projection through its
verified lifecycle before claiming loss recovery. Fresh updates cannot clear a
latched failure. Unbind clears pending state, keeps the serial tombstone and
requires fresh state before a replacement can act. Retained entries/tombstones
consume capacity until the next scope; there is no unsafe eviction. Reset first
releases all command handles and refuses to drop ownership on cancellation failure.

An equipment call throwing after possible submission reports
`submission_uncertain`, blocks reset and requires the fixture owner to retire the
exact actor through its separately verified lifecycle before discarding this
controller. Do not hot-reload away uncertain ownership. A changed mapping fails
without commanding the replacement. A later explicit release uses only the
retained original actor/command and verifies the actor's original exact ID.

The experimental equip hook can give at most eight missing allowed weapon records
to one disposable projection. An actor-local REDscript ledger records each grant
attempt before the mutation, including failed/uncertain attempts. This survives
Lua rebinds/wrapper churn. Existing inventory does not consume grant capacity.
Both the Lua preflight and REDscript grant guard fail closed at capacity; the Lua
reason is `inventory_capacity`. No removal of equipped items has been qualified,
so no inventory is deleted by this adapter. Temporary granted items remain owned
by the exact projection until its separately verified retirement. Do not retain
these experiment actors as persistent world NPCs or use this API for other actors.

## Validation and handoff

UTC handoff owner: KyleBuildsAI, 2026-10-09. Bukczyk retains all shared protocol,
native session/backend routing and recovery ownership; no ownership transferred.
The exact action/appearance requirements are in
[`docs/PLAYER_PRESENTATION_CONTRACT.md`](../../docs/PLAYER_PRESENTATION_CONTRACT.md).

- PASS: 142 mocked checks through the existing Lua runner, including three
  independent players, pre-bind coalescing, draw/switch/holster/crouch, aim capture
  and unsupported ADS, invalid weapons, duplicates, stale scopes, capacity,
  pause, timeout, identity changes/wrapper churn, grant capacity, exact command
  retirement, callback reentry and failure retention. Grant tests mock the engine
  inventory API; they do not establish live item grant or retirement behavior.
- PASS: fresh offline Windows Release core/server/test build and 29/29 CTests.
  Build: `build/offline-actions`, Visual Studio 17 2022 / MSVC 19.41.33923.
  The initial configure request used the repo note's VS18 generator, which this
  installed CMake does not support; the actual configured compiler is recorded
  here. Plugin/legacy server builds were disabled because their source is unchanged.
- PASS: isolated REDscript compile against Test B's vanilla cache and Codeware,
  matched base session declarations, plus only this experimental hook source at
  2026-10-09T04:35:08Z. Source/game input hashes were unchanged.
  Local evidence: `D:\Downloads\syncfix\bench-artifacts\20261009-player-actions\`
  `compile-20261009T043507638076Z.json` and matching `.log`.
- NOT RUN: live weapon/stance visibility, remote ADS, connected action delivery,
  two-window or two-PC tests. Compile and mocked state do not qualify animation.

The [historical 2026-10-06 visual acceptance failure](../../docs/validation/PLAYER_PRESENTATION.md)
remains unresolved. Those hooks compiled against the then-installed 2.31/Codeware
scripts and the private owned-projection fixture ran, without establishing a
visible matching weapon/crouch. The next
engine gate needs owned temporary projections and real readback/video for each
supported firearm and stance, without inventing a network action schema first.
No installed runtime, saves, controls, settings, release or package changed.
