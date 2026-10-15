# Passive player cleanup correction

2026-10-15 UTC. Owner: KyleBuildsAI. Base: PR #20
`a4d05313772946d1f3036b218c97e176b094398e`.
Scope: `player_passive.lua`, its existing tests and this validation record.
No protocol, backend, default, package or installed game changes.

## Proven offline failure

The prior adapter treated nil `IsManaged`, `IsSpawning` and `IsSpawned`
observations as confirmed false. It also discarded the exact actor handle when
unbinding. A real `init.lua` generation reset could release two owned static
tokens and spawn two replacement actors without sending either old actor a
despawn request, while both old actor handles remained attached.

The focused real-entrypoint regression fails on the base revision under both
Lua 5.4 and LuaJIT 2.1 at `unknown static lifecycle blocks real-entrypoint
generation replacement`. It passes with this correction. Injected unavailable
observations reproduce a source acceptance bug; no live occurrence is claimed.

## Corrected behavior

- Pin the exact StaticEntitySystem creator and returned token. Cleanup never
  substitutes a newly fetched system for the creator of an existing token.
- Require explicit Boolean lifecycle and attachment observations, exact actor
  IDs, and strict true readiness/bind/unbind/despawn acknowledgements.
- Preserve the first exact observed actor handle through native unbind. Observe
  creator, global lookup and retained handle before declaring disappearance.
- Wait for the exact creator-owned actor to be managed, spawned, attached and
  no longer spawning before requesting disposal. Global registration alone
  does not establish completed creation.
- Release only after completed creator-owned creation was observed and every
  lifecycle flag is explicitly false, both lookups are absent, and the retained
  handle is explicitly detached. Unknown observations keep ownership and block
  replacement. Placement cannot reinterpret unknown flags as disappearance.

## Why pending cancellation remains conservative

Inspected Codeware v1.18.0
[StaticEntitySystem.cpp](https://github.com/psiberx/cp2077-codeware/blob/v1.18.0/src/App/World/StaticEntitySystem.cpp):
the successful spawn callback registers a non-GameObject and inserts it into
`m_entities` without checking membership in `m_tokens`. `DespawnEntity` erases
the pending token, but this implementation does not explicitly set its abort
flag; existing actors are disposed and retained until update-tick cleanup.
Erasing a pending token is therefore not sufficient evidence of cancellation
for this adapter.

A never-ready or aborted token can remain owned indefinitely because no exposed
terminal cancellation acknowledgement was established. This deliberately
blocks replacement instead of claiming cleanup or repeatedly spawning another
actor. Valid late creation can still be observed, disposed and released. No
dynamic-entity timing window or two-frame rule was imported into this static
adapter. Native scheduling and world-teardown behavior still require live tests.

## Validation

Each existing suite passed under compiled Lua 5.4 and Lupa LuaJIT 2.1:

- `passive_player_tests.lua`: 320 checks, including malformed flags, retained
  and global handles, exact creator, pending creation, qualified absence,
  generation reset, unload and explicit reconnect.
- `player_lifetime_tests.lua`: 3,059 checks.
- `player_motor_tests.lua`: 111 checks.
- `player_pose_tests.lua`: 112 checks.
- `session_lifecycle_tests.lua`: passed; LuaJIT uses Uint64 cdata for local
  player lifecycle identity. Passive-actor fixtures still use opaque ID mocks.

Independent review reran the passive, lifetime and entrypoint lifecycle suites
under both interpreters. The extracted real-entrypoint regression separately
fails the old adapter and passes the fixed adapter (183 checks) in each runtime.
Private evidence is in
`D:\Downloads\syncfix\bench-artifacts\20261015-passive-player-lifecycle-audit`,
including `baseline-versus-fixed.json`, `fix-validation.json` and the pinned
Codeware source copy. `git diff --check` passes.

`experimentalPassivePlayers` remains false. The standard dynamic player path,
networking and experimental movement test packages are unchanged. No game was
launched, no installed files or saves were changed, and no live cleanup or
movement success is claimed by this follow-up.
