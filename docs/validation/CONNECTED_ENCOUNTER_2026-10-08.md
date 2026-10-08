# Connected encounter live checkpoint

Owner: KyleBuildsAI. Last recorded shot: 2026-10-08T03:41:10Z.
One Windows PC, two low-graphics clients and the local typed session server.
This is an experimental diagnostic, not a shared-combat release or a two-PC test.

**Working:** genuine JOINER firing/trace capture, authenticated reliable request
delivery, explicit HOST rejection and returned result, and controlled player
proxy placement. **Blocked:** the independent HOST ray intersects the exact
shooter proxy before the target. No HOST damage application, JOINER reaction or
JOINER death has passed this connected test.

## Source and automated validation

Trial 4 used `97d7c1a0b0fb7751800bf0fa2697769ca4e4b238` on the separate
`work/connected-combat-20261007` preparation branch. This documentation checkpoint
does not change PR #9 or PR #10. Keep PR #9's passive identity/cleanup/idle scope
separate; the connected preparation is intended for draft #10 after #9 lands.

| Source | Change | Hosted Windows, Debian, sanitizers |
| --- | --- | --- |
| `aa289044907a273a34a6819dafae36a21fc50378` | GCC 12 Release formatting fix; native text ABI unchanged | [PASS: 37720214660](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37720214660) |
| `a8b98c72d426e62e8e2df1ddcad35a402eb8e1bc` | Read-only HOST ray diagnostics; validation unchanged | [PASS: 37722033780](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37722033780) |
| `97d7c1a0b0fb7751800bf0fa2697769ca4e4b238` | Bounded exact-actor AI pose command and readback | [PASS: 37723374154](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37723374154) |

At `97d7c1a`, the local Windows Release build and **24/24 CTests** passed.
The player-pose suite includes 36 checks; the connected suite includes 206.
Isolated matched REDscript compilation passed with source/cache inputs unchanged.
Actual installed scripts then compiled on HOST at `03:32:08Z` and JOINER at
`03:33:08Z`. These checks do not substitute for the live results below.

## Observed live sequence

1. **Trial 3 isolated the stale-body failure.** The received HOST X coordinate
   updated to approximately -1641.597, but the visible proxy stayed near
   -1644.594. Network data was changing; the NPC teleport-facility operation did
   not move the actor. A shot's origin-distance squared was `43.064861`, above
   the unchanged limit of `25`. This was a game-side actuator defect.
2. **Trial 4 corrected controlled placement.** After moving JOINER approximately
   six metres, HOST's native target and exact player-2 actor `10724893` matched
   the JOINER source position. At `03:36:49Z`, native and actor readbacks were
   both `(-1647.8989257813, -2318.9399414063, 39.731163024902)`. This qualifies
   that placement, not smooth locomotion, animation or a sustained movement route.
3. **A real shot reached the next HOST check.** At `03:37:18Z`, the JOINER shot
   identified its exact controlled projection and delivered request 1 to HOST.
   HOST's sender mapping was local actor `10724893`, session entity `2`.
   Target mapping was local NPC `10724976`, session entity `4294967296`.
   Origin-distance squared `2.554573` passed. The first query hit was the
   authenticated shooter actor itself: `hitIsShooter=true`,
   `hitIsTarget=false`. HOST rejected with reason 6; routing returned that
   rejection. It did not report successful damage.
4. **The scoped collision experiment did not fix the query.** The private console
   called `NPCPuppet.DisableCollision()` only on the owned shooter-proxy instance,
   after exact tag/hash/session/controller assertions. No ambient actors or
   broad collision groups were modified. Another real shot at `03:41:10Z`
   again passed the origin check (`2.571239`) and hit actor `10724893` / entity
   `2` first. The exact-target check still rejected it. This is evidence that
   this operation did not exclude this actor from this query, not proof about
   all collision systems. The diagnostic is not enabled in production source.

The controlled HOST NPC stayed at **221.400757 health**. No acceptance check was
bypassed, no HOST damage was applied through these requests, and no accepted
damage/death result or corresponding JOINER reaction/death was observed.
The HOST weapon was holstered in later readbacks; the labelled HOST-weapon
diagnostic will also require an active ranged weapon once ray validation passes.

## Next engine-side gate

Verify a query API that excludes only the exactly authenticated shooter actor,
or a suitable passive player projection that does not block its own shot.
Retain the original finite/bounds, five-metre origin, nearest-hit, target identity
and ownership checks. Do not move the ray past an arbitrary obstruction or
accept the requested target because the first hit is inconvenient.

Then repeat a physical JOINER shot and record the full chain: request, independent
HOST acceptance, labelled HOST-weapon diagnostic application, strict causal
engine records, settled authoritative result, JOINER result validation and
visible reaction. Persistent death, duplicate/stale/failure handling, reconnect
restoration, occlusion, moving targets and two-PC testing remain separate gates.

The `CPEX1` body remains an unagreed game-side diagnostic proposal. This does not
establish production combat semantics, JOINER weapon/attacker parity, per-shot
damage attribution, death restoration after reconnect or arbitrary NPC appearance.
No public package version was created. The retained v0.0.37 / alpha.5 package is
not this test build.

Private evidence is retained under the controlled test's
`bench-artifacts/20261007-connected-combat` directory: paired trace records,
installed compiler logs, source/install hashes and launcher/restore records.
Credentials, private configuration and complete game logs are not published here.
Final machine/restoration state belongs in the test-owner handoff; it is not
inferred from these earlier successful compile and placement observations.
