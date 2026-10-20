# Verify local player ground contact without inferring it from height

The lower renderer still infers jumping from vertical motion. A headless 50%
uphill ramp can trigger its airborne state. This experiment verifies a genuine
source-side contact getter before proposing how to deliver it. It does not yet
change remote terrain rendering or any protocol field.

## Verified engine access

The installed SDK names the native interface
`gamestateMachineGameScriptInterface`, alias `StateGameScriptInterface`.
The alias returned nil in Codeware class lookup; the canonical name resolves.
Read-only live metadata exposes 149 methods and confirms `IsOnGround()` is a
native zero-parameter Bool getter. This is separate from the locomotion enum.
The SDK's Muppet physical-state field alone did not establish a player getter.

`LocomotionEventsTransition.OnUpdate` has Float/context/interface parameters.
The optional `experiments/player-locomotion/ground_probe.lua` registers observers
in CET onInit, with metadata guards. It reads the getter only inside a live
callback whose exact execution-owner ID matches the current attached local
player. Session, epoch, generation and identities are rechecked. No interface or
player handle escapes the callback. Missing/foreign/invalid data is unavailable,
never a fabricated false result.

The logger stops at 300 update-clock seconds, 36,000 callbacks, 1,800 rows or
1 MiB, whichever comes first. Persistent file size also limits future loads.
It cannot silently rearm. It records only primitive local diagnostics, applies
no movement/physics/AI or networking state, and never changes callback results.
It is a private opt-in probe, not part of ordinary runtime installation.

## Recorded actual input

Both optional probes were installed only after both games and local server
exited normally. All 13 protected configuration hashes remain exact. The
installed source bytes match the committed recipe; no native/asset changes.
Probe SHA256: `4be5c39a8efe0879228b60292d71a4eb8661d676b4d5cb56e2c6f868080e679f`.

The `ground-contact01/actual-paired-jump01` capture records both real games for
60 seconds with encoder warmup, complete recording/cadence and unchanged tools.
HOST Space input began at 2026-10-20T18:32:12.955Z and C crouch at18:32:38.686Z.
These are input-call times, not native action or network timestamps.

There are 282 selected HOST contact observations: 278 true and four false.
All four false samples report native Jump5 and increasing/decreasing root
height. In the probe's local clock, contact changes true to false at204.609535
and back to true at205.314091. Sampled root height spans0.985260 m. The 56
Crouch1 observations retain true contact. JOINER's separate 280 source samples
remain grounded/Default0. All emitted rows in this run come from the verified
base locomotion callback. This does not establish every advanced state hook.

The recordings contain 1,458/1,457 original frames; maximum tested shared
capture gaps are72.3/73.9 ms. Eleven original frames per view were reviewed.
HOST camera rise/fall and crouch are visible. The actual HOST proxy is outside
JOINER's view, so this is source-contact proof, not a new remote jump/pose test.
Stand input at18:32:57.753Z happened after the video ended; later live/log state
confirms standing/contact, but the recording does not qualify that input.
An earlier 60-second recording captured only standing and is retained separately.

The focused mock checks exact identity, false versus unavailable, changing
scope, foreign owner, pulse cadence and time/callback/row/persistent-byte bounds.
Full Windows Release experimental **78/78** and default-v5 control **76/76**
pass, with both games/server stopped for those full runs.
Neither full terrain traversal nor shared ground-state delivery is proven.
Raw videos, original PTS, metadata proof, input journal and selected rows stay
private under `20261020-crouch-mask`. Controls, configuration and saves remain.

## Shared interface still needed

Proposed behavior for review: deliver the latest valid ground/locomotion state
with its source snapshot association and explicit unavailable/freshness meaning,
scoped to the exact player/entity/session epoch. Late join and reconnect need a
fresh baseline. An ungrounded sample and a missing sample must remain different.
This belongs with the accepted shared presentation/movement contract, not an
extra channel or a hidden movement-value encoding. PR18 remains draft at
`323c1d673be877c5df876b83c0aa614133620cf4`, checked2026-10-20.

KyleBuildsAI owns engine capture/probe, diagnostics and tests. Bukczyk owns typed
delivery/session semantics; this is a proposed requirement, not a unilateral
protocol update or a claim that its implementation is agreed. The existing
height-inference renderer remains until a matched, reviewed replacement passes
slopes, stairs, standing/running jumps, falls, stale data and reconnect tests.

## Primary sources

[CET's maintained observer reference](https://wiki.redmodding.org/scripting-cyberpunk/cyber-engine-tweaks/cet-functions/observers/observe)
documents onInit registration and receiver/parameter order. The actual method
signature and readings above were verified in this installed game independently.
[OPEN//77 utilities](https://open2077.net/docs/player-utilities) document their
own grounded query; that platform API is not installed or callable here. No
third-party implementation was copied. Stable v0.0.37/latest remains unchanged.
