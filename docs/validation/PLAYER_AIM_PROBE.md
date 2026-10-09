# Local logical Aim-state preparation

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-09. Branch:
`feat/player-action-preparation`, follow-up to `bba7ecee9c75f2056a399b9f885cdf53c8706a42`.
No protocol, server, native session declaration, installed runtime, controls,
settings or saves changed. No game was launched or live test performed.

## Candidate comparison from installed primary sources

The source root inspected is
`G:\SteamLibrary\steamapps\common\Cyberpunk 2077 - Baseline\tools\redmod\scripts`.
These are the local installed REDmod scripts, not assumptions about online API
names. The current matched game cache/Codeware also compile every new hook.

| Candidate | Source and observed implementation | Decision |
| --- | --- | --- |
| `NPCPuppet.ChangeUpperBodyState(actor, Aim)` | `cyberpunk/NPC/NPCPuppet.script:1335-1358` sends an `NPCStateChangeSignal`; `npcStateComponent.script:278-287,360-366,752-758` updates native replicated upper-body state, animation feature and blackboard | Use only for the bounded opt-in logical-state probe |
| `AIAimAtTargetCommand` | `core/ai/aiCommand.script:604-608` has target references/duration; `cyberpunk/ai/commands/aiAimWithWeaponCommand.script:60-83` calls `SetCommandCombatTarget` | Reject for passive presentation |
| Combat-target helper | `core/ai/actions/aiActionHelper.script:295-315` changes puppet target attitude to hostile and injects a threat; cleanup at `318-336` does not show attitude restoration | It is not a cosmetic aiming setter |
| `AIInjectLookatTargetCommand` | Installed command targets look-at state | It does not establish weapon grip, sights or ADS |
| `AIEquipCommand` | Slot/item command with no aim field in the inspected delegate | Keep for bounded equipment work only |
| `AnimFeature_Aim` | Native feature exists, but inspected sources did not substantiate an NPC feature name, compatible graph or usable result readback | Do not guess animation calls |

`GetUpperBodyStateFromBlackboard()` is public at
`cyberpunk/puppet/scriptedPuppet.script:1493-1495`. The state component maps Aim
to animation-state value 1 and Normal to 6 at `792-803`, but those values are not
proof of a visible pose or proper sight direction. The component's
`OnUpperBodyStateChanged`, `817-820`, also clears defensive/parry state. Therefore
the experiment accepts only Normal and only an exclusively owned disposable
projection. It does not attempt to snapshot and restore arbitrary combat state.

The public `OnNPCStateChangeSignalReceived` component receiver is another
source-backed dispatch point. This preparation keeps the stock signal setter,
making its asynchronous nature explicit rather than claiming a stronger delivery
guarantee. Directly setting the replicated enum alone would omit the scripted
animation-feature/blackboard path.

Source fingerprints are retained in local evidence:
`D:\Downloads\syncfix\bench-artifacts\20261009-player-actions\aim-primary-source-hashes.json`.
Key SHA-256 values:

- `NPCPuppet.script`: `3b6a43896cfbfe6cd53c3be1ac508a1f19301d1c3ea9b5851ac2cf92254f6175`
- `npcStateComponent.script`: `7a2937ea9ba50aa22b45f64531c5545c8080b348d0b28950b4f7ca05c1dafd19`
- `aiActionHelper.script`: `5094616e10e7b1f0d40442315a4db8fdf3072ba798c749ffae584a075d3ef1a0`

## Implemented fixture boundary

`experiments/player-presentation/aim_probe.lua` is a runnable opt-in fixture module.
It is not loaded or ticked by the shipped runtime. `aim_probe.reds` supplies a
unique actor-local lease and guarded acquire/read/request/release hooks.
`actions.lua` supplies the existing exact scope/entity/actor mapping, fresh held
weapon/stance readback and a local reservation that blocks stage/unbind/reset.

The hook accepts only attached, live, AI-ready NPCs with a supported exact held
firearm, initial Normal state and no pending presentation equipment/stance work.
An actor-local lease excludes another fixture controller even when it has a
separate Actions instance or a different CET wrapper for the same EntityID.
The action hooks reject stance/equip mutations while that lease is held. Existing
equipment commands must be retired before acquisition. A queued stance signal
has no cancellation handle; its actor-local pending flag survives until the
requested stance is read back or that exact actor is retired. No timed-out request
or Lua reset silently clears this uncertainty.

The probe submits Aim once, waits for logical Aim, holds for one active second,
submits Normal once, and requires 0.25 active seconds of sampled Normal readback
before releasing ownership. Default enter/restore deadlines are one active second
each. Configured deadlines are 0.1..2 seconds, hold 0..2 seconds and stability
0.1..0.5 seconds strictly below the deadline. A missed deadline is recorded as
failure even if late readback permits safe cleanup. Observed pauses do not spend
these bounds. Caller-supplied ticks are required; there is no background watchdog.

An early stop while Aim is pending waits for Aim readback first. The stock setter
skips requests equal to the current state, so requesting Normal while the queued
Aim is still pending cannot prove cancellation. If Aim never arrives, the probe
retains ownership and reports exact retirement required. A changed identity,
missing/detached actor, different held weapon or competing upper-body state fails
without forcing Normal. Do not hot-reload away this state; retain the fixture and
retire only the exact owned actor through its verified lifecycle before discarding
an uncertain lease. The fixture itself never deletes or spawns actors.

A known lease rejection is different: it releases only its own Actions reservation
and never asks to retire another controller's actor. Acquisition/submission
exceptions may have mutated native state, so retain the reservation and report
uncertainty. `inspect()` separates native `cleanupConfirmed`, `reservationHeld`
and `retirementRequired`. A failed local reservation release after confirmed native
cleanup does not request actor retirement.

The engine can still change NPC state outside these experiment hooks. The lease
coordinates these adapters only; it does not prove the actor is passive or disable
AI. The probe rejects observed competing states, but a same-enum change from
unrelated engine logic has no causal request ID. Logical evidence is not a claim
of exclusive control over every engine behavior.

## Opt-in usage for a future authorized local test

After separately preparing the experimental scripts, pass the same owned-actor
resolver used by an existing Actions controller. First stage/bind/step that
controller until it returns `partial / ads_unavailable` for a fresh desired state
with `aiming=true`, drawn supported weapon and observed stance. Do not substitute
an ambient actor, an arbitrary nearby NPC or the real player. The fixture does not
create, equip or discover a target on its own.

```lua
local Probe = require("aim_probe") -- explicitly add the experiment directory
local probe = assert(Probe.new({
    enabled = true,
    actions = actionController,
    resolve = resolveOwnedProjection,
    timeout = 1, hold = 1, settle = 0.25
}))
assert(probe:start(scopeToken, opaqueEntityKey, monotonicSeconds))

-- Call on each game-thread fixture update, with the actual pause state:
local status, reason = probe:step(monotonicSeconds, worldPaused)
local evidence = probe:inspect()
-- Retain/log evidence.localKey, phase, activeSeconds, logicalAimObserved,
-- cleanupConfirmed, reservationHeld, retirementRequired and visual.

-- Optional bounded early stop. Keep ticking until complete or explicit failure:
probe:stop()
```

`logicalAimObserved=true` records only the NPC blackboard reading Aim.
`visual` is always `unverified`; the fixture cannot mark its own animation passed.
Successful completion means an observed logical Aim-to-Normal cycle and released
lease. The normal action adapter still reports ADS unavailable, and clean release
clears its old desired state so a newer serial must be staged. This supplies no
remote aim yaw/pitch, camera target, sight alignment, muzzle direction, recoil,
shot, reload, appearance data or multiplayer action contract.

## Validation and handoff

- PASS: 198 mocked action/probe checks. Includes three independent actors,
  wrapper churn, duplicate-controller lease rejection, competing equipment/stance,
  early stop, pause, delayed/missing signals, late cleanup, state/identity conflict,
  failed local reservation release and exceptions after possible acquisition.
- PASS: final full offline CTest run, 29/29 tests in `build/offline-actions`
  using the existing Windows Release core/server/test build. Native/runtime
  sources are unchanged by this follow-up.
- PASS: isolated compilation includes both `action_hooks.reds` and `aim_probe.reds`
  with matched session scripts, Test B vanilla cache and Codeware. Final hook
  compile at 2026-10-09T05:01:23Z, input hashes unchanged. Evidence:
  `D:\Downloads\syncfix\bench-artifacts\20261009-player-actions\compile-20261009T050122567173Z.json`
  and matching `.log`.
- PASS: independent read-only review reproduced 194 checks before the added
  acquire-exception regression and found the three reported ownership/deadline
  blockers addressed. Final targeted checks also include that regression.
- NOT RUN: live logical signals, visible weapon grip/posture/ADS, two-window or
  two-PC action synchronization. Historical visual failure is not overwritten.

Owned files: experimental action/probe Lua and REDscript, experiment README,
`tests/player_actions_tests.lua`, player presentation contract and this note.
Bukczyk retains protocol/shared/native session/backend routing and recovery.
No wire field/kind was added; GameplaySubmit still lacks an agreed player action
and appearance schema. No release, game deployment or package refresh occurred.
