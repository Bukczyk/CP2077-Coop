# Forward-facing directional legs, private M12 candidate

KyleBuildsAI game-side work after 8755077 on draft PR30. The private 32773
and production-v5 contracts, native DLL/server and default flags are unchanged.

## Defect and correction

The old standing direction bank contains raised combat fists. Copying only nine
lower-body bones removes those fists, but the M11 attempt visibly turns the torso
sideways through the pelvis. Its correct entity yaw and tiny root error did not
detect the defect. Original M11 recordings and failed geometry bakes are retained.

M12 normalizes the four inspected rifle walk clips' hips to the relaxed forward
reference. A two-bone leg solve preserves each original foot path and rotation,
with a fixed 5 mm pelvis drop and stable reference knee poles. The current and
departing direction masks copy only Hips, LeftUpLeg, RightUpLeg, LeftLeg,
RightLeg, LeftFoot, RightFoot, LeftToeBase and RightToeBase. Relaxed spine,
shoulders, arms, hands and head remain the base; the separate weapon layer stays.
No root trajectory, events, AI, collider or world transform is applied by clips.

The existing default-off directional experiment additionally admits coherent,
fresh standing holstered state, zero weapon record and NotAiming. It retains
the supported Igla path and rejects unknown/stale/incoherent state. Crouch uses
its separately qualified forward/backward route. Short holds freeze progress;
real stops select idle. No new production action route is introduced.

## Offline evidence

- Focused unarmed regression fails published 8755077 and passes this candidate.
- Strict graph mutation checks reject Spine, whole-track blending and root motion.
- Windows experimental 75/75 and production-v5 control 73/73 pass sequentially.
- Pure geometry tests cover input isolation, limb lengths, foot rotation/path,
  root preservation, malformed hierarchy, float32 sample times and metadata.
- Native import/export passes 493 dense samples, including interpolated times.
  Maximum foot deviation is 0.001433 m. Events and motion extraction are absent.
- The GLB bake reproduces byte-for-byte. Native archive inventory and unpacked
  payload hashes match. Both matched authored graphs/entities roundtrip cleanly.

The new native payload SHA256 is
548b3068b77a27aec9b9e645447bfa27fb14fda0429c3821c4ced45fd122a634.
Its private archive is 45324ee05569630b7143c1eada56bf71f8ab5af3e5e5e0c080e65f04250d9d8e.
Action archive d2867d233468df9bcdcca12864fea326cd3cd712f6ceaa6945d8e19c7de639aa
and weapon archive b2983821fc5dae12461bd8f4d64ed53c82b2bcc25bda4cdd39be398c11769d89
require the new cache, Lua revision12 and measured strides. The historical old
cache stays separate. Eight private files were installed only after both games
and server stopped; all 11 protected configuration hashes were preserved.

## Recorded local qualification

Paired unarmed-directions and directions replays exercise real SessionClient
traffic in two actual game renderers, with original-frame pose review. M12
completed both full 92-second routes, recorded for 117 seconds in each view.
Original gait-boundary, middle-direction and recovery-tail frames were reviewed.
The visible torso retains forward facing during side steps, holstered arms stay
relaxed and the separate armed pose remains. No sustained T-pose appears in the
visible sampled frames. Crowd occlusions and out-of-view intervals are excluded. Recorder metadata deliberately retains visual_pass=false, with visual review
recorded separately. No physical-input, WAN, terrain or capacity claim follows.

Only authored source is publishable. Private caches, owned-game exports, logs and
videos are excluded. Stable v0.0.37/latest is untouched. See the
[local regeneration recipe](../../experiments/player-locomotion/NORMALIZED_DIRECTION_RECIPE.md).


Unarmed run: HOST 2608 fresh video frames (22.50 callbacks/s), JOINER 2652
(22.88/s). Retained diagnostics contain 405/407 rows and 112/113 fresh unarmed
directional samples covering all four axes. Exact old/new actors are HOST
10825887/10825939 and JOINER 10825830/10825904 after participant 3 leaves and 4 joins.

Armed regression: HOST 2613 frames (22.54/s), JOINER 2593 (22.36/s), with 408/402
retained rows and 124/123 fresh armed direction samples covering all four axes.
Old/new actors are HOST 10826142/10826272 and JOINER 10826064/10826158 for participants
5/6. Both routes have no reported actor faults and root error <=0.000002 m in
retained rows. Both clocks remained 1.0, scanners off. Callback cadence is capture
cadence, not a claim of game FPS or networking throughput.

Exact hand/sight alignment, diagonal/terrain/foot-slip quality and sideways
crouch remain open. This is a bounded local visual qualification of the supported
experimental states, not a claim that multiplayer animation is finished.
