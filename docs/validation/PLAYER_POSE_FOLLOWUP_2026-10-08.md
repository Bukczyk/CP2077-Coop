# Player pose follow-up, 2026-10-08 UTC

Owner: KyleBuildsAI, PR #5 (`feat/player-movement-presentation`), starting at
`7df4763f1b5e06cef5d440b41d1b1c9bcd986d73`, based on upstream `e19ffb3`.
Owned changes: `player_pose.lua`, the diagnostic return in `init.lua`,
`tests/player_pose_tests.lua`, `experiments/player-pose-fixture/`, and this record.
No protocol, native networking, server, combat or vehicle changes.

## WAN evidence and unresolved failure

The two-PC Debian trial admitted HOST and JOINER into the same session. JOINER
received changing HOST coordinates but its exact actor latched `readback_timeout`.
Bukczyk reported that a controlled five-metre JOINER position change moved his
visible HOST Judy as a teleport. The JOINER actor later changed identity and
matched a stationary HOST pose, without an agent reconnect. Its replacement
cause and sustained movement recovery remain unverified. HOST closure produced
`SESSION_CLOSED` and zero tracked projections. This is not smooth multiplayer.

## Changes

Retain the existing bounded attempts and fail-closed command ownership. Add
detached value diagnostics: command submissions, failures, command age/state,
admitted and actual transforms, separate position/heading errors, and the last
failure captured before cancellation changes the command state. New targets
cannot change the admitted-pose comparison. Actor reset clears old evidence.
This adds diagnosis, not a claimed timeout fix or a permissive retry loop.

Add an explicitly started, 32-second local fixture using the same pose module.
It measures spawn, translation, rotation and a moving target without sending
network state or changing the player. See its README for bounds and use.

## Live local evidence

Test B remained open; production DLL/scripts/configuration stayed at the prior
first-contact build. Only a separate diagnostic CET mod was installed. CET
reloads reset its modules and caused connection attempts to the already-ended
session; no HOST session was available. No controls, saves or keys were restored.

- One existing AI command moved the fixture exactly one metre and 90 degrees;
  actual transform and command state 5 were read back, and cancellation returned true.
- Slow route: 293 samples, no fault samples, moving-phase position P95 about
  0.210 m at 0.5 m/s.
- Faster route: 294 samples, no fault samples, moving-phase position P95 about
  1.507 m at 6 m/s while heading changed at 1.5 radians/s.
- Immediate 180-degree spawn heading mismatch: completed its 32-second trial
  without a latched fault, including subsequent translation and rotation.

These were scripted local engine targets, not walking input, network tests or
animation passes. Initial origin samples produced roughly 1147 m error and are
retained in raw logs; the P95 figures above cover only moving phases 3 and 4.
Fixture cleanup requested deletion; full visual cleanup is not certified. A
body remained visible after tag cleanup during these experiments, requiring
exact-entity retirement investigation before claiming disappearance.

Windows Release build passed; all 26 CTests passed. The focused player pose test
passes 44 checks, including immutable diagnostics, pre-cancellation state,
rotation-only error, moving latest targets and reset isolation. REDscript/native
source is unchanged. Hosted CI is recorded in the PR after publication.

Private raw logs and metrics: `bench-artifacts/20261008-player-pose-followup`.
Public v0.0.37/alpha.5 remains unchanged; this is diagnostic development, not a
new playable release. The fixture is excluded from normal packages.

## Next test

The WAN freeze was not reproduced by these three local trials. Capture the new
pose diagnostics during the next connected failure, including foreground/pause
state, exact actor ID and admitted command. Diagnose delayed AI execution versus
position-only/heading-only failure before choosing recovery. Independently verify
exact actor retirement and duplicates; a missing tag alone is insufficient.
Then measure continuous following in both directions and human-observed animation.
