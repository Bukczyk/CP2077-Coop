# Offline validation: passive model profiles

UTC date: 2026-10-15. Branch: `feat/passive-mitch-profile`.
Source base: `69f059896fa4049382ca14b06f08ff7d2d9e9bee`.
Scope: authored entity JSON, separate profile builder, focused Python tests and
CTest registration. No C++/REDscript/runtime code, game install or package changed.

## Verified

- 22 profile mutation tests pass. These cover known/unknown profiles, wrong
  mesh/rig/animset, template/compiled drift, extra/hidden resources, graph pin,
  unsafe inheritance/AI, dependency-table mismatches, unchanged Judy source and
  LF/CRLF checkout compatibility.
- The existing 23 asset-contract and 9 hittable-asset tests pass.
- A fresh CMake configuration ran all three focused CTest entries: 3/3 pass.
- Both profiles compiled with pinned WolvenKit 9.0.1, roundtripped through its
  serializer and passed the current strict profile validator.
- Each archive lists exactly one authored entity. Unpacked bytes match the
  staged entity. Both builds confirm original source inputs remained unchanged.
- No game binary, mesh, animation, rig or texture payload was committed or
  included in either archive. The authored idle graph is an external dependency.

No native/REDscript code changed, so these results are asset compilation and
offline Python validation, not a Windows plugin build or live game result.

## Current private artifacts

Evidence root: `D:\Downloads\syncfix\bench-artifacts\20261015-passive-model-audit`.
Each build directory includes `manifest.json`, `build.log`, `archive-list.txt`,
roundtrip JSON, staged resource, unpacked resource and archive.

| Item | SHA256 |
| --- | --- |
| Pinned WolvenKit CLI | `7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738` |
| Corrected authored Mitch JSON | `c2a8e2ad8e800501a93aebcf7b6ea5ea9207016c2a345e73b8389f954ea35287` |
| Existing authored Judy JSON (unchanged) | `f6485a1cad7ec22905f93abf7f305a460fb12511a60269c938ad0770e884527b` |
| Existing authored idle graph JSON (unchanged) | `e448765251286661ec0e877dbecdd8e96ea26c6d0d97d8184f0992c8a298fcc3` |
| `mitch-build-02` archive | `70a51f19745c76d406cfea0bd6ab473328747003707d7ea4d869b2a37883812b` |
| `mitch-build-02` compiled entity | `697e9cd3f4ab9f005c9a92dd73854b940d52fac8d6c91cb1cb410e6caa3331f0` |
| `judy-build-02` archive | `b7fd2bb69129a7f2c7fe3f83b11b57d1d1a6c3e5b618404725f70e361c04d857` |
| `judy-build-02` compiled entity | `918e49cd77231e0e98a3e7610582da4ad69a624d96b0c123e6cc645615f225b0` |

The Judy entity bytes match its earlier `judy-build-01` output exactly; archive
container hashes differ between packing runs. Independent review reran the 53
Python tests, checked actual CLI listings, unpacked resource hashes and current
roundtrip validation, and verified that an existing output directory is refused
without changing its contents. The old male roundtrip now fails the corrected
dependency-table gate as expected.

These are actual private build/input hashes on Windows. Git normalizes the
authored JSON to LF. The source guard uses the normalized graph hash
`bb7065954b0e37c7649c354866e138ad5e76dc9ee9d1d17bdadc43fc78267c07` and the
unchanged Judy test uses `04c2e236f934e41cd781e1ca5427d2b40b3ee76eaf2d1abf5cd2bf4e4e578287`.
The final portability regression adds one test, for 54 Python tests total.
An independent LF-only staging copy reran the complete 22-test profile suite;
both compiled `build-02` roundtrips also pass the final normalized-content gate.

The Mitch archive listing is exactly:

```text
base\cp2077coop\entities\cp2077coop_networkhumanoid_mitch.ent
```

The Judy archive listing is exactly:

```text
base\cp2077coop\entities\cp2077coop_networkhumanoid.ent
```

## Review correction and separate baseline gap

Independent review found that the first male candidate still carried Judy mesh
and female animset references in `resolvedDependencies`. That was a concrete
metadata mismatch; no live rendering failure was inferred. `mitch-build-01` is
superseded and must not be used. The corrected source and `mitch-build-02` use
the male references, and new tests reject wrong-profile table entries.

The original idle builder validates component references but does not enforce
this exact resolved-dependency table. Its current Judy source is consistent.
This experiment adds the stricter gate for both explicit profiles without
editing that production builder. Tightening the baseline builder is a separate
reviewed task if desired; this slice does not claim that gap is fixed globally.

## Unperformed gates

No game launch, installation, spawn, visible model, animation, deformation,
cleanup or two-PC test was performed. No production profile selector exists.
No arbitrary NPC appearance parity, weapon/ADS fidelity or HOST matching is
claimed. The archives are private partial experiments, not released mod versions.
