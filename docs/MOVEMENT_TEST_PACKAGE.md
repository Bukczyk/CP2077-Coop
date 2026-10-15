# Experimental movement test: PR #5 + PR #17

This is an **unqualified test build**, not a finished co-op release. Both PCs must
use this same package version. See BUILD.txt and package-manifest.json for the
exact source and runtime hashes. Protocol v5 and the existing session server are
unchanged. This does not include PR #15, #16 or #18, NPC/combat experiments, or
vehicle work. KyleBuildsAI owns these game-side packages; Bukczyk owns the server.

Locomotion is enabled in CP2077Coop/config.lua. Read-only movement diagnostics are
enabled by the separate CP2077MovementDiagnostics CET mod. The source's normal
movement default remains off. Included dependencies: CET 1.37.1, RED4ext 1.30.0,
Codeware 1.18.0, the pinned redscript compiler, ASI loader, data and license files
from the preserved v0.0.37 bundle. These are the previously used Cyberpunk 2.31
runtime bytes, not dependency upgrades. The typed DLL and co-op scripts replace
the old mod implementation. This is not an overlay for the old relay prototype.

## Install for the two-PC test

1. Close Cyberpunk. Extract your HOST or JOINER ZIP outside the game folder.
   Keep your current complete package for rollback. Do not modify saves.
2. Back up these existing mod folders **outside the game directory**, then move
   those folders out of the game directory so old scripts cannot remain loaded:
   `red4ext/plugins/CP2077Coop`, `r6/scripts/CP2077Coop`, and
   `bin/x64/plugins/cyber_engine_tweaks/mods/CP2077Coop`.
   Do the same for an older `CP2077MovementDiagnostics` CET mod, if present.
   Keep the backed-up session.ini and access.key private.
3. Disable private `zz_FirstContact`, `zz_PlayerPoseFixture`,
   `zz_PlayerCleanupFixture` and other test-control CET mods by moving their mod
   folders outside the game. Do not run old CP2077CoopNet/NetProbe/relay mods with
   this typed DLL. Use an existing clean typed install or a dedicated test copy.
4. Copy the contents of `game-root` beside the game's existing bin, engine, r6
   and red4ext folders. If your dependency versions are different, use a separate
   test copy rather than blindly overwriting them. The ZIP does not contain game
   archives, saves, graphics settings, CET bindings, session.ini or access.key.
5. Restore **only** session.ini and access.key from your typed mod backup into
   `red4ext/plugins/CP2077Coop`. Check role=HOST or role=JOINER for your PC.
   Retain the agreed server address/port, first-test session and private key.
   For a fresh install use config-examples/session.ini.example and obtain the
   connection details privately. Its loopback address is only a placeholder.
6. Keep existing graphics and input bindings. Start HOST, load its save and
   confirm SESSION_READY in `red4ext/plugins/CP2077Coop/session.log`. Then start
   JOINER and confirm the same session ID. This package does not launch a game.

## Run the same short test on both PCs

Record package version and UTC start time. Keep both games active. Observe each
other in an open area, on foot. Avoid combat, vehicles and time-slowing abilities.

1. Stand still for 10 seconds, then walk straight for 20 seconds.
2. Stop for 10 seconds. Turn 90 degrees, then 180 degrees while stationary.
3. Walk in a square for 30 seconds, with a short stop at each corner.
4. Swap who walks and who watches. Record a video on the observing PC.
5. Reconnect JOINER using the existing CET reconnect hotkey. Confirm one remote
   actor returns and the old actor disappears. Repeat twice. Do not remap keys.
6. Collect logs on both PCs, then stop this run before attempting any fixes.

PowerShell, from the extracted package (change the path and role):

```powershell
./Collect-Logs.ps1 -GameRoot 'C:\Games\Cyberpunk 2077' -Role JOINER
```

The ZIP is written to Desktop. It contains logs, never session.ini or access.key.
Send logs privately; they may contain network addresses. Note where walking,
stopping, turning and reconnect started, and what you saw. To roll back, close
the game, replace these mod folders with their saved copies and remove the added
diagnostics folder. Retain current controls/configuration and saves.

## What the diagnostics mean

`CP2077MovementDiagnostics/CP2077MovementDiagnostics.log` records `[CP2077Movement]`
rows at up to 5 Hz, capped at 9,000 frames or 8 MiB of diagnostic message text,
plus the final STOP marker. CET timestamps add overhead. Restart the game for a
new recording if the cap is reached. The collector also includes the session,
main mod, CET and REDscript logs when available.

Frame rows identify session, generation, local PlayerId, HOST, pause state,
remote count and retiring actor count. Player rows identify the remote network
entity and exact local actor, target and observed position, target yaw in radians
and actual yaw in degrees, gait, command type/state/age, tracking error, requested
corrections, observed corrections and latched faults. `na` means unavailable;
`readback=unavailable` is not a zero position. Error/speed and command age are
motor-cached observations and can be stale while paused or faulted. This is not
a measurement of network ping. Logs sample at most 16 remote actors per frame;
that diagnostic limit is not a supported-player claim.

Pass only after both PCs visibly show walking/stopping/turning, no repeated
snapping or frozen actor, no latched motor/bridge fault, and no duplicate or
leftover actors after reconnect. Report actual position-error distribution and
fault/correction counts alongside the video. A submitted command is not proof
of movement; offline tests and script compilation are not this live gate.

## Rebuild

Build the typed Windows Release plugin from this exact commit with
COOP_LEGACY_PLUGIN=OFF. Run CTest and isolated REDscript compilation first.
Use the complete preserved v0.0.37 dependency bundle as an input. The packager
verifies its 38 allowlisted files and hashes, not arbitrary installed game files.

```powershell
python scripts/package-movement.py --dependency-bundle PATH_TO_V37_BUNDLE --build build/movement-package --output artifacts/movement-test --version v0.1.0-movement-experiment.1
```

The output folder must be new and the source checkout clean. Both role archives
share identical game files. Only the role example and resulting manifest/checksums
differ. Each ZIP is reopened and checked against all payload bytes before success.
