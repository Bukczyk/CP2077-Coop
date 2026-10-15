# Offline player action preparation

Experiment only. The separate opt-in `init.lua` now registers local fixture
callbacks, but loading it does not spawn an actor. There is no transport, default
package inclusion or game installation. The production runtime does not require
these Lua modules or load these REDscript hooks. Work branch:
`feat/player-action-preparation`; original boundary base:
`b1f054ed67c0bb03f1b8e290c2b5fd62a621307c`.

Follow-up: [`aim_probe.lua` / `aim_probe.reds`](../../docs/validation/PLAYER_AIM_PROBE.md)
provide an explicitly enabled, local logical Aim-state fixture. They do not add
remote ADS support. Its actor-local lease blocks competing stance/equip requests;
pending stance and equipment work must finish before it can acquire the actor.

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

Probe reservation additionally requires a fresh, fully read-back weapon/stance
state with held aim requested. While reserved, staging, unbinding and resetting
that actor fail closed. On clean probe release the old desired state is cleared;
stage a newer serial before using the normal adapter again.

`step` reports `queued`, `observed`, `partial` or `failed`, plus a reason. A queued
command and a changed blackboard are not proof of animation. Equipment reaches
`observed` only when a stable, non-spawning WeaponRight slot contains the attached
item with the requested exact record, or has no item and explicitly reports empty
for holster. An absent object during spawning is pending. Stance readback uses
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

Actor-local equipment command ownership and pending stance flags now also block
probe acquisition. Equipment ownership clears only after confirmed command
retirement. A stance signal has no cancellation handle: its pending flag clears
only when its requested stance is read back, or with exact actor retirement.
Timeout or Lua reset is not proof that a pending engine signal was cancelled.

## Opt-in local action fixture

`init.lua`, `fixture.lua`, `fixture_engine.lua` and `fixture_hooks.reds` provide
an explicit local test of the existing `actions.lua` and `aim_probe.lua`. They do
not replace those modules, adopt ambient actors, or create a multiplayer session.
One activation owns one temporary `Character.Judy` NPC. This local test bound is
not a multiplayer capacity limit. The NPC's ordinary AI remains active and may
compete with presentation requests; it is not a passive NetworkHumanoid.

Future authorized manual staging uses a dedicated CET mod folder named
`PlayerActionFixture` containing these five Lua files from the same revision:

```text
PlayerActionFixture/
  init.lua
  fixture.lua
  fixture_engine.lua
  actions.lua
  aim_probe.lua
```

Keep `fixture_hooks.reds`, `action_hooks.reds` and `aim_probe.reds` together in a
separate experimental REDscript folder. The matched session `remote.reds`
supplies `CP2077Session_PoseReady`; use the existing matched session scripts, not
a second duplicate definition. Codeware's DynamicEntitySystem is required.
Do not copy only the entrypoint or mix helper revisions. CET resolves literal
mod-local filenames here, with no `package.path` or external-mod fallback.
Nothing in this source task installs or launches these files.

When a future game test is authorized, load a save and choose a clear world
position 3-8 meters from V, within two meters vertically. Coordinates are supplied
explicitly, not inferred as safe ground by this fixture:

```lua
local f = GetMod("PlayerActionFixture")
local generation, reason = f.start({x = chosenX, y = chosenY, z = chosenZ, yaw = 0})
f.status()                    -- wait for phase="ready"
f.capture(generation)         -- begin fresh local weapon/stance follow
f.aim(generation)             -- explicit bounded local Aim/Normal experiment
f.status()                    -- inspect copied evidence and reason
f.stop()                      -- wait for phase="retired" before hot reload/exit
```

All five public calls are engine-free. `start`, `capture`, `aim` and `stop` queue
bounded work for `onUpdate`; `status` returns copied cached evidence. `capture`
starts automatic fresh sampling at no more than one sample per 0.25 effective
seconds. Explicit capture/Aim requests may sample sooner; repeated requests
coalesce to one current sample per update.
Each sample calls the existing native capture boundary. It does not refresh old
copied state to defeat the controller's freshness deadline. Unsupported or failed
captures stop progress explicitly and require cleanup before another activation.

`aim` takes a fresh actual weapon/stance capture, then changes only its local
test intent to aiming=true. Status labels this `injected_local_aim`; it is not a
claim that V physically held aim or that remote ADS exists. The unchanged action
controller must first read back the requested weapon/stance before the unchanged
probe acquires its lease. Follow pauses for that entire lease. After observed
Aim, bounded hold, observed stable Normal and lease release, follow resumes from
a new actual local capture. Changing V's weapon during the probe cannot issue a
competing equipment request. Hold a supported drawn firearm before requesting
the experiment. No input bindings or controls are changed.

Loaded, attached, unpaused context must be explicitly confirmed. Unknown pause,
pregame, throwing lookups, invalid frame delta and unavailable actor observation
freeze work and invalidate retirement qualification. The fixture pins the
original player reference and opaque ID, original creating dynamic system, exact
token and first completed actor. Native reference comparisons accept fresh CET
wrappers but quarantine a different actor with the same ID. The original player
must remain available for action and cleanup work; switching saves/players does
not silently transfer this ownership.

Stop first drains a pending Aim request into Normal and releases supported
command work. If equip/probe cancellation is uncertain, status explicitly names
`unreleased_action_exact_retirement` or `uncertain_probe_exact_retirement`.
Those unchanged module guards stay intact: their ownership is retained while
the exact disposable actor is retired. Two distinct completed attachment
observations are required before one exact `DeleteEntity` attempt. A pending
creation is never deleted. Acceptance, exception, false return, elapsed time or
empty tags alone never prove removal. The original manager must report all
three lifecycle flags false, both exact lookups absent, and the retained actor
detached for a new uninterrupted 0.25-second observation interval. Only then may
the fixture discard uncertain controller/probe handles and allow a new start.
If a previously confirmed completed actor disappears externally, the same fresh
absence qualification can close ownership without sending a deletion request.
An actor returning during qualification cancels that provisional route and must
drain normal cleanup again. A rejected preparation that never called CreateEntity
can close immediately on its next valid update, without requiring the old player
context. Neither exception releases an unknown/pending native creation.

An unknown creation token, foreign native identity, unavailable original creator
or unconfirmed removal remains owned. There is no automatic replacement, retry
after ambiguous deletion, tag-wide deletion or ambient cleanup. The fixed tag
blocks a new activation when an earlier fixture remains, including pending
creation. It does not recover an old Lua handle or authorize deleting it.
`onShutdown` only closes admission and queues stop; CET may provide no further
updates after unload. **Stop and observe `retired` before hot reload or removing
the fixture.** Shutdown is not a cleanup confirmation.

`actions.status="observed"` means engine weapon-slot/stance readback;
`probe.logicalAimObserved` means a logical upper-body state. Neither proves
visible weapon, grip, sight alignment or animation. `visualQualified` remains
false. Full validation and remaining live gates are recorded in
[`PLAYER_PRESENTATION_FIXTURE.md`](../../docs/validation/PLAYER_PRESENTATION_FIXTURE.md).

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

The [weapon-readiness follow-up](../../docs/validation/PLAYER_WEAPON_READINESS_2026-10-15.md)
adds exact held-item identity, attachment/slot readiness and timestamped appearance
and muzzle samples to `inspect().weaponEvidence`. These local diagnostic values
are not a network descriptor or proof of rendered weapon grip/ADS. Aim leases now
pin the exact weapon EntityID as well as its record; a same-model replacement
cannot inherit an existing lease. The fixture must keep both updated REDscript
files and both Lua modules matched. No normal package includes them.

2026-10-15 follow-up: [late action readback validation](../../docs/validation/PLAYER_ACTION_DEADLINE_2026-10-15.md)
fixes matching weapon/stance readback incorrectly hiding an admitted deadline
miss. All 279 focused action/probe checks and 29 branch CTests pass. This changes
only local Lua preparation; the visual and connected-state gates above stay open.
