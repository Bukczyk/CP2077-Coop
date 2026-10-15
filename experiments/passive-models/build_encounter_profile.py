"""Build one private authored encounter profile; never install or activate it.

The unchanged encounter graph is an external authored prerequisite. Vanilla
mesh, rig and animation payloads are external references, never archive content.
This asset prerequisite does not enable the idle fixture's reaction/death path.
"""
from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from types import MappingProxyType


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("encounter_contract", ROOT / "scripts/build-passive-encounter-archive.py")
encounter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(encounter)
idle = encounter.idle
require, sha = idle.require, idle.sha
REFERENCE = ROOT / "experiments/shared-encounter/assets/raw/base/cp2077coop/entities/cp2077coop_networkhumanoid_encounter.ent.json"
GRAPH_SOURCE = ROOT / "experiments/shared-encounter/assets/raw/base/cp2077coop/animations/networkhumanoid_encounter.animgraph.json"
REFERENCE_LF_SHA256 = "6d86e3be6c538ea886e3cff696739a4aadcb4b836ccaa90772b8e9f25144793f"
GRAPH_LF_SHA256 = "5e73fe0bebab9901f4d610143ff6d55e8bd153b63606417c280e4e9b846b5675"


def source_lf_sha(path):
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


@dataclass(frozen=True)
class Profile:
    entity: str
    source: Path
    mesh: str
    rig: str
    sets: tuple[str, ...]


PROFILES = MappingProxyType({
    "judy_default": Profile(encounter.ENTITY, REFERENCE, idle.MESH, idle.RIG, tuple(encounter.SETS)),
    "mitch_default": Profile(r"base\cp2077coop\entities\cp2077coop_networkhumanoid_mitch_encounter.ent",
        Path(__file__).parent / "raw/base/cp2077coop/entities/cp2077coop_networkhumanoid_mitch_encounter.ent.json",
        r"base\characters\appearances\main_npc\proxy\mitch_default\mitch_default.mesh",
        r"base\characters\base_entities\man_base\man_base.rig",
        tuple(r"base\animations\npc\gameplay\man_average\gang\unarmed\ma_gang_unarmed_" + suffix + ".anims"
              for suffix in ("locomotion_combat", "reaction_ranged_impact", "reaction_ranged_death"))),
})


def get_profile(name):
    require(isinstance(name, str) and name in PROFILES, "Unknown encounter profile")
    return PROFILES[name]


def resource(path, flags):
    return {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": path}, "Flags": flags}


def resolved_dependencies(profile):
    # Same ordered Soft table in the authored Judy source and WK 9.0.1 output.
    # Rig is an explicit Obligatory import, not an invented extra table entry.
    return [resource(path, "Soft") for path in (profile.mesh, encounter.GRAPH, *profile.sets)]


def normalized_data(data):
    """Resolve equivalent authored/WK handles without erasing ambiguous input."""
    handles = {}
    for value in idle.walk(data):
        if "HandleId" in value:
            require(set(value) == {"HandleId", "Data"}, "Ambiguous encounter handle definition")
            key = value["HandleId"]
            require(isinstance(key, str), "Invalid encounter handle identity")
            require(key not in handles or handles[key] == value["Data"], "Conflicting encounter handle definitions")
            handles[key] = value["Data"]
        if "HandleRefId" in value:
            require(set(value) == {"HandleRefId"} and isinstance(value["HandleRefId"], str),
                    "Ambiguous encounter handle reference")

    def resolve(value, active=()):
        if isinstance(value, list):
            return [resolve(v, active) for v in value]
        if not isinstance(value, dict):
            return value
        if "HandleId" in value or "HandleRefId" in value:
            key = value.get("HandleId", value.get("HandleRefId"))
            require(key in handles, "Unresolved encounter handle")
            require(key not in active, "Cyclic encounter handle")
            return resolve(handles[key], active + (key,))
        return {key: resolve(child, active) for key, child in value.items()}

    return resolve(data)


def validate(profile_name, entity_path=None, graph_path=GRAPH_SOURCE):
    profile = get_profile(profile_name)
    require(source_lf_sha(REFERENCE) == REFERENCE_LF_SHA256, "Reviewed Judy encounter source changed")
    require(source_lf_sha(graph_path) == GRAPH_LF_SHA256, "Use the unchanged reviewed encounter graph")
    source = Path(entity_path) if entity_path is not None else profile.source
    doc = json.loads(source.read_text(encoding="utf-8-sig"))
    reference = json.loads(REFERENCE.read_text(encoding="utf-8-sig"))
    require(doc["Data"]["EmbeddedFiles"] == [], "No embedded encounter payloads")
    canonical = copy.deepcopy(doc)
    # Validate handle syntax before normalization can hide a contradictory copy.
    normalized_data(canonical["Data"])
    root = canonical["Data"]["RootChunk"]
    require(root["$type"] == "entEntityTemplate", "Expected authored entity template")
    require(root["entity"]["Data"]["$type"] == "entEntity", "Encounter profile must remain entEntity")
    types = ["entAnimatedComponent", "entSkinnedMeshComponent", "entAnimationControllerComponent"]
    chunks = root["compiledData"]["Data"]["Chunks"]
    require([v["$type"] for v in chunks] == ["entEntity"] + types, "Unexpected compiled encounter component")
    require([v["$type"] for v in root["components"]] == types, "Unexpected template encounter component")
    for components in (root["components"], chunks[1:]):
        animated, mesh, _ = components
        require(mesh["mesh"] == resource(profile.mesh, "Default"), "Encounter profile mesh mismatch")
        require(animated["rig"] == resource(profile.rig, "Obligatory"), "Encounter profile rig mismatch")
        require(animated["graph"] == resource(encounter.GRAPH, "Obligatory"), "Encounter graph reference mismatch")
        gameplay = animated["animations"]["gameplay"]
        require(len(gameplay) == 3, "Exactly idle, impact and death sets required")
        require([v["animSet"] for v in gameplay] == [resource(path, "Default") for path in profile.sets],
                "Encounter profile animation sets mismatch")
        mesh["mesh"] = resource(idle.MESH, "Default")
        animated["rig"] = resource(idle.RIG, "Obligatory")
        for entry, path in zip(gameplay, encounter.SETS):
            entry["animSet"] = resource(path, "Default")
    require(root.get("resolvedDependencies") == resolved_dependencies(profile), "Encounter dependency table mismatch")
    root["resolvedDependencies"] = resolved_dependencies(PROFILES["judy_default"])
    with tempfile.TemporaryDirectory(prefix="cp2077_encounter_contract_") as tmp:
        candidate = Path(tmp) / "canonical.ent.json"
        candidate.write_text(json.dumps(canonical), encoding="utf-8")
        # Reuse existing passive/no-AI/visual/binding/graph contract unchanged.
        encounter.validate_sources(candidate, Path(graph_path))
    # WK 9.0.1 changes handle forms, not Data semantics, for this authored subset.
    # Full equality also pins enabled binding/type/masks, controller fields and
    # serialization metadata, so paired-copy changes cannot bypass old checks.
    require(normalized_data(canonical["Data"]) == normalized_data(reference["Data"]),
            "Encounter non-profile Data differs from reviewed Judy source")
    return profile


def build(profile_name, wolvenkit, output_dir, entity_path=None, graph_path=GRAPH_SOURCE):
    profile = validate(profile_name, entity_path, graph_path)
    source = Path(entity_path) if entity_path is not None else profile.source
    wolvenkit, output = Path(wolvenkit).resolve(), Path(output_dir).resolve()
    require(not output.exists(), "Choose a new output directory")
    require(wolvenkit.is_file() and sha(wolvenkit) == idle.CLI_SHA256, "Use pinned official WolvenKit Console 9.0.1")
    inputs = (source, Path(graph_path), REFERENCE, Path(__file__),
              ROOT / "scripts/build-passive-encounter-archive.py", ROOT / "scripts/build-passive-idle-archive.py")
    hashes = {str(path.resolve()): sha(path) for path in inputs}
    output.mkdir(parents=True)
    archive_name = "CP2077Coop_EncounterProfile_" + profile_name
    staging = output / archive_name
    relative = Path(profile.entity.replace("\\", "/"))
    copied = output / "raw" / (str(relative) + ".json")
    copied.parent.mkdir(parents=True)
    shutil.copyfile(source, copied)
    binary = staging / relative
    binary.parent.mkdir(parents=True)
    log = output / "build.log"

    def run(*arguments):
        command = [str(wolvenkit), *map(str, arguments)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
        with log.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(command) + "\n" + result.stdout + result.stderr + "\n")
        require(result.returncode == 0, f"WolvenKit failed; see {log}")
        return result.stdout

    run("convert", "deserialize", copied, "-o", binary.parent)
    require(binary.is_file(), "Authored encounter entity missing")
    roundtrip = output / "roundtrip"
    roundtrip.mkdir()
    run("convert", "serialize", binary, "-o", roundtrip)
    validate(profile_name, roundtrip / (relative.name + ".json"), graph_path)
    require([path.relative_to(staging) for path in staging.rglob("*") if path.is_file()] == [relative],
            "Only the authored encounter entity may be staged")
    packed = output / "out"
    packed.mkdir()
    run("pack", staging, "-o", packed)
    archive = packed / (archive_name + ".archive")
    require(archive.is_file(), "Encounter archive missing")
    listing = run("archive", archive, "--list")
    require(listing.strip().splitlines() == [profile.entity], "Unexpected encounter archive resource")
    (output / "archive-list.txt").write_text(listing, encoding="utf-8")
    unpacked = output / "unpacked"
    unpacked.mkdir()
    run("unbundle", archive, "-o", unpacked)
    require(sha(unpacked / relative) == sha(binary), "Encounter archive resource parity failed")
    require(all(sha(Path(path)) == digest for path, digest in hashes.items()), "Input changed during encounter build")
    manifest = {
        "utc": datetime.now(timezone.utc).isoformat(), "profile": profile_name,
        "status": "PRIVATE_ASSET_PREREQUISITE_NOT_INSTALLED_OR_LIVE_VERIFIED",
        "archive": str(archive), "archive_sha256": sha(archive),
        "resources": {profile.entity: sha(binary)}, "source_sha256": hashes,
        "wolvenkit_cli_sha256": sha(wolvenkit), "inputs_unchanged": True,
        "roundtrip_encounter_contract": "PASS", "unpack_resource_parity": "PASS",
        "external_authored_dependency": encounter.GRAPH,
        "external_installed_dependencies": [profile.mesh, profile.rig, *profile.sets],
        "bundled_vanilla_resources": [], "runtime_selected": False,
        "fixture_reactions_enabled": False, "live_animation_verified": False,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=tuple(PROFILES), default="judy_default")
    parser.add_argument("--entity-json", type=Path)
    parser.add_argument("--graph-json", type=Path, default=GRAPH_SOURCE)
    parser.add_argument("--wolvenkit", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.profile, args.wolvenkit, args.output_dir, args.entity_json, args.graph_json), indent=2))


if __name__ == "__main__":
    main()
