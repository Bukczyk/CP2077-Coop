# Passive Judy/Mitch profile experiment

This source-only experiment adds one authored male `Mitch/default` entity beside
the existing `Judy/default` entity. It provides a strict local profile builder;
it does not select, spawn or install either profile in the game. The existing
runtime, Judy asset, production builders and published packages stay unchanged.

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

## Next separate game-side task

After source review, add an opt-in local fixture under `experiments/passive-models/`
that selects a profile explicitly before spawn and pins it for that entity's
lifetime. Reuse the reviewed exact-ID, pending-spawn, retained-handle and
retirement rules. Unknown/missing assets must spawn nothing. Keep production
`npc_static_population.lua` unchanged until the separate fixture is qualified.

Later live gates are both models visible, correct default appearance, idle
without T-pose/deformation, no autonomous AI, exact orientation/readback and
cleanup/recreation without duplicates. Those gates remain unperformed.

The current NPC descriptor does not supply an arbitrary chosen appearance. No
reliable invariant record-to-Mitch mapping was established here. Matching a HOST
NPC requires an agreed supported descriptor and demonstrated record/appearance
mapping. This experiment does not change protocol, entity ownership or routing.
