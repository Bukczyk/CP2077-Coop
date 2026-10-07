# Networking work worth preserving from KyleBuildsAI

This is KyleBuildsAI's request for Bukczyk to review selected networking work from [KyleBuildsAI/cp2077-coop](https://github.com/KyleBuildsAI/cp2077-coop). The aim is to save time by adapting useful existing work into **Bukczyk/CP2077-Coop**, while keeping its session architecture and typed protocol.

This PR adds a proposal, not networking changes. It complements [PR #2: game-side integration](https://github.com/Bukczyk/CP2077-Coop/pull/2) and [PR #1: shared goals and responsibilities](https://github.com/Bukczyk/CP2077-Coop/pull/1). Merging these documents does not merge the implementation from the other repository.

## Recommendation

Start with the poor-connection test scenarios and network measurements. Use them to compare the current timing with KyleBuildsAI's clock synchronization and adaptive movement buffering. Preserve the authority failure tests for the upcoming gameplay-event work. Consider compression and more detailed relevance rules after the first shared NPC milestone.

These are source-confirmed capabilities and reuse candidates. A smoother or faster result in this session architecture still needs measurement. Keep useful existing code, tests and research with their source history; do not rebuild them without first checking whether adaptation is simpler.

## 1. Poor-connection tests: adapt first

**Existing work:** KyleBuildsAI's [LinkSim][k-linksim] adds controlled delay, jitter, packet loss and duplicates, with reproducible random seeds. The [authority UDP test][k-udp-test] uses actual sockets, 12% configured loss and 10% duplication, then exercises reconnects and rejection of approvals from the old connection.

**What this project already has:** [session socket tests][b-network-tests] cover admission, stale state, reconnects, interest filtering and 16 headless members. [NPC tests][b-npc-tests] cover catalog recovery and interest handling. Preserve these. The reviewed suites do not provide the equivalent configurable impaired-link coverage.

**Request:** adapt the impairment scenarios around this project's TCP/UDP transport. Reuse the test ideas and simulator where suitable, not the old packet format or server. TCP needs slow-reader, delayed-delivery and connection-break tests; dropping application messages after TCP delivery is not a valid simulation of TCP packet loss.

**Pass condition:** use a HOST and at least two JOINERs under named, repeatable impairment profiles. Players can join and recover; old state and old epochs cannot overwrite newer state; reconnect restores the current NPC catalog; queues remain bounded; an unavailable connection fails explicitly. Preserve authentication and source-address checks in the harness. Report configured and observed drops/duplicates, recovery time and failures, not just a successful connection.

## 2. Clock synchronization and adaptive movement buffering: compare next

**Existing work:** [ClockSync][k-clock] estimates the client/relay clock offset from timestamp exchanges, handles drift and clock changes, and is covered by [clock tests][k-clock-tests]. [SnapshotBuffer][k-buffer] adjusts playback delay to measured delivery variation. Both have C++ implementations already, and are used by the [native transport][k-transport].

**Current difference:** the [session client][b-client] gives its interpolation buffer local arrival time plus the sender's sample timestamp. The [buffer][b-buffer] uses arrival time for spacing and a configured fixed delay; sender time rejects stale samples. Several samples processed with the same arrival time replace one another. This can discard their original spacing when packets arrive in a burst.

**Request:** compare a shared-timeline, adaptive-buffer approach against the current receiver under identical profiles. Preserve entity identities, ownership, sequence checks and bounded extrapolation. Define the clock domain for every sender, including JOINER poses forwarded through the HOST. Do not compare unsynchronized client clocks directly.

**Pass condition:** measure displayed position error, playback delay, freezes and corrections on the same recorded movement. Cover burst delivery, asymmetric delay, clock drift, reconnect and long pauses. Do not accept fewer visible jumps if the only improvement is substantially more delay. Clock synchronization cannot remove network travel time or fix an engine animation bug.

**Compatibility:** KyleBuildsAI's timing code uses its old protocol structures, 32-bit wire timestamps and degree-based yaw helpers. This project uses different types, 64-bit sample timestamps and radian rotations. Adapt the algorithm and relevant tests; do not drop in its old codec, IDs or angle handling.

## 3. Network measurements: include with the first task

**Existing work:** [transport diagnostics][k-transport] expose clock uncertainty, connection timing, loss estimates, traffic volume, waiting reliable messages and whether movement was interpolated, extrapolated or held.

**Current difference:** [ClientStats][b-client-header] exposes sent, received, stale and rejected counts. These are useful but do not explain whether a visible pause came from late delivery, a full queue, an empty movement buffer or the engine.

**Request:** add the measurements needed for the comparison above. Label client-to-server round-trip time separately from estimated player-to-player delay. Do not transplant reliable-UDP retry counters as TCP retransmission measurements. Account for intentional interest filtering before interpreting sequence gaps as packet loss.

**Pass condition:** a test report ties measurements to the exact source revision, configuration, connection and session generation. Show unavailable measurements as unavailable. Bukczyk owns measurement collection and any new bridge fields; KyleBuildsAI owns the in-game display and comparison with the actual rendered actor.

## 4. Authority failure cases: preserve for gameplay events

**Existing work:** [authority tests][k-authority-tests] cover competing seat requests, expired approvals, repeated requests, reconnect generations and a world baseline changing while someone joins. The [relay overflow test][k-overflow-tests] checks that a full outgoing queue cannot falsely report an uncommitted action as successful.

This experiment already builds on ideas from Bukczyk's earlier session policy, as recorded in its [provenance and limitations][k-authority-notes]. Its additional test cases are useful to bring back into the shared project.

**What this project already has:** [session policy][b-policy] validates ownership, epochs and event order, and the [game inbox tests][b-bridge-tests] check authority, stale events and overflow. The general [gameplay submission API][b-bridge] still returns Unsupported; the full hit/reaction route is not established by those local contracts.

**Request:** adapt the extra scenarios when implementing seats, hits and other accepted gameplay results. Specify request identity, expiration, repeat handling and recovery after reconnect. Decide explicitly whether queue failure rejects the action or disconnects the slow receiver and restores its state later. Do not silently report a result as delivered or applied when only a request was queued.

**Pass condition:** two players cannot own the same seat; one accepted hit cannot apply damage twice; an old approval cannot affect a new connection or world; queue failure has an explicit recovery path. Seat and hit tests must eventually verify the actual engine result as well as the network state.

The current KyleBuildsAI seat experiment is headless metadata only. It does not mount players or prove shared vehicle physics. Reuse its tests and decisions, not a second authority service or its experimental text messages.

## 5. Compression and relevance: keep as later candidates

**Existing work:** [entity snapshot code][k-snapshots] and its [tests][k-snapshot-tests] include changes sent against acknowledged baselines, update priorities and a margin that prevents entities repeatedly entering/leaving relevance at a distance boundary. A [C++ delta implementation][k-delta] also exists. These are component-level references, not proof of a completed shared-world game integration.

**What this project already has:** [server routing][b-server] already filters by distance and lowers distant update rates. Preserve that working foundation.

**Request:** if measured entity counts or bandwidth justify it, evaluate the additional techniques. Keep the server-issued SessionEntityId; do not import the old world-ID scheme or entity-number widths. Coordinate relevance decisions with the game adapter so network filtering and visible NPC creation do not fight each other.

**Pass condition:** lower bytes per second for the same useful state, recovery after a missing baseline or session reset, no permanently starved entity updates, and stable behavior at relevance boundaries. Verify the final packet-size limit for mass removals as well as updates: the reference encoder collects removal records before its per-update size checks, so its configured size target is not proof of a universal limit. This work should not delay the first shared NPC reaction.

## First proposed implementation and work split

**First network task for Bukczyk to consider:** extend the existing real-socket tests with impaired UDP links, stalled/broken TCP control connections and the measurements needed to compare timing. Keep production timing behavior unchanged for that initial test-only task.

Suggested starting files are `tests/network_e2e_tests.cpp`, `tests/npc_tests.cpp`, `tests/net_tests.cpp` and a new test-only impairment helper under `tests/`. Update `tests/CMakeLists.txt` only if another test target is needed. These are candidate files, not an active claim on Bukczyk's work. Record the exact chosen paths before starting.

After that baseline exists, a separate timing task can consider `shared/src/client.cpp`, `shared/src/interpolation.cpp` and their matching headers/tests. A new clock exchange would also require Bukczyk's protocol/server work. Do not hide it inside movement fields.

- **Bukczyk:** networking, session/server behavior, typed messages, identity/ownership, reconnect, authority and network measurements.
- **KyleBuildsAI:** engine integration, player presentation, map/UI, vehicle/seat engine hooks and live-game measurements.
- **Both:** agree on shared data meanings and the combined test when a feature crosses the boundary. Use existing calls where possible; work in agreed, unoccupied areas can continue while the other person is offline.

Keep earlier useful work as linked references and integrate it through small feature PRs. Each PR should state which existing component it adapts, what changed for compatibility, and which tests prove the result. Do not replace either maintainer's ongoing work or interpret this proposal as a completed port.

## Review record

- Prepared 2026-10-05, America/Los_Angeles. UTC handoff: `2026-10-06T04:13:24Z`.
- KyleBuildsAI source: `67f33612f5f4d1833438858a86cbeda8fda5f7d2`.
- Bukczyk main: `7e3826d1c313595a4784f1b232e10cec222b6ca3`.
- This PR owns only `docs/NETWORK_REUSE_PROPOSAL.md`; it does not edit the files in PR #1 or PR #2.
- Evidence is source/test inspection. No new runtime test, gameplay run, deployment, package change or implementation benchmark is claimed.
- KyleBuildsAI requested publication. Bukczyk's acceptance and ownership of a specific implementation task are not assumed.

[k-linksim]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/coopnet/linksim.py
[k-udp-test]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/tests/test_authority_udp.py
[k-clock]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/plugin/src/v2/ClockSync.cpp
[k-clock-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/plugin/tests/V2ClockTests.cpp
[k-buffer]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/plugin/src/v2/SnapshotBuffer.cpp
[k-transport]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/plugin/src/core/Transport.cpp
[k-authority-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/tests/test_authority.py
[k-overflow-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/tests/test_authority_relay.py
[k-authority-notes]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/docs/AUTHORITY_EXPERIMENT.md
[k-snapshots]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/coopnet/snapshot.py
[k-snapshot-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/tests/test_snapshot.py
[k-delta]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/plugin/src/v2/V2Delta.cpp
[b-network-tests]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/tests/network_e2e_tests.cpp
[b-npc-tests]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/tests/npc_tests.cpp
[b-client]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/shared/src/client.cpp
[b-buffer]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/shared/src/interpolation.cpp
[b-client-header]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/shared/include/coop/client.hpp
[b-policy]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/shared/src/session.cpp
[b-bridge-tests]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/tests/game_bridge_tests.cpp
[b-bridge]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/shared/include/coop/game_bridge.hpp
[b-server]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/shared/src/server.cpp
