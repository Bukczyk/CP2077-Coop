# Teammate marker bridge

Offline checkpoint, 2026-10-09 04:36 UTC: Windows Release plugin/server build and
30/30 local CTests passed, including marker/UI and actual entrypoint lifecycle
fixtures. Isolated REDscript compilation of the final marker source passed with
installed inputs unchanged. Private HOST/JOINER staging includes both new Lua
modules and marker.reds; every staging-manifest hash was verified. No game was
launched, no install was changed, no public package/release was promoted.

This game-side preparation gives each remote PlayerId one owned position mappin.
The minimap and full-map icon override uses the shipped person symbol when the
existing widget atlas can resolve it. Actual appearance is not live qualified.
An explicitly invoked facing-arrow calibration fixture is implemented. Automatic
facing remains disabled: no authoritative world-to-minimap transform was found,
and neither icon appearance nor arrow direction has live qualification.

## Ownership and interface

KyleBuildsAI owns the marker bridge and presentation. This implementation changes
no protocol, native session interface, server behavior or network ownership.
Source files owned by this subtask:

- `runtime/session/redscript/CP2077Coop/marker.reds`
- `docs/TEAMMATE_MARKERS.md`
- `experiments/player-presentation/marker_facing.lua`,
  `tests/marker_facing_tests.lua` and its registration in `tests/CMakeLists.txt`.
- `runtime/session/cet/CP2077Coop/player_markers.lua`, marker integration in
  `init.lua` and `config.lua`, `tests/player_markers_tests.lua`, marker cases in
  `tests/session_lifecycle_tests.lua`, test registration and package inclusion.

2026-10-09 04:33:17 UTC: marker-source subtask handed these two files to the
parent task for isolated compilation and combined review. No ownership of
backend/network files transferred, and no live test occurred.

Methods added to the receiving `PlayerPuppet`:

```reds
public func CP2077Session_SetPlayerMarker(playerId: Uint32, x: Float, y: Float, z: Float, yaw: Float) -> Bool
public func CP2077Session_RemovePlayerMarker(playerId: Uint32) -> Bool
public func CP2077Session_ClearPlayerMarkers() -> Bool
```

`yaw` is body-facing heading in radians from the same received pose as XYZ.
Positions use the existing protocol bounds of +/-1,000,000, and heading uses
+/-6.283186. NaN, infinities, out-of-range coordinates/headings and PlayerId zero
are rejected before mutation. A detached receiving player cannot create or
update markers. Invalid input preserves the prior marker.

The caller owns session/epoch/SessionEntityId scope and frame membership.
It must remove the old lifetime before reusing PlayerId, exclude the local
player, and remove players absent from the native frame. These markers follow received player
positions independently of proxy visibility, spawning or streaming. This can
differ from a delayed avatar pose; it does not measure display latency.
`SessionBridge::ReadFrame` already excludes uninitialized remote transforms,
future receive timestamps and transforms received more than 1000 ms ago
(`shared/src/game_bridge.cpp:276-282`). Missing native-frame membership therefore
retires a stale marker. There is no raw per-player receive-age accessor in the
inspected CET bridge; rereading an interpolated pose is not a fresh packet.
An independent age badge needs a measured age interface. See
[the player data audit](PLAYER_DATA_AVAILABILITY.md).

The Lua controller preserves Uint64 identities as opaque strings, updates each
pin at most 10 times per second, and bounds failed updates/removals to three
attempts separated by at least one second. Uncertain removal retains the old
entry and blocks replacement. Diagnostic `position_requested` means the Void
engine setters were invoked, not observed placement. Retirement retries continue
while unloaded. On a loaded player's first observation, owned REDscript handles
are cleared even if markers are disabled or the network is not active; this
recovers retained handles after a CET reload without touching navigation.

`experimentalPlayerMarkers` defaults to false pending visual qualification. The
matched packager includes marker.reds, but this branch does not install it or
promote a release. Lua tests cover multiple players, reused IDs, scope changes,
departure, ambiguous/invalid samples, bounded failures, opaque IDs and reload.
The actual entrypoint fixture verifies markers without an available proxy
system, unloaded cleanup retries and disabled/disconnected reload recovery.

The player owns a dynamic array of entries containing exact `NewMappinID`
handles. An update reuses its entry and cannot register a duplicate for that
PlayerId. Registration is retained only when the returned handle is nonzero.
Removal is idempotent; absent entries return true. Missing MappinSystem returns
false while retaining owned entries for retry. Clear unregisters only the
recorded handles. `OnDetach` attempts clear before the original callback while
the old player's game instance remains available.

The engine update/unregister APIs return Void. A true result means registration
returned a nonzero handle or the requested calls were issued, not observed
rendering/disappearance. The bridge never tracks, untracks or replaces the
player's navigation waypoint and never removes markers found by a global scan.

## Presentation and fallback

The marker uses `Mappins.CustomPositionMappinDefinition` and
`CustomPositionVariant` for the generic engine controller. Its custom
`CP2077SessionPlayerMarkerData` subtype gates both icon wrappers; all unrelated
mappins keep their normal behavior. The subtype does not derive from
`GameplayRoleMappinData`, which would route minimap presentation to a device
controller.

The wrappers run the normal `UpdateIcon` first, read
`MappinIcons.NPCMappin.AtlasPartName`, and apply it only when
`inkImageRef.IsTexturePartExist` succeeds in the widget's existing atlas. The
shipped record maps `npc` to
`base\gameplay\gui\common\icons\mappin_icons.inkatlas`. No atlas is changed and
no CPO controller cast is introduced. An unavailable record/part leaves the
standard marker intact. The in-world marker retains generic presentation.

Normal marker updates apply no UI rotation. The calibration fixture described
below affects only a newly created child of an owned marker's controller root.
It does not rotate or reparent the existing icon, compass, map or clamp arrow.

## Facing calibration fixture, disabled by default

`experiments/player-presentation/marker_facing.lua` is developer-only. It is not
loaded by `init.lua`, is outside the package's runtime Lua directory, and installs
no hooks, polling loop or view provider. Every `preview(controller, sample)` call
requires `sample.enabled = true` and a complete new sample. Enabling position
markers does not enable the arrow.

The basis columns `(xx, xy)` and `(yx, yy)` must describe world +X and world +Y
in **that exact controller root's local coordinates** at the sampled view. Three
synchronized, unclamped projected points can mathematically define this basis;
`basis_from_points` computes their differences. It does not create probe mappins
or obtain projections. Screen coordinates need a proven conversion to the
parent's local space before use. A compass widget angle, player camera yaw or
remote movement direction is not accepted as an automatic substitute.

The inspected `MinimapSystem` exposes settings and vehicle-radius overrides,
without a view/projection matrix. `MinimapContainerController` exposes compass,
player-icon and geometry widgets but no documented world-to-map conversion.
`IMappin` provides world position, not projected position. `GetScreenPosition`
and `inkCompoundWidget.GetChildPosition` describe existing widgets, so one marker
cannot establish a 2D world basis. `worlduiIGameController.ProjectWorldToScreen`,
`CameraSystem.ProjectPoint` and `inkScreenProjection` are HUD/camera projection
interfaces; their declarations do not establish minimap projection. No automatic
map orientation, cardinal-axis convention, zoom convention or ancestor-transform
correction is claimed from these declarations.

The native calculation uses received body yaw in radians, converts it once with
`Rad2Deg`, then calls `Quaternion.GetForward(EulerAngles.ToQuat(rotation))`.
It maps that vector through the supplied basis and calculates
`rotationSign * Rad2Deg(AtanF(dx, -dy)) + zeroDegrees`. The preview's unrotated
shape points up in its parent space. `rotationSign` must be +1 or -1 and
`zeroDegrees` must be within +/-180; these explicitly calibrate the widget angle
convention rather than assuming its rendered handedness. The vector conversion
comes from the engine, never position differences or velocity. Uniform zoom
cancels from the angle; nonuniform scale and view rotation remain in the basis.

Capture all of these before measuring a sample: the exact controller root
(`GetRootWidget()`), its current custom data (`GetMappin().GetScriptData()`), that
data's `poseRevision`, and `CP2077Session_GetFacingPreviewGeneration()`.
The Lua sample fields are `expected_root`, `expected_data`, `pose_revision`,
`generation`, `basis = {xx=..., xy=..., yx=..., yy=...}`, `rotation_sign`,
`zero_degrees`, and explicit `enabled = true`. Supply the same controller when
calling `preview`. A basis from the minimap must never be reused for the full map.
There is deliberately no example with guessed live basis values.

Both `MinimapPOIMappinController` and `BaseWorldMapMappinController` expose:

```reds
public func CP2077Session_GetFacingPreviewGeneration() -> Uint32
public func CP2077Session_ClearFacingPreview() -> Void
public func CP2077Session_PreviewFacingBasis(expectedRoot: wref<inkWidget>, expectedData: ref<CP2077SessionPlayerMarkerData>, expectedPoseRevision: Uint32, sampleToken: Uint32, worldXx: Float, worldXy: Float, worldYx: Float, worldYy: Float, rotationSign: Float, zeroDegrees: Float) -> Bool
```

The generation changes on every normal `UpdateIcon` and explicit clear; each
generation permits one attempt that reaches the preview helper. The exact root
and script-data references reject cross-surface/controller and PlayerId-lifetime
reuse. Pose revision rejects samples captured before another marker update.
Generation and pose counters saturate and then reject previews rather than
wrapping. Clamped markers and world-map groups/collections reject facing.
Missing ownership, detached owners, nonfinite/degenerate bases and invalid
calibration reject the preview while keeping the position icon unchanged.

The arrow is an owned `inkCanvas` containing three `inkRectangle` strokes.
Normal icon refresh, pose update, explicit clear, retirement and detach remove
only that canvas by reference. Preview registration uses weak references; Hide
unregisters itself and bulk clear snapshots its list before callbacks. A 150 ms
fade is configured with `dependsOnTimeDilation = false` and removes the child on
completion. This is declared playback configuration, **not live proof of pause
behavior**. No game/simulation-clock expiry is assumed. The normal refresh also
invalidates the preview, so a continuing experiment requires a fresh measured
sample after each refresh. A native view change that does not trigger that
refresh remains an unqualified timing boundary. Stop the experiment with
`marker_facing.clear(controller)`; its caller must clear on its own unload.

Offline tests exercise cardinal vectors, radian conversion through an injected
engine-conversion interface, wrap, arbitrary rotating views, zoom, anisotropic
scale, reflection, invalid inputs and independent per-surface forwarding.
The tests' synthetic yaw convention is explicitly not a native-engine result.
Compilation validates engine declarations; neither it nor pure math validates
rendered arrows, update cadence, clipping, fade while paused, or map calibration.
Live gates still include stationary turns, strafing/backward walking, wrap,
map rotation/zoom, paused menus, seated body orientation, stale transforms,
marker/controller recreation, cleanup/reload and both-peer evidence.

2026-10-09 05:08 UTC handoff: the marker-facing subtask owns and hands off the
five scoped source/doc/test files above to the parent for combined build and PR
review. 192 fixture assertions and all 31 local CTests passed against the existing
native build. Final isolated compilation at 05:07:44 UTC, including installed
Codeware, passed with all inputs hash-verified unchanged. Independent review
identified and verified fixes for captured-pose and cross-root sample races.
Private evidence is under `D:\Downloads\syncfix\bench-artifacts\20261009-marker-facing`.
This extends the offline-only checkpoint above; no game, deployment or public
package promotion occurred.

## Local API evidence

Inspected installed game sources under
`G:\SteamLibrary\steamapps\common\Cyberpunk 2077 - Baseline`:

| Relative source | Evidence |
| --- | --- |
| `tools/redmod/scripts/core/systems/mappinSystem.script:21-33` | Generic position registration, script-data/position updates, exact unregister and lookup; no exposed heading setter. |
| `tools/redmod/scripts/core/data/mappinData.script:15-29` | MappinData fields and Uint64 NewMappinID value. |
| `tools/redmod/scripts/cyberpunk/player/player.script:6572-6588` | Native remote-player registration uses its distinct API; unregister guards `id.value != Uint64(0)`. |
| `tools/redmod/scripts/cyberpunk/UI/widgets/minimap/minimap.script:476-477` | CustomPositionVariant uses the generic POI widget. |
| `tools/redmod/scripts/cyberpunk/UI/mappins/minimapMappins.script:1208-1234` | Generic POI UpdateIcon and inkImageRef texture assignment. |
| `tools/redmod/scripts/cyberpunk/UI/fullscreen/map/worldMap.script:1810-1833` | Generic world-map UpdateIcon. |
| `tools/redmod/tweaks/base/gameplay/static_data/database/ui/mappin_ui/mappin_icons.tweak:1-8` | MappinIcons.NPCMappin atlas and npc texture part. |
| `tools/redmod/scripts/core/ui/widgetReference.script:156-157,382-385` | Widget rotation is in degrees; texture-part existence/set and atlas APIs. |
| `tools/redmod/scripts/cyberpunk/UI/mappins/minimapMappins.script:985-1026` | CPO controller casts to RemotePlayerMappin and reads vitals/mission data. |
| `red4ext/plugins/Codeware/Scripts/Codeware.Global.reds:362-365,22307-22310` | iconOrientation supports Upright/Entity only, not arbitrary position-marker heading. |
| `tools/redmod/scripts/core/systems/minimapSystem.script` | Minimap settings/radius API, no exposed view/projection transform. |
| `red4ext/plugins/Codeware/Scripts/Codeware.Global.reds:2436-2455` | Reflected minimap container widget references; these do not establish a map basis. |
| `tools/redmod/scripts/core/ui/baseControllers/widgetController.script:1,312-315` | Widget screen bounds and generic world UI projection. |
| `tools/redmod/scripts/core/ui/screenProjection.script:16-23` and `core/ui/baseControllers/hudGameController.script:136-143` | Screen-projection positions belong to the projected HUD interface. |
| `tools/redmod/scripts/core/math/rot.script:10-14`, `core/math/quat.script:13`, `core/math/scalar.script:42` | Engine Euler/quaternion forward conversion and two-argument AtanF. |
| `tools/redmod/scripts/core/ui/baseWidgets/abstractWidgets.script:61-85,140-163,180,213,222` | Dynamic widget geometry, degree rotation, parent/child ownership and child position. |
| `tools/redmod/scripts/core/ui/baseWidgets/shapeWidget.script` | Native inkRectangle shape widget. |
| `tools/redmod/scripts/core/ui/animationPlaybackOptions.script:12-24`, `animationInterpolators.script:12-13,63-69`, `animationProxy.script:12-21` | Fade duration, time-dilation option, exact animation stop/callback APIs. |
| `red4ext/plugins/Codeware/Scripts/Codeware.UI.reds:313-321,474-481` | Script-created canvas/rectangle and Reparent examples. |

Protocol validation bounds are from `shared/src/protocol.cpp:72-77` in this
checkout. The installed source inspection establishes declarations and routing;
it does not prove runtime rendering. Isolated compilation and automated
lifecycle checks are separate from the pending live-game gates.
