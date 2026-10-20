# Recorded four-direction walking prerequisite

KyleBuildsAI / Codex, `experiment/local-player-actions-20261018`, draft PR30.
This is an isolated asset/engine test. It does not change the connected player
renderer, protocol, server, entity ownership or production capacity.

`build_direction_fixture.py` authors separate entity/graph paths, using the
validated full Judy component/deformation/facial/hair/clothing setup. It references
a uniquely aliased private2.31 unarmed-combat animation bank. Forward, right,
backward and left clips use the same71-joint game rig. All animation root motion,
events and gameplay commands are disabled. Graph selection and progress retain
the existing native wiring/safety checks, with no world-time blend timer.

The private fixture traverses a fixed6m square at1.2m/s with heading0rad/+Y
throughout, using measured metres/cycle: forward5.960565090179443;
right5.90962028503418; backward1.6499662399291992; left1.7075181007385254.
It idles before/after, then removes only its exact owned actor. Its six phases
last30s. This tests clip selection and stride playback, not real player input.

## Evidence and rejected view

Native authored entity/graph roundtrip, exact inventory and unpacked hashes pass.
The separate private cache preserves native buffers and aliases. A native GLB
export contains all six selected animations;31 samples per clip show plausible
pelvis/foot heights and no large coordinate excursion.

`direction01-automated` captured60s/1490 fresh frames,25.27 mean callback Hz,
with all phase receipts and exact actor10809373 removed. Its camera settled too
low on the stairs; actor/feet were not adequately visible. It is retained as an
inconclusive viewing setup, with no directional quality pass.

The corrected explicit observer placement uses(-810,817.5,24.4042), yaw0, once.
It rejects an occupied HOST location. There is no repeated teleport to hold the
camera. `direction02-automated` captured60s/1562 fresh frames,26.47Hz, no capture
errors, all six phase receipts, and exact actor10809347 removed. The sequence was
requested2026-10-20T09:04:28.891478Z. Reviewed5Hz contacts show distinct forward,
sideways and backward steps with fixed body heading. One foreground ambient NPC
obscures early right-walk samples; later right-walk samples are clear. This is
bounded visible evidence, not continuous foot-contact/sliding qualification.
Original metadata is unchanged and all videos/logs/game-derived exports remain
private. UTC request/phase-observation times support reproducible frame offsets.

These are combat locomotion clips and visibly raise the unarmed actor's fists.
Do not replace all ordinary unarmed walking with this whole-body bank. The next
connected experiment must preserve the qualified crouch/weapon layers and
ordinary unarmed behavior, selecting suitable lower-body direction separately.
Diagonal blends, corner transitions and terrain need additional qualification.

## Validation and installation

Windows experimental69/69 and default-v5 control67/67 tests passed. Focused tests
cover exact cache/alias/skeleton/graph checks, fixed bounded route and heading,
observer placement/rejection, input bounds and exact asynchronous cleanup.

- Authored archive `CP2077Coop_DirectionFixture.archive`:
  `8d64688104301e5bca47fac9e1c843d8bbcbb30ada1d4091b6fd532126569817`.
- PRIVATE direction cache:
  `cb21e90abe20952f11801e3fa76b34a61532370c537823c23e0f8961ba2741a1`.

The cache builder outputs a generic ActionClips archive name. For this isolated
test it MUST be installed as `PRIVATE_DO_NOT_DISTRIBUTE_DirectionClips.archive`;
its unique resource is `base\cp2077coop\private\player_directional.anims`.
Do not overwrite the existing corrected-crouch/mixed weapon cache. Existing
action8e9079ab, weapon8eff9157, private action-cacheee83b803 and matched9f27bd4
DLL/server are unchanged. Stopped-game installs verified11 protected hashes.
Stablev0.0.37/latest and production-v5 VPS remain unchanged; no new release.
