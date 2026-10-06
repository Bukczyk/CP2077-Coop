# CET session lifecycle correction

Owner: KyleBuildsAI. Started UTC: 2026-10-06T05:25:00Z.
Branch: `fix/cet-session-lifecycle`.
Base: `7e3826d1c313595a4784f1b232e10cec222b6ca3`.
Status: implementation and verification in progress; no gameplay release.

## Scope and file ownership

KyleBuildsAI is editing these files for this task:

- `runtime/session/cet/CP2077Coop/init.lua`
- `runtime/session/cet/CP2077Coop/config.lua` (new)
- `tests/session_lifecycle_tests.lua` (new)
- `tests/CMakeLists.txt`
- `runtime/session/README.md`
- `docs/validation/CET_SESSION_LIFECYCLE.md` (this evidence record)

Use the existing `CP2077Session_*` calls. No protocol, server, native interface,
NPC projection adapter or movement changes are part of this task.

## Reproduced problems

The first local two-game launch failed while loading `init.lua` because `Observe`
was not yet available. The NPC observer must be registered during CET `onInit`.
After bypassing that failure privately, the game bridge repeatedly stopped and
started sessions because `tostring(player:GetEntityID())` described a temporary
wrapper rather than the stable engine identity. Compare the exact Uint64 `hash`
without conversion to a Lua number.

Restoring startup also makes unfinished NPC replication reachable. Keep that
experimental path explicitly opt-in while passive JOINER AI remains unverified.

## Acceptance checks

- Execute the real entrypoint with engine APIs unavailable before `onInit`.
- Fresh EntityID wrappers with the same hash must keep one activation; a changed
  hash, unload and explicit reconnect must still perform lifecycle transitions.
- Preserve adjacent 64-bit identities above Lua's exact-number range.
- Run the existing portable/runtime tests and new regression tests.
- Fresh-start HOST and JOINER in matched local test installations. Observe stable
  membership, then explicitly reconnect JOINER and verify re-admission.

Live results, durations and exact source hashes will be recorded before review.
The separate proxy movement error remains unresolved. Two local processes do not
establish two-PC internet play, NPC authority or larger-group game capacity.
