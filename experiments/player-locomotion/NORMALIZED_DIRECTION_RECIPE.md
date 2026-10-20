# Private forward-facing direction cache

This builds owned-game animation derivatives locally. Commit only these authored
tools and instructions. Do not distribute GLB exports, native `.anims`, private
archives or raw recordings. The cache is a prerequisite for the default-off
direction experiment, not a multiplayer release.

## Inputs and pinned tools

- Inspected Cyberpunk 2.31 woman-base rig, 71 joints.
- WolvenKit 9.0.1 CLI executable SHA256
  `7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738`.
- Locally exported `wa_gang_rifle_locomotion_combat.anims.glb`, SHA256
  `72c8529394b429d372d907b49b2bb4c7ccab6d1a0046284daaf464cd4889568c`.
- Locally exported `wa_gang_unarmed_locomotion_relaxed.anims.glb`, SHA256
  `3cb77fa83f670a682cf5a8e6e65a599bcfea4c7ac282fca5c159463480a6c521`.
- Python, .NET SDK 6.0.428 and installed .NET runtime 10.0.13 for the inspected
  WolvenKit assemblies. The helper uses net6 reference assemblies and runtime10,
  with no native apphost. Do not retarget to net10 with an SDK6 compiler.

Use absolute paths and new private output directories outside all Git checkouts.
Names below are parameters, not literal machine paths.

## Bake and import

1. Run `normalize_directional_walk.py --source SOURCE_GLB --reference RELAXED_GLB
   --output NEW_PRIVATE_DIR/neutral-direction.glb`. Read its validation sidecar.
   Four aliases are emitted: `cp_coop_directional_neutral_walk_0`, `...walk_090`,
   `...walk_180` and `...walk_270`. No other clips are admitted. The fixed 5 mm
   pelvis drop and reference knee poles preserve both original foot paths and
   rotations while the hips follow the relaxed forward reference.
2. Serialize the owned rifle native set with WolvenKit. Select exactly its
   `walk_0`, `walk_090`, `walk_180`, `walk_270` entries in that order. Rename their
   native animation names to the four aliases. Pass the resulting document
   through `normalize_directional_walk.sanitize_native(document)` and deserialize
   the returned document to a private `player_directional_neutral.anims` seed.
   Keep the original input untouched. This step strips events and root extraction.
3. Build `ImportAnimation.csproj` in Release with both its output and intermediate
   paths in a new private directory. The inspected build had zero warnings/errors.
   Run `dotnet ABSOLUTE_HELPER_DLL ABSOLUTE_WOLVENKIT_FOLDER ABSOLUTE_GAME_EXE
   ABSOLUTE_BAKED_GLB ABSOLUTE_PRIVATE_NATIVE_SEED`. Require four updated clips,
   zero new clips, zero old clips kept, and `ANIMATION_IMPORT_RESULT=True`.
4. Serialize the imported native set again, apply `sanitize_native` again, and
   deserialize that returned document. Import/export can restore native metadata;
   stripping it only before import is insufficient. Serialize once more and
   verify exact aliases, 71 joints, no events and no motion extraction.

## Independent native check and packing

Export the final native file back to GLB with the same owned woman-base rig.
Call `compare_paths(source_glb, reference_glb, native_export_glb)`. Require every
clip's maximum foot error below 0.005 m, foot quaternion error below 0.0001 and
reference hip quaternion error below 0.0001. It checks 493 dense samples including
interpolation between baked keys. Key-only agreement is insufficient.

The inspected M12 roundtrip produced maximum foot error 0.001433 m. Its final
native payload SHA256 is
`548b3068b77a27aec9b9e645447bfa27fb14fda0429c3821c4ced45fd122a634`.
The deterministic GLB bake reproduced
`762218162011e5d36816c2f390ba3e4c2ef8098da72b28da3a024b819e5e7d9c`.
These numbers qualify that input/tool combination, not other game versions.

Pack exactly `base\cp2077coop\private\player_directional_neutral.anims` under
`PRIVATE_DO_NOT_DISTRIBUTE_NeutralDirectionClips.archive`. List its inventory,
unpack it and compare the native payload hash. Keep the old direction cache
separate for the historical isolated fixture. Record source/tool/cache hashes.

Rebuild BOTH action and weapon fixtures with `--directional-walk` and the same
`shotgundual` weapon profile, plus the action builder's `--aim-fixture`. Install
those matched graphs/entities, this new cache and Lua revision12 only while both
games and the local server are stopped. Preserve config, controls and saves.
The four Lua stride values must match the new source, not the old combat bank:
6.495526791, 1.481725335, 1.593894124, 1.495220900 metres per clip.

## Game acceptance

Run paired `unarmed-directions` and `directions` recordings with fresh diagnostics
in both real games. Inspect visible torso facing, relaxed hands versus the
separate armed pose, feet, stop blends, crouch tail, stale repair and exact cleanup.
Entity yaw and root error alone cannot detect a sideways skeleton. Keep rejected
clips and footage. Synthetic SessionClient traffic is not physical-input or WAN
qualification. See the linked validation record for the actual observed outcome.
