"""verify: the checks behind the gates, run by the orchestrator on the current source.

The orchestrator never trusts the agent's own tool results to close a session: it compiles the
source as is, exports every printable part with the default parameters and analyzes each one.
With `assembly`, it also measures the assembly (cadcheck.assembly): when the selector has an
"assembly" option, or when there are two printable parts or more and so there must be one.
`requirements` are the request's own demands on the assembly, such as {"units": 2}.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from cadverify.cadcheck.printability import printability_report
from cadverify.cadcheck.scad import ASSEMBLY, PART, scad_compile, scad_export
from cadverify.scad_source import customizer_options


def printable_parts(source: str) -> list[str | None]:
    """The options of the `part` selector except the assembly, or [None] without a selector."""
    return [p for p in customizer_options(source, PART) if p != ASSEMBLY] or [None]


def verify(
    path: str | Path,
    out_dir: str | Path | None = None,
    assembly: bool = False,
    requirements: dict[str, Any] | None = None,
) -> dict[str, Any]:
    path = Path(path).resolve()
    out_dir = Path(out_dir) if out_dir else path.parent / "checks" / "exports"
    compiled = scad_compile(path)
    source = path.read_text(encoding="utf-8")
    parts = []
    for part in printable_parts(source):
        export = scad_export(path, part, out_dir=out_dir)
        printability = None
        if export["ok"] and export["mesh"] and export["mesh"]["triangles"]:
            allowed = (export["spec"] or {}).get("overhangs_allowed", [])
            printability = printability_report(export["path"], allowed)
        parts.append({"part": part, "export": export, "printability": printability})
    result: dict[str, Any] = {"compile": compiled, "parts": parts}
    if not assembly:
        return result
    printable = [p for p in parts if p["part"] is not None]
    has_assembly = ASSEMBLY in customizer_options(source, PART)
    if not has_assembly and len(printable) < 2:
        result["assembly"] = {"ok": True, "not_needed": True}
        return result
    if not has_assembly:
        result["assembly"] = {"ok": False, "missing": True}
        return result
    from cadverify.cadcheck.assembly import assembly_report

    exported = {
        p["part"]: {"path": p["export"]["path"], "spec": p["export"]["spec"]}
        for p in printable
        if p["export"]["ok"]
    }
    result["assembly"] = assembly_report(path, Path(out_dir) / "assembly", exported, requirements)
    return result
