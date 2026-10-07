# Passive NetworkHumanoid game-side validation

Owner: KyleBuildsAI. Session date: 2026-10-06 Pacific; work continues 2026-10-07 UTC.
Branch: `feat/passive-humanoid-validation`. Status: experiment in progress.

## Starting sources and ownership

- Upstream main: `d3670d94d96c40fe4f24e6e983d343a09f50d38f`.
- Bukczyk's passive checkpoint: `7768923d92db8c7ab0f654dc80d896994edeabbc`.
- PR4 current-main integration: `813922c217e7c97f4c5e6feb5e074930a45d84d5`.
- KyleBuildsAI owns this validation note, the static CET adapter and its tests,
  its integration in `runtime/session/cet/CP2077Coop/init.lua`, related experimental
  asset corrections, and isolated game probes. `tests/CMakeLists.txt` retains all
  inherited suites. Shared native declarations/configuration are inherited from
  Bukczyk's checkpoint; any additional bridge changes require explicit review.
- Bukczyk retains `shared/`, `SessionServer/`, wire contracts, delivery/deduplication
  and reconnect backend ownership. This branch does not implement combat packets.

## Gates

1. Build, adapter regression tests and isolated script compilation.
2. Actual entity creation, visible rendering, exact identity and movement.
3. Passive idle, owned-entity removal, reconnect and recreation.
4. Separate HOST hook probes for actual hits, damage and death.

The asset is a fixed Judy-based visual, not arbitrary NPC appearance replication.
It has no hit collider/gameplay components. Visual success alone proves neither
shootability nor shared combat. Tests below must distinguish source inspection,
mock tests, game-side fixtures, two-game checks and two-PC qualification.

NPC replication remains opt-in. Use controlled test-owned actors only; ambient
population suppression stays disabled. Preserve current saves/settings and the
public v0.0.37 / alpha.5 package. No release qualification is claimed here.

## Evidence

Pending live checks. Private evidence is stored in the local
`bench-artifacts/20261006-shared-encounter` task folder, not committed game logs.
