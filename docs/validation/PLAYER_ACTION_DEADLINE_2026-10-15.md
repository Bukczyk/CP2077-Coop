# Player action deadline follow-up

Owner: KyleBuildsAI. UTC: 2026-10-15T08:00:33Z.
Branch: `feat/player-action-preparation`, previous head
`afd5376e9b6ef5c3b5dc713fe692601ed4fabc0b` (draft PR16).

## Reproduced defect and change

`actions.lua` inspected a matching stance/weapon result before checking the
admitted request's deadline. With the default two-second command deadline and
five-second freshness bound, a request submitted at zero and first observed
matching at 2.1 seconds returned `queued / checking_latest`, then `observed` on
the same timestamp. It silently treated a missed deadline as successful work.

Admitted work now checks its original active-time deadline before accepting
matching readback. Late matching state can still permit the exact owned command
to retire, but the result remains `failed / readback_timeout`. Newer coalesced
desired state, repeated calls and a fresh serial cannot clear that failure.
Existing cancellation failure retains its command and explicit failure reason.
An actor already matching a desired state without an admitted request does not
inherit a fictitious command timeout.

This leaves the existing pause clock, observed fields, equipment grant bounds,
command ownership and aim-probe behavior unchanged. No new engine hook, wire
field, gameplay kind or automatic fixture activation was added.

## Validation

- New regression fails the original `afd5376` implementation at the late-draw
  result assertion. An independent pre-edit probe reproduced the original
  `queued / checking_latest` followed by `observed` result at 2.1 seconds.
- 279 focused Lua checks pass under Lua 5.4 and LuaJIT 2.1. New cases cover
  draw, switch, holster and stance at the exact deadline and after it, with and
  without a newer coalesced state, plus same-timestamp retries and the
  already-matching/no-admitted-work control case.
- Existing configured Windows branch CTests: 29/29 pass.
- `git diff --check` passes. Ignored logs:
  `build/offline-actions/late-actions-ctest.log`, `late-actions-luajit.log` and
  `late-actions-full-ctest.log`.

Only `experiments/player-presentation/actions.lua`, its existing focused tests,
the experiment README and this note changed. No REDscript/native source changed,
so no new script compilation or native rebuild was required. No installed file,
package, configuration or save changed. No new live-game qualification occurred.
Supported weapon visibility, crouch/stand animation, visible aim entry/hold/exit,
appearance matching and multiplayer action delivery remain separate open gates.
