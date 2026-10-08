"""Build the opt-in passive encounter presentation candidate, without installing it.

Only two authored resources are packed. Installed game animation resources remain
external references. A successful build is structural evidence, not live playback.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess


spec = importlib.util.spec_from_file_location("idle_builder", Path(__file__).with_name("build-passive-idle-archive.py"))
idle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idle)
require, sha, walk = idle.require, idle.sha, idle.walk
ENTITY = r"base\cp2077coop\entities\cp2077coop_networkhumanoid_encounter.ent"
GRAPH = r"base\cp2077coop\animations\networkhumanoid_encounter.animgraph"
CONTROLLER = "CP2077Coop_EncounterController"
SETS = [idle.ANIMSET] + [
    rf"base\animations\npc\gameplay\woman_average\gang\unarmed\wa_gang_unarmed_reaction_ranged_{kind}.anims"
    for kind in ("impact", "death")
]


def validate_sources(entity_path, graph_path):
    entity = json.loads(entity_path.read_text(encoding="utf-8-sig"))
    graph = json.loads(graph_path.read_text(encoding="utf-8-sig"))
    for doc in (entity, graph):
        require(doc["Data"]["EmbeddedFiles"] == [], "No embedded resource bytes allowed")
    root = entity["Data"]["RootChunk"]
    handles = {v["HandleId"]: v["Data"] for v in walk(root) if "HandleId" in v and "Data" in v}

    def handle_data(value):
        return value["Data"] if "Data" in value else handles[value["HandleRefId"]]

    require(root["entity"]["Data"]["$type"] == "entEntity", "Must remain entEntity")
    types = ["entAnimatedComponent", "entSkinnedMeshComponent", "entAnimationControllerComponent"]
    chunks = root["compiledData"]["Data"]["Chunks"]
    require([x["$type"] for x in chunks] == ["entEntity"] + types, "Unexpected compiled component, including possible AI/collision")
    require([x["$type"] for x in root["components"]] == types, "Unexpected template component")
    for components in (chunks[1:], root["components"]):
        animated, _, controller = components
        require(idle.resource_path(animated["graph"]) == GRAPH, "Wrong graph path")
        require(idle.resource_path(animated["rig"]) == idle.RIG, "Wrong rig")
        require(handle_data(animated["controlBinding"])["bindName"]["$value"] == CONTROLLER, "Wrong control binding")
        require(controller["name"]["$value"] == CONTROLLER, "Wrong controller name")
        require(controller["animDatabaseCollection"]["animDatabases"] == [], "No gameplay action databases")
        require(idle.resource_path(controller["actionAnimDatabaseRef"]) == "0", "No action animation database")
        require(animated["animations"]["cinematics"] == [], "No cinematic setup")
        gameplay = animated["animations"]["gameplay"]
        require([idle.resource_path(x["animSet"]) for x in gameplay] == SETS, "Unexpected animation set")
        require(all(x["variableNames"] == [] for x in gameplay), "Unconditional animation sets required")
    gr = graph["Data"]["RootChunk"]
    graph_handles = {}
    for value in walk(gr):
        if "HandleId" in value:
            require("Data" in value and value["HandleId"] not in graph_handles,
                    "Missing data or duplicate graph handle definition")
            graph_handles[value["HandleId"]] = value["Data"]

    def graph_data(value):
        require(isinstance(value, dict), "Missing graph handle")
        if "HandleRefId" in value:
            require(set(value) == {"HandleRefId"}, "Ambiguous graph handle reference")
            require(value["HandleRefId"] in graph_handles, "Unresolved graph handle")
            return graph_handles[value["HandleRefId"]]
        require("HandleId" in value and "Data" in value, "Invalid graph handle definition")
        return graph_handles[value["HandleId"]]

    def linked_node(value, link_type):
        require(isinstance(value, dict) and value.get("$type") == link_type,
                "Unexpected graph link type")
        return graph_data(value.get("node"))

    def no_link(value):
        # Omitted links acquire empty animFloatLink defaults on WK roundtrip.
        return value is None or (isinstance(value, dict)
                                 and value.get("$type") == "animFloatLink"
                                 and value.get("node") is None)

    def variable_link(value, name):
        target = linked_node(value, "animFloatLink")
        require(target.get("$type") == "animAnimNode_FloatVariable"
                and target["variableName"]["$value"] == name,
                f"Graph link must read {name}")

    require(gr["animFeatures"] == [] and gr["additionalAnimDatabases"] == [], "No gameplay features")
    require(all(gr[k] == 0 for k in ("useAnimCommands", "useAnimCommandsForCrowd", "useAnimStaticCommands")), "Animation commands disabled")
    nodes = [x for x in walk(gr) if x.get("$type", "").startswith("animAnimNode_")]
    expected = ["animAnimNode_Root", "animAnimNode_Output", "animAnimNode_Switch", "animAnimNode_SkAnim", "animAnimNode_SkFrameAnim", "animAnimNode_SkFrameAnim", "animAnimNode_FloatVariable", "animAnimNode_FloatVariable", "animAnimNode_FloatVariable"]
    require(Counter(x["$type"] for x in nodes) == Counter(expected), "Unexpected graph topology")
    switch = next(x for x in nodes if x["$type"] == "animAnimNode_Switch")
    graph_root = graph_data(gr["rootNode"])
    output_node = next(x for x in nodes if x["$type"] == "animAnimNode_Output")
    require(graph_root.get("$type") == "animAnimNode_Root", "Wrong active graph root")
    root_nodes = [graph_data(x) for x in graph_root["nodes"]]
    require(root_nodes and root_nodes[0] is output_node, "Root must contain the output node first")
    require(len(root_nodes) == 8 and {id(x) for x in root_nodes} == {id(x) for x in nodes if x is not graph_root},
            "Root must contain every non-root node exactly once")
    require(graph_root["outputNode"].get("node") is None, "Unexpected alternate root output")
    initialized = [graph_data(x) for x in gr["nodesToInit"]]
    require(len(initialized) == 9 and {id(x) for x in initialized} == {id(x) for x in nodes},
            "Initialize every graph node exactly once")
    require(linked_node(output_node["node"], "animPoseLink") is switch,
            "Output must use the phase switch")
    require(len(switch["inputNodes"]) == 3, "Switch must have exactly three input links")
    clips = [linked_node(x, "animPoseLink") for x in switch["inputNodes"]]
    require(switch["numInputs"] == 3 and switch["blendTime"] == 0, "Explicit three-way pose selection required")
    variable_link(switch["weightNode"], "cp_coop_phase")
    require([x.get("$type") for x in clips] == ["animAnimNode_SkAnim", "animAnimNode_SkFrameAnim", "animAnimNode_SkFrameAnim"],
            "Switch inputs must be idle, sampled reaction and sampled death")
    require([x["animation"]["$value"] for x in clips] == ["idle_stand", "impact_stand_front_torso_l", "death_front_torso_l_idle"], "Unexpected clip")
    for node, variable in zip(clips[1:], ("cp_coop_hit_progress", "cp_coop_death_progress")):
        variable_link(node["progressLink"], variable)
        require(no_link(node.get("timeLink")) and no_link(node.get("frameLink")),
                "Sampled clips must not have competing time/frame inputs")
    for node in clips:
        require(all(node[k] == 0 for k in ("applyMotion", "collectEvents", "fireAnimLoopEvent", "resume")), "No root motion, event dispatch or resume")
    require([x["isLooped"] for x in clips] == [1, 0, 0], "Only idle loops")
    variables = [graph_data(v) for v in graph_data(gr["variables"])["floatVariables"]]
    require([v["name"]["$value"] for v in variables] == ["cp_coop_phase", "cp_coop_hit_progress", "cp_coop_death_progress"], "Unexpected graph inputs")
    require([v["max"] for v in variables] == [2, 1, 1], "Wrong graph ranges")
    require(all(v["default"] == 0 and v["value"] == 0 and v["min"] == 0 for v in variables), "Default is idle with zero progress")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entity-json", required=True, type=Path)
    parser.add_argument("--graph-json", required=True, type=Path)
    parser.add_argument("--wolvenkit", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    require(args.wolvenkit.is_file() and sha(args.wolvenkit) == idle.CLI_SHA256, "Use official WolvenKit Console 9.0.1")
    validate_sources(args.entity_json, args.graph_json)
    require(not args.output_dir.exists(), "Choose a new output directory")
    output = args.output_dir.resolve()
    output.mkdir(parents=True)
    staging = output / "CP2077Coop_EncounterPresentation"
    packed = output / "out"
    packed.mkdir()
    log = output / "build.log"

    def run(*arguments):
        command = [str(args.wolvenkit.resolve()), *map(str, arguments)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf8", errors="replace")
        with log.open("a", encoding="utf8") as stream:
            stream.write(json.dumps(command) + "\n" + result.stdout + result.stderr + "\n")
        require(result.returncode == 0, f"WolvenKit failed; see {log}")
        return result.stdout

    binaries = {}
    for source, virtual in ((args.entity_json, ENTITY), (args.graph_json, GRAPH)):
        relative = Path(virtual.replace("\\", "/"))
        copied = output / "raw" / (str(relative) + ".json")
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, copied)
        binary = staging / relative
        binary.parent.mkdir(parents=True, exist_ok=True)
        run("convert", "deserialize", copied, "-o", binary.parent)
        require(binary.is_file(), f"Missing {virtual}")
        binaries[virtual] = binary
    require(len(list(staging.rglob("*.*"))) == 2, "Only authored entity and graph may be packed")
    roundtrip = output / "roundtrip"
    roundtrip.mkdir()
    for binary in binaries.values():
        run("convert", "serialize", binary, "-o", roundtrip)
    validate_sources(roundtrip / (Path(ENTITY.replace("\\", "/")).name + ".json"), roundtrip / (Path(GRAPH.replace("\\", "/")).name + ".json"))
    run("pack", staging, "-o", packed)
    archive = packed / "CP2077Coop_EncounterPresentation.archive"
    listing = run("archive", archive, "--list")
    require(sorted(listing.strip().splitlines()) == sorted((ENTITY, GRAPH)), "Unexpected archive resources")
    (output / "archive-list.txt").write_text(listing, encoding="utf8")
    unpacked = output / "unpacked"
    unpacked.mkdir()
    run("unbundle", archive, "-o", unpacked)
    for virtual, binary in binaries.items():
        extracted = unpacked / virtual.replace("\\", "/")
        require(extracted.is_file() and sha(extracted) == sha(binary), f"Payload mismatch {virtual}")
    signature, dates = idle.archive_content_signature(archive)
    record = {
        "utc": datetime.now(timezone.utc).isoformat(),
        "status": "OFFLINE_BUILT_NOT_INSTALLED_OR_LIVE_VERIFIED",
        "archive": str(archive), "archive_sha256": sha(archive),
        "archive_without_pack_timestamps_and_crc_sha256": signature,
        "archive_pack_filetimes": dates,
        "source_sha256": {ENTITY: sha(args.entity_json), GRAPH: sha(args.graph_json)},
        "resource_sha256": {v: sha(p) for v, p in binaries.items()},
        "roundtrip_passive_contract": "PASS", "unpack_resource_parity": "PASS",
        "wolvenkit_cli_sha256": sha(args.wolvenkit), "bundled_vanilla_resources": [],
        "scope": "Three authored poses driven by queued float setters; exact HOST animation and combat networking are not implemented",
    }
    (output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf8")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
