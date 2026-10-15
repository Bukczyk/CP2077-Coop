# Local passive model fixture validation

Validated offline on 2026-10-15 UTC. Branch `feat/passive-model-fixture`, based
on `2a8bb541d59ba47596e5f66a65ad2fc38e77e197` (reviewed profile assets).
This is a separate source experiment, not a new runtime or package version.
The appearance follow-up starts from fixture checkpoint
`e291b75799d7a4db8aff661829343f1f7ae791eb` and retains its scope/defaults.
The coherent color follow-up starts from
`a105a228d2fd5505f071f0e6dd11d05d6493cedd`, reusing this fixture and adding
original-native identity checks needed to keep replacement actors safe.
The pure historical comparison follow-up starts from
`d6ae28f4018ddf2f95f385270759e6c638997d70`; it adds no native calls.
The separate encounter-asset prerequisite starts from
`e8bd1d913b35125015c386915b229fb16ee00897`; it does not activate fixture reactions.

## Scope and ownership

The original fixture adds `engine.lua`, `fixture.lua`, `init.lua`, three focused
Lua test suites, their CMake registration and fixture documentation. The
follow-up adds only `engine_hooks.reds` and updates those three modules/tests
and this documentation; CMake registration is unchanged. It does not change
the authored assets, production adapter, protocol, session server, installed
game files or existing packages. Judy and Mitch are explicit local labels, not
network identities or arbitrary HOST appearance mappings.

The comparison follow-up owns exactly seven files: new `comparison.lua`,
existing `fixture.lua`/`init.lua`, the fixture and entrypoint Lua suites, and
`README.md`/this note. The existing engine adapter, native helpers, asset builder,
assets and CMake registration are unchanged. `compare` reads existing copied
state and returns bounded primitive evidence; it does not retain a comparison,
enqueue work, log, change lifecycle or select/apply a model.

The encounter prerequisite owns six files: one new authored Mitch encounter
entity, `build_encounter_profile.py`, `tests/passive_model_encounter_asset_tests.py`,
one registration in `tests/CMakeLists.txt`, and the two fixture documents. The
existing idle/Judy/hittable assets and encounter graph, native helpers, Lua
fixture, PR12 restoration and backend contracts remain unchanged.

The controller admits bounded copied commands. Only the real entrypoint's
`onUpdate` callback invokes the engine adapter. `onShutdown` queues retirement
without engine access. An unload with no subsequent update can leave pending
ownership; the next instance refuses unknown tagged actors rather than silently
spawning replacements. Stop all slots and observe `closed` before unloading.

## Results

| Check | Result |
| --- | --- |
| Windows x64 Release portable core, session server and test build | Fresh configure and incremental Release passed after the new test registration; native source unchanged, plugin excluded on this branch build |
| Complete CTest suite on this branch | 31/31 passed, including the new encounter asset test and all previous tests |
| Actual engine adapter tests | 248 checks in Lua 5.4; 250 in LuaJIT 2.1 |
| Pure queue/state controller and historical comparison tests | 140 checks, both runtimes |
| Real `init.lua` with real adapter/controller and mocked native APIs | 194 checks, both runtimes |
| Independent actual PR27 producer to PR26 consumer | 54 checks in each runtime; native/helper boundaries mocked |
| Audited comparison metadata/hash constants | Four resource SHA256s and seven native hash constants cross-checked |
| New encounter-profile asset mutation suite | 23 tests passed; both profiles, copy/handle/dependency/controller safety and output refusal |
| Existing idle profile / passive contract / hittable suites | 22 / 23 / 9 tests passed |
| Private WolvenKit 9.0.1 encounter profile builds | Judy and Mitch passed exact roundtrip, single-entry archive listing and unpacked-byte parity |
| Parent independent Python-builder to Lua catalog comparison | Both profiles match all seven fields in both runtimes; returned copies isolated |
| Independent lifecycle/source review | Passed; additional per-slot failure, paused/unknown retirement, native spawn throw and duplicate-ID cases passed |
| REDscript API signature sandbox | Passed against installed 2.31/Codeware declarations; inputs unchanged |
| Exact coherent appearance/color and identity helpers sandbox compile | Passed against copied Test B 2.31 cache and Codeware; source/game/compiler inputs unchanged |
| Installed game or two-PC test | Not performed |

The native mocks exercise the actual Lua modules and actual registered event
callbacks. They do not prove native behavior, rendering or performance in a
running Cyberpunk instance. The signature probe compiles calls without
executing them. Existing generic tests remain applicable only to their own
contracts; passing them is not a new multiplayer-capacity claim.

## Regression coverage

- Concurrent independently named Judy/Mitch slots; duplicate queued starts;
  immutable command/status copies; bounded slots and 64 transition log lines.
- Every profile dependency absent or unknown before native creation; unsupported
  profile; malformed historical tag inventory; tags known to this instance
  permitted for the second profile, including pending creation IDs.
- Exact IDs beyond Lua's integer precision; original creator retained; global
  and first observed exact handles retained; wrong-ID reads fail closed.
- Pending stop/reset/shutdown; missing tokens and nil lifecycle flags; valid
  late callback recovery; no early pending Despawn; no reuse before completed
  creation and actual terminal disappearance.
- Wrong template, wrong root class and missing/nonfinite position/orientation
  readback block movement while exact owned cleanup remains possible.
- Missing or throwing appearance helper, nil, `None`, empty, non-string and wrong
  appearance names block movement/placement qualification. The actual entrypoint
  verifies sibling-slot independence, later recovery and exact cleanup while
  each appearance fault is active. Exact requested `default` equality is required;
  a true verification flag cannot substitute for the name.
- Queued movement, stale generations, stop superseding a queued move, fresh
  player identity, local distance limits and a changed final getter result.
- Rejected preflight versus attempted native outcome; no automatic retry;
  submitted transform does not certify actual placement; later readback can
  qualify it; failed read clears current placement verification.
- One slot's failure does not prevent another slot's progress. Reload with an
  old actor does not create a duplicate under a new slot name.
- Structured transition diagnostics tie exact identity and generation to
  requested/submitted/actual poses, template evidence and false visual status.
- Same-state appearance name changes produce bounded diagnostics; unchanged
  frames stay silent. A final lookup returning the same exact EntityID with a
  changed appearance cannot receive a transform, and the rejected preflight
  clears cached qualification until fresh readback recovers.
- Joint appearance/color capture, exact hash strings above 2^53 and up to Uint64
  max, malformed/overflow/cdata values rejected rather than parsed through Lua.
  Observed `None`, empty symbols and zero hashes remain data; missing or failed
  getters remain unknown. Changing either CName during capture rejects the pair.
- Changing color on the same original actor before final movement preflight
  rejects mutation. Later coherent evidence can recover without claiming a match.
- Native identity differs from Lua wrappers and decimal IDs. Fresh wrappers pass;
  a different same-ID native actor cannot receive movement or retirement, including
  replacement immediately before the deletion call. Positive foreign identity is
  sticky; unknown identity blocks mutation and may recover when verified.
- Exact cleanup works with failed cosmetic readback. A false/throwing/unknown
  native removal attempt is never automatically reissued; actual later terminal
  disappearance can complete retirement.

## Engine evidence

Declarations were checked in installed `Codeware.Global.reds`: ResourceDepot
`ResourceExists`; `ResRef.FromName/GetHash/ToString`; `StaticEntitySpec` and
`StaticEntitySystem` creation, lifecycle, tag inventory and retirement methods;
`Entity.GetTemplatePath`, inherited `ISerializable.IsExactlyA`, actual world
position/orientation and `SetWorldTransform`. Native quaternion fields remain
separate from requested yaw. The verified base `Entity.GetCurrentAppearanceName`
returns CName, as does `GetCurrentColorVariantName`. `NameToString` and
`NameToHash` export readable symbols and exact hashes without mutation.
`CurrentVisualState` checks original native actor/player references, global
lookup, IDs, attachment and both CNames before/after sampling. `OwnedIdentity`
independently returns exact/unknown/foreign identity without cosmetic reads.
The actual helpers compile against copied cache/Codeware. No Lua wrapper equality,
unverified `Entity:GetAppearanceName` getter or GameObject-only actor is assumed.

Lifecycle readiness remains separate from appearance qualification. Failed
appearance readback does not suppress an otherwise exact owned actor's removal.
The coherent pair is verified again on the final mutation actor before
`SetWorldTransform`; the expected appearance is never inferred from template,
profile name or HOST record. Observing `default` still leaves
`visualQualified=false` and does not prove visible mesh/animation correctness.
`colorMatchVerified` is always false: no color, including `None`, is declared
supported or matched to another NPC. Replacing the original player invalidates
visual/movement evidence, while cleanup may use a valid current context to retire
the exact original actor. Positive native actor replacement is a sticky ownership
fault, not a cosmetic failure, and never authorizes cleanup or slot reuse.

The lifetime rules follow the reviewed [Codeware v1.18.0 static system source](https://github.com/psiberx/cp2077-codeware/blob/v1.18.0/src/App/World/StaticEntitySystem.cpp)
and the corrected game-side PR20/PR21 adapters: pending token removal does not
prove the asynchronous callback was canceled. A completed creator-owned ready
attachment must have been observed before empty observations can release the
fixture's ownership. No dynamic-population quiet timer is assumed for this
static system.

Private evidence is under
`D:\Downloads\syncfix\bench-artifacts\20261015-passive-model-fixture-audit`:

- `compile-20261015T090405788234Z.json` and `.log`: compile-only signature probe,
  original input hashes and unchanged-input verification.
- `catalog-crosscheck.json`: direct Python/Lua allowlist comparison.
- `fixture-validation.json`, `fixture-ctest.log`: source hashes, commands,
  runtime results and complete CTest output.

Appearance follow-up evidence is separately retained under
`D:\Downloads\syncfix\bench-artifacts\20261015-passive-model-appearance`:
`lua-validation.json`, `branch-ctest.log`, and
`compile-20261015T093711951193Z.json` / `.log` for the exact helper compile with
unchanged inputs. Independent review reran all three updated suites under both
Lua runtimes and approved the appearance/cleanup boundary.

Coherent color/identity follow-up evidence is under
`D:\Downloads\syncfix\bench-artifacts\20261015-passive-profile-color-observation`:

- `lua-validation.json`: source hashes and 479 Lua 5.4 / 481 LuaJIT checks. The
  extra LuaJIT checks reject cdata hash payloads and accept exact decimal strings.
- `branch-ctest.log`: 30/30 passed. C++ inputs are unchanged; no redundant rebuild.
- `passive-compile-20261015T104427943852Z.json` / `.log`: parent compiled the exact
  final helpers plus session scripts against copied cache/Codeware, inputs unchanged.
  The earlier `passive-compile-20261015T103702883896Z.*` predates identity extension.
- `retirement-reference-probe.lua` and negative-control results in
  `lua-validation.json`: actual original `a105a22` entrypoint/adapter/controller
  deleted a different same-ID native actor (`deletes=1`) while the original handle
  remained attached. Patched source issues no removal (`deletes=0`) in both
  runtimes. This is a mocked reproduction, not a live race.
- `independent-focused-suites.json` and `independent-passive-tuple-review.json`:
  independent review reran the focused suites and 30 separate actual-entrypoint
  scenarios in each runtime; no source blocker remained.

Historical comparison evidence is under
`D:\Downloads\syncfix\bench-artifacts\20261015-passive-appearance-comparison`:

- `lua-validation.json`: 582 Lua 5.4 / 584 LuaJIT checks and eleven exact metadata
  comparisons. Tests cover both known chains and intentional source/target name
  differences; record-only and unsupported tuples; exact Uint64s; missing symbols
  with known/unknown hashes; malformed, cyclic and contradictory input; duplicate
  target fields; target read failure, stop, recreation and shutdown; detached
  result copies; raw color inequality; and zero engine reads, mutations or spam.
- `profile-hash-provenance.json` / `verify_profile_hashes.py`: reproducible ASCII
  FNV1a64 constants from pinned SDK `ad7277714ad30d6885d7050c5ba24fa0102f6920`.
  Independent review checked `CName.hpp` and `ResourcePath.hpp`/`FNV1a.hpp`; these
  canonical lowercase/backslash paths survive resource-path sanitization. Both
  quest-template constants also match actual extracted metadata. Computed hashes
  are not native runtime observations or loaded content attestation.
- `independent-producer-consumer.lua` / `.json`: actual PR27 `ab9d106` observer and
  entrypoint feed actual PR26 fixture/engine/entrypoint, with only native/helper
  return values mocked. 54 checks passed per runtime, including missing symbolic
  source names, historical reset semantics, queued stop and stale generation.
- `branch-validation.json` and its log: parent reran the whole branch, 30/30
  CTests passed with source hashes unchanged. Native/runtime/script/CMake diff
  from `d6ae28f` is empty; the matching Release build was reused. Prior exact
  helper compile evidence remains applicable; no redundant native build or
  compile is claimed for this Lua-only comparison.
- `independent-focused-review.json`: final source/test review approved, rerunning
  the three focused suites in both runtimes and checking exact resource metadata.
  `frozen-source-manifest.json` pins all seven final task files.

The source tuple is caller-supplied historical data, not an authenticated handle.
Old copied captures can still produce historical candidate reports after a
source-only reset/reload/reconnect; the report never claims to detect those.
The current fixture has no target capture frame. Source and target capture times
are not asserted equal, and an observed color pair is not a supported color rule.
The fixture can observe while paused because observation is read-only; comparison
does not certify unpaused state or grant mutation permission. A failed target
read clears cached evidence, and its next comparison returns `unknown`.

## Encounter asset prerequisite evidence

Encounter prerequisite evidence is separately retained under
`D:\Downloads\syncfix\bench-artifacts\20261015-mitch-encounter-profile`:

- `mitch-build-01/manifest.json` and `judy-build-01/manifest.json`: actual pinned
  WolvenKit builds, commands in `build.log`, roundtrip JSON, archive listing and
  extracted single payload. All recorded source/tool inputs stayed unchanged.
- Mitch authored entity SHA256:
  `3a043bf3ead761ab4d7b193efa90fd1bcb884037975433b37cc1878db655f3f2`.
  Archive SHA256:
  `577c972378b7ec4602bdebb2f85333f33f630087e279180bfdf5466779e02ab2`.
- Judy authored entity SHA256:
  `fdaece384d3323106c7ee7725f6f1ea68ecca8df57dbef869fbf9d6d2ac3b159`.
  Archive SHA256:
  `4cf6fccc05313e66cc8731b29fdecc9d8ae870add81dfbf5c590cbf48c6a7ce8`.
  `judy-resource-parity.json` verifies exact equality with the earlier encounter
  `build-03` entity. No timestamp-only archive rebuild was used as a test.
- The reviewed Judy source LF-normalized SHA256 is
  `6d86e3be6c538ea886e3cff696739a4aadcb4b836ccaa90772b8e9f25144793f`;
  the unchanged graph source LF-normalized SHA256 is
  `5e73fe0bebab9901f4d610143ff6d55e8bd153b63606417c280e4e9b846b5675`.
  These pin source JSON, not installed resource bytes.
- `independent-source-review.json` and `independent-build-review.json`: independent
  reviewer passed the 23 new tests plus 37 additional controls, revalidated both
  actual roundtrips, ran CLI archive listing, checked payload/input hashes and
  existing-output refusal, and confirmed 14 protected asset/runtime files were
  unchanged. No remaining source/build blocker was found.
- `branch-validation.json` and logs: fresh configure, incremental Release and
  31/31 CTests passed. Code/test hashes stayed unchanged during validation.
  Native/plugin source is unchanged; this branch build has
  `COOP_BUILD_PLUGIN=OFF`. No new REDscript compilation was needed or claimed.
  `frozen-source-manifest.json` records the six scoped files for publication.

Both archives contain only the authored entity. The unchanged encounter graph
is required separately; no game mesh/rig/animation payload is bundled. This
prepares a presentation asset, not physical hit detection or a connected
male reaction/death implementation. Fixed front-torso clips do not reproduce
arbitrary HOST reactions, ragdoll or final bone poses. Actual idle/impact/death
deformation, transitions, terminal pose and recreation without idle flash remain
deferred live gates. The existing fixture still uses the idle assets.

## Reproduce offline checks

From the source root with a configured Windows Release test build:

```powershell
cmake --build build/passive-model-fixture --config Release
ctest --test-dir build/passive-model-fixture -C Release --output-on-failure
```

Each focused Lua suite also accepts the repository root as its first script
argument. Run `tests/passive_model_{fixture,engine,entrypoint}_tests.lua` in
fresh Lua 5.4 and LuaJIT 2.1 states. The suites total 582 and 584 checks,
respectively. Python profile tests and existing asset contract tests run through
CTest as before.

## Remaining qualification

No fixture was installed or activated. Both actors visible simultaneously,
correct default appearance, deformation, idle playback, absence of autonomous
behavior, native move/readback and cleanup/recreation still require manual
live testing. `visualQualified` remains false unconditionally. Resource
presence alone cannot identify replaced or corrupted asset bytes.

This fixture has no combat, seats, collision, model selection from network
descriptors or remote player binding. Unknown spawn outcomes or a never-ready
actor intentionally keep the slot held; there is no unsafe automatic escape
or cleanup of actors not owned by this exact instance. The next integration
step still requires live qualification and an agreed supported descriptor
mapping. The historical comparison is only a reviewed resource-chain candidate;
it does not establish rendered parity, effective override bytes or authority.
