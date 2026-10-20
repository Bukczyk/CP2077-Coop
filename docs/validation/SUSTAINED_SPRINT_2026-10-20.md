# Sustained sprint rendering in both local games

The existing gait replay sprints6 m at6 m/s, then stops. That one-second case
cannot qualify the multi-second animation problem reported during sprinting.
The private `--sprint-loop` adds six complete radius3m laps at6 m/s, lasting
18.8496 seconds. It stays within a6m square, follows the tangent with a wrapped
body heading, and returns continuously to its starting position before stopping.
The original repair/expiry, unsupported state and reconnect tail remains.

Offline preflight emits381 route points before credentials or sockets. Focused
tests check sustained speed, bounds, constant height, body direction, closed
endpoints, rotated origins, mutually exclusive modes and coordinate overflow.
The paired recording CLI accepts the same mode. Both focused replay-input and
capture tests pass. No production wire format, backend or installed runtime
changed for this tool addition.

## Recorded result

Installed renderer: M14/action3 from `1f2308f`, native animation assets M13,
native DLL/server `9f27bd4`, private32773. Both clocks normal, scanners off.
The complete92-second route is recorded for117 seconds in both actual windows.
It passes warmup, coverage, cadence and unchanged-tool checks:2821 HOST/2791
JOINER original frames, largest replay gaps77.4/163.5 ms. Capture callback rates
24.28/24.04 Hz are not engine FPS.

The full route retains408/410 complete matching diagnostic rows. No actor
faults, maximum root readback error0.000002 m. HOST actors10843693/10843780 and
JOINER actors10843355/10843449 are distinct before/after reconnect.

Each observer records90 consecutive sprint rows, spanning18.651/18.711 seconds
on its own presentation clock, without a diagnostic gap over0.6 s. The stable
interior selects only sprint phase2. Observed heading covers5.93/5.95 turns in
those sampled sprint rows, with maximum yaw readback error0.000023 degrees.
These compare the local actor with its received/interpolated target; they are
not measurements of end-to-end input or network latency.

Original frames were reviewed at four positions in every lap, plus13 stop and
reconnect-tail times in both videos. Visible samples retain running poses and
supported weapon handling, without a sustained T-pose in the reviewed footage.
The stop samples settle back to standing. At5 Hz, the first sampled zero-speed
row is already idle in each observer. That does not prove a zero-millisecond
stop delay. Occluded frames and events shorter than the review/capture gaps
remain outside this claim.

This is controlled synthetic SessionClient state rendered in two real local
games. It is not physical keyboard sprinting, terrain, WAN or a guarantee that
every animation variant is finished. No controls, settings, saves or runtime
files changed during recording. The private recovery package remains the
matched M14/action3 checkpoint; this tool-only change does not create a new
gameplay release. Raw videos, frames, PTS and logs remain private.
