# Actual local player controls, M13

Tested installed source `4327359` in two real Cyberpunk 2077 2.31 games on
2026-10-20. Both were actual HOST/JOINER players, without a synthetic participant.
Native runtime/server remained `9f27bd4`, private protocol 32773. Production v5,
backend, input mappings and saves were not changed.

Two concurrent 160-second videos contain 4518 HOST and 4502 JOINER original
frames, with no invented duplicate frames or capture errors. Fresh callback rates
were 28.38/28.28 Hz; these are capture rates, not engine frame-rate claims.
Original frames were reviewed at draw, crouch, aim, held aim, aim-off and standing.

| Actual HOST control | Observation on JOINER |
| --- | --- |
| `1`, draw slot 1 | The guarded Igla appears on the remote actor. |
| `C`, crouch | Remote actor adopts the low crouched pose. |
| Right mouse, toggle aim | Remote actor adopts the crouched aiming pose. |
| Right mouse, leave aim | Remote actor leaves aiming while remaining crouched. |
| `C`, stand | Remote actor returns to standing. |
| `B`, holster | Later live screenshot and diagnostics show standing/holstered. This action is outside the video interval. |

After the late explicit JOINER diagnostic restart, 275 complete rows in
14:42:30..14:43:30 UTC retain exact actor `10829910`: 143 crouched/Igla/aiming,
39 crouched/Igla/not-aiming, 47 standing/Igla/not-aiming and 46 standing/holstered.
No actor faults and zero reported root readback error occur in that interval.
HOST readbacks before and after the sequence both report crouch=false,
held=false, aim=false. No shot was requested; displayed ammunition stayed 2/192.

## Limits and observed input problem

The automated right mouse click also changed the source camera pitch/yaw.
Actual HOST sight-up and JOINER horizontal aiming are visible simultaneously.
This verifies the aim **state**, not replicated camera aim direction or sight
alignment. Camera-angle transport remains an open contract/integration task.
No camera-angle field or guessed fixed delay was added to the protocol.

The previous bounded JOINER diagnostic capture had stopped, and the private
observer's 1800-second lifetime had elapsed. Its new nonce did not restart it.
Early draw/crouch rely on video; late fresh rows are not retroactive evidence.
The recorder finished before holster. Keep that tail limitation explicit.

This is stationary physical-input capture and presentation evidence. It does not
qualify physical crouch-walking, sprinting, firing, WAN behavior, terrain, exact
grip or arbitrary weapons. The keyboard API has no held-key duration operation.
No blind remapping or repeated firing attempts were used.

Both games exited normally with keep-settings policy afterward. The final
configuration hash matches the previous normal-exit configuration. A fresh
matched launcher reset the bounded private helpers and restored a normal camera
view without changing bindings or restoring old saves.

Private evidence: `20261020-crouch-mask/actual-player-inputs01`, including both
videos, source PTS/keyframes, UTC input journal, fresh state rows and capture
metadata. Owned-game media and logs are not committed.
