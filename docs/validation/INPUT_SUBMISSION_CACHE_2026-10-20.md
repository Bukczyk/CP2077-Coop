# Reduce redundant locomotion input submissions

The M13 lower renderer queues all19 float inputs on every update when direction
and blending are enabled. An idle actor repeats the same values. M14 remembers
values submitted to its exact native actor and queues changes immediately.
Progress and selectors retain their existing order. Once per real second it
refreshes the complete input set; a clock gap or rewind also repairs it once.
The repair covers an unobserved graph reset without a per-frame full refresh.

The cache accepts only a valid exact opaque actor ID, rejects numeric IDs and
cannot be reused on another actor. A value is cached only after its QueueEvent
call returns. A thrown call remains retryable without replaying earlier admitted
values. Each actor has independent cache, clock and submission count. The new
read-only `gaitInputSubmissions` diagnostic counts returned setter calls, not
animation receipts or frames rendered by the engine.

No motion, gait/direction inference, stride, blend timing, authority, asset or
network contract changes. This reduces redundant engine work; it does not by
itself prove an FPS gain or solve every source of visible stutter.

## Validation

The focused regression fails M13 at unchanged idle input submissions and passes
M14. It covers changed progress, exact actor separation, lossy IDs, partial queue
exceptions, independent full-profile state, bounded real-time repair and clock
rewind/duplicate handling. Windows experimental77/77 passes. A first full control
run has one NPC-test `UDP bind failed`; after the games/server stopped, the full
control rerun passes75/75. Both logs are retained. No backend assertion or
networking semantics were changed to bypass that failure.

A controlled ten-second601-frame Lua probe queues11,419 setters in M13 at idle
and at2 m/s. M14 queues209 at idle and1,400 at2 m/s using the same samples. Those
are mock-engine call counts, not in-game performance measurements.

Six matched Lua/diagnostic files were installed while both games/server were
stopped, with backups and all13 protected configuration hashes unchanged. Lower
module SHA256: `a760b9854b6fa49e4458f4f0b273bab752cb772ef3269d608740ed1f01a943c1`.
The M13 native animation assets, action layer3 and native DLL/server remain.

The full92-second `connected-input-cache-crouch01` route is recorded for117
seconds in both real games, passing coverage/cadence and unchanged-tool checks.
There are409 HOST /410 JOINER complete matching rows,169/171 fully weighted side
crouch samples, both side directions and holstered/Igla states. No actor faults;
maximum root readback error0.000002 m. HOST actors10841595/10841730 and JOINER
actors10841576/10841677 are distinct before/after reconnect. Original movement,
stops, weapon/aim, expiry/repair and reconnect-tail frames were reviewed in both
views. Expected low poses remain visible; occlusions are excluded.

In stable actual idle/stop windows, the counter advances in batches no larger
than19. Most sampled windows show about19 to21 submissions/second; one short
HOST window spans only two repair boundaries and measures13.8. This matches the
bounded repair behavior without claiming an engine FPS improvement.

The separate full92-second standing gait route is also recorded for117 seconds
in both views:406/410 complete matching rows, no faults, root error<=0.000002 m,
and distinct HOST actors10842368/10842466 and JOINER actors10842183/10842259.
Original walk, short sprint, stop, repair and reconnect frames were reviewed in
both views. Crouch videos contain2777/2765 original frames; gait videos contain
2852/2876. Maximum replay gaps are164.4/76.3 ms and72.9/80.9 ms respectively;
all tools remain unchanged. These sampled frames show no sustained T-pose in
visible actors. The gait route's sprint lasts about one second, so this evidence
does not qualify sustained sprinting. That needs a longer separate replay.

Private original videos, PTS, diagnostic rows and before/after modules are kept
under `20261020-crouch-mask`. Controls, configuration, graphics and current saves
are preserved. Stable v0.0.37/latest is untouched. KyleBuildsAI owns the lower
renderer, passive-player diagnostic field, recorder field, focused tests and this
record. Protocol, server and session source are unchanged.
