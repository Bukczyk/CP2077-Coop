# Player diagnostic recovery

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15.
Branch: `fix/player-diagnostic-recovery`.
Base: `691dc3975293dec6e4c9114785117f71d3b12389` (published PR #17 movement experiment).

## Scope

This follow-up corrects two misleading diagnostic states and prevents skipped
engine observations from qualifying player cleanup. Movement commands,
recovery budgets and exact identity ownership are unchanged.
The published HOST/JOINER packages remain unchanged.

Owned files:

- `runtime/session/cet/CP2077Coop/player_motor.lua`
- `runtime/session/cet/CP2077Coop/player_lifetime.lua`
- `runtime/session/cet/CP2077Coop/init.lua`
- `tests/player_motor_tests.lua`
- `tests/player_lifetime_tests.lua`
- `tests/session_lifecycle_tests.lua`
- `tests/player_pose_tests.lua`
- `tests/passive_player_tests.lua`
- This validation note

## Defects and behavior

1. After a move retired, a new turn could report `Executing` from the old
   command while its own engine handle was still `Enqueued`. Confirmed release
   and accepted submission now clear the cached command state. The new handle's
   state remains unknown until it is observed. Rejected cancellation still
   retains both the owned handle and its last observed state.
2. One failed exact actor lookup set `actor_observation_error` permanently,
   even after the same actor returned and resumed updating. A successful exact
   lookup now restores the active lifetime's `owned` status. Missing actors,
   identity mismatches and retiring lifetimes cannot use this recovery path.
   Retirement still requires its existing stable attachment and absence checks.
3. A `GetPlayer` or passive-pump exception could advance the bridge clock and
   skip retirement observation. Once the bridge latched its error, the next
   valid tick could count the skipped interval toward confirmed removal. The
   failure path now invalidates every already-owned retirement at the current
   timestamp, even if startup tag recovery also fails. It does not advance time
   again. Failed-mode cleanup also protects the complete pause-context read.

Pause policy is explicit: a requests-handler getter exception still latches
the bridge error. An `IsGamePaused` exception now means nonfatal unknown pause,
consistent with the NPC cleanup path. Missing handlers and non-boolean pause
results are also unknown. Unknown pause cannot qualify attachment or absence;
player owners receive `paused=true`, since their optional nil argument means
unpaused. Valid observations must start a new attachment pair or quiet interval.
The existing pose and passive entrypoint fixtures now supply an explicitly
unpaused handler instead of using nil to stand in for a running game.

## Validation

Seven existing suites passed against this branch using both the pinned Lua 5.4
test executable and the existing LuaJIT 2.1 test dependency:

- Player motor: 111 checks.
- Player lifetime: 2,869 checks.
- Session lifecycle: includes the real CET entrypoint diagnostic recovery and
  retained exact actor without a new spawn; LuaJIT uses actual Uint64 cdata.
- Movement diagnostic recorder and CET lifecycle.
- Player pose: 112 checks.
- Player pose fixture: 41 checks.
- Passive player lifecycle: 244 checks.

The three modified test suites were also run against unchanged base runtime
source. All failed at their new intended regression assertions: cleared motor
state, recovered active lifetime status and recovered entrypoint diagnostics.
This distinguishes regression coverage from tests that pass both versions.

`git diff --check` passed. No native or REDscript source changed, so no new
native build or engine compilation is claimed. No game was launched, no game
installation/configuration/save was changed, and no release was produced.
Private reproduction fixtures and LuaJIT output are under
`D:/Downloads/syncfix/bench-artifacts/20261015-player-reliability-audit`.

The cleanup follow-up adds 13 real-entrypoint cases: four early failures at
each of two retirement stages, plus five unknown-pause cases after a latched
failure. They verify retained ownership, fresh qualification, preserved fatal
error latches, nonfatal method-only pause uncertainty and one clock advance per
callback. The new session lifecycle suite fails against the prior PR #20
runtime (`e19ed94611166fafcd9aef68a9ac0789b8fc5ee9`) at the intended handler-error
invalidation assertion. Both Lua 5.4 and LuaJIT 2.1 pass all seven related suites
after this follow-up. This is offline lifecycle evidence, not a game test.

## Separate moving-facing gap

The motor forwards authoritative yaw to correction and idle-turn commands.
`StartMove` and `RetargetMove` receive position/gait, but no facing value. A turn
is canceled when motion resumes. In the existing command-driven test model, a
10-second walk with target yaw 90 degrees achieved position error below 0.08 m
without a fault, while simulated actor yaw remained 0 degrees. This establishes
missing moving-facing application and missing test coverage, not actual
REDengine orientation behavior.

Do not claim that position convergence proves matching facing. The deferred
two-PC test must include sideways and backward walking while holding a known
body heading, plus turning during motion and after stopping. Compare both
videos and target/actual yaw diagnostics. A subsequent implementation needs a
verified facing hook that does not introduce competing commands; this patch
does not change facing behavior.
