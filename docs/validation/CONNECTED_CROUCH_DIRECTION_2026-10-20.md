# Connected crouch direction and distance timing

KyleBuildsAI game-side checkpoint after887fee7 on draftPR30. The same private
0x8005 local session contracts are used. No production-v5/server/VPS change.

## Correction

The previous crouch layer used forward walking in every movement direction and
advanced its clip with the standing-walk3.795m/cycle rate. Its moving frame also
reset to0 as soon as ordinary gait selected idle, before the crouch-motion fade
finished. Both are independent of correct network root position.

The existing directional experiment now additionally selects forward/backward
crouch relative to unchanged body heading, with hysteresis and80ms real-clock
weights. Measured crouch distances6.249844074m forward and3.992504835m backward
replace the standing rate for fresh crouch only. Crouch uses a separate retained
distance sample while stopping; ordinary idle progress still returns to0.

Stale/unknown stance, invalid heading, jumps, teleports and long update gaps clear
the new override. Sideways crouch keeps the forward fallback and is not qualified.
Each actor owns its own direction, weight and sample. No entity yaw/position,
weapon authority, native AI, hit collider or gameplay side effects change.

Default configuration stays off. The existing directional opt-in requires matched
new action AND weapon entity assets plus the separate private backward cache.
Ordinary action graphs and the locomotion-only renderer retain their old path.
Do not install Lua alone or mix old and new graph/cache lists.

## Validation gates

The focused crouch regression fails887fee7 and passes revision10. It covers body
axes, native stride, actual real-clock blend weights, frozen stop samples, separate
actors/default fallback, stale/invalid state and finite graph inputs. Asset tests
reject a backward clip wired to the resetting ordinary progress reader. Native
action and weapon roundtrip/inventory/unpack hashes pass. Windows experimental
72/72 and production-v5 control70/70 pass. Bounded local connected recordings are
described below; physical-input and multi-PC acceptance remain separate.

The existing local replay gains mutually exclusive `--crouch-directions`: armed
forward/stop/backward ADS, unarmed stop/forward, then the existing92s stale/repair,
hiding, disconnect/rejoin and crouch tail. It sends normal SessionClient state,
not physical keyboard input or injected packets. Its old modes remain available
for standing-direction/gait regression tests.

## Private candidate

- Action archiveca85d22b3e885bb46b327eb444ad3ba81bff68461dadf333120233368bc9bfcf.
- Weapon archive3dddc083cbdc86b4ab08e183fac263135a6d5453af824a67bf3a3598c280cf63.
- Existing separate backward cache87dce4bf, main cacheee83b803 and standing-direction
  cachecb21e90a remain unchanged. Native DLL/server stay9f27bd4/private32773.

Only authored source is publishable. Game-derived caches, owned exports and raw
videos/logs stay private. No stable/latest replacement or gameplay release.

## First normal-clock connected recording

Both actual games loaded revision10, matched new assets and fresh diagnostics.
Normal-clock connected-crouch01 completed the92s synthetic replay. HOST145s/3218
fresh frames/22.32 callbacks Hz and JOINER130s/2853/22.12Hz completed without errors.
Reviewed contacts show low armed forward walking, backward ADS, unarmed stops and
forward walking without sustained T-posing. Original captures remain unchanged.

HOST407 retained diagnostic rows and JOINER409 have no actor faults, root error
<=0.000002m, and19 stale samples each with new crouch direction/progress reset0.
Standing combat direction weight remains0 throughout236/238 crouch samples.
Backward weight reaches1 in56/57 moving-or-stopped samples respectively. Forward
stop windows have14 constant samples per view; backward stop windows14/15. The
held progress is0.480012 after forward travel and0.23142/0.231191 after backward
travel, rather than resetting to0 during the motion fade. This is diagnostic
sample constancy, not precise sub-frame timing or planted-foot-slip proof.

The first fixture route returned3m instantly at36s. That artificial source jump
is retained in the recording and not used to qualify normal movement transitions.
The updated replay's final unarmed segment goes out and back, ending at its origin
without that jump; this also exercises unarmed backward direction in the repeat.
The continuous route was used in the controlled-clock repeat below.

## Controlled clock and standing regression

At 2026-10-20T11:15Z, connected-crouch02 repeated the full92s route with HOST
clock1.0 and JOINER0.03, scanner off. HOST130s/2965 fresh frames/22.98 callbacks Hz
and JOINER145s/3439/23.85Hz finalized without capture errors. Reviewed forward,
backward ADS, unarmed backward, stops and recovery contacts show no sustained
T-pose or seconds-long crouch transition delay in the sampled views. HOST411 and
JOINER407 diagnostic rows have no actor faults and root error<=0.000002m.
Standing combat direction remains0 throughout239/236 crouch samples. Backward
weight reaches1 in71/70 samples. All19 stale samples per endpoint clear the new
crouch fields. Exact native actor bindings change on rejoin, rather than reusing
the departed actor: HOST10816948->10817006, JOINER10817117->10817118.

The gait10 standing regression then completed92s at the same measured clocks:
HOST130s/2901 frames/22.49 callbacks Hz, JOINER145s/3263/22.65Hz, no capture errors.
HOST409/JOINER407 retained rows cover idle/walk/sprint, no actor faults, root error
<=0.000002m,19 stale samples each and66 crouch samples each with standing direction
and departing-gait weight0. Original-frame transition contacts and recovery tails
were reviewed. The route leaves the camera during part of its travel, so those
intervals do not qualify visual quality. Sampled visible transitions show no
sustained T-pose; this does not prove all sprint angles, terrain or foot planting.

The private CP2077Coop.PrivateClock override was explicitly removed at
2026-10-20T11:29:46Z. The game log confirms active=false and global scale1. Both
games/server remain open, scanner off, controls/configuration/saves preserved.
Installed Lua revision20261020-locomotion-10 and matched assets are recorded in
the private install journal; native DLL/server remain9f27bd4/private32773.

Evidence stays under the private20261020-crouch-mask directory: connected-crouch01,
connected-crouch02 and gait10 captures, original-frame contacts, diagnostic copies,
metrics, install backups and hashes. Recorder visual_pass stays false because a
successful capture is not an automated quality verdict. The bounded review above
is separate. A brief standing-backward gait sample at the crouch-to-stand boundary
is retained for further timing measurement, not presented as a proven cause.

## Ownership and next work

KyleBuildsAI owns the changed game-side locomotion/passive/diagnostic Lua, authored
action graph builder, replay tool and focused tests. Existing native network
contracts, server code and default configuration are unchanged. No ownership is
transferred. Next measure action-state versus interpolated-root timing, then
continue directional/aim quality. Sideways crouch, other weapon/appearance models,
diagonal sprint and multi-PC acceptance remain open. No new gameplay release or
stable/latest package replacement is qualified by these private tests.
