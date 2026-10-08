# Passive cosmetic player experiment

Owner: KyleBuildsAI. Source: `84166374849f1c7f512fb0e2cb87f165305318dc`;
trial source: `481609a57ccf775657818fe059f6b87652836ef3`.
This is an opt-in engine fixture, not player combat or a replacement gameplay release.

## Why this exists

A normal Judy player proxy blocked the independent HOST validation ray by being
its first hit. Exact-instance `DisableCollision()` did not remove that obstruction
in trial 4. The experiment uses the already verified render-only NetworkHumanoid
asset for remote player presentation, so the controlled ray can begin at the
correct authenticated sender without moving past an arbitrary obstacle or
weakening nearest-hit/target checks.

## Implementation and default

`runtime/session/cet/CP2077Coop/config.lua` ships with
`experimentalPassivePlayers = false`. The normal player path remains
`player_pose.lua` with one owned AI teleport command per Judy proxy.
Explicit true selects `player_passive.lua` instead; both representations do not
operate on the same player.

The passive adapter uses Codeware `StaticEntitySystem` and
`base\cp2077coop\entities\cp2077coop_networkhumanoid.ent`, requiring the
experimental archive. It has separate `CP2077Session.PassivePlayer` tags and
never uses the controlled NPC target tag. The original idle-only asset has no
player hit collider or NPC AI. No PvP or exact Remote V appearance is provided.

The game-thread controller retains exact spawn tokens and opaque 64-bit entity
identities through pending creation, verifies returned actors, binds only their
exact session identity, and never matches by proximity. It bounds the input
collection and retry rate. Old dynamic player bodies must disappear before
passive activation. Despawn acceptance is not disappearance; unresolved tokens
remain owned through unload, scope reset, bridge failure and explicit reconnect.
Static transform submission is not proof that the actor reached its target;
actual position is checked separately by the live fixture.

## Automated evidence

`tests/passive_player_tests.lua` has 108 checks for identity, pending creation,
retirement, failure paths, scope changes and the actual entrypoint selecting only
the opted-in representation. Tests verify the shipped flag is false. These tests
use opaque-ID mocks and modeled engine calls, not native engine objects.

Hosted Windows, Debian and sanitizer validation passed at the exact trial source:
[run 37725557131](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37725557131).
The compatible mirror separately ran the same passive suite under LuaJIT 2.1;
that runner choice does not turn opaque mocks into actual cdata or a live test.

## Trial 5 observations and limits

On one Windows PC with two low-graphics clients, the passive sender mapped exactly
to HOST actor `10727407`, session player/entity `2`. Independent HOST validation
accepted the genuine JOINER shot's exact controlled NPC as the first hit, without
hitting the sender or relaxing the existing origin/target checks. This removes
the previously observed self-occlusion for that controlled encounter only.

Two accepted requests then produced observed HOST health loss and persistent
death through the labelled HOST-current-weapon fixture, returned outcomes, and
the same JOINER NPC's reaction/death display. Exact times, actor mappings, causal
records and visual evidence are in the [connected checkpoint](CONNECTED_ENCOUNTER_2026-10-08.md#trial-5-connected-controlled-encounter).
The early failed session admission is retained separately, not counted as a
passive-player gameplay failure or successful test.

The body is cosmetic and idle-only. This does not qualify player appearance,
weapons, ADS, locomotion, native bullet collision, PvP, JOINER attacker/weapon
credit, broader shared AI/world behavior, two-PC operation or a live capacity.
The separate NPC corpse-recreation attempt also triggered native quickload;
after reconnect its catalog identity returned but its terminal death did not.
That known recovery failure remains open. No public package version was created.

Controlled cleanup also completed: exact HOST source disappearance and empty
JOINER projection lists were observed. Test-owned games/server are closed;
original runtime, bindings/settings and current saves were restored or preserved
as recorded in the [connected checkpoint](CONNECTED_ENCOUNTER_2026-10-08.md#cleanup-and-retained-evidence).
