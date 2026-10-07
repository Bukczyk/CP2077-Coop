# Shared encounter engine findings

KyleBuildsAI, 2026-10-07 UTC. Game-side evidence for the six questions in [PR #7](https://github.com/Bukczyk/CP2077-Coop/pull/7). This document does not approve new wire fields or implement combat networking.

## Checkpoints and ownership

- Networking proposal: main `d3670d94d96c40fe4f24e6e983d343a09f50d38f`, [shared encounter contract](https://github.com/Bukczyk/CP2077-Coop/blob/d3670d94d96c40fe4f24e6e983d343a09f50d38f/docs/SHARED_ENCOUNTER_PROTOCOL_PROPOSAL.md). At this revision, `SessionBridge::SubmitWorld` returns `Unsupported`.
- Passive projection experiment: `7768923d92db8c7ab0f654dc80d896994edeabbc`, branch `feature/passive-network-humanoid`.
- Game-side validation branch: `feat/passive-humanoid-validation`; the implementation owner records its final tested revision and outcomes below.
- [PR #8](https://github.com/Bukczyk/CP2077-Coop/pull/8), head `07887fffc9a53ca491b125a628f32cf034a6f50e`, was open when checked. It adds a bounded request/outcome ledger and tests. Its description explicitly says the ledger is not wired to gameplay message types. Its reported Windows/13-test result is not a live combat test.
- Bukczyk owns request identities, routing, deduplication, authoritative event delivery and reconnect state. KyleBuildsAI owns engine observation/application, passive rendering and live measurements. Both review data meaning and complete-feature acceptance.

Engine references use the [reconstructed 2.31 script corpus at `a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a`](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a). The pinned corpus was inspected locally. Source presence, successful compilation and observed live behavior are different evidence levels.

## Compiled probe and controlled target

The opt-in [engine probe](../experiments/shared-encounter/engine_hooks.reds) and its [usage notes](../experiments/shared-encounter/README.md) compiled with the current typed session scripts and Codeware at `2026-10-07T01:50:10Z`. The compiler exited successfully, with source and read-only game-reference hashes unchanged. Probe SHA256: `7fb1b1f4ecb62cd26dadf8de3291d7e695c995bfed52f5b71c17dc762c4d7490`.

That probe ran on one Windows PC with two clients from `01:52` to `02:03 UTC`. Three synthetic HOST weapon-pipeline hits changed actual Health, including one persistent death; a directed gunshot was received and followed by a HOST AI transition; exact CET entity binding survived JOINER recreation. These are partial engine results. The JOINER mesh remained standing when the HOST NPC died, and no network combat route was exercised.

The first probe's REDscript `local=` text was unstable because of its `EntityID.ToHash` diagnostic call path. Exclude that field from the first run's identity evidence; CET `.hash` and exact resolver results remained stable. The direct-field source correction compiled successfully, SHA256 `8e2cfb3140b1965cd08bdb733cda930be2a5180c5c952805c363e5ddd8f4a61a`, and was installed at `02:06:39Z` for a second run. All 1,692 engine log entries then reported HOST local `10713017`, matching CET `.hash` across approximately 180 seconds, with zero mismatches; the accepted session entity was `4294967296`. The diagnostic correction therefore has live evidence; it does not retroactively make the first run's bad text valid.

The second run also tested archive SHA256 `139952bee5243c64c766744a350ab1ae1f4269aa427d20954467311e450b10b3`, containing a minimal idle animation graph. The operator observed an idle pose in place of the earlier T-pose. This establishes an improved rendered pose; continuous playback is not yet quantified, and no HOST animation, hit reaction or death animation is replicated. JOINER recreation changed local `10712978 -> 10713025` while retaining session entity `4294967296`. Natural pistol firing remains unverified after further attempted input without ammunition use.

Both HOST and JOINER position coordinates stayed constant throughout that second run. Its zero placement error therefore proves stationary placement only, not moving-projection quality, interpolation or latency. The idle archive still needs a movement trial. Both clients ended with zero network NPCs and an empty JOINER projection inventory; automatic timed cleanup may have preceded the operator's cleanup key.

The probe only records explicitly enabled NPCs managed by Codeware and tagged `CP2077Coop.ControlledEncounter`. Every wrapper calls the original method, preserving its return value where applicable. A session, epoch or local-generation change invalidates scope. There is no production encounter route, automatic ambient-NPC instrumentation or protection removal.

Use an explicitly spawned disposable humanoid, validate its record before creation, and disable persistence. The earlier controlled harness uses `Character.spr_animals_bouncer1_ranged1_omaha_mb`. A record being available does not guarantee that every damage/reaction path works. The original experiment's Judy representation remains suitable for testing basic rendering; it does not establish arbitrary appearance matching or combat support.

The passive asset's [source](https://github.com/Bukczyk/CP2077-Coop/blob/7768923d92db8c7ab0f654dc80d896994edeabbc/runtime/session/assets/source/raw/base/cp2077coop/entities/CP2077Coop_NetworkHumanoid.ent.json) contains a plain `entEntity`, animated component and skinned mesh, without a declared `GameObject`, NPCPuppet, collider or hit-representation component. `gameHitEvent.target` expects a `GameObject`. Therefore ordinary weapon-hit capture against this passive projection remains a separate unresolved gate. Rendering it successfully cannot satisfy that gate.

## 1. Candidate hit and trustworthy context

**Compiled candidate:** the probe wraps `DamageSystem.PreProcess(hitEvent, cache)` and records the controlled target before vanilla preprocessing. It also observes `DealDamages` afterward. Neither wrapper changes the hit. Scoped `RegisterSyncListener` callbacks at `PreProcess` are a source-verified alternative, but this probe does not register them. [S1]

Real hit events declare a target, hit position/direction and optional component/hit-shape data. `AttackData` provides instigator, source, optional weapon, attack type/origin and local attack time. These values require null checks and availability tests. A local weapon EntityID, object pointer, hit-shape object or local timestamp is not a portable authoritative identity or shared clock. The HOST must independently validate any JOINER observation. [S2]

The earlier `ProcessLocalizedDamage` wrapper is unsuitable as proof of final damage: dodge, mitigation and further modifiers follow that stage. Its NPC cast also cannot observe a plain passive entity. Do not restore coordinate-matched targets, movement sentinels or client-proposed damage.

**Proposed first action:** one supported single-shot ranged action against the registered controlled NPC. Beyond the target identity, action kind and finite observed origin/direction are candidate evidence to evaluate. Their final shape, optional impact data and HOST geometry validation are not fixed by this document. A HOST shot/raycast path may be necessary if the passive entity cannot generate a valid native hit. The current probe's synthetic HOST hit does not validate JOINER aim or collision.

**Live evidence:** all three synthetic HOST hits entered `candidate_before_preprocess -> after_preprocess -> after_deal_await_readback`, followed by a later Health change. Their callbacks had a defined instigator and weapon, `Ranged(10)`, finite hit XYZ and one synthetic hit shape. These values were constructed by the HOST fixture. Availability/trustworthiness for a natural JOINER shot, miss or passive hit is still unverified. Attempted pistol clicks did not establish a fired shot; ammunition stayed unchanged.

**Backend requirement:** keep authenticated source player, target session identity, session/epoch and deduplication identity separate from optional observed geometry. Resolve and authorize the target/source on HOST, reject stale or unsupported requests before mutation, and never trust client-proposed damage. The game adapter can validate a tracked exact NPC reference today; production JOINER aim-to-HOST-hit validation remains a game-side gate. This is semantic guidance, not a new payload schema.

## 2. First stimulus

**Compiled capture:** opt-in local-player observation of `StimBroadcasterComponent.TriggerSingleBroadcast` for `Gunshot`. Vanilla firing logic uses this method, but one shot can create multiple audio/visual stimulus calls. The probe labels semantic shot count unverified. It does not interpret every callback as a new network request. [S3]

**Compiled local apply:** `HostGunshot` sends a directed `Gunshot` from the actual HOST player to only the tagged NPC through `SendStimDirectly`. `ReactionManagerComponent.OnEventReceived` records receipt while preserving vanilla handling. Receipt is not proof of accepted AI behavior or a visible reaction. This fixture does not forge a JOINER sender. [S4]

For a real JOINER request, authenticate the source player and resolve its actual HOST representation. A gunshot need not identify a target NPC. HOST should choose supported stimulus/range behavior and validate any supplied location; arbitrary remote game enum/radius values are not authority. Confirm that the source representation has the needed broadcaster before defining its production adapter.

**Live evidence:** one directed fixture produced `gunshot_stimulus_received`, then the controlled HOST NPC changed from `Relaxed(5)` to `Combat(2)` with Health unchanged. This happened about 17 seconds before the first synthetic damage command, so the later hit did not cause that earlier state transition. The receipt and transition support this one local apply path; they do not prove matching JOINER reaction. The local-player gunshot-capture arrays remained empty, so natural firing capture and deduplication are still unverified. A second receipt appeared after the lethal hit and is not attributed to the earlier directed request.

**Backend requirement:** carry an authenticated action request to HOST; HOST chooses the supported gunshot semantics and source representation. Distinguish accepted/queued from received and from an observed AI-state result. Do not send back an invented successful reaction merely because the call returned. A network stimulus's final source location/range policy still needs HOST validation, not arbitrary remote enum/radius control.

## 3. Apply damage once and observe the result

**Compiled local pipeline fixture:** `HostWeaponHit` constructs an attack from the HOST player's current ranged weapon and submits `DamageSystem.QueueHitEvent` to the exact controlled target. Vanilla code supplies a construction precedent. The fixture accepts no JOINER identity, client damage or client weapon; it uses synthetic body-position geometry and does not consume ammunition. It tests the damage pipeline, not a physical projectile, hit validation or shared loadout support. [S5]

`HostHealthDrain` is a separate raw-pool fixture. It bypasses ordinary weapon/armor calculation. Both methods distinguish queuing from subsequent observation and reject duplicate/old local fixture IDs and a second in-flight operation. Those fixture IDs are not networking request keys.

`DealDamages` calls `StatPoolsManager.ApplyDamage` then sends result events. The computed amount and per-pool loss entries are useful evidence, but queued pool requests, minimum-health rules and other affected pools prevent treating them as final Health loss without readback. The probe reads explicit Health points and persistent life state on later game-thread updates. A health change is labelled as an observation with attribution unproven if other causes may be present. A scoped stat-pool listener is another source-verified candidate. [S1, S6]

Exactly-once invocation requires reservation/deduplication before game mutation. Engine calls alone cannot supply that guarantee. Reserve output capacity and revalidate scope when executing. Result semantics should include observed resulting health/life and causal correlation when established. Final units, revision rules and payload fields require joint review. Keep defeat distinct from death, and preserve zero-effect/blocked outcomes rather than inventing damage.

**Live evidence:** request 2 changed Health `221.400757 -> 157.567032`. On a fresh controlled NPC, requests 3 and 4 produced `221.400757 -> 101.900208 -> 0.221401 -> 0`. Each immediate duplicate was rejected, with exactly three corresponding pipeline entries in the trace. Every `after_deal` callback still read the pre-hit Health; later readback supplied the actual pool change. This directly demonstrates why computed damage and call return are insufficient as final outcomes. Other causes of Health change are not generally excluded by the probe. Zero-effect, invulnerable, unsupported and concurrent external-damage cases remain untested. No network exactly-once or shared combat claim is made.

**Backend requirement:** reserve one request before entering the game thread, keep it pending until an observed outcome or explicit unresolved failure, and replay the stored result for a duplicate. Do not retry an uncertain mutation under a fresh request identity. Provide a correlation token to the adapter, while allowing spontaneous HOST changes that have no client request. Health here is read as points (`percentage=false`); confirm the wire representation jointly rather than interpreting it as percent.

## 4. Death and lifecycle

**Compiled observers:** `NPCPuppet.OnDeath` and `ScriptedPuppet.OnDied`. The latter sets persistent dead state read by `IsDeadNoStatPool()`. Death handling can involve queued tasks, so the probe records callback entry separately from later state. [S7]

`IsDead()` checks Health at its minimum. The NPC health listener can mark defeat instead of death. Neither a minimum Health value, potential-death event, missing object nor despawn is sufficient on its own to publish `EntityDeath`.

Keep the exact session/epoch/entity binding until the transition is captured. Production needs one death/tombstone transition per accepted entity life, causal damage ordered before death, and current life state in reconnect baselines. Streaming removal is not death. Revival/respawn needs an agreed new-life identity policy; do not clear tombstones because a new local object appears.

A passive mesh disappearing is cleanup, not a verified death animation, corpse, loot or ragdoll implementation.

**Live evidence:** the lethal trial first read `0.221401` Health with `persistentDead=false`. `OnDeath` then logged Health zero while persistent dead was still false; `OnDied` after vanilla logged true, and later readbacks retained it. Each callback was recorded once. The operator observed the HOST collapse; the JOINER mesh stayed standing. Defeat remained false in this trial, so a true defeat case remains untested. There is no replicated death/tombstone or matching death animation yet.

**Backend requirement:** preserve damage-before-death ordering and the current life state for reconnect; deduplicate one death transition per accepted entity life. Use the persistent-dead observation as evidence for this tested path, not the earlier minimum-health value. Deletion/unloading must use a different lifecycle reason. The game adapter must explicitly report unresolved cases rather than infer death from disappearance.

## 5. Entity types and exact lookup

First encounter scope is one registered HOST-owned humanoid NPC. Player PvP, vehicles, drones/mechs, mission-critical actors, quickhacks and arbitrary campaign population remain separate acceptance tasks.

The existing HOST route offers the local ID with `CP2077Session_NpcOffer`; accepted `RenderNpc` supplies `descriptor.entity` and `hostLocal`. `BeginFrame` binds these in `EntityRegistry`. Its internal `Find(SessionEntityId)->Projection.local` is the forward lookup; `FromLocal(LocalEntityId)` is the reverse. The exposed `CP2077Session_Resolve` performs only local-to-session lookup. [S8]

An engine-side index can use existing tracked HOST references and their nonzero `Resolve` results after adoption. Clear/rebuild it on session/epoch/generation changes, and recheck the actual local ID and attachment before applying effects. A narrow forward-lookup native is another possible reviewed bridge change, not an existing API. Neither approach needs nearest-position or name matching.

JOINER's adapter retains the returned local ID and exact session binding. Preserve opaque Uint64 values through Lua. Same position or record never means same entity.

**Live evidence:** first NPC: HOST local `10712431`, session entity `4294967296`, JOINER local `10712441`. Second NPC: HOST local `10712471`, session entity `4294967297`. During JOINER reconnect/recreation, its local object changed `10712458 -> 10712461`, retaining session entity `4294967297`. Across 2,787 bound samples, CET `Resolve(local)` matched the adapter's exact session entity every time. Old bindings became zero before adapter inventory removal. Inventory absence alone is not independent engine-object destruction evidence. Same-coordinate multiple entities remain untested.

In the subsequent corrected-logging/idle-pose run, HOST `10713017` was bound to session entity `4294967296`; JOINER recreated `10712978 -> 10713025` without changing that session entity. All 1,697 bound samples matched their resolver results. This is a separate session run, so a reused numeric session entity value is not evidence that the earlier authoritative life persisted across server sessions.

**Backend requirement:** route by session entity and ownership/epoch, never by game-local ID, appearance or coordinates. Treat a JOINER local-ID replacement as a projection rebuild of the same authoritative life, not an automatic respawn or resurrection. Current tested scope is the disposable HOST humanoid; plain passive JOINER hit capture is still unsupported/unverified.

## 6. Queue/failure behavior

The current portable `EventInbox` defaults to 256 entries, returns explicit full/stale/authority results and does not silently evict committed events. This is source-verified scaffolding, not an integrated encounter queue or measured engine throughput guarantee. The probe caps its diagnostic logs at 256 NPC entries and 128 player gunshot entries; these are not reliable network queues. None of these numbers sets a production message rate or supported player capacity. [S9]

Game hooks must return promptly, transfer scalar observations through bounded storage and avoid engine objects on network threads. Distinguish ingress acceptance, relay forwarding, engine pending state and observed outcome. Recheck epoch on the game thread. Overflow must produce explicit failure before a requested mutation, or retain/resynchronize an already committed outcome. Drain limits need measurement rather than a guessed capacity promise.

Spontaneous vanilla HOST damage/death can occur without our request admission. We cannot promise that reserving a queue slot prevents every such world event. The design therefore needs retained authoritative state and a resynchronization path when outcome delivery cannot keep up.

JOINER may play its own local shot effects immediately. Shared damage/death/rewards await HOST outcomes. Unsupported/rejected requests clear pending presentation; delayed requests may show a rate-limited busy indication. No local-damage fallback or automatic new request ID for retries. PR8 can handle independent request bookkeeping while these engine semantics are qualified.

**Live evidence:** three immediate duplicate fixture calls were rejected and did not create additional pipeline entries. Busy, overflow, unsupported, queue load, disconnect during a pending operation and replay/resynchronization have not been exercised. The probe's one-in-flight operation guard is a fixture constraint, not a production throughput limit.

**Backend requirement:** expose explicit accepted/pending/observed/rejected/unresolved outcomes with no silent replacement of committed work. Keep retained authoritative state available for resynchronization, including spontaneous vanilla outcomes. Implementing PR8's generic reservation/outcome ledger does not depend on choosing an arbitrary engine messages-per-second limit; measure the adapter's drain behavior before setting a supported rate/capacity.

## Live acceptance record

First run: one PC, two clients, two explicitly spawned NPC lives. Second run: the corrected logging probe and idle-pose candidate, on the same local topology. Installed hashes and separate evidence limits are recorded above. Remaining gates must be completed separately before claiming the shared-encounter milestone.

| Check | Result |
| --- | --- |
| Passive entity visible, movable and free of autonomous AI | First run had a Judy T-pose. Second run produced an idle pose but stayed stationary. Movement with the idle archive, continuous animation and general passive-behavior qualification remain separate. |
| Ordinary weapon hit against passive projection | UNVERIFIED; passive native hit-target path unresolved. |
| Exact identity and confirmed cleanup/reconnect | Exact binding and reconnect recreation observed; independent engine destruction audit remains separate. |
| REDscript local-ID diagnostic | First-run ToHash text invalid; all 1,692 corrected direct-field entries matched CET ID over approximately 180 seconds in the second run. |
| Physical shot candidate and post-pipeline observations | UNVERIFIED; attempted clicks did not establish a fired shot. |
| HOST synthetic pipeline hit and later Health readback | OBSERVED, three fixtures; constructed geometry, not a physical shot. |
| Directed gunshot receipt and actual AI reaction | OBSERVED receipt then HOST Relaxed -> Combat before damage; no matching JOINER reaction. |
| Death versus defeat and persistent-dead readback | Persistent HOST death observed with callback ordering; defeat untested; JOINER remained standing. |
| Duplicate/busy/unsupported fixture behavior | Three immediate duplicates rejected; other cases pending. |
| JOINER action -> HOST result -> matching JOINER outcome | PENDING; backend connection required |
| Separate-PC encounter qualification | PENDING |

## Source index

- S1: [damageSystem.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/damage/damageSystem.swift), lines 18-27, 260-277, 306-318, 560-581, 1285-1317, 2709-2743.
- S2: [orphans.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/orphans.swift), 18681-18702; [attackData.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/damage/attackData.swift), 132-156 and 192-256.
- S3: [weaponTransitions.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/player/psm/weaponTransitions.swift), 1895-1973.
- S4: [stimBroadcasterComponent.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/core/components/stimBroadcasterComponent.swift), 129-177 and 227-253; [reactionComponent.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/core/components/scriptComponents/reactionComponent.swift), 1012-1018.
- S5: [triggerAttackOnNearbyEnemiesEffector.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/core/gameplay/effectors/triggerAttackOnNearbyEnemiesEffector.swift), 195-216; [weapon.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/items/weapon.swift), 59-61. Only the exact-target construction is relevant; this probe does not run that effector's nearby-target selection.
- S6: [statPoolsManager.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/damage/statPoolsManager.swift), 147-195, 234-267 and 293-325; [statPoolsSystem.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/core/systems/statPoolsSystem.swift), 2-4.
- S7: [NPCPuppet.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/NPC/NPCPuppet.swift), 20-54, 656-677 and 3024-3045; [scriptedPuppet.swift](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/cyberpunk/puppet/scriptedPuppet.swift), 282-288, 1557-1563 and 2134-2142.
- S8: [native binding](https://github.com/Bukczyk/CP2077-Coop/blob/d3670d94d96c40fe4f24e6e983d343a09f50d38f/CoopPlugin/src/main.cpp#L74-L130); [registry](https://github.com/Bukczyk/CP2077-Coop/blob/d3670d94d96c40fe4f24e6e983d343a09f50d38f/shared/src/game_bridge.cpp#L9-L38); [passive adapter](https://github.com/Bukczyk/CP2077-Coop/blob/7768923d92db8c7ab0f654dc80d896994edeabbc/runtime/session/cet/CP2077Coop/npc_static_population.lua#L26-L81).
- S9: [queue scaffold and unsupported bridge](https://github.com/Bukczyk/CP2077-Coop/blob/d3670d94d96c40fe4f24e6e983d343a09f50d38f/shared/include/coop/game_bridge.hpp#L54-L93); [queue admission](https://github.com/Bukczyk/CP2077-Coop/blob/d3670d94d96c40fe4f24e6e983d343a09f50d38f/shared/src/game_bridge.cpp#L40-L55).
- S10: [script enums](https://codeberg.org/adamsmasher/cyberpunk/src/commit/a2e6bb31298fc7c613e5bfa3d22d424cdeca3f9a/orphans.swift), attack type at 1027-1044 and NPC high-level state at 4876-4888: `Ranged=10`, `Relaxed=5`, `Combat=2`, `Dead=3`.
