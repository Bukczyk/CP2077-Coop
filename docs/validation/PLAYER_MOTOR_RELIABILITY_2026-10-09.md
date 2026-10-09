# Optional player motor reliability

Owner: KyleBuildsAI. Offline checkpoint: 2026-10-09T04:35:25Z.
Branch: `fix/player-motor-reliability`.
Base: `b1f054ed67c0bb03f1b8e290c2b5fd62a621307c`, KyleBuildsAI PR #5.

## Scope and ownership

Owned files:

- `runtime/session/cet/CP2077Coop/player_motor.lua`
- Movement adapter methods in `runtime/session/redscript/CP2077Coop/remote.reds`
- Diagnostic fields only in `runtime/session/cet/CP2077Coop/init.lua`
- `tests/player_motor_tests.lua`
- This validation note

The optional motor remains disabled by default. The existing pose controller,
entrypoint pause gate, player lifetime handling, interpolation, typed protocol,
backend and NPC code are unchanged. This is game-side reliability work on the
preserved movement experiment, not a second movement/network design.

## Changed behavior

Previously, movement/snap/turn submissions ignored `SendCommand` rejection.
Corrections and turns discarded their handles; a stuck actor could receive
corrections forever. Movement retargeting read the command field directly and
could report success when no active movement policies existed. Non-finite ticks,
targets and engine readback could poison timers or reach engine commands.

Each exact NPC actor now retains one owned command for movement, correction or
turning. All submissions honor the engine's Boolean acceptance result. State is
read through its controller, and retarget/cancel operations reject foreign
handles. Missing movement policies fail explicitly. Retirement verifies a
terminal state before forgetting the handle; an unconfirmed cancellation raises
an error for the existing lifetime cleanup to catch and retain ownership.

Lua validates ticks, pose components, engine readback and Float representability
before command submission. Turns wrap heading differences. Observed motion resets
transient movement failures; terminal statuses without matching placement do not
count as success. A stalled actor is detected outside the 0.2 m arrival tolerance,
including the former 0.2-0.75 m gap.

Pending admission and correction/turn readback have one active-second deadline.
Move, correction and turn failures stop after three attempts of the same kind.
Corrections remain at least one second apart and require observed position plus
heading against the admitted target, even as newer targets arrive. Three
corrections exhaust the recovery burst until one second of observed locomotion
within 3 m of the target, or settled arrival, replenishes it. Successful snaps
alone cannot keep an immobile actor teleporting along a moving route.

Faults stay latched for that motor lifetime. Existing player diagnostics now
expose the motor fault, last failure and observed correction count. The existing
entrypoint still skips motor updates during pause; there is no second pause or
actor-lifetime state machine.

## Verification

- PASS: `player_motor_tests.lua`, 98 checks using the existing checksum-pinned Lua
  runner with this worktree as its module root. Three simultaneous actors evolve
  their actual positions from admitted commands, rather than copying the network
  target into readback. Coverage includes walking/running/sprinting trajectories,
  stops, reversals, wrapped heading, malformed/non-finite data, Float overflow,
  rejected/pending/failed commands, false success, finite recovery bursts,
  observed correction targets, stream grace and cancellation ownership.
- PASS: related Lua suites: player pose (112 checks), pose fixture (41), player
  lifetime (2,843), passive player (244), and the real session entrypoint lifecycle
  suite, including its existing pause gate and independent motor cleanup.
- PASS: `VerifySessionBridge.cmake` and `git diff --check`.
- PASS: isolated REDscript compilation at `2026-10-09T04:32:20Z`; installed game,
  compiler, cache and Codeware inputs unchanged. Private log:
  `D:/Downloads/syncfix/bench-artifacts/20261009-offline-player/redscript/compile-20261009T043220160864Z.log`.
- Verified installed REDmod declaration:
  `tools/redmod/scripts/core/components/aiComponent.script`, lines 8 and 18,
  declares Boolean `SendCommand` and controller `GetCommandState`. SHA-256:
  `6AC77CCF4CE55868E24DDED8A9C4F27B5DE3FDAE402D208B74CD773A8669E185`.

Focused runner command, from this worktree:

```powershell
& 'D:\Downloads\syncfix\collaboration\cet-session-lifecycle\build\first-contact\tests\Release\coop_lua_test.exe' `
  'tests/player_motor_tests.lua' `
  'D:\Downloads\syncfix\collaboration\player-motor-reliability'
```

## Remaining gates

No live game, deployment, package refresh or release was performed. The simulator
does not establish navigation, animation quality, obstacle behavior, real gait
speeds or game tracking error. Actual command admission, cancellation and movement
policy behavior still need a controlled opt-in game test. The earlier documented
smooth-movement failure is not reclassified as passed by these offline checks.
Two-client and multi-PC movement qualification remain separate work.
