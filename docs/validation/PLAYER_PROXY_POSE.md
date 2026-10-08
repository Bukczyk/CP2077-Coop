# Experimental player proxy pose actuator

Owner: KyleBuildsAI. Live checkpoint: 2026-10-08T03:41:10Z.

During connected combat trial 3, the JOINER received a changed HOST native X
coordinate of approximately -1641.597 while its exact tagged Judy player actor
remained at approximately -1644.594. The native snapshot/interpolation path had
updated; the per-frame `TeleportationFacility:Teleport` call had not moved the
NPC. The HOST's stale JOINER actor also caused the independent combat origin
check to reject a real JOINER shot. That check remains unchanged.

## Scoped change

`runtime/session/cet/CP2077Coop/player_pose.lua` now owns one AI teleport command
per exact player actor. `init.lua` supplies the latest interpolated target and
ends that ownership before actor/session cleanup. `remote.reds` exposes the
existing `AITeleportCommand` engine operation, its state and exact cancellation.
The older player presentation experiment already used this engine command;
this change does not import its locomotion system or alter the typed protocol.

- Preserve the requested spawn position. Allow up to three seconds for
  attachment, a nonzero placement and AI command initialization.
- Admit at most one command per actor, no more frequently than 0.1 seconds.
  Keep sampling targets while pending and submit the newest target next.
- Convert the network yaw from radians to degrees once. Confirm the admitted
  command through real transform readback within 0.2 m and five degrees.
  Submission acceptance and engine `Success` are not placement evidence.
- Allow one second for each command to reach its admitted pose. Three
  consecutive failed attempts latch a fault until the actor/session resets.
- Cancel only the owned handle. `NotExecuting` is not terminal evidence because
  command scheduling can precede `Enqueued`. If cancellation cannot be verified,
  retain the handle and latch a fault instead of stacking commands.
- Retire ownership on exact actor replacement, SessionEntityId replacement,
  generation reset, interest removal and shutdown. Never round opaque IDs.

The adapter logs first submission, first observed placement, retries and faults.
It does not claim weapon/animation parity, damage attribution, natural walking
or smooth tracking. A moving actor that never reaches its admitted pose can
still hit the bounded failure gate. That requires live diagnosis, not a relaxed
combat origin tolerance or fabricated placement success.

## Offline validation

PASS: Windows Release build and all 24 CTest suites, including session lifecycle,
player pose, connected encounter, transport and authority regressions.

PASS: `player_pose_tests.lua`, 36 checks under the configured Lua runner, using
opaque-ID mocks. This local run does not establish LuaJIT cdata coverage. The
test executes the actual CET entrypoint with a silent NPC teleport-facility
no-op, changes native targets while a command is pending, and verifies exact
cleanup. It covers deferred initialization, rejected/dropped commands, false
engine `Success`, failed cancellation in state zero, adjacent opaque IDs above
2^53, latest-target coalescing and yaw wrapping.

PASS: isolated matched REDscript compilation on 2026-10-08T03:29:42Z, including
Codeware, typed natives and the connected combat probes. Compiler exit 0;
game/cache/compiler input hashes unchanged. Private evidence:
`bench-artifacts/20261007-connected-combat/redscript/compile-20261008T032941182719Z.json`.

## Controlled placement result

Trial 4 used source `97d7c1a0b0fb7751800bf0fa2697769ca4e4b238`.
Installed REDscript compilation succeeded on both HOST and JOINER. After a
controlled JOINER placement of approximately six metres, HOST's received player
position and its exact actor position matched. At `2026-10-08T03:36:49Z`, both
were `(-1647.8989257813, -2318.9399414063, 39.731163024902)` for player 2,
actor `10724893`; the actual JOINER source was at the same position.

This fixes the observed freeze for that controlled placement. It does not prove
smooth continuous movement, animation, both-direction tracking over a route,
bounded behavior during prolonged movement or cleanup after disconnect.

A subsequent real JOINER shot passed the unchanged HOST origin-distance gate:
the squared distance was `2.554573`, below `25`. Its ray then hit the exact
authenticated shooter proxy instead of the controlled NPC and correctly rejected
the request. No damage, reaction or death pass follows from the pose correction.
See the [connected live checkpoint](CONNECTED_ENCOUNTER_2026-10-08.md) for the
remaining query blocker and failed collision-disable experiment.

All hosted Windows, Debian and sanitizer jobs passed at this exact source head:
[run 37723374154](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37723374154).
No package version or public gameplay milestone is claimed by this change.
