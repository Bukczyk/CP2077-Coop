# Read-only NPC appearance observation

Source-only, opt-in experiment owned by KyleBuildsAI. It records the **actual
loaded NPC's** identity, template, current appearance and color. It does not
choose a proxy, infer HOST authority, publish network state or change the NPC.
No default runtime, package, installed file or protocol is changed.

The reason for this tool is concrete: the same character record does not prove
the same current appearance. Record defaults, a chosen Judy/Mitch profile and
the actor currently rendered by the engine are different evidence.

## Optional manual setup, not performed in this checkpoint

In a future explicitly authorized development test, install this folder's
`init.lua` and `observer.lua` together as a **separate CET mod** named
`CP2077NpcAppearanceObservation`, and its `engine_hooks.reds` under a separate
`r6/scripts` directory. The verified helper requires Codeware and REDscript.
Do not replace the normal session mod. A missing helper produces a failed
observation; there is no guessed fallback.

The mod stays inert until an explicit request. Supply an existing exact actor
reference obtained by your game-thread test harness. It does not search for the
nearest NPC, select a target automatically or adopt an entity.

```lua
local probe = GetMod("CP2077NpcAppearanceObservation")
probe.request("example", exactNpcReference) -- queues only, no engine access
probe.status("example")                    -- copied cached result only
probe.reset()                              -- queues shared reset
```

Do not pass a numeric EntityID or a debug string. The request retains the opaque
actor reference. Its exact EntityID is pinned on the next eligible `onUpdate`,
not at the time the request was queued. All native reads happen in `onUpdate`.

## Results and limits

`request(label, actor)` returns `accepted, reason, ticket`. There are at most
eight distinct labels until reset. A newer pending request for the same label
coalesces the older one. Labels are 1-48 ASCII letters, digits, `_`, `.` or `-`.
A full queue rejects a ninth label. No request is silently dropped to make room.

`status(label)` returns a copied result with `valid`, `reason`, `ticket`, local
`scope`, capture `frame`, `historical=true` for successful captures, and
`visualQualified=false`. The `observed` table contains:

- `entityId`, `contextId`, `recordId`, `templateHash`, `appearanceHash`,
  `colorHash`: exact canonical decimal strings produced natively. Lua never
  converts these through a floating-point number or parses a debug string.
- `templatePath`, `appearance`, `color`: actual native readable values. Separate
  `templatePathAvailable`, `appearanceNameAvailable`, `colorNameAvailable`
  flags report whether a readable symbol was present. The hash remains evidence
  when the symbol is empty. Observed `None` and a zero CName hash remain observed
  values; they do not become a requested/default appearance.

A capture is a **historical one-shot sample**, not a continuously refreshed
appearance. A subsequent appearance change requires another request. Cached
target identity is checked on updates, without reading appearance again. A
detached/replaced target invalidates its cached tuple. Native reference checks
accept fresh CET wrappers for the same native entity and reject a different
native entity occupying the same ID.

Unknown/paused/pre-game context, unload, a replaced local player, context read
exceptions or an invalid/over-one-second update gap invalidate active evidence
and pending requests. The local scope advances; it is not a network epoch or
session ID. This standalone tool cannot detect a network-only reconnect when
the game world and local player stay unchanged. Call `reset()` at such a boundary
from the future test harness. There is no SessionBridge integration here.

The helper checks exact target and context attachment, IDs and global native
references before and after reading. It rejects a changed record, template hash,
appearance or color during capture. Unknown record/template hashes fail. Missing,
throwing or malformed helpers fail explicitly; a rejected request requires an
explicit retry. No stale result can be published under a newer label ticket or
after a reset/shutdown requested during capture.

`reset()` immediately invalidates cached evidence and blocks new requests until
the next update clears retained references. Shutdown clears them without engine
operations. Frame/ticket/scope counters do not wrap: they stop at 2,147,483,647.
Diagnostics emit at most 64 compact result lines per mod instance, including
across resets. There is no per-frame logging or automatic retry loop.

This tool never spawns, moves, changes AI, health, appearance or color, deletes,
adopts or sends an entity. A valid observation does not prove visible skin,
materials, clothing, animation, NPC matching across PCs or network authority.
Full live getter/CET behavior and visual matching remain untested.

See [VALIDATION.md](VALIDATION.md) for the source/build evidence and pending gates.
