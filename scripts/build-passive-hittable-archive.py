"""Build the query-only passive entity; the encounter graph is an external dependency.

The entity adds one kinematic, query-only capsule to the authored encounter
template. It remains entEntity and cannot receive native NPC damage. Only the
one authored entity resource is packed. A build is not live collision evidence.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

spec = importlib.util.spec_from_file_location("idle_builder", Path(__file__).with_name("build-passive-idle-archive.py"))
idle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idle)
require, sha = idle.require, idle.sha
ENTITY = r"base\cp2077coop\entities\cp2077coop_networkhumanoid_hittable.ent"
GRAPH = r"base\cp2077coop\animations\networkhumanoid_encounter.animgraph"
# Installed 2.31 dummy_man_base.ent has a query-only entColliderComponent with
# the NPC Hitbox preset, mask2=2 and zero simulation masks. The name describes
# a physics filter, not an NPC component. See PHYSICAL_SHOTS.md for evidence.
QUERY_MASK = 1 << 1


def validate(path):
    doc = json.loads(path.read_text(encoding="utf-8-sig"))
    handles = {x["HandleId"]: x["Data"] for x in idle.walk(doc) if "HandleId" in x and "Data" in x}

    def deref(value):
        return value["Data"] if "Data" in value else handles[value["HandleRefId"]]

    require(doc["Data"]["EmbeddedFiles"] == [], "No embedded resource bytes")
    root = doc["Data"]["RootChunk"]
    require(root["entity"]["Data"]["$type"] == "entEntity", "Must remain non-NPC entEntity")
    types = ["entAnimatedComponent", "entSkinnedMeshComponent", "entAnimationControllerComponent", "entColliderComponent"]
    chunks = root["compiledData"]["Data"]["Chunks"]
    require([c["$type"] for c in chunks] == ["entEntity"] + types, "No unexpected compiled components")
    require([c["$type"] for c in root["components"]] == types, "No unexpected template components")
    for components in (root["components"], chunks[1:]):
        animated, mesh, controller, collider = components
        require(idle.resource_path(animated["graph"]) == GRAPH, "Must reference the separately built encounter graph")
        require(idle.resource_path(animated["rig"]) == idle.RIG, "Unexpected rig")
        require(controller["animDatabaseCollection"]["animDatabases"] == [], "No gameplay animation databases")
        require(idle.resource_path(controller["actionAnimDatabaseRef"]) == "0", "No gameplay action database")
        require(collider["simulationType"] == "Kinematic" and collider["isEnabled"] == 1 and collider["startInactive"] == 0, "Enabled kinematic capsule required")
        require(len(collider["colliders"]) == 1, "Exactly one capsule required")
        shape = deref(collider["colliders"][0])
        require(shape["$type"] == "physicsColliderCapsule" and shape["isQueryShapeOnly"] == 1, "Must be a query-only capsule")
        require(abs(shape["radius"] - 0.35) < 0.00001 and abs(shape["height"] - 1.1) < 0.00001, "Unexpected capsule bounds")
        require(abs(shape["localToBody"]["position"]["Z"] - 0.9) < 0.00001, "Unexpected capsule offset")
        data = deref(collider["filterData"])
        require(shape["filterData"] is None, "Shape must inherit the component's verified NPC Hitbox filter")
        query = data.get("queryFilter", {})
        simulation = data.get("simulationFilter", {})
        require(int(query.get("mask1", -1)) == 0 and int(query.get("mask2", -1)) == QUERY_MASK,
                "Cooked query mask must expose only AI: mask1=0, mask2=2")
        require(int(simulation.get("mask1", -1)) == 0 and int(simulation.get("mask2", -1)) == 0,
                "Cooked simulation masks must remain zero")
        require(data["preset"]["$value"] == "NPC Hitbox", "Use only the verified query-only NPC Hitbox preset")
        require(data["customFilterData"] is None, "Do not override the verified preset with custom filter data")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entity-json", required=True, type=Path)
    parser.add_argument("--wolvenkit", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    require(args.wolvenkit.is_file() and sha(args.wolvenkit) == idle.CLI_SHA256, "Use official WolvenKit Console 9.0.1")
    validate(args.entity_json)
    require(not args.output_dir.exists(), "Choose a new output directory")
    output = args.output_dir.resolve()
    output.mkdir(parents=True)
    staging = output / "CP2077Coop_EncounterHittable"
    relative = Path(ENTITY.replace("\\", "/"))
    copied = output / "raw" / (str(relative) + ".json")
    copied.parent.mkdir(parents=True)
    shutil.copyfile(args.entity_json, copied)
    binary = staging / relative
    binary.parent.mkdir(parents=True)
    log = output / "build.log"

    def run(*argv):
        command = [str(args.wolvenkit.resolve()), *map(str, argv)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf8", errors="replace")
        with log.open("a", encoding="utf8") as stream:
            stream.write(json.dumps(command) + "\n" + result.stdout + result.stderr + "\n")
        require(result.returncode == 0, f"WolvenKit failed; see {log}")
        return result.stdout

    run("convert", "deserialize", copied, "-o", binary.parent)
    require(binary.is_file(), "No entity binary produced")
    roundtrip = output / "roundtrip"
    roundtrip.mkdir()
    run("convert", "serialize", binary, "-o", roundtrip)
    validate(roundtrip / (relative.name + ".json"))
    require(len(list(staging.rglob("*.*"))) == 1, "Only the authored entity may be packed")
    packed = output / "out"
    packed.mkdir()
    run("pack", staging, "-o", packed)
    archive = packed / "CP2077Coop_EncounterHittable.archive"
    listing = run("archive", archive, "--list")
    require(listing.strip().splitlines() == [ENTITY], "Unexpected archive payload")
    (output / "archive-list.txt").write_text(listing, encoding="utf8")
    unpacked = output / "unpacked"
    unpacked.mkdir()
    run("unbundle", archive, "-o", unpacked)
    require(sha(unpacked / relative) == sha(binary), "Unpacked payload mismatch")
    record = {
        "utc": datetime.now(timezone.utc).isoformat(),
        "status": "OFFLINE_BUILT_NOT_INSTALLED_OR_LIVE_VERIFIED",
        "archive": str(archive), "archive_sha256": sha(archive),
        "source_sha256": sha(args.entity_json), "resource_sha256": sha(binary),
        "external_dependency": GRAPH, "bundled_vanilla_resources": [],
        "roundtrip_query_only_contract": "PASS", "unpack_resource_parity": "PASS",
        "query_profile": {"collision_group": "AI", "collision_group_index": 1, "preset": "NPC Hitbox",
                          "query_mask1": 0, "query_mask2": QUERY_MASK,
                          "simulation_mask1": 0, "simulation_mask2": 0,
                          "shape_filter": "null_inherits_component", "custom_filter": None, "query_only": True},
        "scope": "One query-only capsule on entEntity; physical ray detection and filter behavior still need live validation",
    }
    (output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf8")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
