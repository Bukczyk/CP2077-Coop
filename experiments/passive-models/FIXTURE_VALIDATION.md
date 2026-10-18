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
The local encounter fixture follow-up starts from
`d583c2affa9f33c54dc36101477d44c35afcfeef`, adding opt-in presentation without
installing or activating any game runtime.

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
deferred live gates. The asset checkpoint itself did not activate the fixture;
the separate source-only fixture extension is recorded below.

## Local encounter fixture checkpoint

Starting from PR26 `d583c2affa9f33c54dc36101477d44c35afcfeef`, the existing
fixture adds explicit `judy_encounter`/`mitch_encounter` profiles and the bounded
`present(slot, generation, reaction|death)` command. Production defaults,
protocol, assets, native helpers and package contents are unchanged. The shared
adapter is reused unchanged; the shared pure controller receives the exact
PR12 `restore` method. There is no duplicate state implementation or committed
copy of a shared module.

Evidence is retained under
`D:\Downloads\syncfix\bench-artifacts\20261015-passive-encounter-fixture`:

- `focused-lua-validation.json` / `validate_focused.py`: all three current
  focused suites pass, 811 Lua 5.4 checks (334 engine, 180 fixture, 297 actual
  entrypoint) and 813 LuaJIT checks (336 engine, 180 fixture, 297 entrypoint).
  The two-check difference comes from an existing runtime-order-dependent loop.
- Tests cover explicit resource dependencies, initial/replacement commands
  admitted before first binding, exact actor/player replacement, preflight and
  between-setter pause/context/identity/visual changes, constructor and setter
  exceptions, normalized retry, newer death supersession, stop/reset before
  stage, terminal new-body restoration, stale generations, per-slot clocks,
  invalid deltas, public API inertness, copied status and sibling isolation.
- `independent-engine-stable-review.json`: 305 independent checks per runtime
  across ten scenarios, using actual entrypoint, engine, fixture, state and
  adapter in a literal-path CET-style sandbox. It checks exact per-setter
  identity/context, partial failures, retry and stop between setters.
  `independent-focused-suites.json` also records the reviewer's rerun of the
  three fixture suites and existing shared state/adapter suites.
- `independent-controller-results-20261015T115808389261Z.json`: 237 independent
  checks per runtime across seven scenarios. The real staged entrypoint/state
  covers terminal admission before reset, nonlethal replacement without replay,
  fresh commands before initial/replacement binding, paused admission, sibling
  recovery, partial sampling, superseding death and shutdown. The staged source
  hashes stayed unchanged. The sandbox has no `package` or global require
  fallback and uses the documented `cp2077_passive_encounter/` subfolder.

Only verified native boundaries are mocked in these Lua checks. They do not
execute Cyberpunk, Codeware creation, native animation delivery or rendering.
The underlying helper source is unchanged from the prior successful isolated
compile; no new native signature or redundant REDscript compile is claimed.
`branch-validation.json` and logs record a fresh configure, incremental Windows
Release build and 31/31 CTests, plus all six relevant LuaJIT suites including
the unchanged connected-encounter suite (206 checks). Executable source and test
hashes stayed unchanged. This branch build has `COOP_BUILD_PLUGIN=OFF`; it does
not claim a new in-game native/plugin build. The final ten-file source manifest
includes the eight fixture-owned files plus the two shared state files owned
by the parent implementation task. Hosted CI is a separate publication check.

The fixture retains logical death only within its current in-memory instance,
not across mod reload or network reconnect. Stop/reset retire the disposable
body while preserving that logical state. A replacement gets final dead state
or idle without replaying an old hit; a new command keeps its own serial. Each
slot has its own reused state controller and effective unpaused time, so one
read failure cannot create `stale_time` for another slot. Invalid deltas above
0.25 seconds or non-finite/negative values freeze presentation; time is credited
only after a valid successful/unchanged sample.

The native adapter checks the original actor/player and exact current binding
before each progress/phase setter. A thrown call may already have queued an
event. `forwarded` is an attempted-call count, not a receipt. Current preflight
failures are reported separately from the last attempted sample/submission.
The latest normalized sample can retry after fresh preflight, including after
an unknown partial pair. This does not prove visible continuity or engine
delivery. Terminality is local fixture intent, never inferred HOST authority.
`animationObserved`, `visualQualified` and color matching remain false.

## Defeated held-pose asset checkpoint

From PR26 `97fd12f12a15257b76b92ecff102203743c601d9`, the existing private
builder adds only explicit `--presentation defeated_hold`. The two authored
entities and separate sampled graph do not change the existing Lua fixture,
shared state, native helpers, protocol or packages. Default `encounter` mode and
its original profile table are preserved. This checkpoint does not encode a
nonlethal state as death or activate a runtime profile.

Evidence is under
`D:\Downloads\syncfix\bench-artifacts\20261015-defeated-held-assets`:

- `tests/passive_model_defeated_asset_tests.py`: 24 focused tests cover both
  profiles, default behavior, exact resource/dependency/rig/clip contracts,
  passive roots and inheritance, template/compiled parity, controller bindings,
  sampling input, motion/events/features, ambiguous/dangling/conflicting/cyclic
  handles, alias identity, WK defaults and LF/CRLF equivalence.
- Existing encounter/profile/passive/hittable suites also pass: 23, 22, 23 and
  9 tests. The old entity/graph bytes and old production validators are unchanged.
- `private-builds-03.json`, `judy_default-build-03/` and
  `mitch_default-build-03/` contain the final pinned WolvenKit Console 9.0.1
  commands, compilation logs, actual entity and graph roundtrips, strict
  validation, archive lists, extraction and source/input hashes. Each archive
  has exactly the selected authored entity plus the authored graph. There are
  no proprietary resource payloads. All inputs remained unchanged during build.
- `independent-final-metadata-and-build-review.json`: independent reviewer reran
  the 24 new and 23 encounter tests, actual pinned CLI listings for both
  archives, strict roundtrip/alias checks, compiled/extracted hash parity and
  metadata checks. No source/build blocker remained.
- `branch-validation.json` and logs record fresh configure, incremental Windows
  Release and **32/32 CTests**, preserving all 31 prior registrations. Generator
  is Visual Studio 17 2022; `COOP_BUILD_PLUGIN=OFF`. Code/test hashes stayed
  unchanged. This is a core/session build, not a new in-game plugin result.
  Unchanged Lua/native/REDscript files did not require a new independent script
  compilation or extra LuaJIT run. Hosted CI remains a publication check.
- `default-mode-regression.json` and `default-encounter-regression/` exercise
  the extended builder with no `--presentation` argument. Actual compile,
  roundtrip and single-entity archive/extraction pass; the entity SHA256 exactly
  matches the prior validated Judy encounter build (`fdaece384d3323106c7ee7725f6f1ea68ecca8df57dbef869fbf9d6d2ac3b159`).
  The default manifest shape and external graph prerequisite are preserved.
  This checks the changed packaging branch, not timestamp-only repeatability.
- `frozen-source-manifest.json` records the exact eight scoped source/doc paths.

Final private artifact SHA256s:

| Artifact | SHA256 |
| --- | --- |
| Judy defeated entity | `db028a5c46a99286f6828c6c66e7e956db08ba44670a2d5c142ccc8fbad93688` |
| Mitch defeated entity | `0017b629725ee4fa2e99d17410481cf3f6f8f301f57245f4a371c338bc8b0df6` |
| Shared defeated graph | `fbcde5377c94226d50bd31b011724bf63c5cf348a3d5cea2ac22acf6094491e8` |
| Judy two-resource archive | `74e1a1a77559a54162d71dfc2c8574d0f7d4a26141baad6457bd7573f85945d7` |
| Mitch two-resource archive | `d0100d621429664f42bbd0240d80fa4ca33e4f29c69c2785e155013bbcf555ff` |

Metadata provenance is retained separately in
`20261015-defeated-presentation-audit/animation-metadata.json`. Both game 2.31
sets declare `defeated_loop_01`, duration 10.3000002 s and no motion-extraction
object. The female set SHA256 is
`866b9e1e6f1a043c95a697e02ae3be6a53898a60ca494c5888384bdaf900c16a`;
the male set SHA256 is
`3fc33c80788b9a863f71df3ebe4ce76fe0c83b4018b2699124bc51cb149c81aa`.
Their exact rig/resource references are pinned in the builder. These are metadata
observations, not redistributed animation bytes or rendered validation.

Validation caught and corrected three source/build issues before acceptance:

1. The first authored graph used a forward handle reference. WK reported a
   deserialization error and no compiled graph, despite its process exit zero.
   The builder rejected the missing output. `judy_default-build-01` preserves
   that evidence. The new graph now defines nodes before referring to them.
2. Flattened handle data could accept a copied identical active root or input
   with a different object identity from the initialized node. The graph-only
   alias check rejects those mutations while retaining renumbered/equivalent
   WK forms. Independent and parent probes are preserved in this evidence folder.
   Existing entity normalization was not broadened or changed.
3. The corrected build02 compiled, but strict roundtrip comparison rejected
   defaults materialized by WK that were absent from the terse authored node
   shapes. `wk-roundtrip-defaults.json` and the independent defaults review
   establish that no old field or alias changed. The new graph now authors those
   exact values, with mutation tests; no unknown field is stripped or ignored.
   Failed build02 evidence is retained. Final build03 uses new output folders.

These were offline authoring/validation findings, not observed game bugs. The
new graph exposes normalized 0..1 sampling, default0, without an automatic time
source. At that asset checkpoint the nonlethal state/controller route was still
pending. The separate source-only route is recorded below. No live held pose,
loop, entry/recovery transition, deformation, cleanup or synchronized Defeated
behavior is claimed.

## Supplied life fixture validation, resumed 2026-10-18

The eight scoped files add `baseline(slot, generation, life, progress)` to the
existing local fixture. Alive and Dead use the reviewed encounter body; Defeated
uses the same model family's held-pose body. Exact retirement and observed
absence precede automatic replacement. Newer supplied baselines survive cleanup,
Dead stays terminal, and a supplied final Dead overrides an unfinished death
clip. These are local diagnostic baselines, with no networking or HOST authority.

The moved source is `G:\Projects\CP2077-Coop\collaboration\passive-model-fixture`.
Current evidence is under
`G:\Projects\CP2077-Coop\bench-artifacts\20261018-npc-life-final`.
The earlier `20261015-npc-life-fixture` evidence remains preserved.

- The three updated suites pass **1111 Lua 5.4 / 1113 LuaJIT checks**: 379/381
  engine, 227 controller and 505 actual-entrypoint checks. Existing encounter
  state, adapter and connected-encounter suites also pass under both interpreters.
- The separately staged entrypoint review passes **12 cases / 334 assertions per
  interpreter**, including retained handles, late callbacks, newer baselines,
  final Dead, pause recovery, native player replacement and setter reentrancy.
- Before the final fix, that same review reproduced three failures under both
  interpreters: stop, reset or a changed baseline during spec construction still
  allowed an obsolete body to spawn. The saved failing run and corrected run
  retain module/probe hashes and prove that staged inputs did not change.
- Creation now checks slot/life ownership after the final native context query.
  The controller preserves a cancellation or transition raised during that call.
  Focused regressions additionally cover initial and automatic creation, shutdown
  and progress of the newer body after an unsubmitted obsolete body is cancelled.

Earlier prepublication corrections remain: ordinary pause/missing resources must
defer definitely unsubmitted automatic creation; unknown native attempts cannot
be retried; exact original native player context survives an automatic chain;
and final Dead must supersede a queued or partly played death clip. All are
offline fault-injection findings, not observations of live game bugs.

Fresh branch/combined build and hosted results are recorded in the PR and vault
against the final commits after publication. Old relocated CMake caches are not
used for this resumption. Native helpers, shared state, authored assets, backend
and protocol are unchanged by this eight-file slice. Prior script compilation
applies to unchanged inputs; no new script/native engine signature is introduced.
Live rendering, transition gaps, actual animation delivery and connected
life-state synchronization remain deferred and unqualified.

## Reproduce offline checks

From the source root with a configured Windows Release test build:

```powershell
cmake -S . -B build/npc-life-20261018 -DCOOP_BUILD_PLUGIN=OFF
cmake --build build/npc-life-20261018 --config Release
ctest --test-dir build/npc-life-20261018 -C Release --output-on-failure
```

Each focused Lua suite also accepts the repository root as its first script
argument. Run `tests/passive_model_{fixture,engine,entrypoint}_tests.lua` in
fresh Lua 5.4 and LuaJIT 2.1 states. The current suites total 1111 and 1113 checks,
respectively. Python profile tests and existing asset contract tests run through
CTest as before.

## Remaining qualification

No fixture was installed or activated. Both actors visible simultaneously,
correct default appearance, deformation, idle/reaction/death playback, absence
of autonomous behavior, native move/readback and cleanup/recreation without an
idle flash still require manual
live testing. `visualQualified` remains false unconditionally. Resource
presence alone cannot identify replaced or corrupted asset bytes.

This fixture has no combat, seats, collision, model selection from network
descriptors or remote player binding. Unknown spawn outcomes or a never-ready
actor intentionally keep the slot held; there is no unsafe automatic escape
or cleanup of actors not owned by this exact instance. The next integration
step still requires live qualification and an agreed supported descriptor
mapping. The historical comparison is only a reviewed resource-chain candidate;
it does not establish rendered parity, effective override bytes or authority.
