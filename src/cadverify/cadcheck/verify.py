"""verify: the checks behind the gates, run by the orchestrator on the current source.

The orchestrator never trusts the agent's own tool results to close a session: it compiles the
source as is, exports every printable part with the default parameters and analyzes each one.
With `assembly`, it also measures the assembly (cadcheck.assembly): when the selector has an
"assembly" option, or when there are two printable parts or more and so there must be one.
`requirements` are the request's own demands on the assembly, such as {"units": 2}. With it too,
the behaviour every spec declares (cadcheck.behaviour, G6): a failure there is a red gate with its
reason, never a green one; and a declared family, all of it again at each value.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from cadverify.cadcheck.printability import printability_report
from cadverify.cadcheck.scad import ASSEMBLY, PART, scad_compile, scad_export
from cadverify.scad_source import customizer_options

# Of the orchestrator's VERIFY_TIMEOUT_S (agent/sandbox.py): G6 and the family take what the rest
# left, so the verification comes back with its other gates even when they run out of time.
TOTAL_BUDGET_S = 1740.0
BEHAVIOUR_MIN_S, BEHAVIOUR_MAX_S = 60.0, 600.0  # of CPU
HANG_FACTOR = 2.5  # the clock that says it hung, over its CPU seconds
PROBE_PREFIX = "test_"
PROBE_SCALE = 0.20  # a probe this far off the real part's stiffness or strain does not stand for it
TUNE_MOVED = 0.02  # a measurement that moved less than this was not moved


def printable_parts(source: str) -> list[str | None]:
    """The options of the `part` selector except the assembly, or [None] without a selector."""
    return [p for p in customizer_options(source, PART) if p != ASSEMBLY] or [None]


def is_probe(part: str | None) -> bool:
    """A test print: made by the same code and checked as a part, and not part of the product."""
    return bool(part) and part.startswith(PROBE_PREFIX)


def verify(
    path: str | Path,
    out_dir: str | Path | None = None,
    assembly: bool = False,
    requirements: dict[str, Any] | None = None,
    default_material: str | None = None,
    embed: bool = True,
    _family: bool = True,
) -> dict[str, Any]:
    started = time.perf_counter()
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
        entry = {"part": part, "export": export, "printability": printability}
        if assembly and printability is not None:
            spec = export["spec"] or {}
            material = spec.get("material") or default_material
            entry["slice"] = slice_of(export["path"], Path(out_dir) / "slices", material)
        parts.append(entry)
    result: dict[str, Any] = {"compile": compiled, "parts": parts}
    if not assembly:
        return result
    printable = [p for p in parts if p["part"] is not None and not is_probe(p["part"])]
    has_assembly = ASSEMBLY in customizer_options(source, PART)
    if not has_assembly and len(printable) < 2:
        result["assembly"] = {"ok": True, "not_needed": True}
    elif not has_assembly:
        result["assembly"] = {"ok": False, "missing": True}
    else:
        from cadverify.cadcheck.assembly import assembly_report

        exported = {
            p["part"]: {"path": p["export"]["path"], "spec": p["export"]["spec"]}
            for p in printable
            if p["export"]["ok"]
        }
        result["assembly"] = assembly_report(
            path, Path(out_dir) / "assembly", exported, requirements
        )
    left = max(BEHAVIOUR_MIN_S, TOTAL_BUDGET_S - (time.perf_counter() - started))
    result["behaviour"] = behaviour_of(
        result, Path(out_dir) / "behaviour", default_material, embed, min(left, BEHAVIOUR_MAX_S)
    )
    result["probes"] = probes_of(result)
    if _family:
        tune = declared_tune(result)
        if tune:
            result["tune"] = tune_report(
                path, source, tune, result, Path(out_dir) / "tune", requirements, default_material
            )
        declared = declared_family(result)
        if declared:
            result["family"] = family_report(
                path,
                source,
                declared,
                result,
                Path(out_dir) / "family",
                requirements,
                default_material,
                started,
            )
    return result


def probes_of(result: dict[str, Any]) -> list[dict[str, Any]]:
    """Each probe against the flex it stands for: stiffness and strain per mm of deflection. A probe
    has a single load of its own; what it says about the real part is only as good as these two
    ratios, so they go to the close (agent/physical.py)."""
    behaviour = result.get("behaviour") or {}
    out = []
    for part in result["parts"]:
        spec = part["export"].get("spec") or {}
        if not is_probe(part["part"]):
            continue
        of = spec.get("probe_of")
        row: dict[str, Any] = {"part": part["part"], "of": of, "slice": part.get("slice")}
        out.append(row)
        if not of:
            row["error"] = 'it does not say what it stands for: ["probe_of", "flex a/b"]'
            continue
        flex = next(
            (
                f
                for f in behaviour.get("flex") or []
                if f"flex {f['a']}/{f['b']}" == of and f.get("parts")
            ),
            None,
        )
        load = next(
            (x for x in behaviour.get("loads") or [] if x.get("on") == part["part"]),
            None,
        )
        if flex is None or load is None or "compliance_mm_per_n" not in load:
            row["error"] = f"it needs a load of its own, and {of} computed, to be compared"
            continue
        real = max(flex["parts"], key=lambda p: p["compliance_mm_per_n"])
        stiffness = real["compliance_mm_per_n"] / load["compliance_mm_per_n"]
        per_mm_real = real["strain_pct"] / max(real["deflection_mm"], 1e-9)
        per_mm_probe = load["strain_pct"] / max(load["deflection_mm"], 1e-9)
        strain = per_mm_probe / max(per_mm_real, 1e-9)
        row.update(stiffness_vs_real=round(stiffness, 2), strain_vs_real=round(strain, 2))
        row["represents"] = abs(stiffness - 1) <= PROBE_SCALE and abs(strain - 1) <= PROBE_SCALE
        if not row["represents"]:
            row["why"] = (
                f"it is {stiffness:.2f} times as stiff and reaches {strain:.2f} times the strain "
                "per mm, so a force felt on it does not scale to the real part"
            )
    return out


def declared_tune(result: dict[str, Any]) -> list[dict[str, Any]]:
    specs = [(result.get("assembly") or {}).get("spec") or {}]
    specs += [p["export"].get("spec") or {} for p in result["parts"]]
    return [item for spec in specs for item in spec.get("tune") or []]


def _measure(behaviour: dict[str, Any], name: str) -> float | None:
    """The number a tune entry says it moves: a flex's force, a load's peak strain."""
    kind, _, rest = name.partition(" ")
    if kind == "flex":
        for flex in behaviour.get("flex") or []:
            if f"{flex['a']}/{flex['b']}" == rest:
                return flex.get("force_n")
    for load in behaviour.get("loads") or []:
        if load["name"] == rest:
            return load.get("strain_pct")
    return None


def tune_report(
    path: Path,
    source: str,
    declared: list[dict[str, Any]],
    base: dict[str, Any],
    out_dir: Path,
    requirements: dict[str, Any] | None,
    default_material: str | None,
) -> dict[str, Any]:
    """Each parameter the close will name, moved: it exists, and what it says it moves moves. Only
    on a version green in the behaviour: until then, nothing is left to tune."""
    if (base.get("behaviour") or {}).get("problems"):
        return {"skipped": "the default version is red in the behaviour", "rows": declared}
    rows = []
    for item in declared:
        row = dict(item)
        rows.append(row)
        changed = with_parameter(source, item["param"], item["value"])
        if changed is None:
            row.update(ok=False, why="it is not a top-level parameter of the source")
            continue
        before = _measure(base.get("behaviour") or {}, item["measure"])
        at = _at_value(
            path,
            changed,
            {"param": item["param"]},
            item["value"],
            out_dir,
            requirements,
            default_material,
        )
        after = _measure(at.get("behaviour") or {}, item["measure"])
        row.update(before=before, after=after)
        if before is None or after is None:
            row.update(ok=False, why=f"{item['measure']} could not be measured at both values")
            continue
        moved = abs(after - before) / max(abs(before), 1e-9)
        row.update(moved=round(moved, 3), ok=moved >= TUNE_MOVED)
        if not row["ok"]:
            row["why"] = f"{item['measure']} went from {before} to {after}, which is nothing"
    return {"rows": rows}


def slice_of(stl: str, out_dir: Path, material: str | None) -> dict[str, Any]:
    """The slicer on a part; what goes wrong in it is a red gate, not a verification lost."""
    from cadverify.cadcheck.slicer import slice_report

    try:
        return slice_report(stl, out_dir, material)
    except Exception as exc:
        return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}


def declared_family(result: dict[str, Any]) -> list[dict[str, Any]]:
    """The family the specs declare: each parameter once, the assembly's first."""
    specs = [(result.get("assembly") or {}).get("spec") or {}]
    specs += [p["export"].get("spec") or {} for p in result["parts"]]
    out: dict[str, dict[str, Any]] = {}
    for spec in specs:
        for item in spec.get("family") or []:
            out.setdefault(item["param"], item)
    return list(out.values())


def family_report(
    path: Path,
    source: str,
    declared: list[dict[str, Any]],
    base: dict[str, Any],
    out_dir: Path,
    requirements: dict[str, Any] | None,
    default_material: str | None,
    started: float,
) -> dict[str, Any]:
    """The verification again at each value of the family, on a copy of the source with its
    parameter's default changed. G1 to G6 are judged there as at the default (agent/gates.py), and
    how each force goes along the range is the curve of the replay. Not computed while the default
    version is red in the geometry or the behaviour, since each value costs what the default did:
    the model hears about the default first, and the gate is red either way."""
    report: dict[str, Any] = {"sweeps": [], "problems": []}
    red = (base.get("behaviour") or {}).get("problems") or []
    for gate in ("G3", "G4"):
        red = red or ((base.get("assembly") or {}).get("problems") or {}).get(gate) or []
    if red:
        report["skipped"] = "the default version is red in the geometry or the behaviour"
        return report
    for item in declared:
        rows = []
        for value in item["values"]:
            left = TOTAL_BUDGET_S - (time.perf_counter() - started)
            if left < BEHAVIOUR_MIN_S:
                rows.append({"value": value, "out_of_time": True})
                continue
            changed = with_parameter(source, item["param"], value)
            if changed is None:
                report["problems"].append(
                    f"family: {item['param']} is not a top-level parameter of the source "
                    f"({item['param']} = ...;), so it cannot be moved"
                )
                rows = []
                break
            at_value = _at_value(
                path, changed, item, value, out_dir, requirements, default_material
            )
            rows.append({"value": value, **at_value})
        report["sweeps"].append({"param": item["param"], "values": item["values"], "rows": rows})
    return report


def with_parameter(source: str, param: str, value: Any) -> str | None:
    """The source with the first top-level assignment of `param` set to `value`."""
    pattern = re.compile(rf"^([ \t]*{re.escape(param)}[ \t]*=[ \t]*)[^;\n]+;", re.M)
    if not pattern.search(source):
        return None
    text = json.dumps(value)
    return pattern.sub(lambda m: f"{m.group(1)}{text};", source, count=1)


def _at_value(
    path: Path,
    changed: str,
    item: dict[str, Any],
    value: Any,
    out_dir: Path,
    requirements: dict[str, Any] | None,
    default_material: str | None,
) -> dict[str, Any]:
    """One value: next to the source, so what it includes is found; never left behind."""
    tag = hashlib.sha256(f"{item['param']}={value}".encode()).hexdigest()[:8]
    copy = path.with_name(f"family-{tag}.scad")
    copy.write_text(changed, encoding="utf-8")
    try:
        return verify(
            copy,
            out_dir / tag,
            assembly=True,
            requirements=requirements,
            default_material=default_material,
            embed=False,
            _family=False,
        )
    except Exception as exc:  # a value that breaks the harness is a red value, not a lost run
        return {"error": f"{type(exc).__name__}: {exc}"}
    finally:
        copy.unlink(missing_ok=True)


def behaviour_of(
    result: dict[str, Any],
    out_dir: Path,
    default_material: str | None,
    embed: bool,
    limit_s: float,
    compute: str = "cadverify.cadcheck.behaviour:behaviour_report",
) -> dict[str, Any]:
    """G6 of a verification, in a process of its own with a hard limit (cadcheck.behaviour_run): a
    mesher or a solver that does not come back, or runs out of memory, leaves the gate red with the
    reason and what was computed until then, and the rest of the verification stands."""
    out_dir.mkdir(parents=True, exist_ok=True)
    saved = out_dir / "report.json"
    saved.unlink(missing_ok=True)
    arguments = out_dir / "arguments.json"
    arguments.write_text(
        json.dumps(
            {
                "compute": compute,
                "assembly": result.get("assembly"),
                "parts": result["parts"],
                "out_dir": str(out_dir),
                "default_material": default_material,
                "time_budget_s": limit_s,
                "embed": embed,
                "save": str(saved),
            },
            default=_plain,
        ),
        encoding="utf-8",
    )
    command = [sys.executable, "-m", "cadverify.cadcheck.behaviour_run", str(arguments)]
    child = subprocess.Popen(command, stdout=subprocess.DEVNULL)
    late = _wait_within(child, limit_s, HANG_FACTOR * limit_s)
    if late:
        child.kill()
        child.wait()
    arguments.unlink(missing_ok=True)
    report = json.loads(saved.read_text(encoding="utf-8")) if saved.exists() else _red_report()
    if late:
        report["ok"] = False
        report["problems"].append(
            f"the behaviour ran over its {limit_s:.0f} s of CPU, or hung: not all computed"
        )
    elif child.returncode != 0 or "seconds" not in report:
        report["ok"] = False
        report["problems"].append(f"the behaviour computation died (exit {child.returncode})")
    return report


def _plain(value: Any) -> Any:
    return value.tolist() if hasattr(value, "tolist") else str(value)


def _wait_within(child: subprocess.Popen, cpu_s: float, wall_s: float) -> bool:
    """Waits for a process; True when it used up its CPU seconds, or the clock when it hangs. The
    limit is in CPU so that a busy machine does not turn into a red gate."""
    started = time.perf_counter()
    while True:
        try:
            child.wait(1.0)
            return False
        except subprocess.TimeoutExpired:
            pass
        if _cpu_of(child.pid) > cpu_s or time.perf_counter() - started > wall_s:
            return True


def _cpu_of(pid: int) -> float:
    """The CPU seconds of a process, its threads and the children it waited for, from /proc."""
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    except OSError:
        return 0.0
    return sum(int(fields[i]) for i in (11, 12, 13, 14)) / os.sysconf("SC_CLK_TCK")


def _red_report(saved: Path | None = None, problem: str | None = None) -> dict[str, Any]:
    report = {
        "ok": False,
        "declared": True,
        "problems": [problem] if problem else [],
        "flex": [],
        "loads": [],
        "stability": [],
    }
    if saved is not None:
        report["seconds"] = 0.0
        saved.write_text(json.dumps(report), encoding="utf-8")
    return report
