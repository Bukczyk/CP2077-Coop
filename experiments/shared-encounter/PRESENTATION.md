# Passive encounter presentation experiment

This is an opt-in game-side candidate. It is separate from the PR9 idle archive
and does not implement combat packets, authority decisions, physical collision,
HOST damage, or a playable shared-combat release. Offline checks passed. The fifth
local trial visibly demonstrated a held reaction pose, return to idle, and death
preserved through two local recreations with fresh exact IDs. The earlier crashes
remain recorded below. Trial nine also recorded three real firing callbacks
whose geometric rays hit the exact corrected capsule, including after local
recreation, and an upward-shot miss. Timed reaction playback, native bullet
damage and the complete shared-combat path remain open.

## Design

The entity remains `entEntity`. Its only components are `entAnimatedComponent`,
`entSkinnedMeshComponent`, and one `entAnimationControllerComponent` named
`CP2077Coop_EncounterController`. The animated component binds to that controller.
There is no NPCPuppet, AI, navigation, hit/damage component, action database,
ragdoll, or physics simulation. The controller is an animation-input receiver.

An authored graph selects idle, reaction, or death. Idle uses the previous
`idle_stand` clip. Reaction and death use `animAnimNode_SkFrameAnim` with explicit
normalized progress. An accepted death can therefore request its terminal sample
again after recreation, rather than replaying a death from frame zero. This is
the intended mechanism; serialization alone does not verify engine sampling.

All clips disable root motion and animation-event collection. The existing
entity-transform adapter remains responsible for location and orientation.
No vanilla mesh, skeleton or animation bytes are bundled. These are references
to the installed game, with the same `woman_base.rig` as the Judy proxy:

| Use | Installed animation set suffix | Clip | Duration |
| --- | --- | --- | --- |
| Idle | `wa_gang_unarmed_locomotion_combat.anims` | `idle_stand` | 4.9000001 s |
| Reaction | `wa_gang_unarmed_reaction_ranged_impact.anims` | `impact_stand_front_torso_l` | 0.466666669 s |
| Death | `wa_gang_unarmed_reaction_ranged_death.anims` | `death_front_torso_l_idle` | 1.93333328 s |

All sets are under
`base\animations\npc\gameplay\woman_average\gang\unarmed\`.
The two reaction clips are recorded as animation type `Normal`. These fixed
illustrative clips do not reproduce the HOST's exact directional reaction,
ragdoll, body type, dismemberment, or final bone pose. The misleading word `idle`
in the death clip name is an installed asset name, not a claim that the clip is a
constant dead pose. Terminal corpse appearance and local recreation were viewed
in trial five. Network reconnect and arbitrary appearance remain separate gates.

## Small game-side API

The separate state controller must verify the current session scope, exact
session/local entity binding, accepted event ordering, and terminal-death rule
before it calls this adapter. This module does not choose or validate an NPC.

```lua
local presentation = require("presentation")
-- Use only the exact projection returned by the managed spawn and binding.
local ok, status = presentation.apply(entity, "reaction", 0.5)
-- status == "queued_not_observed" only means QueueEvent returned without error.
-- Returning from QueueEvent does not establish that the graph consumed it.
presentation.apply(entity, "idle", 0) -- explicit end of a nonlethal reaction
presentation.apply(entity, "death", 1) -- terminal sample, including recreation
```

`progress` is finite normalized progress in `[0,1]`, not seconds. `hit` is an
alias of `reaction`. Use `clipDuration.reaction` and `clipDuration.death` for local
playback timing. Repeated same-state samples do not request one-shot restarts.
The state controller, not this low-level adapter, must keep stale reaction or
idle requests from reviving an accepted dead entity.

The exact native path is `Entity.QueueEvent(ref<Event>)` with
`entAnimInputSetterFloat.key` and `.value`. `AnimInputSetterFloat` is the
REDscript alias; CET `NewObject` requires the native RTTI name
`NewObject("entAnimInputSetterFloat")`. It queues progress before phase:

| Input | Values |
| --- | --- |
| `cp_coop_phase` | 0 idle, 1 reaction, 2 death |
| `cp_coop_hit_progress` | 0 to 1 |
| `cp_coop_death_progress` | 0 to 1 |

The phase uses a three-input `animAnimNode_Switch`, with zero blend time for an
unambiguous first experiment. The two progress inputs drive their respective
`SkFrameAnim.progressLink`. This is a discrete presentation fixture, not polished
blending. An exception may occur after one event was already queued; the adapter
reports `queue_failed_or_partial`. A successful queue call has no engine receipt.
Do not advance a networking acknowledgement based on this return value.

## Build and offline evidence

Use the already pinned official WolvenKit Console 9.0.1 CLI. From the repository:

```powershell
python scripts/build-passive-encounter-archive.py `
  --entity-json experiments/shared-encounter/assets/raw/base/cp2077coop/entities/cp2077coop_networkhumanoid_encounter.ent.json `
  --graph-json experiments/shared-encounter/assets/raw/base/cp2077coop/animations/networkhumanoid_encounter.animgraph.json `
  --wolvenkit 'D:\Tools\WolvenKit.Console-9.0.1\WolvenKit.CLI.exe' `
  --output-dir artifacts/passive-encounter-rebuild
```

The builder refuses an existing output directory, checks the CLI hash and
passive graph/component contract before and after serialization, packs exactly
two authored resources, and verifies unpacked binary hashes. It never deploys.
The graph validator resolves handle references and checks the actual root/output
path, switch input order and phase variable, separate reaction/death progress
links, initialization list, and absence of competing time/frame links. Node
counts alone are not accepted as evidence of correct wiring.
The entity depot path is
`base\cp2077coop\entities\cp2077coop_networkhumanoid_encounter.ent`.
The archive is named `CP2077Coop_EncounterPresentation.archive`.

At `2026-10-07T03:16:58Z`, build-03 passed source validation, WolvenKit
conversion/roundtrip contract, exact resource listing, and unpacked binary
parity. The local mock check passed input rejection, event ordering, terminal
sample request, explicit idle, and partial queue failure. These are offline
checks only. Two earlier attempts exposed forward JSON-handle references and
shared roundtrip handles; the sources/builder now handle both.

A later validator-only review passed both the authored sources and the existing
build-03 roundtrip. Nine malformed-wiring fixtures were rejected, covering wrong
phase/progress variables, swapped branches, competing time/frame links, bypassed
switch, unresolved handle, and wrong active root. Candidate sources and archive
bytes were not changed or rebuilt. These checks do not prove the native engine's
normalized-progress or switch-selection behavior.

## Failed constructor trial and repair

The second local two-game trial, launcher `20261007-032228-045229`, attempted
presentation with `NewObject("AnimInputSetterFloat")`. The JOINER mod log reports
`Type 'AnimInputSetterFloat' not found.` The adapter returned failure and the
outer state controller recorded `engine_rejected`; this was a constructor
lookup failure, not evidence that the animation graph rejected a valid event.

An active-game snapshot taken from `2026-10-07T03:35:49.970094Z` through
`03:35:50.146190Z` captured 53 files, including installed probes, traces, per-mod
CET logs and launcher records. It contains 4,352 matching type-lookup log lines
and 4,400 JOINER projection `engine_rejected` observations. These are different
logging streams with different write timing, not independent failures or exact
one-to-one counts. No trace lines in this snapshot failed JSON parsing. Files
could continue growing after capture, and on-disk script identity is not proof
of the version already loaded by CET.

The source constructor now uses `entAnimInputSetterFloat`. The persistent
`tests/encounter_presentation_adapter_tests.lua` mock exposes only that native
name and explicitly rejects the old alias. It verifies queue ordering, terminal
sample requests, invalid-input rejection, constructor failure without queueing,
and partial queue failure without success. It and the current presentation
state tests pass. At this snapshot the repair still needed a live retest; the
third trial below supplies subsequent evidence. The archive bytes did not change.

## Third trial: visible local death and recreation crash

The corrected constructor was installed at `2026-10-07T03:37:53Z`. JOINER bound
local entity `10714169` to session entity `4294967296`. Its trace contains 1,118
exact-bound frames without root-position change. The local reaction fixture at
`03:41:50Z` queued five progress samples, then returned to idle about 0.512 s
after staging. Its immediate duplicate was rejected. These queue records do not
qualify visible reaction playback; a held midpoint sample is still required.

A local death fixture was staged at `03:41:57Z`, with its immediate duplicate
rejected. Terminal progress 1 was queued at `03:41:59Z`, about 1.951 s after
staging. The operator separately observed the corpse on the ground at
`03:42:25Z`. This is a visible terminal-pose observation, not a continuous
30-second persistence test or a HOST-authoritative death. Both fixtures were
local commands, not results of physical hits or network combat messages.

At `03:42:29Z`, F10 requested recreation. The harness called `reset()`, received
false while removal remained pending, then called `step()` with the same scope.
The final trace rebound the old entity `10714169` and queued terminal death into
that retiring entity. JOINER exited with an access violation. The crash dump
records a read at `0xC0` in `Cyberpunk2077.exe+0x574FD7`; its exact faulting engine
call is unresolved. The same-tick reuse is a proven lifetime hazard, not proof
that the graph or query capsule caused the exception.

The game-side lifecycle fix latches an unfinished reset even within the same
epoch, marks retirement before unbinding, and completes observed removal before
fresh spawning. The static adapter refuses binding or moving a removing entry.
Regression tests cover a still-visible retiring handle, repeated same-epoch
steps, rejected unbind, and renewed relevance during pending removal. Each of
the old runtime and old adapter fails its corresponding regression; both fixed
versions pass. The complete local CTest run at `03:50Z` passed all 18 tests.
These source checks alone do not prove that the live crash is fixed. Trial five
below separately records two successful live recreations.

## Fourth trial: initial-spawn crash before recovery testing

The retirement guard and staged private harness were installed at
`2026-10-07T03:50:12Z`. After desktop access resumed, JOINER crashed at
`03:55:10Z` during its first projection spawn. The final trace contains one new
local entity `10714234`, still unbound, and no preceding bound projection. No
reaction, death, hold or recreation input had been exercised in this trial.
The operator briefly saw the newly rendered proxy before the exit.

This differs from the third trial's confirmed old-ID rebound. There is not yet
a recorded call boundary locating the new failure among attachment, first
bind/move and first trace-target setup. The tag-membership change and collider
are hypotheses, not established causes. Clearing a null weak trace target had
already run throughout the preceding empty-NPC frames. The fourth trial does
not qualify recreation, collision or presentation stability. Crash analysis and
the next isolated live check remain with the active test owner.

The next candidate materializes the static tagged-entity collection and checks
exact IDs in a bounded loop, avoiding the nested `GetTags`/`ArrayContains` call.
It compiled at `03:58:48Z`. Trial five subsequently ran through this path without
the fourth crash, but the trace-target gate returned false. That is not full
qualification of the gate or proof of the earlier fault's exact caller. The
presentation graph and archive remained unchanged.

Private evidence is under
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine`:
`live-hitbox-recreate-crash/SUMMARY.md`, `metrics.json`, captured traces and dump;
`presentation/retiring-regression/results.json`; and `retiring-fix-install.json`.
The fourth run is preserved in `live-first-bind-tag-crash/snapshot.json`, captured
at `03:59:53Z` with 32 hashed files. JOINER's trace is final; HOST remained open
as PID 58332, so its snapshot is partial. Trial five restarted only JOINER with
the mitigation and diagnostic call boundaries while retaining the HOST/server.
This was a mixed diagnostic setup, not a matched complete-feature qualification.
Final process/restoration records remain with the test owner.

## Fifth trial: local presentation and recreation observed

JOINER process `60052` ran from about `04:01Z` until its deliberate close before
the `04:14:42Z` archive. HOST `58332` remained on the earlier fourth-trial scripts;
its native-hit observer was not scoped. This mixed diagnostic setup validates
the local presentation fixture, not the current HOST damage implementation.
The final JOINER trace spans `04:01:40Z` to `04:14:01Z` without a logged Lua error.

The operator observed a distinct reaction midpoint held with KP1, then KP2
visibly restored idle. The trace records held samples from `04:05:31Z` to
`04:06:15Z`. A separate timed reaction was staged at `04:06:45Z` and returned to
idle at `04:06:46Z`, after 0.548 s; its brief transient was not verified frame by
frame. Death was staged at `04:06:52Z`, reached terminal state at `04:06:54Z`
after 2.064 s, and was visibly observed as a corpse. All were local fixtures,
not accepted HOST combat results.

The same session entity `4294967297` survived two local recreations:

| Rebuild request | Old local ID | Fresh bound local ID | Recorded result |
| --- | --- | --- | --- |
| `04:07:40Z` | `10713756` | `10714375` at `04:07:40Z` | Pending removal returned false, a later tick confirmed completion, then the fresh ID bound in terminal death. |
| `04:08:10Z` | `10714375` | `10714393` at `04:08:11Z` | The same staged retirement sequence completed without rebinding the old ID. |

The two pending-removal waits were 0.110 s and 0.111 s. All 4,832 bound frames
resolved to the exact session entity; their reported position error was zero
against a stationary target. This does not qualify moving-target latency.
The operator visually confirmed the dead pose after both recreations. At
`04:07:59Z`, a reaction request against the first recreated corpse was rejected
as `terminal_death`. When the controlled HOST fixture's lifetime expired at
`04:12:37Z`, JOINER retired its last owned projection and logged an empty owned
list 0.105 s later. This trial qualifies the tested local retirement and
terminal-state restoration sequence; it is not a universal crash-free claim.

The physical target gate returned false in 4,832 bound frames and JOINER fired
zero shots. No collider-hit or network-damage result was established. This run
still used the old zero-mask capsule archive. Later collider-only trials are
recorded in [the physical encounter checkpoint](PHYSICAL_ENCOUNTER_CHECKPOINT.md).
They corrected the exact-ID gate and tested subsequent filters. In trial nine,
scripted center rays at `04:45:25Z` and `04:46:05Z` hit exact local/session IDs
`10717221` / `4294967300`; an offset ray rejected the target and an upward ray
missed. These calls stayed at sequence 0 without real firing, ammunition use,
damage or networking. Later in the same trial, genuine firing callbacks at
`04:54:21Z`, `04:55:39Z` and `04:55:44Z` produced exact-target ray hits, with a
genuine upward-shot miss at `04:55:52Z`. Magazine decrements and matching shot/ray
sequences are recorded in the checkpoint. The latter hits followed recreation
from local `10718584` to `10718724`, both session entity `4294967301`.
This qualifies the local firing-to-geometric-query path. No native damage or
network event triggered a reaction/death, so shared combat remains unfinished.
The presentation graph/archive are unchanged.

Evidence: `live-presentation-recreate-pass/SUMMARY.md`, `metrics.json`,
`snapshot.json`, final JOINER trace, installed-script hashes and partial HOST
trace. The snapshot marks JOINER closed
and HOST still running. The visual observations above are the test operator's
separate observations, not conclusions inferred from successful queue calls.

| Candidate | SHA256 |
| --- | --- |
| Archive | `ace72cf1514f4564023f7c2e974ac036cba93975736b3e9c561f29128514cfff` |
| Entity binary | `fdaece384d3323106c7ee7725f6f1ea68ecca8df57dbef869fbf9d6d2ac3b159` |
| Graph binary | `49cef3f0588720af25ad08d3a570e9d996d15f2bf770b4177ca41699085c7c08` |

WolvenKit adds pack-time timestamps, so archive hashes differ across rebuilds.
The manifest records resource hashes and the comparison hash with only those
timestamps and the index CRC excluded. Its real archive SHA256 remains the
identity of the candidate being tested.

## Independent live gates

1. Spawn two exact managed projections. Verify no T-pose, no spontaneous AI,
   stable IDs, and that only the selected entity changes pose.
2. Trial five observed progress 0.5 and explicit idle. Hold progress 0 and 1,
   then visually measure playback over the recorded duration.
3. Drive death from 0 to 1, hold for at least 30 seconds, look away/back, and
   inspect that it stays visibly dead without root drift. Do not infer success
   from successful event queues.
4. Trial five observed two exact managed dead-projection recreations and rejected
   a stale reaction. Repeat with accepted HOST state and network reconnect,
   checking that stale idle/reaction state cannot revive it.
5. Test duplicate/reordered fixture events, a failed apply, scope reset and
   cleanup. The state controller must never affect an old or unrelated ID.
6. Connect accepted HOST outcomes through Bukczyk's eventual encounter path.
   Compare visible HOST/JOINER reactions, death and reconnect. Local fixture
   injection is not evidence of network delivery or physical-hit replication.

## Sources

Installed 2.31 asset metadata was inspected locally. Reconstructed game scripts
at `a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a` declare
`core/entity/entity.swift:6` (`Entity.QueueEvent`) and
`core/components/animationControllerComponent.swift:93` (the static float setter
queues `AnimInputSetterFloat`). Its static helper requires `GameObject`; this
adapter uses the underlying Entity event path directly. The third trial's visible
corpse supports this event path for that exact candidate; it does not qualify
every state, entity type or recreation case.

WolvenKit 9.0.1 primary schemas:
[controller](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/entAnimationControllerComponent.cs),
[control binding](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/entAnimationControlBinding.cs),
[switch](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/animAnimNode_Switch.cs),
[frame animation](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/animAnimNode_SkFrameAnim.cs),
[float variable](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/animAnimNode_FloatVariable.cs).
These describe fields and declarations, not runtime results.

CET's [NewObject implementation](https://github.com/maximegmd/CyberEngineTweaks/blob/master/src/scripting/Scripting.cpp#L361)
performs a raw RTTI lookup. WolvenKit's
[native event schema](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/entAnimInputSetterFloat.cs)
names the class `entAnimInputSetterFloat`. The actual lookup failure is recorded
in the local live snapshot, independently of these source declarations.
