"""scad_compile and scad_export, the OpenSCAD tools of the agent (docs/architecture.md).

Both return JSON-ready dicts. Diagnostics come from OpenSCAD's log, never from the exit code
alone: OpenSCAD (2021.01 and 2026.10) exits 0 after a failed assert when it exports `.echo`.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cadverify.cadcheck.mesh import load_exact, report_from_mesh
from cadverify.cadcheck.spec import SpecError, check_spec, find_spec
from cadverify.openscad import define_args, openscad_bin

PART = "part"  # the Customizer selector of a source with several parts
ASSEMBLY = "assembly"  # the `part` option of the assembly, never printed
INSTANCE_ECHO = "cadverify_instance"  # echoed by instance() of each part the assembly places
# `use <cadverify_parts.scad>`: the standard parts an assembly places (cadcheck.assembly).
STANDARD_DIR = Path(__file__).parent / "standard"

# fmt -> OpenSCAD --export-format. STL stays ASCII: its coordinates are full doubles, while
# binary STL rounds to float32 and fuses vertices that OpenSCAD leaves 1e-9 mm apart (a
# perforated plate went from closed to 202 bad edges). OpenSCAD plans binary as the default.
FORMATS = {"stl": "asciistl"}
MAX_LINES = 50

_ASSERT = re.compile(
    r"^ERROR: Assertion '(?P<condition>.*)' failed(?:: (?P<message>.*))?"
    r" in file (?P<file>.*), line (?P<line>\d+)$"
)
_ERROR = re.compile(r"^[A-Z-]*ERROR: ")
_WARNING = re.compile(r"^(?:[A-Z-]*WARNING|DEPRECATED): ")
# OpenSCAD prints strings raw, without escaping inner quotes. A value with quotes only at both
# ends is therefore a single string; two or more values always leave quotes in the middle.
_SINGLE_STRING = re.compile(r'^"[^"]*"$')
_EMPTY = "Current top level object is empty."


@dataclass(frozen=True)
class Engine:
    """An OpenSCAD binary and its geometry backend.

    backend=None runs the binary without `--backend` (OpenSCAD 2021.01 only has CGAL).
    """

    binary: str
    backend: str | None = "Manifold"

    def export_command(self) -> list[str]:
        return [self.binary] + ([f"--backend={self.backend}"] if self.backend else [])


def default_engine() -> Engine:
    """OPENSCAD_BIN (or `openscad` on PATH) with OPENSCAD_BACKEND, Manifold unless set."""
    return Engine(openscad_bin(), os.environ.get("OPENSCAD_BACKEND", "Manifold") or None)


def scad_compile(
    path: str | Path,
    overrides: dict[str, Any] | None = None,
    *,
    engine: Engine | None = None,
    timeout_s: float = 120,
) -> dict[str, Any]:
    """Evaluate the program without building geometry: echoes, warnings, failed asserts, errors.

    Exporting `.echo` instantiates the whole tree selected by the overrides, so asserts inside
    modules run, but no mesh is computed.
    """
    path = Path(path).resolve()
    engine = engine or default_engine()
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out.echo"
        run = _run(
            [engine.binary, "-o", str(out), *define_args(overrides), path.name], path, timeout_s
        )
        # Both 2021.01 and 2026.10 send every message to the .echo file and none to the console;
        # the console only matters when OpenSCAD fails before writing it.
        log = out.read_text(errors="replace") if out.exists() else run["log"]
    diag = parse_log(log)
    diag["echo"] = _cap(diag["echo"])
    ok = run["returncode"] == 0 and not diag["errors"] and not diag["asserts_failed"]
    return {"ok": ok, **diag, **_timing(run)}


def scad_export(
    path: str | Path,
    part: str | None = None,
    overrides: dict[str, Any] | None = None,
    fmt: str = "stl",
    *,
    out_dir: str | Path | None = None,
    engine: Engine | None = None,
    timeout_s: float = 900,
) -> dict[str, Any]:
    """Export one part (`part`) and attach its mesh_report and its check against the spec.

    `ok` means OpenSCAD wrote a non-empty file without errors or failed asserts; whether the
    mesh is good (closed, one body, not inside out) is in `mesh`, and whether it measures what
    the part's `cadverify_spec` echo declares is in `spec_check`, for the gates to judge.
    The file goes to `out_dir` (default: `exports/` next to the source) as
    `<stem>.<part>.<hash of the defines>.<fmt>`, so variants never overwrite each other.
    Echo values are left to scad_compile to keep the result short.
    """
    if fmt not in FORMATS:
        raise ValueError(f"Unsupported format {fmt!r}; supported: {', '.join(FORMATS)}")
    path = Path(path).resolve()
    engine = engine or default_engine()
    defines = dict(overrides or {})
    if part is not None:
        defines[PART] = part
    key = hashlib.sha256(json.dumps(defines, sort_keys=True).encode()).hexdigest()[:8]
    out_dir = Path(out_dir).resolve() if out_dir else path.parent / "exports"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{path.stem}.{part or 'default'}.{key}.{fmt}"
    out.unlink(missing_ok=True)

    cmd = [
        *engine.export_command(),
        f"--export-format={FORMATS[fmt]}",
        "-o",
        str(out),
        *define_args(defines),
        path.name,
    ]
    run = _run(cmd, path, timeout_s)
    diag = parse_log(run["log"])
    echo = diag.pop("echo")
    spec, spec_error = None, None
    try:
        spec = find_spec(echo, assembly=part == ASSEMBLY)
    except SpecError as exc:
        spec_error = str(exc)
    instances, instance_error = None, None
    try:
        instances = find_instances(echo)
    except SpecError as exc:
        instance_error = str(exc)
    empty = _EMPTY in run["log"]
    produced = out.exists() and out.stat().st_size > 0
    ok = (
        run["returncode"] == 0
        and produced
        and not empty
        and not diag["errors"]
        and not diag["asserts_failed"]
    )
    mesh = load_exact(out) if ok else None
    report = report_from_mesh(mesh) if mesh is not None else None
    return {
        "ok": ok,
        "path": str(out) if produced else None,
        "sha256": hashlib.sha256(out.read_bytes()).hexdigest() if produced else None,
        "part": part,
        "empty": empty,
        **diag,
        **_timing(run),
        "mesh": report,
        "spec": spec,
        "spec_error": spec_error,
        "spec_check": check_spec(mesh, report, spec)
        if spec and report and report["triangles"]
        else None,
        **({"instances": instances} if instances is not None else {}),
        **({"instance_error": instance_error} if instance_error else {}),
    }


def find_instances(echo: list[str]) -> list[dict[str, Any]] | None:
    """The parts an assembly places, from the echo of each instance() call, in order. None when
    there is none."""
    prefix = f"{INSTANCE_ECHO} = "
    items = []
    for value in (e.removeprefix(prefix) for e in echo if e.startswith(prefix)):
        try:
            data = json.loads(value)
        except json.JSONDecodeError:
            data = None
        ok = (
            isinstance(data, list)
            and len(data) == 3
            and isinstance(data[0], str)
            and data[0]
            and isinstance(data[1], str)
            and isinstance(data[2], int | float)
            and not isinstance(data[2], bool)
            and float(data[2]).is_integer()
            and data[2] >= 1
        )
        if not ok:
            raise SpecError(
                f"{INSTANCE_ECHO}: instance(name, part, unit) takes two strings and an integer "
                f">= 1; got {value}"
            )
        items.append({"name": data[0], "part": data[1], "unit": int(data[2])})
    if not items:
        return None
    # An instance placed twice (in a loop, or a module called twice) echoes twice: one entry,
    # and the harness says it when the names repeat with different parts.
    unique: dict[str, dict[str, Any]] = {}
    for item in items:
        if item["name"] in unique and unique[item["name"]] != item:
            raise SpecError(
                f"{INSTANCE_ECHO}: the name {item['name']!r} is used for two different "
                "instances; each instance needs its own name"
            )
        unique.setdefault(item["name"], item)
    return list(unique.values())


def parse_log(log: str) -> dict[str, list]:
    """Split an OpenSCAD log into echo values, warnings, failed asserts and other errors.

    TRACE lines (the call chain) are attached to the failed assert they follow.
    """
    echo: list[str] = []
    warnings: list[str] = []
    errors: list[str] = []
    asserts: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None  # the failed assert collecting TRACE lines
    for raw in log.splitlines():
        line = raw.rstrip()
        if line.startswith("TRACE: "):
            if current is not None:
                current["trace"].append(line.removeprefix("TRACE: "))
            continue
        current = None
        if line.startswith("ECHO: "):
            echo.append(_unquote(line.removeprefix("ECHO: ")))
        elif match := _ASSERT.match(line):
            current = {
                "condition": match["condition"],
                "message": _unquote(match["message"]) if match["message"] else None,
                "file": match["file"],
                "line": int(match["line"]),
                "trace": [],
            }
            asserts.append(current)
        elif _ERROR.match(line):
            errors.append(line)
        elif _WARNING.match(line):
            warnings.append(line)
    return {
        "echo": echo,  # all of it: the spec and the instances may come after many others
        "warnings": _cap(list(dict.fromkeys(warnings))),
        "asserts_failed": asserts,
        "errors": _cap(list(dict.fromkeys(errors))),
    }


def _unquote(value: str) -> str:
    """`"text"` -> `text` when the value is a single string; anything else stays as printed."""
    return value[1:-1] if _SINGLE_STRING.match(value) else value


def _cap(lines: list[str]) -> list[str]:
    if len(lines) <= MAX_LINES:
        return lines
    return [*lines[:MAX_LINES], f"... {len(lines) - MAX_LINES} more lines"]


def _run(cmd: list[str], scad: Path, timeout_s: float) -> dict[str, Any]:
    # Running from the file's directory keeps paths in messages short and relative includes working.
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=scad.parent,
            env={**os.environ, "OPENSCADPATH": str(STANDARD_DIR)},
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout_s,
        )
        log, returncode, timed_out = proc.stdout + proc.stderr, proc.returncode, False
    except subprocess.TimeoutExpired as exc:
        log = "".join(
            s.decode(errors="replace") if isinstance(s, bytes) else s
            for s in (exc.stdout or "", exc.stderr or "")
        )
        returncode, timed_out = None, True
    return {
        "log": log,
        "returncode": returncode,
        "timed_out": timed_out,
        "seconds": round(time.perf_counter() - t0, 3),
    }


def _timing(run: dict[str, Any]) -> dict[str, Any]:
    return {k: run[k] for k in ("seconds", "returncode", "timed_out")}
