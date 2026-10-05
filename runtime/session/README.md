# Typed game integration foundation (not a gameplay release)

Default plugin: build/windows/CoopPlugin/Release/CP2077Coop.dll. Matching files are in this directory only. Generate role-specific, non-installed packages with `./scripts/package-session.ps1 -Server <IPv4> -Session <name> [-AccessKeyFile <path>]`; it creates HOST/JOINER profiles, matched scripts, Debian config/key and hashes under ignored artifacts/. Rates default to 60 Hz; interpolation is sampled on every CET update. No save or installation writes occur.

The native frame is coherent from BeginFrame until the next BeginFrame. SetActive(false) invalidates it; workers own SessionClient and never access REDengine. SessionEntityId/engine EntityID remain exact 64-bit values. Game-thread EntityRegistry holds Player/NPC/Vehicle/World projections and rejects foreign epochs, authorities and duplicate local bindings. Player IDs currently correspond to server-registered player EntityIds. World-action contracts and a separate bounded reliable inbox are in shared/include/coop/game_bridge.hpp. SubmitWorld returns Unsupported until the complete authority route exists.

Judy is a temporary non-persistent player proxy, not an NPC simulation implementation. Spawned proxies use unique PlayerId tags and are removed on interest loss/disconnect. JOINER teleports once to its received HOST baseline. The engine transform setter consumes interpolated samples each render frame; it does not apply raw packets. Native registration/CET names are checked by CTest; this does not compile REDscript or certify actual engine behavior.

## Missing hooks/routes for Shared World Reaction MVP
- VPS entity allocation/adoption acknowledgement for NPC/Vehicle/World, snapshot descriptors/archetypes, stable IDs across local streaming and explicit session epoch reset. Never derive identity from coordinates or invent it from a nearest-NPC query.
- HOST observation of ambient/mission NPC creation, streaming, despawn and death. Codeware DynamicEntitySystem creation/deletion/events are available in the inspected local declarations, but they do not establish complete coverage of all engine NPC lifecycles.
- JOINER projection creation from authoritative descriptors plus scoped suppression of local AI, physics ownership and local damage decisions for those network-owned NPCs. Judy proxy AI is not yet suppressed; NPC authority cutover is not enabled.
- Fire/action capture and HOST stimulus injection to activate authoritative AI reactions; define the supported stimulus semantics before enabling PlayerFire/WorldStimulus.
- Stable-entity hit capture, HOST hit validation and damage/death application hooks with event/request deduplication; suppress duplicate local damage only for mapped network entities. No position-based target lookup.
- Reliable gameplay transport/codec/server routing for EntityAdopt/Spawn/Despawn, PlayerFire/WorldStimulus, HitRequest/DamageApplied/EntityDeath; sequenced NpcState and late-join lifecycle baseline. Existing session controls are reliable TCP; world contracts currently have no live route.
- Confirmed load/streaming teardown hooks and HOST world epoch reset on save load. Current CET attachment/pregame checks and reconnect hotkey are a foundation, not full world-load synchronization.
- Isolated REDscript compilation and later engine validation of proxy spawning, per-frame placement, baseline teleport, handle invalidation and cleanup. No in-game test requested yet.

## Rollback
Build frozen plugin with COOP_LEGACY_PLUGIN=ON in a separate build directory. Pair it with the original runtime/cet, runtime/redscript and runtime/tweaks files and the legacy relay. Never load both plugin variants or mix native declarations. Packaging does not perform cutover; it includes a disabled combat.reds placeholder so legacy sentinel combat cannot remain in a future overlay. Complete old mod backup/removal and rollback installation automation remain required before any gameplay distribution.
