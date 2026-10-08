# First contact: current-main integration

## Latest follow-up

The WAN connection and visible remote actor were observed, but JOINER following
froze with `readback_timeout`. The HOST saw one controlled position change.
Local scripted pose trials and new diagnostic fields are documented in
[the follow-up](PLAYER_POSE_FOLLOWUP_2026-10-08.md). The WAN freeze remains
unresolved; do not read the earlier pre-WAN checkpoint below as current status.

## Earlier integration checkpoint

Owner: KyleBuildsAI. Started 2026-10-08 UTC. PR #5, `feat/player-movement-presentation`.
Upstream base: `e19ffb3286efec750b8729487220becf6569ab7b` (protocol v5).

Goal: HOST and JOINER see one remote player each, observe movement/rotation,
and remove the exact actor on departure without duplicates after reconnect.
Two clients are a validation step, not the product capacity limit.

## Scope and ownership

KyleBuildsAI owns the player changes in `runtime/session/cet/CP2077Coop/{init,config,player_motor}.lua`,
`runtime/session/redscript/CP2077Coop/remote.reds`, player tests, CMake test registration and these docs.
Bukczyk owns the unchanged SessionBridge, protocol, client/server and routing.
No PR #12 changes are imported. NPC/combat, vehicles and Sandevistan remain deferred.

Rebased only the two original PR #5 commits, preserving current main's passive-player,
NPC and pose code. The motor is explicitly opt-in (`experimentalPlayerMovement = true`).
Default remains main's bounded, readback-verified pose actuator. The motor is not
claimed smoother: its historical P95 error was about five metres. Both consume the
existing interpolated player state on the CET game thread. Exact replacement and
departure unbind old projections before rebinding; opaque IDs are never rounded.
Value-only diagnostics expose player targets and actor identities for live measurement.

## Validation

- PASS: 26/26 Windows Release CTest suites, including player motor, player pose,
  session lifecycle, real sockets, impairment and authority tests.
- PASS: isolated REDscript compilation with installed Codeware; compiler/game inputs unchanged.
- PASS: Windows Release DLL and matching server build at `0c46caf`.
- PASS: hosted Windows, Debian and sanitizer CI at `0c46caf`, run 37843383366.
- PASS: installed REDscript compilation in both development copies.
- Live visibility/movement/reconnect: pending manual game load. Both local windows
  and the local server are open. Automated menu input did not reliably register;
  no key remapping attempted. No current live gameplay pass is claimed.
- Two-PC Debian test: pending connection instructions and both participants.

Private evidence: `D:\Downloads\syncfix\bench-artifacts\20261008-first-contact`.
Do not promote the public package or claim live success from these offline checks.

## Installed state and next action

Matched DLL/server/scripts from `0c46caf` are installed. Controls, private session
configuration, Lua config and saves were preserved. The local `zz_FirstContact`
probe only logs identities, actor counts and actual/received transforms; it does
not spawn, move, bind or alter actors. Evidence includes deployment.json,
validation.json, ctest.log and isolated compiler records in the private folder.

Bukczyk reports a real HOST connection to Debian. Treat this as collaborator
reported admission, not observed two-player gameplay. The JOINER ZIP has not yet
been provided locally. Inspect its configuration/version privately before
switching one local client to his session. Do not publish keys or private configs.
