# Local vehicle and seat fixture

**Source-only experiment. Disabled by default, not installed, not live tested.**
Nothing in `runtime/session` loads this folder. The published movement experiment
and installed games remain unchanged. Live testing is deferred until KyleBuildsAI
resumes it. This fixture does not synchronize cars over the network.

KyleBuildsAI owns this folder and `tests/vehicle_*_tests.lua`. Bukczyk retains
network/session/authority ownership. Starting revision: upstream main
`e19ffb3286efec750b8729487220becf6569ab7b`. The vehicle observation fixture is
`15045bc77567719458110e12c74e5e88d0bd0e7e`; this independent follow-up branch is
`feat/vehicle-pose-application`. No published gameplay package is changed.

## What the fixture prepares

- One explicitly owned, nonpersistent base-game Hella:
  `Vehicle.v_standard2_archer_hella_player`.
- The exact default appearance returned by that record. Empty/unknown default
  appearance is rejected. The observed appearance must match. The supported color
  variant is exactly `None`; other variants are unsupported, with no fallback.
- Full normalized quaternion at spawn and actual quaternion/position readback.
  Both quaternion signs represent the same orientation. Readiness requires stable
  attachment plus <=0.5 m and <=5 degrees initial placement error.
- Exact EntityID retained from `CreateEntity`, kept as an opaque decimal string
  outside the engine. The creating player's exact ID is pinned before creation,
  including before first attachment. No nearest-car lookup, model-index identity
  or tag-wide delete.
- Actual car-origin velocity, record, appearance, color variant, seat existence,
  vehicle occupant relationships, local player mount parent/child/slot, and vehicle
  camera manager perspectives. Camera values are observations, not proof of a
  restored player camera. **Every reported result has `cameraVerified=false`.**
- Manual enter/exit observation and separately enabled injected mount/unmount
  requests for the local player. There is no control rebinding or automatic action.
- Exact parent/child/slot queries on both sides of a relationship plus a matching
  finished-mounting callback before a request is marked observed. A submitted
  request, callback alone, or occupancy alone never completes it.
- Finished events are peeked and acknowledged only after a whole valid sample.
  Camera/readback failure does not discard them. A bounded exact receipt history
  tolerates failed acknowledgements without replaying an observed result.
- Five unpaused seconds before an unresolved request is quarantined. Its owner is
  retained; no automatic retry or seat reuse occurs. A later matching event and
  relationship can reconcile it and are logged as late.
- Deferred exact cleanup. Pending spawn is never deleted. Cleanup requires an
  explicitly completed spawn (`IsSpawned`, not `IsSpawning`) and waits for stable
  attachment, no pending request, no occupants, local player on foot, low speed,
  and a second engine-side check immediately before `DeleteEntity`.
- Successful deletion requires both lookup paths absent, management/spawn flags
  clear, and the retained exact handle detached, continuously for 0.25 unpaused
  seconds. An accepted delete or empty tags do not establish disappearance.
- A separately enabled, bounded unoccupied-car pose probe, using the vanilla
  whole-vehicle teleport route with the complete quaternion converted to three-axis
  Euler orientation. Submission is separate from actual pose/low-speed readback.
  It is a hook experiment, not continuous movement or physics synchronization.

The fixture can own one car per activation; this is a test boundary, not a
multiplayer capacity limit. State is local and no SessionEntityId is fabricated.
Callbacks on unrelated vehicles preserve their original behavior and record
nothing unless this fixture explicitly enabled its owned car.

## Future local test setup, only after live testing is authorized

Stage `engine_hooks.reds` with the matched session REDscript and Codeware 1.18.0.
Stage `init.lua`, `fixture.lua`, `movement.lua` and `engine.lua` together in a separate CET mod
folder named `zz_VehicleSeatFixture`. Do not add these files to the default runtime
or the currently published movement ZIPs. No automatic installer is included.

Start in safe free roam, on foot, with a clear road surface 6-15 metres away and
within 3 metres vertically. The caller supplies that clear point explicitly;
this fixture does not infer collision clearance or safe terrain. Obtain actual
coordinates and orientation before supplying the table below. Do not use arbitrary
sample coordinates or start in a quest scene, combat, traffic or a live session.

```lua
-- target = {x=<observed>, y=<observed>, z=<observed>,
--           qx=<observed>, qy=<observed>, qz=<observed>, qw=<observed>}
GetMod("zz_VehicleSeatFixture").start(target)
GetMod("zz_VehicleSeatFixture").status()
-- First use ordinary manual enter/exit, observing logs and both camera modes.
-- Only the separate request experiment needs the next call:
GetMod("zz_VehicleSeatFixture").enableRequests(true)
GetMod("zz_VehicleSeatFixture").request("mount", "seat_front_right")
GetMod("zz_VehicleSeatFixture").request("unmount", "seat_front_right")
GetMod("zz_VehicleSeatFixture").stop()
```

`start` and request success mean submission only. Poll status and evidence.
`stop` disables new requests but cannot cancel an unresolved native mount safely.
It retains an occupied or uncertain car. If a timed-out request completes late,
observe reconciliation, then leave the car manually before cleanup proceeds.
Wait for `closed` and visually confirm disappearance before another activation.

Do not hot reload, unload the save, or close the game with a fixture still owned.
Shutdown cannot observe asynchronous removal, so it deliberately never deletes
and reports unfinished ownership. After an unexpected reload, a surviving fixture
tag blocks another spawn. The fixture does not adopt/delete historical orphans.
No settings, controls, connections or saves are restored or modified by the code.

The log uses a 10 Hz observation cadence, up to 9000 records or approximately
8 MiB, plus one limit notice. After the cap, observation and safe cleanup continue.
This is not an unattended long-running session recorder.

## Optional unoccupied movement probe

Do this only after the parked-car observation gate passes, in a clear local test
area. Keep seat request injection disabled. Ordinary manual entry must also stay
off during a pending move. Any occupant or uncertain observation quarantines the
request and holds cleanup. Never use it on a player/NPC/traffic car.

```lua
local probe = GetMod("zz_VehicleSeatFixture")
local generation = probe.status().generation
probe.enableMovement(true)
-- moved = a full normalized pose, derived from the actual parked-car readback.
-- Choose a clear translation of 0.1-0.5 m or rotation of 2-10 degrees.
probe.move(moved, generation)
probe.status() -- queued/pending is NOT proof the car moved
probe.enableMovement(false)
probe.stop() -- pending/unknown outcome holds the exact car until reconciled
```

The exact car ID, creating player's ID and activation generation must match.
The car must be fully spawned, attached, still managed, empty, and below 0.2 m/s;
the creator must be on foot. Actual model/appearance/color must match the supported
descriptor. These checks occur in Lua and immediately before the native call.
The adapter independently rechecks pause at submission, including pause-query
failure. No keys or automatic movement loop are registered.

Each activation allows at most 16 explicit commands, one pending at a time, within
2 m, 0.25 m vertically and 30 degrees of its origin. Each command is at most
0.5 m/10 degrees. Requests below both 0.1 m and 2 degrees are rejected so an
unchanged pose cannot be mistaken for a result. Origin bounds are checked against
the requested spawn pose in Lua and the actual first-application pose natively.

The probe observes position error <=0.025 m, full quaternion error <=0.5 degrees
and the same safe empty/low-speed conditions continuously for 0.25 unpaused
seconds. The two-second deadline and stable interval pause with the game. Unknown
readback or deadline expiry latches a fault, retains the pending command, stops new
movement and blocks deletion. There is no retry. A later valid observed target can
release cleanup, recorded as `observed_after_fault`; it does not clear the fault
or re-enable movement. Successful observations still report
`movementQualified=false` and `cameraVerified=false`.

`stop` disables both experiments immediately but defers car retirement until any
submitted movement has an observed result. Invalid clocks are handled the same
way as unknown readback. After observed movement, future placement qualification
uses the actual observed pose. Accepted application, timeout, mode disable and
shutdown never stand in for completion.

## Known limits and remaining gates

Not implemented: network vehicle adoption/binding, driving authority/seat grants,
connected pose application, driver transfer, moving passengers, collision/damage
agreement, arbitrary vehicles/custom paints, camera restoration or vehicle AI
suppression. The fixture does not freeze a chassis or teleport an occupied car.
Vanilla mounting calls are compiled candidates, not verified injected gameplay.
Default Hella appearance availability and actual seating/camera behavior still
need a live test. A strict unsupported result is preferable to a visually wrong car.

Next live gates: confirm initial model/appearance/rotation and persistence while
parked; ten driver cycles and ten supported passenger cycles; occupied-seat and
interrupted/late transitions; exact cleanup including retained-handle absence;
video of first-person/third-person entry and exit. Then run bounded unoccupied
translation, pitch/roll/yaw, stop, pause and failure readback tests, checking
collisions and physics settling visually. Moving-passenger tests remain a later
implementation step. Two-PC shared rides require a separate
agreed backend route and matched game/server acceptance test.

Next source task, still KyleBuildsAI-owned: use evidence from the bounded probe to
decide whether continuous exact-car application needs a different native route
in `engine_hooks.reds`/`engine.lua`. Do not turn repeated teleports into a presumed
vehicle motor. Occupied-car/passenger/camera work requires separate verified hooks
and tests. This slice prepares an application/readback candidate; its physics and
visual behavior remain unqualified and no connected vehicle feature is complete.

## Existing engine declarations used

The local reconstructed 2.31 corpus at revision
`a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a` provides:

- `core/entity/entity.swift`: actual appearance, color variant, position/quaternion.
- `core/gameplay/vehicles.swift`: record, camera manager and linear velocity.
- `core/components/scriptComponents/vehicleComponent.swift`: exact seat presence,
  occupancy, and the finished-mount callback. Its `IsDriverSlot` uses substring
  matching, so this fixture instead requires exact known seat names.
- `orphans.swift`: `IMountingFacility`, `MountingInfo`, `MountingRequest`,
  `UnmountingRequest`, finished event and camera perspective declarations.
- `core/gameplay/psmImports.swift`: `MountEventData`.
- `orphans.swift:31933`: `TeleportationFacility.Teleport(GameObject, Vector4,
  EulerAngles)`, returning Void; quaternion conversion and normalization are also
  declared in this corpus.
- `cyberpunk/player/psm/vehicleTransition.swift:994`: vanilla whole-vehicle teleport
  during an exit escape path uses the vehicle and full world quaternion converted
  to Euler angles. This verifies an existing whole-vehicle operation, not suitability
  for continuous multiplayer movement.

`PhysicalBodyInterface.SetTransform`/`ToggleKinematic` were inspected but not used:
their application to the full vehicle chassis and passenger behavior is unverified.
No raw per-body writes, velocity forcing or persistent kinematic changes are made.

Codeware 1.18.0's packaged `Codeware.Global.reds` supplies `DynamicEntitySpec` and
exact dynamic entity creation/status/deletion. Declarations were checked by
isolated compilation against the installed game cache. This is compiler evidence,
not evidence that the engine completes these operations as intended.

## Backend boundary to agree later

Protocol v5 already names `VehicleState` and carries a three-axis Euler transform.
The inspected `SessionBridge::Frame` has player/NPC render collections and no
vehicle engine collection. The old relay vehicle authority proposal is not an
accepted typed contract and is not used here.

For a connected vehicle slice, agree stable vehicle identity and generation,
supported record/appearance/color, accepted pose, per-player seats, driver ownership
and recovery baseline. Entry/exit intent must reach the HOST; authoritative grants,
denials and actual observed results must return reliably and survive duplicate
delivery. Newest accepted pose replaces older pose without replaying entry events.
An engine event/relationship observation triggers the result; a queued native call
does not. These are behavioral requirements for joint review, not new packet names,
IDs or transport choices. Local fixture work can proceed independently.

See [VALIDATION.md](VALIDATION.md) for this source checkpoint's tests.
