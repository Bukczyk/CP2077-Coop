# Sideways crouch prerequisite, private local fixture

KyleBuildsAI game-side follow-up after 1037814 on draft PR30. Connected crouch
still uses its original forward fallback for sideways motion. This candidate
qualifies two side clips independently before modifying that renderer.

The inspected 71-joint stealth bank contains forward/backward walk, but no
continuous side loops. Its turn/cover transitions are not side-walking cycles.
The player TPP locomotion bank was also inspected earlier: one hacking idle,
152 joints, not a drop-in woman-base replacement.

`lower_side_crouch.py` derives only the inspected rifle `walk_090`/`walk_270`
clips. It first lowers the hips 0.2 m, corrects their orientation, then solves
the remaining drop to the already qualified forward crouch reference. Both
feet retain their source paths and rotations. Reference spine descendants
supply the low upper body and head pose, preventing combat fists and source
spine counter-rotation from entering the isolated clip. Entity/root transforms
are preserved. Native events and motion extraction are explicitly removed.

The first attempt rotated the standing hips before lowering and failed a
right-foot reach check. It is rejected and retained privately. A first native
derivative retained combat upper-body motion and was superseded before install.
The inspected replacement checks head orientation as well as hip/foot geometry.

Windows Release experimental 76/76 and default-v5 control 74/74 pass sequentially.
The authored IK test covers original feet, rotations, segment lengths, root,
input isolation, low hip height and fail-closed native metadata. Fixture tests
cover distinct asset paths, bounded two-direction route, unchanged yaw/height,
no weapon hooks and exact actor removal. Native authored assets roundtrip,
inventory and extracted payload hashes match.

Native import/export passes 138 dense samples: maximum foot deviation 0.000204 m,
reference hip height error 0.0000092 m, hip quaternion error below 3.5e-10 and
head quaternion error below 6e-11. These are local geometric prerequisites.

Private native payload:
`b094c89b89ad5332af9faf8dd25dbd7c597e9cb049e488f2c42c1f54ef51a405`.
Private cache archive:
`b38c26a7cdd0e46f379dbb535e13dc5eacf8108f47901bad6b504ceadb56b7a1`.
Authored isolated fixture archive:
`1e5934d65d50963d371e31ee68542925e0e4b4726f97c02d23eb8b40c7b44ada`.

The separate `crouch-sides` controller tests idle, right, stop, left, stop and
right again at fixed forward heading. `record_action_fixture.py` supports this
route and now gates admission on the actual first PNG, not a buffered frame log.
Five fixture/cache/controller files were installed while both games and server
were stopped. Connected M12 files stayed unchanged; 11 protected hashes match.
Capped private read-only source logs were backed up before starting fresh logs.
No controls, configuration, keys or current saves were reset.

The isolated game test completed all six phases and confirmed exact actor
10828501 detached at 30.0532 seconds. A 60-second recording contains 1367 fresh
frames (23.24 capture callbacks/s), covering the complete fixture through removal.
Twenty-four phase/cleanup samples and full-size right/left frames were reviewed.
They show low side steps with the crouched upper body, without sustained T-posing
or the prior sideways-torso defect in visible sampled footage. The actor is gone
in the post-removal frames. Recorder visual_pass remains false; this separate
record documents bounded visual review. Crowd occlusions are excluded.

No connected, physical-input, WAN, terrain or exact foot-plant/weapon-alignment
claim is made. Generated cache/GLB/native data and
raw recordings/logs remain private. Stable v0.0.37/latest is preserved.


Regeneration uses the pinned M12 tool chain and absolute private paths. Run
`lower_side_crouch.py --source OWNED_RIFLE_GLB --reference LOWERED_STEALTH_GLB
--output NEW_PRIVATE_DIR/side-crouch.glb`. The reference is the qualified native
roundtrip `player_stealth.anims.glb`, SHA256
9224819304cd4d5abe4482d6f4c73da1d5df03cc301d168059ad494add25182a.
Follow the [native import recipe](../../experiments/player-locomotion/NORMALIZED_DIRECTION_RECIPE.md),
selecting only walk_090/walk_270, aliases cp_coop_crouch_side_walk_090/270, and
this module's sanitize_native/compare_paths. Require head orientation agreement
as well as hip/feet. Pack only base/cp2077coop/private/player_crouch_side.anims
in its separate PRIVATE_DO_NOT_DISTRIBUTE_CrouchSideClips archive. The isolated
builder uses --profile crouch-side; the recorder uses --model crouch-sides.
No generated game bytes are part of this source checkpoint.
