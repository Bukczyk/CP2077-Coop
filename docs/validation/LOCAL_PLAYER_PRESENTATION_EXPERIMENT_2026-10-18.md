# Local persistent player-action experiment

Experimental candidate owned by KyleBuildsAI for the user's request to work on
both sides of local sync. Bukczyk remains the production backend owner. This
implements a test candidate from PR18's direction; it does not claim an accepted
contract, allocate a future production version or change the VPS.

## Compatibility

`COOP_EXPERIMENTAL_PLAYER_PRESENTATION` defaults OFF. Default v5 builds omit
the new payloads entirely. Opt-in builds use private compatibility ID `0x8005`
and private packet IDs `0x7f00..0x7f02`. Every local test client/plugin/server
must match. A v5 peer rejects the experimental version. Never deploy these
binaries to the v5 VPS or label them ordinary v5 packages.

The runtime's `experimentalPlayerPresentation` also defaults false. It needs
the locomotion option and the private native declarations/assets described in
the action experiment. Missing native capability keeps the old movement path.
The generated game-animation cache remains private and must not enter Git,
release assets or downloadable packages.

## Data and lifetime

- Complete 23-byte state: entity u64, semantic revision u32, stance u8, weapon
  state u8, canonical record u64, aim u8. Availability is explicit, not an
  assumed standing/holstered/not-aiming observation.
- Record identity is native hash32 + length8, excluding the three process-local
  cache-offset bytes verified in the pinned SDK. It never traverses Lua numbers.
- Current supported visual is only the inspected Igla Pimp `pimp1` recipe.
  Two stable component observations are required before publishing supported.
  Other weapons, extra attachments and mismatched materials stay unsupported;
  the peer hides the unsupported model instead of substituting another gun.
- Owning player publishes a coalesced full state after changes, with at most
  30 Hz attempts and default 2 Hz complete repairs. Transport sequence advances on
  repairs; state revision changes only with observed semantic values.
- Server validates exact membership, session, epoch, ownership/kind, ordering
  and values. Changed contents under the same revision reject without mutation.
  Latest state is bounded by membership count. Routing reuses movement interest
  and coalesces forwarding to at most 30 Hz per peer/source. It is not a broadcast.
- Reliable baseline resolves the current cache at send time, followed by an
  independent fence. Missing presentation never gates movement/SessionReady.
  Stale cache is not sent as a new fresh baseline. Unknown observers initially
  receive only HOST, matching movement bootstrap policy.
- SessionBridge exposes receipt age/freshness, plus exact session/epoch/local
  generation admission and observable coalescing. Candidate staleness is 2500 ms.
  New actor bindings apply current state once. Fresh repairs do not replay commands.
- Disconnect, entity removal, epoch reset and deactivation clear matching state.
  A stale presentation releases only owned cosmetic inputs/model visibility;
  it does not change the actual player's stance, inventory, movement or authority.

## Game thread and engine boundary

The separate `CP2077Presentation_*` native ABI exists only in experimental
builds. Its declarations live in `experiments/player-locomotion`, outside the
ordinary v5 script package. Native TweakDBID/SessionId/generation are passed
directly. The received record is exposed as an exact hexadecimal string.

The opt-in CET adapter captures actual local blackboard/attached-slot state,
publishes value snapshots and applies cosmetic inputs only after the existing
passive controller's exact creator/actor/registry checks. The pure body uses
the already recorded Igla hand-mount asset. No engine object crosses the worker
boundary. No gameplay/combat/vehicle/NPC authority changes.

Camera pitch/yaw, exact finger grip, sight alignment, other weapon models,
appearance/attachment descriptors and one-shot animations remain separate work.
Logical aim is not a promise of ADS alignment or matching shot direction.

## Current validation

- Windows Release plugin/server builds passed in both modes.
- Experimental mode: 63/63 tests passed, including three real TCP/UDP clients,
  repairs without a revision change, relevance filtering, reliable late join,
  reconnect cleanup, old identity/epoch/revision rejection, modular wrap and
  game-thread scope/freshness recovery. Headless sockets are not game proof.
- Default v5 control: 62/62 passed, including the unchanged v5 golden bytes.
- Isolated native ABI names/types/parameter order and Lua actor ownership,
  exact visual selection, unavailable capture, stale neutralization and
  command-free repair handling passed.
- New native declarations and the hand-visibility helper compiled against both
  matched installed script sets with Codeware, using temporary output only.
- Linux/Debian/sanitizer checks for this candidate are pending hosted CI.
- Actual two-window connected crouch/weapon/aim recording, stale/holster/
  reconnect qualification and matched private installation remain pending.

Movement diagnostics now retain received action revision/sequence/freshness,
stance/weapon/record/aim and submitted pose/crouch-motion values. These are
read-only diagnostics and submission evidence; video must still establish the
rendered result.

Private logs: `bench-artifacts/20261018-player-actions/presentation-*` outside
the repository. Earlier `weapon-mount03-parent` qualifies only the isolated
engine attachment, not this new connected path. No in-game action-sync success
is claimed yet. Stable v0.0.37 remains the tested package.
