# Recorded upper-body aim fixture

KyleBuildsAI / Codex, `experiment/local-player-actions-20261018`, draft PR30.
This is an isolated engine test after the real-time transition correction.
It does not deliver or render another player's actual camera angles.

## Engine implementation

The explicit `--aim-fixture` action-graph option adds clamped, nonincremental
model-space rotations of `Spine2`: pitch X within +/-40 degrees, then yaw Z
within +/-45. Inputs default to zero. The pelvis, feet and entity transform are
outside these rotation nodes. The graph keeps the existing no-root-motion,
no-events and no-animation-gameplay-command checks. Ordinary generation has no
rotation nodes. Entity/component/reference bytes are unchanged.

The private `igla-aim` request selects ten fixed five-second phases on one
separately owned actor: neutral, up/down, left/right, combined directions,
crouched up/down and neutral return. It preserves the existing JOINER/session,
pause, request-bound, exact native identity and asynchronous cleanup gates.
No arbitrary resource path or remotely supplied test command is admitted.
The recording runner accepts the same explicit model option.

## Actual game evidence

Private `20261020-crouch-mask/aim01-joiner`: VFR85s,2143 fresh frames,25.56Hz mean
callback rate, no capture errors. Requested60Hz is not achieved render FPS.
The fixed sequence was requested2026-10-20T08:36:47.002641Z. Reviewed5Hz contacts
show both signs of both rotation axes moving the hands and mounted Igla,
including combined and crouched cases. Sampled foot placement remains fixed;
neutral return reproduces the initial pose. Exact actor10807125 subsequently
reported removed and was absent from the observed scene.

This establishes visible upper-body rotation only. Exact sight/barrel alignment,
grip calibration, all torso deformation, aim-source validity in different game
states, physical inputs and synchronized delivery remain unqualified. Raw
recordings/receipts and derived contacts stay private; capture metadata is intact.

Native roundtrip, exact authored-resource inventory and extracted hashes passed.
Windows experimental68/68 and production-v5 control66/66 passed. Asset regressions
reject pelvis targeting, unbounded/incremental/wrong-axis rotations and silently
accepting the aim graph without opt-in. Fixture tests cover both signs, limits
and exact cleanup. Source capture tests reject optional camera failures without
losing essential crouch/weapon state.

## Better source-camera diagnostic

Live2.31 read-only queries verified `player:GetFPPCameraComponent()` and
`GetLocalToWorld() -> Matrix`. Actual Matrix RTTI exposes `IsOk` and
`GetDirectionVector`; the vector agrees with active camera and body directions
in the observed standing first-person view. `GetWorldForward` on the component
and `Matrix.GetForward` are unavailable, and are not used by this implementation.

The optional source helper now reads the player-owned component through
`Matrix.GetDirectionVector(...)`, validates the matrix and unit direction, and
reports source `player_fpp_component`. Absent/invalid components yield no angle;
there is no fallback to an unrelated scene camera. This is a read-only diagnostic.
Player ownership does not prove that this component is the current gameplay
view during menus, scenes, vehicles, scanner or photo mode. Those admission
rules and camera-to-sight calibration must be qualified before production use.

After a stopped-game installation and fresh launch, both actual source logs
contain `source=player_fpp_component` with valid angles. The updated automatic
runner then completed `aim02-automated`:60s/1600 fresh frames,27.08Hz mean,
no capture errors, all ten phase receipts, exact actor10807932 removed. Reviewed
contacts from the opposite fixed observer view confirm the angle changes and
neutral return again. This run tests runner/engine integration, not networking.
The runner now also records UTC request and phase-observation times for future
comparisons; the earlier aim02 offset is derived from the retained request file's
UTC write time and recorder start time.

## Private installation

Aim archive SHA256:
`8e9079ab9ca8ff3e600477e95163bc024abc0a1b8fef2229383a08af8af121b6`.
Entity payload remains8bba5259; graph payloadcd916852. Existing weapon8eff9157,
private corrected-crouch/mixed cacheee83b803 and9f27bd4 native DLL/server are
unchanged. Installs were performed only with both games/server stopped and all
11 protected control/configuration hashes checked. Stablev0.0.37/latest and
the production-v5 VPS remain unchanged. No generated owned-game data is public.
