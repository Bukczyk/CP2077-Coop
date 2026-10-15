# NPC appearance observation validation

UTC date: 2026-10-15. Owner: KyleBuildsAI. Branch:
`feat/npc-appearance-observation`, based on upstream
`e19ffb3286efec750b8729487220becf6569ab7b`.

Scope is the five files in this experiment directory, one focused Lua test and
its narrow CMake registration. This is a separate source-only observation tool,
not a package update or production selector. Bukczyk's networking/protocol work
is unchanged. No game was launched or modified and no live outcome is claimed.

## Verified native boundary

The installed Codeware declarations and a private compile-only signature probe
verified `Entity.GetTemplatePath`, `EntityID.ToHash`, `TDBID.ToNumber`,
`ResRef.GetHash/ToString`, current appearance/color getters, `NameToString`,
`NameToHash`, NPCPuppet casts and exact native reference comparisons through
`GameInstance.FindEntityByID`. The implemented helper was then compiled against
copied actual Test B `final.redscripts` plus Codeware. Installed inputs remained
unchanged. CName/String equality uses `Equals`; integer identity is exported by
native `ToString(Uint64)` and never routed through Lua doubles.

The exact source helper uses the original actor reference, not a replacement
looked up only by ID. It checks attachment, exact ID and native global-reference
identity before and after the tuple read. Native equality also distinguishes
local-player replacement from fresh CET wrappers for the same native object.
The Lua layer validates the returned schema and copies only primitive evidence.

Actual record defaults are deliberately omitted. An observed `None`/empty
symbol and its exact CName hash remain separate from an unavailable getter.
Unknown record or template rejects the sample. `visualQualified` stays false.

Private evidence directory:
`D:\Downloads\syncfix\bench-artifacts\20261015-npc-appearance-observation`.

- `compile-20261015T100500235552Z.json` / `.log`: exact helper isolated compilation
  passed; all compiler/cache/Codeware/helper input hashes unchanged.
- `compile-20261015T100437175367Z.*`: retained first compile failure. Comparing a
  Uint64 with a Uint32 zero literal was unsupported. The final source compares
  the native decimal strings with `Equals`, then compiled successfully.
- `independent-entrypoint-review.lua` / `.json`: independent real-entrypoint
  probes for reference wrapping, UInt64 max, cache isolation and reentrant reset.

## Automated tests

The focused suite loads the **actual `init.lua`**, invokes its registered update
and shutdown callbacks and runs the real observer against native-helper-facing
mocks. Every mocked engine access asserts it occurs inside `onUpdate`. Native
REDscript behavior itself is compilation evidence, not executable unit-test or
game evidence; mocks exercise its documented return contract.

Coverage includes exact decimal IDs above 2^53/up to Uint64 max, fresh Lua
wrappers for unchanged native actors, true same-ID native replacements, opaque
EntityID forwarding, unsupported roots, attachment loss, changed tuple/identity,
malformed fields, missing/throwing getters, observed None/empty/alternate names,
target isolation, load/pause/unknown context, immutable snapshots, bounded queue,
coalescing, reset/shutdown during capture, old-ticket publication rejection,
recovery by explicit retry, historical cache semantics, bounded logs and counter
exhaustion. LuaJIT additionally forwards an actual Uint64 cdata value opaquely.

Run from the repository root:

```powershell
build/npc-appearance-observation/tests/Release/coop_lua_test.exe tests/npc_appearance_observation_tests.lua .
cmake --build build/npc-appearance-observation --config Release
ctest --test-dir build/npc-appearance-observation -C Release --output-on-failure
```

Final offline results:

- Fresh Windows x64 Release plugin, session server, legacy server and core/test
  build passed using the unchanged pinned RED4ext SDK checkout.
- Full branch CTest: **26/26 passed** (`branch-ctest.log`).
- Focused actual-entrypoint suite: **431 checks passed in Lua 5.4**, **434 in
  LuaJIT 2.1**. The extra LuaJIT checks forward a real Uint64 cdata opaquely.
- Independent source/test review reran both focused suites and a separate
  14-check actual-entrypoint probe in each runtime; no blocker remained.
- Independent README/validation review approved the stated limits. The parent
  separately reviewed native identity/coherence checks.
- `git diff --check` passed. `validation.json` records the source hashes, build
  commands and verified results. Hosted CI/publication remain the parent's next
  steps; no hosted CI result is claimed by this branch-local record.

## Remaining gates

No experiment is installed, no real NPC was sampled and no HOST descriptor was
published. Native getter consistency, runtime marshalling, native integer string
formatting on real actors and visual/model parity still need a future authorized
manual test. Capture is historical; identity is rechecked on subsequent updates,
not continuously between callbacks. A network-only reconnect is invisible to
this isolated tool unless its test harness calls the shared reset.

The next substantive integration task is to capture actual supported NPC tuples
in-game, compare them with authored passive profile capabilities and agree any
missing descriptor data with Bukczyk. Record-only matching is not justified by
this source work. No protocol fields or model mapping are invented here.
