"""The tools the model sees, run in the session's sandbox, and the state the gates need.

Twelve tools: scad_write / scad_patch, scad_compile, scad_export, mesh_report, render_sheet and
printability_report; run_shell and run_python (the model's own code, in the container),
view_image (an image the model made in the workspace) and render_view (a view on demand: free
camera, zoom, cuts, several parts, highlights); and interference_check (the assembly measured as
G3 and G4 measure it). The gates are in agent/gates.py and the close of G8 in agent/closing.py.

After every call the host mirror is synced; the call's log (tools/NNNN-name.json) lists the
files it created, modified or deleted.

Rules enforced here rather than asked for in the prompt:
- After an image (render_sheet, render_view or view_image) the sources cannot change until a
  numeric check has run: scad_export, mesh_report, printability_report, interference_check,
  render_view with a cut or the holes, or the model's own code (run_shell, run_python) ending
  with exit 0 without editing a .scad. A visual finding is a hypothesis; it is confirmed with
  numbers before it is fixed. A .scad changed by shell is an edit like scad_patch: when blocked,
  it is undone.
- The gates verify the .scad files of the workspace, as the mirror holds them, in a new
  container; G7 needs the sheet of the verified export, matched by SHA-256.
- An export of model.scad with the default parameters and a mesh the model has not seen brings
  its sheet attached (_auto_sheet): one early session made 34 exports and looked at none of its
  redesign. The sheet comes with the export's numbers, so it leaves no image to confirm, and it
  is the sheet G7 asks for.
- Before its first question, the model looks at what it got (look_missing): the seed compiled,
  and every option of the `part` selector, the assembly too, exported and seen.
- A spec that moves to what the mesh already measured is flagged in the tool result
  (agent/spec_history.py), and the close must tell it (G8).
- Each image is described (describe_image), so the loop can take old ones out of the context and
  leave in their place what they showed and how to ask for them again.
"""

from __future__ import annotations

import base64
import hashlib
import json
import time
from pathlib import Path
from typing import Any

from cadverify.agent.gates import (
    DEFAULT_OUTPUT,
    GATES,
    PENDING,
    evaluate,
    part_ok,
    print_in_place_problems,
)
from cadverify.agent.sandbox import SOURCE_MAX_BYTES, WORKDIR
from cadverify.agent.spec_history import SpecHistory, notes
from cadverify.cadcheck.render import VIEWS
from cadverify.cadcheck.scad import ASSEMBLY, PART
from cadverify.cadcheck.view import HIGHLIGHTS
from cadverify.scad_source import customizer_options

MAIN_SOURCE = "model.scad"
COMPILE_TIMEOUT_S = 120
EXPORT_TIMEOUT_S = 300
VIEW_TIMEOUT_S = 180
ASSEMBLY_TIMEOUT_S = 900
ASSEMBLY_DIR = "checks/assembly"
EXEC_GRACE_S = 30
RUN_TIMEOUT_S = 60  # default per run_shell / run_python call
RUN_TIMEOUT_MAX_S = 300
MAX_STDOUT, MAX_STDERR = 8000, 4000
# view_image: about 2,400 tokens at most, as measured on the API.
IMAGE_MAX_SIDE, IMAGE_MAX_PIXELS = 1568, 1_800_000
# render_view and view_image images per session; the sheets are not counted, G7 needs them.
MAX_EXPLORATION_IMAGES = 200
FILE_LIST_MAX = 30
EDIT_TOOLS = {"scad_write", "scad_patch"}
NUMERIC_TOOLS = {"scad_export", "mesh_report", "printability_report", "interference_check"}
VISUAL_TOOLS = {"render_sheet", "render_view", "view_image"}
CODE_TOOLS = {"run_shell", "run_python"}

_OVERRIDES = {
    "type": "object",
    "description": "Values that replace parameters of the file (-D name=value).",
    "additionalProperties": {"type": ["number", "string", "boolean", "array"]},
}
_STL = {"type": "string", "description": "Path of the STL scad_export returned."}
_VEC = {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}
_TIMEOUT = {
    "type": "number",
    "description": f"Seconds; {RUN_TIMEOUT_S} by default, {RUN_TIMEOUT_MAX_S} at most.",
}
_SANDBOX = (
    "Runs in /work, inside the sandbox: no network, 2 CPUs and 4 GB; only /work (1 GB) and /tmp "
    "(512 MB) are writable. There is python with numpy, scipy, trimesh, manifold3d, shapely and "
    "matplotlib, openscad and cadcheck (the tools' CLI). Returns stdout and stderr (if long, the "
    "start and the end with the count of bytes left out), the exit code, the time and the files "
    "created, modified or deleted. Processes still alive are ended when the call ends."
)


def _tool(name: str, description: str, properties: dict, required: list[str]) -> dict:
    return {
        "type": "function",
        "name": name,
        "description": description,
        "parameters": {"type": "object", "properties": properties, "required": required},
    }


SCHEMAS = [
    _tool(
        "scad_write",
        "Creates or fully replaces a .scad file of the workspace.",
        {"path": {"type": "string"}, "content": {"type": "string"}},
        ["path", "content"],
    ),
    _tool(
        "scad_patch",
        "Replaces the text `old` with `new` in a .scad file. Fails unless `old` appears exactly "
        "once: copy the exact text, with its indentation.",
        {"path": {"type": "string"}, "old": {"type": "string"}, "new": {"type": "string"}},
        ["path", "old", "new"],
    ),
    _tool(
        "scad_compile",
        "Evaluates the program without building geometry: echo, warnings, failed asserts and "
        "errors.",
        {"path": {"type": "string"}, "overrides": _OVERRIDES},
        ["path"],
    ),
    _tool(
        "scad_export",
        "Exports one part to STL (ASCII). Returns the path, the mesh_report and spec_check, the "
        "mesh compared with the file's cadverify_spec echo. From model.scad with the default "
        "parameters, if the mesh is new (you did not see its sheet or a view of it), it brings "
        "its sheet attached, the one render_sheet makes.",
        {
            "path": {"type": "string"},
            "part": {"type": "string", "description": "Value of the `part` selector, if any."},
            "overrides": _OVERRIDES,
        },
        ["path"],
    ),
    _tool(
        "mesh_report",
        "Watertightness, bad edges and where they are, volume, bounds, size, bodies, cavities, "
        "inverted shells and through holes of an STL.",
        {"stl": _STL},
        ["stl"],
    ),
    _tool(
        "render_sheet",
        "A sheet of orthographic views of the STL, which you get as an image: flat shading, "
        "sharp edges and outlines in black, open and non-manifold edges in red, faces seen from "
        "behind in magenta, axes and a scale in mm.",
        {
            "stl": _STL,
            "views": {
                "type": "array",
                "items": {"type": "string", "enum": list(VIEWS)},
                "description": "All six by default.",
            },
        },
        ["stl"],
    ),
    _tool(
        "printability_report",
        "Overhangs of more than 45° (measured from the vertical) grouped by zone in the STL's "
        "orientation (+Z up, resting on the minimum z), whether each zone is declared in "
        "overhangs_allowed, and whether the part fits the bed of the Bambu Lab A1 "
        "(256 × 256 × 256 mm).",
        {"stl": _STL},
        ["stl"],
    ),
    _tool(
        "run_shell",
        "Runs a bash command. " + _SANDBOX,
        {"cmd": {"type": "string"}, "timeout_s": _TIMEOUT},
        ["cmd"],
    ),
    _tool(
        "run_python",
        "Runs a Python program (python -c). " + _SANDBOX,
        {"code": {"type": "string"}, "timeout_s": _TIMEOUT},
        ["code"],
    ),
    _tool(
        "view_image",
        "Shows you a PNG or JPG image of the workspace that you made (for example, a matplotlib "
        f"plot), scaled down to {IMAGE_MAX_SIDE} px per side and "
        f"{IMAGE_MAX_PIXELS / 1e6:.1f} MP at most.",
        {"path": {"type": "string"}},
        ["path"],
    ),
    _tool(
        "render_view",
        "A view on demand of one or more STLs, which you get as an image with its numbers. Free "
        "camera, orthographic or perspective; zoom to a box or to a point; a cut along any "
        "plane: the cut part with the cut face in salmon and, beside it, the 2D profile of the "
        "cut on a mm grid, with area, regions, holes and box; several parts together, apart "
        "with explode; highlights: overhangs, support faces and the spec's bounds box, through "
        "holes with their diameter at each end, and the spec's details (highlight details) with "
        "what each one measures, and for each declared detail whether it is in frame and up "
        "close (details_in_view). Coordinates in mm of the STL.",
        {
            "stl": {
                "type": "array",
                "items": {"type": "string"},
                "description": "STLs from scad_export; several are shown together.",
            },
            "camera": {
                "type": "object",
                "description": 'One of: {"view": name}, {"direction": [x, y, z]} (from the part '
                'toward the camera) or {"azimuth": degrees, "elevation": degrees}. iso by '
                "default; with a cut, facing the cut face.",
                "properties": {
                    "view": {"type": "string", "enum": list(VIEWS)},
                    "direction": _VEC,
                    "azimuth": {"type": "number"},
                    "elevation": {"type": "number"},
                },
            },
            "projection": {"type": "string", "enum": ["orthographic", "perspective"]},
            "zoom": {
                "type": "object",
                "description": '{"center": [x, y, z], "size_mm": side} or '
                '{"box": [[xmin, ymin, zmin], [xmax, ymax, zmax]]}.',
                "properties": {
                    "center": _VEC,
                    "size_mm": {"type": "number"},
                    "box": {"type": "array", "items": _VEC, "minItems": 2, "maxItems": 2},
                },
            },
            "cut": {
                "type": "object",
                "description": "Cut plane; the side the normal points to is taken away.",
                "properties": {"point": _VEC, "normal": _VEC},
                "required": ["point", "normal"],
            },
            "explode": {"type": "number", "description": "mm to move several parts apart."},
            "highlight": {"type": "array", "items": {"type": "string", "enum": list(HIGHLIGHTS)}},
            "title": {"type": "string"},
        },
        ["stl"],
    ),
    _tool(
        "interference_check",
        'Measures the assembly (part = "assembly") as G3 and G4 measure it: exports each '
        "instance in assembly coordinates and compares it with its part (volume, area, "
        "inertia); copies and units; overlaps between instances (volume, mean thickness and "
        "where) and the gap between the ones that touch; whether everything forms one group; "
        "bounds and support faces of the assembly; each motion swept through its whole range, "
        "with how deep each declared flex goes, and the assembly order; with print_in_place, "
        "the clearances and the print of all the parts together (G5). Leaves in "
        f"{ASSEMBLY_DIR}/ the STL of each instance, each overlap, each pose that collides and "
        "the deepest overlap of each flex, to look at with render_view.",
        {"path": {"type": "string"}},
        ["path"],
    ),
]


class ToolBox:
    def __init__(
        self,
        sandbox,
        log_dir: Path,
        max_images: int = MAX_EXPLORATION_IMAGES,
        requirements: dict[str, Any] | None = None,
    ):
        self.sandbox = sandbox
        self.workspace = sandbox.workspace
        self.log_dir = log_dir
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.verify_dir = log_dir.parent / "verify"
        self.schemas = SCHEMAS
        self.max_images = max_images
        self.requirements = dict(requirements or {})  # the request's demands on the assembly
        self.seq = 0
        # STL path -> {"source", "part", "spec", "overrides", "sha256", "kind", "label"}; kind
        # is "export" (scad_export) or what interference_check left: instance, overlap, collision.
        self.exports: dict[str, dict[str, Any]] = {}
        self.seen_sheets: set[str] = set()  # SHA-256 of every STL whose sheet the model saw
        self.seen_shas: set[str] = set()  # ... whose sheet or render_view the model saw
        self.view_groups: list[set[str]] = []  # the STL drawn together in each render_view
        self.close_views: set[tuple[str, str]] = set()  # (STL SHA-256, detail) seen up close
        self.compiled_sources: set[str] = set()  # versions of model.scad compiled as they are
        self.image_log: dict[int, dict[str, Any]] = {}  # seq -> what each image showed
        self.history = SpecHistory()
        self._notes: list[str] = []  # spec adjustments the verification found, for the next call
        self.images = {name: 0 for name in VISUAL_TOOLS}  # and scad_export's sheets, once any
        # The image whose finding is not confirmed yet: {"seq", "tool", "source"}.
        self.visual_pending: dict[str, Any] | None = None
        self.numeric_sources: set[str] = set()  # source versions with a numeric check
        self.rule_events: list[dict[str, Any]] = []
        self.scad: dict[str, str] = {}  # .scad path -> SHA-256, as of the last sync
        self.sources: dict[str, bytes | None] = {}  # their bytes in the mirror
        self._verified: dict[str, dict[str, Any]] = {}  # source hash -> verify
        self._sync()

    # ---- dispatch -------------------------------------------------------------------------

    def call(self, name: str, raw_arguments: str, iteration: int) -> tuple[dict, str | None]:
        """Run one tool call. Returns the JSON result and, for an image, a PNG data URL."""
        self.seq += 1
        t0 = time.perf_counter()
        blocked = self._edit_blocked()
        before = (dict(self.scad), dict(self.sources))
        png, event = None, None
        try:
            args = json.loads(raw_arguments or "{}")
            if not isinstance(args, dict):
                raise ValueError("the arguments must be a JSON object")
        except (json.JSONDecodeError, ValueError) as exc:
            args, result = None, {"ok": False, "error": f"Invalid arguments: {exc}"}
        else:
            handler = getattr(self, f"_{name}", None)
            if handler is None or name not in {s["name"] for s in self.schemas}:
                result = {"ok": False, "error": f"Unknown tool: {name}"}
            elif name in EDIT_TOOLS and blocked:
                result = dict(blocked)
                event = {"seq": self.seq, "tool": name, "edit": "refused", **self._pending()}
            else:
                try:
                    result, png = handler(**args)
                except TypeError as exc:
                    result = {"ok": False, "error": f"Invalid arguments: {exc}"}
        files = self._sync()
        old = before[0]
        changed = sorted(p for p in set(old) | set(self.scad) if old.get(p) != self.scad.get(p))
        if changed and name not in EDIT_TOOLS:
            event = self._edit_by_code(name, changed, before, blocked, result)
        if event:
            self.rule_events.append(event)
        self._update_rule(name, args or {}, result, edited=bool(changed))
        if name in CODE_TOOLS and "exit_code" in result:
            result["files"] = {
                "created": _capped(files.get("new", [])),
                "modified": _capped(files.get("modified", [])),
                "deleted": _capped(files.get("deleted", [])),
            }
        image = self._data_url(png) if png and result.get("ok") else None
        if png and result.get("ok") and image is None:
            result = {"ok": False, "error": f"Could not read the image {png}"}
        if image:
            self.images[name] = self.images.get(name, 0) + 1
            if name == "scad_export":  # its sheet: asked for again with render_sheet
                self._log_image("render_sheet", {"stl": result["path"]}, png, result)
            else:
                self._log_image(name, args or {}, png, result)
        if notes := self.take_notes():
            result["spec_notes"] = list(result.get("spec_notes", [])) + notes
        record = {
            "seq": self.seq,
            "iteration": iteration,
            "name": name,
            "arguments": args if args is not None else raw_arguments,
            "result": result,
            "seconds": round(time.perf_counter() - t0, 3),
            "image": png if image else None,
            "files": {k: files.get(k, []) for k in ("new", "modified", "deleted", "not_mirrored")},
            "scad_changed": changed,
            "rule": event,
            "source": self.source_hash(),
        }
        (self.log_dir / f"{self.seq:04d}-{name}.json").write_text(
            json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return result, image

    # ---- the OpenSCAD tools ---------------------------------------------------------------

    def _scad_write(self, path: str, content: str) -> tuple[dict, None]:
        return self._cadcheck(["write", self._rel(path)], stdin=content), None

    def _scad_patch(self, path: str, old: str, new: str) -> tuple[dict, None]:
        edit = json.dumps({"old": old, "new": new})
        return self._cadcheck(["patch", self._rel(path)], stdin=edit), None

    def _scad_compile(self, path: str, overrides: dict | None = None) -> tuple[dict, None]:
        args = ["compile", self._rel(path), *self._defines(overrides)]
        args += ["--timeout", str(COMPILE_TIMEOUT_S)]
        result = self._cadcheck(args, timeout_s=COMPILE_TIMEOUT_S + EXEC_GRACE_S)
        if self._rel(path) == MAIN_SOURCE and not overrides and "errors" in result:
            self.compiled_sources.add(self.source_hash())
        return result, None

    def _scad_export(
        self, path: str, part: str | None = None, overrides: dict | None = None
    ) -> tuple[dict, str | None]:
        args = ["export", self._rel(path), *self._defines(overrides)]
        args += ["--timeout", str(EXPORT_TIMEOUT_S)] + (["--part", part] if part else [])
        result = self._cadcheck(args, timeout_s=EXPORT_TIMEOUT_S + EXEC_GRACE_S)
        if result.get("path"):
            result["path"] = self._rel(result["path"])
            self.exports[result["path"]] = {
                "source": self.source_hash(),
                "part": part,
                "spec": result.get("spec"),
                "overrides": dict(overrides or {}),
                "sha256": result.get("sha256"),
                "kind": "export",
                "label": part,
            }
        if self._rel(path) == MAIN_SOURCE and not overrides:
            # Without part, a file with a selector exports its default option, which the
            # orchestrator does not parse: the verification observes every option anyway. The
            # assembly is observed through its report (interference_check, verify).
            label = part or (None if self._options() else DEFAULT_OUTPUT)
            if label is not None and label != ASSEMBLY:
                found = self.history.observe_part(label, result, self.seq)
                if found:
                    result["spec_notes"] = notes(found)
            sha256 = result.get("sha256")
            if result.get("ok") and result.get("path") and sha256 and sha256 not in self.seen_shas:
                return self._auto_sheet(result)
        return result, None

    def _auto_sheet(self, result: dict) -> tuple[dict, str | None]:
        """The sheet of a new mesh, attached to its export."""
        stl = result["path"]
        png = f"renders/sheet-{self.seq:03d}.png"
        sheet = self._cadcheck(["sheet", stl, "--out", png, "--title", stl])
        if not sheet.get("ok"):
            result["sheet"] = {"ok": False, "error": sheet.get("error", "no sheet")}
            return result, None
        self.seen_sheets.add(sheet["stl_sha256"])
        self.seen_shas.add(sheet["stl_sha256"])
        result["sheet"] = {
            "png": png,
            "views": sheet["views"],
            "note": "The sheet of this mesh is attached as an image: look at it before going on. "
            "It comes with the export's numbers, so it leaves nothing to confirm. An export of "
            "the same mesh does not repeat it: ask for it with render_sheet.",
        }
        return result, png

    def _mesh_report(self, stl: str) -> tuple[dict, None]:
        stl = self._rel(stl)
        return self._with_stale_warning(stl, self._cadcheck(["mesh", stl])), None

    def _printability_report(self, stl: str) -> tuple[dict, None]:
        stl = self._rel(stl)
        spec = (self.exports.get(stl) or {}).get("spec") or {}
        allowed = json.dumps(spec.get("overhangs_allowed", []))
        result = self._cadcheck(["printability", stl, "--allowed", allowed])
        if stl not in self.exports:
            result["warning"] = "This STL did not come from scad_export in this session: no zones"
        return self._with_stale_warning(stl, result), None

    def _render_sheet(self, stl: str, views: list[str] | None = None) -> tuple[dict, str | None]:
        stl = self._rel(stl)
        png = f"renders/sheet-{self.seq:03d}.png"
        args = ["sheet", stl, "--out", png, "--title", stl]
        result = self._cadcheck(args + (["--views", ",".join(views)] if views else []))
        if not result.get("ok"):
            return result, None
        self.seen_sheets.add(result["stl_sha256"])
        self.seen_shas.add(result["stl_sha256"])
        result = {
            "ok": True,
            "png": png,
            "views": result["views"],
            "size": result["size"],
            "triangles": result["triangles"],
            "edges": result["edges"],
            "note": "The sheet is attached as an image. A visual finding is a hypothesis: "
            + CONFIRM_HINT,
        }
        return self._with_stale_warning(stl, result), png

    # ---- the model's own code and images ----------------------------------------------------

    def _run_shell(self, cmd: str, timeout_s: float | None = None) -> tuple[dict, None]:
        return self._run("shell", cmd, timeout_s), None

    def _run_python(self, code: str, timeout_s: float | None = None) -> tuple[dict, None]:
        return self._run("python", code, timeout_s), None

    def _run(self, kind: str, code: str, timeout_s: float | None) -> dict:
        if not isinstance(code, str):
            return {"ok": False, "error": "the code is a string"}
        try:
            timeout = min(max(float(timeout_s or RUN_TIMEOUT_S), 1.0), RUN_TIMEOUT_MAX_S)
        except (TypeError, ValueError):
            return {"ok": False, "error": "timeout_s is a number of seconds"}
        request = {
            "kind": kind,
            "code": code,
            "timeout_s": timeout,
            "max_stdout": MAX_STDOUT,
            "max_stderr": MAX_STDERR,
        }
        result = self._cadcheck(["run"], json.dumps(request), timeout + EXEC_GRACE_S)
        reaped = self.sandbox.reap()
        if reaped.get("killed"):
            result["processes_ended"] = reaped["killed"]
        if not reaped.get("ok", False):
            result["process_warning"] = f"processes were left alive: {reaped}"
        return result

    def _view_image(self, path: str) -> tuple[dict, str | None]:
        if limit := self._image_limit():
            return limit, None
        png = f"renders/image-{self.seq:03d}.png"
        args = ["image", self._rel(path), "--out", png]
        args += ["--max-side", str(IMAGE_MAX_SIDE), "--max-pixels", str(IMAGE_MAX_PIXELS)]
        result = self._cadcheck(args)
        if not result.get("ok"):
            return result, None
        result["note"] = "The image is attached. " + CONFIRM_HINT
        return result, png

    def _render_view(
        self,
        stl: list[str] | str,
        camera: dict | None = None,
        projection: str | None = None,
        zoom: dict | None = None,
        cut: dict | None = None,
        explode: float | None = None,
        highlight: list[str] | None = None,
        title: str | None = None,
    ) -> tuple[dict, str | None]:
        if limit := self._image_limit():
            return limit, None
        stls = [self._rel(s) for s in ([stl] if isinstance(stl, str) else list(stl or []))]
        if not stls:
            return {"ok": False, "error": "At least one STL is needed"}, None
        png = f"renders/view-{self.seq:03d}.png"
        parts = []
        for i, path in enumerate(stls):
            export = self.exports.get(path) or {}
            label = export.get("label") or (Path(path).stem.split(".")[0] + f"-{i + 1}")
            parts.append({"stl": path, "label": label, "spec": export.get("spec")})
        request = {
            "parts": parts,
            "out": png,
            "camera": camera,
            "projection": projection,
            "zoom": zoom,
            "cut": cut,
            "explode": explode,
            "highlight": highlight,
            "title": title,
        }
        result = self._cadcheck(["view"], json.dumps(request), VIEW_TIMEOUT_S)
        if not result.get("ok"):
            return result, None
        result.pop("renderer", None)
        result["png"] = result.pop("path")
        shown = {part.get("sha256") for part in result.get("parts") or []} - {None}
        self.seen_shas |= shown
        self.view_groups.append(shown)
        for detail in result.get("details_in_view") or []:
            if detail.get("close"):
                self.close_views.add((detail["sha256"], detail["name"]))
        warnings = []
        for path in stls:
            if path not in self.exports:
                warnings.append(f"{path} did not come from scad_export in this session: no spec")
            elif self.exports[path]["source"] != self.source_hash():
                warnings.append(f"The .scad changed after exporting {path}: export it again")
        if warnings:
            result["warning"] = warnings
        result["note"] = "The view is attached as an image. " + CONFIRM_HINT
        return result, png

    # ---- the assembly -----------------------------------------------------------------------

    def _interference_check(self, path: str) -> tuple[dict, None]:
        args = ["assembly", self._rel(path), "--out-dir", ASSEMBLY_DIR]
        args += ["--requirements", json.dumps(self.requirements)]
        report = _relative(self._cadcheck(args, timeout_s=ASSEMBLY_TIMEOUT_S + EXEC_GRACE_S))
        if "problems" not in report:
            return report, None
        source = self.source_hash()

        def register(stl, kind: str, label: str, part=None, sha256=None) -> None:
            if stl:
                self.exports[stl] = {
                    "source": source,
                    "part": part,
                    "spec": None,  # a part's spec is in its own coordinates, not these
                    "overrides": {},
                    "sha256": sha256,
                    "kind": kind,
                    "label": label,
                }

        for inst in report.get("instances") or []:
            register(inst.get("stl"), "instance", inst["name"], inst["part"], inst.get("sha256"))
        for pair in report.get("pairs") or []:
            register(pair.get("stl"), "overlap", f"overlap {pair['a']} / {pair['b']}")
        for motion in report.get("motions") or []:
            hit = motion.get("collisions") or {}
            register(hit.get("overlap_stl"), "collision", f"collision of {motion['name']}")
            register(hit.get("posed_stl"), "collision", f"pose of {motion['name']}")
            for flex in motion.get("flex") or []:
                label = f"flex {flex['a']} / {flex['b']} of {motion['name']}"
                register(flex.get("overlap_stl"), "collision", label)
        report.pop("spec", None)  # the model wrote it
        report["ok"] = True  # the measurement ran; its findings are in problems
        # As G5 judges it: the clearances, and the print of all the parts together.
        report["problems"]["G5"] = print_in_place_problems(report)
        report["green"] = not any(report["problems"].values())
        if self._rel(path) == MAIN_SOURCE:
            found = self.history.observe_assembly(report, self.seq)
            if found:
                report["spec_notes"] = notes(found)
        return report, None

    # ---- gates ----------------------------------------------------------------------------

    def gates(self) -> dict[str, Any]:
        """Gates of the current sources, verified in a new container (cached per version)."""
        source = self.source_hash()
        if source not in self._verified:
            self._verified[source] = self._verify(source)
            self._observe(self._verified[source])
        verify = self._verified[source]
        if "compile" not in verify:
            failed = {"ok": False, "detail": [f"the verification failed: {verify.get('error')}"]}
            red = {g: failed for g in GATES if g != "G8"}
            return {
                "source": source,
                "error": verify.get("error"),
                "gates": {**red, "G8": {"ok": None, "detail": [PENDING]}},
            }
        stl_sha = {
            part["part"] or DEFAULT_OUTPUT: part["export"].get("sha256") for part in verify["parts"]
        }
        gates = evaluate(
            verify,
            self.seen_sheets,
            stl_sha,
            view_groups=self.view_groups,
            close_views=self.close_views,
        )
        state = {
            "source": source,
            "gates": gates,
            "parts": [
                {
                    "part": p["part"],
                    "ok": part_ok(p),
                    "mesh": p["export"].get("mesh"),
                    "spec": p["export"].get("spec"),
                    "spec_check": p["export"].get("spec_check"),
                    "printability": _short_printability(p["printability"]),
                }
                for p in verify["parts"]
            ],
        }
        if "assembly" in verify:
            state["assembly"] = verify["assembly"]
        return state

    def _observe(self, verify: dict[str, Any]) -> None:
        """The verification of a new version, in the spec history: what it flags goes to the
        model with its next tool result."""
        if "compile" not in verify:
            return
        found = []
        for part in verify["parts"]:
            found += self.history.observe_part(part["part"] or DEFAULT_OUTPUT, part["export"])
        found += self.history.observe_assembly(verify.get("assembly") or {})
        self._notes += notes(found)

    def _verify(self, source: str) -> dict[str, Any]:
        if MAIN_SOURCE not in self.scad:
            return {"ok": False, "error": f"there is no {MAIN_SOURCE}"}
        missing = [p for p, data in self.sources.items() if data is None]
        if missing:
            return {"ok": False, "error": f"the sources {missing[:5]} could not be copied"}
        total = sum(len(d) for d in self.sources.values() if d is not None)
        if total > SOURCE_MAX_BYTES:
            return {
                "ok": False,
                "error": f"the .scad files add up to {total} bytes, more than {SOURCE_MAX_BYTES}",
            }
        sources = {p: d for p, d in self.sources.items() if d is not None}
        out = self.verify_dir / source
        for rel, data in sources.items():
            target = (out / "src" / rel).resolve()
            if target.is_relative_to(out.resolve()):
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        verify = self.sandbox.verify(
            sources, MAIN_SOURCE, assembly=True, requirements=self.requirements
        )
        (out / "verify.json").write_text(json.dumps(verify, ensure_ascii=False, indent=2))
        return verify

    def take_notes(self) -> list[str]:
        """The spec adjustments not told to the model yet; told from now on."""
        notes, self._notes = self._notes, []
        return notes

    def look_missing(self) -> list[str]:
        """What the model has not looked at yet in this version (before a question): the main
        source compiled, and every option of `part`, the assembly too, exported with the default
        parameters and seen in a sheet or a view."""
        if self.sources.get(MAIN_SOURCE) is None:
            return []
        source = self.source_hash()
        missing = []
        if source not in self.compiled_sources:
            missing.append("compile model.scad (scad_compile)")
        for part in self._options() or [None]:
            seen = any(
                e["kind"] == "export"
                and e["source"] == source
                and e["part"] == part
                and not e["overrides"]
                and e["sha256"] in self.seen_shas
                for e in self.exports.values()
            )
            if not seen:
                what = f'the part "{part}"' if part else "the default output"
                missing.append(
                    f"export {what} with the default parameters and look at it (scad_export "
                    "brings its sheet)"
                )
        return missing

    def describe_image(self, seq: int) -> str:
        """What the image of call `seq` showed and how to ask for it again, for its place in the
        context once it leaves."""
        info = self.image_log.get(seq)
        if info is None:
            return "[Image taken out of the context to make room for new ones.]"
        stale = "" if info["source"] == self.source_hash() else "; the .scad changed since"
        args = json.dumps(info["args"], ensure_ascii=False)
        if len(args) > 600:
            args = args[:600] + "..."
        return (
            f"[Image taken out of the context to make room for new ones: {info['tool']} "
            f"(call {seq}) of {info['what']}{stale}. To see it again, repeat the call: "
            f"{info['tool']} {args}]"
        )

    def _log_image(self, name: str, args: dict, png: str, result: dict) -> None:
        stls = args.get("stl") or []
        stls = [self._rel(s) for s in ([stls] if isinstance(stls, str) else stls)]
        entries = [self.exports.get(s) or {} for s in stls]
        parts = set()
        assembly = False
        instances = [e for e in entries if e.get("kind") == "instance"]
        for entry in entries:
            if entry.get("kind") == "export":
                if entry["part"] == ASSEMBLY and not entry["overrides"]:
                    assembly = True
                elif entry["part"] != ASSEMBLY:
                    parts.add(entry["part"] or DEFAULT_OUTPUT)
        if len(instances) >= 2:
            assembly = True
        elif instances:
            parts.add(instances[0]["part"])
        labels = [e.get("label") or Path(s).name for e, s in zip(entries, stls, strict=True)]
        if name == "view_image":
            what = f"the image {args.get('path')}"
        else:
            what = ", ".join(labels) or "?"
            if args.get("cut"):
                what += f", cut by {json.dumps(args['cut'])}"
            if args.get("zoom"):
                what += f", zoomed to {json.dumps(args['zoom'])}"
        self.image_log[self.seq] = {
            "tool": name,
            "args": args,
            "png": png,
            "what": what,
            "parts": sorted(parts),
            "assembly": assembly,
            "source": self.source_hash(),
        }

    def _options(self) -> list[str]:
        data = self.sources.get(MAIN_SOURCE)
        if data is None:
            return []
        return customizer_options(data.decode("utf-8", errors="replace"), PART)

    def source_hash(self) -> str:
        digest = hashlib.sha256()
        for path, sha in sorted(self.scad.items()):
            digest.update(path.encode() + b"\0" + sha.encode() + b"\0")
        return digest.hexdigest()[:16]

    # ---- rules ----------------------------------------------------------------------------

    def _edit_blocked(self) -> dict | None:
        if self.visual_pending is None:
            return None
        return {
            "ok": False,
            "error": "After an image, confirm with numbers before changing the .scad: "
            + CONFIRM_HINT,
        }

    def _edit_by_code(self, name, changed, before, blocked, result) -> dict:
        """The model's code changed .scad files: an edit, allowed unless edits are blocked.
        Then the files go back to their bytes before the call."""
        event = {"seq": self.seq, "tool": name, "scad": changed}
        if not blocked:
            result["scad_edited"] = changed
            return {**event, "edit": "allowed"}
        old_scad, old_sources = before
        self.sandbox.restore({p: old_sources.get(p) if p in old_scad else None for p in changed})
        self._sync()
        restored = all(self.scad.get(p) == old_scad.get(p) for p in changed)
        result["ok"] = False
        result["error"] = (
            f"You changed {', '.join(changed)} by code and "
            + ("I undid it. " if restored else "it could not be undone. ")
            + blocked["error"]
        )
        return {**event, "edit": "undone" if restored else "not undone", **self._pending()}

    def _update_rule(self, name: str, args: dict, result: dict, edited: bool) -> None:
        ok = result.get("ok", True) and "error" not in result
        if not ok:
            return
        measured = args.get("cut") or "holes" in (args.get("highlight") or [])
        numeric = (
            name in NUMERIC_TOOLS
            or (name == "render_view" and measured)
            or (name in CODE_TOOLS and result.get("exit_code") == 0 and not edited)
        )
        if numeric:
            # A view with a cut or the holes is an image and its numbers at once: it confirms
            # an earlier image and leaves nothing pending.
            if self.visual_pending is not None:
                self.rule_events.append({"seq": self.seq, "confirmed_by": name, **self._pending()})
            self.visual_pending = None
            self.numeric_sources.add(self.source_hash())
        elif name in VISUAL_TOOLS:
            self.visual_pending = {"seq": self.seq, "tool": name, "source": self.source_hash()}

    def _pending(self) -> dict:
        pending = self.visual_pending or {}
        return {
            "image_seq": pending.get("seq"),
            "image_tool": pending.get("tool"),
            # Would the edit pass if a numeric check of the same version before the image
            # counted? Logged to weigh that looser rule against this one.
            "numbers_before_image": pending.get("source") in self.numeric_sources,
        }

    def _image_limit(self) -> dict | None:
        used = self.images["render_view"] + self.images["view_image"]
        if used < self.max_images:
            return None
        return {
            "ok": False,
            "error": f"You reached the session's limit of {self.max_images} images of "
            "render_view and view_image. render_sheet is still available.",
        }

    # ---- helpers --------------------------------------------------------------------------

    def _sync(self) -> dict:
        files = self.sandbox.sync()
        if not files.get("ok"):
            return files
        scad = files["scad"]
        sources: dict[str, bytes | None] = {}
        for path, sha in scad.items():
            data = self.sources.get(path) if self.scad.get(path) == sha else None
            if data is None:
                file = (self.workspace / path).resolve()
                if file.is_relative_to(self.workspace) and file.is_file():
                    data = file.read_bytes()
            # The mirror's copy counts only if it is the file the manifest hashed.
            ok = data is not None and hashlib.sha256(data).hexdigest() == sha
            sources[path] = data if ok else None
        self.scad, self.sources = dict(scad), sources
        return files

    def _data_url(self, png: str) -> str | None:
        """The image as a data URL, read only from inside the mirror: its bytes go to the API
        undecoded."""
        file = (self.workspace / png).resolve()
        if not file.is_relative_to(self.workspace):
            return None
        if not file.is_file():
            self.sandbox.pull([png])
        if not file.is_file():
            return None
        return "data:image/png;base64," + base64.b64encode(file.read_bytes()).decode()

    def _cadcheck(self, args: list[str], stdin: str | None = None, timeout_s: float = 120) -> dict:
        return self.sandbox.cadcheck(args, stdin=stdin, timeout_s=timeout_s)

    def _with_stale_warning(self, stl: str, result: dict) -> dict:
        exported = self.exports.get(stl)
        if exported and exported["source"] != self.source_hash():
            result["warning"] = "The .scad changed after this STL was exported: export it again"
        return result

    def _rel(self, path: str) -> str:
        """Workspace-relative path; the sandbox resolves it under /work."""
        path = str(path)
        if path.startswith(WORKDIR + "/"):
            path = path[len(WORKDIR) + 1 :]
        return path

    @staticmethod
    def _defines(overrides: dict | None) -> list[str]:
        args: list[str] = []
        for name, value in (overrides or {}).items():
            args += ["-D", f"{name}={json.dumps(value)}"]
        return args


CONFIRM_HINT = (
    "confirm it with numbers before fixing it: mesh_report, scad_export, printability_report, "
    "interference_check, a cut or the holes of render_view, or a calculation with run_python or "
    "run_shell."
)


def _relative(value: Any) -> Any:
    """Paths under /work, as the workspace-relative paths the tools take."""
    if isinstance(value, str):
        return value.removeprefix(WORKDIR + "/")
    if isinstance(value, list):
        return [_relative(v) for v in value]
    if isinstance(value, dict):
        return {k: _relative(v) for k, v in value.items()}
    return value


def _capped(paths: list[str]) -> list[str]:
    if len(paths) <= FILE_LIST_MAX:
        return paths
    return paths[:FILE_LIST_MAX] + [f"... and {len(paths) - FILE_LIST_MAX} more"]


def _short_printability(report: dict | None) -> dict | None:
    """The printability of a part for the close's auditor: the numbers a close may quote."""
    if not report or not report.get("ok"):
        return report
    keys = (
        "fits_bed",
        "bed_mm",
        "size",
        "bed_margin_mm",
        "base_area_mm2",
        "overhang_area_mm2",
        "zones_total",
        "zones_undeclared",
        "undeclared_area_mm2",
    )
    short = {k: report[k] for k in keys if k in report}
    if "allowed_coverage" in report:
        short["allowed_share_of_surface"] = report["allowed_coverage"]["share"]
    if "zones" in report:
        fields = ("id", "area_mm2", "max_angle_deg", "declared_as")
        short["zones"] = [{k: z.get(k) for k in fields} for z in report["zones"]]
    return short
