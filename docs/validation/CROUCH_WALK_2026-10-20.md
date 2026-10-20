# Crouch-walk correction, private local candidate

KyleBuildsAI / Codex owns this game-side investigation on
`experiment/local-player-actions-20261018`, draft PR30. Starting source2c82941,
matched private0x8005 runtime9f27bd4. No main merge, protocol change, VPS change,
public package or WAN qualification. Generated animation data stays private.

## Recorded diagnosis

Two actual local game renderers recorded the extended synthetic SessionClient
replay. The new last phase is unarmed crouch-walking, separate from armed aiming.
It remains a synthetic participant, not physical player input or a WAN test.
Both recordings passed capture timing checks: HOST130s/2961 fresh frames,
JOINER145s/3341. Actual fresh callback rates were22.96/23.20Hz, not60fps.

A separate crouched weapon mask that excluded all four spine bones preserved
the low torso but pointed the crouched weapon/aim too far down. That mask-only
candidate was rejected and the original authored graph restored. Its recordings,
builder and install backup are retained privately. Do not repeat it as a fix.

The original stealth `walk_0` pelvis is0.7938..0.8481m high, while the selected
idle crouch is0.4237..0.4377m. The visible rise is therefore not solely a missed
stance flag. These are installed-game clip measurements, not remote root error.

## Current candidate and tests

`experiments/player-locomotion/lower_crouch_walk.py` lowers the moving pelvis
by0.25m and solves both two-bone legs back to their original foot trajectories
and orientations. It retains the moving cycle; no stationary-pose sliding,
network XYZ offset, root-motion application, NPC AI or gameplay is introduced.
Only recipe code and synthetic tests belong in Git. The GLB/anims/cache do not.

The private GLB native import/export comparison at101 frames measured maximum
foot displacement0.000152927m, quaternion orientation error1.68e-8, and pelvis
reduction0.249995..0.250011m. Native animation buffers survived the subsequent
event/root-extraction sanitization unchanged. Both aliases retain the71-joint
woman_base rig. Exact three-resource cache inventory and unpacked hashes passed.
These checks do not prove visual success.

The original graph is00f60e82168db1475519e7787a090fbfcae5c0070908104b5566605874625aa6.
Corrected PRIVATE cache is11f4b99033ecc9bc9a7e7700beb8547cb7412f7828a07e7bc108a39fc76dc298.
Both games were closed for installation. All11 protected settings/keys/config
hashes matched. DLL, server, weapon entity, controls and saves were unchanged.

Synthetic IK tests check feet/orientation/segment lengths under different headings
and pelvis heights, reject unreachable targets and invalid drops, and verify
native events/root extraction are removed without altering pose buffers.
The replay now lasts92s and includes unarmed crouch-walk after reconnect.

## Recorded corrected candidate

The second two-window run completed. HOST130s/2953 fresh frames and
JOINER145s/3267 passed timing checks (22.96/22.71 fresh callback Hz).
Both views show the deeper moving knee bend in armed and unarmed crouch.
The original graph retained its previous ready/aim direction instead of the
mask-only candidate's downward weapon tilt. Reviewed contacts include30 frames
at5Hz for armed crouch-walk in each view,30 unarmed JOINER frames, and30 sprint
frames in each view. No sustained T-pose was seen in those sampled sprint frames.
The walk remains a synthetic SessionClient participant rendered in two actual
games; physical crouch-walking input and WAN quality are not newly qualified.

Player3 owned one actor per game, then rejoined as Player4 with replacement
actors. HOST had28 armed crouch-walk samples and27 unarmed; JOINER28/28.
Both had19 stale action samples while the same Player3 actor kept moving
(HOST2.700439m, JOINER2.825683m), followed by recovery. Maximum observed root
error was0 at six-decimal diagnostic precision, not zero skeletal/network latency.
Foot locking is also separately checked through the native clip roundtrip above.

Windows experimental65/65 and default-v5 control63/63 pass. The next work is
dual-barrel-shotgun grip, camera aim direction, other models and directional/
stutter qualification. Exact fingers/sight alignment is not claimed fixed.

Private evidence root:
`G:\Projects\CP2077-Coop\bench-artifacts\20261020-crouch-mask`.
Use `mask01-*`, `lowered01/manifest.json`, native-foot-validation.json and the
two independent install manifests. The accepted recordings are `low01-*` and
`low01-evidence/analysis.json`; the mask-only recordings remain rejected.
Do not upload these generated assets/logs.

## Native import reproducibility

WolvenKit9.0.1 CLI defaults glTF import to Mesh and does not initialize game
archives for its import task. Import as Anims with the installed rig available.
The private automation helper uses the pinned unmodified libraries to initialize
game archives and call `ModTools.ImportAnims`. No vendor patch was made.
After import, serialize the native cache, call `sanitize_native`, deserialize,
roundtrip, and verify pose buffers/inventory/hashes before a stopped-game install.

Primary implementation references:
[import task](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.Modkit/RED4/Tasks/ImportTask.cs),
[animation importer](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.Modkit/RED4/Tools/AnimationTools.cs),
[typed import arguments](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.Common/Model/Arguments/ImportArgs.cs).
