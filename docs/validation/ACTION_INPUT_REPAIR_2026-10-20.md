# Recover unchanged action inputs after a graph reset

The action adapter cached its seven float inputs indefinitely. If the engine
discarded those values during a graph reset, an unchanged crouch/weapon/aim
state could never restore them. Lower-body locomotion already had bounded
repair, so the two layers had different recovery behavior.

Action layer 4 repairs its complete float input set once per presentation-clock
second, and once after a clock gap or rewind. Ordinary changed inputs still
submit immediately. It preserves blend state and does not toggle cosmetic
weapon visibility. Each returned QueueEvent call updates its cache and the new
read-only `actionInputSubmissions` counter; an exception leaves only missing
values retryable. These counters do not prove animation receipt or an FPS gain.

The cache also rejects numeric, zero, malformed and overflowing actor hashes.
The exact native actor must match the state's owner before any setter is called.
There is no protocol, server, authority, asset or source-action capture change.

## Validation

The focused regression independently clears a mock engine's input table while
keeping the same actor and admitted action revision. Action layer 3 fails to
restore it; layer 4 restores the crouch/weapon values. The test covers bounded
steady work, duplicate/rewound clocks, partial queue rejection, stale release,
no visibility retoggle and exact actor isolation. Diagnostic integration checks
verify the counter comes from the correct owned entry. Full Windows Release
experimental **77/77** and default-v5 control **75/75** pass.

Six Lua files were installed only after both games and the local server exited
normally. Previous files and auxiliary source logs are backed up; all 13
protected configuration hashes remain exact. Action module SHA256:
`fda82998b9725bb6d69006a1309cbc1d5f08dc4ca024ef831adac6c790996bb5`.
Lower renderer M14, native assets M13 and matched native 9f27bd4 are unchanged.

Two complete 92-second synthetic routes were recorded for 117 seconds in BOTH
real games, with encoder warmup, cadence/coverage and unchanged-tool checks:

- `connected-action-input-repair01`: 408/408 complete matching rows, no faults,
  maximum root error 0.000002 m. Videos have 2,945/2,955 original frames and
  maximum replay gaps 77.9/75.1 ms. HOST actors 10846404/10846464 and JOINER
  actors 10846368/10846437 remain distinct across reconnect. Fifteen original
  selected frames per observer preserve crouch, aim, walking, sprinting, stops,
  stale neutralization, unsupported-weapon hiding and rejoined crouch poses.
- `connected-action-input-sprint01`: 408/408 complete matching rows, no faults,
  maximum root error 0.000002 m. Videos have 3,175/3,209 original frames and
  maximum replay gaps 67.0/79.4 ms. HOST actors 10846556/10846591 and JOINER
  actors 10846505/10846582 are distinct. The main sprint retains 89/90 gait-2
  samples spanning 18.492/18.669 seconds. All six laps plus stops/tail were
  reviewed using 24+13 original selected frames per view. No sustained T-pose
  or periodic visible pose restart was seen in these reviewed samples.

Stable action windows advance the counter in seven-input batches, never larger
in these sampled windows. Short-window rates range roughly 5.1 to 7.8 returned
submissions/second because repair boundaries and sample endpoints differ.
This matches bounded repair, not a per-frame full refresh. The simulated graph
reset itself was not naturally reproduced in-game; videos qualify normal-path
regression behavior, not every real engine reset.

Private original videos, frame PTS, diagnostic rows, old failing module and
passing test logs remain under `20261020-crouch-mask`. These are synthetic local
states rendered in two actual games, not physical-keyboard sprint or WAN proof.
Occlusions and events shorter than the sampled/capture intervals are excluded.
Source-time association, camera-directed aim, terrain contact, wide unarmed
jump arms and exact weapon grip remain open. Controls, settings and current saves
are preserved; stable v0.0.37/latest is untouched. KyleBuildsAI owns the action
adapter, passive/recorder counter fields, focused tests and this validation.
