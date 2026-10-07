# Controlled encounter engine probe

Opt-in local evidence only. This does not implement PR7 networking or certify passive-proxy hit detection. Install only through the private test runner after isolated compilation.

For the next engine checkpoint, read [physical shot capture and target queries](PHYSICAL_SHOTS.md),
[passive reaction/death presentation](PRESENTATION.md), and the
[trial results, failures and remaining gates](PHYSICAL_ENCOUNTER_CHECKPOINT.md).
These experimental modules are not installed by the normal session package.

Only an explicitly enabled `NPCPuppet` created/managed by Codeware DynamicEntitySystem with tag `CP2077Coop.ControlledEncounter` is observed. A session/epoch/generation change disables its scope. All wrappers always execute vanilla behavior. No listener is registered, no ambient actor is modified, and no god-mode protection is removed.

CET calls on the exact NPC returned by the private spawn:

```lua
npc:CP2077Encounter_Enable(true)
print(npc:CP2077Encounter_Readback())
for _, line in ipairs(npc:CP2077Encounter_Drain()) do print(line) end
-- HOST-local synthetic hit through the real damage pipeline, current ranged weapon:
print(npc:CP2077Encounter_HostWeaponHit(1))
-- Poll Readback on later frames. Use fresh increasing IDs after completion.
print(npc:CP2077Encounter_HostGunshot(2))
-- Optional HOST-only health-pool fixture, after session adoption:
print(npc:CP2077Encounter_HostHealthDrain(3, 5.0))
-- Poll Readback on later frames; this observes state, not causal attribution.
npc:CP2077Encounter_AbandonPending() -- unresolved request stays consumed
npc:CP2077Encounter_Enable(false) -- before cleanup/despawn
-- Separate opt-in local-player gunshot observation, useful on JOINER too:
Game.GetPlayer():CP2077Encounter_EnableGunshotCapture(true)
for _, line in ipairs(Game.GetPlayer():CP2077Encounter_DrainGunshots()) do print(line) end
Game.GetPlayer():CP2077Encounter_EnableGunshotCapture(false)
```

Fire a real supported weapon manually at this NPC for the first physical-shot test. `HostWeaponHit` constructs a local attack from the HOST player's current ranged weapon and queues it through `DamageSystem.QueueHitEvent`. It rejects absent/non-ranged current attacks, uses synthetic body-position hit geometry, and accepts no client damage, identity or weapon. This tests damage-pipeline execution, not physical collision, aim validation or JOINER input. It consumes no ammunition and must not be exposed as ordinary gameplay.

`candidate_before_preprocess`, `after_preprocess`, `after_deal_await_readback`, `death_callback` and `on_died_after_vanilla` are ordered observations. Calculated damage is explicitly labelled `computedNotObserved`; inspect later `readback` health and persistent-dead state. Raw pool drain is a separate fixture and bypasses normal weapon/armor calculation.

`HostGunshot` sends one directed Gunshot stimulus from the HOST's own player to only the tagged target. It does not forge a JOINER sender or broadcast across ambient NPCs. `gunshot_stimulus_received` means the reaction component received the event, not that it accepted/reacted; high-level readback and visible evidence remain necessary. Real local-player gunshot capture observes broadcaster calls, including possibly multiple audio/visual calls for one shot, and labels semantic shot count unverified.

Logs preserve the exact local and session IDs as strings and are bounded to 256 entries per NPC. `Drain` reports any overflow count. This diagnostic buffer is not the production reliable-event queue. Local fixture request IDs are strictly increasing, single in-flight and never reused; they are not network request keys. Concurrent health changes are not attributed to the fixture automatically.

Judy can have gameplay protections. Readback reports immortality/invulnerability without removing them. The earlier controlled harness uses `Character.spr_animals_bouncer1_ranged1_omaha_mb` and validates it with `TweakDBInterface.GetCharacterRecord` before spawning. Prefer that disposable reference record with persistence disabled; do not select an arbitrary nearby mission actor. An invisible/not-hittable plain `entEntity` cannot be instrumented by this NPC probe, and that limitation must remain explicit.

Engine source: reconstructed 2.31 corpus `a2e6bb3`, `damageSystem.swift` PreProcess/DealDamages, `NPCPuppet.swift` OnDeath, `scriptedPuppet.swift` OnDied/IsDeadNoStatPool. Live behavior must be recorded separately from compilation. Root owns deployment, game operation, evidence and cleanup.
