# Player movement pause fix

Owner: KyleBuildsAI. Branch: `feat/player-movement-presentation`, draft PR #5.
Starting commit: `efff4eaba14fa758c1a0af5e2fb65752609d30f3`.
Recorded 2026-10-09 UTC (October 8 Pacific).

## Confirmed bug and fix

CET update callbacks continue while the Escape menu pauses world AI. The player
pose controller previously spent its three one-second readback attempts during
that pause and permanently latched `readback_timeout`. This is reproducible in
the real game with an isolated player-proxy fixture. It is not yet proof that
the earlier WAN failure had this same cause.

`player_pose.lua` now accepts an observed pause flag. It retains the exact owned
command without submitting, cancelling or consuming initialization/readback
timeouts during pause. Resume shifts those timers by the paused duration and
continues toward the newest target. Genuine prior faults stay latched. Retry
counts, active-time deadlines and placement tolerances are unchanged.

The CET entrypoint reads `SystemRequestsHandler.IsGamePaused()`, passes it to
the controller and defers initial JOINER alignment/player spawning while paused.
Native session snapshots and bindings continue. The opt-in motor skips paused
updates. No protocol v5, networking, native, REDscript, NPC or combat changes.

## Real-game evidence

One Test B game, session closed, independent nonpersistent Judy fixture. No HOST
or other PC participated. Native/REDscript remained the installed first-contact
build; the separate diagnostic used the corrected source controller.

- Before fix, actor `10742380ULL`: pause observed at elapsed 10.229 s. Three
  readback failures latched at 18.646 s, with AI command state 1 and actual
  position unchanged. The trial stopped while still paused and retired its ID.
- After fix, actor `10742554ULL`: 285 samples, 121 paused samples spanning
  14.045-27.262 s, zero fault samples. Resume submitted the latest target,
  moving from x=-803.464355 to x=-798.464355. The command reached state 5 with
  zero position error and approximately 0.000008 degrees heading error.
- 32 samples after resume reported observed placement. The fixture finished
  without failure and exact actor retirement was confirmed after 40.74 ms.

Fixture target progression uses CET elapsed time even while paused. These are
pause-recovery checks, not walking-animation, latency or WAN synchronization
qualification. Private raw logs, metrics and hashes are under
`bench-artifacts/20261008-pause-freeze`.

## Automated validation and boundaries

Windows Release build and all 27 local CTests passed. Focused pose tests pass
68 checks, including long/repeated pauses, remaining deadlines/cooldowns, actor
replacement/reset, initialization grace and genuine fault retention. The fixture
suite passes 41 checks. The actual entrypoint test verifies snapshots remain
active and JOINER alignment/spawn are deferred until resume. Independent review
found no blocker. Hosted CI is tracked on PR #5.

This remains an unreleased development candidate. Keep public/local
v0.0.37 alpha.5 packages preserved until the matched replacement passes its gates.
No saves, keys, graphics or session configuration were reset. See the vault for
the exact installed file hashes and whether the game remains open.

## Separate cleanup investigation

The older visible Judy was identified as `10736280ULL`, attached at the first
manual fixture's position but unmanaged by both dynamic/static systems. The
later manual fixture `10736281ULL` is confirmed detached with no engine lookup.
The first fixture did not record CreateEntity's return value, so provenance of
the older body is still inferred. No arbitrary actor was removed.

Installed Codeware is 1.18.0. Its [pinned source](https://github.com/psiberx/cp2077-codeware/blob/b1b2770cdf6ad2631666fb6ef4ccda99d864298e/src/App/World/DynamicEntitySystem.cpp)
removes tracked state before despawning (lines 174-192); an outstanding spawn
callback can still register the entity (237-254), and despawn does nothing when
the stub is not yet available (294-310). Empty tags/IsManaged=false therefore do
not prove a pending spawn cannot appear later. The earlier private source copy
was a different Codeware revision and must not be cited as installed-version proof.

Next game-side task: one isolated exact-ID early-cancellation experiment, then
retain pending actor ownership and defer deletion until spawn settles if the
race is confirmed. Keep that lifecycle work separate from this pause fix.
Next connected gate: two-PC movement through pause/resume and reconnect, using
the enriched diagnostics to distinguish any remaining WAN failure.
