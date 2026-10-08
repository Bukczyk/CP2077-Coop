# Accepted NPC state during local projection recreation

KyleBuildsAI owns this game-side experiment. It retains accepted CPEX1 health and
life state while a local render-only NPC disappears, then applies that state to
the exact replacement. Bukczyk retains protocol, session, accepted-state delivery
and reconnect recovery ownership. This adds no network messages or wire fields.

`joiner.lua` is opt-in and is not installed by the ordinary runtime package.
Its input is the existing authenticated native outcome envelope decoded by
`bridge.lua`; CPEX1 remains a diagnostic body, not a production combat agreement.

## Integration

Construct `Joiner.new` with:

- `context()`: current decoded session/epoch/generation, self, HOST and active flag.
- `resolve(target)`: exact current local EntityID hash as an opaque string, or nil.
  Return nil during retirement and asynchronous replacement. Do not match by position.
- `requestTarget(requestEvent)`: submitted target for this JOINER's own requests.
- `apply(frame)`: queue pose setters on that exact owned projection on the game
  thread; return true only for queue acceptance. Never apply gameplay damage here.
- Bounded target/event capacities and verified reaction/death clip durations.

Pass native outcomes to `accept(event, now)` and call `step(now)` on game updates.
`accept` retains state but does not mutate an engine entity. `step` resolves the
current exact local binding, waits while absent, and retries failed pose queues.
`inspect(target)` returns a copy of retained health, maximum health, life state,
HOST event, local identity, pending status and the last queued frame.

The controller validates HOST, scope, kind, accepted disposition/body and own
request target. Event IDs stay opaque decimal strings, including above 2^53.
Duplicate, conflicting and stale events cannot replay or overwrite accepted
death. Storage exhaustion is explicit; terminal entries are not silently evicted.

An accepted result can animate its currently existing body. A replacement, or
a body created after the result arrived, receives final idle/dead state without
replaying an old hit/death animation. Supplied health is presentation metadata:
the passive `entEntity` has no authoritative NPC stat pool to damage.

Only alive/dead restoration is supported. Defeated returns `unsupported_life`;
it must not be silently converted into an alive reaction or an authoritative death.
An alive result cannot resurrect terminal death within one scope.

Session, epoch, generation, local player or HOST changes clear retained state.
A fresh scope requires a newly supplied accepted result. This is not delivery of
an authoritative reconnect baseline; that remains a separate backend contract.

## Verification

`connected_presentation` covers accepted-state retention, exact replacement,
absence and callback failures, duplicate/stale/conflicting events, scope changes,
bounded storage and unsupported state. Existing projection lifecycle tests cover
asynchronous removal and exact identity ownership. Queue acceptance is distinct
from a visible pose.

The live gate uses the matched private runner with fresh backups and unused F7
recreation input. F9 is forbidden because it invokes native QuickLoad. It must
record a real connected HOST outcome, unchanged scope/session entity, old-ID
disappearance, a new exact local ID and the replacement's visible terminal pose.
Alive recreation must retain accepted health without replaying an old reaction.

The original animation graph defaults to idle during asynchronous spawn. A first
queued dead frame alone does not prove that no idle frame was ever visible.
Detached-spawn/attachment or a default-terminal template requires separate engine
evidence before making that stronger claim. No full reconnect, two-PC, weapon
parity, defeated-pose or general shared-world qualification follows from unit tests.
