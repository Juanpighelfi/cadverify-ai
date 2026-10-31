"""assembly_report: the parts of an assembly measured where the assembly places them.

The assembly (`part = "assembly"`) places each part through a module the prompt gives the model:

    cadverify_only = "";
    module instance(name, part, unit = 1) {
        echo(cadverify_instance = [name, part, unit]);
        if (cadverify_only == "" || cadverify_only == name) children();
    }

so the list of instances comes from the code, and `-D cadverify_only="<name>"` exports one
instance alone, in assembly coordinates. A name no instance has exports what the assembly draws
outside instance(): it must be nothing. `part` is the printable part the instance is, or
"external" for what is not printed (a wall, a screw, a rope).

What is measured (G3, assembly):
- each instance is its printable part moved, not a variant of it: the same volume, area and
  principal moments of inertia (a mirror image passes: the moments do not tell it apart);
- every printable part is in unit 1, as many times as its spec's `copies`;
- no two instances overlap: an overlap counts when it is more than 0.01 mm³ and more than
  0.02 mm thick on average (2·V/A of the overlap: a disc resting in a round seat overlapped
  0.36 mm³ that were 0.0075 mm thick, the faceting of two circles). A press fit is declared in
  `allowed_interferences`, up to 0.3 mm thick;
- the instances touch each other (1 mm or less apart, manifold3d's min_gap) as one group;
- with `requirements["units"] = n`, units 1 to n are there and each one touches the one before;
- the assembly's own `bounds` and `support_faces`, if its spec declares them, on its instances
  together.

And G4, motion:
- each `motions` entry sweeps its instances through the whole range (from 0, the assembled
  pose), at most 0.25 mm of travel or 2° per step, measuring the overlap at each step;
- `assembly_order` lists every instance once, in order: each step's instances arrive from far away
  moving along its direction (and then turn, if the step says so) without crossing what the
  steps before placed. The straight approach is checked whole with two depth maps along the
  direction (the farthest point of the moving parts against the nearest of the placed ones, on a
  grid of 0.05 mm or finer than 1/3000 of the size); the turn, by steps like a movement.
"""

from __future__ import annotations

import hashlib
import itertools
import math
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import manifold3d
import numpy as np
import trimesh
from scipy.ndimage import binary_erosion

from cadverify.cadcheck import section
from cadverify.cadcheck.mesh import load_exact
from cadverify.cadcheck.scad import ASSEMBLY, scad_export

SOLO = "cadverify_only"
OUTSIDE = "__outside_instances__"
EXTERNAL = "external"
OVERLAP_MM3 = 0.01
OVERLAP_THICKNESS_MM = 0.02
PERMITTED_THICKNESS_MM = 0.3
CONTACT_MM = 1.0
CONGRUENCE_REL = 1e-3  # volume and area
INERTIA_REL = 2e-3  # of the largest principal moment
SWEEP_STEP_MM = 0.25
SWEEP_STEP_DEG = 2.0
SWEEP_MAX_STEPS = 360
DEPTH_PX_MM = 0.05
DEPTH_MAX_SIDE = 3000
DEPTH_EPS_MM = 0.02
EXPORT_WORKERS = 2  # the sandbox has 2 CPUs
AXES = {
    "+x": (1, 0, 0),
    "-x": (-1, 0, 0),
    "+y": (0, 1, 0),
    "-y": (0, -1, 0),
    "+z": (0, 0, 1),
    "-z": (0, 0, -1),
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
    report: dict[str, Any] = {"ok": False, "problems": {"G3": g3, "G4": g4}}

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

    _congruence(good, parts, g3)
    report["instances"] = [{k: v for k, v in i.items() if not k.startswith("_")} for i in instances]
    report["copies"] = _copies(instances, parts, g3)
    permitted = _permitted(spec, {i["name"] for i in instances}, g3)
    report["pairs"] = _pairs(good, permitted, out_dir, g3)
    report["components"] = _components(good, report["pairs"], g3)
    report["units"] = _units(instances, report["pairs"], int(requirements.get("units", 1)), g3)
    report["spec_check"] = _own_spec(good, spec, g3)

    names = {i["name"]: i for i in good}
    # Pairs left out of the motion checks: the permitted press fits, and the overlaps G3
    # already reports (they would collide at every pose and in every direction).
    skip = {
        frozenset((p["a"], p["b"]))
        for p in report["pairs"]
        if p.get("permitted") or p.get("interference")
    }
    motions = spec.get("motions", [])
    report["motions"] = [_motion(m, names, skip, out_dir, g4) for m in motions]
    steps = spec.get("assembly_order", [])
    before = len(g4)
    report["assembly_steps"] = _assembly_order(steps, instances, names, skip, out_dir, g4)
    report["assembly_order_ok"] = len(g4) == before
    return _done(report, t0)


def _done(report: dict[str, Any], t0: float) -> dict[str, Any]:
    report["ok"] = not report["problems"]["G3"] and not report["problems"]["G4"]
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


def _properties(mesh: trimesh.Trimesh) -> tuple[float, float, np.ndarray]:
    inertia = np.linalg.eigvalsh(mesh.moment_inertia)
    return float(mesh.volume), float(mesh.area), np.sort(inertia)


def _congruence(instances: list[dict], parts: dict[str, dict], problems: list[str]) -> None:
    cache: dict[str, tuple] = {}
    for inst in instances:
        part = inst["part"]
        if part == EXTERNAL or part not in parts:
            inst["congruent"] = None
            continue
        if part not in cache:
            cache[part] = _properties(load_exact(parts[part]["path"]))
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
        if not ok:
            problems.append(
                f"the instance {inst['name']} is not the part {part} that is printed: volume "
                f"{v:.1f} against {volume:.1f} mm³, area {a:.1f} against {area:.1f} mm² (the "
                "assembly must place the same part, moved)"
            )


def _copies(instances: list[dict], parts: dict[str, dict], problems: list[str]) -> list[dict]:
    for inst in instances:
        if inst["part"] != EXTERNAL and inst["part"] not in parts:
            problems.append(
                f"the instance {inst['name']} says it is the part {inst['part']!r}, which is "
                f"neither a printable option of the part selector ({sorted(parts)}) nor "
                f"{EXTERNAL!r}"
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


# ---- G4 -----------------------------------------------------------------------------------


def rotation(point, axis, degrees: float) -> np.ndarray:
    """4 × 4 rotation by `degrees` about the axis through `point` (right hand rule)."""
    return trimesh.transformations.rotation_matrix(math.radians(degrees), axis, point)


def translation(direction, mm: float) -> np.ndarray:
    matrix = np.eye(4)
    matrix[:3, 3] = np.asarray(direction, float) * mm
    return matrix


def _sweep(
    moving: list[dict],
    others: list[dict],
    poses: list[tuple[float, np.ndarray]],
) -> list[dict[str, Any]]:
    """The collisions of the moving instances, posed by each 4 × 4 matrix, with the others."""
    boxes = [(o, np.reshape(o["_solid"].bounding_box(), (2, 3))) for o in others]
    hits = []
    for pose, matrix in poses:
        for inst in moving:
            solid = inst["_solid"].transform(matrix[:3])
            box = np.reshape(solid.bounding_box(), (2, 3))
            for other, other_box in boxes:
                if _box_gap(box, other_box) > 0:
                    continue
                hit = overlap(solid, other["_solid"])
                if hit:
                    hits.append(
                        {
                            "pose": round(pose, 3),
                            "moving": inst["name"],
                            "with": other["name"],
                            **hit,
                        }
                    )
    return hits


def _motion(motion: dict, names: dict, permitted: set, out_dir: Path, problems: list[str]) -> dict:
    row: dict[str, Any] = {"name": motion["name"], "kind": motion["kind"], "range": motion["range"]}
    missing = [n for n in motion["instances"] if n not in names]
    if missing:
        problems.append(f"motion {motion['name']}: there are no instances {missing}")
        return {**row, "ok": False}
    moving = [names[n] for n in motion["instances"]]
    moving_names = set(motion["instances"])
    others = [
        o
        for n, o in names.items()
        if n not in moving_names and not any(frozenset((n, m)) in permitted for m in moving_names)
    ]
    lo, hi = min(0.0, motion["range"][0]), max(0.0, motion["range"][1])
    if motion["kind"] == "rotate":
        reach = max(_radius(i["_mesh"].vertices, motion["point"], motion["axis"]) for i in moving)
        step = min(SWEEP_STEP_DEG, math.degrees(SWEEP_STEP_MM / max(reach, 1e-6)))
    else:
        step = SWEEP_STEP_MM
    count = min(SWEEP_MAX_STEPS, max(1, math.ceil((hi - lo) / step)))
    values = np.linspace(lo, hi, count + 1)
    poses = [(float(v), _pose(motion, float(v))) for v in values]
    hits = _sweep(moving, others, poses)
    row.update(ok=not hits, steps=count + 1, step=round((hi - lo) / count, 4))
    unit = "°" if motion["kind"] == "rotate" else " mm"
    if hits:
        worst = max(hits, key=lambda h: h["volume_mm3"])
        first = min(hits, key=lambda h: abs(h["pose"]))
        stl = out_dir / f"motion-{_slug(motion['name'])}-{_slug(str(worst['pose']))}.stl"
        _write_stl(worst["_solid"], stl)
        posed = out_dir / f"motion-{_slug(motion['name'])}-pose.stl"
        _write_mesh(_posed_mesh(moving, _pose(motion, worst["pose"])), posed)
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


def _pose(motion: dict, value: float) -> np.ndarray:
    if motion["kind"] == "rotate":
        return rotation(motion["point"], motion["axis"], value)
    return translation(motion["axis"], value)


def _assembly_order(
    steps: list[dict], instances: list[dict], names: dict, permitted: set, out_dir: Path, problems
) -> list[dict]:
    if len(instances) < 2:
        return []
    if not steps:
        problems.append(
            "the assembly order is missing (assembly_order in the assembly's spec): every "
            "instance, in order, with the direction it comes in from"
        )
        return []
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
                if not any(frozenset((p["name"], m)) in permitted for m in moving_names)
            ]
            if np.linalg.norm(direction) < 1e-9:
                if placed:
                    row["ok"] = False
                    problems.append(
                        f"assembly_order, step {k} ({', '.join(step['instances'])}): no direction "
                        "to come in from; only the first step may have none"
                    )
            elif against and moving:
                turn = step.get("turn")
                start = (
                    rotation(turn["point"], turn["axis"], -turn["degrees"]) if turn else np.eye(4)
                )
                meshes = [_transformed(m["_mesh"], start) for m in moving]
                if ctx is None:
                    import moderngl

                    ctx = moderngl.create_context(standalone=True, backend="egl")
                direction /= np.linalg.norm(direction)
                approach = blocked(
                    ctx, meshes, [(p["name"], p["_mesh"]) for p in against], direction
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
                    reach = max(
                        _radius(m["_mesh"].vertices, turn["point"], turn["axis"]) for m in moving
                    )
                    step_deg = min(SWEEP_STEP_DEG, math.degrees(SWEEP_STEP_MM / max(reach, 1e-6)))
                    count = min(SWEEP_MAX_STEPS, max(1, math.ceil(abs(span) / step_deg)))
                    poses = [
                        (float(a), rotation(turn["point"], turn["axis"], float(a)))
                        for a in np.linspace(-span, 0.0, count + 1)
                    ]
                    hits = _sweep(moving, against, poses)
                    row["turn_ok"] = not hits
                    if hits:
                        row["ok"] = False
                        worst = max(hits, key=lambda h: h["volume_mm3"])
                        row["turn_collision"] = _public(worst)
                        problems.append(
                            f"assembly_order, step {k}: turning {span:g}° into place, "
                            f"{worst['moving']} hits {worst['with']} {worst['pose']:g}° "
                            f"before the end ({worst['volume_mm3']} mm³)"
                        )
            rows.append(row)
            placed += moving
    finally:
        if ctx is not None:
            ctx.release()
    return rows


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


def blocked(
    ctx, moving: list[trimesh.Trimesh], placed: list[tuple[str, trimesh.Trimesh]], direction
) -> dict:
    """Whether the moving meshes, arriving from far away along `direction`, cross the placed
    ones: in some column along the direction, placed material lies behind (against the motion)
    the farthest-forward point of the moving parts. One pixel of border is forgiven on each
    side, where two outlines that only touch share pixels."""
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
    behind, owner = _depth(ctx, [m for _, m in near], mvp, tuple(shape), farthest=False)
    front_s = s_lo + front * (s_hi - s_lo)
    behind_s = s_lo + behind * (s_hi - s_lo)
    hit = (front > 0.0) & (behind < 1.0) & (behind_s < front_s - DEPTH_EPS_MM)
    hit = binary_erosion(hit, structure=np.ones((3, 3), bool))
    if not hit.any():
        return {"ok": True}
    rows, cols = np.nonzero(hit)
    u = lo[0] + (cols + 0.5) * px
    v = lo[1] + (rows + 0.5) * px
    world = u[:, None] * basis[0] + v[:, None] * basis[1] + behind_s[rows, cols][:, None] * basis[2]
    ids, counts = np.unique(owner[rows, cols], return_counts=True)
    against = [near[i][0] for i in ids[np.argsort(-counts)] if 0 <= i < len(near)]
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


def _posed_mesh(instances: list[dict], matrix: np.ndarray) -> trimesh.Trimesh:
    return trimesh.util.concatenate([_transformed(i["_mesh"], matrix) for i in instances])


def _box_gap(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.max(np.maximum(a[0] - b[1], b[0] - a[1]).clip(min=0)))


def _overlaps_2d(points: np.ndarray, lo: np.ndarray, hi: np.ndarray) -> bool:
    return bool(np.all(points.min(axis=0) <= hi) and np.all(points.max(axis=0) >= lo))


def _write_stl(solid: manifold3d.Manifold, path: Path) -> None:
    mesh = solid.to_mesh()
    _write_mesh(
        trimesh.Trimesh(np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts)), path
    )


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
