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

## Isolated action engine checkpoint, 00:39 UTC

The separate action fixture now compiles and renders crouch idle/walk and
rifle/handgun ready/aim arm poses, including upper-body aiming while crouched.
This is a fixed local pose sequence on its own actor, not remote captured state.
It has no weapon model. The mask uses the installed rig's named upper-body
bones and leaves hips/root/legs to the lower-body pose. No NPC AI is reintroduced.

- Windows local suite: 58/58 passed. Three new suites cover clip aliasing/data
  preservation, unsafe graph/default/mask mutations and bounded exact-actor
  fixture lifecycle. Mock checks are not counted as live game results.
- Native action asset build04 passed serialization, roundtrip, inventory and
  extracted payload hashes. Its entity/graph binaries exactly match the build03
  payload used in the game. Archive bytes differ because of packing metadata;
  the live installed build03 archive is SHA256
  `00f60e82168db1475519e7787a090fbfcae5c0070908104b5566605874625aa6`.
- Private alias cache01 passed native name/buffer preservation and inventory.
  The later cache02 additionally checks unpacked hashes. The generated cache
  contains installed-game animation data and is never committed/distributed.
- `poses-fixture01` completed capture/cleanup but HOST overlapped the observer,
  so it is rejected for complete visual review. After one HOST staging move,
  `poses-fixture02-clear` recorded all ten phases and exact actor removal at
  about 50.09 s. Reviewed frames show the stance/upper-body combinations.
- Actual HOST C inputs produced crouch true at 00:27:57 UTC and false at
  00:30:07. Slot key 1 produced `Items.Preset_Igla_Pimp` in the attached
  right-hand weapon slot at 00:30:20. Right mouse produced aim true at 00:30:37,
  then false at 00:31:08. A later Alt input changed the slot temporarily to
  `Items.Preset_Overture_Dodger`, then to empty. These are read-only source
  observations, not delivered network states. Source video/logs are private.
- Current capture hooks compiled against both matched installs with Codeware.
  The optional held-template getter also compiled offline; it is not yet loaded
  in the running games. Do not claim its template output was observed live.
- Earlier quality commit `a2b1f3f` passed 55/55 on Windows, Debian and sanitizers:
  https://github.com/Bukczyk/CP2077-Coop/actions/runs/39179730136

Owned new files: the action/cache builders, private fixture/capture/recording
helpers, capture REDscript and optional weapon template probe under
`experiments/player-locomotion`, their three test suites and scoped CMake entries.
No shared/network/server file has been edited. The actual held model, matching
grip, accepted persistent state delivery, late join/reconnect and residual
stutter acceptance remain open. Keep the complete goal active.

## Resource capture and automatic camera checkpoint, 01:06 UTC

- The optional held-template probe is now loaded in both real games. An attached
  Igla reports generic `base/weapons/weapon_root.ent`, not its visible model.
- Read-only component capture was added and compiled against both matched
  installs. It covers separate static and skinned component types plus rig
  references. Resource identity must agree twice; native masks never pass
  through Lua doubles. Optional probe failure is bounded and cannot stop core
  crouch/aim/weapon-state capture. Local suite passed 59/59, with the latest
  capture/observer changes also passing their focused checks.
- Actual slot-key inputs 1/2/3 produced qualified component snapshots for
  `Items.Preset_Igla_Pimp`, `Items.Preset_Overture_Dodger` and
  `Items.Preset_Ticon_Gwent`. Igla has `pimp1`/`pimp1_igla` mesh appearances;
  Overture has `rosco` plus attached `neon_1` scope components; Ticon has
  `redplay`. Right-hand item appearance lookup returned `None` in these samples.
  Metadata includes shadow/placeholder/reload components and does not prove
  that every authored-enabled component is visible. No weapon model is yet
  attached to the pure player projection.
- `poses-fixture03-auto-camera` completed the ten poses and exact removal at
  50.046s. The observer detected HOST at the first view and submitted the second
  fixed view, x=-811. Frame review shows a clear actor and pose changes without
  a manual HOST staging move. The receipt records a submitted target, not an
  exact observed camera transform. A brief ambient NPC crossing is retained.
- Source action checkpoint `125a007` passed all58 tests in Windows, Debian and
  sanitizers: https://github.com/Bukczyk/CP2077-Coop/actions/runs/39182070194

Private new evidence: `poses-fixture03-auto-camera`,
`weapon-source-resources01/weapon-snapshots.json`, `before-weapon-probe`,
`before-weapon-components`, `research/weapon-json`. Raw installed resources stay
outside source. No protocol/server/VPS change. Exact held model/grip, connected
state delivery/recovery and complete stutter acceptance remain open.
