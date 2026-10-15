# Local passive model fixture validation

Validated offline on 2026-10-15 UTC. Branch `feat/passive-model-fixture`, based
on `2a8bb541d59ba47596e5f66a65ad2fc38e77e197` (reviewed profile assets).
This is a separate source experiment, not a new runtime or package version.

## Scope and ownership

The change adds `engine.lua`, `fixture.lua`, `init.lua`, three focused Lua test
suites, their CMake registration and fixture documentation. It does not change
the authored assets, production adapter, protocol, session server, installed
game files or existing packages. Judy and Mitch are explicit local labels, not
network identities or arbitrary HOST appearance mappings.

The controller admits bounded copied commands. Only the real entrypoint's
`onUpdate` callback invokes the engine adapter. `onShutdown` queues retirement
without engine access. An unload with no subsequent update can leave pending
ownership; the next instance refuses unknown tagged actors rather than silently
spawning replacements. Stop all slots and observe `closed` before unloading.

## Results

| Check | Result |
| --- | --- |
| Windows x64 Release portable core, session server and test build | Passed, MSVC 19.41 / Windows SDK 10.0.22621.0 |
| Complete CTest suite on this branch | 30/30 passed |
| Actual engine adapter tests | 89 checks, Lua 5.4 and LuaJIT 2.1 |
| Pure queue/state controller tests | 45 checks, both runtimes |
| Real `init.lua` with real adapter/controller and mocked native APIs | 33 checks, both runtimes |
| Parent independent Python-builder to Lua catalog comparison | Both profiles match all seven fields in both runtimes; returned copies isolated |
| Independent lifecycle/source review | Passed; additional per-slot failure, paused/unknown retirement, native spawn throw and duplicate-ID cases passed |
| REDscript API signature sandbox | Passed against installed 2.31/Codeware declarations; inputs unchanged |
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
- Queued movement, stale generations, stop superseding a queued move, fresh
  player identity, local distance limits and a changed final getter result.
- Rejected preflight versus attempted native outcome; no automatic retry;
  submitted transform does not certify actual placement; later readback can
  qualify it; failed read clears current placement verification.
- One slot's failure does not prevent another slot's progress. Reload with an
  old actor does not create a duplicate under a new slot name.
- Structured transition diagnostics tie exact identity and generation to
  requested/submitted/actual poses, template evidence and false visual status.

## Engine evidence

Declarations were checked in installed `Codeware.Global.reds`: ResourceDepot
`ResourceExists`; `ResRef.FromName/GetHash/ToString`; `StaticEntitySpec` and
`StaticEntitySystem` creation, lifecycle, tag inventory and retirement methods;
`Entity.GetTemplatePath`, inherited `ISerializable.IsExactlyA`, actual world
position/orientation and `SetWorldTransform`. Native quaternion fields remain
separate from requested yaw. No `Entity:GetAppearanceName` getter is assumed.

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

## Reproduce offline checks

From the source root with a configured Windows Release test build:

```powershell
cmake --build build/passive-model-fixture --config Release
ctest --test-dir build/passive-model-fixture -C Release --output-on-failure
```

Each focused Lua suite also accepts the repository root as its first script
argument. Run `tests/passive_model_{fixture,engine,entrypoint}_tests.lua` in
fresh Lua 5.4 and LuaJIT 2.1 states. The three suites total 167 checks per
runtime. Python profile tests and existing asset contract tests run through
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
step requires live qualification and an agreed supported descriptor mapping.
