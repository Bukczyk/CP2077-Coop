# Capture-only map basis probe

2026-10-15 UTC. Source/test experiment on PR15, following the facing calibration fixture at `a4766d6`. No installed files, running game, package, protocol, backend or production arrow changes. The branch also contains the separately owned failed-mode UI guard; this experiment does not change that code.

## What this adds

`experiments/player-presentation/map_basis_capture.reds` owns four diagnostic position mappins: origin, world +X, world +Y and the diagonal, at one fixed Z and a distance of 0.1 to 100 metres. A separate exact ID and script-data object identify each probe. They are not real teammate markers and do not change the navigation waypoint.

Each probe records the minimap and full-map controller that actually updated its own data. The caller explicitly supplies a real teammate controller and its corresponding view controller. The experiment samples the entire set synchronously on the game/UI thread. It never schedules background engine access.

Native `WidgetUtils.LocalToGlobal(probeRoot, point)` followed by `WidgetUtils.GlobalToLocal(targetRoot, point)` measures coordinates in the **exact parent used by the existing teammate-facing preview**. No camera yaw, global HUD projection or assumed screen-to-map conversion is used. Each source root records five points: local origin, anchor times size, render pivot times size, local +X and local +Y. Origin, anchor and pivot remain separate candidate landmarks.

Two immediate reads capture mappin/controller/data/root references, exact Uint64 IDs, requested world-position readback, controller update counters, parent chains, size/anchor/pivot, forward conversions and inverse roundtrips. Changed identities, coordinates, ancestry or revisions reject the sample. Saturated counters reject rather than wrap. These are provenance checks, not a post-layout barrier.

The Lua analyzer rejects missing/duplicate probe IDs, wrong world offsets, mixed surfaces, replaced target data, stale/replayed tokens, missing/hidden/clamped/grouped ancestry, nonfinite values, singular UI conversions and changed measurements. Adjacent Uint64 IDs above 2^53 stay exact. For each landmark it reports a candidate world-X/world-Y basis and diagonal residual. A candidate needs nondegenerate axes and a residual no larger than `0.05 + 0.005 * axisSpan` in target-local units. This diagnostic threshold is not a proven pixel or gameplay error bound.

## Native evidence

Paths below are game-relative, inspected against the locally installed game and Codeware 1.18.0. The private audit records source hashes.

- `tools/redmod/scripts/core/ui/widgetUtils.script:3-6`: native local/global UI conversions.
- `tools/redmod/scripts/core/systems/mappinSystem.script:21-34`: position registration, exact ID lookup and void unregister.
- `tools/redmod/scripts/cyberpunk/UI/mappins/mappinsControllers.script:17-31`: mappin access and protected clamp query.
- `tools/redmod/scripts/cyberpunk/UI/mappins/minimapMappins.script:1101`: minimap update hook.
- `red4ext/plugins/Codeware/Scripts/Codeware.Global.reds:2438-2445,42919-42920`: native clamped/unclamped minimap containers and exact parent lookup.
- `tools/redmod/scripts/cyberpunk/UI/mappins/mappinsContainers.script:7`: native map spawn-container getter.
- `tools/redmod/scripts/cyberpunk/UI/fullscreen/map/worldMap.script:1732-1751,1769-1779`: independent full-map filter, zoom, grouping and update path.

The minimap requires a bounded, noncyclic ancestry path through the exact native **unclamped** container, never its clamped counterpart, ending at the captured view root. Full-map probes require that view's exact spawn container, filter/zoom visibility and no grouping/collection. Each traversed widget must be visible with positive finite opacity. A changed view/container reference invalidates capture.

## Explicit experiment use

This source is excluded from the normal session installation and package. It requires the matching PR15 `marker.reds` and Codeware. The example describes a later, separately authorized test; it is not an instruction to install or run it now.

On the game/UI thread, with a loaded player and deliberately chosen world origin:

```lua
-- Preserve this handle even when registration is partial or the player detaches.
probe = player:CP2077MapBasis_Start(origin, 5.0)
capture = dofile("path/to/map_basis_capture.lua")
tracker, reason = capture.bind(probe)

-- target/view must be exact observed native controller objects from the
-- currently open surface. This module does not guess them from widget names.
report, raw = tracker:capture("minimap", minimapTeammateController, minimapViewController)
-- Separately, while the full map is open:
report, raw = tracker:capture("fullmap", fullmapTeammateController, fullmapViewController)
```

`CP2077MapBasis_Start` returns the owned probe even after partial registration; `probe.active` and `capture.bind` remain false until all four registrations succeed. A second Start on that player fails until explicit cleanup succeeds. If a previously owned probe remains unresolved after player replacement, the caller must not start another one on the new player.

Save only a bounded set of raw records with UTC timestamps and a video reference. Do not serialize native pointers as portable IDs. `report.provenanceValid` means the checks above accepted this raw observation. `candidate.geometryValid` means its arithmetic/residual checks passed. Neither proves a rendered arrow, clipping, current-frame layout or a native world-projection anchor.

Finish with `player:CP2077MapBasis_Stop()` while that player is available. If it returns false, retain `probe` and retry `probe:Stop()` in a later authorized game/UI callback. The probe retains a weak reference to the exact mappin system captured at Start, so cleanup does not require a live player or rediscover a different world's system. A successful direct `probe:Stop()` can then be followed by the player's Stop to clear its guard, if the player still exists.

Cleanup unregisters only an exact ID whose current script-data object is still owned. It checks lookup absence after its own unregister before releasing that ID. An ID never observed before unregister, unavailable system or an ID bound to foreign data remains unresolved. The caller must retain its probe until Stop returns true. `OnDetach` makes one best-effort attempt; it does **not** prove automatic cleanup. Native registration/unregister timing still needs game validation. Do not silently discard a pending handle or reset the fixture to hide it.

There is no capture loop, logging loop, automatic preview call or default activation. One call returns at most five roots, two reads, 64 ancestors per root and five landmarks per root. The four probes stay fixed; no moving-reference projection claims are made.

## Gates deliberately still false

Every report keeps `layoutVerified`, `onscreenVerified`, `projectionAnchorVerified` and `facingQualified` false. The analyzer also rejects a native sample that attempts to set any of these true.

- Native update callbacks and two equal reads do not establish a shared render/layout frame. Repeated captures of unchanged roots are raw observations, not a freshness certificate.
- Visible, unclamped ancestry does not prove inclusion within a nonrectangular minimap mask, map clipping or occlusion. No guessed circular mask or generic HUD screen predicate is used.
- Local origin, centered anchor and render pivot are hypotheses to measure independently. None is automatically selected as the projected world position.
- A small affine residual at four fixed points does not prove accuracy across a tilted/perspective full map, another zoom, another player position or another frame.
- Existing arrow rotation zero/sign and drawn direction still require visual qualification on each surface. This source never calls `CP2077Session_PreviewFacingBasis`.

Next live gates, when authorized: exact controller acquisition and CET reference equality; partial registration/cleanup and player detach; stationary fully visible probe readbacks; independent landmark identification; minimap rotation; full-map rotation/zoom/tilt; edge clamp and mask clipping; pause/menu changes; controller recreation and teammate reconnect. Capture logs plus video. Only a later reviewed change may connect a qualified sampler to the one-shot preview.

## Offline validation

- Windows Release Lua test runner rebuilt through the existing CMake configuration; focused CTest passed 3/3 (`map_basis_capture`, `marker_facing`, `player_markers`).
- Lua 5.4: new capture suite 109 checks; existing facing suite 192 checks and marker lifecycle suite passed.
- LuaJIT 2.1: new capture suite 112 checks, including actual Uint64 cdata above 2^53 and zero rejection; existing facing and marker lifecycle suites passed.
- Synthetic affine/reflected/rotated/sheared geometry, wrong diagonal residual, singular UI/world axes, roundtrip failures, missing/reused IDs, parent/view/controller/pose changes, saturated counters, replay/repair, unknown qualification flags and native-shaped adapter calls are exercised. These mocks do not execute the native REDscript callbacks or prove rendering.
- Isolated REDscript compilation passed with copied Test B cache/compiler, Codeware and matched session scripts. Input hashes stayed unchanged. Private log: `D:\Downloads\syncfix\bench-artifacts\20261015-map-basis-audit\redscript\compile-20261015T080703778873Z.log`. One earlier compile rejected `NewMappinID != NewMappinID`; corrected to exact Uint64 `.value` comparison, with no stubbed API.
- Independent source review prompted retaining the original weak mappin system for cleanup after player detach. No live test, installation, protocol change or package replacement occurred.
