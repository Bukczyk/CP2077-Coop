# Connected encounter live checkpoint

Owner: KyleBuildsAI. Last connected shot: 2026-10-08T04:13:09Z.
Same-body death display observed at 04:14:39Z; subsequent reload is a separate failed recovery test.
One Windows PC, two low-graphics clients and the local typed session server.
This is an experimental diagnostic, not a shared-combat release or a two-PC test.

**Controlled pass:** genuine JOINER firing/trace capture, authenticated request,
independent HOST ray acceptance, labelled HOST-current-weapon engine application,
correlated observed health loss/persistent death, returned authoritative outcomes,
and the same JOINER NPC's reaction/death presentation. This used an explicitly
opt-in passive cosmetic player to avoid the earlier shooter-proxy ray obstruction.

**Still incomplete:** JOINER weapon/attacker parity, production combat semantics,
actual native bullet collision, PvP, general NPC/world behavior and two-PC testing.
Death did not recover after quickload/reconnect. F9 also triggered native quickload,
so the attempted local recreation is not a visual-recreation pass. Earlier failed
trials remain below and in the private evidence archive.

## Source and automated validation

Trial 4 used `97d7c1a0b0fb7751800bf0fa2697769ca4e4b238`. Trial 5 used
`481609a57ccf775657818fe059f6b87652836ef3`, including the default-off passive
player implementation `84166374849f1c7f512fb0e2cb87f165305318dc`, on separate
`work/connected-combat-20261007`. This documentation checkpoint
does not change PR #9 or PR #10. Keep PR #9's passive identity/cleanup/idle scope
separate; the connected preparation is intended for draft #10 after #9 lands.

| Source | Change | Hosted Windows, Debian, sanitizers |
| --- | --- | --- |
| `aa289044907a273a34a6819dafae36a21fc50378` | GCC 12 Release formatting fix; native text ABI unchanged | [PASS: 37720214660](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37720214660) |
| `a8b98c72d426e62e8e2df1ddcad35a402eb8e1bc` | Read-only HOST ray diagnostics; validation unchanged | [PASS: 37722033780](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37722033780) |
| `97d7c1a0b0fb7751800bf0fa2697769ca4e4b238` | Bounded exact-actor AI pose command and readback | [PASS: 37723374154](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37723374154) |
| `481609a57ccf775657818fe059f6b87652836ef3` | Opt-in passive cosmetic players; local-runner documentation correction | [PASS: 37725557131](https://github.com/Bukczyk/CP2077-Coop/actions/runs/37725557131) |

At `97d7c1a`, the local Windows Release build and **24/24 CTests** passed.
The player-pose suite includes 36 checks; the connected suite includes 206.
Isolated matched REDscript compilation passed with source/cache inputs unchanged.
Actual installed scripts then compiled on HOST at `03:32:08Z` and JOINER at
`03:33:08Z`. These checks do not substitute for the live results below.

The opt-in adapter has 108 modeled identity/lifecycle checks. Their opaque ID
mocks are not native game-object evidence. See [passive player validation](PASSIVE_PLAYER.md)
for the experiment's scope, default-off flag and runtime observations.

## Earlier failed trials

Trials 1 and 2 are retained under `trial01-loader-failure` and
`trial02-ray-rejected`: failed harness loading and a returned HOST ray rejection,
respectively. Neither is a connected damage/death pass.

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

In trials 3 and 4 the controlled HOST NPC stayed at **221.400757 health**. No acceptance check was
bypassed, no HOST damage was applied through these requests, and no accepted
damage/death result or corresponding JOINER reaction/death was observed.
The HOST weapon was holstered in later readbacks; the labelled HOST-weapon
diagnostic will also require an active ranged weapon once ray validation passes.

## Trial 5: connected controlled encounter

The first JOINER process attempted admission before HOST had created the session
and received `MissingSession` (reason 4). Its scoped transport fault remained
latched in the private diagnostic. That process was closed and replaced; its
failed startup logs are preserved separately in `trial05-startup-admission`.
No shot or damage was recorded during that admission failure.

The replacement joined active scope `1:1:1`. Private configuration explicitly
enabled passive players; the shipped setting remains false. HOST's authenticated
sender was passive actor `10727407`, player/session entity `2`. Controlled HOST
NPC `10727535` and JOINER projection `10726764` both mapped to session entity
`4294967296`. They are exact registry mappings, not coordinate matches.

| UTC | Request and observation | Accepted result |
| --- | --- | --- |
| 04:12:22 | Genuine JOINER firing sequence 2, adjacent exact-target trace, request 1. HOST origin-distance squared `2.554886` and the unchanged first-hit target check pass; the ray does not hit the shooter. | HOST fixture 1 observes health `221.400757 -> 159.715378`. HOST event 2 returns alive `159.715378`; JOINER accepts reaction serial 1, progresses from 0 to about 0.8766, then returns idle at 04:12:23. The test owner also observed a transient pose change. |
| 04:13:09 | Genuine JOINER firing sequence 3, exact-target request 2 and independent HOST ray acceptance. | HOST fixture 2 first observes health `56.263500`, then 0 and persistent Dead. Settled HOST event 3 returns dead/0; the same JOINER actor accepts death serial 2 and progresses 0 to 1 over about 1.98 seconds. |

Fixture 1's engine sequence was 3781 queued, 3782 candidate, 3783 preprocess,
3784 deal and 3785 observed health change. Scope and fixture serial matched;
engine records marked `syntheticFixture=true` and `projectionPipeline=false`.
The Lua observer then reported `correlated=true` and `ambiguous=false`. These
are a labelled HOST-weapon diagnostic, not evidence
that the remote weapon/attacker was reproduced.

Fixture 2's engine sequence was 4505 queued, 4506 candidate, 4507 preprocess,
4508 deal, then 4509 health `56.263500`. Death callback 4511 reported health 0
while dead was still false; `on_died_after_vanilla` 4512 and later readbacks
confirmed persistent Dead. Waiting for the latter distinction is material:
queue acknowledgement or the early callback alone would not prove death.
The result carries observed terminal state, not a damage amount attributed to a
single shot. It does not establish attacker credit or exact weapon parity.

The JOINER death trace contained 34 accepted pose updates and zero queue errors.
The NPC's root had moved to approximately `(-1654.523682, -2309.015137, 39.503105)`.
After aligning the view to that current position, the test owner observed its
collapsed body at 04:14:39Z. This combines a completed same-body death transition
with a visual observation; it is stronger than queue acceptance alone. It does
not qualify arbitrary NPC rigs, hit-location reactions or ragdoll physics.

## Failed recreation/reconnect recovery

At 04:14:45Z, F9 created replacement local actor `10727611` and queued terminal
death, but the same key also invoked Cyberpunk's `QuickLoad_Button`. The visual
recreation outcome was not observed before reload. This repeats an already
recorded input conflict; it must not be presented as successful corpse recreation.

After reload, the JOINER had scope `1:1:2`, PlayerId 3 and local NPC projection
`10727376`. The catalog restored session NPC `4294967296`, but the projection was
idle/dead=false at 04:14:57Z. The terminal gameplay state was not recovered across
the new generation. This is the known accepted-state restoration gap, not evidence
that reconnect replays death correctly.

F9 is reserved for native quickload and must not be used for the recreation
fixture. Before a future run, check game input mappings and every active CET
binding and choose an unused key. The private runner's replacement choice is F7;
its new mapping is separate preparation, not proof of a completed recreation test.

## Next acceptance gates

1. Repeat local corpse recreation using the preflighted key, without save reload;
   observe old-body disappearance and the replacement's visible terminal pose.
2. Agree and implement accepted death/life restoration for reconnect, late join
   and interest return, then prove a new local projection remains dead.
3. Repeat controlled misses, world occlusion, moving targets, stale/duplicate
   requests, overload and transport failure in game. Automated coverage alone
   does not qualify those live cases.
4. Replace the HOST-current-weapon diagnostic with agreed trustworthy JOINER
   weapon/attacker semantics, without relaxing independent validation.
5. Validate sustained player presentation, supported NPC reactions and the full
   encounter on two PCs before extending the claim to general shared combat.

The `CPEX1` body remains an unagreed game-side diagnostic proposal. This does not
establish production combat semantics, JOINER weapon/attacker parity, per-shot
damage attribution, death restoration after reconnect or arbitrary NPC appearance.
No public package version was created. The retained v0.0.37 / alpha.5 package is
not this test build.

## Cleanup and retained evidence

HOST source `10727535` was observed gone at 04:16:08Z. JOINER unbinding succeeded;
its asynchronous removal first remained pending and then completed, with later
projection lists empty. Test-owned games and the local server were closed.
The launcher recorded graphics/settings restoration at
`2026-10-08T04:18:05.199462Z`.

The complete trial archive contains 29 copied, hash-verified files, with zero
missing files or trace parse errors, captured after reported game exit at
04:19:54Z. The independent audit is in
`bench-artifacts/20261007-connected-combat/trial05-passive-connected-success/analysis.json`.
Earlier failed trials and the failed first JOINER admission remain separate.

Final runtime restoration passed at `20261008T0420284501917Z`: original matched
typed runtime, input bindings and server bytes were hash-verified. The experimental
runtime was archived separately as `restored-experiment-20261008T0420284501917Z`.
Current saves were preserved and their hashes stayed unchanged during restoration;
no save rollback was performed. Exact proof is the private
`runtime-restore-20261008T0420284501917Z.json` record in that evidence directory.
No games or test server were left open.

Private paired traces, compiler records and source/install hashes are retained
locally. Credentials, private configuration and complete game logs are not
published here. Public v0.0.37 / alpha.5 package bytes remain unchanged.
