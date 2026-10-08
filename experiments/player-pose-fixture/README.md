# Local player pose fixture

KyleBuildsAI owns this opt-in engine diagnostic. It is not a multiplayer test
or part of the normal package. Protocol, backend and the local player are untouched.

Install `init.lua` and an exact copy of the revision's
`runtime/session/cet/CP2077Coop/player_pose.lua` in a separate CET mod directory
named `zz_PlayerPoseFixture`. Record the source commit and both hashes. Reload
CET only after the test session has ended; reloading also restarts other mods.
The normal session bridge may make one connection attempt on reload.

Nothing spawns until this CET console command runs:

```lua
GetMod("zz_PlayerPoseFixture").start(0.5, 0, 0)
```

Arguments are speed in m/s (0 to 8), turn rate in radians/s (-3 to 3), and
initial heading offset in radians (-pi to pi). Close the overlay after starting.
`start(6, 1.5, 0)` exercises faster translation and changing heading;
`start(0.5, 0, math.pi)` exercises spawn-time heading mismatch.

The fixture uses one nonpersistent Judy actor tagged `CP2077PoseFixture`, without
a network binding. It tests stationary placement, a one-metre translation,
a 90-degree turn, ten seconds of moving targets, and settling. It stops after
32 seconds, retires its owned command and requests deletion of its tagged actor.
`GetMod("zz_PlayerPoseFixture").stop()` stops early. Deletion requested or an empty
tag list is not proof that no visible body remains; inspect cleanup separately.
Do not run in combat, vehicles, or a live collaboration session.

`POSE_FIXTURE` records in CET's `scripting.log` include the admitted command,
latest target, actual transform and command state. Actual yaw is degrees;
target yaw is radians. Preserve raw records, including initial origin placement
and failed trials. Report moving-phase errors separately from spawn transients.
Scheduling success is not observed movement, and scripted translation is not
walking input or animation validation.
