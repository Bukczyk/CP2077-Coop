# Connected encounter diagnostic

This opt-in experiment connects the existing physical-shot, HOST engine-observation
and passive-presentation probes to the reliable `GameplayIntent` / `GameplayResult`
route introduced by PR #11. It uses the existing protocol and server contract.
The `CPEX1` body below is a game-side diagnostic proposal, not an agreed production
combat schema or a new public runtime release.

The intended sequence is:

1. A real JOINER firing notification and its adjacent physics-query record identify
   the exact currently bound passive NPC. A miss or an unpaired notification does
   not submit an intent.
2. The generic bridge delivers the authenticated request to the HOST game thread.
3. HOST resolves the exact remote-player proxy and controlled NPC, independently
   checks the ray and reserves the target before calling the engine.
4. A labelled diagnostic applies the **HOST's current weapon** through the existing
   synthetic hit fixture. It does not reproduce JOINER weapon stats, ammunition,
   credit, spread, penetration or actual native bullet collision.
5. Strict engine records and later health/life readback produce one composite
   outcome after a settling interval. The result reports observed state, not a
   damage amount attributed to this request.
6. JOINER validates the HOST outcome and queues its existing reaction/death pose.
   Queue acceptance is not evidence that the pose was visually displayed.

Live checkpoint at `97d7c1a`: a real JOINER shot reaches HOST and its explicit
rejection returns through the reliable route. The player proxy now follows a
controlled placement, but the independent HOST ray hits the shooter's own proxy
before the NPC. No connected damage, JOINER reaction or death has passed.
See [the connected live checkpoint](../../../docs/validation/CONNECTED_ENCOUNTER_2026-10-08.md)
for exact evidence and the next gate. Earlier component evidence remains in
[the physical engine checkpoint](../PHYSICAL_ENCOUNTER_CHECKPOINT.md).

## Ownership and files

- `codec.lua`: bounded diagnostic body parsing and exact decimal identity helpers.
- `bridge.lua`: parsing of the generic native bridge's scoped string records.
- `host.lua`: default-off controlled request admission, target reservation,
  observation, rejection and immutable reply retention.
- `engine.lua`: adapter for already captured `engine_hooks.reds` records. The
  private harness remains the sole owner of the engine `Readback` / `Drain` calls.
- `host_ray.reds`: exact source/target registry checks and independent HOST ray.
- `shared/include/coop/game_bridge.hpp`, `shared/src/game_bridge.cpp`: generic
  SessionClient-to-game-thread queues. They contain no engine-object access and
  do not interpret `CPEX1` bodies.
- `CoopPlugin/src/main.cpp`, `runtime/session/redscript/CP2077Coop/natives.reds`:
  matched native registrations and declarations.
- `tests/gameplay_bridge_tests.cpp`, `tests/connected_encounter_tests.lua`:
  portable bridge and diagnostic validation.
- `tests/cet_require.lua`: test-only reproduction of CET's literal module-path
  lookup and nil/error return behavior, used by the connected Lua tests.

KyleBuildsAI owns these engine/bridge integration changes. Bukczyk owns the
protocol, session/server policy and authoritative routing contract. This
experiment does not add or change a protocol message or server-side combat rule.
Keep the work in draft PR #10; do not fold it into PR #9's passive identity,
cleanup and idle-animation update.

## CET module loading

Use `require("connected/engine")` and `require("connected/codec")`, with slash
paths. CET's sandbox loader checks a literal path and its `.lua` / `init.lua`
candidates; it does not apply stock Lua's dot-to-directory conversion. Missing
modules return nil plus an error value. The private runner asserts each module
load so a missing dependency is identified before controller construction.
See the [official CET v1.37.1 loader source](https://github.com/maximegmd/CyberEngineTweaks/blob/v1.37.1/src/scripting/LuaSandbox.cpp#L381-L454).

The connected suite loads all four modules through the test-only CET loader
model, rather than stock `package.path`. It verifies slash/extension caching,
missing dotted imports and a deliberately restored old nested dotted import.
This catches the loading regression that ordinary Lua module tests missed. It
does not reproduce the full CET sandbox, native bindings or in-game execution.

## Native ABI

All five functions return REDscript `String`. The prefix is `CP2077Session_`.
Call them on the game thread. The worker moves only copied, bounded values.

```text
GameplayScope()
GameplaySubmit(session: String, epoch: Uint32, generation: String,
               kind: Uint32, bodyHex: String)
GameplayReply(session: String, epoch: Uint32, generation: String,
              requester: Uint32, requestEvent: String, kind: Uint32,
              disposition: Uint32, reason: Uint32, bodyHex: String)
GameplayPoll()
GameplayFault()
```

`GameplayScope` returns:

```text
session|epoch|generation|self|host|phase
```

`phase == 4` means Active. Session, generation, session-entity, wire-event and local
ticket identities remain canonical decimal strings across the Lua boundary.
Never pass them through `tonumber`. Epoch and PlayerId are Uint32; kind and reason
fit Uint16. `Bridge.opaque` normalizes an opaque native Uint64/ULL string and
rejects Lua numbers. Keep the original native Uint64 when a REDscript method
requires one; use its string form only for validation/logging.

Submit is JOINER-only; reply is HOST-only and must match an admitted request.
The body is at most 1,024 bytes represented by at most 2,048 hex characters.
A successful local admission returns `queued|ticket`. Other returns are
`inactive`, `stale`, `authority`, `invalid`, `full` or `missing`, as applicable.
An identical completed reply may return its retained ticket; a changed reply for
the same request is rejected. Do not reapply an engine effect after a reply retry.

`GameplayPoll` returns an empty string when no event is available, otherwise one
of these exact records:

```text
intent|session|epoch|generation|sender|requestEvent|kind|bodyHex
outcome|session|epoch|generation|host|hostEvent|requester|requestEvent|kind|disposition|reason|bodyHex
sent_intent|session|epoch|generation|ticket|wireEvent
sent_result|session|epoch|generation|ticket|wireEvent
status|session|epoch|generation|correlationEvent|disposition|reason|committed
```

Disposition values are `1 Pending`, `2 Accepted`, `3 Rejected`, `4 Unsupported`
and `5 Full`. A result uses 2 through 5. The final `committed` field is `0` or `1`.
These are generic routing/ledger statuses. Neither a queued ticket, sent event nor
a committed status proves applied damage, observed death or rendered animation.
Only a scoped HOST `outcome` carrying a valid diagnostic result drives JOINER's
pose queue.

`GameplayFault` exposes a sticky transport/queue error. Treat a fault as a failed
test requiring explicit recovery. Preserve its text in evidence. Do not quietly
drop a pending engine action, retry it under a fresh request ID, or report it as
successful. HOST retains result bytes and preserves completion order while
handling result backpressure, with one result awaiting server acknowledgement.

## Diagnostic body proposal

The experimental kind is **32513**. It is a local proposal, not a reserved public
combat kind. `codec.lua` encodes the following ASCII body as hex:

```text
CPEX1I|targetSessionEntity|shotSequence|originX|originY|originZ|directionX|directionY|directionZ
CPEX1R|targetSessionEntity|healthPoints|maximumHealthPoints|life
```

The shot counter is a bounded local Uint32 firing-observation sequence, not the
request's wire identity. Origin/direction are untrusted finite geometry inputs.
No client-supplied damage, weapon identity or health enters the application call.
The result's life value is `alive`, `defeated` or `dead`. Persistent death requires
zero health; zero health without observed defeat/death is not accepted as a
settled alive result. There is no per-request `damage` field.

The request is correlated by authenticated session, epoch, sender and wire-event
identity, plus the receiving bridge's local generation. One target may have one
engine application pending. The controller preserves consumed request identities
and rejects duplicates, old requests, busy targets and unsupported/malformed
bodies. Ambiguous application, missing observations or timeout keep the target
blocked for that scope, with an explicit unresolved rejection.

HOST checks the exact controlled target's attached/managed/tagged status and
registry binding before and after ray validation. The sender comes from the
existing remote-player snapshot plus the exact tagged local proxy whose reverse
registry mapping matches its SessionEntityId. It is never selected by proximity.
This resolves the player proxy, not an authoritative remote weapon.

The HOST ray requires origin within five metres of that proxy and a nearest hit
on the exact target within 100 metres, using Static, Vehicle, PlayerBlocker and AI
query groups. This is current-state validation, with no lag compensation. The
controlled passive capsule and natural NPC geometry can differ; genuine in-game
ray/occlusion tests remain necessary. The current live blocker is shooter-proxy
self-intersection. An exact-instance `NPCPuppet.DisableCollision()` diagnostic
did not remove that actor from this query. A verified exact-shooter exclusion or
passive player body is required; do not bypass the nearest-hit or identity check.

## Private runner flow

The ordinary package does not install the experiment. `Host.new` remains disabled
unless explicitly passed `enabled=true` by a private runner. Install only a
matched plugin, declarations, scripts, modules and assets after isolated
compilation, with games closed and a verified restore manifest. Preserve saves,
graphics, bindings and the existing public package.

The private test owner should:

1. Start the matched typed HOST/JOINER builds. Disable broad automatic NPC
   adoption so the fixture controls which NPC enters the test catalog.
2. Use F8 to create the disposable tagged NPC on HOST, validating its record and
   retaining the returned exact EntityID. F2 cleans up only that owned actor.
3. Capture shot/readback/event records once per update. Ingest the same drained
   engine batch into the observer; never drain again inside the HOST controller.
   Flush idle observations only when no engine request is pending/unresolved so
   a long no-shot wait cannot fill the bounded parser.
4. Submit only an adjacent real-shot/exact-hit pair still matching the current
   passive projection. Log native queue status and the later ticket-to-wire-event
   association. Do not synthesize a physical hit from a keypress or every shot.
5. On HOST, log admission, mapping, independent ray, labelled application, strict
   causal records, settling readback, composite reply and delivery status.
6. On JOINER, require matching scope, HOST, kind and body. Match own-request
   outcomes to their submitted target. Deduplicate exact event IDs and discard
   superseded results/deferred poses by the latest opaque HOST event per target.
   Keep queued pose and visible pose as separate evidence.
7. The private runner's F9 may recreate the local projection only after releasing the weak trace
   reference and unbinding the former exact ID. Wait for observed disappearance;
   retain terminal death state during same-scope recreation. A reconnect is a
   different test and is not proved by this local recreation. Keep F10 available
   for the existing CET overlay binding.
8. Archive complete logs and failed attempts, close the test-owned processes,
   restore matched runtime/settings bytes and verify current saves were retained.

Do not mix manual raw-health, synthetic-hit or local pose hotkeys into connected
evidence. Do not shoot the HOST target locally while trying to qualify a JOINER
request; concurrent unrelated hits invalidate causal attribution.

## Validation and limits

`gameplay_bridge` covers real socket routing, exact text identities, reserved
HOST result storage, queue pressure, stale scope, transport failure, retained
outcome retries and completion order across requesters. `connected_encounter`
covers body bounds, mapping/authority checks, duplicate/stale requests, target
reservation, observed settling, ambiguity/timeouts, bounded state and strict
engine parsing. Existing passive identity and presentation tests still apply.

Example focused invocation after the matched Release build:

```powershell
ctest --test-dir build/windows -C Release --output-on-failure -R 'gameplay_bridge|connected_encounter|session_bridge_contract|npc_static_identity|encounter_presentation'
```

The private runner has separate mocked checks for exact-shot gating and the
HOST observation/reply loop. Mocks, script compilation, native compilation and
Windows/Debian/sanitizer CI do not establish live gameplay. Record exact source
and installed hashes with each real trial; keep failed attempts visible.

At `97d7c1a`, the Windows Release build and all 24 local CTests passed, including
the player-pose entrypoint regression. Hosted Windows/Debian/sanitizer checks also
passed at `aa289044`, `a8b98c72` and `97d7c1a`; the
[checkpoint](../../../docs/validation/CONNECTED_ENCOUNTER_2026-10-08.md#source-and-automated-validation)
links the exact runs. Installed scripts compiled on both trial-4 game clients.

Remaining qualification includes connected reaction and persistent death in both
games, moving/occluded targets, duplicate/stale/failure cases, accepted-state
restoration after reconnect and a two-PC run. The fixed passive Judy model does
not reproduce arbitrary NPC appearance, hit reaction or ragdoll. Its standing
query capsule does not become corpse physics after a death pose. True JOINER
weapon/attacker application and combat semantics remain separate game-side work.

This diagnostic does not merge saves, synchronize quests/AI broadly, establish
larger live-player capacity or turn the retained v0.0.37 / alpha.5 package into a
shared-combat release.
