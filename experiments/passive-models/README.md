# Passive Judy/Mitch profile experiment

This source-only experiment adds one authored male `Mitch/default` entity beside
the existing `Judy/default` entity, a strict local profile builder and a separate
opt-in CET fixture. The fixture can queue local creation, movement and cleanup;
it has not been installed or tested in Cyberpunk. The existing runtime, Judy
asset, production builders and published packages stay unchanged.

## Supported subset

| Local profile | Entity | Installed resources |
| --- | --- | --- |
| `judy_default` (builder default) | Existing `cp2077coop_networkhumanoid.ent` | Judy default proxy, woman-base rig, female unarmed locomotion set |
| `mitch_default` | New `cp2077coop_networkhumanoid_mitch.ent` | Mitch default proxy, man-base rig, male unarmed locomotion set |

Both use mesh appearance `default` and the unchanged authored
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

Later live gates are both models visible, correct default appearance, idle
without T-pose/deformation, no autonomous AI, exact orientation/readback and
cleanup/recreation without duplicates. Those gates remain unperformed.

The current NPC descriptor does not supply an arbitrary chosen appearance. The
historical comparison establishes only the narrow resource relationship above,
not an invariant record-to-Mitch rule or HOST mapping. Matching a HOST NPC still
requires an agreed supported descriptor and live appearance/color/rendering
qualification. This experiment does not change protocol, ownership or routing.
