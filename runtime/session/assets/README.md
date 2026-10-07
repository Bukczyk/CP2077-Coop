# Experimental passive humanoid assets

This archive is for the opt-in passive NPC projection experiment. It is not a
shared-combat release or a replacement for the default player presentation.

## What is included

- `base\cp2077coop\entities\cp2077coop_networkhumanoid.ent`: pure `entEntity`,
  one `entAnimatedComponent`, and one `entSkinnedMeshComponent`.
- `base\cp2077coop\animations\networkhumanoid_idle.animgraph`: an authored
  Root -> Output -> SkAnim graph requesting the `idle_stand` clip in a loop.

The entity references the installed `woman_base.rig`, Judy proxy mesh, and
`base\animations\npc\gameplay\woman_average\gang\unarmed\wa_gang_unarmed_locomotion_combat.anims`.
The installed clip reports a duration of 4.9000001 seconds and the same rig.
No vanilla clip, mesh, or skeleton binary is bundled. There are no added AI,
NPCPuppet, navigation, hit, or damage components. Root motion, animation events,
gameplay animation variables, and animation commands are disabled.

This is local idle presentation from one selected clip. It does not select the HOST NPC's
appearance or replicate its movement animations, aim, hits, reactions, or death.

## Current evidence

On 2026-10-07, the candidate rendered a non-T-pose skeletal idle pose in a local
HOST/JOINER test. Four saved frames from 02:19:54.248Z to 02:19:58.005Z show small
head and bent-arm pose changes while the projection position and camera remain
visually stationary. This supports visible local idle playback for one entity
over this short sequence. It does not establish a playback rate, completion of
the 4.9-second loop, or animation synchronized with the HOST. See the full test record
in [passive humanoid validation](../../../docs/validation/PASSIVE_NETWORK_HUMANOID.md).

Offline checks converted both JSON resources with WolvenKit 9.0.1, serialized
them back for structural inspection, listed exactly two archive resources, and
unpacked both with byte-identical hashes. A second independent build from the
authored JSON produced identical resource bytes and identical archive bytes
except the pack-time timestamps and their index checksum.

## Rebuild from source

Use Python 3.10+ and the official Windows
[WolvenKit Console 9.0.1 release](https://github.com/WolvenKit/WolvenKit/releases/tag/9.0.1).
Extract `WolvenKit.Console-9.0.1.zip` outside the game and repository. ZIP SHA256:
`364427384c0f4ebb6b157fa9abd01595258af1b7993c7b3a7edd2920f2016e92`.
The builder checks the CLI executable SHA256 and refuses an existing output
directory. It does not install assets or alter source files.

From the repository root, substitute your CLI path and choose a new build folder:

```powershell
python scripts/build-passive-idle-archive.py `
  --entity-json runtime/session/assets/source/raw/base/cp2077coop/entities/CP2077Coop_NetworkHumanoid.ent.json `
  --graph-json runtime/session/assets/source/raw/base/cp2077coop/animations/networkhumanoid_idle.animgraph.json `
  --wolvenkit 'D:\Tools\WolvenKit.Console-9.0.1\WolvenKit.CLI.exe' `
  --output-dir artifacts/passive-idle-rebuild `
  --reference-archive runtime/session/assets/CP2077Coop_Experimental.archive
```

Output: `out/CP2077Coop_Experimental.archive`, `manifest.json`, `build.log`,
resource staging files, and the unpacked verification files. The reference
comparison requires all archive bytes to match except the two entry timestamps
and index CRC. It fails for other changes. Omit `--reference-archive` when
intentionally editing the authored sources, then validate and record the new
candidate before installing it.

WolvenKit 9.0.1's
[ArchiveWriter](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Archive/IO/ArchiveWriter.cs)
uses `DateTime.Now` in each archive entry. Repacking therefore changes the whole
archive SHA256. Do not substitute a rebuilt archive while reporting the original
candidate's hash. The builder records both the real archive SHA256 and a
comparison hash with only these metadata bytes masked. It never rewrites the
archive or treats a comparison hash as the distributable's SHA256.

## Exact candidate hashes

| File | SHA256 |
| --- | --- |
| Checked-in tested archive | `139952bee5243c64c766744a350ab1ae1f4269aa427d20954467311e450b10b3` |
| Entity JSON | `f6485a1cad7ec22905f93abf7f305a460fb12511a60269c938ad0770e884527b` |
| Graph JSON | `e448765251286661ec0e877dbecdd8e96ea26c6d0d97d8184f0992c8a298fcc3` |
| Entity binary | `918e49cd77231e0e98a3e7610582da4ad69a624d96b0c123e6cc645615f225b0` |
| Graph binary | `48ddb9dd89ba32e30fc77ff7b4bcefb2f2062b37ce9b58c683521718a609b0af` |
| CLI executable | `7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738` |
| Archive comparison hash, excluding pack timestamps and index CRC | `5f4982bf90010980f309465867a3d217e66f64a2d76ad7e6e7ea4192f27f0b97` |

The JSON hashes describe the Windows source files used for this trial. Git line
ending conversion can change those text-file hashes without changing their
contents or the generated resource bytes. The binary hashes are exact.

## Playback limits and follow-up

The short sequence establishes visible pose progression, not sustained playback
or a complete loop. Check cycle wrap and continued animation over a longer
stationary recording, with multiple projections, after reconnect, and after
leaving and returning to view. Movement and action animation replication still
require their own implementation and tests.

Schema references: [SkAnim node](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/animAnimNode_SkAnim.cs),
[graph playback fields](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.RED4/Types/Classes/animAnimGraph.cs),
and [Codeware 1.18.0 static entity spawning](https://github.com/psiberx/cp2077-codeware/blob/v1.18.0/src/App/World/StaticEntitySystem.cpp).
These establish declared fields and spawning behavior, not a runtime animation
result.
