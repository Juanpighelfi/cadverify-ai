"""Offline tests of the harness around an assembly: its gates, the spec history, the close of
G8, the look before a question and the images that leave the context. Same fakes as
test_agent.py."""

import json

from cadverify import summary
from cadverify.agent import closing, gates, prompts, tools
from cadverify.agent.loop import Limits, run_session
from cadverify.agent.spec_history import MAX_NOTE_ITEMS, SpecHistory, notes
from cadverify.agent.tools import ToolBox
from tests.test_agent import (
    DEFAULT,
    GOOD_CHECK,
    GOOD_MESH,
    SPEC,
    FakeModel,
    FakeSandbox,
    _args,
    _verify,
    instance_bytes,
    part_bytes,
    sha,
)

PARTS = ("base", "lid")
SOURCE = 'part = "base"; // [base, lid, assembly]\ncube(10);\n'
EXPORT = {p: f"exports/model.{p}.44136fa3.stl" for p in (*PARTS, "assembly")}
INSTANCE = {p: f"checks/assembly/model.assembly.{p}.stl" for p in PARTS}
PART_SHA = {p: sha(part_bytes(p)) for p in PARTS}
INSTANCE_SHAS = {sha(instance_bytes(p)) for p in PARTS}
RIB = {"name": "rib", "kind": "material", "box": [[0, 0, 0], [1, 1, 1]], "fraction": 0.8}


def assembly_report(g3=(), g4=(), **extra):
    return {
        "ok": not g3 and not g4,
        "problems": {"G3": list(g3), "G4": list(g4)},
        "instances": [
            {
                "name": p,
                "part": p,
                "unit": 1,
                "stl": f"/work/{INSTANCE[p]}",
                "sha256": sha(instance_bytes(p)),
                "volume_mm3": 1000.0,
                "bounds": [[0, 0, 0], [10, 10, 10]],
                "congruent": True,
            }
            for p in PARTS
        ],
        "pairs": [{"a": "base", "b": "lid", "gap_mm": 0.0, "contact": True}],
        "components": [list(PARTS)],
        "units": {"required": 1, "present": [1], "links": []},
        "copies": [{"part": p, "expected": 1, "placed": 1, "ok": True} for p in PARTS],
        "motions": [],
        "assembly_steps": [
            {"step": 1, "instances": ["base"], "ok": True},
            {"step": 2, "instances": ["lid"], "ok": True},
        ],
        "assembly_order_ok": True,
        "spec": {"bounds": None, "support_faces": [], "assembly_order": []},
        "spec_error": None,
        "errors": [],
        "seconds": 1.2,
        **extra,
    }


def verify_two_parts(assembly=None, spec=SPEC, check=GOOD_CHECK, printability=None):
    verify = _verify(spec=spec, check=check, printability=printability)
    template = verify["parts"][0]
    verify["parts"] = [
        {
            "part": p,
            "export": {
                **template["export"],
                "path": f"/work/checks/exports/model.{p}.x.stl",
                "sha256": PART_SHA[p],
            },
            "printability": template["printability"],
        }
        for p in PARTS
    ]
    verify["assembly"] = assembly if assembly is not None else assembly_report()
    return verify


def two_part_toolbox(tmp_path, verify=None, assembly=None, **kwargs) -> ToolBox:
    workspace = tmp_path / "workspace"
    workspace.mkdir(exist_ok=True)
    box = FakeSandbox(workspace, verify or verify_two_parts(), assembly or assembly_report())
    box.restore({"model.scad": SOURCE.encode()})
    return ToolBox(box, tmp_path / "tools", **kwargs)


def evaluate(verify, views=(INSTANCE_SHAS,), close_views=()):
    return gates.evaluate(
        verify,
        set(PART_SHA.values()),
        PART_SHA,
        view_groups=[set(v) for v in views],
        close_views=set(close_views),
    )


LOOK = [
    *[("scad_export", {"path": "model.scad", "part": p}) for p in PARTS],
    *[("render_sheet", {"stl": EXPORT[p]}) for p in PARTS],
    ("interference_check", {"path": "model.scad"}),
    ("render_view", {"stl": list(INSTANCE.values())}),
]


# ---- gates --------------------------------------------------------------------------------


def test_an_assembly_seen_and_measured_leaves_only_the_close():
    result = evaluate(verify_two_parts())
    assert gates.green_but(result, "G8") and result["G8"]["ok"] is None


def test_g5_judges_an_assembly_printed_in_place():
    gap = "base and lid are 0.15 mm apart: printed in place they fuse (print_in_place asks ...)"
    zone = {"declared": False, "max_angle_deg": 90.0, "area_mm2": 113.1, "bounds": [[0, 0, 5]]}
    printed = {"ok": True, "fits_bed": True, "zones": [zone], "zones_undeclared": 1}
    in_place = {"min_gap_mm": 0.3, "instances": list(PARTS), "gaps": [], "printability": printed}
    report = assembly_report(print_in_place=in_place)
    report["problems"]["G5"] = [gap]
    detail = evaluate(verify_two_parts(report))["G5"]["detail"]
    assert detail == [
        f"printed in place: {gap}",
        "assembly as printed in place: undeclared 90.0° overhang (113.1 mm², bounds [[0, 0, 5]])",
    ]
    clean = dict(printed, zones=[], zones_undeclared=0)
    report = assembly_report(print_in_place=dict(in_place, printability=clean))
    report["problems"]["G5"] = []
    result = evaluate(verify_two_parts(report))
    assert gates.green_but(result, "G8")
    state = {"gates": result, "parts": [], "assembly": report}
    assert closing.reference_problems("[[print_in_place]]", state) == []
    assert closing.reference_problems("[[print_in_place]]", _state(True))[0].startswith(
        "[[print_in_place]] names nothing"
    )


def test_g7_needs_the_instances_of_the_final_assembly_seen_together():
    one = {sha(instance_bytes("base"))}
    detail = evaluate(verify_two_parts(), views=[one, {sha(instance_bytes("lid"))}])["G7"]
    assert not detail["ok"] and "together in one render_view" in detail["detail"][0]
    assert evaluate(verify_two_parts(), views=[INSTANCE_SHAS | {"other"}])["G7"]["ok"]


def test_g3_and_g4_come_from_the_assembly_report():
    overlap = "base and lid overlap 638.4 mm³, 1.2 mm mean thickness, at [...]"
    motion = "motion hinge: collides between 10° and 40°; ..."
    result = evaluate(verify_two_parts(assembly_report(g3=[overlap], g4=[motion])))
    assert result["G3"]["detail"][0] == overlap
    assert "interference_check measures the same" in result["G3"]["detail"][1]
    assert result["G4"] == {"ok": False, "detail": [motion]}
    missing = evaluate(verify_two_parts({"ok": False, "missing": True}))["G3"]
    assert 'the part selector has no "assembly"' in missing["detail"][0]
    assert evaluate(verify_two_parts({"ok": True, "not_needed": True}))["G3"]["ok"]
    broken = evaluate(verify_two_parts({"ok": False, "error": "timeout"}))["G3"]["detail"]
    assert broken == ["the assembly could not be measured: timeout"]
    unmeasured = gates.evaluate(dict(verify_two_parts(), assembly={}), set(), {})["G3"]
    assert unmeasured["detail"] == ["the verification did not measure the assembly"]


def test_g7_reports_each_failing_detail_with_what_it_measured():
    rib = {**RIB, "material_fraction": 0.0, "min_fraction": 0.8, "ok": False}
    flare = {
        "name": "flare",
        "kind": "hole",
        "ok": False,
        "mouth": [0, -102.9, 19.95],
        "diameters": [
            {"depth_mm": 0, "expected_mm": 14, "measured_mm": 9.99, "ok": False},
            {"depth_mm": 2, "expected_mm": 11, "measured_mm": 11.0, "ok": True},
        ],
        "profile": [[0, 9.99], [0.5, 13.98], [2, 11.0], [3, None]],
    }
    check = dict(GOOD_CHECK, ok=False, details=[rib, flare])
    detail = gates.evaluate(_verify(check=check), {"s"}, {DEFAULT: "s"})["G7"]
    assert detail["detail"] == [
        "default output: detail rib (material): 0% of the box [[0, 0, 0], [1, 1, 1]] has "
        "material; at least 80% was declared",
        "default output: detail flare (hole): mouth at [0, -102.9, 19.95]; Ø9.99 at 0 mm from "
        "the mouth (Ø14 declared). Measured profile (mm: Ø): 0: 9.99, 0.5: 13.98, 2: 11.0, 3: -",
    ]


def test_g7_says_the_export_brings_the_sheet():
    detail = gates.evaluate(verify_two_parts(), set(), PART_SHA)["G7"]["detail"]
    assert (
        "base: you did not see the sheet of the final version (export it with the default "
        "parameters: scad_export brings its sheet)" in detail
    )


def test_g7_needs_a_close_look_at_each_view_detail():
    medallion = {"name": "medallion", "kind": "view", "box": [[0, 0, 0], [1, 1, 1]]}
    verify = verify_two_parts(spec=dict(SPEC, details=[medallion]))
    detail = evaluate(verify)["G7"]["detail"]
    assert len(detail) == 2 and "you did not look closely at the detail medallion" in detail[0]
    looked = {(PART_SHA[p], "medallion") for p in PARTS}
    assert evaluate(verify, close_views=looked)["G7"]["ok"]


# ---- the spec history ---------------------------------------------------------------------


def _export(spec, check, sha256="a", mesh=None):
    return {
        "ok": True,
        "spec": spec,
        "spec_check": check,
        "mesh": mesh or GOOD_MESH,
        "sha256": sha256,
    }


def test_a_spec_moved_to_what_the_mesh_measured_is_flagged():
    history = SpecHistory()
    failing = dict(GOOD_CHECK, ok=False, bodies={"ok": False, "expected": 4, "actual": 1})
    assert history.observe_part("lid", _export(dict(SPEC, bodies=4), failing)) == []
    (found,) = history.observe_part("lid", _export(SPEC, GOOD_CHECK), seq=7)
    assert (found["item"], found["from"], found["to"], found["measured"]) == ("bodies", 4, 1, 1)
    assert found["why"] == "the mesh is the same" and found["seq"] == 7
    assert found["text"] == "bodies from 4 to 1, the mesh measures 1 (the mesh is the same)"
    assert history.observe_part("lid", _export(SPEC, GOOD_CHECK)) == []  # once

    # The geometry fixed: the spec stays, the mesh changes. Not an adjustment.
    fixed = SpecHistory()
    fixed.observe_part("lid", _export(dict(SPEC, bodies=4), failing))
    mesh = dict(GOOD_MESH, bodies=4)
    check = dict(GOOD_CHECK, bodies={"ok": True, "expected": 4, "actual": 4})
    assert fixed.observe_part("lid", _export(dict(SPEC, bodies=4), check, "b", mesh)) == []


def test_a_bounds_coordinate_moved_while_the_rest_changed_is_flagged():
    history = SpecHistory()
    tall = dict(SPEC, bounds=[[0, 0, 0], [10, 10, 12]])
    deviation = "max z: measured 10.000, specified 12 (off by -2.000 mm)"
    check = dict(GOOD_CHECK, ok=False, bounds={"ok": False, "deviations": [deviation]})
    history.observe_part("lid", _export(tall, check))
    wider = dict(GOOD_MESH, bounds=[[0, 0, 0], [11, 10, 10]])
    spec = dict(SPEC, bounds=[[0, 0, 0], [11, 10, 10]])
    (found,) = history.observe_part("lid", _export(spec, GOOD_CHECK, "b", wider))
    assert found["item"] == "bounds max z" and found["why"] == "what was measured did not change"
    assert (found["from"], found["to"], found["measured"]) == (12, 10, 10)


def test_a_bounds_coordinate_within_a_millimetre_of_the_mesh_is_not_flagged():
    # The rounding of a spec formula (one early session: 0.2 to 1 mm), not a defect hidden.
    history = SpecHistory()
    tall = dict(SPEC, bounds=[[0, 0, 0], [10, 10, 11]])
    deviation = "max z: measured 10.000, specified 11 (off by -1.000 mm)"
    check = dict(GOOD_CHECK, ok=False, bounds={"ok": False, "deviations": [deviation]})
    history.observe_part("lid", _export(tall, check))
    assert history.observe_part("lid", _export(SPEC, GOOD_CHECK)) == []


def test_the_notes_tell_the_adjustments_once_per_part():
    def adjustment(part, item):
        return {
            "part": part,
            "text": f"{item} from 1 to 2, the mesh measures 2 (the mesh is the same)",
        }

    many = [adjustment("lid", f"detail d{i}") for i in range(MAX_NOTE_ITEMS + 2)]
    lid, base = notes([*many, adjustment("base", "bodies")])
    assert lid.startswith(
        "lid: the spec moved toward what the mesh already measured: detail d0 from 1 to 2, the "
        "mesh measures 2 (the mesh is the same); detail d1"
    )
    assert f"detail d{MAX_NOTE_ITEMS - 1} from" in lid and f"d{MAX_NOTE_ITEMS} from" not in lid
    assert "; and 2 more. That way those checks pass" in lid and "say so in the close" in lid
    assert base.startswith("base: the spec moved") and base.count(" from 1 to 2") == 1


def test_an_adjustment_that_moves_a_box_says_what_moved():
    def spec(box):
        detail = {"name": "plate", "kind": "material", "box": box, "fraction": 0.9}
        return dict(SPEC, details=[detail])

    def check(ok, fraction):
        result = {"name": "plate", "kind": "material", "ok": ok, "material_fraction": fraction}
        return dict(GOOD_CHECK, ok=ok, details=[result])

    history = SpecHistory()
    history.observe_part("pin", _export(spec([[0, 0, 0], [1, 1, 1]]), check(False, 0.5)))
    (found,) = history.observe_part("pin", _export(spec([[0, 0, 2], [1, 1, 3]]), check(True, 1.0)))
    assert found["text"] == (
        "detail plate from box [[0, 0, 0], [1, 1, 1]] to box [[0, 0, 2], [1, 1, 3]], the mesh "
        "measures 1.0 (the mesh is the same)"
    )


def test_a_failing_check_taken_out_with_the_mesh_unchanged_is_flagged():
    history = SpecHistory()
    face = {
        "name": "wall",
        "direction": "-y",
        "ok": False,
        "min_area_mm2": 4800,
        "area_on_extreme_plane_mm2": 0.0,
    }
    spec = dict(SPEC, support_faces=[{"name": "wall", "direction": "-y", "min_area_mm2": 4800}])
    history.observe_part("lid", _export(spec, dict(GOOD_CHECK, ok=False, support_faces=[face])))
    (found,) = history.observe_part("lid", _export(SPEC, GOOD_CHECK))
    assert found["item"] == "support face wall" and found["to"] == "removed"


def test_assembly_adjustments_an_allowed_overlap_and_a_shorter_motion():
    history = SpecHistory()
    pair = {"a": "base", "b": "lid", "volume_mm3": 638.4, "thickness_mm": 1.2}
    motion = {"name": "hinge", "range": [0, 90], "ok": False, "collisions": {"from_to": [10, 40]}}
    history.observe_assembly(
        assembly_report(pairs=[{**pair, "interference": True}], motions=[motion])
    )
    found = history.observe_assembly(
        assembly_report(
            pairs=[{**pair, "permitted": "fit"}],
            motions=[{"name": "hinge", "range": [0, 5], "ok": True}],
        )
    )
    assert [f["item"] for f in found] == ["interference base / lid", "motion hinge"]
    assert found[0]["to"] == "permitted (fit)" and found[1]["to"] == [0, 5]
    assert all(f["part"] == "assembly" for f in found)


def test_assembly_adjustments_a_collision_declared_as_flex_and_a_clearance_moved():
    history = SpecHistory()
    worst = {"moving": "lid", "with": "base", "volume_mm3": 2.1, "thickness_mm": 0.2}
    collided = {"from_to": [80, 88], "worst": worst}
    motion = {"name": "lock", "range": [0, 90], "ok": False, "collisions": collided}
    gap = {"a": "base", "b": "lid", "gap_mm": 0.2}
    in_place = {"min_gap_mm": 0.3, "gaps": [{**gap, "ok": False}]}
    history.observe_assembly(assembly_report(motions=[motion], print_in_place=in_place))
    flex = {"a": "lid", "b": "base", "max_mm": 0.5, "depth_mm": 0.42, "ok": True, "at": 84}
    found = history.observe_assembly(
        assembly_report(
            motions=[{"name": "lock", "range": [0, 90], "ok": True, "flex": [flex]}],
            print_in_place={"min_gap_mm": 0.2, "gaps": [{**gap, "ok": True}]},
        )
    )
    assert [(f["item"], f["to"]) for f in found] == [
        ("print_in_place base / lid", 0.2),
        ("motion lock", "flex base / lid"),
    ]
    assert found[1]["why"] == "the collision is declared as a flex, with the parts unchanged"

    deeper = dict(flex, max_mm=0.3, ok=False)
    history.observe_assembly(
        assembly_report(motions=[{"name": "m", "range": [0, 9], "ok": False, "flex": [deeper]}])
    )
    (raised,) = history.observe_assembly(
        assembly_report(motions=[{"name": "m", "range": [0, 9], "ok": True, "flex": [flex]}])
    )
    assert raised["item"] == "motion m flex lid / base" and raised["measured"] == 0.42

    # Stuck at an end of the range, then free there after a change of geometry: the flex and its
    # depth did not move, so nothing declared did (a session was told "from 0.7 to 0.7").
    stuck = dict(flex, ok=False)
    instances = assembly_report()["instances"]
    history.observe_assembly(
        assembly_report(motions=[{"name": "n", "range": [0, 9], "ok": False, "flex": [stuck]}])
    )
    moved = [dict(i, sha256=f"other {i['name']}") for i in instances]
    freed = {"name": "n", "range": [0, 9], "ok": True, "flex": [flex]}
    assert history.observe_assembly(assembly_report(motions=[freed], instances=moved)) == []
    # With the parts unchanged, a shorter range is what freed it, and the note says so.
    history.observe_assembly(
        assembly_report(motions=[{"name": "s", "range": [0, 9], "ok": False, "flex": [stuck]}])
    )
    (shorter,) = history.observe_assembly(
        assembly_report(motions=[{"name": "s", "range": [0, 8], "ok": True, "flex": [flex]}])
    )
    assert shorter["text"] == (
        "motion s flex lid / base from range [0, 9] to range [0, 8], the mesh measures 0.42 "
        "(the mesh is the same)"
    )


# ---- the close ----------------------------------------------------------------------------


def _state(lid_ok=False):
    rib = {"name": "rib", "kind": "material", "ok": True}
    return {
        "source": "s",
        "gates": {g: {"ok": True, "detail": []} for g in gates.GATES},
        "parts": [
            {"part": "base", "ok": True, "spec_check": {"details": [rib]}},
            {"part": "lid", "ok": lid_ok, "spec_check": {"details": [{**rib, "ok": lid_ok}]}},
        ],
        "assembly": assembly_report(motions=[{"name": "hinge", "range": [0, 90], "ok": True}]),
    }


def test_the_references_of_a_close_must_exist_and_be_green():
    text = (
        "[[base]] [[base/rib]] [[rib]] [[cap]] [[lid]] [[assembly]] [[hinge]] "
        "[[assembly_order]] [[G5]] [[base]]"
    )
    problems = closing.reference_problems(text, _state())
    assert len(problems) == 3
    assert problems[0].startswith("[[rib]] is ambiguous")
    assert problems[1].startswith("[[cap]] names nothing")
    assert problems[2] == "[[lid]] cites the part lid, which is red"


def test_a_close_may_cite_the_assemblys_own_support_faces():
    state = _state(True)
    desk = {"name": "desk", "direction": "-z", "ok": True, "min_area_mm2": 3000}
    tray = {"name": "tray", "direction": "-z", "ok": False, "min_area_mm2": 9000}
    state["assembly"]["spec_check"] = {"support_faces": [desk, tray]}
    assert closing.reference_problems("[[desk]] [[assembly/desk]]", state) == []
    (problem,) = closing.reference_problems("[[tray]]", state)
    assert problem == "[[tray]] cites the support face tray of the assembly, which is red"


def test_the_auditor_reads_what_each_green_gate_verified():
    state = _state(True)
    state["gates"]["G4"] = {"ok": False, "detail": ["collides"]}
    mesh = {"watertight": True, "bad_edges": 0, "bodies": 1, "triangles": 12}
    state["parts"][0]["mesh"] = mesh
    verified = closing.summary(state)
    assert verified["gates"]["G4"] is False and "G8" not in verified["gates"]
    assert set(verified["green_means"]) == {"G1", "G2", "G3", "G5", "G7"}
    assert "0 bad edges" in verified["green_means"]["G2"]
    assert "close view of every detail of kind view" in verified["green_means"]["G7"]
    assert verified["parts"][0]["mesh"]["bad_edges"] == 0
    assert "triangles" not in verified["parts"][0]["mesh"]


def test_the_auditor_gets_the_printability_numbers_a_close_may_quote():
    zone = {"id": "v1", "area_mm2": 4.1, "max_angle_deg": 90.0, "bounds": [], "faces": 8}
    report = {
        "ok": True,
        "printer": "bambu_a1",
        "bed_mm": [256, 256, 256],
        "size": [80, 60, 40],
        "fits_bed": True,
        "bed_margin_mm": [88.0, 98.0, 216.0],
        "z_min": 0.0,
        "base_area_mm2": 4800.0,
        "overhang_area_mm2": 4.1,
        "zones_total": 1,
        "zones_undeclared": 0,
        "undeclared_area_mm2": 0,
        "zones": [{**zone, "declared": True, "declared_as": "pocket roofs"}],
        "allowed_coverage": {"share": 0.012, "per_box": [{"name": "pocket roofs"}]},
    }
    short = tools._short_printability(report)
    assert short["bed_margin_mm"] == [88.0, 98.0, 216.0] and short["overhang_area_mm2"] == 4.1
    assert short["allowed_share_of_surface"] == 0.012 and "printer" not in short
    assert short["zones"] == [
        {"id": "v1", "area_mm2": 4.1, "max_angle_deg": 90.0, "declared_as": "pocket roofs"}
    ]
    assert tools._short_printability({"ok": False, "error": "x"}) == {"ok": False, "error": "x"}


def test_the_auditor_judges_a_close_whose_references_pass():
    claim = {"claim": "holds 3 kg", "reason": "nobody measured it"}
    model = FakeModel([], audits=["Thinking... " + json.dumps({"unsupported": [claim]}) + " done"])
    g8, calls = closing.judge(model, "Holds 3 kg. [[base]]", _state(True), [], "it05")
    assert g8["ok"] is False and len(calls) == 1
    assert g8["detail"] == ["unsupported claim: holds 3 kg: nobody measured it"]
    request = model.audit_payloads[0]
    assert "tools" not in request and request["reasoning"] == {"effort": "medium"}
    assert "ADJUSTMENTS\n- (none)" in request["input"] and "CLOSE\nHolds" in request["input"]
    assert request["input"].startswith("REQUEST\n(none)\n")

    model = FakeModel([])
    g8, _ = closing.judge(model, "Good. [[base]]", _state(True), [], "it05")
    assert g8 == {
        "ok": True,
        "detail": [],
        "audit": {"unsupported": [], "untold_adjustments": [], "unmeasured": []},
    }

    # What the request asks for and the spec could declare, left unmeasured: the stress set's
    # ratchet closed green with a pawl that never touched its wheel and no stop declared.
    gap = {"requirement": "counterclockwise the pawl stops it", "how": "stops"}
    model = FakeModel([], audits=[json.dumps({"unmeasured": [gap]})])
    ratchet = "A ratchet: turned clockwise it clicks; counterclockwise the pawl stops it."
    g8, _ = closing.judge(model, "Good. [[base]]", _state(True), [], "it05", request=ratchet)
    assert g8["detail"] == ["requirement not measured: counterclockwise the pawl stops it: stops"]
    assert model.audit_payloads[0]["input"].startswith(f"REQUEST\n{ratchet}\n\nVERIFIED\n")

    adjustments = [
        {"part": "lid", "text": "bodies from 4 to 2, the mesh measures 2 (the mesh is the same)"},
        {"part": "base", "text": "bodies from 3 to 1, the mesh measures 1 (the mesh is the same)"},
        {
            "part": "lid",
            "text": "through_holes from 2 to 0, the mesh measures 0 (what was measured did not "
            "change)",
        },
    ]
    model = FakeModel([], audits=["not JSON", '{"unsupported": "wrong"}'])
    g8, calls = closing.judge(model, "Good.", _state(True), adjustments, "it05")
    assert g8["ok"] and "not_audited" in g8 and len(calls) == 2
    assert (
        "ADJUSTMENTS\n- lid: bodies from 4 to 2, the mesh measures 2 (the mesh is the same); "
        "through_holes from 2 to 0, the mesh measures 0 (what was measured did not change)\n"
        "- base: bodies from 3 to 1"
    ) in model.audit_payloads[0]["input"]

    model = FakeModel([])
    g8, calls = closing.judge(model, "[[cap]]", _state(True), [], "it05")
    assert not g8["ok"] and calls == [] and model.audit_payloads == []  # no auditor needed


def test_parse_audit():
    assert closing.parse_audit('{"unsupported": ["a"], "untold_adjustments": []}') == {
        "unsupported": ["a"],
        "untold_adjustments": [],
        "unmeasured": [],
    }
    empty = {"unsupported": [], "untold_adjustments": [], "unmeasured": []}
    assert closing.parse_audit("{}") == empty
    for bad in ("", "[1]", '{"unsupported": [1]}', '{"unmeasured": "stops"}', "{no"):
        assert closing.parse_audit(bad) is None


# ---- the tool box -------------------------------------------------------------------------


def test_interference_check_leaves_its_stl_to_look_at(tmp_path):
    toolbox = two_part_toolbox(tmp_path)
    toolbox.call("render_sheet", _args(stl="model.scad"), 1)  # any image: a check is pending
    result, _ = toolbox.call("interference_check", _args(path="model.scad"), 1)
    assert result["ok"] and result["green"] and "spec" not in result
    assert [i["stl"] for i in result["instances"]] == list(INSTANCE.values())
    assert toolbox.visual_pending is None  # a numeric check
    command = toolbox.sandbox.commands[-1]
    assert command[:4] == ["assembly", "model.scad", "--out-dir", "checks/assembly"]
    assert command[4] == "--requirements" and json.loads(command[5]) == {}
    view, _ = toolbox.call("render_view", _args(stl=list(INSTANCE.values())), 2)
    assert [part["label"] for part in view["parts"]] == list(PARTS)  # the instances' names
    assert toolbox.view_groups == [INSTANCE_SHAS]
    assert toolbox.image_log[3]["assembly"] and toolbox.image_log[3]["what"] == "base, lid"


def test_a_spec_adjustment_is_told_in_the_tool_result(tmp_path):
    toolbox = two_part_toolbox(tmp_path)
    failing = dict(GOOD_CHECK, ok=False, bodies={"ok": False, "expected": 4, "actual": 1})
    toolbox.sandbox.export_queue = [
        {"spec": dict(SPEC, bodies=4), "spec_check": failing},
        {"spec": SPEC, "spec_check": GOOD_CHECK},
    ]
    first, _ = toolbox.call("scad_export", _args(path="model.scad", part="base"), 1)
    assert "spec_notes" not in first
    toolbox.call("scad_patch", _args(path="model.scad", old="cube(10)", new="cube(10) "), 2)
    second, _ = toolbox.call("scad_export", _args(path="model.scad", part="base"), 3)
    (warning,) = second["spec_notes"]
    assert warning.startswith(
        "base: the spec moved toward what the mesh already measured: bodies from 4 to 1, the "
        "mesh measures 1"
    )
    assert toolbox.history.adjustments[0]["seq"] == 3


def test_an_export_of_a_new_mesh_brings_its_sheet(tmp_path):
    toolbox = two_part_toolbox(tmp_path)
    result, image = toolbox.call("scad_export", _args(path="model.scad", part="base"), 1)
    assert image and result["sheet"]["png"] == "renders/sheet-001.png"
    assert toolbox.sandbox.commands[-1][:2] == ["sheet", EXPORT["base"]]
    assert toolbox.sandbox.commands[0][-2:] == ["--part", "base"]
    assert PART_SHA["base"] in toolbox.seen_sheets and toolbox.look_missing() == [
        "compile model.scad (scad_compile)",
        'export the part "lid" with the default parameters and look at it (scad_export brings '
        "its sheet)",
        'export the part "assembly" with the default parameters and look at it (scad_export '
        "brings its sheet)",
    ]
    assert toolbox.visual_pending is None  # it comes with the export's numbers
    patched, _ = toolbox.call(
        "scad_patch", _args(path="model.scad", old="cube(10)", new="cube(11)"), 2
    )
    assert patched["ok"]
    assert toolbox.image_log[1]["tool"] == "render_sheet"
    assert toolbox.image_log[1]["parts"] == ["base"]
    assert toolbox.images["scad_export"] == 1

    # Not again for a mesh already seen, nor with overrides, nor for another file.
    again, image = toolbox.call("scad_export", _args(path="model.scad", part="base"), 3)
    assert image is None and "sheet" not in again
    toolbox.sandbox.export_queue = [{"bytes": b"solid other\nendsolid other\n"}] * 2
    _, image = toolbox.call(
        "scad_export", _args(path="model.scad", part="lid", overrides={"h": 3}), 4
    )
    assert image is None
    toolbox.call("scad_write", _args(path="other.scad", content="cube(1);\n"), 5)
    _, image = toolbox.call("scad_export", _args(path="other.scad"), 6)
    assert image is None
    assert [c[0] for c in toolbox.sandbox.commands].count("sheet") == 1


def test_the_verification_measures_the_assembly_with_the_requirements(tmp_path):
    toolbox = two_part_toolbox(tmp_path, requirements={"units": 2})
    toolbox.gates()
    assert toolbox.sandbox.verify_options == [{"assembly": True, "requirements": {"units": 2}}]


# ---- the loop -----------------------------------------------------------------------------


def test_a_question_waits_until_the_model_looked(tmp_path):
    asked = []
    model = FakeModel(
        [
            "PETG pins?",
            [("scad_compile", {"path": "model.scad"}), *LOOK[:2]],
            [("scad_export", {"path": "model.scad", "part": "assembly"})],
            [("render_view", {"stl": list(EXPORT.values())})],
            "PETG pins?",
        ]
    )
    toolbox = two_part_toolbox(tmp_path)

    def asker(questions, iteration):
        asked.append(iteration)
        return "Yes."

    session = run_session(model, toolbox, "p", Limits(max_requests=5), tmp_path, asker=asker)
    closes = [it.get("close") for it in session["iterations"]]
    assert closes == ["questions before looking", None, None, None, "questions"] and asked == [5]
    first = model.payloads[1]["input"]
    assert first.startswith("Your message did not reach the user")
    assert "- compile model.scad (scad_compile)" in first
    assert '- export the part "assembly" with the default parameters' in first
    assert prompts.QUESTIONS in model.payloads[0]["instructions"]
    assert "questions held back: it had not looked yet" in summary.markdown(tmp_path)


def test_the_close_goes_through_the_auditor(tmp_path):
    claim = {"claim": "holds 3 kg", "reason": "nobody measured it"}
    model = FakeModel(
        [
            [("scad_patch", {"path": "model.scad", "old": "cube(10)", "new": "cube(12)"})],
            LOOK,
            "Done. [[cap]]",  # rejected without asking the auditor
            "Done, it holds 3 kg. [[base]]",
            "Done. Verified: [[base]], [[assembly]]. Not verified: the strength.",
        ],
        audits=[json.dumps({"unsupported": [claim]})],
    )
    toolbox = two_part_toolbox(tmp_path)
    session = run_session(model, toolbox, "p", Limits(), tmp_path)
    assert session["status"] == "green"
    closes = [it.get("close") for it in session["iterations"]]
    assert closes == [None, None, "rejected", "rejected", "accepted"]
    assert "[[cap]] names nothing" in model.payloads[3]["input"]
    assert "G8: RED\n  - unsupported claim: holds 3 kg" in model.payloads[4]["input"]
    assert [a["iteration"] for a in session["audits"]] == [3, 4, 5]
    assert session["audits"][0]["requests"] == []
    assert session["final"]["gates"]["G8"]["ok"] is True
    assert session["totals"]["requests"] == 7 and session["totals"]["cost_usd"] == 0.168
    text = summary.markdown(tmp_path)
    assert "G8 at iteration 4: RED, USD 0.0240\n  - unsupported claim" in text
    assert "| 3 | close: rejected | - | G8 |" in text


def test_old_images_leave_the_context_but_the_last_of_each_part(tmp_path):
    view = {p: [("render_view", {"stl": [EXPORT[p]]})] for p in PARTS}
    model = FakeModel(
        [
            [("scad_export", {"path": "model.scad", "part": p}) for p in PARTS],  # 2 sheets
            view["base"],  # seq 3
            view["lid"],  # seq 4
            [("render_view", {"stl": [EXPORT["base"]], "zoom": {"box": [[0] * 3, [1] * 3]}})],
            view["base"],  # seq 6
            "Done.",
        ]
    )
    toolbox = two_part_toolbox(tmp_path)
    limits = Limits(max_requests=6, max_live_images=3, keep_images=1)
    session = run_session(model, toolbox, "p", limits, tmp_path)
    assert session["compactions"] == [
        {"iteration": 4, "removed": [1, 2], "kept": [3, 4]},
        {"iteration": 6, "removed": [3, 5], "kept": [4, 6]},
    ]
    request = model.payloads[5]
    assert "previous_response_id" not in request
    outputs = [i for i in request["input"] if i.get("type") == "function_call_output"]
    kinds = [[c["type"] for c in o["output"]] for o in outputs]
    text, image = ["input_text", "input_text"], ["input_text", "input_image"]
    assert kinds == [text, text, text, image, text, image]
    sheet = outputs[0]["output"][1]["text"]
    assert "render_sheet (call 1) of base. To see it again" in sheet
    assert 'repeat the call: render_sheet {"stl": "exports/model.base' in sheet
    placeholder = outputs[4]["output"][1]["text"]
    assert placeholder.startswith("[Image taken out of the context to make room for new ones")
    assert "render_view (call 5) of base, zoomed to" in placeholder
    assert 'repeat the call: render_view {"stl": ["exports/model.base' in placeholder
    assert session["iterations"][5]["images_removed"] == [3, 5]
    assert "Images out of the context at iteration 6: 2 (kept 2)" in summary.markdown(tmp_path)


# ---- the prompt ---------------------------------------------------------------------------


def test_the_prompt():
    text = prompts.instructions()
    for section in ("ASSEMBLY", "LOOK", "CLOSE", "- G8:", "details", "interference_check"):
        assert section in text
    assert "{units}" not in text and "(unit = 1 to" not in text
    assert {c for c in text if not c.isascii()} <= {"°", "×"}  # plain text, no typography
    assert "module instance(name, part, unit = 1) {\n" in text
    assert (
        'cadverify_only = "";' in text and "echo(cadverify_instance = [name, part, unit]);" in text
    )
    assert "the checks that follow them (scad_export, interference_check)" in text
    for notice in (prompts.WRAP_UP, prompts.WRAP_UP_LAST, prompts.OUTPUT_CUT):
        assert "—" not in notice
    two = prompts.instructions(requirements={"units": 2})
    assert "the assembly shows 2 units (unit = 1 to 2)" in two
    asking = prompts.instructions(questions=True)
    assert asking == text.replace("PROCESS\n", prompts.QUESTIONS + "PROCESS\n", 1)
    assert text.count("PROCESS\n") == 1
