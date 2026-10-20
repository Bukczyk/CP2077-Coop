# Preserve the accepted NPC life baseline at the game boundary

KyleBuildsAI / Codex, 2026-10-20 UTC.

`SessionClient::RemoteNpc` retained the existing `NpcLifeState`, but
`SessionBridge::ReadFrame` constructed each `RenderNpc` without it. Consequently
the game could receive the NPC catalog and transform while losing its accepted
Alive/Defeated/Dead baseline, including after reconnect.

## Scope

This branch starts at player PR30, `fd3d100ba4624599c05a6238c5d4ee160bbd790e`.
It is independent of PR31's Lua cleanup fix. Their installed runtime files must
be combined explicitly; do not copy an entire older NPC module over PR31.

- Copy the already admitted optional typed baseline into each immutable game
  frame, under the existing mutex. No new packet, codec, server, authority,
  sequence, transport or interpolation behavior.
- Five read-only native getters expose known/health/max-health/status/revision
  for the selected NPC. The life entity must match that NPC's descriptor.
- The matching REDscript declarations and CET reader preserve exact opaque
  identity and typed values. Getter failure, missing API, unknown baseline,
  changed selection/revision and malformed data produce no baseline.
- The real CET entrypoint attaches `npc.lifeState` to its NPC frame. It does not
  change any entity's health, AI, reaction, life or animation. A zero health
  value alone is not interpreted as death.

KyleBuildsAI owns `shared/include/coop/game_bridge.hpp`,
`shared/src/game_bridge.cpp`, the native/REDscript/CET exposure files and their
focused tests. These shared-folder edits implement the local game boundary;
Bukczyk's protocol/client/server transport and authority code remain unchanged.

## Existing typed meaning

`NpcLifeState` supplies entity, health, maxHealth, status and revision. Status
values remain Alive=1, Defeated=2, Dead=3. Absent state is unknown, never an
invented Alive baseline. The getter API returns Known=false when absent; other
fallback zero values must not be applied without a valid baseline.

The reader returns a value copy only when identity, bounds and the selected
revision remain coherent. Older DLLs lack the getters; that is unavailable data
and does not stop existing CET movement. The NPC renderer still ignores the
new field until its separately qualified life-state application is connected.
No HOST engine health observer/publisher or authoritative death detector is
added by this patch.

## Validation

- Real localhost TCP/UDP regression with a real HOST SessionClient, session
  server and threaded JOINER SessionBridge. The old projection fails with
  `admitted Alive baseline is missing from RenderNpc`.
- Fixed path checks initial unknown, exact Alive health/revision, Defeated,
  Dead, immutable earlier frame, latest Dead on reconnect and no inherited
  baseline after a distinct replacement entity.
- Focused Lua reader tests cover adjacent opaque IDs above 2^53, no numeric
  identity conversion, health/status/revision bounds, unknown and unavailable
  APIs, thrown getters and changed selection/revision. Existing typed health
  zero/Alive semantics are preserved.
- The real init.lua lifecycle test verifies field forwarding and old-DLL
  movement compatibility, with no actor mutation.
- Windows Release experimental plugin/core build: PASS; CTest79/79 PASS,
  17.61 seconds. Production-v5 control core: build PASS; CTest77/77 PASS,
  14.88 seconds. Native registration/declaration contract passes.
- Complete matched installed REDscript sources with the new declarations
  compile in a fresh private sandbox using the installed compiler. All19 source
  input hashes remain unchanged. No game/cache/setting is written by that check.

These checks qualify data transfer, not live NPC reaction/death or world sync.
Native in-game loading and player-regression video are still pending at this
checkpoint. Preserve the tested installed M14/action4 + NPC cleanup1 recovery
package until its matched replacement passes. Stable v0.0.37 stays unchanged.
