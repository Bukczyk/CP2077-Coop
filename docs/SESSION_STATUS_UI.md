# Session status panel

KyleBuildsAI owns `session_ui.lua`, its CET event integration, configuration and
tests. This is a development overlay, not a new networking/session manager.
`showSessionUI = true` shows the panel only while the existing CET overlay is
open. No controls or bindings are changed. The reconnect button queues the same
existing cleanup/deactivation path as `cp2077_session_reconnect` for the next
`onUpdate`; the drawing callback never invokes engine cleanup. Repeated clicks
before that update coalesce into one request.

The display uses the actual `ClientPhase` values in `shared/include/coop/client.hpp`:
Disconnected, Connecting, Joining session, Synchronizing, Connected, and
Connection failed. It distinguishes unloaded saves and a stopped game bridge.
Active state shows HOST/JOINER, exact session ID, local PlayerId and the number
of remote player snapshots in the coherent `SessionBridge` frame. This count
is not total membership, observed visible actors or verified live capacity.
Session/player/count fields clear when inactive, failed or unloaded.

## Measured ping dependency

The inspected v5 CET/native bridge supplies no RTT or per-player sample-age
accessor. The UI says `Ping: unavailable from current game bridge`. Snapshot
cadence, interpolation delay and time since drawing a frame are not ping.
The current bridge already excludes remote transforms older than 1000 ms at
frame creation. That bounds which cached positions can appear in the frame; it
does not expose their exact age or prove the corresponding actor is visible.
See [the current data audit](PLAYER_DATA_AVAILABILITY.md) for source references.

Proposed for Bukczyk's review: supply a measured client-to-server RTT
as milliseconds plus valid/unknown state and measurement age to the game
thread. Delivery is local SessionClient/SessionBridge -> CET/UI, refreshed when
a measurement is valid and invalidated on disconnect/reconnect. No reliable
gameplay event is required. Peer-to-peer display latency is a different metric
and must not be labeled with this server RTT. No transport or native API change
is implemented by this PR. This dependency does not block First Contact.
The current client does not retain an RTT measurement; heartbeat liveness alone
does not supply this value. Measurement support is part of the proposal.

## Validation and remaining gates

`session_ui_tests.lua` checks all six phases, reconnect progress, role/identity,
field clearing, unknown ping, collapsed windows, balanced Begin/End and the
existing reconnect callback. `session_lifecycle_tests.lua` executes the actual
CET entrypoint with its additional callbacks. UI rendering, readability and
button behavior in Cyberpunk remain untested because live testing is deferred.

CET's official [ImGui binding reference](https://github.com/maximegmd/CyberEngineTweaks/blob/master/src/sol_imgui/README.md)
documents that the single-argument `ImGui.Begin(name)` returns `shouldDraw`;
`ImGui.End()` is required even when collapsed. Inspected 2026-10-09 UTC.
