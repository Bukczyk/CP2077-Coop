"""Build one opt-in authored passive model; never install or select it at runtime.

Only an entity is packaged. The existing authored idle graph is an explicit
external dependency. Installed mesh/rig/animation resources are never bundled.
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
spec = importlib.util.spec_from_file_location("passive_idle_contract", ROOT / "scripts/build-passive-idle-archive.py")
idle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idle)
require, sha, resource_path = idle.require, idle.sha, idle.resource_path
GRAPH_SOURCE = ROOT / "runtime/session/assets/source/raw" / (idle.GRAPH.replace("\\", "/") + ".json")
# Git normalizes these authored JSON files to LF; Windows may check out CRLF.
GRAPH_SOURCE_LF_SHA256 = "bb7065954b0e37c7649c354866e138ad5e76dc9ee9d1d17bdadc43fc78267c07"


def source_lf_sha(path):
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


@dataclass(frozen=True)
class Profile:
    entity: str
    source: Path
    mesh: str
    rig: str
    animset: str


PROFILES = MappingProxyType({
    "judy_default": Profile(idle.ENTITY,
        ROOT / "runtime/session/assets/source/raw/base/cp2077coop/entities/CP2077Coop_NetworkHumanoid.ent.json",
        idle.MESH, idle.RIG, idle.ANIMSET),
    "mitch_default": Profile(r"base\cp2077coop\entities\cp2077coop_networkhumanoid_mitch.ent",
        Path(__file__).parent / "raw/base/cp2077coop/entities/cp2077coop_networkhumanoid_mitch.ent.json",
        r"base\characters\appearances\main_npc\proxy\mitch_default\mitch_default.mesh",
        r"base\characters\base_entities\man_base\man_base.rig",
        r"base\animations\npc\gameplay\man_average\gang\unarmed\ma_gang_unarmed_locomotion_combat.anims"),
})


def get_profile(name):
    require(isinstance(name, str) and name in PROFILES, "Unknown passive model profile")
    return PROFILES[name]


def resolved_dependencies(profile):
    """Exact authored/WolvenKit roundtrip table, not all transitive imports.

    The existing Judy source and 9.0.1 roundtrip list mesh, graph and animset in
    this order. Rig stays an explicit animated-component import; do not invent
    an additional dependency-table convention for this experiment.
    """
    return [{"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": path},
             "Flags": "Soft"} for path in (profile.mesh, idle.GRAPH, profile.animset)]


def validate(profile_name, entity_path=None, graph_path=GRAPH_SOURCE):
    """Require exact profile refs, then reuse the unchanged Judy passive gate.

    The canonical copy replaces ONLY the already-checked mesh, rig and animset
    paths in both component copies, plus the exact resolved-dependency table.
    Every other field remains subject to the
    existing strict entity/visual/idle-graph checks. Production defaults are not
    mutated and unknown profiles never become a fallback.
    """
    profile = get_profile(profile_name)
    require(source_lf_sha(graph_path) == GRAPH_SOURCE_LF_SHA256,
            "Use the unchanged reviewed authored idle graph")
    source = Path(entity_path) if entity_path is not None else profile.source
    doc = json.loads(source.read_text(encoding="utf-8-sig"))
    canonical = copy.deepcopy(doc)
    root = canonical["Data"]["RootChunk"]
    require(root["$type"] == "entEntityTemplate", "Expected authored entity template")
    require(root["entity"]["Data"]["$type"] == "entEntity", "Passive profile must remain entEntity")
    chunks = root["compiledData"]["Data"]["Chunks"]
    types = ["entAnimatedComponent", "entSkinnedMeshComponent"]
    require([x["$type"] for x in chunks] == ["entEntity"] + types, "Unexpected compiled component")
    require([x["$type"] for x in root["components"]] == types, "Unexpected template component")
    for components in (root["components"], chunks[1:]):
        animated, mesh = components
        require(resource_path(mesh["mesh"]) == profile.mesh, "Profile mesh mismatch")
        require(resource_path(animated["rig"]) == profile.rig, "Profile rig mismatch")
        gameplay = animated["animations"]["gameplay"]
        require(len(gameplay) == 1, "Profile requires exactly one idle animation set")
        require(resource_path(gameplay[0]["animSet"]) == profile.animset, "Profile animation set mismatch")
        mesh["mesh"]["DepotPath"]["$value"] = idle.MESH
        animated["rig"]["DepotPath"]["$value"] = idle.RIG
        gameplay[0]["animSet"]["DepotPath"]["$value"] = idle.ANIMSET
    require(root.get("resolvedDependencies") == resolved_dependencies(profile),
            "Profile resolved dependency table mismatch")
    root["resolvedDependencies"] = resolved_dependencies(PROFILES["judy_default"])
    # Reuse schema, no-AI, no-inheritance, parity, bindings and graph checks
    # without loosening or monkeypatching the existing production builder.
    with tempfile.TemporaryDirectory(prefix="cp2077_profile_contract_") as tmp:
        candidate = Path(tmp) / "canonical.ent.json"
        candidate.write_text(json.dumps(canonical), encoding="utf-8")
        idle.validate_sources(candidate, Path(graph_path))
    return profile


def build(profile_name, wolvenkit, output_dir, entity_path=None, graph_path=GRAPH_SOURCE):
    profile = validate(profile_name, entity_path, graph_path)
    source = Path(entity_path) if entity_path is not None else profile.source
    wolvenkit, output = Path(wolvenkit).resolve(), Path(output_dir).resolve()
    require(wolvenkit.is_file() and sha(wolvenkit) == idle.CLI_SHA256,
            "Use the pinned official WolvenKit Console 9.0.1")
    require(not output.exists(), "Choose a new output directory")
    input_hashes = {str(source.resolve()): sha(source), str(Path(graph_path).resolve()): sha(Path(graph_path))}
    output.mkdir(parents=True)
    archive_name = "CP2077Coop_PassiveProfile_" + profile_name
    staging = output / archive_name
    relative = Path(profile.entity.replace("\\", "/"))
    copied = output / "raw" / (str(relative) + ".json")
    copied.parent.mkdir(parents=True)
    shutil.copyfile(source, copied)
    binary = staging / relative
    binary.parent.mkdir(parents=True)
    log = output / "build.log"

    def run(*args):
        command = [str(wolvenkit), *map(str, args)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
        with log.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(command) + "\n" + result.stdout + result.stderr + "\n")
        require(result.returncode == 0, f"WolvenKit failed; see {log}")
        return result.stdout

    run("convert", "deserialize", copied, "-o", binary.parent)
    require(binary.is_file(), "Authored entity binary missing")
    roundtrip = output / "roundtrip"
    roundtrip.mkdir()
    run("convert", "serialize", binary, "-o", roundtrip)
    validate(profile_name, roundtrip / (relative.name + ".json"), graph_path)
    require([p.relative_to(staging) for p in staging.rglob("*") if p.is_file()] == [relative],
            "Only the authored profile entity may be staged")
    packed = output / "out"
    packed.mkdir()
    run("pack", staging, "-o", packed)
    archive = packed / (archive_name + ".archive")
    require(archive.is_file(), "Profile archive missing")
    listing = run("archive", archive, "--list")
    require(listing.strip().splitlines() == [profile.entity], "Unexpected archive resource")
    (output / "archive-list.txt").write_text(listing, encoding="utf-8")
    unpacked = output / "unpacked"
    unpacked.mkdir()
    run("unbundle", archive, "-o", unpacked)
    require(sha(unpacked / relative) == sha(binary), "Archive resource parity failed")
    require(all(sha(Path(path)) == digest for path, digest in input_hashes.items()), "Source input changed during build")
    manifest = {
        "utc": datetime.now(timezone.utc).isoformat(), "profile": profile_name,
        "status": "PRIVATE_OFFLINE_EXPERIMENT_NOT_INSTALLED_OR_LIVE_VERIFIED",
        "archive": str(archive), "archive_sha256": sha(archive),
        "resources": {profile.entity: sha(binary)}, "source_sha256": input_hashes,
        "wolvenkit_cli_sha256": sha(wolvenkit), "roundtrip_passive_profile": "PASS",
        "unpack_resource_parity": "PASS", "inputs_unchanged": True,
        "external_authored_dependency": idle.GRAPH,
        "external_installed_dependencies": [profile.mesh, profile.rig, profile.animset],
        "bundled_vanilla_resources": [], "runtime_selected": False,
        "appearance_matching_verified": False, "live_animation_verified": False,
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
