# Player diagnostic recovery

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15.
Branch: `fix/player-diagnostic-recovery`.
Base: `691dc3975293dec6e4c9114785117f71d3b12389` (published PR #17 movement experiment).

## Scope

This follow-up corrects two misleading diagnostic states without changing
movement commands, recovery budgets, identity ownership or deletion policy.
The published HOST/JOINER packages remain unchanged.

Owned files:

- `runtime/session/cet/CP2077Coop/player_motor.lua`
- `runtime/session/cet/CP2077Coop/player_lifetime.lua`
- `tests/player_motor_tests.lua`
- `tests/player_lifetime_tests.lua`
- `tests/session_lifecycle_tests.lua`
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
