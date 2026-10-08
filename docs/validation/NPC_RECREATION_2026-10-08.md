# NPC projection recreation checkpoint

Owner: KyleBuildsAI. Checkpoint: 2026-10-08T12:36:11Z cleanup complete.
Accepted alive-state recreation passed for the controlled fixture. The later
dead-result attempt failed closed on mixed engine-hit evidence; dead-state
recreation remains unqualified. This record separates completed offline checks
and observed one-PC, two-client behavior from the remaining live gates.

## Source and ownership

[PR #10](https://github.com/Bukczyk/CP2077-Coop/pull/10) merged at
2026-10-08T11:30:23Z as `d32dcb54666751b3680e6c3bc428be28a7d1fc3e`.
[PR #12](https://github.com/Bukczyk/CP2077-Coop/pull/12) builds on that main
revision on `feat/npc-projection-state-restoration`. Its tested source is
`34da697de6066fbf76658fbd2733a0e42600a17d`.

The restoration change contains these six files, owned by KyleBuildsAI for this
game-side task:

- `experiments/shared-encounter/connected/joiner.lua`
- `experiments/shared-encounter/presentation_state.lua`
- `experiments/shared-encounter/connected/PRESENTATION_RESTORE.md`
- `experiments/shared-encounter/connected/README.md`
- `tests/connected_presentation_tests.lua`
- `tests/CMakeLists.txt`

This checkpoint document is a subsequent documentation addition. Bukczyk retains
protocol, session/server, accepted-state delivery and reconnect ownership.
The opt-in adapter uses the existing native outcome envelope and CPEX1 diagnostic
body. It adds no network message, wire field or competing network design, and
does not change production defaults or weaken HOST validation.

The [integration notes](../../experiments/shared-encounter/connected/PRESENTATION_RESTORE.md)
define the behavior: retain an accepted result while the local actor is absent,
then restore the exact replacement in the same session/epoch/generation scope.
Health is presentation metadata, not JOINER damage simulation. Alive/dead are
supported; defeated is rejected as `unsupported_life`. Old, duplicate, conflicting
and foreign-scope outcomes cannot overwrite retained state. The default event
ledger admits at most 64 accepted events per scope and explicitly returns
`event_full` when exhausted; this is a bounded diagnostic limit, not sustained
production combat capacity. A scope change clears retained state and requires a
newly supplied outcome.

## Completed offline verification

- Windows Release plugin/server build passed.
- All 26 local CTests passed, including `connected_presentation`.
- The focused JOINER presentation/restoration suite passed 177 checks.
- Matched REDscript compiled in isolation at approximately 11:36:47Z with
  unchanged compilation inputs and compiler result 0.
- [Hosted CI run 37771671659](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37771671659)
  passed Windows, Debian and sanitizer jobs at the exact PR #12 source revision.
  The last job, Windows, completed at 2026-10-08T11:46:14Z.

Private local evidence root:
`D:\Downloads\syncfix\bench-artifacts\20261008-npc-recreation`.
The offline records include `windows-build.log`, `windows-ctest.log`,
`connected-presentation-checks.log`, `redscript.log` and
`redscript/compile-20261008T113646852369Z.log`.

## Earlier live attempts: rejected results and input limitations

Topology: one Windows PC, two game clients and the local typed session server.
Both installed script sets compiled, both clients reached active scope `1:1:1`,
and controlled NPCs spawned. These are setup observations, not recreation proof.

At 2026-10-08T11:54:54Z, a real JOINER shot produced firing sequence 1 and
request 1 for session target `4294967296`, mapped on JOINER to exact local actor
`10729918`. HOST's independent ray check accepted its exact target `10730070`.
The subsequent labelled HOST-current-weapon fixture rejected the request as
`rejected_no_host_ranged_weapon`, reason 7, because HOST's weapon was holstered.
JOINER received HOST event 2 and correctly reported `rejected_outcome`.

This rejection supplied no accepted health/death state for a recreation test.
It is neither a restoration-code failure nor a restoration pass.

Further UI automation attack attempts raised the weapon without an observed
ammo decrement. This occurred with both a pistol and shotgun. Readback showed
weapon state 6 while lowered and 5 briefly while raised; safe scene, forced scene
aim, no-combat, fast-forward and vehicle-scene checks were false.

The local decompiled 2.31 `cyberpunk/player/psm/weaponTransitions.swift` reference
identifies state 5 as Ready and 6 as Safe/PublicSafe. It shows a default 0.30-second
PublicSafe-to-Ready transition and a default 1.00-second idle interval before
returning to PublicSafe. Semi-auto uses a fresh `RangedAttack` press. An
instantaneous automation pulse can therefore raise the weapon and expire before
Ready, while a later isolated pulse repeats that sequence. This is a source-based
input-timing explanation, not a confirmed diagnosis or new firing evidence.

Temporary test-control changes included an attempted F6 attack binding and
`ToggleAimingON`. Original input configuration was restored during final cleanup.
F7 is the intended preflighted recreation input; F9 remains prohibited because it
invokes native QuickLoad.

Trial 4 used user-assisted firing. All 12 user-fired requests were rejected for
the missing HOST ranged weapon. A later local HOST shot killed that trial's NPC;
this produced no accepted connected result for JOINER and cannot qualify
restoration. The controlled actors were replaced using the private F2/F8 fixture
controls for trial 5. These rejected attempts remain part of the evidence.

## Trial 5: accepted alive outcome and local recreation pass

Trial 5 retained active scope `1:1:1`. HOST controlled NPC `10730949` and JOINER
projection `10732548` mapped to the same session target `4294967300`.
User-assisted actual firing produced request 21. HOST fixture serial 15 queued
at 2026-10-08T12:24:05Z and observed authoritative health change from
`221.400757` to `108.654007`, with life state alive.

Accepted HOST event 30 reached JOINER at 12:24:06Z. The new JOINER module accepted
the outcome, retained health `108.654007`, presented a reaction and returned to
idle. This establishes fresh accepted-state admission and same-body presentation
for this controlled fixture.

At 12:24:59Z, F7 triggered local recreation while scope `1:1:1` and session target
`4294967300` stayed unchanged. The reset observed old local actor `10732548`
removed; replacement `10732707` was then bound by its exact local identity.
The replacement's first queued frame was idle, serial 1, retaining HOST event 30,
health `108.654007` and maximum health `221.400757`. The old hit reaction was not
replayed.

At approximately 12:25:35Z, the test owner visually observed the standing
replacement. The screenshot is retained as `alive-recreated.jpg` in the private
evidence root. Combined with the exact removal/binding and queued-frame records,
this passes alive-state local recreation for the controlled fixture. It does not
qualify dead-state recreation or reconnect recovery.

## Trial 5 death attempt: mixed-hit rejection, then diagnostic saturation

At 12:28:46Z, JOINER firing sequence 28 produced request 22 for the same target
`4294967300`. HOST's unchanged exact-target ray check passed, and fixture serial
16 queued against local NPC `10730949`. Engine sequences 6688-6690 recorded the
fixture's candidate/preprocess/deal path. Subsequent observations were valid and
correlated: health first reached `0.221401`, then 0 with persistent death after
sequences 6693-6695. A second valid dead/0 sample followed at sequence 6696.

Before the required 0.25-second settling interval completed, another hit entered
the same NPC's engine evidence. At 12:28:47Z, sequences 6697/6698 reported
`syntheticFixture=false`, `weaponDefined=false`, `weaponLocal=0`,
`instigatorLocal=1` and `hitShapes=13`. The event was not the exact synthetic
fixture hit. Its origin is unproven; this record does not attribute it to a
specific player input, perk or engine mechanism.

`connected/engine.lua` requires a defined weapon and nonzero exact weapon identity
for complete hit evidence. It therefore returned `valid=false` for this mixed
sample. `connected/host.lua` correctly failed closed as unresolved: request 22
received disposition 3, reason 8, then HOST event 31. JOINER rejected that outcome
instead of replacing its retained accepted alive state with an unaccepted death.
The valid dead samples alone did not satisfy the complete settling gate. This is
an unresolved mixed-hit fixture, not a demonstrated JOINER restoration defect.

The later `engine_observation_capacity` fault is secondary. After unresolved
state was recorded, the private runner stopped consuming idle baselines because
its flush condition requires both `pending==0` and `unresolved==0`. Readback
ingestion continued. Exactly 257 undrained readback lines, sequences 6700-6956,
then exceeded the per-actor 256-line buffer at 12:29:03Z. This was not exhaustion
of the 64-target or accepted-outcome ledger and was not the original rejection.
Increasing the limit would only delay the secondary fault.

Exact records are in the archived HOST `zz_EncounterProbe/trace.jsonl`: lines
45198-45208 contain the valid death, mixed-hit rejection and event 31; lines
45465-45466 contain the first capacity failure. A private offline replay,
`mixed-hit-trace-replay.lua` with `mixed-hit-trace-replay.log`, loaded the unchanged
source adapter and those captured samples. It reproduced three valid correlated
samples, the mixed sample returning `valid=false`, and capacity rejection on
exactly the 257th subsequent undrained line. The replay mocked only the effectful
apply callback and performed no game action.

No server or protocol fix is justified by this evidence. Do not weaken causal
validation, accept the rejected death manually or replay engine damage. The
smallest diagnostic correction is to stop capture explicitly after an unresolved
fixture, or continue a separate diagnostic drain while preserving its unresolved
status, so the secondary capacity message cannot obscure the primary failure.
No such behavioral change was made in this checkpoint.

## Remaining live gates

Repeat in a fresh activation/scope with one controlled JOINER shot while HOST
holds a ranged weapon without firing. If a second, unrecognized hit recurs,
identify its engine source before changing attribution or acceptance rules.
Obtain an accepted connected dead result, then qualify dead-state recreation:
record unchanged scope and session target, disappearance of the old local ID,
creation of a new exact local ID and the replacement's visible terminal pose.
The original spawn graph defaults to idle, so a first queued terminal frame does
not prove that no idle frame was visible during asynchronous creation.

This checkpoint claims no authoritative reconnect baseline, zero-idle-flash
restoration, defeated pose, two-PC qualification, JOINER weapon/attacker parity or
general shared-world gameplay. It creates no gameplay release or package
replacement. Earlier connected same-body reaction/death evidence remains in the
[separate encounter record](CONNECTED_ENCOUNTER_2026-10-08.md).

## Cleanup and retained evidence

The test owner closed both game clients and the local test server. The launcher
restored graphics/settings at 12:35:56Z. Runtime restoration completed at
2026-10-08T12:36:11.4224903Z, with status `complete` in
`runtime-restore-20261008T1236096222758Z.json` under the private evidence root.
The journal verifies original matched runtime files and input mappings, reports
zero games open, and confirms 167 save files unchanged by restoration. Saves
were preserved; no save rollback was performed.

The restored original DLL SHA256 is identical in HOST and JOINER:
`bf6ee3a3ebea5374140fa74e43da4f416d0d2c8a431ef46c16afe6d219c4393d`.
The complete experimental runtime and traces are archived under
`restored-experiment-20261008T1236096222758Z`. Private configuration and full
logs remain local. The tested public package is not replaced by this experiment.
KyleBuildsAI retains game-side ownership; no ownership is transferred by this
checkpoint.
