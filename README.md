# CP2077-Coop

Work toward v0.1.0 Session Architecture. The running legacy plugin still reports v0.0.25; the imported Lua bridge reports v0.0.26. The new portable core is not yet wired into the game or a public session server.

## Build and check
Requirements: CMake 3.21+, C++20 compiler, Git for SDK bootstrap. Windows: Visual Studio C++ x64 tools and Windows SDK. Linux: GCC 12+ and Ninja (Debian bookworm packages cmake, g++, ninja-build).

```powershell
# Windows: plugin, legacy relay, portable core and automated tests
./scripts/build.ps1
# Reuse the exact pinned local SDK checkout, without downloading it
./scripts/build.ps1 -SdkSource D:/CP2077-Coop/RED4ext.SDK
# Portable code only, with no RED4ext dependency
./scripts/build.ps1 -CoreOnly
```

```sh
# Linux: portable core and tests (no game/Windows SDK required)
bash scripts/build.sh
```

Equivalent portable commands:

```sh
cmake -S . -B build/core -DCOOP_BUILD_PLUGIN=OFF -DCOOP_BUILD_LEGACY_SERVER=OFF
cmake --build build/core --config Release --parallel
ctest --test-dir build/core -C Release --output-on-failure
```

The default root build includes the portable core/tests and, on Windows, the legacy relay. Enable COOP_BUILD_PLUGIN to build the DLL. RED4ext.SDK is automatically fetched at ad7277714ad30d6885d7050c5ba24fa0102f6920 when no COOP_RED4EXT_SOURCE override is given. RedLib is not required. No script installs files into the game.

Windows root-build outputs: build/windows/CoopPlugin/Release/CP2077Coop.dll and build/windows/CoopServer/Release/CP2077CoopServer.exe. Linux currently builds shared/libcoop_core.a plus test executables; a deployable Debian session server belongs to the next stage, and the legacy relay remains Windows-only.

GitHub Actions checks a fresh Windows build with SDK bootstrap, a Debian bookworm core build, and Linux ASan/UBSan tests. Protocol tests include golden bytes, truncation/type/value rejection and deterministic malformed-input coverage. Session tests cover roles, identity binding, isolation, ownership, ordering, reconnect/reset and resource bounds. runtime_import verifies the five frozen source hashes on both platforms.

## Source map
- shared/: platform-independent protocol and single-threaded session policy.
- tests/: headless checks; no running game needed.
- CoopPlugin/ and CoopServer/: frozen legacy runtime/relay until coordinated cutover.
- runtime/: byte-preserved CET/REDscript/TweakXL import; see runtime/README.md.
- docs/PROTOCOL.md: exact implemented wire contract and limitations.
- ARCHITECTURE.md and MIGRATION_PLAN.md: target design, gates and status.
