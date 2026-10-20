# Keep late crouch state from covering jump animation

The private action renderer previously applied crouch whenever the latest fresh
action snapshot said crouching. The movement path independently infers takeoff,
flight and landing. A delayed or held crouch snapshot therefore covered those
phases with a grounded crouch, visibly lifting a crouched body through the air.

`player_presentation.lua`, action revision `20261020-realtime-actions-2`, admits
the crouch layer only during grounded idle/walk/sprint. It releases the layer
over the existing 80 real milliseconds during takeoff/flight/landing, then blends
the still-valid crouch back in after landing. Guarded weapon visibility and aim
state remain active. No received action, entity transform or authority is changed.
No animation asset, native DLL, private/production wire format or backend change.

The focused regression fails the retained original module at "late crouch cannot
fully override takeoff" and passes the candidate. It covers holstered/Igla states,
takeoff release, settled flight, landing, grounded recovery and weapon visibility.
Windows experimental 77/77 and default-v5 control 75/75 pass sequentially.

The private `--jump-actions` replay adds four continuous 0.9 m hops: standing
armed, held crouch/unarmed, held crouch/aim and standing aim. The old repair,
expiry, unsupported-state and disconnect/rejoin tail is retained. Preflight
checks height/endpoints, phase states and mode exclusions before credentials or
sockets. These are synthetic fault cases, not actual keyboard jumping.

## Recorded comparison

Both before and after runs complete the same 92-second route with concurrent
117-second videos in both actual games. Before: 76 HOST and 14 JOINER held-crouch
air/landing rows all retain stance weight 1. Original midair frames visibly show
the grounded crouch. HOST's explicit 30 Hz diagnostic capture reaches its byte
bound before reconnect; its later tail has no diagnostic qualification. JOINER's
5 Hz capture retains the complete route and both actors.

After: 410 HOST / 407 JOINER complete rows, all reporting action revision 2.
Among held-crouch air/landing rows, 14/15 HOST and 13/14 JOINER have weight zero;
the remaining sample in each is the bounded early release. Neither retains a
fully crouched air/landing sample. Original airborne frames show the jump clip,
with armed/aim handling preserved. No actor fault, maximum root readback error
0.000004 m. Exact actors before/after rejoin:

| Run | HOST actors | JOINER actors |
| --- | --- | --- |
| Before | 10833126; rejoin outside its diagnostic bound | 10833003 / 10833193 |
| After | 10833996 / 10834070 | 10833929 / 10834031 |

After videos contain 2880/2820 original HOST/JOINER frames at 24.80/24.29 fresh
callbacks/s. Callback cadence is not engine FPS. Original takeoff/flight/landing,
recovery and removal/rejoin samples were reviewed in both views. Occlusions are
excluded. The unarmed native air clip has a wide-arm pose that remains a visual
tuning item; this change does not certify every animation as finished.

The subsequent full 92-second `crouch-sides` regression is also recorded for
117 seconds in both games: 2975/2928 original frames, 410/404 complete rows,
170/167 fully weighted side-crouch samples, both side axes and weapon states.
No faults; root readback error <=0.000002 m. Original movement, stop, armed/aim
and recovery/rejoin frames retain expected grounded crouch behavior. Exact
HOST actors 10834203/10834299 and JOINER 10834148/10834267 are distinct on rejoin.

Two module copies changed with both games/server stopped. Old modules and hashes
are retained in `before-jump-guard01`; all 11 protected configuration hashes match.
Native runtime/server remain `9f27bd4`, lower gait M13 and private assets unchanged.
Current saves/controls/graphics/keys are preserved. Stable v0.0.37/latest remains.

This is controlled local flat-ground evidence. Movement still infers jumping
from vertical displacement, so stairs, terrain, physical-input timing, WAN,
precise grip and camera-directed aim remain unqualified. Raw videos, game-derived
caches and logs stay private under `20261020-crouch-mask/connected-jump-*`.
