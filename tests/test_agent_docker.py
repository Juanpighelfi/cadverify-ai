"""Integration of the orchestrator with the real sandbox: docker exec, cadcheck and the gates.

The model is a scripted fake (no API calls); everything else is real. Runs on the host and is
skipped when Docker or the cadverify-sandbox image is not available.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from cadverify.agent.loop import Limits, run_session
from cadverify.agent.sandbox import IMAGE, Sandbox
from cadverify.agent.tools import ToolBox
from cadverify.hostile import PLATE
from tests.test_agent import FakeModel
from tests.test_assembly import MODEL as ASSEMBLY_MODEL


def _image_available() -> bool:
    if shutil.which("docker") is None:
        return False
    probe = subprocess.run(["docker", "image", "inspect", IMAGE], capture_output=True)
    return probe.returncode == 0


pytestmark = pytest.mark.skipif(not _image_available(), reason=f"needs Docker and {IMAGE}")

ROOT = Path(__file__).parents[1]
# The bracket's intent, with its overhangs declared one by one: the two wall holes and the shelf
# hole lie horizontal in the print orientation, and the rib's floor faces down.
BRACKET_SPEC = """
echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], [shelf_flange_length, wall_flange_height, bracket_width]]],
    ["support_faces", [["wall", "-x", 0.8 * wall_flange_height * bracket_width]]],
    ["overhangs_allowed", [
        ["lower wall hole", [[-1, 86, 30], [7, 98, 42]]],
        ["upper wall hole", [[-1, 22, 30], [7, 34, 42]]],
        ["shelf hole", [[94, -1, 19], [106, 7, 31]]],
        ["rib floor", [[5, 5, 21.5], [77, 77, 22.5]]]
    ]]
]);
"""
STL = "exports/model.default.44136fa3.stl"
ALL_BUT_G8 = ("G1", "G2", "G3", "G4", "G5", "G7")


def _session(tmp_path, source):
    script = [
        [("scad_write", {"path": "model.scad", "content": source})],
        [("scad_compile", {"path": "model.scad"}), ("scad_export", {"path": "model.scad"})],
        [("printability_report", {"stl": STL}), ("render_sheet", {"stl": STL})],
        [("mesh_report", {"stl": STL})],
        "Done.",
    ]
    with Sandbox(tmp_path / "workspace") as box:
        toolbox = ToolBox(box, tmp_path / "tools")
        session = run_session(FakeModel(script), toolbox, "p", Limits(max_requests=5), tmp_path)
    return session


def _gates(red=(), pending=("G8",)) -> dict:
    return {g: (None if g in pending else g not in red) for g in (*ALL_BUT_G8, "G8")}


def test_a_correct_part_closes_green(tmp_path):
    session = _session(tmp_path, PLATE)
    assert session["status"] == "green", session["final"]["gates"]
    assert session["iterations"][-1]["close"] == "accepted"
    assert (tmp_path / "workspace" / "renders" / "sheet-003.png").exists()  # the export's
    assert (tmp_path / "workspace" / "renders" / "sheet-005.png").exists()
    assert len(list((tmp_path / "tools").glob("*.json"))) == 6


def test_the_protrusion_cannot_close(tmp_path):
    source = (ROOT / "tests/fixtures/l_bracket_protrusion.scad").read_text() + BRACKET_SPEC
    session = _session(tmp_path, source)
    assert session["status"] == "request limit reached"
    last = session["iterations"][-1]
    assert last["close"] == "rejected"
    assert last["gates"] == _gates(red=("G5", "G7")), last["gate_detail"]
    detail = last["gate_detail"]["G7"]["detail"]
    assert "bounds off the spec: min x: measured -2.000" in detail[0]
    assert any("material sticks out 2.0 mm" in d for d in detail)
    # Printed on its side, the gusset's floor is a 70 mm triangle in the air, held by the two
    # flanges only: declared, it still cannot bridge.
    (bridge,) = last["gate_detail"]["G5"]["detail"]
    assert bridge.startswith("default output: declared overhang 'rib floor': the flat ceiling")
    assert "a point 34.75 mm from any material under it" in bridge


def test_an_openscad_warning_cannot_close(tmp_path):
    # The plate still exports right: only G1 sees the unknown variable.
    session = _session(tmp_path, PLATE.replace("d = 6;", "d = 6; margin = clearance + 1;"))
    assert session["status"] == "request limit reached"
    last = session["iterations"][-1]
    assert last["close"] == "rejected"
    assert last["gates"] == _gates(red=("G1",))
    assert last["gate_detail"]["G1"]["detail"] == [
        'compilation: WARNING: Ignoring unknown variable "clearance" in file model.scad, line 2',
        "compilation: WARNING: undefined operation (undefined + number) in file model.scad, line 2",
    ]


def test_a_sheet_finding_is_confirmed_with_numbers_before_the_fix(tmp_path):
    script = [
        [("scad_write", {"path": "model.scad", "content": PLATE})],
        [("scad_export", {"path": "model.scad"})],
        [("render_sheet", {"stl": STL})],
        [("scad_patch", {"path": "model.scad", "old": "d = 6;", "new": "d = 5;"})],
        [("mesh_report", {"stl": STL})],
        [("scad_patch", {"path": "model.scad", "old": "d = 6;", "new": "d = 5;"})],
        "Done.",
    ]
    with Sandbox(tmp_path / "workspace") as box:
        toolbox = ToolBox(box, tmp_path / "tools")
        session = run_session(FakeModel(script), toolbox, "p", Limits(max_requests=6), tmp_path)
    summaries = [t["summary"] for it in session["iterations"] for t in it["tool_calls"]]
    assert "confirm with numbers" in summaries[3]
    assert summaries[5].startswith("model.scad line 2")
    assert "d = 5;" in (tmp_path / "workspace" / "model.scad").read_text()


def test_the_exploration_tools_end_to_end(tmp_path):
    plot = (
        "import matplotlib.pyplot as plt, trimesh\n"
        f"m = trimesh.load('{STL}')\n"
        "print(round(m.volume, 1), m.is_watertight)\n"
        "plt.plot([0, 1], [0, 1]); plt.savefig('plot.png', dpi=50)\n"
    )
    cut = {"point": [20, 15, 2.5], "normal": [0, 1, 0]}
    script = [
        [("scad_write", {"path": "model.scad", "content": PLATE})],
        [("scad_export", {"path": "model.scad"}), ("render_sheet", {"stl": STL})],
        [("render_view", {"stl": [STL], "cut": cut, "highlight": ["holes", "support_faces"]})],
        [("run_python", {"code": plot}), ("view_image", {"path": "plot.png"})],
        [("run_shell", {"cmd": "sed -i 's/d = 6;/d = 5;/' model.scad"})],  # after an image
        [("run_shell", {"cmd": "cat model.scad | head -2"})],
        "Done.",
    ]
    with Sandbox(tmp_path / "workspace") as box:
        toolbox = ToolBox(box, tmp_path / "tools")
        session = run_session(FakeModel(script), toolbox, "p", Limits(max_requests=7), tmp_path)
    assert session["status"] == "green", session["final"]["gates"]
    logs = [json.loads(p.read_text()) for p in sorted((tmp_path / "tools").iterdir())]
    names = [log["name"] for log in logs]
    assert names[3:] == ["render_view", "run_python", "view_image", "run_shell", "run_shell"]
    view = logs[3]["result"]
    assert view["cut"][0]["area_mm2"] == pytest.approx(5 * 40 - 5 * 6, abs=0.5)
    assert view["holes"][0]["holes"][0]["min_diameter_mm"] == pytest.approx(6, abs=0.1)
    assert view["support_faces"][0]["faces"][0]["ok"]
    python = logs[4]["result"]
    assert python["exit_code"] == 0 and python["stdout"].split()[1] == "True"
    assert python["files"]["created"] == ["plot.png"]
    assert logs[5]["image"] == "renders/image-006.png"
    assert "I undid it" in logs[6]["result"]["error"]  # the sed after view_image
    assert logs[6]["rule"]["image_tool"] == "view_image"
    assert "d = 6;" in logs[7]["result"]["stdout"]
    images = [i["tool"] for it in session["iterations"] for i in it["images"]]
    assert images == ["scad_export", "render_sheet", "render_view", "view_image"]
    assert (tmp_path / "workspace" / "renders" / "image-006.png").exists()


def test_an_assembly_closes_green(tmp_path):
    parts = ("base", "pin")

    def instances():
        (log,) = (tmp_path / "tools").glob("*-interference_check.json")
        report = json.loads(log.read_text())["result"]
        return [("render_view", {"stl": [i["stl"] for i in report["instances"]]})]

    close = (
        "Done. Verified: [[base]], [[pin]], [[assembly]], [[assembly_order]] and [[pin turn]]. "
        "Not verified: the strength."
    )
    script = [
        [("scad_write", {"path": "model.scad", "content": ASSEMBLY_MODEL})],
        [
            ("scad_compile", {"path": "model.scad"}),
            *[("scad_export", {"path": "model.scad", "part": p}) for p in parts],
        ],
        [("interference_check", {"path": "model.scad"})],  # the exports brought the sheets
        instances,
        close,
    ]
    with Sandbox(tmp_path / "workspace") as box:
        toolbox = ToolBox(box, tmp_path / "tools", requirements={"units": 1})
        model = FakeModel(script)
        session = run_session(model, toolbox, "p", Limits(max_requests=5), tmp_path)
    final = session["final"]["gates"]
    assert session["status"] == "green", final
    assert {g: v["ok"] for g, v in final.items()} == _gates(pending=())
    assembly = session["final"]["assembly"]
    assert [i["name"] for i in assembly["instances"]] == ["base1", "pin1"]
    sheets = session["iterations"][1]["images"]
    assert [image["tool"] for image in sheets] == ["scad_export", "scad_export"]
    for image in sheets:
        assert (tmp_path / "workspace" / "renders" / f"sheet-{image['seq']:03d}.png").exists()
    assert session["audits"][-1]["g8"]["audit"] == {
        "unsupported": [],
        "untold_adjustments": [],
        "unmeasured": [],
    }
    assert len(model.audit_payloads) == 1
