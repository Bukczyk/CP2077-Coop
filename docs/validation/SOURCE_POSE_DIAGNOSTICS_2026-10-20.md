# Local source pose beside action observations

The private bounded source logger now records actual root position, body yaw,
native locomotion enum, exact local EntityID, separate SessionEntityId, generation
and epoch in the same game-thread callback as crouch/aim/weapon/camera readback.
Missing getters, non-finite values, lossy numeric IDs and scope changes make only
the optional pose unavailable. Essential action observation continues. Session
phase, generation, epoch and identities are rechecked after the optional reads.
No protocol, session/server behavior, movement capture or rendering changes.

Local update time/observation ordinal are diagnostic only. The wall timestamp
has one-second precision. This is not an atomic engine/network snapshot, a wire
capture timestamp, or a packet sequence. A locomotion enum such as `Default`
does not establish ground contact. The log retains its2 MiB/9,000-row bound.

## Validation

Focused tests cover valid exact separated identities plus missing pose getter,
NaN, numeric entity identity, changing generation and changing phase. Optional
failure cannot stop essential capture. Windows experimental77/77 and default-v5
control75/75 pass. The last added phase-change test also passes the experimental
focused check and the full control run.

The two auxiliary Lua copies were installed only after both games and local
server stopped normally. Previous modules/logs were backed up and all13 protected
configuration hashes remain exact. Installed SHA256:
`47cdf36ca2ace85f33eca91ea3c78fa9fdbb61fc8c8682494704541b3bbc7373`.

The actual two-player `actual-source-pose01` test records both real games for90
seconds, with encoder warmup, complete coverage and unchanged recording tools.
One debug HOST placement before recording makes the actual HOST proxy visible
in JOINER; this is not physical walking. Actual preserved C inputs at
17:46:51.498Z and17:47:16.900Z request crouch/stand, followed by one Space input
at17:47:26.037Z. Those times are input-call starts, not engine/network timestamps.

All426 selected HOST and424 JOINER source observations contain valid pose data.
HOST records122 Crouch1,301 Default0 and3 Jump5 observations. JOINER stays
Default0 throughout. Each process has local EntityID1, but session entities are
HOST1 and JOINER2. Equal process-local IDs must never identify a shared actor.

There are419/420 complete remote rows, no faults and maximum root readback error
0/0.000004 m. HOST observes JOINER actor10845319 and JOINER observes actual HOST
actor10844895. Twelve original frames per view, including source camera motion,
remote crouch/stand, jump flight and settled idle, were inspected. The unarmed
flight pose still spreads the arms too far and remains a quality issue.
Maximum recording gaps during the shared interval are85.9/76.9 ms. This is
actual local stationary C/Space input evidence, not sprint/WAN/terrain proof.

A private conditional clock-offset fit near the jump has nonempty12.0/4.3 ms
intervals. Sampled source/remote height peaks differ by roughly0.125 to0.142s
under that constant-offset assumption, but5 Hz sampling can miss the true peak.
This is a diagnostic observation, not precise animation/network latency or a
reason to insert an arbitrary delay. Shared source-time association still needs
the agreed typed contract; no guessed field was added.

Raw videos, frame PTS, selected source/remote rows and input journal are private
under `20261020-crouch-mask`. Settings, controls and current saves are preserved.
Lower renderer M14/action3, native assets M13 and matched native9f27bd4 remain.
KyleBuildsAI owns the auxiliary logger, focused tests and this record. Stable
v0.0.37/latest and the production backend remain unchanged.
