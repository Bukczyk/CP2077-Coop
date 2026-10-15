# Reviewed passive NPC asset validation

2026-10-15 UTC. Source base: `e19ffb3286efec750b8729487220becf6569ab7b`.
Owner: KyleBuildsAI, game-side asset builders and offline validation only.

## Problem and supported subset

The idle, encounter and hittable builders checked component types, skeleton and
animation references, but did not establish that the entity still used the
reviewed Judy/default mesh. They also accepted template/compiled visual drift
and inherited entity templates. All three original builders accepted each of:

- Replacing both mesh resource paths with the existing skeleton resource path.
- Setting only the template mesh draw mask to zero.
- Adding an inherited template reference in `includes`.

The shared gate now requires the existing
`base\characters\appearances\main_npc\proxy\judy_default\judy_default.mesh`,
default template/mesh appearance, enabled mesh, reviewed draw mask and identity
local transforms for both the animated root and mesh. Resolved template and
compiled entity/component content must agree. Skinning and parent bindings must
be enabled and point to the animated component. Unknown, ambiguous, conflicting
or cyclic handles fail validation; repeated identical definitions remain valid.

The exact `entEntity` and allowed component lists remain in the individual
builders. Inherited templates, appearance overrides and extra instance/visual
data are rejected. This keeps the authored asset structure free of NPC/AI
components; it does not prove engine behavior solely from JSON.

This is a fixed Judy/default visual subset. It does not match an arbitrary HOST
NPC model or appearance, add appearance IDs, or change network descriptors.
Idle, encounter animation and query-only hittable variants keep their existing
separate animation/collision checks and activation requirements.

## Reviewed source and artifact evidence

The source hashes match the existing recorded artifact manifests:

| Variant | Authored entity JSON SHA256 |
| --- | --- |
| Idle | `f6485a1cad7ec22905f93abf7f305a460fb12511a60269c938ad0770e884527b` |
| Encounter | `99e99a7c9593e7dc8a6e3c812dadd535e840b8ca06b6348dbfebbc5d5f155bfe` |
| Hittable | `e08da5de2ffc9620b08132f089ec97a10602f5bb35bfc0894d206f6256a85693` |

Before editing, the existing local manifests and WolvenKit 9.0.1 roundtrip JSON
were inspected under `bench-artifacts/20261006-shared-encounter/research/animation/idle-candidate`,
`bench-artifacts/20261007-passive-encounter-engine/presentation/build-03` and
`bench-artifacts/20261007-passive-encounter-engine/physical-shots/hittable-build-06`.
They establish the reviewed values and allowed duplicate handle representations.
These private historical files are additional compatibility evidence, not test
dependencies. The committed tests use only repository source assets.

No JSON asset, archive, manifest, DLL, runtime setting or installed file changed.
The existing idle archive SHA256 remains
`139952bee5243c64c766744a350ab1ae1f4269aa427d20954467311e450b10b3`.
No new archive build or package version is claimed.

## Validation

- New `passive_asset_contract_tests.py`: 23 Python unittest methods with
  three-builder and field subcases pass. Mutations cover the three original
  acceptance defects, changed/missing visual bindings, invalid handles,
  wrong root/extra AI components, appearance/instance overrides, and matching
  copies with zero draw masks or shifted/rotated animated-root/mesh transforms.
- Existing `passive_hittable_asset_tests.py`: 9 tests pass.
- CTest `npc_projection_asset_contract`, `passive_hittable_asset` and
  `passive_asset_contract`: 3/3 pass in a fresh Windows configure. The two Python
  suites retain the existing Python-available CMake condition.
- Debian CI explicitly installs Python 3 so these conditional suites also run
  in its minimal container. A green build with Python unavailable would omit
  their coverage; final CI logs must show `passive_asset_contract` executed.
- All three historical WolvenKit roundtrips pass the stricter gates.
- Independent review reproduced the matching-copy draw-mask/transform hole in
  the first patch. Pinning the reviewed values and adding paired-copy mutations
  closes it. Final independent rerun passed 23 + 9 tests and all three roundtrips.
- `git diff --check` passes. Ignored local evidence is in
  `build/passive-assets/ctest.log`, `source-roundtrip-regression.log` and
  `final-roundtrip.log`.

No native rebuild or live-game test was needed for this Python-only source
validation change. Actual visibility, animation, collision, absence of autonomous
JOINER behavior and HOST/JOINER appearance matching still require their separate
engine and two-PC gates. This contribution does not qualify full NPC replication.

## Exact file ownership

- `scripts/build-passive-idle-archive.py`: shared supported-visual gate and idle use.
- `scripts/build-passive-encounter-archive.py`: encounter gate use.
- `scripts/build-passive-hittable-archive.py`: hittable gate use.
- `tests/passive_asset_contract_tests.py`: source-only mutation regressions.
- `tests/CMakeLists.txt`: register the new Python test.
- `.github/workflows/build.yml`: install the interpreter in Debian CI.
- This validation note.

No protocol, networking, session bridge or authoritative backend changes.
