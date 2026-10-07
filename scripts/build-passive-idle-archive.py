"""Build only the authored passive entity and idle graph; never install assets.

Requires Python 3.10+ and official WolvenKit Console 9.0.1 on Windows.
WolvenKit timestamps its archive entries at pack time. Resource bytes and the
archive excluding timestamps/checksum can be compared with a reference build.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess


ENTITY = r"base\cp2077coop\entities\cp2077coop_networkhumanoid.ent"
GRAPH = r"base\cp2077coop\animations\networkhumanoid_idle.animgraph"
ANIMSET = r"base\animations\npc\gameplay\woman_average\gang\unarmed\wa_gang_unarmed_locomotion_combat.anims"
RIG = r"base\characters\base_entities\woman_base\woman_base.rig"
CLI_SHA256 = "7ae9c308da2fe003220b55ce4ca9c122b51f0701a67db1618cca3ff4f7ff6738"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resource_path(value):
    return value["DepotPath"]["$value"]


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def validate_sources(entity_path, graph_path):
    entity = json.loads(entity_path.read_text(encoding="utf-8-sig"))
    graph = json.loads(graph_path.read_text(encoding="utf-8-sig"))
    for document in (entity, graph):
        require(document["Header"]["WolvenKitVersion"] == "9.0.1", "Source schema must be WolvenKit 9.0.1")
        require(document["Data"]["EmbeddedFiles"] == [], "Embedded assets are not permitted")
    root = entity["Data"]["RootChunk"]
    require(root["entity"]["Data"]["$type"] == "entEntity", "Entity must remain a pure entEntity")
    chunks = root["compiledData"]["Data"]["Chunks"]
    require([x["$type"] for x in chunks] == ["entEntity", "entAnimatedComponent", "entSkinnedMeshComponent"], "Unexpected compiled components")
    require([x["$type"] for x in root["components"]] == ["entAnimatedComponent", "entSkinnedMeshComponent"], "Unexpected template components")
    for component in (root["components"][0], chunks[1]):
        require(resource_path(component["graph"]) == GRAPH, "Wrong idle graph reference")
        require(resource_path(component["rig"]) == RIG, "Wrong skeleton")
        require(component["controlBinding"] is None, "Animation controller is outside this passive experiment")
        setup = component["animations"]
        require(setup["cinematics"] == [] and len(setup["gameplay"]) == 1, "Expected one unconditional animation set")
        require(resource_path(setup["gameplay"][0]["animSet"]) == ANIMSET, "Wrong installed animation set")
        require(setup["gameplay"][0]["variableNames"] == [], "Animation set must not require gameplay variables")
    graph_root = graph["Data"]["RootChunk"]
    require(graph_root["$type"] == "animAnimGraph", "Wrong graph resource type")
    nodes = [x for x in walk(graph_root) if x.get("$type", "").startswith("animAnimNode_")]
    require([x["$type"] for x in nodes] == ["animAnimNode_Root", "animAnimNode_Output", "animAnimNode_SkAnim"], "Expected only Root -> Output -> SkAnim")
    clip = nodes[-1]
    require(clip["animation"]["$value"] == "idle_stand" and clip["isLooped"] == 1, "Expected looping idle_stand")
    require(all(clip[name] == 0 for name in ("applyMotion", "collectEvents", "fireAnimLoopEvent")), "Root motion and animation events must stay disabled")
    require(graph_root["animFeatures"] == [] and graph_root["additionalAnimDatabases"] == [], "Gameplay graph features are outside this experiment")
    require(all(graph_root[name] == 0 for name in ("useAnimCommands", "useAnimCommandsForCrowd", "useAnimStaticCommands")), "Animation commands must stay disabled")


def archive_content_signature(path):
    """Hash complete archive bytes except pack-time entry dates and index CRC.

    Layout: WolvenKit 9.0.1 ArchiveWriter.WriteHeader/WriteIndex/WriteFileEntry.
    This does not alter the output archive or skip payload integrity checks.
    """
    data = bytearray(path.read_bytes())
    require(data[:4] == b"RDAR", "Invalid REDengine archive magic")
    index = struct.unpack_from("<Q", data, 8)[0]
    index_size = struct.unpack_from("<I", data, 16)[0]
    require(index + index_size <= len(data) and index_size >= 28, "Invalid archive index")
    entries, segments, dependencies = struct.unpack_from("<III", data, index + 16)
    require(entries == 2, "Archive must contain exactly two resources")
    require(28 + entries * 56 + segments * 16 + dependencies * 8 == index_size, "Unexpected archive index layout")
    timestamps = {}
    for ordinal in range(entries):
        offset = index + 28 + ordinal * 56
        resource_hash, timestamp = struct.unpack_from("<QQ", data, offset)
        timestamps[str(resource_hash)] = timestamp
        data[offset + 8:offset + 16] = b"\0" * 8
    data[index + 8:index + 16] = b"\0" * 8
    return hashlib.sha256(data).hexdigest(), timestamps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entity-json", required=True, type=Path)
    parser.add_argument("--graph-json", required=True, type=Path)
    parser.add_argument("--wolvenkit", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path, help="A new directory; existing directories are refused")
    parser.add_argument("--reference-archive", type=Path, help="Optional known candidate archive for exact resource and layout comparison")
    args = parser.parse_args()
    require(args.wolvenkit.is_file(), "WolvenKit CLI was not found")
    require(sha(args.wolvenkit) == CLI_SHA256, "Use the official Windows WolvenKit.Console-9.0.1 CLI")
    validate_sources(args.entity_json, args.graph_json)
    require(not args.output_dir.exists(), "Output directory already exists; choose a new directory")
    output = args.output_dir.resolve()
    output.mkdir(parents=True)
    staging = output / "CP2077Coop_Experimental"
    packed = output / "out"
    packed.mkdir()
    log = output / "build.log"

    def run(*arguments):
        command = [str(args.wolvenkit.resolve()), *map(str, arguments)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
        with log.open("a", encoding="utf-8") as stream:
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
        require(binary.is_file(), f"Expected resource missing: {binary}")
        binaries[virtual] = binary
    require(len(list(staging.rglob("*.*"))) == 2, "Unexpected staging files")
    run("pack", staging, "-o", packed)
    archive = packed / "CP2077Coop_Experimental.archive"
    require(archive.is_file(), "Archive was not produced")
    listing = run("archive", archive, "--list")
    (output / "archive-list.txt").write_text(listing, encoding="utf-8")
    require(sorted(listing.strip().splitlines()) == sorted((ENTITY, GRAPH)), "Archive contains unexpected resource paths")
    unpacked = output / "unpacked"
    unpacked.mkdir()
    run("unbundle", archive, "-o", unpacked)
    for virtual, binary in binaries.items():
        extracted = unpacked / virtual.replace("\\", "/")
        require(extracted.is_file() and sha(extracted) == sha(binary), f"Archive payload mismatch: {virtual}")
    signature, timestamps = archive_content_signature(archive)
    record = {
        "utc": datetime.now(timezone.utc).isoformat(),
        "status": "OFFLINE_BUILD_ONLY_NOT_INSTALLED",
        "wolvenkit_cli_sha256": sha(args.wolvenkit),
        "source_sha256": {ENTITY: sha(args.entity_json), GRAPH: sha(args.graph_json)},
        "resource_sha256": {virtual: sha(binary) for virtual, binary in binaries.items()},
        "archive": str(archive), "archive_sha256": sha(archive),
        "archive_without_pack_timestamps_and_crc_sha256": signature,
        "archive_pack_filetimes": timestamps,
        "unpack_resource_parity": "PASS",
        "scope": "Fixed local idle presentation only; no HOST animation replication or AI/gameplay components",
        "bundled_vanilla_resources": [],
    }
    if args.reference_archive:
        reference_signature, _ = archive_content_signature(args.reference_archive)
        record["reference_archive_sha256"] = sha(args.reference_archive)
        record["reference_exact_archive_parity"] = sha(archive) == sha(args.reference_archive)
        record["reference_parity_excluding_pack_metadata"] = signature == reference_signature
        require(signature == reference_signature, "Reference archive differs beyond pack timestamps/checksum")
    (output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
