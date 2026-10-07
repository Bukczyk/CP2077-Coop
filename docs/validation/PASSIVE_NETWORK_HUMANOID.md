# Passive NetworkHumanoid game-side validation

Owner: KyleBuildsAI. Session date: 2026-10-06 Pacific; work continues 2026-10-07 UTC.
Branch: `feat/passive-humanoid-validation`. Review: [PR9](https://github.com/Bukczyk/CP2077-Coop/pull/9), stacked on PR4. Status: controlled live evidence, not a gameplay release.

## Starting sources and ownership

- Upstream main: `d3670d94d96c40fe4f24e6e983d343a09f50d38f`.
- Bukczyk's passive checkpoint: `7768923d92db8c7ab0f654dc80d896994edeabbc`.
- PR4 current-main integration: `813922c217e7c97f4c5e6feb5e074930a45d84d5`.
- KyleBuildsAI owns this validation note, the static CET adapter and its tests,
  its integration in `runtime/session/cet/CP2077Coop/init.lua`, related experimental
  asset corrections, and isolated game probes. `tests/CMakeLists.txt` retains all
  inherited suites. Shared native declarations/configuration are inherited from
  Bukczyk's checkpoint; any additional bridge changes require explicit review.
- Bukczyk retains `shared/`, `SessionServer/`, wire contracts, delivery/deduplication
  and reconnect backend ownership. This branch does not implement combat packets.

## Gates

1. Build, adapter regression tests and isolated script compilation.
2. Actual entity creation, visible rendering, exact identity and movement.
3. Passive idle, owned-entity removal, reconnect and recreation.
4. Separate HOST hook probes for actual hits, damage and death.

The asset is a fixed Judy-based visual, not arbitrary NPC appearance replication.
It has no hit collider/gameplay components. Visual success alone proves neither
shootability nor shared combat. Tests below must distinguish source inspection,
mock tests, game-side fixtures, two-game checks and two-PC qualification.

NPC replication remains opt-in. Use controlled test-owned actors only; ambient
population suppression stays disabled. Preserve current saves/settings and the
public v0.0.37 / alpha.5 package. No release qualification is claimed here.

## First live run: 2026-10-07 UTC

Matched Windows plugin/server and session scripts were deployed to the private
Baseline and Test B installations. Both games ran side by side on one PC in the
low-graphics test profile. No public package was replaced. The private fixture
offers only one explicitly spawned, disposable HOST actor through the existing
NPC catalog, then runs the same static adapter on JOINER. It does not enable
ambient population suppression or implement encounter messages.

| Check | Observed result |
| --- | --- |
| Native build and offline regressions | Full Windows plugin/server build and all 16 CTests passed. Isolated session and encounter-probe compilation passed. |
| Hosted CI at `21aed14e43b9bf8aee8e1bd665e6f0ef40ad6698` | Windows, Debian and ASan/UBSan passed. |
| Visible projection | A plain `entEntity` using the fixed Judy mesh appeared in JOINER. It does not match the male HOST test actor's appearance. |
| Exact identity | First catalog entity `4294967296` bound to JOINER local `10712441`; later entity `4294967297` bound to local `10712458`. No positional actor lookup was used. |
| Movement | The same projection applied received HOST transforms. The requested scripted out-and-back movement did not establish the planned motion; real HOST reaction movement must be measured separately. Local target agreement does not measure network latency or interpolation quality. |
| Passivity | The projection stayed visible for more than 60 seconds with no independent movement decision observed. Its template contains no NPC/AI components. No claim of full AI-side-effect instrumentation is made. |
| JOINER reconnect | F7 reconnected during entity `4294967297`; its projection changed from local `10712458` to `10712461` while resolving to the same session entity. The adapter completed removal before replacement. |
| Source removal/recreation | Automatic first-run cleanup and explicit second-run cleanup emptied the JOINER catalog and owned projection set. The next source received a new session identity. The old visual disappeared. |
| Animation | FAIL: the checkpoint asset remains in T-pose. A separate minimal idle-graph investigation follows. |
| HOST damage/death fixture | A locally constructed current-weapon hit traversed vanilla damage processing; subsequent readback confirmed lower health. A later lethal fixture produced health zero, persistent death and visible collapse. |
| Shared encounter | NOT IMPLEMENTED: JOINER still displays a standing projection after HOST death. No JOINER hit request, authoritative result message, shared death animation or reconnect death tombstone was tested. |

See [engine findings](../ENCOUNTER_ENGINE_FINDINGS.md) for the six PR7 answers,
hook limitations, request-guard evidence and exact damage/death observations.
The probe's original REDscript `local=` conversion was unstable and is excluded
from identity evidence. CET's native `EntityID.hash` and session resolution were
stable. A logging-only correction reads the native field directly.

Private logs, deployment hashes, build results and restoration records are in
`bench-artifacts/20261006-shared-encounter`; these logs are not committed.
The first game's launch record is `20261007-015131-149127`.

## Revised asset trial: 2026-10-07 02:10-02:13 UTC

The original template references the general humanoid graph without gameplay
animation sets. A minimal authored graph now selects the installed game's
woman-rig-compatible `idle_stand` clip. It requests a looping idle with no root
motion, animation events, gameplay features or NPC/AI/controller component.
The archive includes only the entity and authored graph, not the game's clips.

Tested archive SHA256:
`139952bee5243c64c766744a350ab1ae1f4269aa427d20954467311e450b10b3`.
This exact archive was installed in both test copies for launch
`20261007-020640-057467`. WolvenKit conversion, packing, extraction and resource
byte parity passed. See the asset build instructions for reproducibility limits.

- The JOINER model displayed a bent-arm idle pose instead of T-pose and remained
  visible for over two minutes. Continuous playback frequency was not measured;
  this is a verified pose correction, not replicated actions or locomotion.
- Both source and projection positions stayed stationary throughout this trial;
  the scripted motion request was ineffective. This is not a movement pass.
  After reconnect, local `10712978` became `10713025`; both resolved to session entity
  `4294967296` in this new session. Reuse of that numeric value across separate
  server runs does not establish persistent identity across worlds.
- HOST's corrected REDscript ID text `10713017` matched CET's raw local ID and
  remained stable. The installed probe hash was
  `8e2cfb3140b1965cd08bdb733cda930be2a5180c5c952805c363e5ddd8f4a61a`.
- Cleanup again left zero catalog entries and an empty owned projection set
  while JOINER was still in session phase 4. Both games then closed normally.

The known appearance mismatch, missing hit target and missing shared
reaction/death presentation remain. A fixed idle pose is useful progress but
does not pass the complete shared-NPC milestone.

## Final trial and cleanup: 2026-10-07 02:19-02:24 UTC

The same archive and corrected probe were retested in launch
`20261007-021551-631272`. Four stationary-camera frames captured between
`02:19:54.248Z` and `02:19:58.005Z` showed small head and arm pose changes.
This establishes short visible local idle progression. It does not measure a
playback rate, prove a complete 4.9-second loop or synchronize HOST actions.

The directed stimulus again caused HOST combat state, and three constructed
weapon hits reduced health `221.400757 -> 112.747452 -> 0.617901 -> 0` with
persistent death. Source position stayed fixed until the lethal reaction.
That reaction changed the HOST root position by meters; the same JOINER local
entity `10712992` continued resolving to session entity `4294967296` and applied
the changed received transforms. This validates movement of the revised asset
over that limited reaction trajectory, not a walking route or interpolation
quality. The JOINER retained its idle pose after HOST death, which remains a
failed shared-life/presentation gate.

Timed source removal emptied the JOINER catalog and projection inventory.
The final reconnect key occurred after cleanup, so it does not qualify a
dead-entity reconnect or death-tombstone baseline.

Both games and the test server are closed. The original typed movement-preview
runtime, bindings and server were restored byte-for-byte from this session's
backups at `02:24:12Z`. The launcher restored graphics; all 167 current save files
were unchanged by restoration. Gameplay-created saves were preserved, not
rolled back. Experimental files and logs remain recoverable in the evidence
archive. The complete public v0.0.37 / alpha.5 package remains unchanged, with
all 69 payload hashes and its ZIP verified.

The asset-contract test initially failed because it required the old general
humanoid graph. Its updated assertions retain the no-NPC/no-AI constraints and
validate the new graph, clip binding and disabled root motion/events. All 16
local CTests then passed; Windows, Debian and sanitizers passed at source
`949c9e91df32e31e2ef4c3ccfb2479d14fadb865`. Later documentation commits change
no tested runtime bytes.

## Remaining acceptance gates

- Sustained/multiple-entity animation qualification and accepted HOST-driven
  movement/action/death poses.
- A supported hit representation and real JOINER intent capture for the plain entity.
- Arbitrary HOST appearance matching; the fixed Judy asset is only a visual fixture.
- Bukczyk's reviewed encounter message implementation and game-thread delivery.
- Connected stimulus, damage, death, duplicates, rejected requests, overload and
  alive/dead reconnect tests. Local fixture guards are not network deduplication.
- Separate two-PC qualification, latency/interpolation measurement and larger
  live groups. Two windows and headless group tests do not establish live capacity.
