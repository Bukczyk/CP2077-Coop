# Bring KyleBuildsAI's game-side work into the shared project

This is a proposal from KyleBuildsAI for Bukczyk to review. It identifies useful work from [KyleBuildsAI/cp2077-coop](https://github.com/KyleBuildsAI/cp2077-coop) and explains how to adapt it to **Bukczyk/CP2077-Coop**. This PR adds the plan only. It does not add these features to the running game.

Keep Bukczyk's session and networking foundation. Bring over selected game integration, presentation, testing and packaging work. Do not copy the old two-player runtime as a replacement for the new system.

The proposed work split is described in [collaboration PR #1](https://github.com/Bukczyk/CP2077-Coop/pull/1): KyleBuildsAI handles the game side; Bukczyk handles networking, session identity and world authority. This plan adds concrete reuse candidates and a small first task.

## What is worth bringing over

### 1. Safer NPC creation and cleanup - first task

KyleBuildsAI's controlled NPC test checks where the actor actually appeared, waits for the exact old actor to disappear before replacing it, and limits unfinished movement commands. These safeguards address cases where an engine call succeeds but the visible result is not ready yet.

Bukczyk already keeps the exact engine ID returned by creation, waits for asynchronous spawning, and reconnects projections to their session IDs. Keep that work. Add measured placement and confirmed cleanup around it. The current adapter clears its tracking when the deletion request succeeds; it does not wait to observe actual disappearance.

Sources: [engine helpers][k-npc-engine], [lifecycle checks][k-npc-lifecycle], [regression tests][k-npc-tests]. Destination: [current NPC adapter][b-npc-adapter] and [lifecycle controller][b-npc-runtime]. Details of the first task are below.

### 2. More reliable remote-player spawning and recovery

Reuse the checks for delayed attachment, incorrect initial placement, detached player models and streaming distance. These can help a remote player appear reliably and recover when the local display model is lost.

Adapt the checks separately for every player ID. Replacing a missing display model must never override the HOST's gameplay death state. Bukczyk already has per-player spawning; this proposal strengthens its engine recovery behavior.

Sources: [player engine helpers][k-remote], [game controller][k-init], [avatar tests][k-avatar-tests]. Destination: [session game controller][b-init] and [player engine helpers][b-remote].

### 3. Pause and menu handling

Reuse the game pause/menu detection so a paused game does not count as a failed spawn or trigger repeated movement corrections. The current session controller checks player attachment and the pregame state, but does not have the same pause/menu handling.

KyleBuildsAI owns the engine detection and local timers. Bukczyk owns any session timeout or network policy change. Pausing local presentation must not silently stop network service for the other players.

Sources: `Sync.frozenReason` and `Sync.updateFrozen` in the [game controller][k-init], plus [live-bug regression tests][k-live-tests].

### 4. Map and minimap player markers

Bring over the marker that follows fresh received player positions, with stale-marker cleanup and retry handling. The active session runtime does not currently contain this marker feature. Adapt the single-partner implementation into one marker per player ID, and remove the right marker when that player leaves.

The existing marker is a waypoint-style pin. A recognizable player icon and a facing arrow are still feature requests, not completed work. Preserve the player's own navigation waypoint.

Sources: [marker engine helpers][k-marker], [game controller][k-init], [marker tests][k-marker-tests].

### 5. Crouching and weapon presentation

Reuse the game helpers for remote crouching, drawing/holstering, and supported weapon-category props. Bukczyk's active player bridge currently applies transforms; it does not yet apply these presentation states.

KyleBuildsAI handles the visible result. Bukczyk owns any new typed network fields needed to carry it. Detecting that someone is aiming is not the same as showing an aiming-down-sights animation. Full appearance, exact loadouts and aiming animations remain separate work.

Sources: [state and presentation helpers][k-state], [state regression tests][k-state-tests]. Do not copy the old encoding of gameplay flags into movement fields.

### 6. Measurements and game regression tools

Bring over the tools that record the received position, requested position and actual actor position separately. They help tell network delay apart from engine movement problems. Reuse frame-rate, correction and round-trip-time measurements where the new APIs supply them, plus isolated REDscript compilation checks.

Bukczyk already has automated networking and bridge tests. Add game-side evidence to those tests. Adapt logs for multiple players and session resets. Existing prototype test results do not prove the new integration works; sprint smoothing and experimental steering still need measurement.

Sources: [steering trace guide][k-trace], [trace summarizer][k-summarizer], [isolated script compilation setup][k-sandbox].

### 7. Complete installation packages

Reuse the complete-package manifest, file-hash checks and release checklist. Extend Bukczyk's existing matched HOST/JOINER packaging, which already produces matching plugin/scripts/configuration and hashes.

A future install ZIP must contain compatible versions of the new runtime and its required dependencies, with a clear rollback procedure. Keep private session keys out of public releases. Do not mix the v0.0.37 plugin with the typed session scripts.

Sources: [complete package builder][k-package], [release workflow][k-release]. Existing destination: [session package builder][b-package].

## First implementation task: prove one NPC's local lifecycle is safe

**Player-visible result:** the JOINER creates the correct network-owned NPC, places it where the HOST says, and removes it cleanly without leaving a duplicate behind.

This is one prerequisite for the shared NPC reaction milestone. It does not finish passive AI, hit forwarding, damage or death synchronization.

### Proposed file ownership

For this small follow-up code PR, KyleBuildsAI would work only in:

- `runtime/session/cet/CP2077Coop/npc_population.lua`: local creation, observed placement and confirmed deletion.
- `runtime/session/cet/CP2077Coop/npc_runtime.lua`: pending-operation handling and cleanup during session changes.
- `tests/npc_population_tests.lua`: regression cases for those engine-facing behaviors.
- `runtime/session/README.md`: the actual validation result and remaining limitations.

These are proposed files, not an active runtime claim. Before starting, check current main, open PRs and the latest handoff for overlapping edits. If Bukczyk is changing the same adapter for passive humanoids, keep this task separate until the file ownership is settled; measurements and isolated research can continue.

The existing calls are already available: `spawn`, `bind`, `move`, `unbind` and `remove`, together with `CP2077Session_Bind` and `CP2077Session_Unbind`. Start from these calls and their tests. No request for Bukczyk to look up file names is needed.

### Required behavior

1. Keep the exact engine EntityID tied to the server's SessionEntityId. Never identify an NPC by nearby coordinates or a shared tag.
2. Treat creation, visible placement and deletion as separate stages that can take time. Keep ID binding distinct from a local "ready" result if binding is needed before movement can be applied.
3. Measure the actual actor pose before declaring placement ready. Set explicit tolerances and deadlines in the code and tests; do not treat a successful API call as proof of placement.
4. Keep tracking a deletion request until the exact owned actor is confirmed gone. Block replacement for that projection while cleanup is pending. A deadline reports failure; it must not discard ownership tracking and allow a duplicate.
5. Reject stale work after a session reset or reconnect. Keep all engine object access on the game thread, and preserve opaque 64-bit IDs.
6. Adapt the safeguards, not the old test protocol or single-actor controller. The prototype's AI teleport commands require an AI controller; do not assume they work for a render-only humanoid. Disabling senses alone does not establish passive AI.

### How to check it

Automated checks must cover delayed creation, wrong initial placement, deletion that is accepted before the actor disappears, repeated frames, two NPCs at identical coordinates, and reconnect while creation or cleanup is pending. They must prove that retries remain bounded, IDs stay distinct, no replacement overlaps its old actor, and unrelated ambient NPCs are untouched.

Then record a controlled HOST/JOINER test on matching builds, subject to the existing NPC authority gate in [the runtime notes][b-runtime-notes]. Capture both views and log session ID, NPC ID, local actor ID, target pose, observed pose and cleanup result. A mocked test is not evidence of game behavior. Do not enable shared combat or call the NPC passive until that separate engine problem is verified.

## Following tasks and boundaries

After the lifecycle task, prioritize player recovery, pause handling and measurements around the first shared NPC milestone. Map markers are an independent game-side task when their files are free. Crouch/weapon presentation needs agreed typed state fields. Complete packaging follows a verified matching runtime.

Vehicle matching, shared seats, a facing-arrow icon, full aiming animations and time/weather synchronization belong in later tasks. KyleBuildsAI has useful experiments and helpers, but these must not be presented as finished ports.

For Bukczyk to consider separately: the [clock-sync implementation][k-clock] and [real-socket delay/loss/duplication tests][k-network-tests] may provide useful ideas or test cases. The current session system already has interpolation and socket tests. Evaluate these against measured problems; this plan does not replace the new networking stack or assign networking edits to KyleBuildsAI.

Work should continue in small branches and PRs against this repository. Use existing interfaces where possible. If a new shared field or call is necessary, record its meaning and the combined test before either side builds a conflicting version. Leave a UTC handoff with the exact files changed, evidence and next action. Nobody needs to wait for a reply to inspect existing code or do work within an already agreed, unoccupied area.

## Review baseline and handoff

- Prepared on 2026-10-05 (America/Los_Angeles). UTC handoff: 2026-10-06T03:56:05Z.
- KyleBuildsAI source reviewed: `67f33612f5f4d1833438858a86cbeda8fda5f7d2`. The v0.0.37 / alpha.5 prototype has earlier live-test evidence; this document reports no new game run.
- Bukczyk main reviewed: `7e3826d1c313595a4784f1b232e10cec222b6ca3`. The comparison targets `runtime/session`, not the frozen legacy runtime.
- This PR owns only `docs/KYLEBUILDSAI_INTEGRATION_PLAN.md`. It is independent of the files in PR #1.
- Next review decision: which reuse candidates to accept and whether the proposed NPC adapter files are free for KyleBuildsAI's first code task. Publication does not imply Bukczyk has accepted the plan.
- Existing runtime/package remains unchanged until a separately verified cutover. No features are marked integrated by this documentation PR.

[k-npc-engine]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/r6/scripts/CP2077Coop/testnpc.reds
[k-npc-lifecycle]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop/testnpc.lua
[k-npc-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/test_npc_test.py
[k-remote]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/r6/scripts/CP2077Coop/remote.reds
[k-init]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop/init.lua
[k-avatar-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/test_avatar.py
[k-live-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/test_live_bugs.py
[k-marker]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/r6/scripts/CP2077Coop/marker.reds
[k-marker-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/test_marker.py
[k-state]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/r6/scripts/CP2077Coop/state.reds
[k-state-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/test_state_sync.py
[k-trace]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/STEERING_TRACE.md
[k-summarizer]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/coop-tools/steering_summarize.py
[k-sandbox]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/tests/make_sandbox.py
[k-package]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/scripts/package_game_files.py
[k-release]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/docs/RELEASE_WORKFLOW.md
[k-clock]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/plugin/src/v2/ClockSync.cpp
[k-network-tests]: https://github.com/KyleBuildsAI/cp2077-coop/blob/67f33612f5f4d1833438858a86cbeda8fda5f7d2/relay/tests/test_authority_udp.py
[b-npc-adapter]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/runtime/session/cet/CP2077Coop/npc_population.lua
[b-npc-runtime]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/runtime/session/cet/CP2077Coop/npc_runtime.lua
[b-init]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/runtime/session/cet/CP2077Coop/init.lua
[b-remote]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/runtime/session/redscript/CP2077Coop/remote.reds
[b-package]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/scripts/package-session.ps1
[b-runtime-notes]: https://github.com/Bukczyk/CP2077-Coop/blob/7e3826d1c313595a4784f1b232e10cec222b6ca3/runtime/session/README.md
