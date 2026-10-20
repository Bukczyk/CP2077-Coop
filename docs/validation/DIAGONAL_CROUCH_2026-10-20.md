# Connected diagonal crouch regression

Installed M13 `4327359` remains unchanged. The private action replay adds
`--crouch-diagonals`, exposed by the paired recorder's matching `--mode`.
Production v5, private 32773 semantics, backend and entity authority are unchanged.

Eight continuous three-second legs move at 0.5 m/s, straddling each diagonal by
ten degrees. Body heading stays fixed; opposite legs return to the starting
point without teleporting. The sequence crosses all four direction hysteresis
boundaries, changes holstered/Igla/aim states and stops. The existing state
expiry, repair, unsupported weapon, disconnect/rejoin and crouch tail remain.

Offline preflight tests verify leg distance, heading invariance, rotated origin,
closed-route stop and mutually exclusive modes before reading credentials or
opening a socket. The Lua regression adds both yaw bases and noisy diagonal
velocities: no direction chatter, bounded real-clock settling, no standing-bank
leak, unchanged network transform and held stop progress. Windows experimental
77/77 and default-v5 control 75/75 pass sequentially.

## Recorded local run

`connected-diagonals01` completed the full 92-second synthetic SessionClient
route, covered by both concurrent 117-second game videos. HOST contains 2917
original frames at 25.12 fresh callbacks/s; JOINER 2876 at 24.75. Neither capture
reports an error or invented duplicate frames. These are not engine FPS claims.

Retained complete HOST/JOINER diagnostic rows: 408/404. Both report normal time
scale, all four crouch axes, both side directions and both supported/holstered
weapon states. Each retains 83 fully weighted side-crouch rows. No actor fault;
maximum root readback error 0.000002 m.

Exact actor lifecycle for synthetic participant 3, then rejoined participant 4:

| Observer | Initial actor | New actor after rejoin |
| --- | --- | --- |
| HOST | 10832542 | 10832602 |
| JOINER | 10832500 | 10832572 |

Reviewed original frames from each leg, stops and the repair/removal/rejoin tail
in both views. Additional boundary frames span -120..+400 ms around each intended
direction change. Visible samples retain low crouched poses, correct body facing
and armed/unarmed upper-body handling, without a sustained T-pose. Occluded or
out-of-view intervals are excluded. This does not certify exact foot plants,
terrain adaptation, grip, camera-aim alignment or physical diagonal input.

The keyboard/mouse check is separate:
[actual player controls and its limits](ACTUAL_PLAYER_INPUTS_2026-10-20.md).
Raw game-derived videos, assets, logs and per-frame PTS stay private. No release,
main merge, stable-package replacement or WAN acceptance is implied.
