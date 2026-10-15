"""Strict encounter-profile mutations; source-only, no game or compiler required."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("encounter_profiles", ROOT / "experiments/passive-models/build_encounter_profile.py")
BUILDER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BUILDER
SPEC.loader.exec_module(BUILDER)


def groups(root):
    return root["components"], root["compiledData"]["Data"]["Chunks"][1:]


class EncounterProfileAssets(unittest.TestCase):
    def validate(self, name="mitch_default", mutate=None, error=None):
        profile = BUILDER.get_profile(name)
        doc = json.loads(profile.source.read_text(encoding="utf-8-sig"))
        if mutate:
            mutate(doc)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "candidate.ent.json"
            path.write_text(json.dumps(doc), encoding="utf-8")
            if error:
                with self.assertRaisesRegex(ValueError, error):
                    BUILDER.validate(name, path)
            else:
                BUILDER.validate(name, path)

    def test_both_explicit_profiles_and_old_judy_validator_pass(self):
        for name in BUILDER.PROFILES:
            with self.subTest(profile=name):
                self.validate(name)
        BUILDER.encounter.validate_sources(BUILDER.REFERENCE, BUILDER.GRAPH_SOURCE)

    def test_unknown_profile_does_not_fallback(self):
        for name in ("", "male", "Mitch", "mitch", None, 1, []):
            with self.subTest(profile=name), self.assertRaisesRegex(ValueError, "Unknown encounter profile"):
                BUILDER.validate(name)

    def test_wrong_profile_asset_is_rejected(self):
        for name, other in (("judy_default", "mitch_default"), ("mitch_default", "judy_default")):
            with self.subTest(profile=name), self.assertRaisesRegex(ValueError, "mesh mismatch"):
                BUILDER.validate(name, BUILDER.PROFILES[other].source)

    def test_each_copy_rejects_cross_profile_mesh_rig_and_three_sets(self):
        for name, other in (("judy_default", "mitch_default"), ("mitch_default", "judy_default")):
            alternate = BUILDER.PROFILES[other]
            for index in (0, 1):
                for field in ("mesh", "rig", 0, 1, 2):
                    def change(doc):
                        animated, mesh, _ = groups(doc["Data"]["RootChunk"])[index]
                        if field == "mesh":
                            mesh["mesh"]["DepotPath"]["$value"] = alternate.mesh
                        elif field == "rig":
                            animated["rig"]["DepotPath"]["$value"] = alternate.rig
                        else:
                            animated["animations"]["gameplay"][field]["animSet"]["DepotPath"]["$value"] = alternate.sets[field]
                    with self.subTest(profile=name, copy=index, field=field):
                        self.validate(name, change, "profile .* mismatch")

    def test_paired_copies_cannot_add_or_reorder_animation_sets(self):
        for operation in ("extra", "reorder", "remove"):
            def change(doc):
                for group in groups(doc["Data"]["RootChunk"]):
                    entries = group[0]["animations"]["gameplay"]
                    if operation == "extra":
                        entries.append(copy.deepcopy(entries[0]))
                    elif operation == "reorder":
                        entries.reverse()
                    else:
                        entries.pop()
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="sets required|sets mismatch")

    def test_resource_flags_storage_and_unreviewed_paths_fail(self):
        for field in ("graph", "rig", "mesh", "set"):
            for part in ("Flags", "$storage", "$value"):
                def change(doc):
                    for a, m, _ in groups(doc["Data"]["RootChunk"]):
                        ref = m["mesh"] if field == "mesh" else a["animations"]["gameplay"][0]["animSet"] if field == "set" else a[field]
                        if part == "Flags":
                            ref[part] = "Soft"
                        else:
                            ref["DepotPath"][part] = "uint64" if part == "$storage" else "unreviewed.asset"
                with self.subTest(field=field, part=part):
                    self.validate(mutate=change, error="mismatch")

    def test_dependency_table_add_drop_reorder_and_metadata_rejected(self):
        for operation in ("extra", "remove", "reorder", "flags", "storage", "path", "extra_metadata"):
            def change(doc):
                deps = doc["Data"]["RootChunk"]["resolvedDependencies"]
                if operation == "extra": deps.append(copy.deepcopy(deps[0]))
                elif operation == "remove": deps.pop()
                elif operation == "reorder": deps.reverse()
                elif operation == "flags": deps[0]["Flags"] = "Default"
                elif operation == "storage": deps[0]["DepotPath"]["$storage"] = "uint64"
                elif operation == "path": deps[1]["DepotPath"]["$value"] = BUILDER.idle.GRAPH
                else: deps[0]["unexpected"] = True
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="dependency table mismatch")

    def test_dependency_table_cross_profile_substitution_rejected(self):
        for name, other in (("judy_default", "mitch_default"), ("mitch_default", "judy_default")):
            for index in (0, 2, 3, 4):
                def change(doc):
                    doc["Data"]["RootChunk"]["resolvedDependencies"][index] = BUILDER.resolved_dependencies(BUILDER.PROFILES[other])[index]
                with self.subTest(profile=name, entry=index):
                    self.validate(name, change, "dependency table mismatch")

    def test_profile_copies_must_agree_on_visuals(self):
        def change(doc):
            doc["Data"]["RootChunk"]["components"][1]["chunkMask"] = "0"
        self.validate(mutate=change, error="visual components differ")

    def test_paired_copy_hiding_or_offset_is_forbidden(self):
        for operation in ("hidden", "offset", "appearance"):
            def change(doc):
                for _, mesh, _ in groups(doc["Data"]["RootChunk"]):
                    if operation == "hidden": mesh["chunkMask"] = "0"
                    elif operation == "offset": mesh["localTransform"]["Position"]["z"]["Bits"] = 131072
                    else: mesh["meshAppearance"]["$value"] = "mitch_default"
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="draw mask|identity local transform|default mesh appearance")

    def test_disabled_wrong_type_or_masked_controller_binding_fails(self):
        for operation in ("disabled", "type", "mask"):
            def change(doc):
                for value in BUILDER.idle.walk(doc["Data"]):
                    if value.get("$type") == "entAnimationControlBinding":
                        if operation == "disabled": value["enabled"] = 0
                        elif operation == "type": value["$type"] = "entHardTransformBinding"
                        else: value["enableMask"]["hardTags"]["tags"] = [{"$type": "CName", "$storage": "string", "$value": "Blocked"}]
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="non-profile Data")

    def test_controller_rebinding_or_replication_fails(self):
        for operation in ("binding", "replication"):
            def change(doc):
                for _, _, controller in groups(doc["Data"]["RootChunk"]):
                    if operation == "binding": controller["controlBinding"] = {"HandleRefId": "2"}
                    else: controller["isReplicable"] = 1
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="non-profile Data")

    def test_wrong_controller_name_or_action_database_fails(self):
        for operation in ("name", "database"):
            def change(doc):
                for _, _, controller in groups(doc["Data"]["RootChunk"]):
                    if operation == "name": controller["name"]["$value"] = "OtherController"
                    else: controller["actionAnimDatabaseRef"]["DepotPath"]["$value"] = "1"
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="controller name|action animation database")

    def test_animation_priority_and_conditional_variable_cannot_change(self):
        for operation in ("priority", "conditional"):
            def change(doc):
                for animated, _, _ in groups(doc["Data"]["RootChunk"]):
                    entry = animated["animations"]["gameplay"][0]
                    if operation == "priority": entry["priority"] = 0
                    else: entry["variableNames"] = [{"$type": "CName", "$storage": "string", "$value": "AI"}]
            with self.subTest(operation=operation):
                self.validate(mutate=change, error="non-profile Data|Unconditional")

    def test_inherited_npc_ai_and_collision_components_are_forbidden(self):
        for kind in ("AIHumanComponent", "entColliderComponent", "entRagdollComponent"):
            def change(doc):
                r = doc["Data"]["RootChunk"]
                r["components"].append({"$type": kind})
                r["compiledData"]["Data"]["Chunks"].append({"$type": kind})
            with self.subTest(kind=kind):
                self.validate(mutate=change, error="Unexpected compiled encounter component")
        self.validate(mutate=lambda d: d["Data"]["RootChunk"].update(includes=[{"template": "mitch.ent"}]), error="empty includes")
        def npc(doc):
            r = doc["Data"]["RootChunk"]
            r["entity"]["Data"]["$type"] = "NPCPuppet"
            r["compiledData"]["Data"]["Chunks"][0]["$type"] = "NPCPuppet"
        self.validate(mutate=npc, error="must remain entEntity")

    def test_embedded_or_unrecognized_data_payload_is_rejected(self):
        self.validate(mutate=lambda d: d["Data"].update(EmbeddedFiles=[{"FileName": "vanilla.mesh", "Content": "forbidden"}]),
                      error="embedded encounter payloads")
        self.validate(mutate=lambda d: d["Data"].update(UnreviewedPayload="forbidden"), error="non-profile Data")

    def test_ambiguous_dangling_conflicting_and_cyclic_handles_fail(self):
        def binding(doc): return doc["Data"]["RootChunk"]["components"][0]["controlBinding"]
        # The authored source contains a template reference to compiled HandleId2.
        mutations = {
            "ambiguous_reference": lambda d: binding(d).update({"Data": {}}),
            "dangling": lambda d: binding(d).update({"HandleRefId": "missing"}),
            "conflict": lambda d: d["Data"]["RootChunk"]["components"][0].update(controlBinding={"HandleId": "2", "Data": {"different": True}}),
            "ambiguous_definition": lambda d: d["Data"]["RootChunk"]["compiledData"]["Data"]["Chunks"][1]["controlBinding"].update(unknown=True),
            "cycle": lambda d: d["Data"]["RootChunk"]["compiledData"]["Data"]["Chunks"][1]["controlBinding"]["Data"].update(loop={"HandleRefId": "2"}),
        }
        for reason, change in mutations.items():
            with self.subTest(reason=reason):
                self.validate(mutate=change, error="Ambiguous|Unresolved|Conflicting|Cyclic")

    def test_identical_repeated_definitions_and_reference_forms_remain_valid(self):
        def change(doc):
            r = doc["Data"]["RootChunk"]
            r["components"][0]["controlBinding"] = copy.deepcopy(r["compiledData"]["Data"]["Chunks"][1]["controlBinding"])
        self.validate(mutate=change)

    def test_unchanged_graph_is_mandatory(self):
        original = json.loads(BUILDER.GRAPH_SOURCE.read_text(encoding="utf-8-sig"))
        mutations = [lambda g: g["Data"]["RootChunk"].update(useAnimCommands=1),
                     lambda g: g["Data"].update(EmbeddedFiles=[{"payload": "forbidden"}])]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "graph.json"
            for change in mutations:
                doc = copy.deepcopy(original);change(doc)
                path.write_text(json.dumps(doc), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "unchanged reviewed encounter graph"):
                    BUILDER.validate("mitch_default", graph_path=path)

    def test_lf_crlf_sources_and_graphs_preserve_content_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            entity, graph = Path(tmp) / "entity.json", Path(tmp) / "graph.json"
            for name, p in BUILDER.PROFILES.items():
                for newline in (b"\n", b"\r\n"):
                    entity.write_bytes(p.source.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", newline))
                    graph.write_bytes(BUILDER.GRAPH_SOURCE.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", newline))
                    with self.subTest(profile=name, newline=newline):
                        BUILDER.validate(name, entity, graph)

    def test_validation_never_changes_source_bytes(self):
        for name, profile in BUILDER.PROFILES.items():
            original = profile.source.read_bytes()
            BUILDER.validate(name)
            self.assertEqual(profile.source.read_bytes(), original)
        self.assertEqual(BUILDER.source_lf_sha(BUILDER.REFERENCE), BUILDER.REFERENCE_LF_SHA256)
        self.assertEqual(BUILDER.source_lf_sha(BUILDER.GRAPH_SOURCE), BUILDER.GRAPH_LF_SHA256)

    def test_existing_output_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "existing";output.mkdir()
            sentinel = output / "existing.archive";sentinel.write_bytes(b"untouched")
            with self.assertRaisesRegex(ValueError, "new output directory"):
                BUILDER.build("mitch_default", Path(tmp) / "unused.exe", output)
            self.assertEqual(sentinel.read_bytes(), b"untouched")
            self.assertEqual(list(output.iterdir()), [sentinel])

    def test_unpinned_compiler_is_rejected_before_creating_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            cli = Path(tmp) / "fake.exe";cli.write_bytes(b"not a compiler")
            output = Path(tmp) / "new"
            with self.assertRaisesRegex(ValueError, "pinned official WolvenKit"):
                BUILDER.build("mitch_default", cli, output)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
