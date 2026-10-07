# Typed game integration foundation (not a gameplay release)

## CET startup and player session lifecycle

The NPC observer registers during `onInit`, when CET exposes `Observe`. Player
load/replacement checks compare the exact `EntityID.hash` Uint64 value; a fresh
CET wrapper for the same player must not restart the session.

`cet/CP2077Coop/config.lua` defaults `experimentalNpcReplication` to `false`.
Player sessions and player proxies remain enabled. HOST NPC discovery/offers and
JOINER NPC projection updates require explicit opt-in on both clients. This is a
development gate while passive AI and exact live NPC behavior remain unverified;
enabling it does not make shared NPC simulation safe. Edit it with games closed
and restart both clients for a controlled NPC experiment.

See [lifecycle validation](../../docs/validation/CET_SESSION_LIFECYCLE.md) for the
focused test record. Player proxy movement remains a separate unresolved issue.

Default plugin: build/windows/CoopPlugin/Release/CP2077Coop.dll. Matching files are in this directory only. Generate role-specific, non-installed packages with `./scripts/package-session.ps1 -Server <IPv4> -Session <name> [-AccessKeyFile <path>]`; it creates HOST/JOINER profiles, matched scripts, Debian config/key and hashes under ignored artifacts/. Rates default to 60 Hz; interpolation is sampled on every CET update. No save or installation writes occur.

The native frame is coherent from BeginFrame until the next BeginFrame. SetActive(false) invalidates it; workers own SessionClient and never access REDengine. SessionEntityId/engine EntityID remain exact 64-bit values. Game-thread EntityRegistry holds Player/NPC/Vehicle/World projections and rejects foreign epochs, authorities and duplicate local bindings. Player IDs currently correspond to server-registered player EntityIds. NPC adoption/state/release use the bounded SessionBridge NPC interface and protocol v3. Other world-action contracts remain Unsupported; no combat or stimuli are enabled.

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

## First Shared World NPC foundation
HOST discovers NPCPuppet OnGameAttached callbacks on the game thread, adopts relevant sources using their exact engine EntityID, and stops replication after source detachment. The server allocates stable NPC IDs above the PlayerId namespace; records, transforms and lifecycle are restored to reconnecting JOINERs. Repeated adoption does not create another entity. Transport defaults: players/vehicles 60 Hz, NPC state 20 Hz with distant routing at 10 Hz. NPC capacity/rates and bubble radius are configurable. Record identifiers contain only the portable 40-bit TweakDB name, never a local database offset.

The Session Bubble is a union of relevance spheres around available player snapshots. Position only controls relevance; it never selects or matches an NPC identity. JOINER receives a catalog independent of its local ambient population. `npc_runtime.lua` manages exact SessionEntityId projections through `npc_population.lua`. The JOINER adapter now creates a Codeware DynamicEntitySpec from the accepted TweakDBID, retains the returned EntityID while the entity streams, and binds only after `GetEntity(id)->GetEntityID()` exactly matches that ID. It updates through the existing game-thread teleport facility and deletes only IDs returned by its own CreateEntity calls. Session/epoch reset, catalog removal and disconnect release bindings and owned projections.

**Projection creation is implemented; the NPC authority gate remains closed for gameplay.** Codeware entity creation, streaming state, exact EntityID lookup/deletion, and the existing CET teleport facility are verified against installed declarations/source and bridge usage. Created NPCs are active game entities: autonomous AI suppression and JOINER ambient population suppression are not implemented. Do not treat this as safe Shared World gameplay yet. Automated Lua coverage verifies asynchronous handle availability, exact mapping, duplicate prevention, despawn, epoch reset and reconnect with mocked engine APIs; it does not prove runtime behavior in game.

Remaining hooks before an actual in-game NPC milestone:
- Reversible, scoped hide/freeze/suppression of unassociated ambient NPCs, including new streamed entrants; preserve original state, exclude mapped entities and restore on boundary/session exit. No ambient deletion is implemented.
- Disable autonomous AI/decision-making for network-owned projections before activation. Current Codeware `DynamicEntitySpec.active=true` starts spawning and is not an AI-disable switch. Recheck authority and record availability in a controlled in-game test after adding a verified AI hook.
- Add reversible ambient NPC suppression/restoration in the Session Bubble. Verify this separately from projection creation; no ambient entities are changed by the current adapter.
- Verify spawn/delete, record availability and exact handle binding in game. Already-attached NPC enumeration and complete ambient/mission streaming coverage are not implemented; attachment discovery is the initial bounded source. This Lua-only adapter change adds no REDscript declarations; the earlier matched REDscript/native compilation gap remains.
- Verify save/load teardown and wire-level world epoch reset before treating a world reload as resumable. Current HOST disconnect ends the session; JOINER reconnect to a live HOST restores the NPC catalog. Epoch rejection/reset is tested in the policy/mapping core.

Do not start PlayerFire/WorldStimulus/HitRequest/DamageApplied/EntityDeath as an in-game milestone until this gate is resolved. No in-game test is requested by this checkpoint.
