# Player action hook experiment

Not packaged or loaded by `runtime/session`. Do not copy into a normal install.

These hooks compiled against the installed 2.31/Codeware scripts and were called
by a private local fixture on an owned player projection on 2026-10-06. The test
did not establish a visible matching weapon or crouch animation. A queued command
is not a successful equip, posture change or multiplayer action.

Next verify actual item identity in the right-hand slot, equip command state,
posture and visual output. Bound supported weapon records and item lifetime
before exposing inventory operations to incoming state. The current experimental
method does not provide that production boundary. ADS pose, recoil and one-shot
actions have no implementation here.

See `docs/validation/PLAYER_PRESENTATION.md` and the separate typed-state proposal
in `docs/PLAYER_PRESENTATION_CONTRACT.md`. No protocol or server field was changed.
