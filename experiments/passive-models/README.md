# Passive Judy/Mitch profile experiment

This source-only experiment adds one authored male `Mitch/default` entity beside
the existing `Judy/default` entity, a strict local profile builder and a separate
opt-in CET fixture. The fixture can queue local creation, movement, cleanup and
explicit encounter reaction/death presentation and supplied life baselines;
it has not been installed or tested in Cyberpunk. The existing runtime, Judy
asset, production builders and published packages stay unchanged.
An additional private encounter-profile builder prepares a separate Mitch asset
for the existing idle/impact/death graph. Encounter presentation requires explicit
encounter profiles and separately staged shared modules. The original idle
profiles remain idle-only; no production activation or package changes occur.

## Supported subset

| Local profile | Entity | Installed resources |
| --- | --- | --- |
| `judy_default` (builder default) | Existing `cp2077coop_networkhumanoid.ent` | Judy default proxy, woman-base rig, female unarmed locomotion set |
| `mitch_default` | New `cp2077coop_networkhumanoid_mitch.ent` | Mitch default proxy, man-base rig, male unarmed locomotion set |

These idle profiles use mesh appearance `default` and the unchanged authored
`base\cp2077coop\animations\networkhumanoid_idle.animgraph`. The profile names
are local experiment labels, not network values or arbitrary NPC identities.

`build_profile.py` contains the full resource allowlist. It checks the exact
mesh, rig and single animset in both template and compiled components. It also
checks the exact resolved-dependency table, including path representation,
ordering and flags. Only after those checks does a temporary canonical copy
reuse the unchanged Judy validator for passive structure, bindings, transforms,
draw mask, template/compiled parity and idle graph safety. Unknown profiles or
appearance overrides fail instead of falling back to another character.

The dependency table follows the reviewed existing source and WolvenKit 9.0.1
roundtrip: mesh, authored graph, animset, each a `Soft` string resource. The rig
is separately checked as an explicit animated-component import. The table is
not an inventory of all transitive resources. The manifest lists the installed
rig dependency as well. The graph source is pinned by SHA256 after LF newline
normalization so both Git LF and Windows CRLF checkouts validate identically.

The male source differs from the project's existing authored minimal entity
only in those three component resource paths and the two corresponding table
entries. Local component labels remain identical, including the historic
`CP2077Coop_NetworkHumanoid_JudyMesh` label; that label is not a model selector or
network identity. No vanilla entity template, mesh, animation or rig payload is
copied into this source. There is no `NPCPuppet`, template inheritance, AI,
navigation, damage or collision component.

## Encounter asset prerequisite

`build_encounter_profile.py` uses the existing Judy encounter entity or the new
`cp2077coop_networkhumanoid_mitch_encounter.ent.json`. Its explicit
`judy_default`/`mitch_default` labels select build inputs only. The separate
fixture names `judy_encounter`/`mitch_encounter` below explicitly select the built
encounter entities. Idle builder defaults, production selection and the
historical appearance comparison remain unchanged.

The Mitch encounter entity references the reviewed Mitch proxy, `man_base.rig`
and three male animation sets: `ma_gang_unarmed_locomotion_combat.anims`,
`ma_gang_unarmed_reaction_ranged_impact.anims` and
`ma_gang_unarmed_reaction_ranged_death.anims`. Read-only game 2.31 metadata reports
the same named clips used by the existing encounter graph:
`idle_stand`, `impact_stand_front_torso_l` (about 0.4667 s) and
`death_front_torso_l_idle` (about 1.9333 s). This establishes resource/rig/clip
compatibility, not male deformation or playback quality.

The graph remains the unchanged authored
`base\cp2077coop\animations\networkhumanoid_encounter.animgraph`, with phase
0/1/2 and normalized hit/death progress. Root motion and event dispatch remain
disabled. The added entity remains `entEntity` with animated, skinned-mesh and
animation-controller components only. It has no inherited NPC/AI, collider,
native damage handling or ragdoll. Physical hit detection is a separate task.

Validation checks exact profile mesh, rig, three ordered animation sets and
resource flags in both template/compiled copies, plus the exact ordered
dependency table. A temporary canonical copy substitutes only those already
checked profile references and invokes the unchanged Judy encounter validator.
Its complete `Data` must also equal the hash-pinned reviewed Judy source after
resolving valid equivalent handle forms. That pins controller type/enabled
binding/masks and all other non-profile fields, not just matching component
copies. Conflicting, ambiguous, missing or cyclic handles fail; identical
repeated definitions and valid WolvenKit references remain accepted. LF and CRLF
checkouts have the same content pins. The old production validators are not
modified or monkeypatched.

```powershell
python tests/passive_model_encounter_asset_tests.py
python experiments/passive-models/build_encounter_profile.py --profile mitch_default `
  --wolvenkit 'D:\tools\WolvenKit.Console-9.0.1\WolvenKit.CLI.exe' `
  --output-dir 'D:\private-builds\mitch-encounter-new'
```

Use the pinned official WolvenKit Console 9.0.1 and a new private output folder.
The default build profile remains Judy. The archive contains **one authored
entity only**. The unchanged encounter graph is an external authored prerequisite;
mesh, rig and animation files are external installed dependencies. The builder
does not bundle the graph or any proprietary game payload. It verifies actual
roundtrip data, archive listing, unpacked bytes and unchanged input files, and
refuses existing output folders. These partial archives are not installation
packages and are not added to `game-files/latest` or release downloads.

Both private profiles built successfully. The new Judy entity bytes exactly
match the earlier encounter build; pack timestamps make whole-archive equality
a different question. Existing Judy, idle, hittable and graph sources remain
unchanged. The opt-in fixture below queues exact-generation local presentation
on the update thread. Submission is not visible playback. It does not connect
combat, networking or shared interfaces. See
[FIXTURE_VALIDATION.md](FIXTURE_VALIDATION.md) for hashes and offline evidence.

## Defeated sampled-pose asset prerequisite

The same builder accepts explicit `--presentation defeated_hold`. It builds a
separate Judy or Mitch entity and a separate authored
`networkhumanoid_defeated_hold.animgraph`. Omitting that argument retains the
existing `encounter` build and its one-entity archive. The asset checkpoint
preserved `PROFILES`, fixture commands, runtime selectors and shared state.
The asset checkpoint did not activate a runtime profile. The separate local
life-baseline fixture below now uses these assets through explicit same-family
body replacement; they are not directly selectable by `start`.

```powershell
python tests/passive_model_defeated_asset_tests.py
python experiments/passive-models/build_encounter_profile.py --profile mitch_default `
  --presentation defeated_hold `
  --wolvenkit 'D:\tools\WolvenKit.Console-9.0.1\WolvenKit.CLI.exe' `
  --output-dir 'D:\private-builds\mitch-defeated-new'
```

Use a fresh private output directory. The archive contains exactly two authored
resources: `cp2077coop_networkhumanoid_mitch_defeated.ent` (or
`cp2077coop_networkhumanoid_defeated.ent` for Judy) and the new graph. It does not
overwrite the existing encounter resources or contain vanilla payloads.

The graph exposes `cp_coop_defeated_progress` as a normalized **0..1** input with
initial/default value **0**. Root/output nodes lead to a sampled `SkFrameAnim`
node for `defeated_loop_01`; its progress link points to the initialized input
node. There is no clock, automatic looping, phase/death alias, root-motion
application, animation event dispatch, gameplay feature or extra database.
Default zero is an initial sample, not a claim that a useful pose renders.

The source keeps the existing passive three-component `entEntity` structure
and exact default mesh/rig for each model. It uses one unconditional animation
set: `wa_gang_unarmed_reaction_defeated.anims` under the female gameplay folder,
or `ma_gang_unarmed_reaction_defeated.anims` under the male folder. Read-only game
2.31 metadata confirms matching woman/man-base rigs and a `defeated_loop_01`
duration of **10.3000002 seconds** with no motion-extraction object in either
clip. That metadata does not establish rendered parity or playback behavior.
The ordered dependency table is mesh, graph, animation set; the rig remains an
explicit component import. No NPC root, template inheritance, AI or collider is
introduced. Defeated is not treated as Dead or Unconscious.

Validation compares the entire allowed entity/graph data, including explicit
WolvenKit 9.0.1 defaults, and then reuses the unchanged existing passive validator
on a private canonical entity. Graph validation additionally preserves handle
alias relationships: equal copied nodes cannot replace the nodes actually
initialized. Consistent handle renumbering and equivalent definition/reference
forms remain valid. Unexpected defaults, ambiguous handles, cross-profile
resources, template/compiled disagreement and inherited payloads fail closed.
Both actual compiled roundtrips, exact archive lists and extracted-resource
hashes passed. All existing asset/controller/runtime source bytes are preserved.

This builder remains an asset prerequisite only. The local baseline fixture
below separately drives the normalized input and retains nonlethal Defeated.
Entry/recovery animations, automatic looping, live continuity/rendering and
authoritative integration remain unimplemented or unqualified. Nothing is installed,
activated or added to published game packages by this build.

## Resource evidence and limits

Read-only inspection of installed Cyberpunk 2077 2.31 resources on 2026-10-15
verified:

- `mitch_default.mesh` exposes mesh appearance `default` and 18 named bones.
  All 18 names exist in `man_base.rig`, which has 71 named bones.
- The vanilla Mitch entity's default appearance maps to this proxy, and its
  root animated component names that male rig. Its vanilla entity is an
  `NPCPuppet` with AI components, so it is deliberately not inherited.
- `ma_gang_unarmed_locomotion_combat.anims` declares the same male rig and
  includes `idle_stand` (about 4.9 seconds). The existing authored idle graph
  selects that clip by name without adding a vanilla graph.

This verifies references and bone-name compatibility, not bind-pose matrices,
deformation, actual playback or visual matching. The coarse proxy does not have
named hand/finger/foot/facial bones. It is not a finished Remote V model or
evidence of weapon, ADS, face or equipment fidelity.

Private audit metadata and build evidence are recorded under
`bench-artifacts/20261015-passive-model-audit` outside the repository. Vanilla
resources were decoded in memory during the audit; only paths, hashes and
metadata summaries were saved. See [VALIDATION.md](VALIDATION.md).

## Offline build

Use Python 3 and the pinned official WolvenKit Console 9.0.1. Run from the
repository root, substituting your verified CLI and a new private output path:

```powershell
python tests/passive_model_profile_tests.py
python experiments/passive-models/build_profile.py --profile mitch_default `
  --wolvenkit 'D:\tools\WolvenKit.Console-9.0.1\WolvenKit.CLI.exe' `
  --output-dir 'D:\private-builds\mitch-profile-01'
```

The builder validates source, compiles one entity, serializes it back to JSON,
validates that roundtrip, packs the archive, requires exactly one listed
resource, unpacks it and compares its bytes. It refuses an existing output
directory and checks that source inputs did not change during the build.

The result is a private partial experiment archive, not a complete installation
package. It contains only the authored entity. The already-authored idle graph
is an explicit external dependency, and the vanilla mesh/rig/animset remain
external installed resources. Do not replace a tested runtime/package with it.
No automatic activation, game-file write or installation command is provided.

## Opt-in local fixture

`init.lua`, `engine.lua` and `fixture.lua` form a separate CET experiment, with
the read-only appearance helper in `engine_hooks.reds`. They are not loaded by
the production mod. Loading this entrypoint only registers
callbacks. There are no hotkeys, default spawns, network calls or automatic
movement. All engine reads and mutations run inside `onUpdate`; the public
methods only validate/copy commands or return copied cached status.

A future manual test requires Codeware, CET, both reviewed authored entities,
the authored idle graph and the installed vanilla dependencies listed above.
Stage this experiment's `engine_hooks.reds` separately under `r6/scripts` and
confirm successful REDscript compilation before using the CET fixture. Its
uniquely named `CP2077PassiveModelFixture_CurrentVisualState` helper on `Entity`
returns a coherent current appearance/color pair and exact native CName hash
strings. It double-reads the CNames and checks the original native actor/player,
IDs, attachment and global lookup before/after. The separate read-only
`CP2077PassiveModelFixture_OwnedIdentity` helper verifies the original native
actor without depending on cosmetic getters. Neither helper changes state.
Use matching Lua and REDscript files; unavailable identity or coherent readback
cannot qualify movement.
The runtime presence check is not an archive hash or visual-quality check. Use
the builder's verified outputs and manifest; do not install unreviewed assets.
No installation or package changes are made by this source change.

After separately approved manual installation as a CET mod named
`PassiveModelFixture`, the console API is:

```lua
local f = GetMod("PassiveModelFixture")
-- Define judyPoint and mitchPoint from observed clear positions near the player.
-- Each is {x=<world x>, y=<world y>, z=<world z>, yaw=<radians>}.
local okJ, generationJ = f.start("judy", "judy_default", judyPoint)
local okM, generationM = f.start("mitch", "mitch_default", mitchPoint)
f.status("judy") -- cached actual observation; inspect after game updates
f.status()       -- all slots, copied so callers cannot mutate ownership
-- Only after this exact generation reports ready:
f.move("judy", generationJ, observedNearbyTarget)
f.stop("judy")   -- queues retirement of only this fixture-owned actor
f.reset()        -- queues retirement of every slot in this fixture instance
```

Choose points from the current loaded scene. Creation requires an attached
player, explicit unpaused state, a point
1 to 15 metres away and a vertical difference of at most 3 metres. A movement
step is at most 5 metres and must stay within 20 metres of the current player.
Yaw is in radians, between minus pi and pi. Readback retains all quaternion
components; the input deliberately supports yaw only. There are eight named
diagnostic slots, a local resource budget unrelated to multiplayer capacity.

Each slot pins its profile, generation, original creator system and native player,
opaque exact EntityID and first observed exact actor handle. Native comparisons
accept fresh CET wrappers for the same object and reject a different native
object reusing its ID. Creation is considered complete only after
the original creator returns that actor attached, managed, spawned and not
spawning. Nil/unknown flags do not qualify. Cleanup never cancels an in-flight
static spawn: a late callback remains owned and can then be retired. Never-ready
or unknown native outcomes remain held. Cleanup needs completed creation and
confirmed absence from the creator, global lookup and retained handle before
the slot can be reused. Before removal, exact native identity is read again.
Unknown identity blocks mutation until verified. A positively foreign actor
produces a sticky ownership fault: this instance neither deletes it nor reuses
the slot, even if later lookup/absence appears normal. That fault requires
separate investigation, with no automatic recovery/adoption. A removal attempt
is issued only once, including a false or throwing return; actual disappearance
must be observed. No population-wide delete or fallback actor is used.

The common tag inventory permits this instance's known IDs, including pending
tokens, but blocks unknown historical actors after reload. **Stop all slots and
wait until every status is `closed` before unloading.** `onShutdown` queues
cleanup only; there may be no later update to execute it. A blocked historical
actor is not automatically adopted or deleted by a replacement fixture.

`submittedTarget` records the native command target. `observed.pose` comes from
the actual actor. `placementVerified` requires fresh matching readback within
5 cm and 0.02 radians, the exact template, the expected `entEntity` root and an
observed current appearance name exactly equal to the requested `default`, from
a coherent pair whose original native identity was verified.
A call returning does not prove placement. Observation failure clears current
readback and qualification. Wrong template/root or missing/wrong appearance
blocks movement but still permits safe retirement when the separate exact-actor
identity check succeeds. A changed original player blocks visual/movement
qualification, but a valid current player context can still retire the exact
original actor. Cosmetic failure does not become an ownership failure.

`requestedAppearance` is `default`; `observedAppearance` and
`observedAppearanceHash` record actual engine values. `observedColor` and
`observedColorHash` record the current color variant. Hashes are canonical native
Uint64 decimal strings, never Lua numbers or parsed debug text.
`visualStateObserved` and `colorObserved` require a coherent validated tuple;
`appearanceVerified` also requires exact `default` equality.

Observed `None`, an empty readable symbol and a zero CName hash are preserved,
distinct from missing/throwing getters. `appearanceNameAvailable` and
`colorNameAvailable` report whether a readable symbol was present. An empty or
`None` appearance cannot satisfy `default`, while a coherently observed color
remains evidence only. **`colorMatchVerified=false` always:** no supported color
rule, HOST mapping or color application is implemented. Missing/malformed color
rejects the joint sample and cannot qualify the appearance/default movement gate.

The final mutation actor is checked again against the original native reference
and coherent pair. Changed appearance/hash or color/hash rejects the move and
clears cached qualification. This checks temporal consistency, not similarity to
another NPC. No appearance/color mutation or fallback forces a match.
`visualQualified` always remains false. The name alone proves neither mesh
quality nor animation. No network descriptor or HOST appearance is inferred.

State transitions emit structured diagnostic lines with slot, profile,
generation, exact ID, submitted/requested/actual pose, template and actual
appearance/color evidence and identity status. Changed names or hashes are
logged even if the state stays the same. Logging is limited to 64 lines per instance;
unchanged frames stay silent. Status remains available after that limit. See
[FIXTURE_VALIDATION.md](FIXTURE_VALIDATION.md) for offline evidence and limits.

## Opt-in local encounter presentation

The explicit fixture profiles `judy_encounter` and `mitch_encounter` use
`cp2077coop_networkhumanoid_encounter.ent` and
`cp2077coop_networkhumanoid_mitch_encounter.ent`, respectively. They require the
reviewed encounter graph plus their mesh, rig and all three idle/impact/death
animation sets. All seven resource dependencies must be present before creation.
The runtime check proves presence only. It cannot attest override bytes or
rendered animation.

For a later authorized manual installation, stage this layout under the separate
CET mod `PassiveModelFixture`. Copy the two shared files unchanged from this
same revision, with the reviewed `restore` method included:

```text
PassiveModelFixture/
  init.lua                         <- experiments/passive-models/init.lua
  engine.lua                       <- experiments/passive-models/engine.lua
  fixture.lua                      <- experiments/passive-models/fixture.lua
  comparison.lua                   <- experiments/passive-models/comparison.lua
  cp2077_passive_encounter/
    presentation.lua               <- experiments/shared-encounter/presentation.lua
    presentation_state.lua         <- experiments/shared-encounter/presentation_state.lua
```

Also stage the existing matching read-only `engine_hooks.reds` and reviewed
authored assets as described above. No source copies are duplicated in the
repository and no files have been installed. The explicit slash paths are
intentional: CET resolves `require` relative to this mod root and does not turn
dotted names into folders, as defined in
[CET v1.37.1 LuaSandbox.cpp](https://github.com/maximegmd/CyberEngineTweaks/blob/v1.37.1/src/scripting/LuaSandbox.cpp#L381-L405).
No `package` library or other mod's module cache is
required. Missing shared modules reject encounter start. Idle profiles do not
load these modules or submit encounter setters.

```lua
local f = GetMod("PassiveModelFixture")
local ok, generation = f.start("male_test", "mitch_encounter", observedClearPoint)
-- Wait for status("male_test").state == "ready", then explicitly request:
f.present("male_test", generation, "reaction")
f.status("male_test")
-- Optional terminal presentation on that same logical slot:
f.present("male_test", generation, "death")
```

`present` validates cached state and queues at most one pending command per slot;
it does not access the engine. Only `reaction` and `death` are accepted. Death
supersedes a pending reaction and is terminal as soon as it is admitted, even
if stop/reset happens before the next update. Stale generations, unready bodies,
queued movement and idle profiles cannot receive presentation commands. Command
and body counters stop at 2,147,483,647 rather than lose exact identity.

Each logical encounter slot reuses its own instance of the existing shared
presentation state controller. It has an independent effective clock, driven by
finite update deltas in [0, 0.25] seconds. Invalid/long deltas, pause, missing
context or failed actor/preflight checks freeze that slot; a sibling can keep
progressing. Zero delta may sample without advancing. A successful or unchanged
sample credits the current delta for the next update. This avoids counting
unobserved failure intervals as animation time.

The existing shared adapter submits normalized progress followed by phase.
Before **each** native setter, the engine rechecks the original native actor and
player, exact ID/generation binding, attachment, creator readiness, template,
passive root, coherent appearance/color and explicit unpaused loaded context.
It does not authorize a replacement merely because its EntityID is the same.
Stop, a newer command, or lost context between setters blocks the remaining
setter. An exception can still leave a partial pair. The next valid update may
retry only the latest desired normalized sample with fresh checks; a later
death supersedes the old reaction. No delivery receipt or native pose readback
is invented.

Stop/reset retire bodies through the existing exact cleanup. They retain the
logical slot's profile, serial and terminal death within this fixture instance.
Explicitly recreating the **same** closed encounter slot uses a new body
generation: known death submits the final death sample immediately, while a
previous nonlethal reaction settles to idle without replay. A fresh command
queued for the replacement is not consumed by restoration. This does not prove
that a rendered idle flash is absent before the first setter arrives.
The retained profile cannot be changed for that logical slot. Use a different
available slot for a fresh life; the local eight-slot budget is unchanged.
Mod reload loses this in-memory logical state, and historical tagged actors
still block unsafe reuse. This is not network reconnect restoration or a HOST
life-state source.

Copied `status.presentation` separates `pending`, retained `desired`, last
attempted `sample`, and native submission details. `forwarded` counts attempted
native setters, including a throwing call. `submission` is
`queued_not_observed` or `failed_or_partial`; it is not an animation result.
`reason` describes current processing and `preflightError` preserves a current
bounded failure separately from the last submission reason. A failed preflight
does not erase the last attempted sample or imply another submission. Transition
logs include these distinctions under the existing 64-line limit, without
per-frame progress spam. **`animationObserved=false`, `visualQualified=false`
and `colorMatchVerified=false` remain unconditional.**

The historical `compare` API remains restricted to its reviewed idle-profile
resource chains. Encounter profiles are not silently added to that mapping.
This fixture does not detect hits, change health, create NPC AI, replicate
combat, apply HOST state or generate ragdoll. Its fixed front-torso clips are
local presentation probes, not arbitrary replicated NPC reactions.

## Supplied Alive, Defeated and Dead baselines

`baseline(slot, generation, life, progress)` is an explicit local fixture
command. It supplies a final presentation state, **not health, damage, HOST
approval or a network message**. Start with `judy_encounter` or
`mitch_encounter`; idle profiles remain unsupported for this command.

| `life` | Required `progress` | Desired presentation |
| --- | --- | --- |
| `"alive"` | Omit | Existing encounter body, final idle; no old hit replay |
| `"defeated"` | Finite number from 0 to 1 | Same-family defeated body, explicitly held normalized sample |
| `"dead"` | Omit | Existing encounter body, final death sample; terminal |

```lua
local f = GetMod("PassiveModelFixture")
local s = f.status("judy") -- previously started judy_encounter slot
f.baseline("judy", s.generation, "defeated", 0.35)
-- Inspect status and wait for the replacement to become ready.
-- Always obtain its current generation before the next command.
s = f.status("judy")
f.baseline("judy", s.generation, "alive") -- supplied baseline, no recovery animation
```

Build and manually stage the matched encounter and defeated assets for each
model used, including both authored graphs. The earlier builder commands create
private partial archives, not complete installation packages. The CET module
layout and matching read-only helper are unchanged. This source checkpoint does
not install or start the fixture and does not connect a production descriptor.

Switching to or from Defeated requires replacing the body because the authored
graphs are separate. The old body's template, exact actor reference, creator and
EntityID remain pinned throughout cleanup. The fixture submits exact retirement
at most once and waits for confirmed absence before reserving a new generation.
It never spawns a replacement beside a still-owned or uncertain old actor. The
latest supplied baseline wins while cleanup is pending, so an obsolete
intermediate body is not created. Use the current retiring generation for such
updates; once replacement begins, the old generation is stale.

Automatic replacement preserves the original native local player and exact
player ID. Fresh Lua wrappers are accepted; a different native player, changed
ID or unknown identity blocks creation. Definite pre-call failure, including
pause, missing context or missing resources, leaves `spawn_deferred` and can
retry fresh preflight later. Once a native spawn was attempted, an unknown
outcome is retained and is never automatically retried. Cleanup remains
available independently of cosmetic or continuation-context failure.

Explicit `stop`, `reset` or shutdown cancels automatic recreation, including a
deferred unsubmitted spawn. A later baseline cannot rearm a stopped slot.
Creation checks the current slot and desired body again after its final context
getter. A synchronous preparation callback that stops/resets the fixture or
supplies a different life-state body prevents the obsolete native spawn. The
update retains cancellation or the newer transition instead of closing it by
mistake. An already attempted native spawn remains owned through cleanup.
The supplied life/sample remains in the logical slot; an explicit same-family
`start` after confirmed closure restores it on a new generation. Explicit
manual restart may establish a new local-player context. Model family cannot
change for a retained logical slot. Shutdown is queue-only; stop and observe
closure before unloading because a later update is not guaranteed.

Dead is terminal for that logical slot. Neither Alive nor Defeated can resurrect
it. The existing `present(..., "death")` command enters the same terminal life
immediately, even before its transient clip is submitted. A supplied Dead
baseline supersedes that pending/in-progress clip and selects its final sample.
Repeating an already supplied Dead baseline is idempotent. Reactions are accepted
only for a ready Alive encounter body. Defeated is distinct from Dead and
Unconscious; no engine gameplay predicate or recovery authority is inferred.

A Defeated sample uses only `cp_coop_defeated_progress`, with fresh exact
actor/player/creator/template/appearance/color and unpaused context checks before
the native setter. Invalid update deltas and unknown context block submission.
There is no elapsed-time loop or entry/recovery animation. Failed/uncertain
setter submission can retry only the newest supplied normalized sample after
fresh checks. Successful submission is cached per body/serial to avoid per-frame
spam; it is not a native receipt or observed pose. Alive/Dead continue to reuse
the existing shared controller and adapter without modifying their semantics.

Copied `status.presentation` distinguishes `life`, held `progress`,
`logicalProfile`, `desiredProfile`, `transition`, `baselinePending` and
`finalDeadBaseline` from the current physical `status.profile`, body generation
and last attempted sample. The shared controller's `desired` snapshot describes
its encounter state only; Defeated is deliberately retained outside that
Alive/Dead-only controller. Bounded transition logs report supplied life and
body transition. `animationObserved`, `visualQualified` and `colorMatchVerified`
remain false. Appearance comparison remains limited to the earlier idle subset.

This route establishes only source-tested local state/lifetime behavior. Body
replacement may produce a visible gap, standing/default-frame flash or abrupt
pose change. Rendering, floor contact, blending, held/loop continuity and actual
nonlethal gameplay behavior remain unqualified until live testing. No native
health, damage, AI, physics, backend or protocol state changes occur.

## Compare historical NPC and fixture observations

`compare(slot, generation, sourceStatus)` is a pure report, available through
this existing fixture API. Supply a copied status from the separate
`CP2077NpcAppearanceObservation` experiment (PR27) and an explicitly chosen
existing fixture slot. It never selects/spawns a profile, changes readiness,
queues work, logs, queries the engine or changes either actor.

```lua
local f = GetMod("PassiveModelFixture")
local probe = GetMod("CP2077NpcAppearanceObservation")
local selected = f.status("judy") -- slot already started and observed
local source = probe.status("example") -- an explicitly requested NPC capture
local report = f.compare("judy", selected.generation, source)
```

The result distinguishes:

- `candidate_resource_match`: the reported source tuple follows the reviewed
  resource chain for this explicit target profile.
- `different_profile`: the reviewed source chain points to the other profile.
- `unsupported_source`: a complete source tuple does not have a reviewed chain.
- `unknown`: source evidence or the exact ready target lifetime is unavailable.
- `invalid_input`: malformed evidence, stale format or contradictory fields.

A stale slot generation returns `unknown` with `stale_generation`. Stop,
movement submission, shutdown or a failed target observation immediately prevents
comparison qualification through the existing cached state. This is not a new
movement/spawn permission check. The fixture permits read-only observation while
paused; this report does not certify that the game is currently unpaused.

The reviewed game 2.31 chains are deliberately narrow:

| Source record and template | Actual source appearance | Reviewed `.app` entry / proxy | Explicit target profile / appearance |
| --- | --- | --- | --- |
| `Character.Judy`, `base\quest\secondary_characters\judy.ent` | `judy_default` | `judy.app/default`, `judy_default.mesh` | `judy_default` / `default` |
| `Character.Mitch`, `base\quest\tertiary_characters\mitch.ent` | `mitch_default` | `mitch.app/default`, `mitch_default.mesh` | `mitch_default` / `default` |

Record alone, requested appearance alone, or direct source/target name equality
cannot establish that chain. Source and target EntityIDs intentionally differ.
The report requires exact record/template/appearance hashes and the target's
coherent native identity, expected authored template, passive root and observed
`default` appearance. Duplicated target status fields must agree.

`comparison.lua` embeds the audited template/appearance-resource SHA256s and
computed decimal identifiers. Constants follow pinned RED4ext SDK
`ad7277714ad30d6885d7050c5ba24fa0102f6920`: `CName.hpp` uses FNV1a64 and
`ResourcePath.hpp` sanitizes paths before hashing. These canonical lowercase,
backslash paths are unchanged by sanitization; both source template hashes also
match the extracted metadata. SHA256 evidence, resource-path hashes and CName
hashes are separate domains. No proprietary asset payload is included.

Missing readable source symbols remain empty in `source.observed`. Exact known
hashes can still identify a reviewed chain; canonical labels appear separately
under `resourceChain`. Unknown hashes remain unsupported. Known name/hash or
path/hash contradictions fail. Observed `None`/zero remains distinct from a
missing color read. `colorObservedEqual` compares both the raw color name and
hash, but **`colorMatchVerified=false` and `visualQualified=false` always**.
Neither equality nor a candidate chain proves materials, clothing, facial
features, deformation, equipment or animation look the same.

All results are **historical reports**, not authenticated or simultaneous
captures. Source scope/ticket/frame and target slot/generation/entity are copied;
the fixture has no target capture frame, so none is invented. Scope is not a
network epoch. A caller can retain, edit or fabricate a plain source table;
shape validation is not authentication. This API cannot detect a later source
reset, mod reload, reconnect, appearance change, world unload or newer sample
from an old supplied copy. Get a fresh source status/capture for each manual
comparison. Even then `sourceAuthenticated`, `freshnessVerified`,
`simultaneousCapture` and `resourceBytesVerified` remain false. The report does
not attest which asset override bytes are currently loaded. Returned evidence
is copied, bounded and read-only with respect to both input objects.

## Remaining live gates

Later live gates are both models visible, correct default appearance, idle and
encounter playback without T-pose/deformation, no autonomous AI, exact
orientation/readback, normalized sampling/terminal transitions and
cleanup/recreation without duplicates or visible idle flash. Those gates remain
unperformed.

The current NPC descriptor does not supply an arbitrary chosen appearance. The
historical comparison establishes only the narrow resource relationship above,
not an invariant record-to-Mitch rule or HOST mapping. Matching a HOST NPC still
requires an agreed supported descriptor and live appearance/color/rendering
qualification. This experiment does not change protocol, ownership or routing.
