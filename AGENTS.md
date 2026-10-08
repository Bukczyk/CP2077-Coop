# Agent instructions — CP2077-Coop

## Objective
Migrate to v0.1.0 Session Architecture. HOST is the world authority, JOINER is a session client, and Debian owns session membership, accepted state storage, and relay. Read ARCHITECTURE.md and MIGRATION_PLAN.md before implementation.

## Work rules
- Read [the shared goals](docs/SHARED_GOALS.md) and [the collaboration guide](docs/COLLABORATION.md) before shared work. These documents record KyleBuildsAI's approved proposal for Bukczyk's review; do not infer acceptance from publication alone.
- Check active tasks, PRs and handoffs before editing. Record the task owner, branch, base commit, exact files and acceptance checks. Use task branches and PRs; never write directly to main.
- Follow the agreed networking/game-integration boundary. Coordinate shared files and interface changes with the other owner; being offline does not release task ownership.
- Questions and explanations authorize discussion and inspection only. Implement or publish only when explicitly requested by the directing maintainer; proceed autonomously within that assigned scope.
- Implement, build, diagnose and commit autonomously within the requested scope. Ask the user only for checks that require a running game or unavailable credentials/access. Never report an unperformed check as passed.
- Preserve unrelated edits and local game saves. Commit only explicit task files. Do not push or deploy to an unidentified server.
- Freeze CP1/RP1 and all sentinel encoding (-666/-777/8888/9999). Do not add markers, widen marker predicates or put additional gameplay into movement fields. Existing legacy behavior stays until the complete replacement bridge is ready.
- Separate protocol, session policy, transport and game integration. Shared protocol/session code must compile without Windows or RED4ext headers.
- Use explicit packet types and entity IDs. JOINER sends intent; HOST validates and emits authoritative world results. Debian validates sender membership and role before relay/storage.
- No game object access from network threads. Transfer coherent snapshots and bounded event queues to the game thread; movement and combat have separate storage.
- Explicitly encode bytes; never send native struct memory. Validate version, lengths, enum values, numeric ranges, finite floats, ownership, sequence and session epoch.
- Meaningful protocol/session changes require automated tests for malformed input, role violations, duplicate/reordered events, isolation and disconnect. Documentation-only changes require review and git diff --check.
- Keep migration status and actual validation current. Do not mark v0.1.0 released while the plugin still runs the legacy protocol.

## Current build
C++20; local generator is Visual Studio 18 2026, x64. Existing configured builds:

```powershell
cmake --build CoopPlugin/build --config Release
cmake --build CoopServer/build --config Release
```

Outputs: CoopPlugin/build/Release/CP2077Coop.dll and CoopServer/build/Release/CP2077CoopServer.exe. The latter is currently Windows-only, not the target Debian server.

Root CMake builds shared/ and tests/ on Windows/Linux. scripts/build.ps1 builds the Windows plugin and relay too; scripts/build.sh builds the portable core on Linux. See README.md. RED4ext.SDK is pinned and fetched by CMake when no verified local override is given; RedLib is unused. The existing ignored checkouts remain local. Do not modify vendor code to mask integration failures. The frozen CET/REDscript/TweakXL bridge is tracked under runtime/; consult runtime/README.md before changing it. Automated core tests are required during stage 2.
