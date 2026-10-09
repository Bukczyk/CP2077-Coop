# Local player cleanup experiment

KyleBuildsAI game-side diagnostic. It creates one temporary Judy actor, records
the exact returned EntityID, and never binds or publishes a network entity.
It stays idle until explicitly started. Do not install as a production feature.

Install `init.lua` in the diagnostic CET mod `zz_PlayerCleanupFixture`, together
with an exact copy of `runtime/session/cet/CP2077Coop/player_lifetime.lua`.
Reload only when every previous fixture actor has confirmed removal. Do not
reload an active experiment because its ownership record lives in Lua.

Start the safe production-controller test:

```lua
GetMod("zz_PlayerCleanupFixture").start("settled")
```

`start()` also selects settled mode. It requests retirement immediately after
CreateEntity, then pumps the actual player lifetime module on game updates.
Observed game pause defers deletion and the watch timer; an unavailable pause
observation does not authorize deletion. The module waits for stable attachment
and confirms absence before reporting done. The fixture keeps observing for a
full five unpaused seconds, even if the controller finishes sooner.

`CLEANUP_FIXTURE` log entries contain the exact actor, attachment/registry state,
lifetime status/done, deletion and completion times, and pause observations.
`delete_after_spawn` means the API accepted deletion, not confirmed removal.
Use `inspect()` for another observation. `reset()` requires controller completion
in settled mode and refuses while either exact actor lookup or any
managed/spawning/spawned evidence remains. A blocked or
failed run stays recorded rather than starting another actor.

Known-bug reproduction is a separate explicit opt-in:

```lua
GetMod("zz_PlayerCleanupFixture").start("immediate")
```

This deliberately calls DeleteEntity immediately and can leave an unmanaged
actor on affected Codeware builds. After the full watch, `recover()` requests
despawn only for this fixture's exact returned ID. Inspect afterward and call
`reset()` only when absence is confirmed. Never delete a nearby NPC by position.

These tests establish local engine cleanup behavior. They do not establish WAN
movement, player animation or two-PC success.
