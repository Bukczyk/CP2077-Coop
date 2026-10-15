# Static NPC pending-spawn retirement

UTC date: 2026-10-15. Follow-up to PR #21, starting from
`4f56311052bb2949f05aeda036b2a8d0b2883987`.

## Confirmed offline defect

The old static adapter could call `DespawnEntity` on a pending token, observe
empty status maps and release its local/session identity. The actual reconnect
entrypoint could then create a replacement. A later successful spawn callback
could insert the original actor, leaving two actors and only one retained owner.

This is grounded in the reviewed Codeware **v1.18.0** `StaticEntitySystem`
implementation. Its pending despawn erases the token-map entry, while the
successful callback registers/inserts the entity without checking that token
membership still exists. The callback's own token can remain valid. Removing the
map entry is not a documented cancellation barrier.

The private reproducer ran the real `init.lua`, `npc_runtime.lua` and
`npc_static_population.lua`, with an engine shim reproducing that callback
ordering. Both Lua 5.4 and LuaJIT reproduced premature owner release, replacement
creation, two actors after callback delivery and a forgotten old actor whose
`remove` call returned success without issuing a native despawn.

This establishes the unsafe code path under the modeled ordering. No in-game
occurrence or timing frequency was measured.

## Changed behavior

- Retain the exact creating system and returned EntityID. Read that creator
  directly, with strict readiness, instead of assuming fresh CET wrappers have
  stable Lua object equality.
- Mark creation completed only after the creator returns the exact attached
  actor with `managed=true`, `spawned=true`, `spawning=false`. Global or retained
  attachment alone cannot establish callback completion.
- Never call despawn for a pending/unknown creation or release its owner from
  empty token maps. A late successful callback is retired under that owner.
- Keep the first exact actor handle across unbind and lookup replacement.
  Observe exact creator/global lookups and retained attachment separately.
- Release a completed creation only when all lifetime flags are explicitly
  false, both lookups are empty and the retained actor is explicitly detached.
  Missing/malformed status values, identity mismatches and observation errors
  retain ownership.
- Retirement is irreversible. Pending cleanup never rebinds or moves its old
  actor. Native bind/unbind/despawn acceptance must be exactly `true`.

No DynamicEntitySystem timing window was copied. Codeware retains disposed
static actors until its update observes `Uninitialized`; the static gate uses
observed state instead of an invented delay. No protocol, backend, dynamic NPC
adapter, shared runtime entrypoint or player implementation changed.

## Validation

- Existing configured Windows CTest suite: **26/26 passed**.
- Five focused suites pass under **both Lua 5.4 and LuaJIT**: static population,
  static identity, dynamic population, dynamic identity and session lifecycle.
- The static identity suite includes the real reconnect hotkey: pending token,
  external token-map gap, unknown status, late successful callback, asynchronous
  despawn, surviving global/retained actor and eventual single replacement.
- Focused cases cover overwritten retained handles, wrong global identity,
  malformed attachment/readiness, changing system lookup wrappers and incomplete
  creator-only qualification. Existing exact-ID and malformed flag cases remain.
- Independent review reran the focused suites and injected the original adapter
  into the new actual-entrypoint test. Both runtimes failed at
  `reconnect must never cancel an in-flight static token`; the fixed adapter passed.
- `git diff --check` passed. No native or REDscript source changed.

Private evidence:
`D:\Downloads\syncfix\bench-artifacts\20261015-static-npc-lifecycle-audit`.
This contains the before-fix reproducer, source hashes/revisions, both runtime
outputs, after-fix focused results and CTest log. The reviewed Codeware source
cache is in the adjacent `20261015-passive-player-lifecycle-audit` directory.

## Remaining limits

An unknown or failed never-completed spawn is intentionally retained if no
terminal callback outcome can be proven. This may block further NPC projection
creation rather than risk an orphan or duplicate. A proven world teardown or
explicit engine cancellation-completion signal would need a separate recovery
contract; no timeout is treated as proof here.

No installed runtime, save, graphics, controls, server or package was changed.
No game launch, live reconnect or two-PC validation was performed. Experimental
static projection remains opt-in and still needs its later live qualification.
