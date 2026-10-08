"""Offline guards for the authored capsule's query-only collision contract.

Run: python tests/passive_hittable_asset_tests.py
The first regression case models the zero-mask archive from live trials 3-5.
These checks do not replace in-game physics registration or hit tests.
"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("hittable_builder", ROOT / "scripts/build-passive-hittable-archive.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
SOURCE = ROOT / "experiments/shared-encounter/assets/raw/base/cp2077coop/entities/cp2077coop_networkhumanoid_hittable.ent.json"


class CollisionContract(unittest.TestCase):
    def setUp(self):
        self.doc = json.loads(SOURCE.read_text(encoding="utf-8-sig"))

    def validate(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "candidate.json"
            path.write_text(json.dumps(self.doc), encoding="utf8")
            builder.validate(path)

    def filters(self):
        return [item for item in builder.idle.walk(self.doc) if item.get("$type") == "physicsFilterData"]

    def test_authored_query_only_profile_is_accepted(self):
        self.validate()

    def test_previously_packable_zero_query_masks_are_rejected(self):
        for item in self.filters():
            item["queryFilter"]["mask2"] = "0"
        with self.assertRaisesRegex(ValueError, "Cooked query mask"):
            self.validate()

    def test_extra_query_bit_cannot_silently_widen_ai_only_capsule(self):
        for item in self.filters():
            item["queryFilter"]["mask2"] = "6"
        with self.assertRaisesRegex(ValueError, "Cooked query mask"):
            self.validate()

    def test_previous_static_numeric_profile_is_rejected(self):
        for item in self.filters():
            item["queryFilter"]["mask2"] = "4"
        with self.assertRaisesRegex(ValueError, "Cooked query mask"):
            self.validate()

    def test_contact_enabled_preset_is_rejected_even_with_zero_numeric_masks(self):
        for item in self.filters():
            item["preset"]["$value"] = "World Static"
        with self.assertRaisesRegex(ValueError, "query-only NPC Hitbox preset"):
            self.validate()

    def test_shape_cannot_override_component_filter(self):
        for item in builder.idle.walk(self.doc):
            if item.get("$type") == "physicsColliderCapsule":
                item["filterData"] = {"HandleRefId": "11"}
        with self.assertRaisesRegex(ValueError, "inherit the component"):
            self.validate()

    def test_simulation_collision_cannot_be_enabled_by_numeric_mask(self):
        for item in self.filters():
            item["simulationFilter"]["mask1"] = "4"
        with self.assertRaisesRegex(ValueError, "simulation masks"):
            self.validate()

    def test_physical_shape_cannot_replace_query_only_shape(self):
        for item in builder.idle.walk(self.doc):
            if item.get("$type") == "physicsColliderCapsule":
                item["isQueryShapeOnly"] = 0
        with self.assertRaisesRegex(ValueError, "query-only capsule"):
            self.validate()

    def test_npc_root_cannot_replace_passive_entity(self):
        self.doc["Data"]["RootChunk"]["entity"]["Data"]["$type"] = "NPCPuppet"
        with self.assertRaisesRegex(ValueError, "non-NPC entEntity"):
            self.validate()


if __name__ == "__main__":
    unittest.main()
