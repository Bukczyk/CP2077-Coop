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

## Native loading and player regression

Both actual game copies loaded the matching DLL/declarations/CET files and
reached phase4 in the existing private32773 loopback session. All five new
getters were called from each CET console. With no selected NPC baseline,
Known=false and the other values are zero, not an admitted Alive/Dead result.
The native DLL hash is
`4112b5a9bed8e3cbd08ee34b9893543deea9fd8e2fd23fde25dd50a36558a399`.

A 92-second synthetic connected player-action route recorded117 seconds in
both real games: 2,592 HOST and2,612 JOINER original frames, completed with
unchanged recording tools and no capture errors.404/409 complete action4
diagnostic rows report no faults and root error <=0.000002 m. Exact actor IDs
are HOST10851968/10852095 and JOINER10852042/10852219 across rejoin.
Fifteen original frames per view were reviewed: expected low crouch, armed/aim,
idle, expiry/repair and reconnect poses remain present. No sustained T-pose is
seen in those reviewed visible samples. This is not physical-keyboard or WAN
qualification, or proof of positive NPC life-state application.

At code commit `f6ca4f7d5643ecdb0e3ec2b35c68aab17ab7016e`, all six hosted
Windows/Debian/sanitizer jobs pass, including both protocol configurations,
run39487402798. Raw smoke logs and video remain private. Both games/server
were then closed normally; all13 protected settings hashes and8 installed
task-file hashes match. No old settings or saves were restored.

The complete PRIVATE recovery package is refreshed to88 payload files with a
reproducible ZIP and explicit native/CET f6ca4f7 and NPC cleanup2f9ce9c source
provenance. Relative to the preceding86 files, only two DLLs, two native
declarations and two entrypoints change; two reader modules are added. No
server, animation asset, key, save or protected configuration is replaced.

Next: qualify the existing NPC life-pose fixture and then connect supported
engine observation/application. Existing backend baseline transport is present;
this remaining engine work is not waiting for a replacement network design.
