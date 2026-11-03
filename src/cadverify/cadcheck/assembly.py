"""assembly_report: the parts of an assembly measured where the assembly places them.

The assembly (`part = "assembly"`) places each part through a module the prompt gives the model:

    cadverify_only = "";
    module instance(name, part, unit = 1) {
        echo(cadverify_instance = [name, part, unit]);
        if (cadverify_only == "" || cadverify_only == name) children();
    }

so the list of instances comes from the code, and `-D cadverify_only="<name>"` exports one
instance alone, in assembly coordinates. A name no instance has exports what the assembly draws
outside instance(): it must be nothing. `part` is the printable part the instance is,
"external" for what is not printed (a wall, a screw, a rope), or "standard:<module>" for a part
of standard/cadverify_parts.scad, which is checked like a printed part against the module itself.

What is measured (G3, assembly):
- each instance is its printable part moved, not a variant of it: the same volume, area and
  principal moments of inertia (a mirror image passes: the moments do not tell it apart);
- every printable part is in unit 1, as many times as its spec's `copies`;
- no two instances overlap: an overlap counts when it is more than 0.01 mm³ and more than
  0.02 mm thick on average (2·V/A of the overlap: a disc resting in a round seat overlapped
  0.36 mm³ that were 0.0075 mm thick, the faceting of two circles). A press fit is declared in
  `allowed_interferences`, up to 0.3 mm thick;
- the instances touch each other (1 mm or less apart, manifold3d's min_gap) as one group;
- printed in place (`print_in_place`), each printed part is held by the others, and so is each
  instance `held` lists (a lid that does not lift off): it comes off moving straight along none
  of 26 directions (the faces, edges and corners of a cube), each checked whole with the depth
  maps of the assembly order below. A pivot in an open groove, a pin that slides out of its
  knuckles, a ring that lifts out of its frame: each comes off the bed loose, not assembled;
- with `requirements["units"] = n`, units 1 to n are there and each one touches the one before;
- the assembly's own `bounds` and `support_faces`, if its spec declares them, on its instances
  together.

And G4, motion:
- each `motions` entry sweeps its instances through the whole range (from 0, the assembled
  pose), at most 0.25 mm of travel or 2° per step, measuring the overlap at each step between
  every two instances that move against each other. A `screw` turns and advances its pitch for
  each turn; the instances a motion `drives` turn or slide at their ratio, each group about its
  own axis (carried by the motion too, when it names them: a planet on its carrier). The
  parts are rigid: an elastic feature (a detent bump, a snap) is declared in the motion's
  `flex`, a pair of instances and how deep they may overlap. A motion that moves every instance
  moves nothing against anything, and is refused. There, an overlap is a flex and
  not a collision when it is no deeper than declared (the farthest a vertex of the overlap is
  from the surface of the other solid) and the parts are free at both ends of the range: a
  feature that stays deflected at rest is a press fit (allowed_interferences), and a flex that
  never overlaps bends nothing and is refused. The bayonet jar
  of the demo had to trade its detent bump for a pocket before this existed. At each end the
  motion `stops` at, moving on until its fastest point has gone 2 mm more, two instances collide
  (deeper than their flex, for a flex pair): a drawer that does not come out, the way a ratchet
  does not turn (the poses of a sweep are the same both ways; only its ends tell them apart). At
  each value it `rests` at, its flex pairs do not overlap (a detent in its notch), and between
  two rests they do: it clicks from one to the next;
- `assembly_order` lists every instance once, in order: the first step places one (an assembly
  printed in place may start with all it prints), and each next step's instances arrive from far
  away moving along its direction (and then turn or screw in, if the step says so) without crossing
  what the steps before placed. The straight approach is checked whole with two depth maps along the
  direction (the farthest point of the moving parts against the nearest of the placed ones, on a
  grid of 0.05 mm or finer than 1/3000 of the size); the turn, by steps like a movement. A step
  that declares a `flex` (what snaps in as it comes in) comes in by steps instead against what it
  flexes on, from where their bounding boxes no longer meet, with a motion's flex rule;

A pair that presses together in place (allowed_interferences) is swept like any other, as a
press fit: along a motion or a turn, its overlaps no thicker than a fit are not collisions, and on
its way in, in each column along the direction, the first of the other part that a part meets
must be their overlap in place. A lid pressed onto its box still has to come in from above, not
through the floor.

And G5, for an assembly that declares `print_in_place` (printed whole, all its parts at once):
the instances of unit 1 that are printed, together as they print (+z up, the lowest faces on the
bed), go through the printability of a part with the assembly's `overhangs_allowed`
(gates.print_problems judges it), and every two of them are at least the declared clearance
apart: closer, or a press fit, and they print fused. They print in the assembly pose, or in the
`print_pose`: each of its motions at its value, applied in order to the instances it moves; the
clearances are measured again in that pose, and an overlap there is a G5 problem. The parts as
they print are left as print-in-place.stl.
"""

from __future__ import annotations

import hashlib
import itertools
import math
import re
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import manifold3d
import numpy as np
import trimesh
from scipy.ndimage import binary_erosion
from scipy.spatial import cKDTree

from cadverify.cadcheck import section
from cadverify.cadcheck.mesh import load_exact
from cadverify.cadcheck.printability import mesh_printability
from cadverify.cadcheck.scad import ASSEMBLY, STANDARD_DIR, scad_export

SOLO = "cadverify_only"
OUTSIDE = "__outside_instances__"
EXTERNAL = "external"
STANDARD = "standard:"  # a part of cadverify_parts.scad, `standard:<module>`
OVERLAP_MM3 = 0.01
OVERLAP_THICKNESS_MM = 0.02
PERMITTED_THICKNESS_MM = 0.3
CONTACT_MM = 1.0
CONGRUENCE_REL = 1e-3  # volume and area
INERTIA_REL = 2e-3  # of the largest principal moment
SWEEP_STEP_MM = 0.25
SWEEP_STEP_DEG = 2.0
SWEEP_MAX_STEPS = 360
STOP_TRAVEL_MM = 2.0  # past a stop, how far the fastest point moves looking for what stops it
DEPTH_PX_MM = 0.05
DEPTH_MAX_SIDE = 3000
DEPTH_EPS_MM = 0.02
EXPORT_WORKERS = 2  # the sandbox has 2 CPUs
FLEX_SAMPLE_MM = 0.5  # the triangles of the overlap whose centers measure a flex's depth
FLEX_TOLERANCE_MM = 0.05  # how far past its declared depth a flex is not refused
FLEX_MAX_TRIANGLES = 20_000
FLEX_ROUNDS = 8  # splits of the triangles that might pass the declared depth
AXES = {
    "+x": (1, 0, 0),
    "-x": (-1, 0, 0),
    "+y": (0, 1, 0),
    "-y": (0, -1, 0),
    "+z": (0, 0, 1),
    "-z": (0, 0, -1),
}
# The 26 directions a part may come off along: the axes first, then the edges and corners.
_CUBE = [v for v in itertools.product((-1, 0, 1), repeat=3) if sum(map(abs, v)) > 1]
DIRECTIONS = {
    **{name: np.array(v, float) for name, v in AXES.items()},
    **{
        "".join(f"{'+' if c > 0 else '-'}{a}" for a, c in zip("xyz", v, strict=True) if c): (
            np.array(v) / np.linalg.norm(v)
        )
        for v in _CUBE
    },
}
MAX_LISTED = 12


def assembly_report(
    path: str | Path,
    out_dir: str | Path,
    parts: dict[str, dict[str, Any]] | None = None,
    requirements: dict[str, Any] | None = None,
    timeout_s: float = 300,
) -> dict[str, Any]:
    """Every check of the module docstring. `parts` maps each printable part to its export
    ({"path", "spec"}, as verify made it); without it, the parts are exported here."""
    t0 = time.perf_counter()
    path = Path(path).resolve()
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    requirements = requirements or {}
    g3: list[str] = []
    g4: list[str] = []
    g5: list[str] = []
    report: dict[str, Any] = {"ok": False, "problems": {"G3": g3, "G4": g4, "G5": g5}}

    outside = scad_export(path, ASSEMBLY, {SOLO: OUTSIDE}, out_dir=out_dir, timeout_s=timeout_s)
    report["errors"] = outside.get("errors", []) + [
        f"failed assert {a['condition']}: {a['message']}" for a in outside.get("asserts_failed", [])
    ]
    report["spec"], report["spec_error"] = outside.get("spec"), outside.get("spec_error")
    if report["errors"] or outside.get("timed_out"):
        g3.append("the assembly could not be evaluated: " + "; ".join(report["errors"][:3]))
        return _done(report, t0)
    if outside.get("instance_error"):
        g3.append(outside["instance_error"])
        return _done(report, t0)
    listed = outside.get("instances")
    if not listed:
        g3.append(
            "the assembly does not place its parts with instance(name, part, unit): the harness "
            "cannot take them apart to measure them"
        )
        return _done(report, t0)
    if outside["ok"]:
        where = outside["mesh"]["bounds"] if outside.get("mesh") else None
        report["outside_geometry"] = where or True
        g3.append(
            f"the assembly draws geometry outside instance() (bounds {where}): every part of "
            "the assembly goes inside an instance"
        )
    if report["spec_error"]:
        g3.append(f"invalid assembly spec: {report['spec_error']}")
    spec = report["spec"] or {}

    if parts is None:
        parts = _export_parts(path, out_dir, timeout_s)
    instances = _export_instances(path, out_dir, listed, timeout_s)
    for inst in instances:
        if inst.get("problem"):
            g3.append(inst["problem"])
    good = [i for i in instances if i.get("_solid") is not None]

    _congruence(good, parts, out_dir, g3)
    report["instances"] = [{k: v for k, v in i.items() if not k.startswith("_")} for i in instances]
    report["copies"] = _copies(instances, parts, g3)
    permitted = _permitted(spec, {i["name"] for i in instances}, g3)
    report["pairs"] = _pairs(good, permitted, out_dir, g3)
    report["components"] = _components(good, report["pairs"], g3)
    report["units"] = _units(instances, report["pairs"], int(requirements.get("units", 1)), g3)
    report["spec_check"] = _own_spec(good, spec, g3)
    if spec.get("print_in_place") or spec.get("held"):
        report["held"] = _held(good, spec.get("held") or [], bool(spec.get("print_in_place")), g3)

    names = {i["name"]: i for i in good}
    # Pairs left out of the motion checks: the overlaps G3 already reports (they would collide
    # at every pose and in every direction). The permitted press fits stay in, as press fits.
    skip = {frozenset((p["a"], p["b"])) for p in report["pairs"] if p.get("interference")}
    pressed = {frozenset((p["a"], p["b"])) for p in report["pairs"] if p.get("permitted")}
    motions = spec.get("motions", [])
    report["motions"] = [_motion(m, names, skip, pressed, out_dir, g4) for m in motions]
    steps = spec.get("assembly_order", [])
    before = len(g4)
    report["assembly_steps"] = _assembly_order(
        steps, instances, names, skip, pressed, bool(spec.get("print_in_place")), out_dir, g4
    )
    report["assembly_order_ok"] = len(g4) == before
    if spec.get("print_in_place"):
        report["print_in_place"] = _print_in_place(
            good, spec, report["pairs"], permitted, out_dir, g5
        )
    return _done(report, t0)


def _done(report: dict[str, Any], t0: float) -> dict[str, Any]:
    report["ok"] = not any(report["problems"].values())
    report["seconds"] = round(time.perf_counter() - t0, 2)
    return report


# ---- exports ------------------------------------------------------------------------------


def _export_parts(path: Path, out_dir: Path, timeout_s: float) -> dict[str, dict[str, Any]]:
    from cadverify.cadcheck.verify import printable_parts

    out = {}
    for part in printable_parts(path.read_text(encoding="utf-8")):
        if part is None:
            continue
        export = scad_export(path, part, out_dir=out_dir, timeout_s=timeout_s)
        if export["ok"]:
            out[part] = {"path": export["path"], "spec": export.get("spec")}
    return out


def _export_instances(path: Path, out_dir: Path, listed: list[dict], timeout_s: float) -> list:
    def one(item: dict[str, Any]) -> dict[str, Any]:
        export = scad_export(
            path, ASSEMBLY, {SOLO: item["name"]}, out_dir=out_dir, timeout_s=timeout_s
        )
        inst: dict[str, Any] = {**item, "stl": export.get("path"), "sha256": export.get("sha256")}
        if not export["ok"]:
            reason = "has no geometry" if export.get("empty") else "could not be exported"
            inst["problem"] = (
                f"the instance {item['name']} {reason} (is it inside another instance, or "
                "outside the assembly with the default parameters?)"
            )
            return inst
        mesh = load_exact(export["path"])
        solid = section.to_manifold(mesh)
        inst.update(
            volume_mm3=round(float(mesh.volume), 3),
            bounds=_r(mesh.bounds),
            _mesh=mesh,
            _solid=solid,
        )
        if solid is None:
            inst["problem"] = f"the instance {item['name']} is not a closed, oriented solid"
        return inst

    with ThreadPoolExecutor(EXPORT_WORKERS) as pool:
        return list(pool.map(one, listed))


# ---- G3 -----------------------------------------------------------------------------------


def _printed(inst: dict) -> bool:
    """Whether an instance is a part that is printed: not external, not a standard part."""
    return inst["part"] != EXTERNAL and not inst["part"].startswith(STANDARD)


def _properties(mesh: trimesh.Trimesh) -> tuple[float, float, np.ndarray]:
    inertia = np.linalg.eigvalsh(mesh.moment_inertia)
    return float(mesh.volume), float(mesh.area), np.sort(inertia)


def _congruence(
    instances: list[dict], parts: dict[str, dict], out_dir: Path, problems: list[str]
) -> None:
    cache: dict[str, tuple | None] = {}
    for inst in instances:
        part = inst["part"]
        if part.startswith(STANDARD) and part not in cache:
            cache[part] = _standard(part.removeprefix(STANDARD), out_dir, problems)
        elif part in parts and part not in cache:
            cache[part] = _properties(load_exact(parts[part]["path"]))
        if cache.get(part) is None:
            inst["congruent"] = None
            continue
        volume, area, inertia = cache[part]
        v, a, i = _properties(inst["_mesh"])
        dv, da = abs(v - volume) / max(volume, 1e-9), abs(a - area) / max(area, 1e-9)
        di = float(np.max(np.abs(i - inertia)) / max(float(inertia.max()), 1e-9))
        ok = dv <= CONGRUENCE_REL and da <= CONGRUENCE_REL and di <= INERTIA_REL
        inst["congruent"] = ok
        inst["congruence"] = {
            "volume_mm3": [round(v, 2), round(volume, 2)],
            "area_mm2": [round(a, 2), round(area, 2)],
            "inertia_rel_diff": round(di, 5),
        }
        if not ok and part.startswith(STANDARD):
            problems.append(
                f"the instance {inst['name']} is not the standard part "
                f"{part.removeprefix(STANDARD)}() of cadverify_parts.scad: volume {v:.1f} against "
                f"{volume:.1f} mm³, area {a:.1f} against {area:.1f} mm² (place the module "
                "itself, moved: the design has to fit the real part)"
            )
        elif not ok:
            problems.append(
                f"the instance {inst['name']} is not the part {part} that is printed: volume "
                f"{v:.1f} against {volume:.1f} mm³, area {a:.1f} against {area:.1f} mm² (the "
                "assembly must place the same part, moved)"
            )


def _standard(name: str, out_dir: Path, problems: list[str]) -> tuple | None:
    """The volume, area and principal moments of a module of cadverify_parts.scad."""
    modules = re.findall(
        r"^module (\w+)\(\)", (STANDARD_DIR / "cadverify_parts.scad").read_text(), re.M
    )
    if name not in modules:
        problems.append(
            f"there is no standard part {name!r}: cadverify_parts.scad has {sorted(modules)}"
        )
        return None
    source = out_dir / f"standard-{name}.scad"
    source.write_text(f"use <cadverify_parts.scad>\n{name}();\n")
    export = scad_export(source, out_dir=out_dir)
    if not export["ok"]:
        problems.append(f"the standard part {name} could not be exported")
        return None
    return _properties(load_exact(export["path"]))


def _copies(instances: list[dict], parts: dict[str, dict], problems: list[str]) -> list[dict]:
    for inst in instances:
        if _printed(inst) and inst["part"] not in parts:
            problems.append(
                f"the instance {inst['name']} says it is the part {inst['part']!r}, which is "
                f"neither a printable option of the part selector ({sorted(parts)}), "
                f"{EXTERNAL!r} nor a {STANDARD}<module> of cadverify_parts.scad"
            )
    rows = []
    for part, export in sorted(parts.items()):
        expected = int(((export.get("spec") or {}).get("copies")) or 1)
        placed = sum(1 for i in instances if i["part"] == part and i["unit"] == 1)
        rows.append(
            {"part": part, "expected": expected, "placed": placed, "ok": placed == expected}
        )
        if placed == 0:
            problems.append(f"the part {part} is not in the assembly (unit 1)")
        elif placed != expected:
            problems.append(f"unit 1 places {placed} {part} and its spec says copies = {expected}")
    return rows


def _permitted(spec: dict[str, Any], names: set[str], problems: list[str]) -> dict:
    out = {}
    for item in spec.get("allowed_interferences", []):
        unknown = [n for n in (item["a"], item["b"]) if n not in names]
        if unknown:
            problems.append(f"allowed_interferences names instances that do not exist: {unknown}")
        out[frozenset((item["a"], item["b"]))] = item["reason"]
    return out


def overlap(a: manifold3d.Manifold, b: manifold3d.Manifold) -> dict[str, Any] | None:
    """The overlap of two solids when it counts (module docstring), else None."""
    inter = a ^ b
    volume = inter.volume()
    if volume <= OVERLAP_MM3:
        return None
    area = inter.surface_area()
    thick = 2 * volume / area if area > 0 else 0.0
    if thick <= OVERLAP_THICKNESS_MM:
        return None
    lo, hi = np.reshape(inter.bounding_box(), (2, 3))
    return {
        "volume_mm3": round(volume, 3),
        "thickness_mm": round(thick, 3),
        "bounds": _r([lo, hi]),
        "_solid": inter,
    }


def _pairs(instances: list[dict], permitted: dict, out_dir: Path, problems: list[str]) -> list:
    rows = []
    boxes = {i["name"]: np.reshape(i["_solid"].bounding_box(), (2, 3)) for i in instances}
    for a, b in itertools.combinations(instances, 2):
        if _box_gap(boxes[a["name"]], boxes[b["name"]]) > CONTACT_MM:
            continue
        key = frozenset((a["name"], b["name"]))
        hit = overlap(a["_solid"], b["_solid"])
        gap = 0.0 if hit else float(a["_solid"].min_gap(b["_solid"], CONTACT_MM * 1.01))
        row: dict[str, Any] = {
            "a": a["name"],
            "b": b["name"],
            "gap_mm": round(gap, 3),
            "contact": gap <= CONTACT_MM,
        }
        if hit:
            row.update({k: v for k, v in hit.items() if not k.startswith("_")})
            stl = out_dir / f"overlap-{_slug(a['name'])}-{_slug(b['name'])}.stl"
            _write_stl(hit["_solid"], stl)
            row["stl"] = str(stl)
            reason = permitted.get(key)
            if reason is not None and hit["thickness_mm"] <= PERMITTED_THICKNESS_MM:
                row["permitted"] = reason
            else:
                row["interference"] = True
                cap = (
                    f"; declared as {reason!r}, but a fit goes up to "
                    f"{PERMITTED_THICKNESS_MM} mm thick"
                    if reason is not None
                    else ""
                )
                problems.append(
                    f"{a['name']} and {b['name']} overlap {hit['volume_mm3']} mm³, "
                    f"{hit['thickness_mm']} mm thick on average, in {hit['bounds']}{cap}"
                )
        rows.append(row)
    return rows


def _components(instances: list[dict], pairs: list[dict], problems: list[str]) -> list[list[str]]:
    parent = {i["name"]: i["name"] for i in instances}

    def root(n: str) -> str:
        while parent[n] != n:
            parent[n] = parent[parent[n]]
            n = parent[n]
        return n

    for pair in pairs:
        if pair["contact"]:
            parent[root(pair["a"])] = root(pair["b"])
    groups: dict[str, list[str]] = {}
    for name in parent:
        groups.setdefault(root(name), []).append(name)
    components = sorted(groups.values(), key=len, reverse=True)
    if len(components) > 1:
        loose = "; ".join(", ".join(c) for c in components[1:MAX_LISTED])
        problems.append(
            f"the assembly is not one group: {', '.join(components[0])} does not touch {loose} "
            f"(contact: {CONTACT_MM} mm or less)"
        )
    return components


def _units(instances: list[dict], pairs: list[dict], required: int, problems: list[str]) -> dict:
    unit = {i["name"]: i["unit"] for i in instances}
    present = sorted(set(unit.values()))
    links = sorted(
        {
            (min(unit[p["a"]], unit[p["b"]]), max(unit[p["a"]], unit[p["b"]]))
            for p in pairs
            if p["contact"] and unit[p["a"]] != unit[p["b"]]
        }
    )
    for u in range(2, required + 1):
        if u not in present:
            problems.append(
                f"the request chains units and the assembly does not show unit {u}: place with "
                f"instance(..., unit = {u}) the parts of unit {u} that hook onto unit {u - 1}"
            )
        elif (u - 1, u) not in links:
            problems.append(f"no part of unit {u} touches one of unit {u - 1}")
    return {"required": required, "present": present, "links": [list(x) for x in links]}


def _own_spec(instances: list[dict], spec: dict[str, Any], problems: list[str]) -> dict | None:
    """The assembly's bounds and support faces, measured on all its instances together."""
    if not instances or (spec.get("bounds") is None and not spec.get("support_faces")):
        return None
    from cadverify.cadcheck.spec import _check_bounds, support_face

    whole = trimesh.util.concatenate([i["_mesh"] for i in instances])
    check: dict[str, Any] = {}
    if spec.get("bounds") is not None:
        check["measured_bounds"] = _r(whole.bounds)
        check["bounds"] = _check_bounds(check["measured_bounds"], spec["bounds"])
        problems += [f"assembly bounds: {d}" for d in check["bounds"]["deviations"]]
    check["support_faces"] = [support_face(whole, **face) for face in spec["support_faces"]]
    for face in check["support_faces"]:
        if not face["ok"]:
            problems.append(
                f"assembly support face {face['name']} ({face['direction']}): "
                f"{face['area_on_extreme_plane_mm2']} mm² on the extreme plane "
                f"{face['extreme_plane']}, {face['min_area_mm2']} required"
            )
    return check


def _held(
    instances: list[dict], listed: list[str], in_place: bool, problems: list[str]
) -> list[dict]:
    """The directions each instance `held` lists, and each printed part of an assembly printed in
    place, comes off the others along, straight from where it is assembled (module docstring).
    The axes are checked first: a part that comes off along one is not checked along the
    diagonals. Printed in place, a part is held by the other printed parts only."""
    names = {i["name"]: i for i in instances}
    missing = [n for n in listed if n not in names]
    if missing:
        problems.append(f"held: there are no instances {missing}")
    printed = [i for i in instances if _printed(i) and i["unit"] == 1]
    if not in_place or len(printed) < 2:
        printed = []
    checked = printed + [names[n] for n in listed if n in names and names[n] not in printed]
    if not checked:
        return []
    import moderngl

    ctx = moderngl.create_context(standalone=True, backend="egl")
    rows = []
    try:
        for inst in checked:
            pool = printed if inst in printed else instances
            others = [(o["name"], o["_mesh"]) for o in pool if o is not inst]
            free: list[str] = []
            for names in (list(AXES), [n for n in DIRECTIONS if n not in AXES]):
                # Coming off along a direction sweeps what arriving along its opposite does.
                free += [
                    n for n in names if blocked(ctx, [inst["_mesh"]], others, -DIRECTIONS[n])["ok"]
                ]
                if free:
                    break
            rows.append({"instance": inst["name"], "free": free})
            if free and inst in printed:
                problems.append(
                    f"{inst['name']} is not held: printed in place, it comes off the others "
                    f"moving along {', '.join(free)}. An assembly printed in place comes off the "
                    "bed in one piece, each part held by the others (a pin capped at both ends, "
                    "a pivot in a closed bore)"
                )
            elif free:
                problems.append(
                    f"{inst['name']} is not held: assembled, it comes off the others moving along "
                    f"{', '.join(free)}, and held says it stays on (a lip that catches, a cap at "
                    "each end, a bore that closes around it)"
                )
    finally:
        ctx.release()
    return rows


def _print_in_place(
    instances: list[dict],
    spec: dict[str, Any],
    pairs: list[dict],
    permitted: dict,
    out_dir: Path,
    problems: list[str],
) -> dict[str, Any]:
    """G5 of an assembly printed whole, as it stands or in its print pose (module docstring)."""
    need = spec["print_in_place"]["min_gap_mm"]
    printed = [i for i in instances if _printed(i) and i["unit"] == 1]
    names = {i["name"] for i in printed}
    pose = spec.get("print_pose") or []
    if pose:
        printed = _in_print_pose(printed, pose, spec["motions"])
        found: list[str] = []
        posed_dir = out_dir / "print_pose"
        posed_dir.mkdir(parents=True, exist_ok=True)
        pairs = _pairs(printed, permitted, posed_dir, found)
        problems += [f"in the print pose, {p}" for p in found]
    gaps = []
    for pair in pairs:
        if not {pair["a"], pair["b"]} <= names or pair.get("interference"):
            continue  # an overlap G3 reports is not repeated here
        row = {"a": pair["a"], "b": pair["b"], "gap_mm": pair["gap_mm"], "ok": True}
        if pair.get("permitted") is not None:
            row["ok"] = False
            problems.append(
                f"{pair['a']} and {pair['b']} are a press fit ({pair['permitted']}): printed "
                "in place, they print as one piece"
            )
        elif pair["gap_mm"] < need - 1e-6:
            row["ok"] = False
            problems.append(
                f"{pair['a']} and {pair['b']} are {pair['gap_mm']} mm apart: printed in place "
                f"they fuse (print_in_place asks for {need} mm or more)"
            )
        gaps.append(row)
    whole = trimesh.util.concatenate([i["_mesh"] for i in printed]) if printed else None
    report = mesh_printability(whole, spec["overhangs_allowed"]) if whole else None
    stl = None
    if whole:
        stl = out_dir / "print-in-place.stl"
        _write_mesh(whole, stl)
    return {
        "min_gap_mm": need,
        "pose": pose,
        "instances": sorted(names),
        "gaps": gaps,
        "printability": report,
        "stl": str(stl) if stl else None,
    }


def _in_print_pose(printed: list[dict], pose: list[dict], motions: list[dict]) -> list[dict]:
    """The printed instances moved by each motion of the print pose, in order."""
    by_name = {m["name"]: m for m in motions}
    matrix = {i["name"]: np.eye(4) for i in printed}
    for step in pose:
        for name, moved in _poses(by_name[step["motion"]], step["value"]).items():
            if name in matrix:
                matrix[name] = moved @ matrix[name]
    return [
        {
            **i,
            "_mesh": _transformed(i["_mesh"], matrix[i["name"]]),
            "_solid": i["_solid"].transform(matrix[i["name"]][:3, :]),
        }
        for i in printed
    ]


# ---- G4 -----------------------------------------------------------------------------------


def rotation(point, axis, degrees: float) -> np.ndarray:
    """4 × 4 rotation by `degrees` about the axis through `point` (right hand rule)."""
    return trimesh.transformations.rotation_matrix(math.radians(degrees), axis, point)


def translation(direction, mm: float) -> np.ndarray:
    matrix = np.eye(4)
    matrix[:3, 3] = np.asarray(direction, float) * mm
    return matrix


def _sweep(
    pairs: list[tuple[dict, dict]],
    poses: list[tuple[float, dict[str, np.ndarray]]],
) -> list[dict[str, Any]]:
    """The collisions of each pair of instances (the first one moves) at each pose: a 4 × 4
    matrix for each instance that moves; one without stays in place."""
    rest = {}
    for inst in {i["name"]: i for pair in pairs for i in pair}.values():
        rest[inst["name"]] = (inst["_solid"], np.reshape(inst["_solid"].bounding_box(), (2, 3)))
    hits = []
    for pose, matrices in poses:
        placed = dict(rest)
        for name, matrix in matrices.items():
            if name in rest:
                solid = rest[name][0].transform(matrix[:3])
                placed[name] = (solid, np.reshape(solid.bounding_box(), (2, 3)))
        for a, b in pairs:
            (solid, box), (other, other_box) = placed[a["name"]], placed[b["name"]]
            if _box_gap(box, other_box) > 0:
                continue
            hit = overlap(solid, other)
            if hit:
                hits.append(
                    {
                        "pose": round(pose, 3),
                        "moving": a["name"],
                        "with": b["name"],
                        **hit,
                        "_matrices": {
                            n: matrices.get(n, np.eye(4)) for n in (a["name"], b["name"])
                        },
                    }
                )
    return hits


def _motion(
    motion: dict, names: dict, skip: set, pressed: set, out_dir: Path, problems: list[str]
) -> dict:
    row: dict[str, Any] = {"name": motion["name"], "kind": motion["kind"], "range": motion["range"]}
    if motion["kind"] == "screw":
        row["pitch_mm"] = motion["pitch_mm"]
    drives = motion.get("drives") or []
    if drives:
        row["drives"] = [{"instances": d["instances"], "ratio": d["ratio"]} for d in drives]
    driven = [n for d in drives for n in d["instances"]]
    missing = [n for n in dict.fromkeys(motion["instances"] + driven) if n not in names]
    if missing:
        problems.append(f"motion {motion['name']}: there are no instances {missing}")
        return {**row, "ok": False}
    # Instances with the same key move together: by the motion, by one of its drives, or not.
    keys = {
        n: (
            n in motion["instances"],
            next((k for k, d in enumerate(drives) if n in d["instances"]), -1),
        )
        for n in names
    }
    still = (False, -1)
    if len(set(keys.values())) < 2:
        problems.append(
            f"motion {motion['name']}: it moves every instance together, so nothing moves against "
            "anything and the sweep checks nothing: a motion moves some instances against the rest"
        )
        return {**row, "ok": False}
    moving = [names[n] for n in names if keys[n] != still]
    # Every two instances that move against each other, the one that moves (or the motion's) first.
    pairs = [
        (names[a], names[b]) if keys[a] > keys[b] else (names[b], names[a])
        for a, b in itertools.combinations(names, 2)
        if keys[a] != keys[b] and frozenset((a, b)) not in skip
    ]
    lo, hi = min(0.0, motion["range"][0]), max(0.0, motion["range"][1])
    step = _step(motion, names)
    count = min(SWEEP_MAX_STEPS, max(1, math.ceil((hi - lo) / step)))
    values = np.linspace(lo, hi, count + 1)
    poses = [(float(v), _poses(motion, float(v))) for v in values]
    hits = _fits_left_out(_sweep(pairs, poses), pressed)
    unit = " mm" if motion["kind"] == "slide" else "°"
    flexes = motion.get("flex") or []
    bent = {frozenset((f["a"], f["b"])) for f in flexes}
    rides = sorted({h["pose"] for h in hits if frozenset((h["moving"], h["with"])) in bent})
    if flexes:
        row["flex"], hits = _flexes(motion, flexes, hits, names, keys, (lo, hi), out_dir, problems)
    flexed = any(not f["ok"] for f in row.get("flex", []))
    if motion.get("stops"):
        row["stops"] = _stops(motion, pairs, names, pressed, (lo, hi), step, problems)
    stopped = all(s["ok"] for s in row.get("stops", []))
    if motion.get("rests"):
        row["rests"] = _rests(motion, pairs, bent, rides, problems)
    rested = all(r["ok"] for r in row.get("rests", []))
    row.update(
        ok=not hits and not flexed and stopped and rested,
        steps=count + 1,
        step=round((hi - lo) / count, 4),
    )
    if hits:
        worst = max(hits, key=lambda h: h["volume_mm3"])
        first = min(hits, key=lambda h: abs(h["pose"]))
        stl = out_dir / f"motion-{_slug(motion['name'])}-{_slug(str(worst['pose']))}.stl"
        _write_stl(worst["_solid"], stl)
        posed = out_dir / f"motion-{_slug(motion['name'])}-pose.stl"
        _write_mesh(_posed_mesh(moving, _poses(motion, worst["pose"])), posed)
        poses_hit = sorted({h["pose"] for h in hits})
        row["collisions"] = {
            "from_to": [poses_hit[0], poses_hit[-1]],
            "first": _public(first),
            "worst": _public(worst),
            "overlap_stl": str(stl),
            "posed_stl": str(posed),
        }
        problems.append(
            f"motion {motion['name']}: collides between {poses_hit[0]:g}{unit} and "
            f"{poses_hit[-1]:g}{unit}; the worst, at {worst['pose']:g}{unit}: "
            f"{worst['moving']} with {worst['with']}, {worst['volume_mm3']} mm³ "
            f"({worst['thickness_mm']} mm thick)"
        )
    return row


def _fits_left_out(hits: list[dict], pressed: set) -> list[dict]:
    """The hits that are collisions: those of a press-fit pair no thicker than a fit are not."""
    return [
        h
        for h in hits
        if frozenset((h["moving"], h["with"])) not in pressed
        or h["thickness_mm"] > PERMITTED_THICKNESS_MM
    ]


def _flexes(
    motion: dict,
    flexes: list[dict],
    hits: list[dict],
    names: dict,
    keys: dict,
    ends: tuple[float, ...],
    out_dir: Path,
    problems: list[str],
    touch: bool = True,
) -> tuple[list[dict], list[dict]]:
    """The motion's flex pairs measured on its overlaps, and the overlaps left: collisions. `keys`
    tells which instances move together; without `touch`, a pair may not meet in it (an assembly
    step's flex may meet only as it turns). Its problems start with the motion's `label`."""
    unit = " mm" if motion["kind"] == "slide" else "°"
    label = motion.get("label") or f"motion {motion['name']}"
    rows, left = [], list(hits)
    for flex in flexes:
        pair = {flex["a"], flex["b"]}
        row: dict[str, Any] = {**flex, "ok": True, "poses": None, "depth_mm": 0.0}
        rows.append(row)
        if not pair <= set(keys) or keys[flex["a"]] == keys[flex["b"]]:
            row["ok"] = False
            problems.append(
                f"{label}: the flex {flex['a']} / {flex['b']} needs two "
                "instances that move against each other in it"
            )
            continue
        mine = [h for h in left if {h["moving"], h["with"]} == pair]
        left = [h for h in left if h not in mine]
        if not mine:
            if not touch:
                continue
            row["ok"] = False
            problems.append(
                f"{label}: {flex['a']} and {flex['b']} never overlap along it, so "
                "nothing bends: a flex is a feature that rides over what it presses on (a detent, "
                "a catch). Make it meet that, or leave the flex out"
            )
            continue
        a, b = mine[0]["moving"], mine[0]["with"]
        measured = []
        # The largest overlaps first: one deeper than declared is enough to refuse the flex.
        for hit in sorted(mine, key=lambda h: -h["volume_mm3"]):
            posed, fixed = (
                trimesh.transform_points(
                    names[n]["_mesh"].triangles.reshape(-1, 3), hit["_matrices"][n]
                ).reshape(-1, 3, 3)
                for n in (a, b)
            )
            hit["depth_mm"], hit["depth_is"], hit["depth_floor_mm"] = _flex_depth(
                hit, posed, fixed, flex["max_mm"]
            )
            measured.append(hit)
            if hit["depth_mm"] > flex["max_mm"]:
                break
        deepest = max(measured, key=lambda h: h["depth_mm"])
        poses = sorted({h["pose"] for h in mine})
        stl = out_dir / f"flex-{_slug(motion['name'])}-{_slug(a + b)}.stl"
        _write_stl(deepest["_solid"], stl)
        row.update(
            poses=[poses[0], poses[-1]],
            depth_mm=deepest["depth_mm"],
            at=deepest["pose"],
            overlap_stl=str(stl),
        )
        at_rest = [p for p in poses if any(abs(p - e) <= 1e-3 for e in ends)]  # poses: 3 decimals
        if at_rest:
            row["ok"] = False
            problems.append(
                f"{label}: {a} and {b} still overlap at {at_rest[0]:g}{unit}, "
                "an end of its range: a flex springs back at rest; a fit that stays loaded is "
                "an allowed_interference"
            )
        if deepest["depth_mm"] > flex["max_mm"] and deepest["depth_is"] == "at most":
            row["ok"] = False
            problems.append(
                f"{label}: {a} may go up to {deepest['depth_mm']} mm deep into {b} at "
                f"{deepest['pose']:g}{unit}, past the {flex['max_mm']} mm of its flex: it goes "
                f"{deepest['depth_floor_mm']} mm at least, and the overlap is too large to "
                "measure closer"
            )
        elif deepest["depth_mm"] > flex["max_mm"]:
            row["ok"] = False
            goes = {"measured": "goes", "at least": "goes more than"}
            problems.append(
                f"{label}: {a} {goes[deepest['depth_is']]} {deepest['depth_mm']} "
                f"mm deep into {b} at {deepest['pose']:g}{unit}, deeper than the "
                f"{flex['max_mm']} mm of its flex"
            )
    return rows, left


def _flex_depth(
    hit: dict, moving: np.ndarray, other: np.ndarray, limit: float
) -> tuple[float, str, float]:
    """How deep two solids go into each other: the farthest a point of their overlap's surface
    is from the surface of the other solid (each point of it lies on one of the two; `moving`
    and `other` are their triangles), whether that is "measured", or past the limit and only
    "at least" or "at most" that, and the deepest point measured.

    The deepest point can be inside a face (a ridge as wide as the slider over it has every
    vertex of the overlap on both surfaces), so the surface is sampled at the centers of
    triangles FLEX_SAMPLE_MM wide (wider on a large overlap). A triangle cannot pass the limit
    (plus FLEX_TOLERANCE_MM) when either bound of it stays under: its center's depth plus its
    radius (the distance changes no faster than the point moves), or the farthest of its
    vertices from the face nearest its center on each surface (the distance to one face is
    convex, so a triangle's farthest point from it is a vertex: an overlap as deep as its flex
    across a wide face is measured as that deep). The others are split until they cannot pass
    or one center passes. When that needs more than FLEX_MAX_TRIANGLES, the answer is the
    bound: at most.

    Each piece of the overlap is measured against the surface within the limit plus
    FLEX_SAMPLE_MM of it only (the three detents of a jar make one overlap as wide as the
    jar): a point farther than that from it is at least that deep."""
    deepest = 0.0
    for piece in hit["_solid"].decompose():
        mesh = piece.to_mesh()
        vertices = np.asarray(mesh.vert_properties)[:, :3]
        faces = np.asarray(mesh.tri_verts)
        if not len(faces):
            continue
        # Only the surface near the piece can be nearer than the limit to it.
        margin = limit + FLEX_SAMPLE_MM
        lo, hi = vertices.min(axis=0) - margin, vertices.max(axis=0) + margin
        near = [_Surface(t, lo, hi) for t in (moving, other)]
        size = max(FLEX_SAMPLE_MM, math.sqrt(8 * piece.surface_area() / FLEX_MAX_TRIANGLES))
        vertices, faces = trimesh.remesh.subdivide_to_size(vertices, faces, size, 20)
        depth, kind, floor = _piece_depth(vertices[faces], near, limit, margin)
        if depth > limit:
            return round(depth, 3), kind, round(floor, 3)
        deepest = max(deepest, depth)
    return round(deepest, 3), "measured", round(deepest, 3)


def _piece_depth(
    triangles: np.ndarray, near: list, limit: float, margin: float
) -> tuple[float, str, float]:
    """_flex_depth of one piece of the overlap, sampled on `triangles`; `near` are the two
    surfaces within `margin` of it. The triangles are first taken in cells, FLEX_SAMPLE_MM wide
    and then halved, each measured at the center of one of its triangles, with the farthest of
    its vertices from there as its radius: an overlap cut from fine facets has thousands of
    triangles in a few square mm, and only the cells that might pass the limit are opened."""
    deepest = 0.0
    size = FLEX_SAMPLE_MM
    for _ in range(FLEX_ROUNDS):
        centers = triangles.mean(axis=1)
        cells = np.unique(np.floor(centers / size), axis=0, return_inverse=True)[1].reshape(-1)
        if cells.max() + 1 > len(triangles) // 4:
            break
        mean = np.zeros((cells.max() + 1, 3))
        np.add.at(mean, cells, centers)
        mean /= np.bincount(cells)[:, None]
        # The center nearest the middle of each cell: a point of the surface.
        order = np.lexsort((np.linalg.norm(centers - mean[cells], axis=1), cells))
        sample = centers[order[np.r_[True, cells[order][1:] != cells[order][:-1]]]]
        radius = np.zeros(len(sample))
        reach = np.linalg.norm(triangles - sample[cells][:, None], axis=2).max(axis=1)
        np.maximum.at(radius, cells, reach)
        depth, bound = _depth_and_bound(sample, triangles, cells, near)
        if depth.max() >= margin:
            return margin, "at least", margin
        deepest = max(deepest, float(depth.max()))
        open_ = np.minimum(depth + radius, bound) > limit + FLEX_TOLERANCE_MM
        if deepest > limit or not open_.any():
            return deepest, "measured", deepest
        triangles = triangles[open_[cells]]
        size /= 2
    for _ in range(FLEX_ROUNDS):
        centers = triangles.mean(axis=1)
        radius = np.linalg.norm(triangles - centers[:, None], axis=2).max(axis=1)
        depth, bound = _depth_and_bound(centers, triangles, np.arange(len(triangles)), near)
        if depth.max() >= margin:
            return margin, "at least", margin
        deepest = max(deepest, float(depth.max()))
        upper = np.minimum(depth + radius, bound)
        open_ = upper > limit + FLEX_TOLERANCE_MM
        if deepest > limit or not open_.any():
            return deepest, "measured", deepest
        if 4 * int(open_.sum()) > FLEX_MAX_TRIANGLES:
            break
        triangles = _split(triangles[open_])
    return float(upper[open_].max()), "at most", deepest


def _depth_and_bound(
    samples: np.ndarray, triangles: np.ndarray, cells: np.ndarray, near: list
) -> tuple[np.ndarray, np.ndarray]:
    """The depth at each sample point (the farther of the two surfaces), and a bound of the
    depth over each cell of `triangles` (its index in `cells`): on each surface, the farthest
    of the cell's vertices from the face nearest its sample."""
    depth = np.zeros(len(samples))
    bound = np.zeros(len(samples))
    for surface in near:
        distance, nearest = surface.distance(samples)
        depth = np.maximum(depth, distance)
        farthest = np.zeros(len(samples))
        np.maximum.at(farthest, cells, surface.farthest(triangles, nearest[cells]))
        bound = np.maximum(bound, farthest)
    return depth, bound


class _Surface:
    """The triangles of a surface inside the box [lo, hi], to measure points against.

    `distance` gives each point's distance to the nearest of them (inf without any) and which
    one it is. The triangles are kept in classes about as wide (radius within a factor of 2),
    each in a tree of its centers. A point's distance is at most `bound`, the nearest of the
    triangles of the few nearest centers of each class; the nearest triangle's center is no
    farther than the distance plus its radius, so only the centers of each class within the
    bound plus its widest radius are measured: a cap of the surface around the nearest point,
    whether its facets are fine or a few large ones."""

    def __init__(self, triangles: np.ndarray, lo: np.ndarray, hi: np.ndarray):
        self.triangles = _inside(triangles, lo, hi)
        centers = self.triangles.mean(axis=1)
        radius = np.linalg.norm(self.triangles - centers[:, None], axis=2).max(axis=1)
        level = np.floor(np.log2(np.maximum(radius, 1e-6)))
        self.classes = []
        for each in np.unique(level):
            index = np.nonzero(level == each)[0]
            self.classes.append((cKDTree(centers[index]), index, float(radius[index].max())))

    def distance(self, points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        out = np.full(len(points), np.inf)
        nearest = np.full(len(points), -1)
        if not len(self.triangles):
            return out, nearest
        for tree, index, _ in self.classes:
            k = min(4, len(index))
            cols = tree.query(points, k=k)[1].reshape(len(points), k)
            rows = np.repeat(np.arange(len(points)), k)
            self._measure(points, rows, index[cols.reshape(-1)], out, nearest)
        bound = out.copy()
        for tree, index, widest in self.classes:
            for i in range(0, len(points), 4096):
                chunk = slice(i, i + 4096)
                found = tree.query_ball_point(points[chunk], bound[chunk] + widest)
                rows = np.repeat(np.arange(len(found)), [len(f) for f in found])
                if len(rows):
                    cols = index[np.fromiter(itertools.chain.from_iterable(found), int, len(rows))]
                    self._measure(points[chunk], rows, cols, out[chunk], nearest[chunk])
        return out, nearest

    def farthest(self, triangles: np.ndarray, faces: np.ndarray) -> np.ndarray:
        """How far the farthest vertex of each of `triangles` is from its face of `faces` (inf
        for a face of -1: no surface near it)."""
        out = np.full(len(triangles), np.inf)
        known = faces >= 0
        if known.any():
            vertices = triangles[known].reshape(-1, 3)
            closest = trimesh.triangles.closest_point(
                np.repeat(self.triangles[faces[known]], 3, axis=0), vertices
            )
            out[known] = np.linalg.norm(closest - vertices, axis=1).reshape(-1, 3).max(axis=1)
        return out

    def _measure(self, points, rows, cols, out, nearest) -> None:
        """Keeps, for each point of `rows`, the nearer of what it has and the triangles `cols`."""
        closest = trimesh.triangles.closest_point(self.triangles[cols], points[rows])
        distance = np.linalg.norm(closest - points[rows], axis=1)
        order = np.lexsort((distance, rows))
        first = order[np.r_[True, rows[order][1:] != rows[order][:-1]]]
        better = distance[first] < out[rows[first]]
        out[rows[first][better]] = distance[first][better]
        nearest[rows[first][better]] = cols[first][better]


def _inside(triangles: np.ndarray, lo: np.ndarray, hi: np.ndarray) -> np.ndarray:
    """The triangles whose bounding box meets the box [lo, hi]."""
    keep = np.all(triangles.max(axis=1) >= lo, axis=1) & np.all(triangles.min(axis=1) <= hi, axis=1)
    return triangles[keep]


def _split(triangles: np.ndarray) -> np.ndarray:
    """Each triangle as four, through the midpoints of its edges."""
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
    return np.concatenate(
        [np.stack(t, axis=1) for t in ((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca))]
    )


def _pose(movement: dict, value: float) -> np.ndarray:
    """The 4 × 4 matrix of a rotation, slide or screw at `value` (degrees; mm for a slide)."""
    if movement["kind"] == "slide":
        return translation(movement["axis"], value)
    matrix = rotation(movement["point"], movement["axis"], value)
    if movement["kind"] == "screw":
        matrix = translation(movement["axis"], movement["pitch_mm"] * value / 360) @ matrix
    return matrix


def _poses(motion: dict, value: float) -> dict[str, np.ndarray]:
    """Where a motion at `value` takes each instance it moves: those it names by its own movement,
    those it drives by theirs at its ratio (and then by the motion's, when it names them too)."""
    own = _pose(motion, value)
    out = {name: own for name in motion["instances"]}
    for drive in motion.get("drives") or []:
        matrix = _pose(drive, drive["ratio"] * value)
        for name in drive["instances"]:
            out[name] = out.get(name, np.eye(4)) @ matrix
    return out


def _step(motion: dict, names: dict) -> float:
    """The step of a motion's sweep: no point of what it moves travels more than SWEEP_STEP_MM
    or turns more than SWEEP_STEP_DEG in one, moved by the motion and by its drives."""
    turn, travel = _speed(motion, names)
    return min(
        SWEEP_STEP_DEG / turn if turn else math.inf, SWEEP_STEP_MM / travel if travel else math.inf
    )


def _speed(motion: dict, names: dict) -> tuple[float, float]:
    """The most a motion turns (degrees) and moves (mm) any point of what it moves, for each
    degree (or mm) of the motion, by its own movement and by its drives."""
    span = max(map(abs, motion["range"]))
    turn = travel = 0.0  # the most, for each degree (or mm) of the motion
    for name, inst in names.items():
        vertices = inst["_mesh"].vertices
        drive = next((d for d in motion.get("drives") or [] if name in d["instances"]), None)
        t = d = shift = 0.0
        if drive:
            t, d, shift = _rates(drive, vertices, abs(drive["ratio"]), span)
        if name in motion["instances"]:
            own_t, own_d, _ = _rates(motion, vertices, 1.0, span, shift)
            t, d = t + own_t, d + own_d
        turn, travel = max(turn, t), max(travel, d)
    return turn, travel


def _stops(
    motion: dict,
    pairs: list[tuple[dict, dict]],
    names: dict,
    pressed: set,
    ends: tuple[float, float],
    step: float,
    problems: list[str],
) -> list[dict]:
    """Each stop the motion declares: past that end of its range, before its fastest point has
    moved STOP_TRAVEL_MM more, two instances collide (deeper than its flex, for a flex pair)."""
    unit = " mm" if motion["kind"] == "slide" else "°"
    past = STOP_TRAVEL_MM / max(_speed(motion, names)[1], 1e-9)
    flex = {frozenset((f["a"], f["b"])): f["max_mm"] for f in motion.get("flex") or []}
    rows = []
    for at in motion["stops"]:
        sign = 1.0 if at == ends[1] else -1.0
        count = max(1, math.ceil(past / step))
        values = at + sign * np.linspace(0.0, past, count + 1)[1:]
        poses = [(float(v), _poses(motion, float(v))) for v in values]
        hits = sorted(
            _fits_left_out(_sweep(pairs, poses), pressed), key=lambda h: abs(h["pose"] - at)
        )
        stop = next((h for h in hits if _stops_it(h, flex, names)), None)
        row: dict[str, Any] = {"at": at, "ok": stop is not None}
        rows.append(row)
        if stop:
            row.update(after=round(abs(stop["pose"] - at), 3), by=[stop["moving"], stop["with"]])
            continue
        problems.append(
            f"motion {motion['name']}: it does not stop at {at:g}{unit}: moved {past:.3g}{unit} "
            f"past it ({STOP_TRAVEL_MM:g} mm for its fastest point), nothing is in its way. A "
            "stop is a part in the way: past the end, the parts collide, deeper than any flex"
        )
    return rows


def _rests(
    motion: dict,
    pairs: list[tuple[dict, dict]],
    bent: set,
    rides: list[float],
    problems: list[str],
) -> list[dict]:
    """Each rest the motion declares: there, the pairs its flex names do not overlap (a detent in
    its notch), and between it and the next rest they do somewhere (`rides`: the poses of the
    sweep where they overlap; a gap no pose of the sweep falls in is swept at four more)."""
    unit = " mm" if motion["kind"] == "slide" else "°"
    label = f"motion {motion['name']}"
    flexing = [p for p in pairs if frozenset((p[0]["name"], p[1]["name"])) in bent]
    rests = motion["rests"]
    held = _sweep(flexing, [(r, _poses(motion, r)) for r in rests])
    rows = []
    for k, at in enumerate(rests):
        row: dict[str, Any] = {"at": at, "ok": True}
        pressed = [h for h in held if abs(h["pose"] - at) <= 1e-3]  # poses: 3 decimals
        if pressed:
            worst = max(pressed, key=lambda h: h["volume_mm3"])
            row.update(ok=False, overlap=[worst["moving"], worst["with"]])
            problems.append(
                f"{label}: at its rest {at:g}{unit}, {worst['moving']} and {worst['with']} "
                f"overlap ({worst['thickness_mm']} mm thick): a detent rests free in its notch, "
                "and rides over what it presses on only between rests"
            )
        if k + 1 < len(rests):
            after = rests[k + 1]
            clicks = any(at < pose < after for pose in rides)
            if not clicks:
                values = [float(v) for v in np.linspace(at, after, 6)[1:-1]]
                clicks = bool(_sweep(flexing, [(v, _poses(motion, v)) for v in values]))
            row["rides_to_next"] = clicks
            if not clicks:
                row["ok"] = False
                problems.append(
                    f"{label}: between its rests {at:g}{unit} and {after:g}{unit}, its flex rides "
                    "over nothing, so nothing holds it at either: between two rests a detent "
                    "rides over what it presses on, and drops into the next notch"
                )
        rows.append(row)
    return rows


def _stops_it(hit: dict, flex: dict, names: dict) -> bool:
    """Whether a collision past a stop stops the motion: any, but a flex no deeper than its own."""
    limit = flex.get(frozenset((hit["moving"], hit["with"])))
    if limit is None:
        return True
    posed, other = (
        trimesh.transform_points(
            names[n]["_mesh"].triangles.reshape(-1, 3), hit["_matrices"][n]
        ).reshape(-1, 3, 3)
        for n in (hit["moving"], hit["with"])
    )
    return _flex_depth(hit, posed, other, limit)[0] > limit


def _rates(
    movement: dict, vertices: np.ndarray, ratio: float, span: float, shift: float = 0.0
) -> tuple[float, float, float]:
    """How many degrees a movement at `ratio` turns, and how many mm it moves the farthest of
    the vertices (or of points `shift` away from them), for each unit of the motion; and how far
    it takes one from where it was over a motion of `span` at most."""
    if movement["kind"] == "slide":
        return 0.0, ratio, ratio * span
    radius = _radius(vertices, movement["point"], movement["axis"]) + shift
    arc = radius * math.pi / 180  # mm of arc for each degree
    advance = abs(movement.get("pitch_mm", 0.0)) / 360  # mm along the axis for each degree
    shift = min(2 * radius, ratio * span * arc) + ratio * span * advance
    return ratio, ratio * (arc + advance), shift


def _assembly_order(
    steps: list[dict],
    instances: list[dict],
    names: dict,
    skip: set,
    pressed: set,
    in_place: bool,
    out_dir: Path,
    problems,
) -> list[dict]:
    if len(instances) < 2:
        return []
    if not steps:
        problems.append(
            "the assembly order is missing (assembly_order in the assembly's spec): every "
            "instance, in order, with the direction it moves along as it comes in"
        )
        return []
    if not in_place and len(steps[0]["instances"]) > 1:
        # Parts that start out together were never put together: only a print does that.
        problems.append(
            f"assembly_order, step 1 places {', '.join(steps[0]['instances'])} together, and only "
            "an assembly printed in place starts out in more than one part: start with one and "
            "bring each of the others in along its direction"
        )
    order = [n for s in steps for n in s["instances"]]
    every = [i["name"] for i in instances]
    repeated = sorted({n for n in order if order.count(n) > 1})
    unknown = sorted(set(order) - set(every))
    missing = [n for n in every if n not in order]
    for what, items in (("repeats", repeated), ("names instances that do not exist:", unknown)):
        if items:
            problems.append(f"assembly_order {what} {items}")
    if missing:
        problems.append(f"assembly_order does not say when {missing} comes in")
    rows, placed = [], []
    ctx = None
    try:
        for k, step in enumerate(steps, 1):
            moving = [names[n] for n in step["instances"] if n in names]
            row: dict[str, Any] = {"step": k, "instances": step["instances"], "ok": True}
            direction = np.asarray(step["direction"], float)
            moving_names = set(step["instances"])
            against = [
                p
                for p in placed
                if not any(frozenset((p["name"], m)) in skip for m in moving_names)
            ]
            if np.linalg.norm(direction) < 1e-9:
                if placed:
                    row["ok"] = False
                    problems.append(
                        f"assembly_order, step {k} ({', '.join(step['instances'])}): no direction "
                        "to come in along; only the first step may have none"
                    )
            elif against and moving:
                turn = step.get("turn")
                start = _pose(turn, -turn["degrees"]) if turn else np.eye(4)
                meshes = [_transformed(m["_mesh"], start) for m in moving]
                if ctx is None:
                    import moderngl

                    ctx = moderngl.create_context(standalone=True, backend="egl")
                direction /= np.linalg.norm(direction)
                flexes = step.get("flex") or []
                keys = {n: (n in moving_names, -1) for n in names}
                partners = {n for f in flexes for n in (f["a"], f["b"])}
                # What snaps in comes in by steps, against what it flexes on; the rest, whole.
                swept = [p for p in against if p["name"] in partners]
                rigid = [p for p in against if p not in swept]
                # A part pressed in place comes in straight; one that turns presses as it turns.
                fits = {} if turn else _fits(moving, rigid, pressed)
                approach = blocked(
                    ctx, meshes, [(p["name"], p["_mesh"]) for p in rigid], direction, fits
                )
                flexed: list[list[dict]] = []
                if swept:
                    span = _clear_after(meshes, swept, direction)
                    count = min(SWEEP_MAX_STEPS, max(1, math.ceil(span / SWEEP_STEP_MM)))
                    poses = [
                        (float(v), {m["name"]: translation(direction, v) @ start for m in moving})
                        for v in np.linspace(-span, 0.0, count + 1)
                    ]
                    hits = _fits_left_out(
                        _sweep([(m, p) for m in moving for p in swept], poses), pressed
                    )
                    coming = {
                        "name": f"step {k}",
                        "kind": "slide",
                        "label": f"assembly_order, step {k}",
                    }
                    rows_in, hits = _flexes(
                        coming,
                        flexes,
                        hits,
                        names,
                        keys,
                        (-span,) if turn else (-span, 0.0),
                        out_dir,
                        problems,
                        touch=False,
                    )
                    flexed.append(rows_in)
                    row["flex"] = rows_in
                    if hits:
                        row["ok"] = False
                        worst = max(hits, key=lambda h: h["volume_mm3"])
                        row["approach_collision"] = _public(worst)
                        problems.append(
                            f"assembly_order, step {k}: coming in along {_vec(direction)}, "
                            f"{worst['moving']} hits {worst['with']} {-worst['pose']:g} mm before "
                            f"it is in ({worst['volume_mm3']} mm³, {worst['thickness_mm']} mm "
                            "thick): deeper than any flex it declares"
                        )
                if not approach["ok"]:
                    row["ok"] = False
                    free = [
                        name
                        for name, axis in AXES.items()
                        if blocked(
                            ctx,
                            meshes,
                            [(p["name"], p["_mesh"]) for p in against],
                            np.array(axis, float),
                            fits,
                        )["ok"]
                    ]
                    row["approach"] = approach
                    row["free_axes"] = free
                    problems.append(
                        f"assembly_order, step {k}: {', '.join(step['instances'])} does not go in "
                        f"moving along {_vec(direction)}: it hits "
                        f"{', '.join(approach['against'])} on {approach['area_mm2']} mm² of its "
                        f"shadow (zone {approach['bounds']}); "
                        + (
                            f"it would go in along {', '.join(free)}"
                            if free
                            else "it goes in along no axis direction"
                        )
                    )
                if turn:
                    span = turn["degrees"]
                    motion = {**turn, "instances": step["instances"], "range": [-span, 0.0]}
                    step_deg = _step(motion, {m["name"]: m for m in moving})
                    count = min(SWEEP_MAX_STEPS, max(1, math.ceil(abs(span) / step_deg)))
                    poses = [
                        (float(a), {m["name"]: _pose(turn, float(a)) for m in moving})
                        for a in np.linspace(-span, 0.0, count + 1)
                    ]
                    pairs = [(m, p) for m in moving for p in against]
                    hits = _fits_left_out(_sweep(pairs, poses), pressed)
                    if flexes:
                        turning = {
                            **motion,
                            "name": f"step {k}",
                            "label": f"assembly_order, step {k}",
                        }
                        rows_turn, hits = _flexes(
                            turning,
                            flexes,
                            hits,
                            names,
                            keys,
                            (0.0,),
                            out_dir,
                            problems,
                            touch=False,
                        )
                        flexed.append(rows_turn)
                        row["turn_flex"] = rows_turn
                    row["turn_ok"] = not hits
                    if hits:
                        row["ok"] = False
                        worst = max(hits, key=lambda h: h["volume_mm3"])
                        row["turn_collision"] = _public(worst)
                        verb = "screwing" if turn["kind"] == "screw" else "turning"
                        problems.append(
                            f"assembly_order, step {k}: {verb} {span:g}° into place, "
                            f"{worst['moving']} hits {worst['with']} {worst['pose']:g}° "
                            f"before the end ({worst['volume_mm3']} mm³)"
                        )
                for i, flex in enumerate(flexes):
                    if not any(r[i]["poses"] for r in flexed):
                        row["ok"] = False
                        problems.append(
                            f"assembly_order, step {k}: {flex['a']} and {flex['b']} never "
                            "overlap as it comes in, so nothing snaps: a flex is a feature that "
                            "rides over what it presses on. Make it meet that, or leave it out"
                        )
            rows.append(row)
            placed += moving
    finally:
        if ctx is not None:
            ctx.release()
    return rows


def _clear_after(meshes: list[trimesh.Trimesh], placed: list[dict], direction) -> float:
    """How far back along `direction` the meshes start clear of what is placed: where their
    bounding boxes, seen along it, no longer meet."""
    ahead = max(float((trimesh.bounds.corners(m.bounds) @ direction).max()) for m in meshes)
    behind = min(
        float((trimesh.bounds.corners(p["_mesh"].bounds) @ direction).min()) for p in placed
    )
    return max(ahead - behind + 1.0, SWEEP_STEP_MM)


_DEPTH_VS = """
#version 330
uniform mat4 mvp;
in vec3 in_pos;
void main() { gl_Position = mvp * vec4(in_pos, 1.0); }
"""
_DEPTH_FS = """
#version 330
uniform int layer;
out vec4 color;
void main() {
    int n = layer + 1;
    color = vec4(float(n & 255) / 255.0, float((n >> 8) & 255) / 255.0, 0.0, 1.0);
}
"""


def _fits(moving: list[dict], against: list[dict], pressed: set) -> dict:
    """The overlaps in place of the moving instances with each placed one they press into."""
    fits: dict[str, list[trimesh.Trimesh]] = {}
    for p in against:
        for m in moving:
            if frozenset((m["name"], p["name"])) not in pressed:
                continue
            if hit := overlap(m["_solid"], p["_solid"]):
                fits.setdefault(p["name"], []).append(_trimesh(hit["_solid"]))
    return fits


def blocked(
    ctx,
    moving: list[trimesh.Trimesh],
    placed: list[tuple[str, trimesh.Trimesh]],
    direction,
    fits: dict[str, list[trimesh.Trimesh]] | None = None,
) -> dict:
    """Whether the moving meshes, arriving from far away along `direction`, cross the placed
    ones: in some column along the direction, placed material lies behind (against the motion)
    the farthest-forward point of the moving parts. One pixel of border is forgiven on each
    side, where two outlines that only touch share pixels. `fits` holds, by placed part, the
    overlaps in place of a press fit: in a column where the first of that part the moving parts
    meet is their overlap in place, they push into it as a fit; anywhere else they cross it."""
    fits = fits or {}
    basis = section.frame(direction)  # rows u, v and the direction
    points = np.vstack([m.vertices for m in moving])
    uv = points @ basis[:2].T
    size = float(np.max(uv.max(axis=0) - uv.min(axis=0)))
    px = max(DEPTH_PX_MM, size / DEPTH_MAX_SIDE)
    lo = uv.min(axis=0) - 2 * px
    shape = np.ceil((uv.max(axis=0) + 2 * px - lo) / px).astype(int)  # columns, rows
    hi = lo + shape * px
    near = [
        (name, mesh) for name, mesh in placed if _overlaps_2d(mesh.vertices @ basis[:2].T, lo, hi)
    ]
    if not near:
        return {"ok": True}
    every = np.vstack([points] + [m.vertices for _, m in near]) @ basis[2]
    s_lo, s_hi = float(every.min()) - 1.0, float(every.max()) + 1.0
    mvp = np.zeros((4, 4))
    mvp[0, :3], mvp[0, 3] = basis[0] * 2 / (hi[0] - lo[0]), -(hi[0] + lo[0]) / (hi[0] - lo[0])
    mvp[1, :3], mvp[1, 3] = basis[1] * 2 / (hi[1] - lo[1]), -(hi[1] + lo[1]) / (hi[1] - lo[1])
    mvp[2, :3], mvp[2, 3] = basis[2] * 2 / (s_hi - s_lo), -(s_hi + s_lo) / (s_hi - s_lo)
    mvp[3, 3] = 1.0
    front, _ = _depth(ctx, moving, mvp, tuple(shape), farthest=True)
    front_s = s_lo + front * (s_hi - s_lo)
    hit = np.zeros(front.shape, bool)
    behind_s = np.zeros(front.shape)
    names = np.full(front.shape, "", dtype=object)
    free = [x for x in near if x[0] not in fits]
    pressed = [x for x in near if x[0] in fits]
    for group in (free, pressed):
        if not group:
            continue
        behind, owner = _depth(ctx, [m for _, m in group], mvp, tuple(shape), farthest=False)
        group_s = s_lo + behind * (s_hi - s_lo)
        crossed = (front > 0.0) & (behind < 1.0) & (group_s < front_s - DEPTH_EPS_MM)
        if group is pressed:
            overlaps = [m for name, _ in group for m in fits[name]]
            fit, _ = _depth(ctx, overlaps, mvp, tuple(shape), farthest=False)
            fit_s = s_lo + fit * (s_hi - s_lo)
            crossed &= ~((fit < 1.0) & (group_s >= fit_s - px - DEPTH_EPS_MM))
        crossed &= ~hit
        hit |= crossed
        behind_s[crossed] = group_s[crossed]
        label = np.array([name for name, _ in group] + [""], dtype=object)
        names[crossed] = label[np.where((owner >= 0) & (owner < len(group)), owner, -1)][crossed]
    hit = binary_erosion(hit, structure=np.ones((3, 3), bool))
    if not hit.any():
        return {"ok": True}
    rows, cols = np.nonzero(hit)
    u = lo[0] + (cols + 0.5) * px
    v = lo[1] + (rows + 0.5) * px
    world = u[:, None] * basis[0] + v[:, None] * basis[1] + behind_s[rows, cols][:, None] * basis[2]
    found, counts = np.unique(names[rows, cols].astype(str), return_counts=True)
    against = [str(n) for n in found[np.argsort(-counts)] if n]
    return {
        "ok": False,
        "against": against,
        "area_mm2": round(float(hit.sum()) * px * px, 2),
        "bounds": _r([world.min(axis=0), world.max(axis=0)]),
        "grid_mm": round(px, 4),
    }


def _depth(
    ctx, meshes: list[trimesh.Trimesh], mvp: np.ndarray, shape: tuple[int, int], farthest: bool
):
    """Window depth per pixel (rows bottom-up) of the farthest or the nearest drawn point, and
    the index of the mesh that drew it."""
    import moderngl

    fbo = ctx.framebuffer(
        color_attachments=[ctx.renderbuffer(shape, components=4)],
        depth_attachment=ctx.depth_texture(shape),
    )
    fbo.use()
    ctx.viewport = (0, 0, *shape)
    ctx.clear(0.0, 0.0, 0.0, 1.0, depth=0.0 if farthest else 1.0)
    ctx.enable(moderngl.DEPTH_TEST)
    ctx.depth_func = ">" if farthest else "<"
    program = ctx.program(vertex_shader=_DEPTH_VS, fragment_shader=_DEPTH_FS)
    program["mvp"].write(mvp.T.astype("f4").tobytes())
    released = [program]
    for i, mesh in enumerate(meshes):
        program["layer"].value = i
        vbo = ctx.buffer(mesh.vertices[mesh.faces].reshape(-1, 3).astype("f4").tobytes())
        vao = ctx.vertex_array(program, [(vbo, "3f", "in_pos")])
        vao.render(moderngl.TRIANGLES)
        released += [vao, vbo]
    width, height = shape
    depth = np.frombuffer(fbo.depth_attachment.read(), dtype="f4").reshape(height, width).copy()
    raw = np.frombuffer(fbo.read(components=3), dtype=np.uint8).reshape(height, width, 3)
    owner = raw[:, :, 0].astype(int) + 256 * raw[:, :, 1].astype(int) - 1
    for obj in released:
        obj.release()
    fbo.depth_attachment.release()
    fbo.release()
    return depth, owner


# ---- helpers ------------------------------------------------------------------------------


def _radius(vertices: np.ndarray, point, axis) -> float:
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    rel = vertices - np.asarray(point, float)
    return float(np.linalg.norm(rel - np.outer(rel @ axis, axis), axis=1).max())


def _transformed(mesh: trimesh.Trimesh, matrix: np.ndarray) -> trimesh.Trimesh:
    out = mesh.copy()
    out.apply_transform(matrix)
    return out


def _posed_mesh(instances: list[dict], matrices: dict[str, np.ndarray]) -> trimesh.Trimesh:
    return trimesh.util.concatenate(
        [_transformed(i["_mesh"], matrices.get(i["name"], np.eye(4))) for i in instances]
    )


def _box_gap(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.max(np.maximum(a[0] - b[1], b[0] - a[1]).clip(min=0)))


def _overlaps_2d(points: np.ndarray, lo: np.ndarray, hi: np.ndarray) -> bool:
    return bool(np.all(points.min(axis=0) <= hi) and np.all(points.max(axis=0) >= lo))


def _trimesh(solid: manifold3d.Manifold) -> trimesh.Trimesh:
    mesh = solid.to_mesh()
    return trimesh.Trimesh(np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts))


def _write_stl(solid: manifold3d.Manifold, path: Path) -> None:
    _write_mesh(_trimesh(solid), path)


def _write_mesh(mesh: trimesh.Trimesh, path: Path) -> None:
    # ASCII, like the exports: binary STL rounds to float32 and fuses near vertices.
    path.write_bytes(trimesh.exchange.stl.export_stl_ascii(mesh).encode())


def _public(hit: dict) -> dict:
    return {k: v for k, v in hit.items() if not k.startswith("_")}


def _slug(text: str) -> str:
    keep = "".join(c if c.isalnum() else "_" for c in text)[:40]
    return keep + "-" + hashlib.sha256(text.encode()).hexdigest()[:4]


def _vec(v) -> str:
    return "[" + ", ".join(f"{c + 0.0:g}" for c in np.round(v, 3)) + "]"


def _r(array) -> list:
    return (np.round(np.asarray(array, float), 3) + 0.0).tolist()
