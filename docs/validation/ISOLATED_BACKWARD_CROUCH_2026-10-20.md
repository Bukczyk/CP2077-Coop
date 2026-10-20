# Isolated forward/backward crouch qualification

KyleBuildsAI game-side work after4eb7e14, draftPR30. This is an explicitly armed,
local engine fixture, not networked crouch direction or a public gameplay release.

## Asset and timing

The inspected2.31 unarmed stealth bank contains forward and backward walk clips,
but no ordinary sideways walk clips. The lower-crouch tool now accepts an explicit
`walk_180` selection, retaining the default forward recipe. It lowers the pelvis
0.25m and solves both legs to their original foot paths. Native import/export
comparison across87 samples gives maximum foot change0.000111143m, quaternion
orientation error1.33e-8 and pelvis drop0.249997..0.250019m. Events and motion
extraction are removed; the uniquely aliased compressed pose buffers survive
pack/unpack and alias roundtrip unchanged.

The installed motion metadata measures6.249844074m per forward clip cycle and
3.992504835m backward. The16-byte translation-key format was verified against the
[pinned WolvenKit9.0.1 reader](https://github.com/WolvenKit/WolvenKit/blob/9.0.1/WolvenKit.Modkit/RED4/Tools/Animation/AnimRootMotion.cs).
These measurements drive cosmetic clip sampling only. Graph root motion stays
disabled, with no position/heading authority change. Existing connected crouch
still shares the ordinary standing-walk rate; correcting that is the next task.

`build_direction_fixture.py --profile crouch` references the existing corrected
idle/forward cache plus one separate backward resource. Its explicit controller
model `crouch-directions` exercises low idle, forward0.6m/s, stop, backward0.6m/s,
stop and forward return in30s. Heading stays0. Only selectors0/1/2 are used; unused
base-selector slots render neutral crouch. No weapon hooks or AI are invoked.

## Actual game observation

Both stopped games received authored fixture102f50e2 and PRIVATE single-clip
cache87dce4bf. Only JOINER's private fixture controller changed. Main action graph
8840cad3, weapon414efd02, existing caches, locomotion9 and native9f27bd4 remained
unchanged. The earlier fixture01 combined-cache plan was superseded before use;
the installed candidate is fixture02 with two explicit cache references.

JOINER recording60s/1463 fresh frames/24.74 callbacks Hz completed without errors.
Requested60Hz is not achieved render FPS; original VFR metadata is unchanged.
Reviewed contacts show low forward and backward steps with fixed facing, stops,
forward return and exact removal. One early forward sample was occluded by a
local pedestrian; it is retained, with later forward samples and the repeat clear.
Actor10815709's nonce-matched receipt reports `removed`, elapsed30.049s, and reviewed
post-cleanup frames contain no duplicate fixture. The inherited mod-log filename
was stale, so it is not used as phase-timing evidence. Recording, request and
exact receipt provide the bounded test evidence.

This does not qualify arbitrary terrain, exact planted-foot slip, armed crouch,
sideways crouch, multiplayer delivery, actual keyboard input or WAN. No connected
renderer change is included yet. Both games/server remain open with controls,
configuration and current saves preserved. No clock override remains active.

## Source and checks

KyleBuildsAI owns `lower_crouch_walk.py`, `build_direction_fixture.py`,
`action_fixture.lua`, their three focused tests and this record. Windows71/71 and
production-v5 control69/69 pass. Focused tests preserve known graph bindings,
forbid mixed recipes/root motion/events, reject unknown clip/profile names and
retain exact context, identity, bounded route and cleanup requirements.

Only authored source is published. Game-derived GLBs, caches, exports, snapshots,
raw logs and videos stay private. No new runtime/package release or stable/latest
replacement, production protocol, session/backend or VPS change.
