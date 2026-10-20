# Isolated crouch and upper-body pose experiment

Current crouch-walk follow-up:
[recorded correction and rejected mask experiment](../../docs/validation/CROUCH_WALK_2026-10-20.md).
`lower_crouch_walk.py` is an optional PRIVATE owned-export recipe. It lowers the
moving pelvis and solves both legs back to the original foot paths. Generated
GLB/anims/cache must stay outside Git and all public packages. Import with the
inspected71-joint rig as Anims, then apply `sanitize_native` to the native JSON
roundtrip to remove retained events/root extraction without changing pose buffers.
Use a new output, native roundtrip/inventory/hash checks, stopped-game backups and
fresh recorded visual qualification. This does not change the public runtime.

This is game-side engine work, not connected player-action synchronization.
The ordinary optional locomotion renderer remains separate and unchanged.
No protocol/server/VPS or production configuration is changed by these tools.

`build_action_fixture.py` authors a separate pure entity and graph. It selects
crouch idle/walk and masks rifle/handgun ready/aim clips onto upper-body bones
inspected in the installed 2.31 rig. Hips, legs and root are not in that mask.
Root motion, animation events, AI and gameplay commands are disabled. Native
serialization, graph/binding checks, exact archive inventory and unpacked hashes
are required. A native build alone does not prove a visible pose.

The game banks reuse names such as `walk_0` and `ovr_idle`. To avoid silently
replacing standing clips, `prepare_private_action_clips.py` retains selected
installed clips under distinct names. It preserves their compressed payloads
and checks the native roundtrip. It accepts only the inspected 2.31 rig and clip
profiles and refuses to write inside Git checkouts. **Its generated cache
contains game animation data. Never commit, upload or distribute that cache.**
Build it locally from the operator's own WolvenKit exports. Only the source
recipe and synthetic tests are shared. The authored fixture archive references
this cache but contains only our entity and graph.

`action_fixture.lua` is installed only as the private
`zz_CP2077ActionFixture/init.lua`. It accepts a fresh, bounded, exact-session
JOINER request and spawns its own separately tagged actor. Ten fixed five-second
phases exercise stance and upper-body poses, then remove that exact actor.
Asynchronous spawn ownership is retained until observed cleanup. It does not
bind to a SessionEntityId, modify a real player, transmit actions or create a
weapon. Phase names explicitly say `no_weapon`. Up to three requests per load
and 30 minutes of admission are allowed. Keep it out of all packages.

`player_capture.reds` and the private `capture_fixture.lua` read actual local
crouch, logical aim and the attached right-hand WeaponObject's exact record.
They do not apply anything. Data stays in a bounded private JSONL file. An
optional `weapon-probe/held_template.reds` reads the actual held template through
Codeware; a missing probe is unavailable rather than a guessed asset mapping.
Record identity remains native on capture, with a diagnostic string in the log.
The log is not a wire codec or proof that arbitrary locomotion states are
classified correctly. Unsupported entity/weapon/state handling needs production
capture policy before connection.

The optional `weapon-probe/components/held_components.reds` now records bounded
rig/static/skinned component metadata for the exact attached weapon. Its source
capture waits for two matching resource observations and preserves native chunk
masks as strings. Unavailable metadata cannot stop basic source-state capture.
The live template getter returned generic `base/weapons/weapon_root.ent` for
Igla, so that path must not be used as the visible model. Actual component
snapshots include per-mesh appearances and attached optics. Item appearance
lookup returned `None` in this bench even while meshes had named appearances.
Authored `isEnabled` metadata alone does not prove that every component is
currently rendered. Shadow meshes, placeholders and reload-only magazines
must not be blindly cloned into a ready/aim presentation.

After a controlled private installation and fresh game load:

```powershell
python experiments/player-locomotion/record_action_fixture.py --game-root '<JOINER game root>' --output '<new private capture folder>'
```

The runner requires a fresh in-game source sample. It records the actual window,
requests one observer placement, records per-phase submission receipts and
requires exact fixture removal. `visual_pass` stays false until frame review.
Keep CET's overlay open with its console hidden to prevent mouse rotation.
Verify the camera is clear: shared saves can load HOST at the observer location.
The observer now reads HOST's current root position and selects the other of
two fixed views if HOST occupies the first. Missing position rejects placement;
the receipt records only the submitted target, not an observed camera pose.
Do not hold a player with repeated teleports. Failed/obstructed recordings
remain evidence, not visual passes.

Initial local recordings show crouch idle/walk and distinct ready/aim upper-body
poses, including crouched combinations. Actual HOST inputs independently
produced crouch/stand, exact drawn firearm and logical aim on/off observations.
The default pose fixture has no held model. Sight alignment/pitch and
action-state delivery to a remote player remain unverified. See
`docs/validation/PLAYER_QUALITY_ACTIONS_2026-10-18.md` for the evidence boundary.

## Isolated passive Igla mount

`build_weapon_fixture.py` accepts only the qualified Igla Pimp record and its
captured component/material combination. It authors a separate pure entity
with a `WeaponRight` bone slot, three reference-pose rigs and five initially
hidden skinned parts. Each rig's authored graph maps the body's animated
WeaponRight to its inspected root bone through animation control binding.
The recorded Igla fixture now follows the hands instead of remaining at the
feet. This does not qualify finger grip, sight alignment or camera pitch/yaw.
Shadow, placeholder and reload-only parts are excluded;
unexpected attachments or material/mask/binding combinations reject the recipe.
The archive contains only our entity and three authored graphs. Installed game meshes,
rigs and the separate private action cache remain references.

The private `weapon_fixture.reds` hook checks the exact fixture template and
every named part before submitting visibility changes on the game thread.
It does not equip inventory, create a WeaponObject or run firing/AI/damage.
The fixture request accepts only `poses`, `igla` or `igla-aim`, never an arbitrary resource.
The Igla sequence exercises hidden/ready/aim/crouched/walking/hidden transitions
and exact actor cleanup. The ready/aim clips are a rifle-pose mount experiment;
native serialization and submission do not prove correct shotgun grip.

Install this hook/archive only in the controlled JOINER bench with both games
fully exited and backups recorded. Then record with:

```powershell
python experiments/player-locomotion/record_action_fixture.py --game-root '<JOINER game root>' --model igla --output '<new private capture folder>'
```

This remains an engine fixture, not a player-action transport or a release.

## Isolated upper-body aim

`build_action_fixture.py --aim-fixture --weapon-profile shotgundual` adds two
bounded model-space `Spine2` rotations after the weapon overlay. Pitch uses X
within +/-40 degrees and yaw uses Z within +/-45. Both default to zero, clamp,
and use nonincremental rotation. Pelvis, feet and entity transforms are outside
this rotation layer. This is an explicit opt-in; the ordinary graph has no aim
rotation nodes. The weapon entity is unchanged and references the same graph.

With the matched private graph installed in stopped games, the recorder accepts
`--model igla-aim`. It tests ten five-second standing/crouched, single/combined
angle phases and exact removal. Recordings show both signs of both axes moving
the hands and passive weapon. This does not qualify camera-to-sight calibration,
all torso deformation, aim delivery or actual player-input synchronization.

The read-only source diagnostic now uses the player's own FPP camera component:
`Matrix.GetDirectionVector(player:GetFPPCameraComponent():GetLocalToWorld())`.
Actual2.31 calls and matrix RTTI were verified in game. Invalid matrices or an
absent component return no angle, with no active-scene-camera fallback. Current
view eligibility in vehicles, menus, scenes and photo mode remains unqualified.
The helper never changes cameras, actors, inventory or network state.
