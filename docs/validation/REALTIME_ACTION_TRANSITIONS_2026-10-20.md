# Action transitions independent of local world time

KyleBuildsAI / Codex, `experiment/local-player-actions-20261018`, draft PR30.
This is a private 0x8005 presentation experiment, not a production v5 change.

## Reproduced problem and fix

Two actual game renderers observed the same synthetic SessionClient participant.
HOST ran at scale1; JOINER ran at a measured scale0.03. The earlier graph used
0.08-second engine Switch blends. Recorded JOINER crouch/aim transitions took
seconds while root position continued tracking. At replay12.6s it was still
mostly standing, lowering through13.6s. The normal HOST was crouched by12.6s.

The graph now consumes bounded Blend2 weights advanced from the existing CET
presentation update clock. Stance, moving crouch and weapon transitions settle
over0.08 real seconds. Previous/current weapon selection stays bounded to two
poses, freezing the departing gait sample. All Switch blend timers are zero;
moving upper-body clips use distance-driven samples. Idle breathing still uses
ordinary animation time. This does not qualify smooth lower-gait retargeting.
Stale presentation immediately clears only this layer's owned overrides.

No body transform, entity identity, inventory, AI, server or protocol changes.
Existing native version, attached actor, exact Igla identity and visibility
checks remain in place. The private isolated action fixture uses the same new
graph inputs. Diagnostics report the loaded action revision and blend weights.

## Recorded before/after evidence

Private bench `20261020-crouch-mask`, `clock01-before-*` / `clock02-after-*`.
The after replay started2026-10-20T08:21:38.4219224Z and ran92 seconds.
Retained diagnostics cover the complete replay: HOST scale1.000000 and JOINER
scale0.030000. Both report `20261020-realtime-actions-1`, with no actor faults.

After correction, both views are already crouched at the12.2s sample. Shoulder
aim and moving-crouch transitions are present by the18.2/24.2s samples, instead
of the earlier seconds-long fade. Reviewed5Hz contacts also cover sprint/stop,
stale neutralization, same-state repair, unsupported/unavailable weapon hiding,
disconnect, rejoin and unarmed moving crouch. The sampled sprint sequence has
no sustained T-pose. This is bounded visual evidence, not a full-frame latency
measurement, physical-input test, WAN result or complete animation qualification.

Original VFR recordings are retained privately: HOST145s/3525 fresh frames
(24.48 mean callback Hz), JOINER160s/3964 (24.90Hz), no capture errors. Requested
60Hz is not achieved game/render FPS. Metadata remains unchanged; contact sheets
are separately derived at5Hz using recorded UTC start offsets.

The scanner UI was active during the comparison. A private TimeSystem reason
provided the controlled slowdown; do not describe it as a natural scanner or
Sandevistan test. Explicit cleanup at08:28:14Z reported the private reason
inactive. Scanner off then restored total scale1.000000, verified in diagnostics
and normal UI. Do not rely on the engine duration argument as a wall-clock guard.

## Validation and installed scope

- Windows experimental67/67 and production-v5 control65/65 CTests passed locally.
- New focused timing regression checks real-clock blend settlement, world-scale
  independence, frozen departing gait, repair stability, stale clearing, bounded
  rapid retargeting and clock discontinuities. Asset checks reject nonzero
  Switch timers, invalid Blend2 bounds and time-driven moving weapon samples.
- Native roundtrip, authored archive inventory and unpacked hashes passed.
- Installed ActionFixture archive SHA256:
  `77799c413af10b7e36138f3c865783f3759a94441610779e22aa4c22ffaa4e51`.
- Corrected crouch/mixed-grip private cache and weapon entity are unchanged from
  the previous checkpoint. Native DLL/server remain the matched9f27bd4 build.

Both games and local server closed normally by08:29:25Z. Launcher finalized
with keep-settings policy; no saved-game restoration or key changes. The stable
v0.0.37 complete package is unchanged. Generated game-derived caches, exports,
raw diagnostics and videos remain private and must not enter Git/releases.

Next: isolated camera-directed upper-body aim rendering, followed by additional
weapon models and directional locomotion/stutter qualification. True pitch/yaw
is captured read-only but is not yet replicated or rendered.
