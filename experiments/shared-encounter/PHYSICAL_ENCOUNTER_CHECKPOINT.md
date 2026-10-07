# Physical encounter engine checkpoint

Status: **LOCAL_FIRING_TO_QUERY_AND_PRESENTATION_PASSED_SHARED_COMBAT_PENDING**.
Final local-test record after restoration at `2026-10-07T05:23:55.0108458Z`. Trial five
visibly preserved death through two recreations. Trial nine recorded three real
firing callbacks whose local rays hit the exact passive target, including after
recreation, plus a real firing miss. Trial eleven observed genuine local HOST
hit, health loss and persistent death. JOINER intent delivery, HOST validation of
that remote intent, and accepted-result presentation are still unconnected.
Trial eleven's local presentation check selected the wrong idle-only template;
trial twelve corrected it and visibly passed held reaction, idle, death and
terminal-pose recreation on the combined build 06 asset. This is not a playable
shared-combat release claim.

## Goal, ownership and source

The complete goal is one supported physical action against the exact shared NPC:
HOST validates and owns its damage/reaction/death, and JOINER presents the accepted
result without independent NPC AI. KyleBuildsAI owns engine capture and rendering
in both roles. Bukczyk owns the compatible session/server delivery, identity,
authority, deduplication and reconnect work. HOST/JOINER are runtime roles, not a
split of maintainer responsibility.

- Collaboration upstream: `Bukczyk/CP2077-Coop`.
- Branch: `feat/passive-encounter-engine`.
- Starting source: `b0cdce98fc6cb81516e09ef1cd5f70b128499a90`, from [PR9](https://github.com/Bukczyk/CP2077-Coop/pull/9).
- Worktree: `D:\Downloads\syncfix\collaboration\passive-humanoid-validation`.
- Implementation source: `63b70987c249860097bfc460a3406fcea5bf2837`.
  This documentation was finalized after the implementation commit; exact
  documentation revisions are in the PR history.
  [PR10](https://github.com/Bukczyk/CP2077-Coop/pull/10) is open as a draft, not merged.
- The verified engine answers were published on
  [PR7](https://github.com/Bukczyk/CP2077-Coop/pull/7#issuecomment-6031592494).
- No ownership transfer to Bukczyk is implied by publishing the engine experiment.

KyleBuildsAI retains these exact task files:

- Under `experiments/shared-encounter/`: `engine_hooks.reds`,
  `physical_shots.reds`, `physical_trace.reds`, `presentation.lua`,
  `presentation_state.lua`, `README.md` navigation links, `PHYSICAL_SHOTS.md`,
  `PRESENTATION.md` and this record.
- Under `experiments/shared-encounter/assets/raw/base/cp2077coop/`:
  `entities/cp2077coop_networkhumanoid_encounter.ent.json`,
  `entities/cp2077coop_networkhumanoid_hittable.ent.json` and
  `animations/networkhumanoid_encounter.animgraph.json`.
- `scripts/build-passive-encounter-archive.py` and
  `scripts/build-passive-hittable-archive.py`.
- `tests/encounter_presentation_tests.lua`,
  `tests/encounter_presentation_adapter_tests.lua`,
  `tests/passive_hittable_asset_tests.py` and their
  `tests/CMakeLists.txt` registrations.
- `runtime/session/cet/CP2077Coop/npc_runtime.lua`,
  `runtime/session/cet/CP2077Coop/npc_static_population.lua` and
  `tests/npc_static_identity_tests.lua`, for pending-retirement protection.

Existing session/server/protocol implementation remains outside this task's edits.

## What was implemented

[Physical shot observer](PHYSICAL_SHOTS.md) describes an explicitly enabled local
`UI_ActiveWeaponData.ShootEvent` listener and bounded diagnostics. It validates the
variant and finite XYZ data, uses canonical point/vector W values, and records
weapon/ammunition context. Reset unregisters the listener and clears the old
trace target. Session, epoch and generation changes invalidate capture.

The separate query-only capsule stays on `entEntity`, without NPC AI or a damage
component. A physics ray checks the exact managed/tagged/bound target and current
session scope. The current build 06 uses the vanilla `NPC Hitbox` filter preset:
AI query mask `0/2`, simulation masks `0/0`, no custom override, and no per-shape
override. It accepts origins within five metres of the local player and checks
the nearest result from `Static`, `Vehicle`, `PlayerBlocker` and `AI` within
100 metres. This is a proposed geometric candidate at the UI direction,
not proof of native bullet collision, spread, penetration or projectile travel.

[Presentation candidate](PRESENTATION.md) adds an animation controller, a three-way
idle/reaction/death graph and installed-resource references. No vanilla mesh,
skeleton or animation bytes are bundled. The sampled reaction lasts 0.466666669 s
and death 1.93333328 s according to inspected clip metadata. Fixed illustrative
Judy clips do not reproduce arbitrary HOST appearance, exact directional reactions
or ragdoll. Trial five visually demonstrated a held reaction, return to idle and
death retained through two local recreations. Timed reaction playback and
network recovery remain unqualified.

The [local state guard](presentation_state.lua) takes an opaque caller-owned scope,
exact string session/local IDs, bounded local serials and monotonic local time.
It rechecks mapping before dispatch, rejects duplicate/stale instructions, retains
terminal death across local projection recreation and rejects full capacity
without evicting retained records. Its local serials are not network event IDs.
The caller must establish authority before staging an instruction. Engine queue
acceptance is not visually observed completion or a network acknowledgement.

The existing controlled-NPC [engine probe](README.md) now records exact instigator
and weapon IDs, native hit geometry and whether the callback references the last
synthetic fixture event. `syntheticFixture=false` only means that object does not
match the last tagged fixture. It does not identify the local player or establish
a physical hit by itself. Always correlate source identity, shot/ammunition
evidence and subsequent engine state. All vanilla wrapped methods still run.

The projection runtime now retains a pending reset across same-epoch updates.
Once retirement starts, it must finish before an entity can be recreated; the
static adapter rejects binding and movement while removal is pending. This
addresses the proven old-ID reuse path in trial 3. The private harness also
stages cleanup across frames. Trial five then completed two local recreation
cycles and lifetime-expiry cleanup without the earlier same-ID reuse. This
qualifies those tested sequences, not every possible engine lifecycle.

## Offline validation

| Check | Observed result and limit |
| --- | --- |
| Local state guard suite | PASS using `build/windows/tests/Release/coop_lua_test.exe`; exact IDs above 2^53, scope/time/serial rejection, mapping changes, capacity, failures and retained death tested. |
| Presentation adapter suite | PASS; native RTTI constructor, input rejection, progress-before-phase ordering, terminal sample, explicit idle and partial queue failure tested. A mock cannot prove native consumption. |
| Isolated REDscript compilation | PASS at `2026-10-07T04:30:13Z` for session declarations, installed Codeware and the current three probe sources, including materialized exact IDs and the AI-inclusive query. No live behavior is established by compilation. |
| Presentation asset build | PASS conversion, roundtrip, exact two-resource archive and unpacked binary parity. Source and existing roundtrip also pass stronger handle/link validation; nine miswiring cases are rejected. |
| Capsule asset build | Build 06 PASS conversion, query-only component/filter contract, one-resource archive and unpacked binary parity; nine regression tests PASS. NPC Hitbox preset, query masks 0/2, zero simulation masks and inherited shape filter match the inspected vanilla resource. Trial nine separately passed real-firing-to-exact-query and miss checks, including after recreation. Native bullet damage remains unproved. |
| Pending-retirement regressions | PASS for same-epoch reset, bind/move rejection, rejected unbind and relevance returning during removal. Old runtime and old adapter each fail the corresponding new case. |
| Complete local CTest | 19/19 PASS on `2026-10-07`, from `04:31Z` to `04:32Z`, including the nine current collider cases, both presentation suites and static identity; retained in `final-19-tests.log`. These are offline checks. |
| Native Release build | PASS at `2026-10-07T04:19Z`, recorded by the test owner. No subsequent native source change is part of these asset/script revisions. |
| Hosted CI | Windows, Debian and sanitizer jobs all PASS for implementation `63b7098` in [run 37574659468](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37574659468), completed `05:10:51Z`. Final documentation-head checks are separate. |
| Two-PC or larger live group | Not run in these completed local trials. |

The presentation candidate archive SHA256 is
`ace72cf1514f4564023f7c2e974ac036cba93975736b3e9c561f29128514cfff`.
The zero-mask capsule used in trials 3-5 has archive SHA256
`73574af7d27d8a7a6008c468fbc4ea52cd5d4633a97138df0e2f8cb541a13371`.
The custom Static-mask candidate used in trials 6-7, build 05, has archive SHA256
`d6a8a867afdd220b94bf4a430df5d2f8deb790539e9ee8e05cd70d2fc8a3d0ce`.
The current NPC Hitbox candidate used for launches 8-9, build 06, has archive
SHA256 `d7d8a7426490e30cd0d4e4746316f0e2307b96c13916a708aed176e6c4a5d9c7`.
Pack timestamps affect rebuilt archive hashes; manifests retain actual archive
and extracted resource hashes. Do not replace actual hashes with normalized ones.

## Trial 1: genuine firing and stimulus, no local-player target hit

Topology: two game processes on one PC. Launcher
`20261007-031415-271644`, started `2026-10-07T03:14:15Z`. Archived traces end at
`03:20:17Z` HOST and `03:20:18Z` JOINER.

At `03:18:30Z`, HOST weapon `10713436` emitted one real UI shooting notification.
Surrounding same-weapon readbacks show magazine **6 to 5** and total ammunition
**574 to 573**. The captured direction length squared was 1. Capture had been
enabled before the weapon was drawn, so its first callback's `sameWeapon=false`
is not the evidence for the decrement; the surrounding readbacks are.

The same shot produced two natural Gunshot broadcasts. Controlled HOST NPC
`10713575`, session entity `4294967296` in session 1, received both stimuli and
changed from Relaxed (5) to Combat (2) at `03:18:31Z`, with health unchanged at
221.400757. Neither directed-stimulus nor synthetic-hit fixtures ran.

Three subsequent native hit candidates came from instigator `9015294`, weapon
`10713533`, rather than the local player. No corresponding damage-pipeline
completion or death appeared, and initialized health stayed unchanged. They must
not be counted as the player's hit against the controlled NPC. No JOINER firing
or passive-proxy collision was established in this run. This trial used the old
idle asset, without the new reaction graph or query-only collider.

**Preserved incident:** F9 cleanup also invoked normal game quickload. The HOST
loaded a new session, and JOINER ended in phase 5 instead of demonstrating
automatic recovery. Brief zero-health samples during new-source initialization
had `persistentDead=false` and are not death. Cleanup moved to F2 for the next
trial. This incident is not a passing cleanup or reconnect qualification.

## Trial 2: animation constructor failure

Topology: two game processes on one PC. Launcher
`20261007-032228-045229`, started `2026-10-07T03:22:28Z`. The presentation and
capsule candidates were installed. Captured traces cover `03:22:51Z` to
`03:35:49Z` HOST and `03:23:28Z` to `03:35:50Z` JOINER.

The adapter used `NewObject("AnimInputSetterFloat")`, the REDscript alias rather
than CET's native RTTI type. The captured JOINER log contains 4,352 type-lookup
errors, and trace data contains 4,400 `engine_rejected` applications. Those are
separate observations, not an assumed one-to-one count. No real shooting events,
physics traces or staged reaction/death requests were recorded in either role's
archived trace. This trial does not qualify visible reaction/death or collision.

The source correction is `NewObject("entAnimInputSetterFloat")`. A regression
test rejects the former alias and validates the native name and failure path.
The correction was installed at `2026-10-07T03:37:53Z`, together with refreshed
probe scripts. Constructor correction and queue tests alone do not establish that
the graph consumes events. The subsequent trials below supply separate visual
evidence.

## Trial 3: local death observed, physical target hit unproved, recreation crashed

Topology remained two game processes on one PC. The final archive was captured
after both games closed and launcher settings restoration at `03:48:13Z`.
Its manifest hashes 32 files, including exact installed probes, traces, launcher
records, RED4ext logs and the JOINER dump.

HOST captured five genuine UI firing notifications from local player `1`, weapon
`10714128`, at `03:42:50Z`, `03:43:47Z`, `03:45:16Z`, `03:45:48Z` and
`03:46:04Z`. Magazine fell **6 to 1** and total ammunition **574 to 569**.
Ten natural Gunshot receipts appeared on controlled NPCs. There were zero native
hit candidates, damage/death callbacks or persistent-dead readbacks. All four
initialized NPC lifetimes retained health 221.400757. The operator observed
aim/target movement problems. These shots do not establish physical target hits.

HOST's five physics-trace records were disabled because its NPC was not the
selected passive JOINER target. JOINER fired zero shots before the crash. There
was no exact-target query, clear-miss or obstruction test. Configuring a trace
target is not evidence that the collider was queried or hit.

JOINER bound local `10714169` to session entity `4294967296`, with 1,118 bound
frames and zero root-position span. A local reaction fixture at `03:41:50Z`
queued five samples, then returned to idle after about 0.512 s. Its visible
playback was not qualified. A local death fixture at `03:41:57Z` queued terminal
progress at `03:41:59Z`; the operator independently observed a corpse on the
ground at **`03:42:25Z`**. Immediate duplicate requests were rejected. These were
local fixtures, not physical-hit or HOST-authoritative network outcomes. One
corpse observation does not establish continuous 30-second persistence.

At **`03:42:29Z`**, F10 requested recreation. The harness continued after
`reset()` returned false and rebound the same retiring local entity `10714169`
before queuing its terminal pose. JOINER process `61424` exited with an access
violation. The dump records a read at `0xC0` in
`Cyberpunk2077.exe+0x574FD7`. No fully unwound symbolic stack identified the
faulting engine call; neither the capsule nor graph is an established cause.

The retained Codeware handle permits this unsafe reuse before disposal finishes.
The new reset latch, irreversible retirement and adapter guards prevent it in
regression tests. The complete 18-test local suite passed. The game-side code and
staged private harness were installed at `03:50:12Z` for the next trial; their
live recreation result was still untested.

A separate Codeware 1.18 static `IsTagged` defect checks any tag rather than the
requested tag. The fourth trial candidate checked explicit `GetTags` membership;
that change compiled at `03:48:44Z` and was not in the crashed third run. No connection
between this tag defect and the crash has been established.

## Trial 4: crash during initial projection spawn

After desktop access resumed, JOINER crashed at **`03:55:10Z`**. Its final trace
contains the first new projection, local ID `10714234`, with `bound=false` and
`exists=false`; no earlier bound projection was logged. The operator briefly
saw the proxy render. No reaction, death, hold or recreation input had run.
This is not the third trial's same-ID recreation sequence.

The failure was not localized between asynchronous attachment, first
bind/move and the first non-null trace-target call. Null target clearing had
already run throughout preceding empty-NPC frames. The new tag-membership call
is a hypothesis requiring isolation, not a demonstrated destructor or array
failure. Its exact cause remains unresolved; subsequent narrower tests are
recorded below. The fourth trial does not qualify the retirement fix, collision
or stable presentation.

The next mitigation restores the previously used DynamicEntitySystem tag check
for HOST and materializes StaticEntitySystem's tagged-entity collection for
JOINER. A bounded loop compares exact local IDs, preserving ownership checks
while avoiding the nested `GetTags`/`ArrayContains` expression. Compilation
passed at `03:58:48Z`; trial five below records the later result. Fourth-dump
analysis reports a different fault offset, `Cyberpunk2077.exe+0x28336B`, with
the attempted read address equal to local entity ID `10714234`. This supports
investigating a value/address mismatch but does not identify its exact caller.

The fourth snapshot at `03:59:53Z` hashes 32 files. JOINER's trace is final; HOST
remained open as PID 58332, so that role's snapshot is partial. Trial five
restarted JOINER with the mitigation and call-boundary diagnostics while
retaining the existing HOST/server. It was a mixed diagnostic setup; HOST's
native-hit scope and complete matched-runtime behavior remain unqualified.
Its results are recorded separately below. A successful queue cannot fill a visible
animation gate. Trial five supplies a separate held-sample observation below.

## Trial 5: held reaction, terminal death and two recreations passed locally

JOINER process `60052` started about `04:01Z` and was deliberately closed before
the final snapshot at `04:14:42Z`. HOST `58332` retained its trial-four source
and unscoped native-hit observer. This mixed diagnostic setup is valid evidence
for the local presentation fixture, not current HOST damage validation. JOINER's
final trace spans `04:01:40Z` to `04:14:01Z`, with 6,661 state frames and no
logged Lua error; additional rows are diagnostic call boundaries.

The operator observed a visibly distinct KP1 reaction midpoint and KP2 return
to idle. Held samples span `04:05:31Z` to `04:06:15Z`. The separate F3 timed
reaction at `04:06:45Z` was staged and returned to idle after 0.548 s, but its
short transient was not visually measured. F4 death at `04:06:52Z` reached
terminal state at `04:06:54Z` after 2.064 s and visibly produced a corpse.

F10 recreation at `04:07:40Z` replaced local ID `10713756` with `10714375`.
A second request at `04:08:10Z` bound new local ID `10714393` at `04:08:11Z`.
Both retained session entity `4294967297`. Each cleanup first returned false,
then true on a later tick, after 0.110 s and 0.111 s respectively, before a fresh
ID spawned and bound. All 4,832 bound frames resolved the exact session entity.
Their zero target-position error applies to a stationary target, not moving
latency. Neither old ID
was rebound. The operator observed terminal death preserved after both changes.
An F3 reaction at `04:07:59Z` was rejected as `terminal_death`.

At `04:12:37Z`, the HOST fixture expired. JOINER first showed the old projection
unbound, then an empty owned-projection list 0.105 s after catalog removal.
This is passing evidence for the tested local retirement/recreation sequence.
It does not identify the exact faulting instruction in either earlier crash or
establish network dead-state recovery.

All these pose commands were local fixtures. The trace-target gate returned
false in **4,832 bound frames**, and JOINER fired **zero shots**. No physical
target hit, clear miss, obstruction or shared-combat outcome was established.
The zero-mask capsule was still installed. Trial six subsequently used numeric
query mask2=4 and trace-gate status diagnostics, without backend integration.

The archive `live-presentation-recreate-pass/snapshot.json` preserves final
JOINER inputs/traces and marks the continuing HOST snapshot as nonfinal. Visual
pose confirmations are separate operator observations; queue logs alone do not
establish them. The final restoration record below covers the completed session.

## Trial 6: target rejection isolated to a chained ID read

JOINER `15452` recorded 943 stable bound frames from `04:16:33Z` through
`04:18:15Z`, with exact local ID `10714475` mapped to session entity
`4294967298`. Every trace-target setter rejected exact tag membership: the
one-entry collection's chained `GetEntityID().hash` produced `1246179402736`,
while the separately stored target ID read correctly. Scope, attachment,
non-NPC and managed-entity checks had passed. This isolates the failing
comparison path without proving a particular compiler/native temporary defect.

The correction stores the tagged entity and its native `EntityID` return in
separate locals before reading `.hash`. It preserves every identity check and
compiled at `04:17:36Z`. This trial fired no shots and made no ray query. The
mask-4 candidate's collision behavior was still untested. The operator closed
JOINER before archiving; the final shutdown breadcrumb still showed removal
pending, so shutdown itself did not prove observed disappearance. HOST `58332`
continued its older, unscoped damage probe.

## Trial 7: exact target gate passed, four rays failed the capsule

After the materialized-ID correction, all **4,740 bound frames** passed exact
mapping and the tag gate without a logged probe error. The first 2,339 frames
used local/session IDs `10714475` / `4294967298`; after HOST catalog recreation,
2,401 frames used `10715125` / `4294967299`.

Four genuine JOINER firing notifications at `04:21:18Z`, `04:22:03Z`,
`04:22:28Z` and `04:22:45Z` accompanied magazine **6 to 2** and total ammunition
**574 to 570**. Weapon `10714844` belonged to local player `1`, session player
`5`. All four custom rays returned `exactTarget=false` and no hit-entity handle.
The fourth UI-direction ray passed 0.036697 m from the authored capsule center
at 4.006 m along the ray, then hit world geometry at 9.305 m. This is meaningful
evidence of a candidate-filter failure, not merely an assumed aiming error.
It is still a geometric ray, not a verified native bullet trajectory.

Read-only collider inspection at `04:25:58Z` and `04:27:33Z` found an enabled
kinematic body, one shape, valid body index 0, `queryable=true`, and the correct
world transform. Its runtime query masks were **0/0**, despite build 05's
authored 0/4. The reason initialization ignored or cleared the custom filter
has not been established. No target query hit or damage was observed.

JOINER `5032` was closed before the `04:30:40Z` archive. The HOST snapshot was
partial and still cannot qualify current HOST damage behavior. The following
candidate changed only the owned capsule filter setup to the vanilla NPC
Hitbox preset and included AI in the query; it added no AI or native damage.

## Launch 8: startup crash before fresh encounter code ran

JOINER `42412` launched with build 06 at `04:31:36Z` and crashed at
`04:32:13Z`, before loading a world or receiving operator input. RED4ext loaded
Codeware/session plugins and REDscript compiled at `04:31:47Z`, but no fresh
experiment trace or CET mod initialization was recorded. The preserved trace
and scripting log are from trial seven; they are not eighth-launch evidence.

The dump reports an access-violation write at `Cyberpunk2077.exe+0x19088D0` to
`exe+0x2ACD0E0`, distinct from the earlier two crash offsets/read failures.
There is no symbolic causal link to the capsule. This launch qualifies no
projection, firing, collider, reaction or damage behavior. The next retry used
the identical installed inputs instead of claiming a speculative crash fix.

## Trial 9: scripted checks, then real firing to exact-target query passed

The identical-input retry launched JOINER `47884` at `04:34:17Z` and reached
the world. `joiner-nine-retry.json` records no changed files relative to the
eighth-launch installation. At `04:36:36Z`, read-only inspection of local
`10717221`, session entity `4294967300`, found a valid queryable body at the
correct target transform. Its NPC Hitbox query masks were **0/2** and simulation
masks **0/0**, matching build 06.

At **`04:45:25Z`**, an explicitly scripted CET call passed a ray from the player's
position plus 1.6 m toward the proxy's authored center to the existing private
`CP2077Encounter_TracePhysicalShot` helper. It returned `exactTarget=true`, with
both hit and expected IDs equal to local `10717221` / session `4294967300`, at
distance-squared 13.508876. At **`04:46:05Z`**, the center test passed again; an
offset direction returned world geometry with `exactTarget=false`, and an upward
direction returned `outcome=miss`.

These calls retained **sequence 0** and did not send `ShootEvent`, consume
ammunition, create native damage or submit network intent. They prove the
corrected capsule's local queryability, exact identity and these two rejection
cases. They do not prove the actual firing callback hits the capsule, bullet
trajectory equivalence, or a target occluded by a nearer object. The raw CET log
labels them `scripted_query_only`, `scripted_query_center`,
`scripted_query_offset` and `scripted_query_up`.

The earlier input check initially produced no shot. A separate `04:41:11Z`
read of friendly aim, Stunned and Jam returned false with `weaponDefined=false`,
so it cannot exclude restrictions at firing time. Later short-cycle tool inputs
kept the weapon ready and produced the following genuine firing notifications;
the cause of every prior failed input attempt is not established.

| UTC | Shot sequence | Local target / session entity | Same-callback query result | Ammunition readback |
| --- | --- | --- | --- | --- |
| `04:53:33Z` | 1 | No current projection | Trace disabled | Magazine 5; previous weapon observation differed. |
| `04:54:21Z` | 2 | `10718584` / `4294967301` | Exact hit; distance-squared 13.653147 | Magazine 5 to 4; total 573 to 572. |
| `04:55:39Z` | 3 | `10718724` / `4294967301` | Exact hit; distance-squared 13.622984 | Magazine 4 to 3; total 572 to 571. |
| `04:55:44Z` | 4 | `10718724` / `4294967301` | Exact hit; distance-squared 13.680485 | Magazine 3 to 2; total 571 to 570. |
| `04:55:52Z` | 5 | `10718724` / `4294967301` | Upward shot missed | Magazine 2 to 1; total 570 to 569. |

All five notifications identify weapon `10717189`, local player `1`, session
player `6`; the complete readback sequence shows magazine 6 to 1. Sequences 2-5
report the same weapon and a one-round decrease. Each
hit/miss line shares its sequence with the genuine firing callback. Exact
local/session mapping and the tag gate passed in those same state frames.

Between the first hit and the two later hits, F10 recreation at `04:55:11Z`
returned pending then complete on the following tick, 0.104 s later. The local
ID changed from `10718584` to `10718724`, first bound at `04:55:12Z`, while
session entity `4294967301` stayed the same. The old ID never rebound. Hits after
recreation resolve the fresh ID. This validates the local
firing-notification to geometric-ray to exact-target path and this rebind case.

These are real shots followed by custom geometric queries. The passive entity
still receives no native damage, and no network intent/result delivery or
synchronized reaction is implemented. The ray uses UI direction without verified
spread, penetration or projectile travel. Nearer wall, vehicle, NPC, self-occlusion
and moving-target cases remain open. HOST `58332` used the older probe, so its
trace does not qualify HOST damage. The ninth archive is now final:
`live-query-filter-pass/snapshot.json` hashes 39 files, with JOINER
`04:34:52Z-04:57:12Z` and HOST `03:50:44Z-04:57:40Z`. All 7,094 bound JOINER
frames passed exact mapping and tag membership. Both games/server closed, and
the launcher reported settings restored at `04:57:52.635Z`. Subsequent matched
tests are separate runs; their final cleanup is recorded below.

## Trial 11: genuine HOST hit, damage and death observed

Both roles received the current source probes from commit `63b7098` through the
matched deployment recorded at `05:02:05Z`. In this run the HOST's native observer
was scoped. At `05:07:14Z`, a genuine shot from weapon `10718342` correlated with
PreProcess and DealDamages observations on controlled local NPC `10718591`,
session entity `4294967296`. The instigator was local player `1`, the callback
weapon matched, `syntheticFixture=false`, `projectionPipeline=false`, and
`fixtureRequest=0`. Subsequent health readback fell from 221.400757 to
110.067528. This is observed health loss, not inferred computed damage.

At `05:10:44Z`, genuine shot sequence 7 hit controlled local `10718799`, session
entity `4294967297`, with the same player/weapon attribution and no synthetic
fixture. Ammunition changed 6 to 5 after reload, total 568 to 567. The engine
ordering matters for the eventual authoritative result:

| Simulation time | Observed point | Health / death evidence |
| --- | --- | --- |
| `216022.478734` | Genuine firing notification | Health still 221.400757. |
| `216022.503892` | PreProcess / DealDamages observation | Computed damage became 399.499512, but observed health was still 221.400757. |
| `216022.530476` | `death_callback` | Health 0; persistent dead flag still false. |
| `216022.530476` | `on_died_after_vanilla` | Health 0; persistent dead flag now true. |
| `216022.588446` | Independent readback | Health 0 and persistent death confirmed. |

This passes the tested local native hit/damage/death observer path. A computed
damage value, an early callback or a queued action alone must not be published
as completed damage/death. The run does not implement JOINER intent submission,
HOST validation/apply of that intent, or delivery of accepted outcomes.

The JOINER remained idle after HOST death, as expected with no combat-result
delivery. A separate local presentation check also failed visually: held pose
at `05:11:35Z` and death at `05:12:04Z` queued, but the proxy was still upright at
`05:12:14Z`. Investigation found a concrete private deployment error:
`install_matched_ten.py` copied the production default adapter into the private
probe without restoring its `_hittable.ent` template override. The manifest and
installed private adapter hash `0d4155fb2cce59823776fd2e662a7045e552fa9d2c8e363976daa779fcce0019`
select the original `cp2077coop_networkhumanoid.ent`, whose graph is idle-only.

The encounter/hittable archives still had the correct hashes, but that spawned
template did not use them. The build 04 to build 06 entity comparison shows only
collider-filter changes and serialization handle renumbering, not altered
presentation components. This invalidates trial eleven as a test of the
encounter presentation graph; it does not establish a graph regression or erase
trial five's qualified visual evidence. The narrow correction belongs in the
private installer, preserving the production default. Correct template selection
and a fresh projection must be verified before the next presentation check.

## Trial 12: combined asset's local presentation and recreation passed

The private JOINER adapter's `_hittable.ent` override was restored at
`05:16:41Z`, recorded in `joiner-twelve-install.json`. The normal production
adapter stayed unchanged. JOINER restarted with the same build 06 collider and
build 03 presentation archives; HOST continued its current trial-eleven process.
Trial eleven is preserved in `live-host-physical-native`: final JOINER trace,
partial continuing HOST snapshot, 43 input hashes and reproducible native-hit
and death-order assertions.

The first JOINER lifetime, local `10719099` / session `4294967297`, overlapped
the HOST fixture's automatic expiry. The `05:19:57Z` F10 reset occurred after
that life was already removed and is excluded as recreation evidence.

The next lifetime used local `10719874` / session entity `4294967298`. The
operator observed a visibly different held reaction pose, then idle restored
after release at `05:21:02Z`. Local death was staged at `05:21:07Z`, serial 2;
the operator observed the corpse at `05:21:14Z`.

At `05:21:20Z`, F10 reset returned false/pending and then true 0.109347 s later.
Fresh local `10719913` first bound at `05:21:21Z` to the same session entity.
Its first bound presentation state was terminal dead, progress 1, serial 2.
The operator visually confirmed the preserved corpse at `05:21:28Z`. This
qualifies held reaction, idle restoration, local death and terminal-pose
recreation with the current combined candidate. It is not timed-animation,
network-reconnect or accepted-HOST-result delivery evidence.

The final archive `live-final-presentation-pass` preserves both final role traces
and 44 hashed inputs. All 1,893 bound JOINER frames passed exact tag/mapping;
137 frames held the reaction midpoint from `05:20:46Z` to `05:21:02Z`. Three
body inspections confirmed query masks 0/2 and simulation masks 0/0. Neither
role logged a probe error. JOINER fired no shots in this final trial, so the
ninth trial remains the physical-shot-to-query evidence.

The verified HOST death and JOINER local poses remain separate tests. No combat
network message triggered the JOINER transition. Both games/server closed, and
the launcher reported graphics/settings restored at `05:23:06.523483Z`. The
subsequent hash-verified runtime restoration is recorded below.

## Shared interface and next complete-feature test

The inspected [`SessionBridge::SubmitWorld`](../../shared/include/coop/game_bridge.hpp)
still returns `SubmitResult::Unsupported`. The
[shared encounter contract](../../docs/SHARED_ENCOUNTER_PROTOCOL_PROPOSAL.md) and
[previous engine findings](../../docs/ENCOUNTER_ENGINE_FINDINGS.md) remain the
coordination records. This task adds no packet numbers, wire layout or alternative
delivery route. No complete JOINER intent to HOST damage to JOINER accepted result
path is implemented by these local fixtures.

The proposed exchange is a supported JOINER action and exact session target,
followed by HOST-approved reaction/life outcomes. Observed UI origin/direction and
local weapon context are client evidence, not trusted damage or final trajectory.
Bukczyk retains transport, sender/epoch validation, request/result ordering and
recovery. KyleBuildsAI retains engine capture, validation/apply hooks and rendering.
Both must agree payload meaning and failure behavior against actual observations.

Complete acceptance requires one controlled supported NPC: a genuine JOINER
action reaches HOST, HOST alone validates/applies the result, and both clients
observe the same reaction/death. Then test duplicate and stale traffic, missing
targets, capacity failure and dead-state recovery on reconnect. Local serial
rejection and local projection recreation do not prove network recovery. Repeat
on two PCs before claiming the internet gameplay path is qualified.

## Evidence and final handoff

Private evidence root:
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine`.

- `live-shot-observer/SUMMARY.md`, `metrics.json`, archived sources/traces and launcher.
- `live-constructor-failure/constructor-failure-summary.json`, archived sources/traces and launcher.
- `live-hitbox-recreate-crash/SUMMARY.md`, reproducible `metrics.json`, archived sources/traces and crash dump.
- `live-first-bind-tag-crash/snapshot.json`, final JOINER trace/dump and nonfinal HOST snapshot.
- `live-presentation-recreate-pass/SUMMARY.md`, reproducible `metrics.json`, `snapshot.json`, final JOINER trace and nonfinal HOST snapshot.
- `live-tag-id-diagnostic/SUMMARY.md`, reproducible `metrics.json` and exact sixth-trial inputs.
- `live-query-mask-failure/SUMMARY.md`, reproducible `metrics.json`, four shot/ray records and collider readbacks.
- `live-startup-crash/SUMMARY.md`, crash metrics/dump and provenance for the stale prior trace.
- `live-query-filter-pass/SUMMARY.md`, reproducible `metrics.json`, final ninth traces and 39-file hash manifest.
- `live-host-physical-native/SUMMARY.md`, reproducible native-hit/death metrics, final trial-eleven JOINER and partial continuing HOST snapshot.
- `live-final-presentation-pass/SUMMARY.md`, `analyze.py`, `metrics.json`, `analyze_native_host.py`, `native-host-metrics.json` and the 44-file hash manifest preserve the final twelfth JOINER and full eleventh HOST traces.
- `presentation/build-03/manifest.json`, `builder-link-validation.json`.
- `presentation/retiring-regression/results.json` and the local `build/windows/Testing/Temporary/LastTest.log`.
- `physical-shots/hittable-build-04/manifest.json`, `physical-shots/hittable-build-05/manifest.json`, `physical-shots/hittable-build-06/manifest.json` and `physical-shots/result.json`.
- `final-19-tests.log` records the latest complete local CTest run.
- `candidate-install.json`, `candidate-refresh.json`, `retiring-fix-install.json`, `joiner-five-install.json`, `joiner-six-install.json`, `joiner-seven-install.json`, `joiner-eight-install.json`, `joiner-nine-retry.json`, `matched-ten-install.json` and `joiner-twelve-install.json` identify installed inputs, unchanged retry and private-template correction.

Restoration manifest `runtime-restore-20261007T0523537922296Z.json` reports
**complete** at `2026-10-07T05:23:55.0108458Z`. It verifies the original typed
HOST/JOINER runtime, bindings, input XML and server bytes. Experimental installed
files were archived separately. Graphics/settings were restored, and no game or
test server was left running. All **167 current save files** checked before and
after restoration were unchanged; no old saves were restored.

`public-package-verified.json`, recorded at `2026-10-07T04:29:40.9078660Z`,
verified all **70 SHA entries** (69 payload files plus the manifest). The existing
complete package in `D:\Downloads\syncfix\MP=Jakub\game-files\latest` remains
**v0.0.37 / alpha5**, unchanged. Its ZIP SHA256 is
`4205990ab92d0a9754232067e2082ba170df7850acc30bcb97a5153d45032ddc`.
This source experiment did not create a new playable package or replace that
public release. The restored typed test installs and the public package are
separate baselines.

The remaining complete-feature work is agreed network intent/result delivery,
game-side HOST validation and observed application of remote intent, accepted
JOINER presentation, then duplicate/stale/reconnect and two-PC qualification.
Local component passes do not mark those shared-combat gates complete.
