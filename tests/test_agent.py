"""Offline tests of the orchestrator: gates, the tool box and the loop, with fakes.

The fake model replays scripted Responses API bodies and the fake sandbox answers canned cadcheck
JSON; the "code" of run_shell is a tiny script the fake interprets, never executed. They test the
harness only; they never stand in for the real run.
"""

import base64
import hashlib
import json
import time
from pathlib import Path

import pytest

from cadverify import summary
from cadverify.agent import gates, prompts
from cadverify.agent.loop import Limits, requests_left, run_session, wrap_up_notice
from cadverify.agent.prompts import CLOSE_REJECTED
from cadverify.agent.sandbox import Sandbox
from cadverify.agent.tools import SCHEMAS, ToolBox
from cadverify.cadcheck import run as cadcheck_run
from cadverify.meta_api import ApiCall

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC"
)
GOOD_MESH = {
    "triangles": 12,
    "watertight": True,
    "bad_edges": 0,
    "bad_edge_locations": [],
    "volume_mm3": 1000.0,
    "bounds": [[0, 0, 0], [10, 10, 10]],
    "bodies": 1,
    "inverted_shells": 0,
    "through_holes": 0,
}
SPEC = {
    "bounds": [[0, 0, 0], [10, 10, 10]],
    "bodies": 1,
    "through_holes": None,
    "support_faces": [],
    "overhangs_allowed": [],
}
GOOD_CHECK = {
    "ok": True,
    "bounds": {"ok": True, "deviations": []},
    "bodies": {"ok": True, "expected": 1, "actual": 1},
    "support_faces": [],
}
DEFAULT = gates.DEFAULT_OUTPUT
STL = "checks/exports/model.default.44136fa3.stl"
STL_BYTES = b"solid x\nendsolid x\n"
STL_SHA = hashlib.sha256(STL_BYTES).hexdigest()
CLEAN_AUDIT = json.dumps({"unsupported": [], "untold_adjustments": []})


def part_bytes(part: str) -> bytes:
    """The STL bytes FakeSandbox exports for a `part` option (the default output: STL_BYTES)."""
    return f"solid {part}\nendsolid {part}\n".encode()


def instance_bytes(name: str) -> bytes:
    return f"solid instance {name}\nendsolid\n".encode()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _verify(mesh=None, spec=SPEC, check=GOOD_CHECK, printability=None, compile_ok=True):
    printability = printability or {
        "ok": True,
        "fits_bed": True,
        "bed_mm": [256, 256, 256],
        "size": [10, 10, 10],
        "zones": [],
        "zones_total": 0,
        "zones_undeclared": 0,
        "undeclared_area_mm2": 0,
    }
    compiled = {"ok": compile_ok, "errors": [] if compile_ok else ["ERROR: Parser error"]}
    compiled["asserts_failed"] = []
    export = {
        "ok": True,
        "path": f"/work/{STL}",
        "errors": [],
        "asserts_failed": [],
        "mesh": mesh or GOOD_MESH,
        "spec": spec,
        "spec_error": None,
        "spec_check": check,
        "sha256": STL_SHA,  # the same bytes as the agent's export in FakeSandbox
    }
    return {
        "compile": compiled,
        "parts": [{"part": None, "export": export, "printability": printability}],
        "assembly": {"ok": True, "not_needed": True},  # one part
    }


def _red(result) -> list[str]:
    return [g for g, v in result.items() if v["ok"] is False]


def test_all_gates_green_but_the_close():
    result = gates.evaluate(_verify(), {"sha"}, {DEFAULT: "sha"})
    assert list(result) == list(gates.GATES)
    assert gates.green_but(result, "G8") and not gates.all_green(result)
    assert result["G8"] == {"ok": None, "detail": [gates.PENDING]}
    assert "G8: pending" in prompts.gate_report(result)


def test_g7_needs_the_sheet_of_the_final_mesh():
    result = gates.evaluate(_verify(), {"old"}, {DEFAULT: "new"})
    assert _red(result) == ["G7"]
    assert result["G7"]["detail"] == [
        "default output: you did not see the sheet of the final version (export it with the "
        "default parameters: scad_export brings its sheet)"
    ]


def test_g2_strict_with_the_cause_of_an_inverted_shell():
    mesh = dict(GOOD_MESH, volume_mm3=-1000.0, bodies=0, inverted_shells=1)
    detail = gates.evaluate(_verify(mesh), {"s"}, {DEFAULT: "s"})["G2"]["detail"]
    assert any("polyhedron" in d for d in detail)
    assert any("volume not positive" in d for d in detail)
    assert any("0 bodies, 1 expected" in d for d in detail)


def test_g2_takes_the_declared_body_count():
    mesh = dict(GOOD_MESH, bodies=2)
    spec = dict(SPEC, bodies=2)
    assert gates.evaluate(_verify(mesh, spec), {"s"}, {DEFAULT: "s"})["G2"]["ok"]


def test_g5_undeclared_overhang_and_bed():
    printability = {
        "ok": True,
        "fits_bed": False,
        "bed_mm": [256, 256, 256],
        "size": [300, 10, 10],
        "zones": [{"declared": False, "max_angle_deg": 90.0, "area_mm2": 2399.8, "bounds": []}],
        "zones_total": 1,
        "zones_undeclared": 1,
    }
    detail = gates.evaluate(_verify(printability=printability), {"s"}, {DEFAULT: "s"})
    assert len(detail["G5"]["detail"]) == 2 and not detail["G5"]["ok"]


def test_g5_caps_the_allowed_boxes():
    printability = {
        "ok": True,
        "fits_bed": True,
        "zones": [],
        "zones_undeclared": 0,
        "allowed_coverage": {"share": 0.8, "per_box": [{"name": "all", "share": 0.8}]},
    }
    detail = gates.evaluate(_verify(printability=printability), {"s"}, {DEFAULT: "s"})["G5"]
    assert len(detail["detail"]) == 1 and "cover 80% of the part's surface" in detail["detail"][0]
    assert "all 80%" in detail["detail"][0]


def test_g7_reports_a_protrusion_behind_a_support_face():
    check = {
        "ok": False,
        "bounds": {"deviations": ["min x: measured -2.000, specified 0 (off by -2.000 mm)"]},
        "bodies": {"ok": True},
        "support_faces": [
            {
                "name": "wall",
                "direction": "-x",
                "ok": False,
                "min_area_mm2": 4800,
                "area_on_extreme_plane_mm2": 0.0,
                "extreme_plane": "x = -2.000",
                "largest_flat_face": {"plane": "x = 0.000", "area_mm2": 5440.4},
                "protrusion_mm": 2.0,
            }
        ],
    }
    detail = gates.evaluate(_verify(check=check), {"s"}, {DEFAULT: "s"})["G7"]
    assert not detail["ok"]
    assert "material sticks out 2.0 mm" in detail["detail"][1]


def test_g7_without_spec_and_g1_on_errors():
    result = gates.evaluate(_verify(spec=None, check=None, compile_ok=False), {"s"}, {DEFAULT: "s"})
    assert (
        "cadverify_spec = [...]) with the verifiable spec is missing" in result["G7"]["detail"][0]
    )
    assert result["G1"]["detail"] == ["compilation: ERROR: Parser error"]


def test_g1_fails_on_warnings_and_reports_each_once():
    unknown = 'WARNING: Ignoring unknown variable "pos_x" in file model.scad, line 71'
    undef = "WARNING: undefined operation (undefined - number) in file model.scad, line 71"
    nonplanar = "WARNING: PolySet has nonplanar faces. Attempting alternate construction"
    verify = _verify()
    verify["compile"]["warnings"] = [unknown, undef]
    verify["parts"][0]["export"]["warnings"] = [unknown, undef, nonplanar]
    result = gates.evaluate(verify, {"s"}, {DEFAULT: "s"})
    assert _red(result) == ["G1"]
    assert result["G1"]["detail"] == [
        f"compilation: {unknown}",
        f"compilation: {undef}",
        f"export of default output: {nonplanar}",
    ]


def test_g1_caps_the_warnings_of_a_stage():
    verify = _verify()
    verify["compile"]["warnings"] = [f"WARNING: w{i}" for i in range(gates.MAX_WARNINGS + 5)]
    detail = gates.evaluate(verify, {"s"}, {DEFAULT: "s"})["G1"]["detail"]
    assert len(detail) == gates.MAX_WARNINGS + 1
    assert detail[-1] == "compilation: and 5 more warnings (see scad_compile)"


class FakeSandbox(Sandbox):
    """Answers cadcheck commands with canned JSON and writes the files the tools would, in a
    local directory that is its own mirror; the manifest and the sync are the real ones.

    run_shell understands lines "write <path> <text>", "rm <path>" and "exit <code>".
    An export of a `part` writes part_bytes(part); `export_queue` holds result fields for the
    next exports, in order. The assembly command answers `assembly` and writes its instances."""

    def __init__(self, workspace: Path, verify: dict, assembly: dict | None = None):
        super().__init__(workspace)
        self.verify_result = verify
        self.assembly_result = assembly
        self.export_queue: list[dict] = []
        self.commands: list[list[str]] = []
        self.verified: list[dict[str, bytes]] = []
        self.verify_options: list[dict] = []

    def cadcheck(self, args, stdin=None, timeout_s=120):
        command = args[0]
        if command == "manifest":
            return cadcheck_run.manifest(str(self.workspace))
        self.commands.append(args)
        if command == "write":
            (self.workspace / args[1]).write_text(stdin)
            return {"ok": True, "lines": stdin.count("\n")}
        if command == "patch":
            edit = json.loads(stdin)
            path = self.workspace / args[1]
            path.write_text(path.read_text().replace(edit["old"], edit["new"]))
            return {"ok": True, "line": 1, "lines": 1}
        if command == "compile":
            return {"ok": True, "echo": [], "warnings": [], "asserts_failed": [], "errors": []}
        if command == "export":
            part = args[args.index("--part") + 1] if "--part" in args else None
            stl = self.workspace / "exports" / f"model.{part or 'default'}.44136fa3.stl"
            stl.parent.mkdir(exist_ok=True)
            result = {
                "ok": True,
                "path": f"/work/exports/{stl.name}",
                "mesh": GOOD_MESH,
                "spec": SPEC,
                "spec_check": GOOD_CHECK,
            }
            if self.export_queue:
                result.update(self.export_queue.pop(0))
            data = result.pop("bytes", None) or (STL_BYTES if part is None else part_bytes(part))
            stl.write_bytes(data)
            return {**result, "sha256": sha(data)}
        if command == "assembly":
            for inst in self.assembly_result["instances"]:
                path = self.workspace / inst["stl"].removeprefix("/work/")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(instance_bytes(inst["name"]))
            return json.loads(json.dumps(self.assembly_result))
        if command in ("sheet", "view", "image"):
            out = args[args.index("--out") + 1] if "--out" in args else json.loads(stdin)["out"]
            png = self.workspace / out
            png.parent.mkdir(exist_ok=True)
            png.write_bytes(PNG)
            if command == "sheet":
                return {
                    "ok": True,
                    "views": ["iso"],
                    "size": [1, 1],
                    "triangles": 12,
                    "edges": {},
                    "stl_sha256": sha((self.workspace / args[1]).read_bytes()),
                }
            if command == "image":
                return {"ok": True, "path": out, "size": [1, 1]}
            request = json.loads(stdin)
            parts = [
                {**p, "sha256": sha((self.workspace / p["stl"]).read_bytes())}
                for p in request["parts"]
            ]
            framing = [
                {
                    "part": p["label"],
                    "sha256": p["sha256"],
                    "name": d["name"],
                    "kind": d["kind"],
                    "in_frame": True,
                    "close": bool(request.get("zoom")),  # the fake's idea of a close look
                }
                for p in parts
                for d in (p.get("spec") or {}).get("details") or []
            ]
            return {
                "ok": True,
                "path": out,
                "size": [1, 1],
                "renderer": "fake",
                "parts": [{k: p[k] for k in ("label", "stl", "sha256")} for p in parts],
                "details_in_view": framing,
            }
        if command == "run":
            return self._run(json.loads(stdin)["code"])
        if command == "mesh":  # like the real mesh_report: facts, no "ok" field
            return {"watertight": True, "bodies": 1, "bounds": [[0, 0, 0], [10, 10, 10]]}
        return {"ok": True, "zones_total": 0, "zones_undeclared": 0, "fits_bed": True}

    def _run(self, script: str) -> dict:
        code = 0
        for line in script.splitlines():
            op, _, rest = line.partition(" ")
            if op == "write":
                path, _, text = rest.partition(" ")
                (self.workspace / path).write_text(text + "\n")
            elif op == "rm":
                (self.workspace / rest).unlink()
            elif op == "exit":
                code = int(rest)
        return {"ok": code == 0, "exit_code": code, "timed_out": False, "stdout": "", "stderr": ""}

    def reap(self):
        return {"ok": True, "killed": 0, "remaining": 0}

    def pull(self, paths):
        return set(paths)  # the workspace is the mirror

    def restore(self, files):
        for rel, data in files.items():
            if data is None:
                (self.workspace / rel).unlink()
            else:
                (self.workspace / rel).write_bytes(data)
        self.sync()

    def verify(self, sources, main, **options):
        self.verified.append(sources)
        self.verify_options.append(options)
        return self.verify_result


def _toolbox(tmp_path, **kwargs) -> ToolBox:
    workspace = tmp_path / "workspace"
    workspace.mkdir(exist_ok=True)
    return ToolBox(FakeSandbox(workspace, _verify()), tmp_path / "tools", **kwargs)


def _seeded(tmp_path) -> ToolBox:
    """A session that starts with model.scad, as a request with a .scad does."""
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    box = FakeSandbox(workspace, _verify())
    box.restore({"model.scad": b"cube(10);\n"})
    return ToolBox(box, tmp_path / "tools")


@pytest.fixture
def toolbox(tmp_path):
    return _toolbox(tmp_path)


def _args(**kwargs):
    return json.dumps(kwargs)


def test_the_tools():
    assert [s["name"] for s in SCHEMAS] == [
        "scad_write",
        "scad_patch",
        "scad_compile",
        "scad_export",
        "mesh_report",
        "render_sheet",
        "printability_report",
        "run_shell",
        "run_python",
        "view_image",
        "render_view",
        "interference_check",
    ]
    export = next(s for s in SCHEMAS if s["name"] == "scad_export")
    assert "part" in export["parameters"]["properties"]
    assert export["description"].endswith("its sheet attached, the one render_sheet makes.")
    view = next(s for s in SCHEMAS if s["name"] == "render_view")["description"]
    assert "details_in_view" in view


def test_a_fix_after_a_sheet_needs_a_numeric_check_first(toolbox):
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    stl = toolbox.call("scad_export", _args(path="model.scad"), 1)[0]["path"]
    result, image = toolbox.call("render_sheet", _args(stl=stl), 2)
    assert result["ok"] and image.startswith("data:image/png;base64,")
    blocked, _ = toolbox.call("scad_patch", _args(path="model.scad", old="10", new="12"), 3)
    assert not blocked["ok"] and "confirm with numbers before changing" in blocked["error"]
    assert "mesh_report, scad_export, printability_report" in blocked["error"]
    toolbox.call("mesh_report", _args(stl=stl), 3)
    assert toolbox.call("scad_patch", _args(path="model.scad", old="10", new="12"), 3)[0]["ok"]
    stale = toolbox.call("mesh_report", _args(stl=stl), 4)[0]
    assert "export it again" in stale["warning"]
    logged = sorted(p.name for p in toolbox.log_dir.iterdir())
    assert logged[2] == "0003-render_sheet.json" and len(logged) == 7
    record = json.loads((toolbox.log_dir / "0001-scad_write.json").read_text())
    assert record["files"]["new"] == ["model.scad"] and record["scad_changed"] == ["model.scad"]
    refused, confirmed = toolbox.rule_events
    assert refused["edit"] == "refused" and refused["image_tool"] == "render_sheet"
    assert refused["numbers_before_image"]  # scad_export ran on that version before the sheet
    assert confirmed["confirmed_by"] == "mesh_report"


def test_tool_errors_go_back_to_the_model(toolbox):
    assert "Invalid arguments" in toolbox.call("scad_write", "{no json", 1)[0]["error"]
    assert "Unknown tool" in toolbox.call("cad_magic", "{}", 1)[0]["error"]
    assert "Invalid arguments" in toolbox.call("mesh_report", _args(path="x"), 1)[0]["error"]
    assert "Invalid arguments" in toolbox.call("run_shell", "{}", 1)[0]["error"]


def test_printability_gets_the_declared_zones_of_its_export(toolbox):
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    stl = toolbox.call("scad_export", _args(path="/work/model.scad"), 1)[0]["path"]
    toolbox.call("printability_report", _args(stl=stl), 1)
    command = toolbox.sandbox.commands[-1]
    assert command[:2] == ["printability", stl] and command[3] == "[]"
    assert toolbox.sandbox.commands[0] == ["write", "model.scad"]


def test_gates_use_the_seen_sheets_and_verify_only_the_sources(toolbox):
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    assert not toolbox.gates()["gates"]["G7"]["ok"]
    toolbox.call("scad_export", _args(path="model.scad"), 1)  # it brings the sheet
    state = toolbox.gates()
    assert gates.green_but(state["gates"], "G8")
    assert toolbox.sandbox.verified == [{"model.scad": b"cube(10);\n"}]  # cached per version
    assert toolbox.sandbox.verify_options == [{"assembly": True, "requirements": {}}]
    snapshot = toolbox.verify_dir / state["source"]
    assert (snapshot / "src" / "model.scad").read_bytes() == b"cube(10);\n"
    assert (snapshot / "verify.json").exists()


def test_without_a_source_every_gate_is_red_but_the_close_is_pending(toolbox):
    state = toolbox.gates()["gates"]
    assert state["G8"] == {"ok": None, "detail": [gates.PENDING]}
    assert all(
        state[g] == {"ok": False, "detail": ["the verification failed: there is no model.scad"]}
        for g in gates.GATES[:-1]
    )
    assert toolbox.sandbox.verified == []


def test_a_shell_edit_is_an_edit(toolbox):
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    before = toolbox.source_hash()
    result = toolbox.call("run_shell", _args(cmd="write model.scad cube(12);"), 2)[0]
    assert result["scad_edited"] == ["model.scad"]
    assert result["files"] == {"created": [], "modified": ["model.scad"], "deleted": []}
    assert toolbox.source_hash() != before
    assert toolbox.sources["model.scad"] == b"cube(12);\n"


def test_a_shell_edit_after_an_image_is_undone(toolbox):
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    stl = toolbox.call("scad_export", _args(path="model.scad"), 1)[0]["path"]
    toolbox.call("render_view", _args(stl=[stl], camera={"view": "iso"}), 2)
    source = toolbox.source_hash()
    script = "write model.scad cube(12);\nwrite extra.scad cube(1);\nrm exports/" + Path(stl).name
    result = toolbox.call("run_shell", _args(cmd=script), 3)[0]
    assert not result["ok"] and "I undid it" in result["error"]
    assert (toolbox.workspace / "model.scad").read_text() == "cube(10);\n"
    assert not (toolbox.workspace / "extra.scad").exists()
    assert toolbox.source_hash() == source
    event = toolbox.rule_events[-1]
    assert event["edit"] == "undone" and event["image_tool"] == "render_view"
    assert event["scad"] == ["extra.scad", "model.scad"]
    # Still blocked: the failed call was not a check. A script that ends with exit 0 is.
    assert toolbox.call("run_shell", _args(cmd="exit 1"), 4)[0]["exit_code"] == 1
    assert not toolbox.call("scad_patch", _args(path="model.scad", old="10", new="11"), 4)[0]["ok"]
    toolbox.call("run_shell", _args(cmd="exit 0"), 5)
    assert toolbox.call("scad_patch", _args(path="model.scad", old="10", new="11"), 5)[0]["ok"]
    assert toolbox.rule_events[-1]["confirmed_by"] == "run_shell"


def test_a_view_with_a_cut_or_the_holes_is_a_numeric_check(toolbox):
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    stl = toolbox.call("scad_export", _args(path="model.scad"), 1)[0]["path"]
    toolbox.call("render_view", _args(stl=[stl]), 2)
    assert toolbox.visual_pending["tool"] == "render_view"
    cut = {"point": [5, 5, 5], "normal": [0, 0, 1]}
    result, image = toolbox.call("render_view", _args(stl=[stl], cut=cut), 3)
    assert image and result["png"] == "renders/view-004.png" and "renderer" not in result
    assert toolbox.visual_pending is None
    assert toolbox.rule_events == [
        {
            "seq": 4,
            "confirmed_by": "render_view",
            "image_seq": 3,
            "image_tool": "render_view",
            "numbers_before_image": True,
        }
    ]
    toolbox.call("render_view", _args(stl=stl, highlight=["holes"]), 4)
    assert toolbox.visual_pending is None
    request = json.loads(Path(toolbox.log_dir / "0005-render_view.json").read_text())
    assert request["arguments"]["stl"] == stl and request["image"] == "renders/view-005.png"


def test_exploration_images_have_a_cap(tmp_path):
    toolbox = _toolbox(tmp_path, max_images=2)
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    stl = toolbox.call("scad_export", _args(path="model.scad"), 1)[0]["path"]
    assert toolbox.call("render_view", _args(stl=[stl]), 2)[1]
    assert toolbox.call("view_image", _args(path="renders/view-003.png"), 2)[1]
    capped, image = toolbox.call("render_view", _args(stl=[stl]), 3)
    assert image is None and "limit of 2 images" in capped["error"]
    assert toolbox.call("render_sheet", _args(stl=stl), 3)[1]  # G7 needs it: never capped
    assert toolbox.images == {
        "render_view": 1,
        "view_image": 1,
        "render_sheet": 1,
        "scad_export": 1,
    }


def test_an_image_outside_the_mirror_is_never_read(tmp_path):
    # The mirror holds no symlinks (tests/test_hostile_docker.py); if one got there, the host
    # still reads images only from inside it.
    workspace, outside = tmp_path / "workspace", tmp_path / "outside"
    workspace.mkdir()
    outside.mkdir()
    (workspace / "renders").symlink_to(outside)
    toolbox = ToolBox(FakeSandbox(workspace, _verify()), tmp_path / "tools")
    toolbox.call("scad_write", _args(path="model.scad", content="cube(10);\n"), 1)
    export, image = toolbox.call("scad_export", _args(path="model.scad"), 2)
    assert image is None and "Could not read the image" in export["error"]
    result, image = toolbox.call("render_sheet", _args(stl=EXPORTED), 3)
    assert (outside / "sheet-003.png").exists() and image is None


class FakeModel:
    """Replays scripted responses: each item is a list of tool calls or a final text, or
    {"incomplete": [tool calls]} for a response cut at max_output_tokens, or a function that
    returns one of those when its turn comes (calls that depend on earlier results).

    The auditor's requests (agent/closing.py) take their answers from `audits`, a clean audit
    when it runs out, and are kept apart in `audit_payloads`. `lose` lists request numbers whose
    previous_response_id the server no longer has, and `lose_then_fail` the ones where it says so
    on every chained retry and then fails with a 500.
    """

    def __init__(self, script, cost_tokens=1000, lose=(), lose_then_fail=(), audits=()):
        self.script = list(script)
        self.payloads = []
        self.audits = list(audits)
        self.audit_payloads = []
        self.cost_tokens = cost_tokens
        self.lose = set(lose)
        self.lose_then_fail = set(lose_then_fail)

    def responses(self, label, **payload):
        if "-audit" in label:
            self.audit_payloads.append(payload)
            text = self.audits.pop(0) if self.audits else CLEAN_AUDIT
            return self._answer(label, f"audit_{len(self.audit_payloads)}", text)
        self.payloads.append(payload)
        chained = "previous_response_id" in payload
        error = {"type": "invalid_request_error", "message": "referenced response not found"}
        if len(self.payloads) in self.lose and chained:
            return ApiCall(label, 400, {"error": error}, latency_s=0.1)
        if len(self.payloads) in self.lose_then_fail and chained:
            failed = {"type": "server_error", "message": "internal server error"}
            attempts = [{"attempt": n, "status_code": 400, "error": error} for n in (1, 2, 3)]
            attempts.append({"attempt": 4, "status_code": 500, "error": failed})
            return ApiCall(label, 500, {"error": failed}, latency_s=0.1, attempts=attempts)
        step = self.script.pop(0)
        if callable(step):
            step = step()
        return self._answer(label, f"resp_{len(self.payloads)}", step)

    def _answer(self, label, response_id, step):
        cut = isinstance(step, dict)
        if cut:
            step = step["incomplete"]
        if isinstance(step, str):
            output = [{"type": "message", "content": [{"type": "output_text", "text": step}]}]
        else:
            output = [
                {"type": "function_call", "call_id": f"c{i}", "name": n, "arguments": _args(**a)}
                for i, (n, a) in enumerate(step)
            ]
        body = {
            "id": response_id,
            "status": "incomplete" if cut else "completed",
            "output": output,
            "usage": {"input_tokens": self.cost_tokens, "output_tokens": self.cost_tokens},
        }
        if cut:
            body["incomplete_details"] = {"reason": "max_output_tokens"}
        return ApiCall(label=label, status_code=200, body=body, latency_s=1.0)


EXPORTED = "exports/model.default.44136fa3.stl"
WRITE = [("scad_write", {"path": "model.scad", "content": "cube(10);\n"})]
EXPORT = [("scad_export", {"path": "model.scad"})]


def test_loop_rejects_a_close_with_red_gates_then_accepts(toolbox, tmp_path):
    model = FakeModel([WRITE, "Done.", EXPORT, "Done, verified: [[G2]]."])
    session = run_session(model, toolbox, "request", Limits(), tmp_path)
    assert session["status"] == "green"
    closes = [it.get("close") for it in session["iterations"]]
    assert closes == [None, "rejected", None, "accepted"]
    assert model.payloads[2]["input"].startswith(CLOSE_REJECTED[:30])
    assert "G7: RED" in model.payloads[2]["input"]
    sheet_output = model.payloads[3]["input"][0]["output"]  # the export brings the sheet
    assert sheet_output[1]["type"] == "input_image"
    assert all(p["instructions"] and p["tools"] == toolbox.schemas for p in model.payloads)
    assert model.payloads[0]["instructions"] == prompts.instructions()
    assert model.payloads[1]["previous_response_id"] == "resp_1"
    assert (
        len(model.audit_payloads) == 1
        and "CLOSE\nDone, verified" in (model.audit_payloads[0]["input"])
    )
    saved = json.loads((tmp_path / "session.json").read_text())
    assert saved["totals"]["requests"] == 5 and saved["totals"]["tool_calls"] == 2
    assert saved["final"]["gates"]["G8"]["ok"] is True


def test_a_session_designs_with_its_model_and_audits_with_another(toolbox, tmp_path):
    model = FakeModel([WRITE, EXPORT, "Done, verified: [[G2]]."])
    session = run_session(
        model, toolbox, "request", Limits(), tmp_path, model="muse-spark-1.3", auditor="m2"
    )
    assert session["status"] == "green"
    assert session["model"] == "muse-spark-1.3" and session["auditor"] == "m2"
    assert {p["model"] for p in model.payloads} == {"muse-spark-1.3"}
    assert {p["prompt_cache_key"] for p in model.payloads} == {"cadverify-agent-muse-spark-1.3"}
    assert [p["model"] for p in model.audit_payloads] == ["m2"]

    model = FakeModel([WRITE, EXPORT, "Done, verified: [[G2]]."])
    session = run_session(model, toolbox, "request", Limits(), tmp_path, model="muse-spark-1.3")
    assert session["auditor"] == "muse-wonder-1.0"
    assert [p["model"] for p in model.audit_payloads] == ["muse-wonder-1.0"]


def test_loop_stops_at_the_request_limit_and_the_budget(toolbox, tmp_path):
    model = FakeModel(["Done."] * 5)
    session = run_session(model, toolbox, "p", Limits(max_requests=3), tmp_path)
    assert session["status"] == "request limit reached" and len(model.payloads) == 3

    expensive = FakeModel(["Done."] * 5, cost_tokens=100_000)  # USD 2.4 per request
    session = run_session(expensive, toolbox, "p", Limits(max_cost_usd=4.0), tmp_path)
    assert session["status"] == "session budget spent"
    assert len(expensive.payloads) == 2


def test_loop_resends_the_history_when_the_server_lost_a_response(toolbox, tmp_path):
    model = FakeModel(
        [
            WRITE,
            [("scad_export", {"path": "model.scad"}), ("render_sheet", {"stl": EXPORTED})],
            [("mesh_report", {"stl": EXPORTED})],
            "Done.",
        ],
        lose={3},
    )
    session = run_session(model, toolbox, "request", Limits(), tmp_path)
    assert session["status"] == "green"
    assert session["iterations"][2]["lost_previous_response"]["status_code"] == 400
    replay = model.payloads[3]
    assert "previous_response_id" not in replay
    kinds = [item.get("type", item.get("role")) for item in replay["input"]]
    assert kinds == [
        "user",
        "function_call",
        "function_call_output",
        "function_call",
        "function_call",
        "function_call_output",
        "function_call_output",
    ]
    assert replay["input"][-1]["output"][1]["type"] == "input_image"
    assert model.payloads[4]["previous_response_id"] == "resp_4"  # chained again


def test_a_lost_response_is_resent_even_when_the_last_retry_fails_otherwise(toolbox, tmp_path):
    # One session got "not found" on the three chained retries, then a 500, and ended with G1
    # to G5 green.
    model = FakeModel([WRITE, EXPORT, "Done."], lose_then_fail={2})
    session = run_session(model, toolbox, "request", Limits(), tmp_path)
    assert session["status"] == "green"
    assert session["iterations"][1]["lost_previous_response"]["status_code"] == 500
    assert "previous_response_id" not in model.payloads[2]


def test_the_summary_of_a_session(tmp_path):
    script = [
        [("run_python", {"code": "write measure.txt trimesh volume 1000"})],
        [("run_shell", {"cmd": "exit 2"}), ("run_shell", {"code": "exit 2"})],  # no cmd
        [
            ("run_python", {"code": "s = m.section(plane_origin=o, plane_normal=n)"}),
            ("run_python", {"code": "i = m.intersection(shelf)  # trimesh boolean"}),
        ],
        "Good.",
    ]
    model = FakeModel(script, cost_tokens=10_000)
    run_session(model, _seeded(tmp_path), "r", Limits(max_requests=4), tmp_path)
    text = summary.markdown(tmp_path)
    assert "4 requests, 5 tool calls" in text and "USD 0.96" in text
    assert "| 1 | run_python | - | G7 | 10,000 (0) | 10,000 (0) | 0.2400 | 1.0 s |" in text
    assert "| 4 | close: rejected | - | G7 |" in text
    assert "| 1 | 1 | run_python | measurements | 0 |" in text
    assert "| 2 | 2 | run_shell | other | 2 |" in text
    assert "| 3 | 2 | run_shell | other | - | - | `exit 2` |" in text
    assert "| 4 | 3 | run_python | cuts | 0 |" in text
    assert "| 5 | 3 | run_python | measurements | 0 |" in text  # not a cut
    assert summary.num(2277) == "2,277" and summary.num(0.4249, 2) == "0.42"


def test_questions_before_the_first_edit_go_to_the_user(tmp_path):
    asked = []

    def asker(questions, iteration):
        asked.append((questions, iteration))
        time.sleep(1.2)  # longer than the session's wall time limit: waiting does not count
        return "PETG, no supports."

    model = FakeModel(
        [
            [("scad_compile", {"path": "model.scad"}), *EXPORT],  # it looks first
            "Which material?",
            [("scad_patch", {"path": "model.scad", "old": "cube(10)", "new": "cube(12)"})],
            EXPORT,
            "Done.",  # after an edit, a reply without tools is the close
        ]
    )
    limits = Limits(max_wall_s=1.0)
    session = run_session(model, _seeded(tmp_path), "request", limits, tmp_path, asker=asker)
    assert asked == [("Which material?", 2)]
    assert session["status"] == "green"
    closes = [it.get("close") for it in session["iterations"]]
    assert closes == [None, "questions", None, None, "accepted"]
    assert session["iterations"][1]["answer"] == "PETG, no supports."
    assert model.payloads[2]["previous_response_id"] == "resp_2"
    assert model.payloads[2]["input"] == "PETG, no supports."
    assert session["totals"]["user_wait_s"] >= 1.2 and session["totals"]["wall_s"] < 1.0
    assert prompts.QUESTIONS in model.payloads[0]["instructions"]
    assert "questions to the user" in summary.markdown(tmp_path)


def test_without_someone_to_answer_a_reply_without_tools_is_a_close(tmp_path):
    model = FakeModel(["Which material?", "Done."])
    session = run_session(model, _seeded(tmp_path), "request", Limits(max_requests=2), tmp_path)
    assert [it.get("close") for it in session["iterations"]] == ["rejected", "rejected"]
    assert prompts.QUESTIONS not in model.payloads[0]["instructions"]


def test_a_cut_response_runs_nothing_and_asks_for_smaller_steps(toolbox, tmp_path):
    model = FakeModel(
        [
            WRITE,
            {"incomplete": [("scad_patch", {"path": "model.scad", "old": "cube", "new": "x"})]},
            EXPORT,
            "Done.",
        ]
    )
    session = run_session(model, toolbox, "request", Limits(), tmp_path)
    assert session["status"] == "green"
    cut = session["iterations"][1]
    assert cut["incomplete"] == {"reason": "max_output_tokens"} and cut["tool_calls"] == []
    assert (toolbox.workspace / "model.scad").read_text() == "cube(10);\n"
    # The same request again, from the same response, with a note at the end.
    again = model.payloads[2]
    assert again["previous_response_id"] == model.payloads[1]["previous_response_id"] == "resp_1"
    assert again["input"][:-1] == model.payloads[1]["input"]
    note = again["input"][-1]["content"]
    assert note.startswith("Your previous response was cut short") and "32000 tokens" in note
    assert "go back to sending the edits of one change with their checks" in note
    assert "response cut short (max_output_tokens)" in summary.markdown(tmp_path)


def test_a_session_is_told_when_its_end_is_in_sight(toolbox, tmp_path):
    model = FakeModel([WRITE, EXPORT, EXPORT, "Done."])
    limits = Limits(max_requests=4, wrap_up_requests=2)
    session = run_session(model, toolbox, "request", limits, tmp_path)
    notices = [it.get("wrap_up_notice") for it in session["iterations"]]
    assert notices[0] is None and notices[3] is None  # 3 left, then none
    assert notices[1].startswith(
        "About 2 requests of the session are left: 2 of 4 done, USD 0.05 of 2.00 and 0 of 20 "
        "min. Put closing first"
    )
    assert notices[2].startswith("You have one request left: the session reaches its limit (3 of 4")
    assert "Close now, without calling tools" in notices[2]
    assert model.payloads[2]["input"][-1] == {"role": "user", "content": notices[1]}
    assert model.payloads[3]["input"][-1] == {"role": "user", "content": notices[2]}
    assert session["status"] == "green"
    for payload in model.payloads:  # streamed, and routed to the backend with the cache
        assert (
            payload["stream"] is True
            and payload["prompt_cache_key"] == "cadverify-agent-muse-wonder-1.0"
        )
        assert payload["prompt_cache_retention"] == "24h"


def test_a_rejected_close_near_the_end_says_so(toolbox, tmp_path):
    model = FakeModel([WRITE, "Done.", "Done."])
    limits = Limits(max_requests=3, wrap_up_requests=5)
    session = run_session(model, toolbox, "request", limits, tmp_path)
    assert session["iterations"][1]["close"] == "rejected"
    assert model.payloads[2]["input"].endswith(session["iterations"][1]["wrap_up_notice"])
    assert session["iterations"][1]["wrap_up_notice"].startswith("You have one request left")


def test_requests_left_at_the_session_average():
    limits = Limits(max_requests=150, max_cost_usd=12.0, max_wall_s=5400.0)
    assert requests_left(limits, 80, 7.42, 4203.0) == 22  # time: 1197 s left at 52.5 s each
    assert requests_left(limits, 10, 6.0, 600.0) == 10  # cost: USD 6 left at 0.60 each
    assert requests_left(limits, 145, 1.0, 100.0) == 5  # the request limit
    assert requests_left(limits, 0, 0.0, 0.0) == 150
    assert requests_left(limits, 100, 12.5, 100.0) == 0
    assert wrap_up_notice(Limits(), 24, 0.1, 1.0) is None  # not asked for
    assert wrap_up_notice(Limits(max_requests=4, wrap_up_requests=2), 4, 0.1, 1.0) is None
