# Player actor lifetime and early cancellation

Owner: KyleBuildsAI. Branch: `feat/player-movement-presentation`, draft PR #5.
Starting commit: `4a017ec587727c6512f7059839b8cd1529c9791a`.
Recorded October 8 Pacific / October 9 UTC. Source is the commit containing this
record, based on the starting commit above. This is an unreleased draft-PR
change. Hosted CI for this revision is recorded in the PR, separately from the
local results below.

## Confirmed engine race

Deleting a dynamic actor immediately after CreateEntity can remove its tracked
ownership before the asynchronous spawn callback finishes. The actor can then
appear in the world without its original tags or managed state. Therefore,
DeleteEntity returning true, empty tags, and IsManaged=false are not sufficient
proof of removal. IsSpawning=false is also insufficient before attachment.

Installed Codeware 1.18.0's [pinned DynamicEntitySystem source](https://github.com/psiberx/cp2077-codeware/blob/b1b2770cdf6ad2631666fb6ef4ccda99d864298e/src/App/World/DynamicEntitySystem.cpp)
removes tracked state before despawning (lines 174-192). A pending callback can
still register the entity (237-254), while despawn cannot remove a stub that is
not yet available (294-310). This is the installed-version source identified in
[the pause-fix investigation](PLAYER_PAUSE_FIX_2026-10-08.md), not the earlier
private source copy from a different Codeware revision.

## Real-game reproduction before the fix

One Test B game, session closed, opt-in nonpersistent Judy fixture. No HOST or
other PC participated. The fixture retained the exact CreateEntity return value.
Raw evidence: private `bench-artifacts/20261008-player-lifecycle/immediate-cancel.log`.

- At 2026-10-09 03:37:20 UTC, CreateEntity returned `10745218ULL`. It was managed,
  not spawned, and reported IsSpawning=false.
- Immediate DeleteEntity returned true. At elapsed 0.019716 s, no attachment,
  tags or managed state remained.
- At elapsed **0.133403 s**, that same exact actor was attached and spawned,
  while managed=false and tagged=0. It remained attached through the full
  5.013738-second watch.
- At 03:37:39 UTC, explicit recovery called PreventionSpawnSystem.RequestDespawn
  for this fixture's exact ID. The 03:37:56 UTC inspection still found it
  attached/spawned and unmanaged; reset correctly returned false. This recovery
  did not remove the actor in the observed window.

This confirms the early-cancellation failure independently of the older visible
Judy `10736280ULL`. The older body's origin remains inferred because its initial
manual spawn did not record the returned ID. No nearby actor was selected for
deletion by appearance or position.

## Game-side change

The proposed fix keeps the exact actor ID from creation through confirmed
removal. The local REDscript SpawnProxy helper now returns CreateEntity's EntityID
to CET, including an empty ID on rejection. This is an engine-side call change;
protocol v5 and native session/server contracts are unchanged.

`player_lifetime.lua` retains canceled pending actors instead of deleting them
early. It waits for two distinct observations of the same attached, managed,
spawned actor with no spawn in progress. It then releases the owned binding and
pose/motor before submitting exact-ID deletion. Release/deletion failures have
bounded retries and retain ownership; accepted deletion is not repeated.

Completion requires both world and dynamic-system actor lookups to be absent,
all managed/spawning/spawned evidence to clear, and a 0.25-second unpaused quiet
interval. Pause does not authorize deletion or satisfy the absence interval.
Exact opaque IDs are preserved without converting them to Lua numbers.

The CET entrypoint retains retiring actors across disconnect, generation/entity
replacement, unload and bridge failure. It pumps retirement while inactive or
failed. New dynamic spawns, and switching to the passive representation, wait
while unresolved dynamic ownership remains. Managed tags support startup
recovery, but cannot reconstruct an already untracked in-flight deletion.
Do not hot-reload while a retirement is pending. Already unmanaged historical
orphans are not automatically adopted or deleted by this change.

Native deactivation or another representation's reset can fail without losing
dynamic IDs. These errors keep the bridge failed until a successful explicit
reconnect. Missing active actors are diagnosed and retained without spawning a
duplicate. Shutdown attempts only exact owned command cancellation, without
deleting pending actors. It does not claim asynchronous removal has completed.

The fixture's settled mode immediately requests retirement through the actual
production lifetime module. It remains idle until explicitly started, observes
pause, and watches for five unpaused seconds even if removal finishes sooner.
Its immediate mode remains an explicit known-bug reproduction. Reset requires
confirmed exact absence, plus controller completion in settled mode.

## File ownership and scope

KyleBuildsAI owns this bounded work:

- `runtime/session/cet/CP2077Coop/player_lifetime.lua` and player ownership in
  `init.lua`, with the owned pose-release support needed for retirement.
- `runtime/session/redscript/CP2077Coop/remote.reds`: SpawnProxy return value.
- Relevant player lifetime/pose/lifecycle/passive regression tests and their
  CMake registration.
- `experiments/player-cleanup-fixture/` and this validation record.

Bukczyk retains protocol, server, session ownership and routing. No new backend
requirement has been established. This change adds no combat, vehicle, world-NPC
replication or player appearance feature.

## Automated validation

The final source and regression tests passed the Windows Release build and
**28/28 local CTests**, with zero failures in 6.89 seconds. Coverage includes
pending cancellation, independent exact lookups after tags clear, late attachment,
pause, bounded failures, binding theft, cleanup exceptions, missing active actors
and shutdown command identity. The lifetime suite performs 2,843 assertions,
including repeated exact-ID guards; the pose suite performs 112 checks.
A separate private fixture smoke test passed 14 checks using the real lifetime
module with mocked engine observations.

REDscript sandbox compilation for Test B and Baseline completed at approximately
03:47 UTC. No REDscript changed after those successful checks. These are script
compilation and offline tests, not proof of the fixed behavior in Cyberpunk.

Private evidence includes `ctest-final.log`, `windows-release-build-final.log`,
`redscript-test-b.log`, `redscript-baseline.log`, the fixture smoke harness and
installed-file hashes under `bench-artifacts/20261008-player-lifecycle`.
Private connection profiles and keys must not be published with this record.

## Remaining acceptance gates

| Gate | Status |
| --- | --- |
| Exact-ID early-deletion race reproduced in Cyberpunk | Confirmed above |
| Fixed settled cancellation in Cyberpunk | Pending: add actor ID, deletion/completion times, full-watch evidence and reset result |
| Local two-window movement, pause/resume and reconnect | Not completed: automated menu input was unreliable; KyleBuildsAI was away and explicitly requested skipping the manual test |
| Two-PC WAN movement and reconnect with Bukczyk | Blocked on Bukczyk availability and an active HOST; no current session confirmed |
| Windows/Debian/sanitizer hosted CI | Check this revision's PR checks; prior commit's green CI is not evidence for these edits |

Local two-window testing is useful KyleBuildsAI-side integration evidence, but
does not replace two-PC WAN observations. Preserve current controls, graphics,
saves and the private WAN profile during any bounded local test. The existing
v0.0.37 alpha.5 package remains the preserved public/local package; this document
does not declare a new playable version.
