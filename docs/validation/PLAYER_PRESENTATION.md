# Player presentation task

Owner: KyleBuildsAI. Started 2026-10-06 UTC.
Branch: `feat/session-player-presentation`, starting local commit `8b95f3d`.
Upstream checked at `7e3826d`; depends on the lifecycle correction in Bukczyk PR #4.

The current typed preview teleports a Judy projection every render frame and
sends no weapon, stance or aiming state. This task restores engine-driven player
movement first, using the existing interpolated position/yaw calls unchanged.
The older v0.0.37 implementation supplies the AI movement/rotation/equipment
reference. It is not installed alongside this runtime.

Owned implementation files: `runtime/session/cet/CP2077Coop/init.lua`, new
`player_motor.lua`, `runtime/session/redscript/CP2077Coop/remote.reds`,
`tests/player_motor_tests.lua`, `tests/session_lifecycle_tests.lua`,
`tests/CMakeLists.txt`, runtime README and this validation note. Local source
provenance, packaging and vault handoffs will be updated with final evidence.
No world-NPC adapter or network/session implementation is claimed.

Acceptance: independently tracked players walk/run/stop/turn; normal movement
does not send teleport commands each frame; corrections are bounded and judged
by observed position; replacement/unload/reconnect stops old commands; existing
session regressions pass. Record actual two-game tracking errors and limitations.

Weapons, crouch and aiming require a shared presentation-state contract. The
current PlayerPose/PlayerState contains only transform and sample time. Do not
overload coordinates/rotation or add a parallel relay. Prepare the contract and
game-side hooks for review before changing Bukczyk's wire/server interfaces.

Status: implementation and verification in progress. No passing live result or
new gameplay version is claimed yet.
