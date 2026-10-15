# Local player action fixture

UTC checkpoint: 2026-10-15. Owner: KyleBuildsAI. Source-only follow-up to PR16
`75a7a211da8775158a5c6d8f43bb137554dce0dc`. Bukczyk retains shared networking and
session ownership. No protocol/backend, production activation, package, installed
file, game process, save or binding changed.

## Scope and evidence boundary

Eight scoped paths add a queued local fixture, native exact-reference checks,
actual-entrypoint tests and documentation. Existing `actions.lua`, `aim_probe.lua`,
`action_hooks.reds` and `aim_probe.reds` are unchanged. This fixture is one
disposable local NPC per activation, not a two-player protocol or capacity limit.

The entrypoint uses literal same-folder CET module loading and calls the actual
existing controller/probe. It queues explicit start, fresh follow, injected local
Aim and stop requests. All engine access occurs inside `onUpdate`. Status is a
copy of cached evidence. No ambient adoption, fake SessionEntityId, tag deletion,
physical input automation, inventory removal or automatic respawn is introduced.

The creating DynamicEntitySystem is retained before the native create call.
Source-supported `Character.Judy`, opaque EntityID, first exact completed native
actor and original native player/ID are pinned. Fresh wrappers are accepted by
native reference comparisons. Context/lifecycle checks run again before each
forwarded existing controller/probe call, not only at initial activation. Final
create preflight rejects context changes during position/spec preparation before
claiming a native creation attempt.

The same effective observation-qualified clock is used for active presentation
and normal stop/drain. Retirement uses a separate qualified observation clock.
Unknown pause/context/actor data and invalid delta invalidate timing intervals;
they cannot spend a skipped interval against an Aim timeout or prove absence.
Automatic fresh follow samples are produced at a maximum 4 Hz effective cadence;
explicit capture/Aim requests may sample sooner and coalesce per update. A real
capture failure never refreshes stale copied data. Follow stops during a probe
lease and resumes from a new capture after stable Normal/release.

`injected_local_aim` is an explicit test intent over a freshly observed supported
weapon/stance. It does not report observed physical aiming, network input or ADS.
The original action/probe readback, ownership, inventory bounds and failure
semantics remain unchanged.

## Retirement contract

Normal stop drains Aim before requesting Normal; confirmed lease/command cleanup
precedes retirement. Existing modules explicitly permit exact actor retirement
for uncertain equip/probe outcomes. That failure route is visible in status and
keeps module ownership until actor removal is observed. No module reset bypasses
its release guards.

Codeware 1.18.0 can complete CreateStub callbacks after an early DeleteEntity has
forgotten the token. This fixture never deletes an unobserved pending creation.
It requires two distinct positive-delta ready observations from the retained
creator and exact native actor before one removal attempt. After that attempt,
manager readiness and explicit false managed/spawning/spawned flags, absent
world/population lookups and detached retained handle must all stay observed for
0.25 unpaused seconds. An ambiguous native return does not trigger a second
attempt. Unknown or foreign identity remains held. Original-player replacement
also blocks further action/cleanup rather than transferring the fixture to a
different loaded world.

A previously confirmed creator-owned completed actor may disappear externally.
The same fresh coherent absence interval can then release its retained modules
without issuing DeleteEntity. Any returning lookup/attachment breaks that
interval and clears the provisional route; a returned ready actor drains normal
Aim/command cleanup. Never-ready creation still stays held. A preparation that
definitely never invoked CreateEntity can close on queued stop without demanding
a now-replaced original player. These two cases were independently reproduced
against intermediate fixture source and corrected before this checkpoint.

Shutdown only queues stop and closes admission. It cannot guarantee future
updates or cleanup after Lua unload. The manual gate is `stop()` followed by
observed `phase="retired"` before hot reload or removal. A tag collision blocks
another spawn, but cannot reconstruct or delete previously lost ownership.

## Offline validation

Evidence directory:
`D:\Downloads\syncfix\bench-artifacts\20261015-player-action-fixture`.

- `focused-validation.json`: existing action/probe suite 328 checks in each
  runtime; actual new fixture suite 432 Lua 5.4 / 442 LuaJIT checks. The LuaJIT
  branch additionally uses real Uint64 cdata above 2^53. Both pass.
- New fixture checks load the actual entrypoint, engine adapter, action controller
  and probe with a literal local loader and no `package` library. Only native
  observations/mutations are mocked. Covered draw/switch/holster/crouch, copied
  status, coalescing, stale generations, explicit Aim/Normal, >5-second fresh
  follow, failure without stale refresh, changing local state during Aim,
  pause/unknown context/delta, late spawn, malformed lifecycle, retained actor,
  original creator replacement, fresh wrappers, same-ID foreign actors/players,
  mutation between stance and equip, failed/uncertain cleanup and fresh absence.
- `compile-20261015T123443835183Z.json` and `.log`: matched three player experiment
  helpers plus session scripts compile against private copies of the installed
  Cyberpunk 2.31 cache/compiler and Codeware. All compiler, installed and source
  input hashes remained unchanged. This verifies signatures, not native behavior.
- `branch-validation.json` and `branch-{configure,build,ctest}.log`: fresh
  configure, incremental Windows Release and 30/30 CTests pass with all prior
  29 registrations retained plus the new fixture. Existing configured generator
  is Visual Studio 17 2022, x64, session server ON, plugin OFF. This branch check
  does not claim a new native plugin build. All executable source/test hashes
  stayed unchanged during validation. Exact commands are saved in the JSON.
- Independent review: 14 actual-entrypoint scenarios / 39 additional assertions
  per runtime pass, including original creator/wrapper changes, interrupted
  external absence, definitely rejected creation, fresh follow and Aim cleanup.
  Evidence: `independent-entrypoint-20261015T123913942382Z.json` and
  `independent-final-focused-20261015T123937015649Z.json`. The independent reviewer
  also reran both focused suites and verified matching helper/input hashes.
- Eight scoped files are frozen in `frozen-source-manifest.json` for parent
  publication review. No hosted-CI or live success is claimed here.

## Remaining live gates

No game was launched or controlled for this work. Mocked command/readback tests
and isolated compilation cannot prove visible weapon/stance/ADS, grip or muzzle
alignment, NPC competing AI behavior, actual dynamic spawn/retirement timing,
inventory behavior or native Aim event delivery. `visualQualified=false` remains
fixed. A future authorized manual test needs the matched Lua/REDscript files,
loaded save, clear explicit pose, observed exact retirement and captured logs.
Connected player presentation remains dependent on an agreed shared contract;
this fixture does not send or receive network state.
