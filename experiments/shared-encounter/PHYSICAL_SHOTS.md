# Opt-in physical shot observer

This is a local diagnostic, not combat networking. It observes the engine's
`UI_ActiveWeaponData.ShootEvent` notification for the enabled local player and
copies scalar values to a bounded 128-line buffer. It never presses fire, creates
an attack, changes ammunition, applies damage or writes network state.

```lua
local player = Game.GetPlayer()
print(player:CP2077Encounter_EnablePhysicalShotCapture(true))
print(player:CP2077Encounter_PhysicalShotReadback())
-- Manually fire a supported ranged weapon with a non-empty magazine.
for _, line in ipairs(player:CP2077Encounter_DrainPhysicalShots()) do print(line) end
print(player:CP2077Encounter_PhysicalShotReadback())
player:CP2077Encounter_EnablePhysicalShotCapture(false)
```

Use a normal, unsilenced, single-shot Power pistol first. Observe the ammunition
counter before and after firing and compare it with the readback. An empty
buffer and unchanged ammunition do not prove a hook failure. Check game focus,
CET overlay/input capture, a held click long enough to reach a game frame and
the reported restriction values. The probe does not bypass firing restrictions.

The readback reports exact current weapon `EntityID.hash`, magazine count,
capacity, total ammunition, weapon/high-level state and selected vanilla firing
restrictions (`NoCombat`, `FastForward`, `VehicleScene`, safe scene tier, forced
scene aim, takedown and combat gadget). This is a partial diagnostic, not a
complete `CanFire` implementation. Reading it does not alter the previous shot's
ammunition observation.

For a ranged weapon, `weaponState=5` is `gamePSMRangedWeaponStates.Ready`
(`Safe=6`, `Shoot=8`), matching `ReadyEvents.OnEnter`. Do not interpret it with
the separate `gamePSMWeaponStates` enum. Ready plus these partial restriction
flags does not prove that a physical button press reached `RangedAttack`.
Additional vanilla gates include friendly aim, Stunned/Jam, locomotion,
consumable, right-hand equip and workspot state. Inspect them without changing
the flags when ammunition remains unchanged.

The callback validates the exact variant type before conversion, finite and
bounded origin/direction components, a nonzero direction and the current ranged
weapon. It records origin/direction XYZ as supplied by the UI event, and sets
origin W=1 and direction W=0 before vector/raycast operations. It does so without
claiming they include spread, projectile travel, penetration or the final bullet
trajectory. It records whether the same weapon's magazine decreased since the
previous callback or enable-time observation. Callback ordering relative to
ammunition decrement must be measured; this flag is not one-to-one shot proof.
`collision=false` explicitly means the firing notification is not a collision.
An optional separate `physical_trace` line can report a physics-query result.

Enabling capture requires an active session and resets the buffer, counters and
listener. Re-enabling unregisters the old listener first. Session, epoch,
generation or local-player changes invalidate capture. Call `DrainPhysicalShots`
or `PhysicalShotReadback` each probe tick so an idle scope change also unregisters
the listener. Drain discards stale-scope samples. Always disable capture before
leaving the game. Overflow and rejected events are reported explicitly.

## Validation gates

1. Compile with the current session declarations and installed Codeware in an
   isolated sandbox. Compilation does not prove callback delivery.
2. Fire three separated real shots into a harmless empty direction. Record UI
   ammunition, callback count, readback and UTC evidence. Test a held burst
   separately. Establish callback timing and count before using a firing event.
3. Fire at the tagged HOST test NPC with the existing `engine_hooks.reds`
   observers enabled. Match natural firing evidence to `PreProcess`, damage
   readback and exact target session ID. Do not call the synthetic fixture.
4. Test the passive JOINER entity separately. The original minimal template has
   no collider or hit representation. A firing notification alone cannot
   establish a hit against it. The optional collider/raycast candidate must match the
   exact bound local ID, reject misses/occlusion and preserve non-NPC AI behavior.
5. Disable/re-enable and change session generation: old samples must disappear,
   new callbacks must not multiply and the fresh scope must require enablement.

## Optional exact-target physics trace

The separate `cp2077coop_networkhumanoid_hittable.ent` candidate adds one query-only
capsule to the encounter presentation template. It remains `entEntity`, with no
NPCPuppet, AI, damage component or gameplay animation database. The capsule is
kinematic and has no physical collision groups in its authored filter. The
current candidate uses the built-in `NPC Hitbox` preset, exposing it to `AI`
queries with `mask1=0, mask2=2` and zero simulation masks. Custom filter data and
the shape override are null, so the shape inherits the component filter. This
matches the filter arrangement of an installed vanilla query-only hitbox.
Three genuine firing callbacks have now produced exact-target query hits,
including after replacement of the local entity. A real sky shot and separate
scripted miss checks are also verified below. Broader occlusion and movement
gates remain. Radius 0.35, height 1.1 and local center
Z=0.9 are provisional body bounds, not head/limb hitboxes or an animation-matched
hurtbox. Shape orientation, filter behavior and transform following need live
measurement.

The presentation death pose does not reshape or disable this standing capsule.
It is not corpse physics. A future caller must apply authoritative alive/dead
rules and deliberately clear, replace or reconfigure hit geometry as required;
an exact geometric match alone does not authorize damage to a living target.

Build it with `scripts/build-passive-hittable-archive.py`. The resulting
`CP2077Coop_EncounterHittable.archive` contains only the one authored entity and
requires `CP2077Coop_EncounterPresentation.archive` for its graph. No installed
game resource bytes are bundled. Keep the candidate opt-in in the private runner.

The preset is grounded in installed 2.31 physics definitions and the
`HitPhysicalQueryMesh` component of `dummy_man_base.ent`. Its query-only shape
uses `NPC Hitbox`, null custom data, null shape filter, query masks 0/2 and
simulation masks 0/0. `AI` is collision-group index 1. Private comparisons of
Player Blocker and Vehicle/Tank Blocker components also confirm that these bits
occupy `mask2`. Only this filter arrangement is reproduced in the authored
capsule; no vanilla entity, NPC or AI component is redistributed.

Earlier candidates used preset `None`, a custom `Static` query name and shared
shape/component filter. Build 05 explicitly authored query mask 0/4. The
seventh live trial found its body registered and queryable at the correct
position, but both runtime query masks were zero. A ray passing within 0.037 m
of the authored center missed the proxy. This rules out treating an offline
mask check as proof of live filter initialization. The cause of the cleared or
ignored custom filter is not established. Build 06 deliberately changes to the
known built-in preset and its inheritance arrangement. Private extracted evidence stays under
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\physical-shots\collision-research`
and is not redistributed. Build 06 passed roundtrip and payload parity at
04:30:39Z on 2026-10-07; all nine asset checks passed and the current probes
compiled at 04:30:13Z. The identical candidate's ninth live launch subsequently
verified filter initialization, scripted center/miss queries and three genuine
firing-to-target queries as described below. These remain local geometry evidence,
not native bullet damage or synchronized combat.

From the repository root, using a fresh output directory:

```powershell
python tests/passive_hittable_asset_tests.py
python scripts/build-passive-hittable-archive.py `
  --entity-json experiments/shared-encounter/assets/raw/base/cp2077coop/entities/cp2077coop_networkhumanoid_hittable.ent.json `
  --wolvenkit 'D:\Downloads\syncfix\bench-artifacts\20261006-shared-encounter\research\tools\WolvenKit.Console-9.0.1\WolvenKit.CLI.exe' `
  --output-dir 'D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\physical-shots\hittable-rebuild-01'
```

The builder checks the CLI hash, exact component types, query-only/no-contact
filters, cooked query/simulation masks and capsule dimensions, deserializes and serializes the entity, checks
the same invariants after roundtrip, packs exactly one entity, then unpacks and
compares payload hashes. `manifest.json` records actual archive/source/resource
hashes. Pack timestamps can change the archive hash between builds. Point
Codeware's private `StaticEntitySpec.templatePath` at
`base\cp2077coop\entities\cp2077coop_networkhumanoid_hittable.ent`; the original
public/default template is unchanged.

Install `physical_shots.reds` and `physical_trace.reds` together. After the exact
JOINER entity has spawned and been bound:

```lua
local player = Game.GetPlayer()
player:CP2077Encounter_EnablePhysicalShotCapture(true)
-- entity is the exact StaticEntitySystem handle returned for the bound proxy.
print(player:CP2077Encounter_SetPhysicalTraceTarget(entity))
print(player:CP2077Encounter_GetPhysicalTraceStatus()) -- retained reason, count and exact IDs
-- Fire normally. DrainPhysicalShots now also contains physical_trace lines.
player:CP2077Encounter_SetPhysicalTraceTarget(nil) -- stop tracing
player:CP2077Encounter_EnablePhysicalShotCapture(false)
```

The setter only accepts an attached, StaticEntitySystem-managed, tagged, bound
non-NPC target. Each firing callback rechecks the current session scope and exact
binding, rejects origins more than five metres from the local player, then casts
one normalized 100-metre ray with `SyncRaycastByQueryFilter`. The filter combines
the `Static`, `Vehicle`, `PlayerBlocker` and `AI` groups. Adding `AI` selects the
new preset and lets nearer ordinary NPC hitboxes occlude the target. Both
`staticOnly` and `dynamicOnly` are false; a kinematic physics body is not limited
to the static actor category. The nearest physics
result must resolve through Codeware `TraceResult.GetHitEntity` to the exact
local ID and session ID. A wall with no entity handle, another entity, a miss or
a stale mapping cannot be reported as an exact-target hit.

Tag membership materializes `system.GetTagged(expectedTag)` in a local array,
then checks the exact local entity ID in a loop bounded to 256 entries. This is
an experiment bound, not a multiplayer player-count limit.
The installed Codeware 1.18.0 static `IsTagged` implementation only checks that
an entity has any tag, ignoring the supplied tag. The official
[StaticEntitySystem fix](https://github.com/psiberx/cp2077-codeware/commit/613a1cb830ecf33508ffca839d3ea631073504ef)
corrects that behavior. This probe preserves the matched installed runtime and
uses its verified tag-indexed entity collection instead. The dynamic system
used by HOST NPC adoption already checks the requested tag in its 1.18.0 source;
the HOST probe keeps that previously working `IsTagged` call.

A prior nested `ArrayContains(system.GetTags(id), expectedTag)` expression
compiled but failed its fourth live trial on 2026-10-07 at 03:55:10Z. JOINER
crashed during the first projection setup, before any logged bound frame or
physical shot. The native 8-byte equality comparison tried to read an address
equal to the exact target EntityID. That supports investigating argument or
temporary-array handling, but does not prove a specific compiler or Codeware
defect. HOST tag scope also stayed false in this trial. The explicit collection
loop and restored dynamic check compiled at 03:58:48Z. The next two trials
avoided that crash but exposed a separate chained ID-read problem below.
This is separate from the third trial's pending-removal and
same-tick rebinding hazard, which faulted at a different native address.

The sixth trial's retained status localized rejection to exact tag membership:
all 943 bound frames reported expected local ID `10714475`, a one-entry tag
collection, and the wrong chained ID value `1246179402736`. Earlier scope,
attachment, non-NPC and managed-entity guards passed. The implementation now
assigns the indexed tagged entity to a local, assigns `GetEntityID()` to a
separate `EntityID` local, and only then reads `.hash`. Do not collapse these
locals back into `tagged[index].GetEntityID().hash`.

That correction compiled at 04:17:36Z and passed the seventh live tag-gate check:
all 4,740 bound frames accepted their exact local/session IDs, across local
`10714475` / session `4294967298` and replacement local `10715125` / session
`4294967299`. Four real firing callbacks then produced four custom ray results,
but none hit the exact proxy. This verifies target selection and ray execution,
not successful target collision. Exact IDs are process-local.
Sixth-trial evidence and reproducible metrics are in
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-tag-id-diagnostic`.
The retained `CP2077Encounter_GetPhysicalTraceStatus()` string reports each
rejecting gate, tag count and at most eight inspected IDs without weakening
identity checks. Read it immediately after the non-null setter, since clearing
the target deliberately changes the status to `disabled`.

This is a custom geometric hit candidate at the UI-event direction. It does not
prove that native bullets collide with the proxy, model spread/penetration or
projectile travel, apply damage or submit network intent. Occlusion is limited
to the specified groups; glass and other filters need separate validation.
Test torso hit, clear miss, nearer wall, nearer vehicle, nearer NPC, self-occlusion,
movement, rebind and
cleanup before calling this an accepted collision route.

## Source grounding

Reconstructed 2.31 scripts, pinned `a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a`:

- `core/gameplay/prereqs/weapon/weaponShootPrereq.swift:74-107`: vanilla immediate
  listener registration and unregistration on `UI_ActiveWeaponData.ShootEvent`.
- `orphans.swift:55816-55821`: `gameuiWeaponShootParams.fromWorldPosition/forward`.
- `cyberpunk/items/weapon.swift:339-350`: magazine/capacity readback.
- `cyberpunk/player/psm/weaponTransitions.swift:599-627,714-718`: selected firing
  restrictions and safe-scene calculation. Normal unsilenced shooting also
  broadcasts Gunshot twice, so stimulus count alone is unsuitable as shot count.
- Installed Codeware: native `EntityID.hash` and `Reflection.GetTypeOf` support
  exact ID readback and variant-type checks.
- `orphans.swift:27598-27647` and
  `core/systems/spatialQueriesSystem.swift:14-35,52-60`: physics ray/query APIs and
  vanilla `Static`, `Vehicle` and `PlayerBlocker` groups.
- [Codeware TraceResult extension](https://github.com/psiberx/cp2077-codeware/blob/613a1cb/src/App/Physics/TraceResultEx.hpp):
  physics result ID resolves an actual entity handle. This is evidence for the
  intended API, not proof that the new capsule is registered in those queries.
- Installed Codeware `ColliderComponent`, `physicsColliderCapsule`,
  `physicsICollider` and `physicsCustomFilterData` declarations provide the
  kinematic/query-only shape and filter schema.

## Later query and launch evidence

The seventh trial recorded four real JOINER shots with magazine 6 -> 2 and
total ammunition 574 -> 570. All four custom rays hit world geometry with no
entity handle. The fourth ray's center distance was 0.036697 m; the physics
result lay roughly 9.3 m away, behind the proxy at about 4 m. Read-only live
inspection confirmed an enabled, queryable kinematic body at the proxy's exact
transform but query masks 0/0. Its default mass was normalized to 1 by the
engine; no mass change is justified by these observations.

Reproducible metrics and the two CET body inspections are preserved in
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-query-mask-failure`.
A console file-logging attempt failed because `io` was unavailable; successful
readback remains in `JOINER-scripting.log`. It made no game mutations.

The first build-06 launch crashed before any fresh probe initialization or world
load. Its fault address differed from both earlier projection crashes, and the
retained trace belonged to the seventh trial. This does not establish a collider
fault or provide new query evidence. The exact launch and dump are preserved in
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-startup-crash`.

The ninth trial proved a scripted exact-target query against the passive
capsule. Its read-only body inspection at 04:36:36Z found local entity
`10717221`, bound to session entity `4294967300`: preset `NPC Hitbox`, query
masks 0/2, simulation masks 0/0, one enabled shape and a valid queryable
kinematic body at the target transform.

At 04:45:25Z, CET directly called the existing private
`CP2077Encounter_TracePhysicalShot(origin, direction)` method with a ray from
the local player's position plus 1.6 m to the exact proxy's position plus
0.9 m. It returned `exactTarget=true`, matching local `10717221` and session
`4294967300`, at distance-squared 13.508876. A repeat at 04:46:05Z hit the same
entity; an offset direction returned world geometry with `exactTarget=false`,
and an upward ray returned `outcome=miss`.

These console results are explicitly labeled `scripted_query_only`,
`scripted_query_center`, `scripted_query_offset` and `scripted_query_up` in
scripting.log. They retain sequence 0: no `ShootEvent` was injected, no physical
shot was captured, no ammunition was consumed and no damage or network intent
was submitted. This verifies local capsule queryability, exact identity and
these two miss cases. Broader occlusion and movement cases remain unqualified;
the later recreation check is recorded below.

At 04:53:33Z, the ninth trial then recorded a genuine shot: sequence 1,
weapon `10717189`, magazine 6 -> 5 and total ammunition 574 -> 573. The target
had already expired, so the paired trace reported `disabled`. A temporary
native input observer had recorded presses in both Safe (6) and Ready (5)
states. Closely spaced manual input actions finally fired; the earlier Ready
press without a shot means timing/Safe state does not fully explain every
attempt. Input observer callbacks were duplicated and are not a shot counter.
This restores genuine firing evidence for the current scripts but still does
not join that first shot to an exact target hit.

At 04:54:21Z, the second genuine firing callback did reach the replacement
target through the local physics query. Shot sequence 2, weapon `10717189`,
magazine 5 -> 4 and total ammunition 573 -> 572 accompanied a same-callback
trace with `exactTarget=true`: expected and hit local ID `10718584`, expected
and hit session entity `4294967301`. The same frame confirms current tag and
session binding. Hit position was (-1646.666016, -2314.387451, 40.409203), with
distance-squared 13.653147. This qualifies one genuine firing notification to
exact passive-target geometry result. It still does not prove native bullet
collision/damage, spread or penetration, network submission, or synchronized
reaction/death. Those remain separate gates.

F10 recreation at 04:55:11Z completed across two updates 0.104473 seconds apart.
The replacement local ID `10718724` bound at 04:55:12Z to the same session entity
`4294967301`; the old local ID never rebound. Two subsequent genuine shots,
sequence 3 at 04:55:39Z and sequence 4 at 04:55:44Z, both hit the exact new
local/session IDs with magazine 4 -> 3 -> 2. The fourth shot still used the
previous downward aim while the input moved the camera. Sequence 5 at
04:55:52Z used the now-upward direction (forward Z=0.808142), consumed the next
round and returned `outcome=miss`. Thus the current trial has five genuine
shots: three exact proxy query hits, one sky miss and the earlier disabled
trace after target expiry. These results retain the native-damage and
network-authority limitations above.

The ninth trial ended normally with both games and the server closed. The
launcher reported settings restored at 04:57:52.635Z. All 7,094 bound JOINER
frames passed exact tag/mapping checks and no probe errors were recorded.
Final evidence, 39 copied-file hashes and a reproducible analyzer are in
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-query-filter-pass`.
The archived HOST trace is the full continuing fourth-trial process with its
old unscoped hit observer. It does not qualify native HOST damage or death.

At 04:41:11Z, an additional console read reported friendly aim, Stunned and Jam
all false, but also reported `weaponDefined=false`. Those values were taken
with the weapon holstered, so they cannot rule out restrictions at firing time.

## First live firing evidence

At 2026-10-07T03:18:30Z, one genuine HOST firing notification was recorded with
magazine 6 -> 5, total ammunition 574 -> 573 and finite UI origin/direction. Two
native Gunshot broadcasts followed the same shot; the tagged HOST NPC received
both and changed from Relaxed to Combat without losing health. This was one
shot on one PC, not burst-count or bullet-trajectory qualification. Three later
native impacts had a different NPC instigator, so they do not prove the local
player hit the controlled NPC.

The run used the initial observer without `physical_trace.reds` or the new
capsule. F9 cleanup also triggered normal game quickload; the test reset into a
new HOST session. F2 replaces that diagnostic binding in the next private run.

Reproduce this first-run evidence analysis with:

```powershell
python 'D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-shot-observer\analyze.py'
```

That folder retains exact copied HOST/JOINER probes, input hashes, raw traces,
`metrics.json` and `SUMMARY.md`. Both copied script sets match the original
03:13:50Z isolated compile inputs. Do not apply these firing-only results to the
later capsule or trace code without their separate live evidence.

The later physical trace and W-canonicalization code passed isolated compilation
at 2026-10-07T03:35:14Z. The ninth trial separately qualifies three real
firing-to-passive-target queries, as detailed above. Neither pose fixtures nor
scripted rays qualify native damage or synchronized reactions.

## Matched HOST native hit and death evidence

The eleventh launch installed current probes on both roles. At 05:07:14Z, a
genuine HOST shot from local player `1`, weapon `10718342`, reduced magazine
6 -> 5. The exact controlled NPC `10718591` / session entity `4294967296`
received native PreProcess and DealDamages callbacks with matching instigator
and weapon, `syntheticFixture=false`, `projectionPipeline=false` and fixture
request 0. Subsequent readback confirmed health 221.400757 -> 110.067528.
Five later shots missed the moving NPC; no additional health loss was inferred.

At 05:10:44Z, genuine shot sequence 7 hit a fresh controlled NPC `10718799` /
session entity `4294967297`, initially at its full 221.400757 health. After a
normal reload, readbacks and the shot recorded magazine 6 -> 5 and total
ammunition 568 -> 567. The callback's `ammoDecreasedSincePreviousObservation`
was false because the previous firing observation was an empty magazine;
that field alone cannot account for intervening reloads.

The native event order is significant:

| Simulation time | Observation |
| --- | --- |
| 216022.478734 | Genuine firing notification, sequence 7. |
| 216022.503892 | PreProcess and DealDamages callbacks, matching local attacker/weapon; health still reads 221.400757. Final computed value is 399.499512. |
| 216022.530476 | `death_callback`: health 0, persistent-death flag still false. |
| 216022.530476 | `on_died_after_vanilla`: health 0, persistent-death flag true. |
| 216022.588446 | Subsequent readback confirms health 0 and persistent death. |

No synthetic attack or raw-health fixture ran. This proves local HOST native
hit, actual damage and persistent-death observation. It also shows why a future
engine adapter must await observed health/death after application; neither
computed damage nor the first OnDeath callback is a complete result. The
UI firing vector differs slightly from the final native attack vector/origin,
reinforcing that the UI ray is not a complete bullet-trajectory contract.

These are separate local and HOST gates. The experiment still has no reliable
JOINER intent -> HOST validation/application -> authoritative result transport,
nor automatic shared reaction/death presentation. Broader collision and
gameplay qualification remain open. Native evidence and a reproducible analyzer
are archived at
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-host-physical-native`.
That earlier archive contains final eleventh JOINER evidence and a partial
snapshot of HOST before the separate JOINER restart. The full final HOST trace
is retained in the twelfth-trial archive below.

The eleventh JOINER incorrectly used the original idle-only template: its
private installer copied the production adapter without restoring the
experimental `_networkhumanoid_hittable.ent` selection. Queued local pose
commands therefore did not prove visible pose application. Exact copied
adapter bytes preserve the mistake. Build 04 versus build 06 contains no
animation/controller changes, only collider filters and serialization details.
The twelfth private restart corrected template selection and passed the final
local presentation checks. No production default or asset-source change was
needed for this fixture error.

## Final corrected-template and restoration check

The twelfth JOINER produced no physical shots. It independently confirmed three
enabled queryable bodies with the intended `NPC Hitbox` masks 0/2 and zero
simulation masks, plus 1,893 exact tag/session-bound frames and no probe errors.
Root directly observed the held reaction pose, return to idle, death pose and
death pose after local recreation; queued feature values alone are not the
visual proof.

The fresh second lifetime, session entity `4294967298`, is the qualified final
fixture: local `10719874` held the reaction pose from 05:20:46Z to 05:21:02Z,
returned to idle, and staged the local death fixture at 05:21:07Z. The corpse
was visible at 05:21:14Z. Recreation at 05:21:20Z completed across two updates
0.109347 seconds apart. Replacement local `10719913` first bound at 05:21:21Z
already dead, progress 1 and serial 2; the preserved corpse was visible at
05:21:28Z. A first-lifetime recreation overlapping HOST fixture expiry is
excluded. These are local presentation fixtures, not receipt of HOST death.

Final evidence is in
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\live-final-presentation-pass`.
`analyze.py` verifies presentation/lifecycle evidence, while
`analyze_native_host.py` verifies the full continuing HOST's genuine native hit,
actual health loss and persistent death. The ninth trial remains the separate
evidence for three genuine JOINER firing-to-proxy query hits and a real sky miss.

Both games and the test server closed, with launcher settings restored at
05:23:06.523483Z. Private experimental installs were then restored around
05:23:55Z; the restoration manifest is
`D:\Downloads\syncfix\bench-artifacts\20261007-passive-encounter-engine\runtime-restore-20261007T0523537922296Z.json`.
Graphics and all 167 checked save files were preserved. No production package
or runtime cutover was promoted by these experiments. Remaining integration is
reliable intent/result delivery and automatic shared reactions/death, followed
by broader physics and gameplay qualification.
