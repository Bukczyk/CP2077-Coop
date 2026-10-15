"""Exact authored defeated sampling contract. No installed resource access."""
from pathlib import Path
import copy
import importlib.util
import json
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("defeated_profile_tests", ROOT / "experiments/passive-models/build_encounter_profile.py")
BUILDER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BUILDER
SPEC.loader.exec_module(BUILDER)


def groups(doc):
    root = doc["Data"]["RootChunk"]
    return root["components"], root["compiledData"]["Data"]["Chunks"][1:]


def graph_nodes(doc):
    return {v["HandleId"]: v["Data"] for v in BUILDER.idle.walk(doc["Data"]) if "HandleId" in v}


class DefeatedAssets(unittest.TestCase):
    def validate(self, name="mitch_default", entity=None, graph=None, reject=False):
        profile = BUILDER.defeated_profile(name)
        e = json.loads(profile.source.read_text(encoding="utf-8-sig"))
        g = json.loads(BUILDER.DEFEATED_GRAPH_SOURCE.read_text(encoding="utf-8-sig"))
        if entity:
            entity(e)
        if graph:
            graph(g)
        with tempfile.TemporaryDirectory() as tmp:
            ep, gp = Path(tmp)/"entity.json", Path(tmp)/"graph.json"
            ep.write_text(json.dumps(e), encoding="utf-8")
            gp.write_text(json.dumps(g), encoding="utf-8")
            if reject:
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    BUILDER.validate(name, ep, gp, "defeated_hold")
            else:
                BUILDER.validate(name, ep, gp, "defeated_hold")

    def test_both_explicit_profiles_and_default_behavior(self):
        self.assertEqual(tuple(BUILDER.PROFILES), ("judy_default", "mitch_default"))
        for name in BUILDER.PROFILES:
            self.validate(name)
            self.assertEqual(BUILDER.validate(name), BUILDER.PROFILES[name])
            self.assertNotEqual(BUILDER.validate(name, presentation="defeated_hold").entity, BUILDER.PROFILES[name].entity)

    def test_unknown_modes_and_profiles_never_fallback(self):
        for mode in (None, False, 0, "", "death", "defeated", "DEFEATED_HOLD"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                BUILDER.validate("judy_default", presentation=mode)
        for name in (None, 1, "", "unknown", "judy_encounter"):
            with self.subTest(profile=name), self.assertRaises(ValueError):
                BUILDER.validate(name, presentation="defeated_hold")

    def test_no_implicit_graph_or_profile_mode_swap(self):
        for name in BUILDER.PROFILES:
            with self.assertRaises(ValueError):
                BUILDER.validate(name, BUILDER.defeated_profile(name).source, BUILDER.DEFEATED_GRAPH_SOURCE)
            with self.assertRaises(ValueError):
                BUILDER.validate(name, BUILDER.PROFILES[name].source, BUILDER.GRAPH_SOURCE, "defeated_hold")

    def test_exact_metadata_and_exposed_sample_range(self):
        self.assertEqual(BUILDER.DEFEATED_CLIP, "defeated_loop_01")
        self.assertEqual(BUILDER.DEFEATED_DURATION, 10.3000002)
        graph = json.loads(BUILDER.DEFEATED_GRAPH_SOURCE.read_text())
        nodes = graph_nodes(graph)
        self.assertEqual(nodes["2"]["$type"], "animAnimNode_SkFrameAnim")
        self.assertEqual(nodes["3"]["variableName"]["$value"], "cp_coop_defeated_progress")
        self.assertEqual([nodes["5"][k] for k in ("value", "default", "min", "max")], [0, 0, 0, 1])
        self.assertEqual(nodes["2"]["progressLink"]["node"]["HandleId"], "3")
        self.assertNotIn("cp_coop_death_progress", json.dumps(graph))

    def test_wrong_profile_and_both_copy_resource_substitution(self):
        for name, other in (("judy_default", "mitch_default"), ("mitch_default", "judy_default")):
            with self.assertRaises(ValueError):
                BUILDER.validate(name, BUILDER.defeated_profile(other).source, presentation="defeated_hold")
            alternate = BUILDER.defeated_profile(other)
            for field in ("mesh", "rig", "animset"):
                def change(doc):
                    for animated, mesh, _ in groups(doc):
                        if field == "mesh": mesh["mesh"] = BUILDER.resource(alternate.mesh, "Default")
                        elif field == "rig": animated["rig"] = BUILDER.resource(alternate.rig, "Obligatory")
                        else: animated["animations"]["gameplay"][0]["animSet"] = BUILDER.resource(alternate.sets[0], "Default")
                with self.subTest(profile=name, field=field):
                    self.validate(name, entity=change, reject=True)

    def test_template_compiled_disagreement(self):
        for index in (0, 1):
            def change(doc):
                groups(doc)[index][1]["meshAppearance"]["$value"] = "other"
            self.validate(entity=change, reject=True)

    def test_exact_dependency_order_flags_and_storage(self):
        for change in (
            lambda deps: deps.pop(), lambda deps: deps.append(copy.deepcopy(deps[0])), lambda deps: deps.reverse(),
            lambda deps: deps[1].update(Flags="Default"),
            lambda deps: deps[1]["DepotPath"].update({"$storage": "uint64"}),
            lambda deps: deps[1]["DepotPath"].update({"$value": BUILDER.encounter.GRAPH}),
        ):
            self.validate(entity=lambda d: change(d["Data"]["RootChunk"]["resolvedDependencies"]), reject=True)

    def test_only_one_unconditional_defeated_set(self):
        for mode in ("extra", "none", "condition", "priority", "cinematic", "wrong_flag"):
            def change(doc):
                for animated, _, _ in groups(doc):
                    setup = animated["animations"]
                    if mode == "extra": setup["gameplay"].append(copy.deepcopy(setup["gameplay"][0]))
                    elif mode == "none": setup["gameplay"] = []
                    elif mode == "condition": setup["gameplay"][0]["variableNames"] = ["unreviewed"]
                    elif mode == "priority": setup["gameplay"][0]["priority"] = 999
                    elif mode == "cinematic": setup["cinematics"] = [copy.deepcopy(setup["gameplay"][0])]
                    else: setup["gameplay"][0]["animSet"]["Flags"] = "Soft"
            with self.subTest(mode=mode): self.validate(entity=change, reject=True)

    def test_passive_root_and_forbidden_inheritance(self):
        def npc(doc):
            root = doc["Data"]["RootChunk"]
            root["entity"]["Data"]["$type"] = "NPCPuppet"
            root["compiledData"]["Data"]["Chunks"][0]["$type"] = "NPCPuppet"
        self.validate(entity=npc, reject=True)
        for field in ("includes", "appearances", "backendDataOverrides", "bindingOverrides", "inplaceResources"):
            self.validate(entity=lambda d: d["Data"]["RootChunk"].update({field: [{"template": "vanilla.ent"}]}), reject=True)

    def test_no_extra_component_or_payload(self):
        def ai(doc):
            for components in groups(doc): components.append({"$type": "AIHumanComponent"})
        self.validate(entity=ai, reject=True)
        self.validate(entity=lambda d: d["Data"].update(EmbeddedFiles=[{"FileName": "animation.anims"}]), reject=True)
        self.validate(graph=lambda d: d["Data"].update(EmbeddedFiles=[{"FileName": "animation.anims"}]), reject=True)
        self.validate(entity=lambda d: d["Data"].update(UnknownPayload="data"), reject=True)

    def test_both_copy_visual_and_controller_changes(self):
        for field in ("mask", "transform", "appearance", "enabled", "binding", "binding_type", "controller_binding"):
            def change(doc):
                for animated, mesh, controller in groups(doc):
                    if field == "mask": mesh["chunkMask"] = "0"
                    elif field == "transform": animated["localTransform"]["Orientation"]["r"] = 0.5
                    elif field == "appearance": mesh["meshAppearance"]["$value"] = "other"
                    elif field == "enabled": mesh["isEnabled"] = 0
                    elif field == "binding": animated["controlBinding"]["enabled"] = 0
                    elif field == "binding_type": animated["controlBinding"]["$type"] = "entHardTransformBinding"
                    else: controller["controlBinding"] = copy.deepcopy(animated["controlBinding"])
            with self.subTest(field=field): self.validate(entity=change, reject=True)

    def test_exact_clip_not_entry_death_or_other_loop(self):
        for clip in ("death_front_torso_l_idle", "defeated_front_torso_l_idle", "defeated_loop_02", "idle_stand", ""):
            self.validate(graph=lambda d: graph_nodes(d)["2"]["animation"].update({"$value": clip}), reject=True)

    def test_no_motion_events_or_playback(self):
        for field in ("isLooped", "applyMotion", "collectEvents", "fireAnimLoopEvent", "resume", "fireAnimEndOnceOnAnimEnd"):
            self.validate(graph=lambda d: graph_nodes(d)["2"].update({field: 1}), reject=True)
        for field in ("useAnimCommands", "useAnimCommandsForCrowd", "useAnimStaticCommands", "isPaused", "hackAlwaysSample"):
            self.validate(graph=lambda d: d["Data"]["RootChunk"].update({field: 1}), reject=True)

    def test_no_features_or_databases(self):
        for field in ("animFeatures", "additionalAnimDatabases"):
            self.validate(graph=lambda d: d["Data"]["RootChunk"].update({field: ["unreviewed"]}), reject=True)

    def test_exact_progress_input_range_and_initial_value(self):
        for field, value in (("value", .5), ("default", .5), ("min", -1), ("max", 0), ("max", 2), ("max", True)):
            self.validate(graph=lambda d: graph_nodes(d)["5"].update({field: value}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["3"]["variableName"].update({"$value": "cp_coop_death_progress"}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["5"]["name"].update({"$value": "different"}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["4"]["floatVariables"].append({"HandleRefId": "5"}), reject=True)

    def test_active_topology_and_initialization(self):
        self.validate(graph=lambda d: graph_nodes(d)["1"]["node"].update(node={"HandleRefId": "3"}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["2"]["progressLink"].update(node={"HandleRefId": "1"}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["2"].update({"$type": "animAnimNode_SkAnim"}), reject=True)
        self.validate(graph=lambda d: d["Data"]["RootChunk"].update(rootNode={"HandleRefId": "2"}), reject=True)
        self.validate(graph=lambda d: d["Data"]["RootChunk"]["nodesToInit"].pop(), reject=True)
        self.validate(graph=lambda d: d["Data"]["RootChunk"]["nodesToInit"].append({"HandleRefId": "2"}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["0"]["nodes"].pop(), reject=True)

    def test_handle_ambiguity_dangling_cycle_and_conflicting_definitions(self):
        self.validate(graph=lambda d: d["Data"]["RootChunk"]["rootNode"].update(Data={}), reject=True)
        self.validate(graph=lambda d: d["Data"]["RootChunk"].update(rootNode={"HandleRefId": "999"}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["3"].update(cycle={"HandleRefId": "3"}), reject=True)
        def conflict(doc):
            node = copy.deepcopy(graph_nodes(doc)["3"])
            node["variableName"]["$value"] = "other"
            doc["Data"]["RootChunk"]["nodesToInit"][3] = {"HandleId": "3", "Data": node}
        self.validate(graph=conflict, reject=True)
        for bad in (None, 3, "", "-1", "１２"):
            self.validate(graph=lambda d: d["Data"]["RootChunk"]["rootNode"].update(HandleRefId=bad), reject=True)

    def test_equivalent_identical_handle_definitions_and_renumbering(self):
        def equivalent(doc):
            node = copy.deepcopy(graph_nodes(doc)["3"])
            doc["Data"]["RootChunk"]["nodesToInit"][3] = {"HandleId": "3", "Data": node}
            for value in BUILDER.idle.walk(doc["Data"]):
                for field in ("HandleId", "HandleRefId"):
                    if field in value: value[field] = str(int(value[field])+100)
        self.validate(graph=equivalent)

    def test_active_aliases_cannot_be_equal_but_distinct_uninitialized_nodes(self):
        def root_alias(doc):
            original = copy.deepcopy(graph_nodes(doc)["0"])
            doc["Data"]["RootChunk"]["rootNode"] = {"HandleId": "99", "Data": original}
        self.validate(graph=root_alias, reject=True)
        def variable_alias(doc):
            nodes = graph_nodes(doc)
            original = copy.deepcopy(nodes["3"])
            # Keep the original node initialized, then point the active link at
            # a distinct otherwise identical object that is not initialized.
            doc["Data"]["RootChunk"]["nodesToInit"][3] = {"HandleId": "3", "Data": original}
            nodes["2"]["progressLink"]["node"] = {"HandleId": "99", "Data": copy.deepcopy(original)}
        self.validate(graph=variable_alias, reject=True)
        def sample_alias(doc):
            nodes = graph_nodes(doc)
            original = copy.deepcopy(nodes["2"])
            doc["Data"]["RootChunk"]["nodesToInit"][2] = {"HandleId": "2", "Data": original}
            nodes["1"]["node"]["node"] = {"HandleId": "99", "Data": copy.deepcopy(original)}
        self.validate(graph=sample_alias, reject=True)

    def test_authored_graph_defines_before_referring(self):
        document = json.loads(BUILDER.DEFEATED_GRAPH_SOURCE.read_text())
        seen = set()
        for value in BUILDER.idle.walk(document["Data"]):
            if "HandleId" in value: seen.add(value["HandleId"])
            if "HandleRefId" in value: self.assertIn(value["HandleRefId"], seen)

    def test_materialized_wolvenkit_defaults_are_exact_not_ignored(self):
        for field, value in (("motionProvider", {"unreviewed": True}),
                             ("timeLink", {"$type": "animFloatLink", "node": {"HandleRefId": "3"}}),
                             ("frameLink", {"$type": "animFloatLink", "node": {"HandleRefId": "3"}}),
                             ("convertToAdditive", 1), ("applyInertializationOnAnimSetSwap", 0),
                             ("clipEnd", 0.5), ("clipFront", 0.2), ("visAxes", 1),
                             ("unreviewedDefault", 0)):
            self.validate(graph=lambda d: graph_nodes(d)["2"].update({field: value}), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["2"].pop("motionProvider"), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["5"].update(enableDebug=1), reject=True)
        self.validate(graph=lambda d: d["Data"]["RootChunk"]["staticCommandsRig"]["DepotPath"].update({"$value": "1"}), reject=True)

    def test_schema_and_boolean_number_distinction(self):
        self.validate(graph=lambda d: d["Header"].update(WolvenKitVersion="8.0.0"), reject=True)
        self.validate(entity=lambda d: d["Header"].update(WolvenKitVersion="8.0.0"), reject=True)
        self.validate(graph=lambda d: graph_nodes(d)["2"].update(applyMotion=False), reject=True)
        self.validate(entity=lambda d: d["Data"].update(Version=True), reject=True)

    def test_lf_and_crlf_portability(self):
        with tempfile.TemporaryDirectory() as tmp:
            for newline in (b"\n", b"\r\n"):
                for name in BUILDER.PROFILES:
                    ep, gp = Path(tmp)/"entity.json", Path(tmp)/"graph.json"
                    for source, dest in ((BUILDER.defeated_profile(name).source, ep), (BUILDER.DEFEATED_GRAPH_SOURCE, gp)):
                        dest.write_bytes(source.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", newline))
                    BUILDER.validate(name, ep, gp, "defeated_hold")

    def test_original_source_pins_and_default_profiles(self):
        self.assertEqual(BUILDER.source_lf_sha(BUILDER.REFERENCE), BUILDER.REFERENCE_LF_SHA256)
        self.assertEqual(BUILDER.source_lf_sha(BUILDER.GRAPH_SOURCE), BUILDER.GRAPH_LF_SHA256)
        for name in BUILDER.PROFILES:
            BUILDER.validate(name)


if __name__ == "__main__":
    unittest.main()
