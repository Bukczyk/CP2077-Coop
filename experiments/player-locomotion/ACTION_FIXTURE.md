# Isolated crouch and upper-body pose experiment

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

After a controlled private installation and fresh game load:

```powershell
python experiments/player-locomotion/record_action_fixture.py --game-root '<JOINER game root>' --output '<new private capture folder>'
```

The runner requires a fresh in-game source sample. It records the actual window,
requests one observer placement, records per-phase submission receipts and
requires exact fixture removal. `visual_pass` stays false until frame review.
Keep CET's overlay open with its console hidden to prevent mouse rotation.
Verify the camera is clear: shared saves can load HOST at the observer location.
A single explicit staging move can clear it; do not hold a player with repeated
teleports. Failed/obstructed recordings remain evidence, not visual passes.

Initial local recordings show crouch idle/walk and distinct ready/aim upper-body
poses, including crouched combinations. Actual HOST inputs independently
produced crouch/stand, exact drawn firearm and logical aim on/off observations.
There is still no held model on the fixture, sight alignment/pitch proof or
action-state delivery to a remote player. Those are the next gates. See
`docs/validation/PLAYER_QUALITY_ACTIONS_2026-10-18.md` for the evidence boundary.
