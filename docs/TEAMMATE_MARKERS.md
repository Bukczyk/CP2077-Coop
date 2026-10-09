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
The facing arrow is not implemented or qualified: body heading is retained as
data pending map-relative rotation calibration.

## Ownership and interface

KyleBuildsAI owns the marker bridge and presentation. This implementation changes
no protocol, native session interface, server behavior or network ownership.
Source files owned by this subtask:

- `runtime/session/redscript/CP2077Coop/marker.reds`
- `docs/TEAMMATE_MARKERS.md`
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
There is no raw per-player receive-age accessor in the inspected CET bridge.
Reading the same interpolated pose each frame must not be treated as a fresh
packet. Frame membership and session/epoch transitions drive cleanup; an
independent stale-packet badge is deferred pending a measured age interface.

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

No UI rotation is applied. The exposed widget rotation function alone does not
establish correct body heading relative to a rotating minimap. Arrow work needs
stationary turns, strafing, backward walking, angle wraparound, map rotation and
zoom, seated orientation, stale-state handling and both-peer evidence.

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

Protocol validation bounds are from `shared/src/protocol.cpp:72-77` in this
checkout. The installed source inspection establishes declarations and routing;
it does not prove runtime rendering. Isolated compilation and automated
lifecycle checks are separate from the pending live-game gates.
