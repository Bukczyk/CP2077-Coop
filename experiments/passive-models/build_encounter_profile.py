"""Build one private authored encounter profile; never install or activate it.

The default encounter graph is an external authored prerequisite. An explicit
defeated_hold mode bundles its separate authored sampled graph and entity only.
Vanilla mesh, rig and animation payloads remain external references. Neither
mode selects a runtime profile or changes controller semantics.
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
DEFEATED_GRAPH = r"base\cp2077coop\animations\networkhumanoid_defeated_hold.animgraph"
DEFEATED_GRAPH_SOURCE = Path(__file__).parent / "raw" / (DEFEATED_GRAPH.replace("\\", "/") + ".json")
DEFEATED_CLIP = "defeated_loop_01"
DEFEATED_PROGRESS = "cp_coop_defeated_progress"
DEFEATED_DURATION = 10.3000002
# Read-only game 2.31 metadata. Resource hashes identify observed payloads; no
# proprietary animation bytes are embedded, copied or inferred from these IDs.
DEFEATED_ANIMATIONS = MappingProxyType({
    "judy_default": (r"base\animations\npc\gameplay\woman_average\gang\unarmed\wa_gang_unarmed_reaction_defeated.anims",
        "866b9e1e6f1a043c95a697e02ae3be6a53898a60ca494c5888384bdaf900c16a"),
    "mitch_default": (r"base\animations\npc\gameplay\man_average\gang\unarmed\ma_gang_unarmed_reaction_defeated.anims",
        "3fc33c80788b9a863f71df3ebe4ce76fe0c83b4018b2699124bc51cb149c81aa"),
})


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


def get_presentation(value):
    require(isinstance(value, str) and value in ("encounter", "defeated_hold"), "Unknown presentation mode")
    return value


def defeated_profile(name):
    base = get_profile(name)  # one existing model identity allowlist
    entity = (r"base\cp2077coop\entities\cp2077coop_networkhumanoid_defeated.ent" if name == "judy_default"
              else r"base\cp2077coop\entities\cp2077coop_networkhumanoid_mitch_defeated.ent")
    return Profile(entity, Path(__file__).parent / "raw" / (entity.replace("\\", "/") + ".json"),
                   base.mesh, base.rig, (DEFEATED_ANIMATIONS[name][0],))


def _reviewed_sources():
    require(source_lf_sha(REFERENCE) == REFERENCE_LF_SHA256, "Reviewed Judy encounter source changed")
    require(source_lf_sha(GRAPH_SOURCE) == GRAPH_LF_SHA256, "Reviewed encounter graph changed")
    encounter.validate_sources(REFERENCE, GRAPH_SOURCE)


def defeated_dependencies(profile):
    return [resource(path, "Soft") for path in (profile.mesh, DEFEATED_GRAPH, *profile.sets)]


def expected_defeated_entity(name):
    """Exact allowed transformation of the pinned passive encounter source."""
    _reviewed_sources()
    profile = defeated_profile(name)
    doc = json.loads(REFERENCE.read_text(encoding="utf-8-sig"))
    root = doc["Data"]["RootChunk"]
    for components in (root["components"], root["compiledData"]["Data"]["Chunks"][1:]):
        animated, mesh, _ = components
        mesh["mesh"] = resource(profile.mesh, "Default")
        animated["rig"] = resource(profile.rig, "Obligatory")
        animated["graph"] = resource(DEFEATED_GRAPH, "Obligatory")
        gameplay = animated["animations"]["gameplay"]
        animated["animations"]["gameplay"] = [copy.deepcopy(gameplay[0])]
        animated["animations"]["gameplay"][0]["animSet"] = resource(profile.sets[0], "Default")
    root["resolvedDependencies"] = defeated_dependencies(profile)
    return doc


def expected_defeated_graph():
    """Reuse proven authored node shapes, not a vanilla graph or a death alias."""
    _reviewed_sources()
    doc = json.loads(GRAPH_SOURCE.read_text(encoding="utf-8-sig"))
    graph = doc["Data"]["RootChunk"]
    nodes = {v["HandleId"]: copy.deepcopy(v["Data"]) for v in idle.walk(graph) if "HandleId" in v}
    root, output, sample, progress = (nodes[key] for key in ("0", "1", "4", "7"))
    sample["animation"]["$value"] = DEFEATED_CLIP
    progress["variableName"]["$value"] = DEFEATED_PROGRESS
    # WK9.0.1 resolves references as it reads: nested definitions precede the
    # root/nodesToInit references, matching the reviewed encounter serialization.
    sample["progressLink"] = {"$type": "animFloatLink", "node": {"HandleId": "3", "Data": progress}}
    output["node"] = {"$type": "animPoseLink", "node": {"HandleId": "2", "Data": sample}}
    root["nodes"] = [{"HandleId": "1", "Data": output}] + [{"HandleRefId": key} for key in ("2", "3")]
    graph["nodesToInit"] = [{"HandleId": "0", "Data": root}] + [{"HandleRefId": key} for key in ("1", "2", "3")]
    graph["rootNode"] = {"HandleRefId": "0"}
    variable = nodes["11"]
    variable["name"]["$value"] = DEFEATED_PROGRESS
    # The existing progress field has exact value/default0 and normalized0..1.
    # It may be sampled later; no time source or auto-loop is authored here.
    container = nodes["9"]
    container["floatVariables"] = [{"HandleId": "5", "Data": variable}]
    graph["variables"] = {"HandleId": "4", "Data": container}
    # Explicit WK9.0.1 defaults observed after compiling these node shapes.
    # Pin them in the authored graph too; never discard unknown roundtrip fields.
    none = {"$type": "CName", "$storage": "string", "$value": "None"}
    color = {"$type": "Color", "Alpha": 0, "Blue": 0, "Green": 0, "Red": 0}
    for node in (root, output, sample, progress):
        node.update(poseInfoLogger=None, visAxes=0, visMask=None, visNames=0,
                    visPostPose=0, visPostPoseColor=copy.deepcopy(color),
                    visPrePose=0, visPrePoseColor=copy.deepcopy(color),
                    visRigPartMask=copy.deepcopy(none), visWhenActive=0)
    sample.update(applyInertializationOnAnimSetSwap=1, clipEnd=0, clipFront=0,
                  convertToAdditive=0, debug=0, debugFootsteps=0, motionProvider=None,
                  frameLink={"$type": "animFloatLink", "node": None},
                  timeLink={"$type": "animFloatLink", "node": None})
    for field in ("animLoopEventName", "clipEndByEvent", "clipFrontByEvent",
                  "popDataByTag", "pushDataByTag", "pushSafeCutTag"):
        sample[field] = copy.deepcopy(none)
    variable["enableDebug"] = 0
    graph["staticCommandsRig"] = {
        "DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"},
        "Flags": "Default"}
    return doc


def _same_data(actual, expected):
    # WK may spell a numeric zero as 0.0, but Bool is not a numeric flag/value.
    if type(expected) in (int, float):
        return type(actual) in (int, float) and actual == expected
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        return actual.keys() == expected.keys() and all(_same_data(actual[k], v) for k, v in expected.items())
    if isinstance(expected, list):
        return len(actual) == len(expected) and all(_same_data(a, b) for a, b in zip(actual, expected))
    return actual == expected


def graph_alias_signature(data):
    """Canonical handle numbering without conflating distinct native objects.

    Inline and reference forms resolve to the same canonical identity, but a
    copied node with a new handle remains distinct even when its Data is equal.
    normalized_data has already checked syntax, conflicts and cycles.
    """
    handles = {v["HandleId"]: v["Data"] for v in idle.walk(data) if "HandleId" in v}
    identifiers, definitions = {}, []

    def visit(value):
        if isinstance(value, list):
            return [visit(v) for v in value]
        if not isinstance(value, dict):
            return value
        if "HandleId" in value or "HandleRefId" in value:
            key = value.get("HandleId", value.get("HandleRefId"))
            if key not in identifiers:
                identifiers[key] = len(definitions)
                definitions.append(None)
                definitions[identifiers[key]] = visit(handles[key])
            return {"canonicalHandle": identifiers[key]}
        return {key: visit(value[key]) for key in sorted(value)}

    root = visit(data)
    return {"root": root, "definitions": definitions}


def _exact_defeated_data(document, expected, label):
    require(document["Header"]["WolvenKitVersion"] == "9.0.1", "Source schema must be WolvenKit 9.0.1")
    for value in idle.walk(document["Data"]):
        for field in ("HandleId", "HandleRefId"):
            if field in value:
                require(isinstance(value[field], str) and value[field].isascii() and value[field].isdigit(),
                        "Invalid defeated handle identity")
    normalized, expected_normalized = normalized_data(document["Data"]), normalized_data(expected["Data"])
    require(_same_data(normalized, expected_normalized),
            "Defeated " + label + " differs from reviewed exact contract")
    if label == "graph":
        require(_same_data(graph_alias_signature(document["Data"]), graph_alias_signature(expected["Data"])),
                "Defeated graph active/initialized handle identity mismatch")


def validate_defeated(name, entity_path=None, graph_path=None):
    profile = defeated_profile(name)
    entity_path = profile.source if entity_path is None else Path(entity_path)
    graph_path = DEFEATED_GRAPH_SOURCE if graph_path is None else Path(graph_path)
    entity = json.loads(entity_path.read_text(encoding="utf-8-sig"))
    graph = json.loads(graph_path.read_text(encoding="utf-8-sig"))
    _exact_defeated_data(entity, expected_defeated_entity(name), "entity")
    _exact_defeated_data(graph, expected_defeated_graph(), "graph")
    # Exact equivalence to the allowed transformation above preserves the old
    # no-AI/visual/binding gate without monkeypatching imported constants. Restore
    # only the verified resource substitutions on a private canonical copy.
    canonical = copy.deepcopy(entity)
    root = canonical["Data"]["RootChunk"]
    reference = json.loads(REFERENCE.read_text(encoding="utf-8-sig"))["Data"]["RootChunk"]
    for components in (root["components"], root["compiledData"]["Data"]["Chunks"][1:]):
        animated, mesh, _ = components
        mesh["mesh"] = resource(idle.MESH, "Default")
        animated["rig"] = resource(idle.RIG, "Obligatory")
        animated["graph"] = resource(encounter.GRAPH, "Obligatory")
        animated["animations"]["gameplay"] = copy.deepcopy(reference["components"][0]["animations"]["gameplay"])
    root["resolvedDependencies"] = resolved_dependencies(PROFILES["judy_default"])
    with tempfile.TemporaryDirectory(prefix="cp2077_defeated_contract_") as tmp:
        candidate = Path(tmp) / "canonical.ent.json"
        candidate.write_text(json.dumps(canonical), encoding="utf-8")
        encounter.validate_sources(candidate, GRAPH_SOURCE)
    return profile


def validate(profile_name, entity_path=None, graph_path=None, presentation="encounter"):
    if get_presentation(presentation) == "defeated_hold":
        return validate_defeated(profile_name, entity_path, graph_path)
    graph_path = GRAPH_SOURCE if graph_path is None else Path(graph_path)
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


def build(profile_name, wolvenkit, output_dir, entity_path=None, graph_path=None, presentation="encounter"):
    mode = get_presentation(presentation)
    graph_path = Path(graph_path) if graph_path is not None else (DEFEATED_GRAPH_SOURCE if mode == "defeated_hold" else GRAPH_SOURCE)
    profile = validate(profile_name, entity_path, graph_path, mode)
    source = Path(entity_path) if entity_path is not None else profile.source
    wolvenkit, output = Path(wolvenkit).resolve(), Path(output_dir).resolve()
    require(not output.exists(), "Choose a new output directory")
    require(wolvenkit.is_file() and sha(wolvenkit) == idle.CLI_SHA256, "Use pinned official WolvenKit Console 9.0.1")
    inputs = (source, Path(graph_path), REFERENCE, GRAPH_SOURCE, Path(__file__),
              ROOT / "scripts/build-passive-encounter-archive.py", ROOT / "scripts/build-passive-idle-archive.py")
    hashes = {str(path.resolve()): sha(path) for path in inputs}
    output.mkdir(parents=True)
    archive_name = ("CP2077Coop_DefeatedHoldProfile_" if mode == "defeated_hold" else "CP2077Coop_EncounterProfile_") + profile_name
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
    resources = {profile.entity: binary}
    if mode == "defeated_hold":
        graph_relative = Path(DEFEATED_GRAPH.replace("\\", "/"))
        graph_copy = output / "raw" / (str(graph_relative) + ".json")
        graph_copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(graph_path, graph_copy)
        graph_binary = staging / graph_relative
        graph_binary.parent.mkdir(parents=True, exist_ok=True)
        run("convert", "deserialize", graph_copy, "-o", graph_binary.parent)
        require(graph_binary.is_file(), "Authored defeated graph missing")
        run("convert", "serialize", graph_binary, "-o", roundtrip)
        resources[DEFEATED_GRAPH] = graph_binary
        validate(profile_name, roundtrip / (relative.name + ".json"), roundtrip / (graph_relative.name + ".json"), mode)
    else:
        validate(profile_name, roundtrip / (relative.name + ".json"), graph_path)
    require({path.relative_to(staging) for path in staging.rglob("*") if path.is_file()}
            == {Path(name.replace("\\", "/")) for name in resources}, "Only the exact authored resources may be staged")
    packed = output / "out"
    packed.mkdir()
    run("pack", staging, "-o", packed)
    archive = packed / (archive_name + ".archive")
    require(archive.is_file(), "Encounter archive missing")
    listing = run("archive", archive, "--list")
    require(sorted(listing.strip().splitlines()) == sorted(resources), "Unexpected encounter archive resource")
    (output / "archive-list.txt").write_text(listing, encoding="utf-8")
    unpacked = output / "unpacked"
    unpacked.mkdir()
    run("unbundle", archive, "-o", unpacked)
    for name, payload in resources.items():
        require(sha(unpacked / name.replace("\\", "/")) == sha(payload), "Encounter archive resource parity failed")
    require(all(sha(Path(path)) == digest for path, digest in hashes.items()), "Input changed during encounter build")
    manifest = {
        "utc": datetime.now(timezone.utc).isoformat(), "profile": profile_name,
        "status": "PRIVATE_ASSET_PREREQUISITE_NOT_INSTALLED_OR_LIVE_VERIFIED",
        "archive": str(archive), "archive_sha256": sha(archive),
        "resources": {name: sha(payload) for name, payload in resources.items()}, "source_sha256": hashes,
        "wolvenkit_cli_sha256": sha(wolvenkit), "inputs_unchanged": True,
        "roundtrip_encounter_contract": "PASS", "unpack_resource_parity": "PASS",
        "external_authored_dependency": encounter.GRAPH,
        "external_installed_dependencies": [profile.mesh, profile.rig, *profile.sets],
        "bundled_vanilla_resources": [], "runtime_selected": False,
        "fixture_reactions_enabled": False, "live_animation_verified": False,
    }
    if mode == "defeated_hold":
        manifest.update({"presentation": mode, "external_authored_dependency": None,
            "roundtrip_defeated_contract": "PASS", "sample_input": DEFEATED_PROGRESS,
            "sample_range": [0, 1], "sample_default": 0, "clip": DEFEATED_CLIP,
            "clip_duration_seconds": DEFEATED_DURATION, "clip_motion_extraction": None,
            "observed_animset_sha256": DEFEATED_ANIMATIONS[profile_name][1],
            "automatic_looping": False, "live_defeated_pose_verified": False})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=tuple(PROFILES), default="judy_default")
    parser.add_argument("--presentation", choices=("encounter", "defeated_hold"), default="encounter")
    parser.add_argument("--entity-json", type=Path)
    parser.add_argument("--graph-json", type=Path)
    parser.add_argument("--wolvenkit", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args.profile, args.wolvenkit, args.output_dir, args.entity_json, args.graph_json, args.presentation), indent=2))


if __name__ == "__main__":
    main()
