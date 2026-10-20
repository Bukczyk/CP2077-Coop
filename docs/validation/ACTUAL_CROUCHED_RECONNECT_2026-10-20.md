# Actual crouched player reconnect

Two actual local Cyberpunk clients ran the installed `f15c089` game-side
renderer, lower animation M13 and action layer 2. No synthetic participant was
connected during this check. Both players were crouched, holstered and not
aiming. The existing CET reconnect button was used without changing bindings.

The second run captured both windows for 90 seconds after stable encoder
startup. Native JOINER HELLO was observed at 2026-10-20T16:05:06.805Z, accepted
at 16:05:06.819Z, and SESSION_READY at 16:05:06.829Z. The local session remained
1, HOST remained PlayerId 1, and the reconnected JOINER changed from 11 to 12.
These are local test identities, not a claim about multi-PC operation.

## Observed result

Original HOST frames around HELLO show the previous crouched actor, a brief
empty interval, then the replacement already crouched. It is visible by the
sample at +0.311 seconds and remains crouched through the reviewed +12.011
second sample. The sampled first appearance does not show the upright pose
seen in some synthetic replay initializations. That synthetic behavior is
therefore not a demonstrated actual-client bug.

HOST diagnostics retain 23 old-player rows and 94 new-player rows over the
selected window. Old actor 10837101 and replacement 10837417 are distinct.
Every new-player row reports fresh stance 2, stance weight 1 and no actor fault;
maximum root readback error is 0.000002 m. No diagnostic tick contains both
players. The controller retains retiring entries in diagnostics and only drops
one after the original creator and retained exact native handles confirm
removal. Together with the visible empty interval, this supports cleanup for
this reconnect. It is not a general proof against all cleanup races.

The recordings contain 2214 HOST and 2240 JOINER original frames. Both pass
coverage/cadence checks with unchanged tool hashes; maximum tested gaps are
84.0 ms and 139.3 ms. Events shorter than those gaps are not excluded. The
JOINER video is retained as the actual-source view; it does not observe its own
remote proxy. Consequently there are no JOINER diagnostic rows for players
11/12, and no such rows are claimed.

An earlier run also reconnected successfully but normal join placement moved
the source beside HOST and outside the observer's view. It qualifies connection
and stance traces only, not first-visible-pose behavior. For the second run,
HOST rotated in place toward the actual join position and crouched to improve
the view. The existing join placement offset was not changed.

## Scope and preservation

This is one controlled actual-client reconnect, not physical walking/sprinting,
WAN, arbitrary appearance or full player synchronization acceptance. There was
no firing, remapping, protocol/backend edit or runtime deployment during it.
Both games/server remain open, clocks normal and scanners off. Controls,
configuration, graphics and current saves are preserved. Stable v0.0.37 and
`game-files/latest` are untouched. Raw evidence remains private in
`20261020-crouch-mask/actual-crouched-reconnect01` and `02`.

KyleBuildsAI owns this engine-test evidence. The next independent game-side
checks are recovery from rejected cosmetic updates, source/render timing
diagnostics and terrain/pose quality. Camera/sample-time contract work remains
subject to the shared networking review.
