# Private weapon-pose comparison and camera capture

KyleBuildsAI / Codex, branch `experiment/local-player-actions-20261018`, PR30.
This follows the recorded [crouch-walk correction](CROUCH_WALK_2026-10-20.md).
No production protocol/backend change, main merge, release or WAN qualification.

## Weapon pose profile

The default rifle asset recipe is unchanged. Optional
`--weapon-profile shotgundual` on both authored asset builders selects dual-barrel
shotgun ready/walk/sprint while retaining rifle shoulder-aim idle/walk. The
inspected Palica bank uses hip-fire aim, so its raw aim profile was recorded and
rejected for Igla shoulder presentation. That failed comparison is retained.
The Igla model descriptor, exact native identity, visibility guard and passive
hand-parent mount are unchanged. Other weapons remain unsupported.

Four matching private caches are required: corrected stealth, shotgun, rifle and
handgunboth. The matching body and weapon entity both reference them. Native
roundtrips, authored archive inventories and unpacked resource hashes passed.
Tests reject unknown profiles and body/graph/cache profile mismatches. Generated
owned-game cache/exports/videos remain outside Git and all public packages.

Two actual local games rendered the92s synthetic SessionClient participant.
Both mixed-profile recordings passed timing checks: HOST130s/2873 fresh frames,
JOINER145s/3264, with22.27/22.67 fresh callbacks per second. Reviewed contacts
show distinct ready and shoulder-aim holds and retain the corrected low moving
crouch, including unarmed control. This does not qualify exact finger contacts,
sight alignment, camera-directed aim, physical input or WAN behavior.
Raw shotgun comparison was130s/3165 HOST frames and145s/3581 JOINER frames,
both timing checks passed, but its aim pose was unsuitable as described above.

Current private candidate hashes:

- Action entity/graph archivee883fc37a85e5d7d655a7c7acf02eb98c351cb4763d21ccdbb5fea29593f4bbb.
- Weapon entity archive8eff915752d8340b6c08f8196c42ea136dd9f4a5ff8e62f5979707423c1807f7.
- PRIVATE four-cache archiveee83b80305e1ed037213ab8bc4a7f1d818e8c6fa1e340846a254f6758fa00a94.

Installed native DLL/server remain the matched9f27bd4 private0x8005 build.
All11 protected config/control/settings hashes matched before installation;
saves were not restored. The private capture mod adds the helper below. Stable
v0.0.37/latest is unchanged. Do not deploy these endpoints to the v5 VPS.

## Read-only camera direction

Actual in-game RTTI confirms `gameCameraSystem.GetActiveCameraForward() -> Vector4`.
A guarded live call returned camera/body(-0.316228,0.948683,0) at the staged yaw.
The private `aim_direction.lua` computes relative yaw and pitch in degrees from
validated normalized vectors, handles180-degree wrap, and rejects nonfinite,
invalid-scale and degenerate/polar-yaw inputs. CET LuaJIT and test Lua5.4 atan
entry points are handled separately. No camera/actor setters or wire fields.

Fresh private JSONL from both games contains cameraAim observations. The active
camera's ownership is not yet qualified. Optional camera failure cannot stop
essential action capture, and the existing private file bounds are retained.
Synthetic angle cases and the45-check capture regression pass. Capture is not
replicated aim, an authoritative hit direction, or visible aim rendering.

Windows experimental66/66 and default-v5 control64/64 pass. Hosted CI for this
follow-up must be checked separately;15b94fd's preceding six-job matrix passed.

## Next investigations

Check the new upper-body/crouch graph under actual scanner time dilation. The
lower locomotion renderer previously passed scanner checks, but action graph
switches and time-looped weapon clips were added later and need their own check.
Do not assume earlier lower-body evidence qualifies these new layers. Retain a
before recording, then test distance-sampled weapon gait and transition timing
if the new test reproduces a problem. Camera-driven upper-body rendering and its
compatible typed delivery remain subsequent work.

Private evidence root:
`G:\Projects\CP2077-Coop\bench-artifacts\20261020-crouch-mask`.
Use hybrid01/shotgun01 captures, contacts, replay logs, native build manifests,
`before-hybrid01/install.json`, `camera-rtti-probe.txt`, and local test logs.
## Enabled own-camera guard, 2026-10-20

The private read-only `aim_direction.fromPlayer` now requires an attached player,
an explicitly enabled FPP component and an attached component owner with the
exact same opaque native entity identity. Numeric identity adapters, zero/missing
IDs, disabled/unknown components and foreign owners fail closed. IDs are never
converted through Lua numbers, including values above2^53. Optional camera failure
continues to leave essential stance/weapon capture running.

Actual2.31 `gameFPPCameraComponent` RTTI and live calls verify `IsEnabled()` and
`GetEntity()`; the enabled component's owner matches the current player. A guessed
`entCameraComponent` type returned Unknown and was rejected, with the failed query
retained privately. No camera/scene setter was invoked. Fresh matched private
module5e0e4397 capture observed320 HOST and31 JOINER samples through the new guard,
players1/2, sourceplayer_fpp_component, at10:26:14..10:27:21Z. JOINER gameplay was
visually observed after its loading screen. These checks do not prove current-view
eligibility in every loading/menu, vehicle, scene or photo-mode situation.

Windows experimental71/71 pass, including disabled/foreign-owner and adjacent
large-ID regressions, and continued essential capture. Default-v5 control69/69 also pass. No protocol/asset/animation/network change.

Both games/server were stopped before the two private module copies changed.
Old modules and bounded capture journals were backed up. The first restart exited
with a null-read access violation before a new source log; cause is unresolved.
The one bounded retry loaded both games and captured the new module successfully.
Both attempts remain in the private evidence. Launcher reserialization changed
the settings file hash, but comparison found zero changed JSON scalar values;
current settings were preserved, with no old-save or settings restore.
