# Action versus body timing, local private experiment

KyleBuildsAI owns this game-side measurement after2edbb2f on draftPR30. Existing
private32773 network/native runtime and production-v5 contracts remain unchanged.

## Observation and boundary

`SessionBridge::ReadFrame` samples body snapshots through their configured100ms
interpolation buffer, while its experimental presentation field contains the
latest received action state. This is source evidence of different timelines.
It does not by itself explain every animation stutter or prove WAN latency.

The read-only recorder now accepts an explicit30Hz timing capture. Default stays
5Hz, with the same8MiB/9000-frame and16-capture limits. No catch-up burst occurs.
`presentationTime` exposes the cosmetic renderer's local clock for comparison
within one actor. It is not a synchronized remote timestamp or measured ping.
Invalid rates reject without replacing the current recording.

The offline analyzer previously ignored CAPTURE after STOP and then discarded
the restarted recording. A regression reproduces that loss on the previous
source. It now recognizes validated explicit capture headers as separate runs,
including a retained rotated log beginning with CAPTURE. It never compares
movement/counters across those restarts. The capture label and requested rate
remain visible in the report; missing rotated bytes are not recovered.

## Recorded timing02

Both actual games used locomotion10 and the unchanged matched crouch assets,
normal clocks and scanner off. The normal92s synthetic SessionClient crouch route
completed. HOST130s/3025 fresh frames/23.44 callbacks Hz and JOINER145s/3366/23.38Hz
finalized without capture errors. JOINER recording began84s before admission,
so it covers the first60s, including the timing task, but NOT the recovery tail.
HOST covers the full route. Earlier timing01 recordings are setup only and do
not qualify a replay. These limitations are retained rather than hidden.

Saved high-rate subsets contain1502 HOST and996 JOINER player3 rows, with no
actor faults and root error<=0.000002m. The byte cap shortened JOINER's diagnostic
tail. Main first36s boundary observations are present in both:

| Observed event | HOST | JOINER |
| --- | ---: | ---: |
| First armed state to first forward motion |82.5ms|91.8ms|
| First ADS state to first backward motion |87.4ms|96.0ms|
| First standing state to root stopping |94.9ms|118.9ms|
| First standing state to idle gait |180.8ms|164.5ms|

These are sampled local intervals, not sub-frame timing, round-trip latency or
remote clock alignment. First standing samples still have0.47/0.57m/s inferred
body speed;4/3 early samples select standing backward direction. Original video
frames at6,18,24,33,36 and36.2s were reviewed in both windows. They show the bounded
crouch, reverse and standing transitions without a sustained T-pose in those
samples. Hands/sights, sideways crouch and complete smoothness remain open.

## Shared requirement, proposed for the presentation contract

Needed: render stance/weapon/aim changes on the same timeline as body snapshots.
Direction: source engine capture -> accepted presentation route -> receiving
game-side renderer. The existing action revision/sequence and local receipt age
do not identify the source movement sample associated with an action change;
periodic repairs refresh receipt age. A fixed extra delay cannot establish exact
ordering under different delivery jitter.

Bukczyk owns review of a shared source capture time or movement-sample association,
including its validation, repair/late-join/reconnect semantics. This is a proposal,
not an implemented packet change. KyleBuildsAI can consume accepted timing data,
keep per-actor state history and sample it with the body once the agreed contract
provides it. Acceptance: recorded move/stop/crouch/aim transitions, reordered or
delayed delivery, action expiry and reconnect, with both renderers measured.
No private or production wire change, backend redesign or fixed-delay workaround
is included here. Independent gait/asset/aim work can continue now.

## Automatic capture coverage

The separate `tools/run_player_action_capture.py` starts both existing window
recorders before admitting the replay. Both must produce a first frame. It then
requires actual video start/end timestamps to cover the entire replay, rather
than trusting requested duration. The parent must be new, so stale evidence
cannot satisfy readiness. Failures retain their result/logs and stop only owned
recorder/replay processes, never games/server. `visual_pass` remains false.

Paired01 completed in the real bench at2026-10-20T11:57:22Z. Both117s captures
cover the entire92s gait replay: HOST2382 fresh frames/20.55 callbacks Hz and
JOINER2364/20.41Hz, no capture errors.400/409 retained diagnostic rows have no
actor faults, root error<=0.000002m and idle/walk/sprint coverage. Rejoin changes
exact native bindings on both endpoints. This qualifies recording coverage,
not animation quality automatically; video review remains separate.

Windows experimental73/73 and production-v5 control71/71 pass. An initial CMake
registration reused the existing input-capture test name; configuration failed
explicitly. The video test now has its own name and both builds/suites were rerun
successfully. No failed configure or earlier72-test output is counted as73 tests.
Focused analyzer regression fails the previous source and passes the correction.

Changed ownership: KyleBuildsAI retains the read-only recorder/wrapper, passive
diagnostic field, offline analyzer, paired recorder runner, related tests/CMake
registration and documentation. Bukczyk's protocol/session/backend files are
unchanged. Both games/server remain open, normal speed and scanner off. Controls,
private keys/configuration and current saves remain preserved.

Private logs/videos, timing calculations and install hashes remain under
20261020-crouch-mask. No owned-game data is published or new release created.
