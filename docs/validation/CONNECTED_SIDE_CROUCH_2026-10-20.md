# Connected sideways crouch, private M13 candidate

KyleBuildsAI game-side follow-up after fb1e60e, draft PR30. Requires the existing
default-off directional experiment, matched action/weapon graphs and the separate
qualified side-crouch cache. Production v5, private 32773 routing, native runtime,
backend/VPS and default flags are unchanged.

The earlier renderer chose forward/backward crouch only. Sideways movement used
the forward clip and its stride, so the visual steps did not match lateral travel.
M13 selects four body-relative crouch axes with score hysteresis. Right and left
use the separately recorded low side clips and their measured 1.481725335 /
1.495220900 m strides. Forward/backward keep the existing 6.249844074 /
3.992504835 m clips. The body transform and facing remain network-owned.

The side layer copies only the nine qualified lower-body bones over the existing
forward/backward crouch. A previous/current two-clip blend runs over 80 real
milliseconds, freezing the departing sample. Short holds and real stops preserve
the sampled moving feet while the crouch-motion layer settles to idle. Stale,
invalid-heading, jump, teleport and long-gap states clear the side weight.
Per-actor state stays independent; the default renderer is unchanged.

Six read-only fields expose crouch direction, side, previous side, blend, weight
and frozen progress. No source timestamp, aim-angle message or network schema is
added. The private replay/paired runner adds `crouch-sides`: unarmed right, stop,
aimed left, stop and armed out/back, then existing expiry/repair/rejoin tails.

The focused side regression fails fb1e60e and passes M13. Four rotated body-axis
routes, measured strides, held stops, frozen reversal, real-clock blend and
invalid/default guards pass. Existing standing, gait, forward/backward crouch and
strict graph safety tests pass. Windows experimental 77/77 and default-v5 control
75/75 pass sequentially. Both native authored archives roundtrip, exact inventory
and extracted hashes match. Generated caches remain private.

Private action archive:
`5ecfef42bacd83e69d226d20732a3e1a8478988b1101d165b4fbe6e01056f64e`.
Private weapon archive:
`4d24d4662ecbd3faa03bba9df8b36ee23532118eea8ff0c94cffc8e8af75ade5`.
Existing side cache:
`b38c26a7cdd0e46f379dbb535e13dc5eacf8108f47901bad6b504ceadb56b7a1`.

Ten matched files were installed only with both games/server stopped. Exact
backups and installed hashes were checked; 11 protected configuration hashes
were preserved. Capped private source logs were retained before refreshing them.
Controls, graphics, keys, current saves and native DLL/server are unchanged.
The stable v0.0.37/latest package is separate and untouched.

Four full 92-second local SessionClient routes were recorded for 117 seconds
in BOTH real game renderers. Original-frame movement boundaries, middle poses
and expiry/repair/disconnect/rejoin/crouch tails were reviewed. They retain low
sideways poses, appropriate armed/unarmed upper body and correct torso facing.
No sustained T-pose appears in visible sampled frames. Forward/backward crouch
and standing walk/sprint/stop regressions also retain expected poses. Crowd
occlusions/out-of-view intervals are excluded. Recorder visual_pass remains false;
separate private review records document these bounded observations.

| Route | Clocks HOST/JOINER | Retained complete rows H/J | Fresh video frames H/J |
| --- | --- | --- | --- |
| Side crouch | 1 / 1 | 406 / 408 | 2716 / 2733 |
| Side crouch, slow world | 1 / 0.03 | 409 / 406 | 2692 / 2748 |
| Forward/backward crouch | 1 / 1 | 410 / 405 | 2954 / 2961 |
| Standing walk/sprint/stop | 1 / 1 | 409 / 406 | 2931 / 2938 |

All four runs report no actor faults and root readback error <=0.000002 m in
retained complete rows. Capture callbacks span 23.18..25.49/s; these are not game
FPS or network-throughput claims. Side runs retain 168/169 and 169/168 fully
weighted side samples respectively, with both directions and armed/holstered
states. Explicit stop windows contain 9..10 samples each with exactly constant
moving progress. Forward/back stops likewise hold their own progress, with side
weight zero. Partial copied log lines are excluded from these complete-row counts.

Exact old/new actors after each disconnect/rejoin:

- Side normal: HOST 10830438/10830465; JOINER 10830342/10830376.
- Side slow: HOST 10830701/10830725; JOINER 10830534/10830535.
- Forward/backward: HOST 10831010/10831063; JOINER 10830671/10830704.
- Standing gaits: HOST 10831249/10831285; JOINER 10830821/10830873.

The JOINER private clock was explicitly removed at 2026-10-20T14:13:35Z.
Actual engine readback was active=false, scale=1. Both later regressions ran at
normal speed. Scanners stayed off. Native side-clip loop endpoint positions
agree within 0.001 mm; normalized standing forward has an 0.084 mm endpoint
seam. This rules out a large native loop discontinuity for the inspected files,
not all visual foot slip.

These are synthetic connected state tests, not physical keyboard/mouse or WAN
qualification. Terrain, diagonal transitions, exact foot planting, sight/grip
alignment, other weapons/appearances and action/source-time association remain
open. No production contract or backend change is included.
