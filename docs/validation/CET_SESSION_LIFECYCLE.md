# CET startup and repeated reconnects

Owner: KyleBuildsAI. Handoff UTC: 2026-10-06T05:40:49.502510+00:00.
PR: https://github.com/Bukczyk/CP2077-Coop/pull/4
Branch: `fix/cet-session-lifecycle`.
Base: `7e3826d1c313595a4784f1b232e10cec222b6ca3`.
Tested code: `89d619ee8f06c8f9c6695dbfa574c7a840cdfa00`.
Status: fixes tested and proposed for Bukczyk review; not merged or released.

## What changed

- Register the NPC observer during CET `onInit`. Before this fix, a fresh game
  launch failed while loading the mod because `Observe` was not available yet.
- Compare `player:GetEntityID().hash` as an exact Uint64 string. The previous
  wrapper string changed between reads, repeatedly stopping and recreating the
  session even though the same player was still loaded. Real replacement,
  unload and the reconnect hotkey still reset the session.
- Default `config.lua`'s `experimentalNpcReplication` to `false`. Repairing
  startup makes the unfinished NPC path reachable, so HOST adoption and JOINER
  projection updates require explicit development opt-in. Player replication
  stays enabled. This does not implement passive NPC AI or fix NPC identity.

## Files and responsibility

KyleBuildsAI owns this change and its follow-up corrections:

- `runtime/session/cet/CP2077Coop/init.lua`
- `runtime/session/cet/CP2077Coop/config.lua`
- `tests/session_lifecycle_tests.lua`
- `tests/CMakeLists.txt`
- `runtime/session/README.md`
- `docs/validation/CET_SESSION_LIFECYCLE.md`

Existing `CP2077Session_*` interfaces are unchanged. No protocol, server,
C++ native, REDscript, NPC projection adapter or movement code was modified.
Bukczyk retains network ownership and upstream merge review.

## Automated evidence

| Check | Result |
| --- | --- |
| Fresh Windows MSVC Release plugin/server/core build | PASS |
| CTest, including new executable CET lifecycle test | PASS, 12/12 |
| Same lifecycle test under LuaJIT 2.1 with real uint64_t cdata | PASS |
| Reintroduce original module-level Observe | Test rejects with original nil-Observe error |
| Reintroduce player wrapper comparison | Test rejects repeated session activation |
| Convert hash through Lua number | Test rejects missed identity replacement above 2^53 |
| Hosted Windows, Debian and Linux ASan/UBSan | PASS at tested code, run 37419183473 |

The lifecycle test executes the real entrypoint with engine APIs absent before
`onInit`, fresh wrappers, adjacent opaque 64-bit IDs, real-ID replacement,
pregame/unload, explicit reconnect, shutdown and NPC opt-in/default-off paths.
NPC adapter tests remain mocked; they do not establish passive game behavior.

CI: https://github.com/Bukczyk/CP2077-Coop/actions/runs/37419183473

## Local two-game test

Fresh HOST and JOINER processes, Cyberpunk 2077 2.31, on one Windows PC with a
loopback session server. Both used 1280x720 windowed low graphics, 60 FPS cap and
ray tracing off. Runtime prerequisites: RED4ext 1.30.0 and Codeware 1.18.0, with
installed CET/redscript. The previously matched native plugin/server and compiled
REDscript were reused because this PR changes none of their source. The fresh
build above is separate build evidence, not a claim that new binaries were used.

Both clients ran the exact reviewed Lua files. A separate private diagnostic mod
sampled native frame getters and actual engine IDs every two seconds; it did not
advance the native frame or change product Lua. A temporary F8 binding invoked
the existing JOINER reconnect hotkey.

Recorded stable intervals on 2026-10-06 UTC:

| Role | Interval | Result |
| --- | --- | --- |
| HOST | 05:33:59-05:38:51, 292 s | Session 1 / Player 1, no spontaneous restart |
| JOINER before reconnect | 05:35:01-05:37:25, 144 s | Session 1 / Player 2 |
| JOINER after reconnect | 05:37:27-05:38:52, 85 s | Session 1 / Player 3, host membership unchanged |

The trace recorded 146 different HOST wrapper strings with the same `1ULL`
engine hash. This reproduces the original instability while verifying the fixed
identity comparison. Both clients remained Active and exchanged player samples.
No NPC catalog entities were replicated with the switch off. After JOINER exit,
HOST stayed Active in Session 1 with no remote player or remaining player proxy.

The server log contained one CREATE_SESSION, one initial JOIN_SESSION, and one
JOIN_SESSION caused by the explicit reconnect. These are run-specific IDs.
No network speed, internet latency, shared NPC authority or movement quality
claims follow from this lifecycle test.

Deployed file SHA256 values (Windows checkout bytes):

- `init.lua`: `022ed855044154e46f8743a541732526a7c618302f6ae5df777302db6beb167d`
- `config.lua`: `69cba261f6d634340985c0ed133eb854670eb5c89938206fd029b2fa4ea53dc8`

Private local evidence is under
`D:/Downloads/syncfix/bench-artifacts/20261006-cet-lifecycle`.
It includes backups and private access keys; do not upload that directory.

## Remaining work and release status

The previously observed player-proxy movement error is still a separate task.
The initial JOINER baseline placement is also not qualified by staying connected.
NPC adapter wrapper comparisons, passive AI, vehicles, combat, appearance,
minimap integration, full save/load world reset and two-PC/larger-group gameplay
are not fixed or qualified here. Enabling the NPC experiment is not permission to
claim shared-world gameplay.

This is a focused source correction submitted for review, not a new public game
package. The tested v0.0.37 / alpha.5 package remains the public rollback/reference.
No saves were restored from backup. Temporary graphics, key bindings and the
private diagnostic mod are removed/restored after the test, with cleanup verified
in the local handoff. Review and merge this PR before starting separate movement
or NPC integration work.
