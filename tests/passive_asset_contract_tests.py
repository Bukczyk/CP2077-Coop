"""Mutation guards for the existing passive Judy asset subset, without game files.

Run: python tests/passive_asset_contract_tests.py
These checks establish source/build acceptance only, not HOST appearance parity.
"""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
IDLE = ROOT / "runtime/session/assets/source/raw/base/cp2077coop"
ENCOUNTER = ROOT / "experiments/shared-encounter/assets/raw/base/cp2077coop"


def load_builder(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"scripts/build-passive-{name}-archive.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BUILDERS = {
    "idle": (load_builder("idle"), IDLE / "entities/CP2077Coop_NetworkHumanoid.ent.json",
             IDLE / "animations/networkhumanoid_idle.animgraph.json"),
    "encounter": (load_builder("encounter"), ENCOUNTER / "entities/cp2077coop_networkhumanoid_encounter.ent.json",
                  ENCOUNTER / "animations/networkhumanoid_encounter.animgraph.json"),
    "hittable": (load_builder("hittable"), ENCOUNTER / "entities/cp2077coop_networkhumanoid_hittable.ent.json", None),
}


def components(root):
    return root["components"], root["compiledData"]["Data"]["Chunks"][1:]


class PassiveVisualContract(unittest.TestCase):
    def validate_all(self, mutate=None, error=None):
        for name, (builder, source, graph) in BUILDERS.items():
            with self.subTest(builder=name):
                doc = json.loads(source.read_text(encoding="utf-8-sig"))
                if mutate:
                    mutate(doc["Data"]["RootChunk"])
                with tempfile.TemporaryDirectory() as tmp:
                    candidate = Path(tmp) / "candidate.ent.json"
                    candidate.write_text(json.dumps(doc), encoding="utf8")

                    def validate():
                        if graph is None:
                            builder.validate(candidate)
                        else:
                            builder.validate_sources(candidate, graph)

                    if error:
                        with self.assertRaisesRegex(ValueError, error):
                            validate()
                    else:
                        validate()

    def test_reviewed_sources_pass_all_three_builders(self):
        self.validate_all()

    def test_inline_and_referenced_identical_bindings_remain_valid(self):
        def mutate(root):
            root["components"][1]["skinning"] = copy.deepcopy(root["compiledData"]["Data"]["Chunks"][2]["skinning"])
        self.validate_all(mutate)

    def test_wrong_resource_type_cannot_replace_mesh_in_both_copies(self):
        def mutate(root):
            for group in components(root):
                group[1]["mesh"]["DepotPath"]["$value"] = BUILDERS["idle"][0].RIG
        self.validate_all(mutate, "reviewed Judy mesh")

    def test_template_mesh_drift_from_compiled_copy_is_rejected(self):
        def mutate(root):
            root["components"][1]["mesh"]["DepotPath"]["$value"] = BUILDERS["idle"][0].RIG
        self.validate_all(mutate, "visual components differ")

    def test_compiled_mesh_drift_from_template_copy_is_rejected(self):
        def mutate(root):
            root["compiledData"]["Data"]["Chunks"][2]["chunkMask"] = "0"
        self.validate_all(mutate, "visual components differ")

    def test_animated_component_drift_is_rejected(self):
        def mutate(root):
            root["components"][0]["clientForcedLod"] = 1
        self.validate_all(mutate, "visual components differ")

    def test_empty_mesh_appearance_is_not_an_approved_variant(self):
        def mutate(root):
            for group in components(root):
                group[1]["meshAppearance"]["$value"] = ""
        self.validate_all(mutate, "default mesh appearance")

    def test_empty_template_default_appearance_is_rejected(self):
        self.validate_all(lambda root: root["defaultAppearance"].update({"$value": ""}), "default appearance")

    def test_disabled_mesh_is_rejected(self):
        def mutate(root):
            for group in components(root):
                group[1]["isEnabled"] = 0
        self.validate_all(mutate, "mesh must stay enabled")

    def test_zero_draw_mask_is_rejected_even_when_copies_match(self):
        def mutate(root):
            for group in components(root):
                group[1]["chunkMask"] = "0"
        self.validate_all(mutate, "draw mask")

    def test_shifted_visual_is_rejected_even_when_copies_match(self):
        for component in (0, 1):
            with self.subTest(component=component):
                def mutate(root):
                    for group in components(root):
                        group[component]["localTransform"]["Position"]["x"]["Bits"] = 131072
                self.validate_all(mutate, "identity local transform")

    def test_rotated_visual_is_rejected_even_when_copies_match(self):
        for component in (0, 1):
            with self.subTest(component=component):
                def mutate(root):
                    for group in components(root):
                        group[component]["localTransform"]["Orientation"].update({"k": 1, "r": 0})
                self.validate_all(mutate, "identity local transform")

    def test_unresolved_skinning_reference_is_rejected(self):
        def mutate(root):
            root["components"][1]["skinning"] = {"HandleRefId": "missing"}
        self.validate_all(mutate, "Unresolved entity handle")

    def test_conflicting_handle_definition_is_rejected(self):
        def mutate(root):
            binding = copy.deepcopy(root["compiledData"]["Data"]["Chunks"][2]["skinning"])
            binding["Data"]["enabled"] = 0
            root["components"][1]["skinning"] = binding
        self.validate_all(mutate, "Conflicting entity handle")

    def test_cyclic_binding_reference_is_rejected(self):
        def mutate(root):
            binding = root["compiledData"]["Data"]["Chunks"][2]["skinning"]
            binding["Data"]["parentTransform"] = {"HandleRefId": binding["HandleId"]}
        self.validate_all(mutate, "Cyclic entity handle")

    def test_ambiguous_reference_cannot_override_shared_binding(self):
        def mutate(root):
            root["components"][1]["skinning"]["Data"] = {}
        self.validate_all(mutate, "Ambiguous entity handle reference")

    def test_missing_skinning_binding_is_rejected(self):
        def mutate(root):
            for group in components(root):
                group[1]["skinning"] = None
        self.validate_all(mutate, "Invalid mesh skinning binding")

    def test_mesh_binding_to_wrong_component_is_rejected(self):
        def mutate(root):
            root["compiledData"]["Data"]["Chunks"][2]["skinning"]["Data"]["bindName"]["$value"] = ""
        self.validate_all(mutate, "must target the reviewed animated component")

    def test_disabled_parent_binding_is_rejected(self):
        def mutate(root):
            root["compiledData"]["Data"]["Chunks"][2]["parentTransform"]["Data"]["enabled"] = 0
        self.validate_all(mutate, "must target the reviewed animated component")

    def test_npc_root_is_rejected(self):
        self.validate_all(lambda root: root["entity"]["Data"].update({"$type": "NPCPuppet"}), "entEntity")

    def test_extra_gameplay_component_is_rejected(self):
        def mutate(root):
            for group in (root["components"], root["compiledData"]["Data"]["Chunks"]):
                group.append({"$type": "AIControllerComponent"})
        self.validate_all(mutate, "[Uu]nexpected.*component")

    def test_inherited_templates_and_appearance_overrides_are_rejected(self):
        for field in ("includes", "appearances", "backendDataOverrides", "bindingOverrides",
                      "componentResolveSettings", "inplaceResources"):
            with self.subTest(field=field):
                self.validate_all(lambda root: root.update({field: [{}]}), "requires empty " + field)

    def test_extra_instance_or_visual_tag_data_is_rejected(self):
        for field in ("includeInstanceBuffer", "localData", "visualTagsSchema"):
            with self.subTest(field=field):
                self.validate_all(lambda root: root.update({field: {}}), "forbids " + field)


if __name__ == "__main__":
    unittest.main()
