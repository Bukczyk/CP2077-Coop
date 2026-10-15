# Dynamic NPC exact identity and retirement

Owner: KyleBuildsAI. UTC checkpoint: 2026-10-15T07:09:57Z.
Branch: `fix/dynamic-npc-lifecycle`.
Base: `e19ffb3286efec750b8729487220becf6569ab7b` (canonical main).
This is an isolated source contribution. PR #12, PR #17 and the published
movement experiment are unchanged. No installation or package version changes.

## Defects and resulting behavior

The dynamic NPC adapter compared EntityID wrapper text. A fresh wrapper for the
same opaque hash failed to bind, while adjacent IDs above 2^53 must stay distinct.
It also discarded ownership immediately after DeleteEntity returned true,
allowing a replacement while the old actor was still visible. Existing tests used
stable string IDs and synchronous removal, so they did not expose either defect.
The new regression suite fails on the original adapter at the fresh-wrapper bind.

The adapter now uses opaque EntityID hashes without converting them to Lua
numbers. Only its exact created IDs can bind, move or retire. Transform inputs
reject nonfinite values; initial orientation uses the supplied yaw. Native
mapping disappearance permits unbinding, while an unknown or foreign mapping
cannot authorize another entity's unbind or deletion.

Dynamic cleanup must also avoid the already documented early-cancellation race.
The lifetime invariants come from KyleBuildsAI's
[`player_lifetime.lua` at PR #5 head b1f054e](https://github.com/Bukczyk/CP2077-Coop/blob/b1f054ed67c0bb03f1b8e290c2b5fd62a621307c/runtime/session/cet/CP2077Coop/player_lifetime.lua)
and its [recorded engine evidence](https://github.com/Bukczyk/CP2077-Coop/blob/b1f054ed67c0bb03f1b8e290c2b5fd62a621307c/docs/validation/PLAYER_LIFETIME_FIX_2026-10-08.md).
They are adapted to NPC ownership here; the player implementation and PR #5 are
not imported or modified.

Codeware 1.18.0's
[pinned DynamicEntitySystem source](https://github.com/psiberx/cp2077-codeware/blob/b1b2770cdf6ad2631666fb6ef4ccda99d864298e/src/App/World/DynamicEntitySystem.cpp)
allows a pending creation callback to complete after an early delete loses
management. Empty manager/global observations before attachment therefore do
not prove cancellation. The old game reproduction is prior evidence, not a new
live test of this NPC change.

## Cleanup contract

- `npc_runtime:pump(now, paused)` supplies one caller-owned game-update timestamp.
  `init.lua` pumps it during ordinary updates, unloaded saves and latched errors.
  A missing/throwing pause query is unknown, not unpaused.
- Removal requires confirmed native unbinding. The same exact actor must be
  globally attached, managed, spawned and not spawning in two distinct unpaused
  update timestamps before DeleteEntity is called.
- Repeated reset/remove calls in the same frame cannot qualify attachment twice.
  Pause or invalid time/observations resets stability and absence qualification.
- Accepted deletion is submitted once. Failed submissions have at most three
  attempts, separated by 0.5 seconds of observed unpaused time.
- Completion needs global lookup and population lookup to be absent, the
  retained exact actor handle to be detached, and managed/spawning/spawned flags
  to be explicitly false for 0.25 seconds of observed unpaused time. Unknown
  Boolean results fail closed rather than becoming false through Lua truthiness.
- Returning catalog entries cannot cancel retirement or create an overlapping
  replacement. The existing NPC runtime keeps its original ID until completion.

## Exact owned files

- `runtime/session/cet/CP2077Coop/npc_population.lua`
- `runtime/session/cet/CP2077Coop/npc_runtime.lua`
- `runtime/session/cet/CP2077Coop/init.lua` (NPC clock/pause pumping only)
- `tests/npc_dynamic_identity_tests.lua`
- `tests/npc_population_tests.lua`
- `tests/session_lifecycle_tests.lua`
- `tests/CMakeLists.txt`
- `docs/validation/DYNAMIC_NPC_LIFECYCLE_2026-10-15.md`

Bukczyk retains protocol, networking, authoritative state and shared bridge
ownership. None of those files or contracts changes. NPC replication remains
disabled by default; player behavior and installed game files are unchanged.

## Verification

- Fresh Windows x64 Release build: plugin, session server and portable core pass
  with Visual Studio 2022 / MSVC 19.41.33923.0. Cached SDK and Lua source inputs
  are the same verified dependencies used for the preserved movement package.
- All 26 CTests pass, including the new `npc_dynamic_identity` test.
- The focused dynamic suite passes 228 checks under Lua 5.4 and LuaJIT 2.1.
- Existing dynamic population, static identity and actual CET entrypoint lifecycle
  suites also pass under LuaJIT 2.1. The entrypoint test verifies explicit pause,
  unknown pause and continued NPC pumping after unload or a latched failure.
- Independent review found a nil-truncated Boolean-validation loop during
  implementation. Explicit field checks fix it. Regression cases cover each nil
  state after deletion and nil/malformed states before attachment qualification.
  The independent four-case reproducer now rejects every unknown observation.
- `git diff --check` passes. Build/test logs are in ignored `build/dynamic-npc/`:
  `build.log`, `ctest.log` and `luajit.log`.

The fixture explicitly models accepted early deletion dropping a management token
followed by a late actor. Production adapter tests verify that pending actors
never enter that deletion path, and external early cancellation cannot cause the
adapter to forget or replace the ID. Other cases cover paused/same-frame updates,
global-only and retained-handle-only presence, cleanup retry limits, exact scope
reset, bubble reentry and foreign entity protection.

### Pause observation failure follow-up

2026-10-15T07:25:39Z: review found that the pause handler getter itself could throw
before the protected `IsGamePaused()` call. That skipped the NPC clock pump,
leaving old attachment/absence observations valid across an unknown interval.
The entire lookup is now protected. A throwing handler getter supplies unknown
pause before preserving the existing ordinary-update bridge failure. Latched
failure ticks continue delivering unknown while the getter is unavailable.
Any earlier update exception also invalidates NPC observations after cleanup,
using the same timestamp without advancing the clock a second time.

The actual entrypoint regression seeds a real dynamic-adapter retirement and
checks handler failure both before deletion and during the absence quiet period,
plus an earlier `GetPlayer()` exception. Recovery needs fresh attachment samples
or a fresh 0.25-second unpaused absence interval. It also checks exact clock deltas
and that a handler error does not continue normal session work. Each of the three
cases fails against pre-follow-up commit `88a144d` and passes with this change.
Four focused suites pass under both built Lua 5.4 and LuaJIT 2.1; logs are
`build/dynamic-npc/pause-ctest.log` and `pause-luajit.log`. This follow-up changes
only CET source, the lifecycle fixture and this note, so no native rebuild or new
live-game test was performed.

## Remaining gates and limitations

A never-attached token, lost ownership or an exhausted deletion retry stays
retained indefinitely when safe cancellation/removal cannot be established.
This can block further NPC creation during reset. It must not be bypassed by
dropping the ID, deleting by proximity, or claiming a timeout proves removal.
An engine-supported cancellation receipt or later verified recovery is still
needed to resolve those cases automatically.

Do not hot-reload scripts while retirement is pending. This change does not
persist in-memory ownership across reload or recover historical unmanaged
orphans. No new live NPC or two-PC test has run. Future live checks must cover
pending-create cancellation, disconnect/reconnect, pause/resume, delayed despawn
and exact old-ID disappearance before replacement.

Dynamic NPCs still have autonomous AI, and the teleport call still reports API
acceptance rather than measured placement. This patch does not enable that path
as safe shared-world gameplay, fix appearance parity, connect authoritative
life-state baselines, or qualify smooth NPC movement. No REDscript/native source
changed, so no new isolated script compilation was required.
