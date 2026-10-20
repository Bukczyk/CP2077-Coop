# Connected armed walking direction candidate

KyleBuildsAI / Codex, `experiment/local-player-actions-20261018`, draft PR30.
Private0x8005 loopback candidate. Production-v5, server semantics, actor identity,
cleanup ownership and network body position/yaw are unchanged.

## Behavior and implementation

The default-off `experimentalPlayerDirectionalWalk` option connects the
[qualified directional clips](ISOLATED_DIRECTIONAL_WALK_2026-10-20.md) to the
existing interpolated player renderer. It admits only fresh standing state for
the exact supported Igla record. Body-relative velocity chooses forward/right/
backward/left with hysteresis. Each actor advances gait by measured distance,
blends bounded previous/current directions over80 real milliseconds and freezes
the departing sample. Neither heading nor root position is rewritten to hide
wrong foot movement. Upper-body weapon presentation remains independently layered.

Crouching, unarmed/unsupported weapon, stale state and non-walking phases leave
the new layer. Ordinary unarmed/crouch playback remains on the previous recipe;
the combat bank's raised fists are not substituted for ordinary unarmed walking.
The asset builders require an explicit matching `--directional-walk` option and
the fifth private cache. Default generation remains unchanged. No game-derived
animation bytes, exports or recordings enter Git or public packages.

Revision8 also fixes two hold cases: a long update gap no longer gets one extra
walking frame, and a brief zero-motion sample retains the directional layer
during the existing50ms gait hold. The latter failed a focused regression before
correction and appeared in initial JOINER diagnostic samples. Source7, its
recordings and failure are retained privately. A real stop still exits to idle;
unavailable heading/state cannot admit directional playback.

## Recorded correction and validation

Two actual game renderers observed a synthetic SessionClient JOINER over the
existing loopback session. The replay's `--directions` option uses the original
92s repair/stale/disconnect/rejoin sequence with an armed square route at12..36s.
It uses normal owned snapshots and presentation APIs, with no forged tokens,
packet injection or physical-keyboard claim.

Both games verified `20261020-locomotion-8` and `gaitDirectionEnabled=true` before
`connected-direction02`. HOST145s/3271 fresh frames,22.74 mean callback Hz;
JOINER130s/2976 frames,23.10Hz. Both captures completed without errors. Requested
60Hz is not achieved render FPS. Original VFR metadata is unchanged. Reviewed5Hz
contacts show the four directions, ready/aim poses, stop, stale neutralization,
same-state repair, disconnect, new-player rejoin and armed/unarmed crouch tail.

Each endpoint retained143 standing armed walking samples spanning all directions
with no actor faults or zero-speed directional-weight drops. One actual short
hold on HOST retained its selected direction correctly. Native root readback
maximum error was0.000002m in both views. Each recorded19 stale samples with
owned overrides neutralized and direction weight0. Each had66 crouch samples
with direction weight0, preserving the previously corrected low crouch recipe.

Exact actor identities remained distinct:

- HOST player3 actor10811406, rejoined player4 actor10811545.
- JOINER player3 actor10811349, rejoined player4 actor10811432.

Old actors disappear in reviewed disconnect samples; the new actors return
crouched without a duplicate. This is bounded local synthetic-input evidence,
not physical player-input latency, WAN, arbitrary weapon/appearance support,
diagonal-quality, fast sideways sprint or terrain/foot-contact qualification.
Lower-gait phase transitions and exact sight/hand alignment remain open.

Windows experimental70/70 and production-v5 control68/68 passed after the hold
correction. Focused tests cover body-relative axes, stride rates, diagonal noise,
bounded real-time retargeting, short/long gaps and guarded fallback, without
mutating the input body transform. Asset tests reject mixed direction profiles,
wrong aliases, nonzero engine blend timers and unsafe graph/body changes. Native
action/weapon roundtrips, inventories and unpacked resource hashes passed.

## Installed private candidate

- Action archive `e3350b070677577edd8b04a0e06bea3e1972478791a7b3bfaaa8d9ffc35d3d48`.
- Weapon archive `414efd0277a62e4d8bd896244c5b35714fc12d53518f6d5eca983d28b34cd158`.
- Existing private crouch/mixed cacheee83b803 and separate direction cachecb21e90a
  remain unchanged. Native DLL/server remain the matched9f27bd4/private0x8005 build.

Both stopped-game installs preserved11 protected control/configuration/settings
hashes and current saves. The private configuration gained only the new opt-in
flag. Stablev0.0.37/latest and the v5 VPS are unchanged; this is not a release.
Both games currently remain open for the next bounded validation. Controlled
clock-dilation qualification of this new direction layer is still pending.
