# Lower idle/walk/sprint blend qualification

KyleBuildsAI game-side work on draft PR30, based on23518bb. This is the private
0x8005 local experiment. No production-v5, server, VPS, combat or vehicle change.

## Change and boundary

The lower standing gait selector switched instantly after its engine-time fade
was removed to fix dilation lag. The matched action graph now mixes the current
gait with one departing gait, freezing moving samples (neutral idle still loops).
Lua supplies an80ms real presentation-clock
weight. Stance and upper-weapon blending retain their separate existing layers.
The departing walking sample preserves its dominant strafe direction and weight.
Rapid retargeting keeps at most two poses. No root position or heading is changed.

Only fresh standing ground phases0/1/2 blend. Crouch, stale/unavailable state,
takeoff/air/landing, teleports and long/invalid update gaps clear the departing
layer immediately. The original locomotion-only renderer keeps its two inputs;
extra blend inputs require the matched experimental action renderer. New graph
variables default to zero, selecting the ordinary current gait until supplied.

The local replay adds `--gaits`, mutually exclusive with `--directions`. Its first
36s walk forward, stop, sprint back and stop, walk again and stop. The existing
92s stale/repair, unsupported/unavailable, disconnect/rejoin and crouch tail is
retained. This is a normal synthetic SessionClient participant, not physical
keyboard input, WAN or replicated authority proof.

## Offline evidence

The focused gait test fails on23518bb and passes on working revision9. Coverage
includes walk/sprint/stop, independent actors, frozen strafe sampling, bounded
retargeting and immediate neutralization. Asset validation rejects wrong sample
readers, engine timers, unsafe masks, root motion, missing nodes and mixed caches.
Native graph serialize/deserialize, pack/list/unpack and resource hashes passed.
Windows experimental71/71 and production-v5 control69/69 passed. Live validation
and hosted CI for this source are pending; tests alone do not prove smoothness.

## Installed private candidate

Both games and their local server were stopped before installation. Only the
action archive, locomotion/controller Lua and diagnostics recorder changed.

- Action archive8840cad366563cd25a3b1dc2a0e4edf33aba53b672f53326d21911caa98a051b.
- Graph370b670ea769c0cd7210fb46c49b72c734b2436db0c2a561e935d4ccd8ae5f20.
- Body entitya07bf148 unchanged; weapon archive414efd02 and private cachesee83b803,
  cb21e90a unchanged. Native DLL/server remain9f27bd4/private32773.
- Eleven protected key/configuration/control/settings hashes unchanged. Private
  feature flags, saves and stablev0.0.37/latest remain unchanged.

Raw game-derived caches, snapshots, logs and videos remain private. No new
distributable runtime/package version has been created.

## Normal-clock two-renderer recording

Both loaded revision9 and gaitBlendEnabled=true before gait-blend01. HOST video
145s/2833 fresh frames,19.80 callback Hz; JOINER130s/2511,19.73Hz, no errors.
Original-frame transition contacts retain actual PTS values (36 unique HOST
frames and35 JOINER frames for36 requested samples). Original captures remain
unchanged. Reviewed walk/start/stop, sprint/stop and repeated walking do not retain
a sustained T-pose or seconds-long departing gait. This is bounded observation,
not exact physical-input latency, foot-contact quality or frame-perfect proof.

HOST401 retained diagnostic rows and JOINER409 cover gait0/1/2, no actor faults,
root error<=0.000002m and normal1.0 clocks. Both recorded transient nonzero blend
weights then settled to zero. All18/19 stale and65/66 crouch samples respectively
kept departing-gait and directional weights0. Original five-Hz diagnostics do
not measure an80ms transition precisely; original video frames supplement them.

HOST player3 actor10813750 was replaced on rejoin by player4 actor10813852;
JOINER10813611 by10813688. Reviewed stale/repair, unsupported hiding, disconnect,
rejoin and low armed/unarmed crouch tail retain correct cleanup with no visible
duplicate. Full92s synthetic replay completed. Controlled0.03-clock gait check
and hosted CI for this checkpoint are next. Both games/server remain open.

## Controlled slow-clock repeat

`gait-blend02` repeated the full92s replay with scanner off, measured HOST1.0 and
JOINER0.03. Fresh captures were explicitly started in both endpoints. HOST130s/
3822 fresh frames/29.64 callbacks Hz; JOINER145s/4119/28.57Hz, no capture errors.
Original-frame contacts retain36 distinct source frames per renderer. Reviewed
walk/sprint/stop boundaries show no seconds-long departing gait; stale recovery,
unsupported hiding, exact cleanup/rejoin and low crouch tail remain visible.

HOST409 retained diagnostic rows, JOINER405, no actor faults, root error<=0.000002m.
Both19 stale and66 crouch samples keep the departing-gait weight zero. Transient
nonzero weights settle back to zero on the real clock. Exact actor IDs after
rejoin changed from10814237 to10814269 on HOST and10814298 to10814300 on JOINER.
JOINER's private clock was explicitly removed at2026-10-20T10:15:03Z, with receipt
`active=false scale=1`. Both games/server remain open with controls/config/saves
preserved. Original VFR capture metadata remains unchanged; visual review is a
separate bounded record. Foot-slip, exact hand/sight alignment, arbitrary models,
diagonal/sprint direction quality, physical inputs and WAN remain unqualified.

KyleBuildsAI owns the changed action graph builder, `player_locomotion.lua`,
`player_passive.lua`, diagnostics `recorder.lua`, focused gait/asset/replay tests,
`tests/CMakeLists.txt`, `tools/player_action_replay.cpp` and these validation docs.
No networking/session file ownership transfers or shared wire changes occur.
