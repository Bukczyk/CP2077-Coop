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
uniquely named `CP2077PassiveModelFixture_CurrentAppearance` helper on `Entity`
returns the engine's current appearance name as a String and changes nothing.
Without that helper, appearance readback stays unverified and movement is blocked.
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

Each slot pins its profile, generation, original creator system, opaque exact
EntityID and first observed exact handle. Creation is considered complete only after
the original creator returns that actor attached, managed, spawned and not
spawning. Nil/unknown flags do not qualify. Cleanup never cancels an in-flight
static spawn: a late callback remains owned and can then be retired. Never-ready
or unknown native outcomes remain held. Cleanup needs completed creation and
confirmed absence from the creator, global lookup and retained handle before
the slot can be reused. No population-wide delete or fallback actor is used.

The common tag inventory permits this instance's known IDs, including pending
tokens, but blocks unknown historical actors after reload. **Stop all slots and
wait until every status is `closed` before unloading.** `onShutdown` queues
cleanup only; there may be no later update to execute it. A blocked historical
actor is not automatically adopted or deleted by a replacement fixture.

`submittedTarget` records the native command target. `observed.pose` comes from
the actual actor. `placementVerified` requires fresh matching readback within
5 cm and 0.02 radians, the exact template, the expected `entEntity` root and an
observed current appearance name exactly equal to the requested `default`.
A call returning does not prove placement. Observation failure clears current
readback and qualification. Wrong template/root or missing/wrong appearance
blocks movement but still permits safe retirement of the exact owned actor.
`requestedAppearance` is `default`; `observedAppearance` records the name actually
read and `appearanceVerified` requires exact equality. Empty, `None`, non-string,
missing or throwing readback cannot qualify. The final actor returned immediately
before movement is checked again; a contradicted preflight clears cached
qualification. A requested name does not guarantee that the native getter will
return it, and no appearance mutation or fallback is used to force a match.
`visualQualified` always remains false. The name alone proves neither mesh
quality nor animation. No network descriptor or HOST appearance is inferred.

State transitions emit structured diagnostic lines with slot, profile,
generation, exact ID, submitted/requested/actual pose, template and actual
appearance evidence. A changed observed name is logged even if the mismatch
state remains the same. Logging is limited to 64 lines per fixture instance;
unchanged frames stay silent. Status remains available after that limit. See
[FIXTURE_VALIDATION.md](FIXTURE_VALIDATION.md) for offline evidence and limits.

## Remaining live gates

Later live gates are both models visible, correct default appearance, idle
without T-pose/deformation, no autonomous AI, exact orientation/readback and
cleanup/recreation without duplicates. Those gates remain unperformed.

The current NPC descriptor does not supply an arbitrary chosen appearance. No
reliable invariant record-to-Mitch mapping was established here. Matching a HOST
NPC requires an agreed supported descriptor and demonstrated record/appearance
mapping. This experiment does not change protocol, entity ownership or routing.
