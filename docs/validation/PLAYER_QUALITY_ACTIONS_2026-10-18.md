# Player quality and action synchronization follow-up

Owner: KyleBuildsAI. Branch `fix/local-sync-presentation-20261018`, draft #29.
Starting source `cfdba0d4826bf94ac1f19ae873cab7c7b6ba5f68`. UTC follow-up
2026-10-19. The complete crouch/weapon/aim objective is still open.

## Model and movement changes

The earlier renderer references the simplified Judy proxy mesh. The optional
`--model full` profile instead authors a pure entity with separate installed
clothed Judy mesh references, supporting deformation/facial/hair/pants rigs,
explicit bindings and full LOD settings. It contains no NPC AI, navigation,
collision or gameplay component. Only our entity and graph enter the archive.

The first full-detail candidate passed native validation but visibly deformed.
It omitted supporting deformation rigs. Full-detail build 03 preserves those
rigs and the stock root name together; the experiment does not isolate which
individual change is necessary. Failed recordings are retained privately.

Locomotion revision `20261018-locomotion-6` filters gait selection with
walk/sprint hysteresis, holds short zero-motion gaps, and settles a higher-ledge
landing or resets after a discontinuous source correction. Network/body XYZ is
unchanged. These are cosmetic heuristics, not replicated action or ground state.
Focused regressions cover jitter, stop bounds, takeoff/apex, higher landing and
teleports. The private observer is placed once, offset from the old shared
spawn spot. No repeated player teleport or control remapping is used.

## Test record

- Windows Release: 55/55 CTests after full-detail and gait changes. Five focused
  suites also passed after adding bounded diagnostic-rotation retention.
- Full build 03: native serialization, roundtrip validation, exact two-resource
  inventory and extracted hash parity passed. Archive SHA256:
  `829a1539058179ae936ed585465365fd15f26434b1578ffaaa40bc4a3c6d9720`.
- Both actual game copies loaded revision 6. The 00:03 UTC automatic recording
  showed a normally shaped clothed actor, walking/sprinting, airborne poses,
  landing and arms-down idle. The current log rotated mid-run, so its first
  diagnostics were absent from that capture. That run remains a reporting fail.
- The runner now copies at most three bounded CET rotations and the current
  log, records hashes and checks exact participant/timestamps as before. The
  00:06 UTC repeat admitted replay player 4, collected 301 fresh samples through
  the end of the route and measured maximum root error 0.000004 m. Capture and
  transport passed. Visual review is recorded separately; root error does not
  measure skeletal lag or packet latency.
- Repeat frame review again shows a normally shaped actor in walk/sprint/jump,
  landing and neutral idle, without the rejected candidate's spiky deformation.
  Residual stutter has not yet received complete acceptance, and none of these
  clips demonstrates synchronized crouch, held weapons or aiming.

These runs use two real games and an additional synthetic production
SessionClient on loopback. The replay is not a human sprint, WAN test, capacity
benchmark or proof of synchronized action state. Capture requests 60 FPS;
actual fresh callback cadence is recorded independently. Raw game captures,
native assets, access keys, settings and saves remain private.

## Crouch, weapon and aim boundary

V5 movement carries transform/time only. #18 is a proposed persistent
presentation contract, not an implemented route. Do not overload movement or
opaque GameplayIntent/Result messages. Existing NPC stance/equipment fixtures
do not prove application on this pure entity. Logical aim capture does not
prove visible aiming or sight alignment.

The pinned RED4ext SDK `ad7277714ad30d6885d7050c5ba24fa0102f6920`
stores a TweakDBID hash/length plus cache-offset bytes. Equality ignores the
offset; uint64 conversion preserves it. A native SDK probe produced equal
records with raw values 113697797098 and 6211609690957853674 by changing only
the offset. This is ABI evidence, not an observed disagreement between live
weapon samples. Canonical semantic identity needs contract review before
implementation. Finding posted on [#18](https://github.com/Bukczyk/CP2077-Coop/pull/18#issuecomment-6256848927).

Next: independently validate crouch and weapon/aim rendering on the pure
entity, then connect actual engine capture through a reviewed typed persistent
state route, including stale data, late join, reconnect and cleanup. No protocol,
server or VPS change is part of this quality checkpoint. No new release/version.

Private evidence root:
`G:\Projects\CP2077-Coop\bench-artifacts\20261018-player-actions`.
Relevant folders: `full-detail-build03`, `before-gait6`,
`full03-gait6-qualification`, `full03-gait6-repeat`, `record-id-probe`.
