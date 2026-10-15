"""Offline profile/asset mutations; no game files, binaries or runtime required."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("passive_model_builder", ROOT / "experiments/passive-models/build_profile.py")
BUILDER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BUILDER
SPEC.loader.exec_module(BUILDER)


def groups(root):
    return root["components"], root["compiledData"]["Data"]["Chunks"][1:]


class PassiveModelProfile(unittest.TestCase):
    def validate(self, name="mitch_default", mutate=None, error=None):
        profile = BUILDER.get_profile(name)
        doc = json.loads(profile.source.read_text(encoding="utf-8-sig"))
        if mutate:
            mutate(doc["Data"]["RootChunk"])
        with tempfile.TemporaryDirectory() as tmp:
            candidate = Path(tmp) / "candidate.ent.json"
            candidate.write_text(json.dumps(doc), encoding="utf-8")
            if error:
                with self.assertRaisesRegex(ValueError, error):
                    BUILDER.validate(name, candidate)
            else:
                BUILDER.validate(name, candidate)

    def test_both_reviewed_profiles_pass(self):
        for name in BUILDER.PROFILES:
            with self.subTest(profile=name):
                self.validate(name)

    def test_production_judy_source_and_idle_builder_are_unchanged(self):
        source = BUILDER.PROFILES["judy_default"].source
        self.assertEqual(BUILDER.source_lf_sha(source), "04c2e236f934e41cd781e1ca5427d2b40b3ee76eaf2d1abf5cd2bf4e4e578287")
        BUILDER.idle.validate_sources(source, BUILDER.GRAPH_SOURCE)

    def test_unknown_profile_has_no_fallback(self):
        for name in ("", "male", "default", "mitch", "Judy_Default", None, 1):
            with self.subTest(profile=name), self.assertRaisesRegex(ValueError, "Unknown passive model profile"):
                BUILDER.validate(name)

    def test_profile_is_explicit_not_inferred_from_asset(self):
        for name, other in (("judy_default", "mitch_default"), ("mitch_default", "judy_default")):
            with self.subTest(profile=name), self.assertRaisesRegex(ValueError, "Profile mesh mismatch"):
                BUILDER.validate(name, BUILDER.PROFILES[other].source)

    def test_male_female_mesh_swap_rejected_in_either_copy(self):
        for index in (0, 1):
            def change(root):
                groups(root)[index][1]["mesh"]["DepotPath"]["$value"] = BUILDER.idle.MESH
            with self.subTest(copy=index):
                self.validate(mutate=change, error="Profile mesh mismatch")

    def test_matching_copies_cannot_select_unreviewed_male_mesh(self):
        def change(root):
            for group in groups(root):
                group[1]["mesh"]["DepotPath"]["$value"] = r"base\characters\appearances\main_npc\proxy\victor_vektor_default\victor_vektor_default.mesh"
        self.validate(mutate=change, error="Profile mesh mismatch")

    def test_male_female_rig_swap_rejected_in_both_copies(self):
        def change(root):
            for group in groups(root):
                group[0]["rig"]["DepotPath"]["$value"] = BUILDER.idle.RIG
        self.validate(mutate=change, error="Profile rig mismatch")

    def test_male_female_animation_swap_rejected_in_both_copies(self):
        def change(root):
            for group in groups(root):
                group[0]["animations"]["gameplay"][0]["animSet"]["DepotPath"]["$value"] = BUILDER.idle.ANIMSET
        self.validate(mutate=change, error="Profile animation set mismatch")

    def test_extra_animation_set_cannot_sneak_into_profile(self):
        def change(root):
            for group in groups(root):
                entry = group[0]["animations"]["gameplay"][0]
                group[0]["animations"]["gameplay"].append(copy.deepcopy(entry))
        self.validate(mutate=change, error="exactly one idle animation set")

    def test_appearance_override_is_not_a_supported_profile(self):
        def change(root):
            for group in groups(root):
                group[1]["meshAppearance"]["$value"] = "mitch_default"
        self.validate(mutate=change, error="default mesh appearance")

    def test_compiled_template_drift_is_not_hidden_by_normalization(self):
        self.validate(mutate=lambda r: r["components"][1].update({"chunkMask": "0"}), error="visual components differ")

    def test_matching_copies_cannot_hide_or_offset_mesh(self):
        for field in ("chunkMask", "localTransform"):
            def change(root):
                for group in groups(root):
                    if field == "chunkMask":
                        group[1][field] = "0"
                    else:
                        group[1][field]["Position"]["x"]["Bits"] = 131072
            with self.subTest(field=field):
                self.validate(mutate=change, error="draw mask|identity local transform")

    def test_vanilla_entity_inheritance_is_forbidden(self):
        self.validate(mutate=lambda r: r.update({"includes": [{"template": "mitch.ent"}]}), error="requires empty includes")

    def test_npc_root_is_forbidden(self):
        def change(root):
            root["entity"]["Data"]["$type"] = "NPCPuppet"
            root["compiledData"]["Data"]["Chunks"][0]["$type"] = "NPCPuppet"
        self.validate(mutate=change, error="must remain entEntity")

    def test_extra_ai_component_is_forbidden(self):
        def change(root):
            root["components"].append({"$type": "AIHumanComponent"})
            root["compiledData"]["Data"]["Chunks"].append({"$type": "AIHumanComponent"})
        self.validate(mutate=change, error="Unexpected compiled component")

    def test_unknown_embedded_resource_payload_is_forbidden(self):
        doc = json.loads(BUILDER.PROFILES["mitch_default"].source.read_text(encoding="utf-8"))
        doc["Data"]["EmbeddedFiles"] = [{"FileName": "vanilla.mesh", "Content": "forbidden"}]
        with tempfile.TemporaryDirectory() as tmp:
            candidate = Path(tmp) / "candidate.ent.json"
            candidate.write_text(json.dumps(doc), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Embedded assets"):
                BUILDER.validate("mitch_default", candidate)

    def test_canonical_validation_does_not_mutate_input(self):
        for name, profile in BUILDER.PROFILES.items():
            before = profile.source.read_bytes()
            BUILDER.validate(name)
            self.assertEqual(profile.source.read_bytes(), before)

    def test_unreviewed_external_graph_is_rejected(self):
        graph = json.loads(BUILDER.GRAPH_SOURCE.read_text(encoding="utf-8-sig"))
        graph["Data"]["RootChunk"]["useAnimCommands"] = 1
        with tempfile.TemporaryDirectory() as tmp:
            candidate = Path(tmp) / "graph.json"
            candidate.write_text(json.dumps(graph), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unchanged reviewed authored idle graph"):
                BUILDER.validate("mitch_default", graph_path=candidate)

    def test_lf_and_crlf_checkouts_pass_the_same_content_pin(self):
        with tempfile.TemporaryDirectory() as tmp:
            graph = Path(tmp) / "graph.json"
            entity = Path(tmp) / "entity.json"
            graph_lf = BUILDER.GRAPH_SOURCE.read_bytes().replace(b"\r\n", b"\n")
            for name, profile in BUILDER.PROFILES.items():
                entity_lf = profile.source.read_bytes().replace(b"\r\n", b"\n")
                for newline in (b"\n", b"\r\n"):
                    graph.write_bytes(graph_lf.replace(b"\n", newline))
                    entity.write_bytes(entity_lf.replace(b"\n", newline))
                    with self.subTest(profile=name, newline=newline):
                        BUILDER.validate(name, entity, graph)

    def test_resolved_dependencies_match_explicit_profile(self):
        for name, other in (("judy_default", "mitch_default"), ("mitch_default", "judy_default")):
            for index in (0, 2):
                def change(root):
                    root["resolvedDependencies"][index] = BUILDER.resolved_dependencies(BUILDER.PROFILES[other])[index]
                with self.subTest(profile=name, dependency=index):
                    self.validate(name, mutate=change, error="resolved dependency table mismatch")

    def test_dependency_table_cannot_add_drop_reorder_or_weaken_resources(self):
        mutations = {
            "drop": lambda r: r["resolvedDependencies"].pop(),
            "extra": lambda r: r["resolvedDependencies"].append(copy.deepcopy(r["resolvedDependencies"][0])),
            "reorder": lambda r: r["resolvedDependencies"].reverse(),
            "flags": lambda r: r["resolvedDependencies"][0].update({"Flags": "Default"}),
            "storage": lambda r: r["resolvedDependencies"][0]["DepotPath"].update({"$storage": "uint64"}),
            "graph": lambda r: r["resolvedDependencies"][1]["DepotPath"].update({"$value": "vanilla.animgraph"}),
        }
        for name in BUILDER.PROFILES:
            for reason, mutate in mutations.items():
                with self.subTest(profile=name, mutation=reason):
                    self.validate(name, mutate=mutate, error="resolved dependency table mismatch")

    def test_all_nonprofile_fields_match_existing_authored_entity(self):
        judy = json.loads(BUILDER.PROFILES["judy_default"].source.read_text(encoding="utf-8-sig"))
        male = json.loads(BUILDER.PROFILES["mitch_default"].source.read_text(encoding="utf-8-sig"))
        for male_group, judy_group in zip(groups(male["Data"]["RootChunk"]), groups(judy["Data"]["RootChunk"])):
            male_group[0]["rig"] = copy.deepcopy(judy_group[0]["rig"])
            male_group[0]["animations"] = copy.deepcopy(judy_group[0]["animations"])
            male_group[1]["mesh"] = copy.deepcopy(judy_group[1]["mesh"])
        male["Data"]["RootChunk"]["resolvedDependencies"] = copy.deepcopy(judy["Data"]["RootChunk"]["resolvedDependencies"])
        self.assertEqual(male, judy, "Male entity must remain the existing authored passive subset")


if __name__ == "__main__":
    unittest.main()
