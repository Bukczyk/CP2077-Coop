# Completed static NPC retirement with retained native references

KyleBuildsAI / Codex, 2026-10-20 UTC.

## Change and ownership

This game-side fix is based on PR29 at
`84bdad644253fddc6e4318b4beea59ba9fe48b58`. It is separate from the player action
experiment in PR30. Only `npc_static_population.lua`, its exact identity tests
and this evidence note are changed. No networking, server, protocol, AI, hit or
vehicle behavior is changed.

A completed StaticEntitySystem actor can be removed from its creator maps while
an exact detached native reference remains resolvable. Waiting for the global
reference to become nil can hold the adapter's owner forever and prevent the
next generation from recreating its projection. CET weak wrappers can also be
non-nil after their native reference expires.

The adapter releases ownership only after an observed completed creation,
native unbind, a ready original creator with all three lifecycle flags false,
and no attached creator/global/retained exact handle. A valid detached handle
must match the original opaque EntityID. Positive `IsDefined(...) == false`
establishes expiry without dereferencing a dead wrapper. Non-boolean, thrown or
foreign-handle observations remain unknown and block reuse. The creator is never
replaced by a newly returned system. Pending creation tokens are never cancelled.

Codeware 1.18.0's disposal queue removes creator ownership after its entity status
becomes Uninitialized. The adapter still requires those observations, rather
than interpreting a queued `DespawnEntity` return as removal.

## Regression and Windows validation

- The new independent `npc_runtime` regression fails against the original
  adapter at the new-generation recreation assertion. It passes with the fix.
- Creator removal plus exact detached global/retained references admits a
  distinct replacement and does not repeat disposal.
- Attached and foreign handles continue to block release.
- Unknown/failed weak-lifetime reads retain ownership; positive expiry releases
  it without invoking methods on an expired wrapper.
- Existing late callback, pending spawn, unbind, generation, malformed lifecycle
  and real init.lua reconnect regressions pass.
- Windows Release build, plugin enabled, pinned RED4ext SDK: PASS.
- Full Windows CTest: 58/58 PASS, 11.82 seconds.

The verified local generator was Visual Studio 17 2022 Preview, x64. An initial
attempt with the historical AGENTS.md VS18 generator was unsupported by the
installed CMake; no toolchain or vendor modification was used to bypass that.

## Live validation, single HOST

The first bounded attempt stopped
before spawning: the current player-only bench did not contain the static NPC
template. A read-only resource check returned false. The existing authored idle
archive was rebuilt with the pinned WolvenKit 9.0.1 CLI; exact two-resource
inventory and unpacked hashes pass. It was added to both stopped game copies,
with no resource collision, control changes or core adapter replacement.

This prerequisite is kept private. It contains the authored entity and idle
graph only; vanilla mesh/rig/animation resources remain references. The test
fixture uses copies of the actual old/fixed adapters, at most three creations,
no network binds and no ambient actor deletion. All engine work is onUpdate.

After the prerequisite was added, JOINER crashed during startup before HELLO;
its report records a null-read access violation with no causal stack. HOST
remained running. No conclusion about the cause follows from that report.

A separate 60-second HOST-only recording then captured the bounded comparison
at 2026-10-20T19:14:22Z through 19:14:40Z. The 97-row lifecycle trace records:

| Adapter | Exact local EntityID | Creator removed; retained/global detached | Owner released |
| --- | --- | --- | --- |
| Original | 10849665 | Yes | No, still blocked at the six-second limit |
| Fixed, first cycle | 10849670 | Yes | Yes |
| Fixed, replacement cycle | 10849671 | Yes | Yes |

Each creation was observed managed, spawned, not spawning and attached before
disposal. Every final creator flag was false and both exact retained/global
handles were detached. The replacement reused the same fixture logical label,
not the previous local EntityID. No network identity was registered or unbound
by this isolated fixture.

The video contains 2,521 original frames, no capture errors; the controlled
23-second window has 997 callback rows and maximum gap 43.2 ms. Nine original
frames were extracted/reviewed. The original idle asset's body is partly below
the walkway. The console obscures part of the first body, and the second fixed
body is not clearly visible in its selected frames. This is observed engine
lifecycle/ownership proof, not qualified model presentation or shared-world
replication. Longer visible dwell and a recovered paired-game run remain next.

Raw video/logs and the derived private prerequisite stay local. The existing
validated player runtime and stable v0.0.37 package are preserved. No in-game
damage, AI, matching cars, physical movement or WAN success is claimed here.

## Extended HOST and JOINER checks

The next normal matched restart succeeded in both games without another code,
asset, save or configuration change to address the startup crash. That does not
identify or resolve its cause. The core cleanup patch was installed while both
games and the local server were stopped; all 13 protected config hashes match.

The isolated fixture holds each actor for ten seconds. A diagnostic-only +1 m
vertical offset clears the walkway for inspection; it is not a production
placement fix. Both instances stay in their existing connected local session.
Their three-body comparisons run independently, not as replicated shared NPCs.

| Game | Original blocked local ID | Fixed first local ID | Fixed replacement local ID | Trace rows |
| --- | --- | --- | --- | --- |
| HOST | 10850923 | 10850934 | 10850937 | 183 |
| JOINER | 10850417 | 10850426 | 10850570 | 184 |

The old cleanup remains blocked at the six-second observation limit in both.
Both fixed cycles release ownership after original creator removal and exact
global/retained detachment. Same-label replacement has a distinct ID. All logged
holding samples remain creator-managed/spawned/attached; 146 HOST and 148 JOINER
samples verify the exact native entEntity class and template hash
`4410265881089470268ULL`. No NPCPuppet, AI or invented network binding is used.

Two paired 90-second recordings passed warmup, frame cadence, completion and
unchanged-tool checks. JOINER's comparison is in the first pair; HOST's comparison
is in the second. Original frame counts H/J are 2,017/2,039 and 1,954/1,935.
Eight original frames per tested view were reviewed. Both fixed replacements
are visible in their selected holding frames and absent after disposal. The
initial baseline is partly obscured by the console; its lifetime is confirmed
by engine readback. This qualifies the scoped local lifecycle/recreation fix,
not full NPC appearance, ground placement or shared-world replication.

At code commit `2f9ce9c8da0a6e0368a9ddcaba70259f554a2308`, all hosted Windows,
Debian and sanitizer jobs pass, run 39482523123. The current complete PRIVATE
recovery payload has 86 files, explicit player fd3d100 / NPC 2f9ce9c / native
9f27bd4 provenance and verified reproducible ZIP hash. Only the two NPC Lua
copies and two authored idle archives differ from the preceding 84-file player
checkpoint. No derived asset, raw video, key or save is published.
