# Local connected player actions: recorded game evidence

Owner: KyleBuildsAI / Codex. Local date 2026-10-19; test UTC
2026-10-20T04:28:52Z through 04:51:24Z. Branch
`experiment/local-player-actions-20261018`, draft PR30 stacked on PR29.
Installed experimental runtime source is
`9f27bd4e17cc52cdac9bb3636489f04a7ee079c2` in both games and the local server.
This follow-up adds test tooling and evidence, not a replacement game DLL.

## What passed in the actual game

Two Cyberpunk 2077 2.31 instances used the matched private 0x8005 runtime and
the existing local session `lifecycle-20261006`. No v5 VPS or main was changed.

- Actual HOST input -> actual JOINER rendering was recorded in the preceding
  `connected-actions01` run: crouch, Igla equip, aim, stand and lower weapon.
- Actual JOINER input -> actual HOST rendering was recorded in `reverse01`:
  crouch, equip the captured Igla Pimp, aim, stand, lower and holster. Source
  blackboard/attached-slot observations and received presentation values agree.
  Holster uses the existing saved B binding, verified in UserSettings and mappings.
- Actual JOINER reconnect used the existing CET UI. PlayerId2 left and PlayerId3
  joined the same session1. HOST restored the current crouch/Igla state. The exact
  old engine actor10798908 was attached before and no longer defined afterward,
  checked with a retained, roundtrip-verified native EntityID. Its replacement
  was10799464. A later real source holster also reached the new actor.
- An additional **synthetic loopback JOINER**, using SessionClient, tested the
  same game renderer in both real games. This is separate from real player input.
  It exercised crouch-walk/aim, sprint, stop, unavailable/unsupported state,
  presentation expiry/repair, disconnect and readmission. It used PlayerIds6/7.
- During the synthetic action gap, ordinary owned movement continued. On HOST,
  the same actor10800090 had19 stale samples and moved2.766846m while stale;
  JOINER's same actor10800710 had20 and moved2.872131m. Owned weapon/aim inputs
  neutralized and the gun hid. Full repair restored revision6 on those same
  actors. Missing presentation did not retire or freeze their bodies.
- Both final fixture videos finalized without capture errors: HOST135.021s /
  3680 frames /27.55 mean fresh callbacks/s; JOINER120.022s /3338 /28.00.
  Requested60fps is not achieved recording cadence or a measured game frame rate.
  No sustained T-pose was observed in30 sprint frames sampled at5Hz. This is
  bounded visual evidence, not certification of every animation transition.

The synthetic fixture adds one participant to the two real local clients. This
does not establish a physical multi-PC result, WAN behavior or live capacity.
Root readback error was0 at the diagnostic's six-decimal precision. It does not
measure skeletal pose, foot contact, grip, frame pacing or animation latency.

## What is still not good enough

- Crouch-walking looks too upright compared with stationary crouch. The current
  `wa_gang_unarmed_locomotion_stealth` walk clip needs pose selection/height
  investigation. The received crouch state and selected crouch-motion input are
  present; that alone is not satisfactory visual posture.
- Sprint clips play in the sampled test, but residual sliding/stutter, turning,
  directional locomotion and gait phase require longer recorded checks. The
  fixture moves laterally with a fixed facing and sharp test-route reversals;
  it cannot qualify natural forward running or precise foot planting.
- Logical aim selects a raised pose. Camera pitch, matching sight/shot direction
  and exact finger grip remain unqualified. No claim of accurate ADS alignment.
- Only the inspected Igla Pimp model/recipe is supported. Overture and other
  records are explicit unsupported states and hide the cosmetic gun. No substitute
  weapon is presented as a match. Other models/attachments still need work.
- The render model remains a full Judy placeholder, not another player's V.
  Production presentation contract remains proposed in PR18; 0x8005 is private.
  Private game-derived clip caches prevent distributing this fixture as a public
  complete package. Stable v0.0.37 remains unchanged.

## Automation changes and failure records

`coop_player_action_replay` is built only with both replay and experimental
presentation options ON. It is a bounded86-second loopback-only JOINER. It uses
the existing client API, explicit session name and private key-file input; no
engine access, input injection, HOST impersonation or new protocol messages.
Its six-second gap omits Tick/repairs while continuing SendLocalSnapshot. The
gap is below the client's existing10-second timeout. It disconnects, waits,
reconnects under a new membership and finally leaves. No backend semantics change.

Example after both local games are loaded and the cameras are deliberately
placed for this fixture. Do not use these coordinates as a production spawn rule:

```powershell
build/presentation-local/Release/coop_player_action_replay.exe `
  --key-file '<private local server access.key>' --session '<actual local room>' `
  --origin '-814.5,821.5,24.393097,-3.141592653589793'
```

For the final recording, HOST was placed once at(-811,817.5,24.4042), yaw18.4349;
JOINER at(-815,817.5,24.4042), yaw-18.4349. The fixture moves3m along X. Source
players are never held with repeated teleports. Existing graphics/controls remain.

- First fixture admission used the old `first-test` WAN room and correctly failed
  MissingSession. No backend fault. The tool now requires an explicit session name.
- Fixture02 reached the server and renderer but was outside the camera for part
  of the run. Its trace is retained; the visual acceptance repeat is fixture03.
- Suspending the actual JOINER for3.801s interrupted movement too. The proxy was
  removed/recreated, so this did not isolate presentation expiry. Its source
  video has a genuine3.784s frame gap and remains a failed capture-quality result.
- The older recorder incorrectly included initial capture startup in its maximum
  inter-frame gap. It now reports startup separately, rejects startup>10s, and
  continues rejecting actual inter-frame gaps>2s or early/missing frames. A
  reconnect source video with2.705s startup has1.056s maximum actual frame gap;
  a separate timing reassessment passes without rewriting the original failure.
  A different20.993s-startup attempt remains rejected.

## Source ownership and validation

KyleBuildsAI owns this follow-up's `tools/player_action_replay.cpp`,
`tools/record_game_window.py`, `tests/player_action_replay_tests.py`,
`tests/player_replay_evidence_tests.py`, the scoped root/tests CMake additions
and this validation record. No engine/source/state contract ownership transfer.
Installed Lua, DLLs, assets, INIs and keys were not changed in this follow-up.

CLI tests reject malformed/non-finite/out-of-range origins, missing/unknown
options, missing/invalid session names, and prove validation runs without reading
credentials or connecting. Recording regressions distinguish startup, actual
stalls, early closure and missing frames. Full Windows experimental64 and default
v5 control62 checks are recorded in the private evidence directory; consult the
current PR CI for hosted Windows/Debian/sanitizer results for this follow-up.

Private evidence, outside Git/packages:
`G:\Projects\CP2077-Coop\bench-artifacts\20261019-connected-actions`.
Use `recording-manifest.json`, `final-evidence/analysis.json`, exact-actor cleanup
readbacks, `reverse01-*`, `reconnect01-*`, `fixture03-*` and timing reassessments.
State, sprint and expiry contact sheets were manually reviewed. The preceding
HOST-to-JOINER evidence is under `20261018-player-actions/connected-actions01-*`.
No recordings, private key or game animation bytes are committed.

Both games closed normally after recording. The launcher finished and stopped
its local server. Development configuration and current saves were preserved;
no settings rollback or old-save restoration was performed.

Next game-side action: inspect a genuinely low crouch-walk clip and qualify the
moving posture, then exact weapon-family poses/grips, camera-directed aim and
direction-aware locomotion. Keep the private candidate separate from production
while Bukczyk reviews the persistent-state contract.
