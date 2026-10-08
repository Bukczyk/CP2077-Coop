# PR #10 update onto main

Owner: KyleBuildsAI. Task: bring the validated connected-combat preparation
into PR #10 after Bukczyk merged PR #9. Bukczyk retains session/server/protocol
ownership. This update changes history and review documentation, not the
validated engine behavior or shared networking contracts.

## Revisions and preservation

- PR #9 merged at 2026-10-08T08:17:09Z; main is
  `61eb2c5b3efb9f9fb352c52e6a7dab07d69222a3`.
- Previous PR #10 head: `3aecdc114aee3762f812635bf5ad07793ac3d571`.
- Preparation retained publicly on `work/connected-combat-20261007` at
  `0a8103e316d1994d6be05123fd81d599b8de5bb1`.
- Rebased preparation: `70bd15143685250cf8bafcb3d0a143465c152496`.
- Rebase completed without conflicts. The complete rebased tree is byte-identical
  to the preparation, tree `73854089f05c491f7e66b4c957e2b66f968aba22`.
- Range-diff preserves all ten engine/preparation commits unchanged. PR #11's
  networking commits are already on main and are not replayed into the PR.
- The final review checkpoint adds only Markdown documentation to that tree.
  Source files, tests, default-off flags and asset inputs retain their validated bytes.

The retained path is JOINER firing/target query -> reliable request -> independent
HOST target validation -> HOST-current-weapon fixture -> observed authoritative
health/death result -> JOINER reaction/death presentation. No origin, nearest-hit
or exact-identity validation was weakened. Passive cosmetic players stay opt-in.

## Fresh validation

- Windows Release plugin/server build passed on the rebased source.
- All 25 CTests passed, including real-socket gameplay bridge, connected
  encounter, player pose, passive-player lifecycle and asset contract suites.
- Matched session and experiment REDscripts compiled in an isolated sandbox at
  2026-10-08T10:47:18Z. Compiler/runtime inputs stayed unchanged; no game installed.
- Complete-tree equality, range-diff and `git diff --check` passed.
- The PR's checks and published handoff record fresh Windows/Debian/sanitizer
  CI for the final review revision; previous preparation CI alone is not its gate.

Private local evidence: `bench-artifacts/20261008-pr10-main-update/`;
matched script compilation: `20261007-connected-combat/redscript/compile-20261008T104718044073Z`.

## Scope and next steps

The [live checkpoint](CONNECTED_ENCOUNTER_2026-10-08.md) remains the evidence for
the controlled one-PC/two-client encounter. No new live test is claimed for this
history-only update. JOINER weapon/attacker parity, native bullet behavior,
authoritative life-state recovery after reconnect and two-PC qualification remain
unfinished. The CPEX1 payload/kind remain diagnostic proposals.

Game/bridge ownership and exact source paths remain recorded in the
[connected adapter](../../experiments/shared-encounter/connected/README.md) and
[passive-player record](PASSIVE_PLAYER.md). This task does not modify
SessionServer or the wire protocol, deploy to a server, replace an installed
game runtime, or publish a new gameplay package. The existing v0.0.37 / alpha.5
package is preserved.

After review, Bukczyk decides the PR merge. Follow-up work connects agreed
weapon/attacker semantics and accepted health/death restoration to the game-side
adapter, then repeats isolated recreation/reconnect and broader live tests.
