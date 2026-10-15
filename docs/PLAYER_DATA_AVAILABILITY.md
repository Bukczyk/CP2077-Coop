# Player presentation data: available versus proposed

Checked 2026-10-09 UTC against upstream main
`e19ffb3286efec750b8729487220becf6569ab7b` and PR5 base `b1f054e`.
PR15 and PR16 had no collaborator comments or reviews at this checkpoint.
The requests below remain proposals. No protocol, server, SessionBridge or
native API change is made by this document or the offline engine experiments.

| Feature | Current verified boundary | Remaining work |
| --- | --- | --- |
| Body position/facing | `BeginFrame`/`Select` supplies PlayerId, opaque SessionEntityId, XYZ and yaw radians. Session, epoch and generation are available. | KyleBuildsAI can use these for movement and markers now. Camera aim is different from body facing. |
| Stale map positions | `SessionBridge::ReadFrame` omits uninitialized/future-dated receive entries and those older than 1000 ms. | Existing frame absence drives marker cleanup. A precise age badge requires an accessor; repeatedly reading an interpolated pose is not a newly received packet. |
| Crouch, held weapon, held aim | `PlayerPose`/`PlayerState` contains entity, body transform and sample time only. | Agree accepted action state, revisions, supported records, loss repair and late-join/reconnect baseline before connecting the engine adapter. |
| Aim direction / pitch | Transform has three body Euler components, but the current game native sends only body yaw. There is no distinct aiming orientation. | Do not repurpose body rotation fields as aim flags or sight direction. Agree direction convention, radians/ranges and validity independently of the visual hook. |
| Ping / sample age | RemotePlayer retains source and local receive times internally; Frame exposes neither. Client heartbeat updates liveness, with no stored RTT metric. | Bukczyk reviews measured server RTT and local receipt age accessors; KyleBuildsAI labels and displays their meaning. |
| Reliable gameplay | Generic GameplaySubmit/Reply exists with opaque bodies and kind correlation. | Delivery alone does not establish an action schema, permission rules or a current-state cache. Do not allocate an action kind without agreement. |

## Smallest useful interface proposals

For held player presentation, the owning game observes crouch/draw/equip/aim
changes and supplies an agreed state for its authenticated player/entity. Peers
need the latest accepted revision and session/epoch identity, including baseline
recovery. Missing/reordered state must not latch an old pose. One-shot shot/reload
events need separate expiry/deduplication rules. The complete proposal is in
[PR16](https://github.com/Bukczyk/CP2077-Coop/pull/16).

For diagnostics, expose valid/unknown server RTT in milliseconds with measurement
age, and per-player local receive age with a validity flag, through coherent
game-thread values. Updates should follow actual measurements; disconnect and
generation changes invalidate them. This is a local client-to-UI boundary, not
a request for a new gameplay packet. Source timestamps from another clock must
not be subtracted from the local clock and called latency. See
[SESSION_STATUS_UI.md](SESSION_STATUS_UI.md).

Neither proposal blocks basic First Contact or offline engine work. Body-facing
arrows also require a verified map transform on KyleBuildsAI's side; additional
network fields do not solve that UI calibration problem.

## Source evidence

- [PlayerPose/PlayerState and Transform](https://github.com/Bukczyk/CP2077-Coop/blob/e19ffb3286efec750b8729487220becf6569ab7b/shared/include/coop/protocol.hpp#L45-L66).
- [RenderPlayer and Frame](https://github.com/Bukczyk/CP2077-Coop/blob/e19ffb3286efec750b8729487220becf6569ab7b/shared/include/coop/game_bridge.hpp#L72-L82).
- [Receive-age gate and interpolated frame](https://github.com/Bukczyk/CP2077-Coop/blob/e19ffb3286efec750b8729487220becf6569ab7b/shared/src/game_bridge.cpp#L276-L292).
- [RemotePlayer timestamps](https://github.com/Bukczyk/CP2077-Coop/blob/e19ffb3286efec750b8729487220becf6569ab7b/shared/include/coop/client.hpp#L18-L23).
- [Accepted snapshots and heartbeat handling](https://github.com/Bukczyk/CP2077-Coop/blob/e19ffb3286efec750b8729487220becf6569ab7b/shared/src/client.cpp#L132-L148).
- [Game-native transform input/output](https://github.com/Bukczyk/CP2077-Coop/blob/e19ffb3286efec750b8729487220becf6569ab7b/CoopPlugin/src/main.cpp#L74-L121).
