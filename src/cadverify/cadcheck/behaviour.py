"""G6, behaviour: what the parts do under force, computed by the harness on its own meshes.

Three things a spec declares, and what is computed for each (cadcheck.fea does the elasticity):

- a `flex` of a motion or an assembly step. G4 measures how deep the two instances go into each
  other, and that depth has to be taken up by the two bending. Each is cut out around the contact,
  held at the cut and pushed on the surface inside the overlap, for its compliance: mm per N. Two
  springs in series take the depth: F = depth / (c_a + c_b), each deflecting F * c. A part that is
  not printed (external, standard) counts as rigid. The strain is the peak tension over the
  modulus, on the surface, against the limit for what bends once (an assembly step) or again and
  again (a motion). Nobody says which part bends or which is a beam, so nobody can get it wrong.
- a `loads` entry: a force or a weight on a region of a part, a region held still, and a limit on
  how far it may move. It gives the stress, the strain and the deflection, against the limit for
  what stays loaded.
- a `stability` entry: which way is down and what it carries. The mass and center of gravity of
  the printed parts are measured, for a print from 30% full to solid, with what it carries
  on top, against the polygon it stands on: how far inside, and how far it can lean.

Layers are weakest pulled apart, and the tension along the print's Z is judged by itself, against
the limit times the material's `z_factor`. The print's Z of an instance comes from the pose it
prints in, or from how its part, exported as it prints, was moved into the assembly.

A cut is checked by growing it: it doubles until the compliance moves under SETTLED of it, or
nothing is left to cut. A mesh is checked by refining it: sizes times REFINE, and a part that holds
a real share of the depth or of its limit has to move under SETTLED again. When a part cannot be
filled, a load touches nothing or the numbers do not settle, the gate is red and says so.

The parts are solid and elastic: infill, creep and large displacements are not modeled.
"""

from __future__ import annotations

import base64
import hashlib
import json
import math
import os
import time
from pathlib import Path
from typing import Any

import numpy as np
import shapely
import trimesh
from scipy.spatial import cKDTree

from cadverify.cadcheck import fea
from cadverify.cadcheck.materials import MATERIALS, POISSON, Material
from cadverify.cadcheck.mesh import load_exact

SETTLED = 0.10
REFINE = 0.7
WORTH_REFINING = 0.25  # of the depth a part takes up
MARGIN = 0.7  # of a limit: a stiff part under this, far from its verdict, is not refined
CROP_START_MM = 12.0
FILLS = (0.3, 1.0)  # of the solid's weight, for a print from sparse to solid
FAR_FIXED = 0.8  # with nothing to cut, the part is held where it is this far from the contact
SUPPORT_TOLERANCE_MM = 0.2
MIN_TILT_DEG = 5.0  # how far a product must lean before it tips, by default
REPEATED, ONCE = "repeated", "once"
# When the checks of one version must stop: the verification has its own timeout around it.
TIME_BUDGET_S = 600.0


def declared(spec: dict[str, Any] | None) -> bool:
    return bool((spec or {}).get("loads") or (spec or {}).get("stability"))


def behaviour_report(
    assembly: dict[str, Any] | None,
    parts: list[dict[str, Any]],
    out_dir: str | Path,
    default_material: str | None = None,
    time_budget_s: float = TIME_BUDGET_S,
    embed: bool = True,
    save: Path | None = None,
) -> dict[str, Any]:
    """Every flex, load and stability the spec declares, from the assembly report and the exports
    of `verify`. `default_material` stands for one the spec does not declare: only to recompute
    recorded sessions, whose specs could not declare it. Each part computed gets a picture:
    its strain in color and its peak marked, in `out_dir`, and inside the report with `embed`.
    With `save`, the report as it stands goes to that file after each thing computed."""
    t0 = time.perf_counter()
    cpu_at_start = _cpu()
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    # In CPU seconds: a verdict does not depend on what else the machine is doing. A mesher that
    # hangs uses none, and verify.behaviour_of holds that one with the clock.
    deadline = cpu_at_start + time_budget_s
    problems: list[str] = []
    rows: dict[str, list] = {"flex": [], "loads": [], "stability": []}
    spec = (assembly or {}).get("spec") or {}
    flexes = _declared_flexes(assembly or {})
    part_specs = {p["part"]: (p["export"].get("spec") or {}) for p in parts}
    wants = bool(flexes) or declared(spec) or any(declared(s) for s in part_specs.values())
    report: dict[str, Any] = {"declared": wants, **rows, "problems": problems}

    def checkpoint() -> None:
        _write(report, save)

    checkpoint()
    for part in parts:
        if part["export"].get("spec_error"):
            label = part["part"] or "default output"
            problems.append(f"the spec of {label} did not parse, so what it declares is not known")
    if not wants:
        return _done(report, t0, save)
    geometry = (assembly or {}).get("problems") or {}
    if geometry.get("G3") or geometry.get("G4") or (flexes and not assembly.get("instances")):
        problems.append(
            "not computed: the assembly has to pass G3 and G4 first, since a force is computed "
            "on the depth G4 measures"
        )
        report["skipped"] = True
        return _done(report, t0, save)

    def material_of(name: str | None) -> Material | None:
        return _material(name or spec.get("material") or default_material)

    instances = {i["name"]: i for i in (assembly or {}).get("instances") or []}
    context = _Context(spec, instances, part_specs, parts, material_of)
    context.pictures = (out_dir, embed)
    used: dict[str, Material] = {}
    for item in flexes:
        if _cpu() > deadline:
            problems.append(f"not computed, out of time: the flex {item['a']} / {item['b']}")
            continue
        rows["flex"].append(_flex(item, context, used, problems))
        checkpoint()
    for part in parts:
        pspec = part["export"].get("spec") or {}
        if not pspec.get("loads") and not pspec.get("stability"):
            continue
        if not part["export"].get("ok"):
            problems.append(f"not computed: the part {part['part']} did not export")
            continue
        mesh = load_exact(part["export"]["path"])
        material = material_of(pspec.get("material"))
        label = part["part"] or "default output"
        for load in pspec.get("loads") or []:
            if _cpu() > deadline:
                problems.append(f"not computed, out of time: the load {load['name']}")
                continue
            rows["loads"].append(
                _load(load, mesh, material, np.eye(3)[2], label, used, problems, (out_dir, embed))
            )
            checkpoint()
        for item in pspec.get("stability") or []:
            rows["stability"].append(_stability(item, [mesh], material, label, used, problems))
    for load in spec.get("loads") or []:
        inst = instances.get(load["instance"])
        if inst is None or not inst.get("stl"):
            problems.append(f"the load {load['name']}: there is no instance {load['instance']}")
            continue
        if _cpu() > deadline:
            problems.append(f"not computed, out of time: the load {load['name']}")
            continue
        material = context.material(load["instance"])
        rows["loads"].append(
            _load(
                load,
                load_exact(inst["stl"]),
                material,
                context.print_z(load["instance"], np.eye(4)),
                load["instance"],
                used,
                problems,
                (out_dir, embed),
            )
        )
        checkpoint()
    for item in spec.get("stability") or []:
        printed = [i for i in instances.values() if context.printed(i)]
        meshes = [load_exact(i["stl"]) for i in printed if i.get("stl")]
        # A multi-material product weighs each part as its own; the first stands for the table.
        material = context.material(printed[0]["name"]) if printed else None
        rows["stability"].append(_stability(item, meshes, material, "assembly", used, problems))
    report.update(rows)
    report["materials"] = {k: m.public() for k, m in used.items()}
    return _done(report, t0, save)


def _done(report: dict[str, Any], t0: float, save: Path | None = None) -> dict[str, Any]:
    report["ok"] = not report["problems"]
    report["seconds"] = round(time.perf_counter() - t0, 1)
    report["cpu_seconds"] = round(_cpu(), 1)
    _write(report, save)
    return report


def _write(report: dict[str, Any], save: Path | None) -> None:
    if save is None:
        return
    temporary = save.with_suffix(".tmp")  # a kill in the middle leaves the last whole one
    temporary.write_text(
        json.dumps(report, default=lambda v: v.tolist() if hasattr(v, "tolist") else float(v)),
        encoding="utf-8",
    )
    temporary.replace(save)


def _material(name: str | None) -> Material | None:
    return MATERIALS.get(name) if name else None


class _Context:
    """What the flexes and the assembly's loads ask of an instance."""

    def __init__(self, spec, instances, part_specs, parts, material_of):
        self.spec = spec
        self.instances = instances
        self.part_specs = part_specs
        self.exports = {p["part"]: p["export"] for p in parts}
        self.material_of = material_of
        self.pictures: tuple[Path, bool] | None = None
        self._aligned: dict[str, np.ndarray | None] = {}

    def printed(self, inst: dict[str, Any]) -> bool:
        return inst["part"] != "external" and not inst["part"].startswith("standard:")

    def material(self, name: str) -> Material | None:
        inst = self.instances[name]
        return self.material_of((self.part_specs.get(inst["part"]) or {}).get("material"))

    def print_z(self, name: str, moved: np.ndarray) -> np.ndarray | None:
        """The print's Z in the frame `moved` takes the instance to, or None when it cannot be
        told (the tension along Z is then judged on the largest tension)."""
        rotation = np.asarray(moved)[:3, :3]
        if self.spec.get("print_in_place"):
            pose = np.eye(3)
            for matrix in self._print_pose(name):
                pose = matrix[:3, :3] @ pose
            return rotation @ pose.T @ np.array([0.0, 0.0, 1.0])
        if name not in self._aligned:
            self._aligned[name] = self._alignment(name)
        aligned = self._aligned[name]
        return None if aligned is None else rotation @ aligned @ np.array([0.0, 0.0, 1.0])

    def _print_pose(self, name: str) -> list[np.ndarray]:
        from cadverify.cadcheck.assembly import _poses

        by_name = {m["name"]: m for m in self.spec.get("motions") or []}
        out = []
        for step in self.spec.get("print_pose") or []:
            moved = _poses(by_name[step["motion"]], step["value"])
            if name in moved:
                out.append(moved[name])
        return out

    def _alignment(self, name: str) -> np.ndarray | None:
        """The rotation from the part, as it prints, to the instance, as the assembly places it."""
        inst = self.instances[name]
        export = self.exports.get(inst["part"])
        if not export or not export.get("path") or not inst.get("stl"):
            return None
        return alignment(load_exact(export["path"]), load_exact(inst["stl"]))


def alignment(part: trimesh.Trimesh, moved: trimesh.Trimesh) -> np.ndarray | None:
    """The rotation that takes `part` onto `moved`, from their principal axes: the sign choice
    whose vertices land on the other's. None when no choice does (a shape whose axes are not
    defined, such as a cube). A shape round about one axis leaves that axis defined, and it is
    what a layer's direction needs."""

    def frame(mesh):
        return mesh.center_mass, np.linalg.eigh(mesh.moment_inertia)[1]

    a_center, a_axes = frame(part)
    b_center, b_axes = frame(moved)
    tree = cKDTree(moved.vertices)
    size = float(np.linalg.norm(moved.extents))
    best, best_distance = None, math.inf
    for signs in ((1, 1, 1), (1, -1, -1), (-1, 1, -1), (-1, -1, 1)):
        flip = np.diag(signs).astype(float)
        for candidate in (b_axes @ flip @ a_axes.T, -b_axes @ flip @ a_axes.T):
            if np.linalg.det(candidate) < 0:  # a mirror image passes G3; turn it into a rotation
                candidate = candidate @ np.diag((1.0, 1.0, -1.0))
            placed = (part.vertices - a_center) @ candidate.T + b_center
            distance = float(tree.query(placed)[0].mean())
            if distance < best_distance:
                best, best_distance = candidate, distance
    return best if best_distance <= 0.02 * size else None


# ---- flex -------------------------------------------------------------------------------------


def _declared_flexes(assembly: dict[str, Any]) -> list[dict[str, Any]]:
    """Each flex that met what it presses on, with how often it bends and where it is deepest."""
    out = []
    for motion in assembly.get("motions") or []:
        for flex in motion.get("flex") or []:
            out.append({**flex, "use": REPEATED, "where": f"motion {motion['name']}"})
    for step in assembly.get("assembly_steps") or []:
        for key in ("flex", "turn_flex"):
            for flex in step.get(key) or []:
                out.append({**flex, "use": ONCE, "where": f"assembly step {step['step']}"})
    return [f for f in out if f.get("poses") and f.get("overlap_stl")]


def _flex(
    flex: dict[str, Any], context: _Context, used: dict, problems: list[str]
) -> dict[str, Any]:
    label = f"{flex['where']}, flex {flex['a']} / {flex['b']}"
    row: dict[str, Any] = {
        "where": flex["where"],
        "a": flex["a"],
        "b": flex["b"],
        "depth_mm": flex["depth_mm"],
        "at": flex.get("at"),
        "use": flex["use"],
        "force_target_n": flex.get("force_n"),
        "ok": False,
    }
    overlap = load_exact(flex["overlap_stl"])
    moved = flex.get("matrices") or {}
    bodies = []
    for name in (flex["a"], flex["b"]):
        inst = context.instances[name]
        if not context.printed(inst):
            continue
        material = context.material(name)
        if material is None:
            problems.append(
                f"{label}: {name} has no material: declare it in the spec "
                f'(["material", "PLA"], one of {sorted(MATERIALS)})'
            )
            return row
        used[material.name] = material
        matrix = np.asarray(moved.get(name, np.eye(4)), float)
        mesh = load_exact(inst["stl"])
        mesh.apply_transform(matrix)
        bodies.append((name, mesh, material, context.print_z(name, matrix)))
    if not bodies:
        problems.append(f"{label}: neither of the two is printed, so nothing here bends")
        return row
    try:
        solved = [
            (n, _contact(mesh, overlap, material), material, up) for n, mesh, material, up in bodies
        ]
        # Series; then each part that matters refined, and the force again.
        total = sum(s[1]["compliance"] for s in solved)
        force = flex["depth_mm"] / total
        for _name, unit, material, up in solved:
            limit = _limit(flex["use"], material)
            share = unit["compliance"] / total
            strain = fea.peaks(unit["unit"], force, material.bending_modulus_mpa, _up(up))
            # A stiff part far under its limit moves nothing the verdict depends on.
            if share >= WORTH_REFINING or strain.get("strain_pct", 0) >= MARGIN * 100 * limit:
                _refine(unit, material, _up(up), overlap)
        total = sum(s[1]["compliance"] for s in solved)
        force = flex["depth_mm"] / total
    except fea.MeshingError as exc:
        problems.append(f"{label}: could not be computed, so it is not verified: {exc}")
        row["error"] = str(exc)
        return row
    row["force_n"] = round(force, 2)
    row["compliance_mm_per_n"] = round(total, 5)
    row["parts"] = []
    fine = True
    for name, unit, material, up in solved:
        limit = _limit(flex["use"], material)
        part = _part_row(name, unit, force, material, limit, up)
        _picture(part, unit["unit"], force, material, label, context.pictures)
        row["parts"].append(part)
        fine &= _judge(label, part, limit, material, flex["use"], problems)
    moved = max((p.get("mesh_change") or {}).get("compliance", 0.0) for p in row["parts"])
    row["force_moved"] = round(moved, 3)
    target = flex.get("force_n")
    if target and not target[0] <= force <= target[1]:
        fine = False
        problems.append(
            f"{label}: it takes {force:.1f} N to ride over, and the spec asks for {target[0]:g} "
            f"to {target[1]:g} N: {_softer(force, target)}"
        )
    elif target and moved > SETTLED and not _inside(force, moved, target):
        fine = False
        problems.append(
            f"{label}: it takes {force:.1f} N to ride over, but a finer mesh moved that by "
            f"{moved:.0%}, which could take it out of the {target[0]:g} to {target[1]:g} N the "
            "spec asks for, so it is not verified"
        )
    row["ok"] = fine
    return row


def _inside(value: float, moved: float, band: list[float]) -> bool:
    return band[0] <= value * (1 - moved) and value * (1 + moved) <= band[1]


def _softer(force: float, target: list[float]) -> str:
    if force > target[1]:
        return "make it softer (a longer or thinner arm) or shallower"
    return "make it stiffer (a shorter or thicker arm) or deeper"


def _limit(use: str, material: Material) -> float:
    return material.strain_once if use == ONCE else material.strain_repeated


def _cpu() -> float:
    """The CPU seconds of this process and of what it waited for: gmsh runs in a child."""
    return sum(os.times()[:4])


def _up(up: np.ndarray | None) -> np.ndarray:
    return np.array([0.0, 0.0, 1.0]) if up is None else up


def _contact(mesh: trimesh.Trimesh, overlap: trimesh.Trimesh, material: Material) -> dict:
    """A body's compliance at its contact: cut around it, the cut growing until it settles."""
    from cadverify.cadcheck import section

    solid = section.to_manifold(mesh)
    if solid is None:
        raise fea.MeshingError("the instance is not a closed solid")
    center = overlap.bounds.mean(axis=0)
    half = max(CROP_START_MM, 2.0 * float(overlap.extents.max()))
    previous = None
    while True:
        piece, cut = _crop(solid, center, half, overlap)
        solved = _solve_contact(piece, overlap, center, half if cut else None, material, 1.0)
        solved.update(piece=piece, center=center, half=half if cut else None)
        settled = previous is not None and (
            abs(solved["compliance"] - previous) <= SETTLED * solved["compliance"]
        )
        if not cut or settled:
            solved["crop_mm"] = round(2 * half, 1) if cut else None
            solved["crop_change"] = (
                round(abs(solved["compliance"] - previous) / solved["compliance"], 3)
                if previous is not None
                else None
            )
            return solved
        previous = solved["compliance"]
        half *= 2


def _crop(solid, center, half: float, overlap: trimesh.Trimesh) -> tuple[trimesh.Trimesh, bool]:
    """The pieces of `solid` inside a cube around `center` that touch the overlap, and whether
    the cube cut anything off them."""
    import manifold3d

    from cadverify.cadcheck.assembly import _inside, _Surface, _trimesh

    lo, hi = np.reshape(solid.bounding_box(), (2, 3))
    box_lo, box_hi = center - half, center + half
    whole = bool(np.all(lo >= box_lo) and np.all(hi <= box_hi))
    inner = (
        solid
        if whole
        else solid ^ manifold3d.Manifold.cube(tuple(box_hi - box_lo)).translate(tuple(box_lo))
    )
    pieces = inner.decompose()
    margin = 1.0
    low, high = overlap.bounds[0] - margin, overlap.bounds[1] + margin
    kept = []
    for piece in pieces:
        mesh = _trimesh(piece)
        triangles = _inside(mesh.triangles, low, high)
        if not len(triangles):
            continue
        distance, _ = _Surface(triangles, low, high).distance(overlap.vertices)
        if float(distance.min()) <= margin:
            kept.append(mesh)
    if not kept:
        raise fea.MeshingError("the overlap touches nothing of the part")
    joined = trimesh.util.concatenate(kept)
    cut = bool(
        np.any(np.isclose(joined.vertices, box_lo, atol=1e-6))
        or np.any(np.isclose(joined.vertices, box_hi, atol=1e-6))
    )
    return joined, cut


def _solve_contact(
    piece: trimesh.Trimesh,
    overlap: trimesh.Trimesh,
    center: np.ndarray,
    half: float | None,
    material: Material,
    scale: float,
    hot: np.ndarray | None = None,
) -> dict[str, Any]:
    from cadverify.cadcheck.assembly import _Surface

    area = max(float(overlap.area) / 2, 1e-3)
    near = float(np.clip(math.sqrt(area) / 5, fea.HOT_SIZE_MM, 0.6))
    tets = fea.filled(piece, overlap.vertices, near, scale, hot)
    margin = 2.0
    surface = _Surface(overlap.triangles, overlap.bounds[0] - margin, overlap.bounds[1] + margin)

    def loaded(centers: np.ndarray, reach: float) -> np.ndarray:
        inside = np.all(
            (centers >= overlap.bounds[0] - margin) & (centers <= overlap.bounds[1] + margin),
            axis=1,
        )
        out = np.zeros(len(centers), bool)
        if inside.any():
            out[inside] = surface.distance(centers[inside])[0] <= reach
        return out

    def load_facets(centers: np.ndarray) -> np.ndarray:
        for reach in (0.1, near / 2, near, 2 * near):
            found = loaded(centers, reach)
            if found.sum() >= 3:
                return found
        return found

    if half is not None:
        low, high = center - half, center + half

        def fixed(centers: np.ndarray) -> np.ndarray:
            return np.any(
                np.isclose(centers, low, atol=1e-3) | np.isclose(centers, high, atol=1e-3), axis=1
            )

    else:
        # Nothing to cut: it is held where it is farthest from what presses on it, measured from
        # the contact itself. The center of a ring of lugs is on nothing, and everything around
        # it, the lugs too, would count as far.
        contact = cKDTree(np.vstack([overlap.vertices, overlap.triangles_center]))
        reach = float(contact.query(piece.vertices)[0].max())

        def fixed(centers: np.ndarray) -> np.ndarray:
            return contact.query(centers)[0] >= FAR_FIXED * reach

    unit = fea.solve_unit(tets, material.bending_modulus_mpa, POISSON, load_facets, fixed)
    if unit.compliance <= 0:
        raise fea.MeshingError("the contact moved away from its load: its surface is not a contact")
    return {"unit": unit, "compliance": unit.compliance}


def _refine(solved: dict, material: Material, up: np.ndarray, overlap) -> None:
    """The same cut, finer around where it peaks, twice: the second is the result, and how far it
    moved from the first says whether it settled. A peak on a sharp inner corner is a value only
    over a length (cadcheck.fea), and it takes a mesh finer than that length around it."""
    modulus = material.bending_modulus_mpa
    hot = fea.hot_spots(solved["unit"], up)
    args = (solved["piece"], overlap, solved["center"], solved["half"], material)
    first = _solve_contact(*args, 1.0, hot)
    hot = np.vstack([hot, fea.hot_spots(first["unit"], up)])
    finer = _solve_contact(*args, REFINE, hot)
    solved["mesh_change"] = _change(first["unit"], finer["unit"], modulus, up)
    solved.update(unit=finer["unit"], compliance=finer["compliance"])


def _change(coarse: fea.Unit, fine: fea.Unit, modulus: float, up: np.ndarray) -> dict[str, float]:
    """How far a finer mesh moved the compliance and the two peaks, each a fraction of the finer."""
    low, high = fea.peaks(coarse, 1.0, modulus, up), fea.peaks(fine, 1.0, modulus, up)

    def moved(key: str) -> float:
        return round(abs(high[key] - low[key]) / max(high[key], 1e-9), 3)

    return {
        "compliance": round(abs(fine.compliance - coarse.compliance) / abs(fine.compliance), 3),
        "strain": moved("strain_pct"),
        "z_strain": moved("z_strain_pct"),
    }


def _part_row(
    name: str, solved: dict, force: float, material: Material, limit: float, up
) -> dict[str, Any]:
    unit = solved["unit"]
    peak = fea.peaks(unit, force, material.bending_modulus_mpa, _up(up))
    z_strain = peak.get("z_strain_pct", 0.0)
    z_at = peak.get("z_at")
    if up is None:  # the print's Z is not known: the worst it could be
        z_strain, z_at = peak.get("strain_pct", 0.0), peak.get("at")
    return {
        "instance": name,
        "material": material.name,
        "compliance_mm_per_n": round(solved["compliance"], 5),
        "deflection_mm": round(force * solved["compliance"], 3),
        "strain_pct": peak.get("strain_pct", 0.0),
        "stress_mpa": peak.get("tension_mpa", 0.0),
        "limit_pct": round(100 * limit, 2),
        "at": peak.get("at"),
        "z_strain_pct": z_strain,
        "z_limit_pct": round(100 * limit * material.z_factor, 2),
        "z_at": z_at,
        "print_z": None if up is None else np.round(up, 3).tolist(),
        "tets": unit.tets,
        "unknowns": int(unit.unknowns),
        "mesh": unit.method,
        "crop_mm": solved.get("crop_mm"),
        "crop_change": solved.get("crop_change"),
        "mesh_change": solved.get("mesh_change"),
    }


def _judge(
    label: str,
    part: dict,
    limit: float,
    material: Material,
    use: str,
    problems: list[str],
    force_follows: bool = True,
) -> bool:
    """The limits and the settling of one part of a flex or a load; its problems, in `problems`."""
    fine = True
    name = part["instance"]
    how = "what bends a few times" if use == ONCE else "what bends again and again or stays loaded"
    if part["strain_pct"] > part["limit_pct"]:
        fine = False
        problems.append(
            f"{label}: {name} reaches {part['strain_pct']:.2f}% strain at {part['at']}, past the "
            f"{part['limit_pct']:.2f}% of {material.name} for {how}: it takes a longer or "
            "thinner arm, less depth, or a material that bends more"
        )
    if part["z_strain_pct"] > part["z_limit_pct"]:
        fine = False
        problems.append(
            f"{label}: {name} pulls its layers apart at {part['z_strain_pct']:.2f}% at "
            f"{part['z_at']}, past the {part['z_limit_pct']:.2f}% of {material.name} between "
            "layers: bend it along the layers, or print it another way up"
        )
    change = part.get("mesh_change") or {}
    if _unsettled(part, change, force_follows):
        fine = False
        problems.append(
            f"{label}: the numbers of {name} did not settle on a finer mesh (compliance moved "
            f"{change['compliance']:.0%}, strain {change['strain']:.0%}, along Z "
            f"{change['z_strain']:.0%}), so they are not verified"
        )
    return fine


def _picture(
    part: dict, unit: fea.Unit, force: float, material: Material, title: str, where
) -> None:
    """The part with its strain in color and its peak marked, as a PNG. A picture that cannot be
    drawn is not a finding: the numbers are in the row."""
    if where is None or part.get("at") is None:
        return
    out_dir, embed = where
    try:
        png = out_dir / f"{_slug(title + part['instance'])}.png"
        strain = fea.strain_map(unit, force, material.bending_modulus_mpa)
        fea.draw_strain(unit, strain, part["limit_pct"] / 100, part["at"], png, _caption(part))
    except Exception as exc:  # drawing is for the reader, the verdict does not depend on it
        part["picture_error"] = f"{type(exc).__name__}: {exc}"
        return
    part["picture"] = str(png)
    if embed:
        part["picture_png"] = base64.b64encode(png.read_bytes()).decode()


def _caption(part: dict) -> str:
    return (
        f"{part['instance']}: {part['strain_pct']:.2f}% at {part['at']}, "
        f"limit {part['limit_pct']:.2f}% (red at the limit or past it)"
    )


def _slug(text: str) -> str:
    keep = "".join(c if c.isalnum() else "_" for c in text)[:40]
    return f"{keep}-{hashlib.sha256(text.encode()).hexdigest()[:4]}"


def _unsettled(part: dict, change: dict[str, float], force_follows: bool) -> bool:
    """Whether a finer mesh moved a peak enough that its verdict could change. Under a flex the
    force comes from the compliance and the peak from the force, so the two movements add up; under
    a load the force is given. What moved and no verdict depends on stays in `mesh_change`."""
    through = change.get("compliance", 0.0) if force_follows else 0.0
    for moved, value, limit in (
        (change.get("strain", 0.0), part["strain_pct"], part["limit_pct"]),
        (change.get("z_strain", 0.0), part["z_strain_pct"], part["z_limit_pct"]),
    ):
        total = (1 + moved) * (1 + through) - 1  # a fraction of the finer value
        decided = value * (1 + total) < limit or value * (1 - total) > limit
        if total > SETTLED and not decided:
            return True
    return False


# ---- loads ------------------------------------------------------------------------------------


def _load(
    load: dict[str, Any],
    mesh: trimesh.Trimesh,
    material: Material | None,
    up: np.ndarray | None,
    label: str,
    used: dict,
    problems: list[str],
    pictures: tuple[Path, bool] | None = None,
) -> dict[str, Any]:
    name = f"load {load['name']} on {label}"
    row: dict[str, Any] = {"name": load["name"], "on": label, "ok": False}
    if material is None:
        problems.append(
            f"{name}: no material: declare it in the spec "
            f'(["material", "PLA"], one of {sorted(MATERIALS)})'
        )
        return row
    used[material.name] = material
    force = np.asarray(load["force"], float)
    magnitude = float(np.linalg.norm(force))
    direction = force / magnitude
    box, held = np.asarray(load["box"], float), np.asarray(load["fixed"], float)

    def inside(centers: np.ndarray, zone: np.ndarray) -> np.ndarray:
        return np.all((centers >= zone[0] - 1e-6) & (centers <= zone[1] + 1e-6), axis=1)

    points = mesh.vertices[inside(mesh.vertices, box)]
    if not len(points):
        points = mesh.triangles_center[inside(mesh.triangles_center, box)]
    modulus = material.bending_modulus_mpa
    z = _up(up)

    def solve(scale: float, hot: np.ndarray | None) -> fea.Unit:
        tets = fea.filled(mesh, points if len(points) else None, 1.0, scale, hot)
        return fea.solve_unit(
            tets,
            modulus,
            POISSON,
            lambda c: inside(c, box),
            lambda c: inside(c, held),
            direction=direction,
        )

    try:
        hot = fea.hot_spots(solve(1.0, None), z)
        coarse = solve(1.0, hot)
        unit = solve(REFINE, np.vstack([hot, fea.hot_spots(coarse, z)]))
    except fea.MeshingError as exc:
        problems.append(f"{name}: could not be computed, so it is not verified: {exc}")
        row["error"] = str(exc)
        return row
    solved = {
        "unit": unit,
        "compliance": unit.compliance,
        "mesh_change": _change(coarse, unit, modulus, z),
    }
    limit = material.strain_repeated
    part = _part_row(label, solved, magnitude, material, limit, up)
    part["largest_mm"] = round(unit.largest * magnitude, 3)
    _picture(part, unit, magnitude, material, f"load {load['name']}", pictures)
    row.update(part)
    row["force_n"] = round(magnitude, 2)
    row["deflection_mm"] = round(unit.compliance * magnitude, 3)
    fine = _judge(
        name, {**part, "instance": label}, limit, material, REPEATED, problems, force_follows=False
    )
    bound = load.get("max_deflection_mm")
    row["max_deflection_mm"] = bound
    moved = solved["mesh_change"].get("compliance", 0.0)
    if bound is not None and part["largest_mm"] > bound:
        fine = False
        problems.append(
            f"{name}: it moves {part['largest_mm']:.2f} mm under {magnitude:.1f} N, past the "
            f"{bound:g} mm the spec allows: it takes more material where it bends"
        )
    elif bound is not None and moved > SETTLED and part["largest_mm"] * (1 + moved) > bound:
        fine = False
        problems.append(
            f"{name}: it moves {part['largest_mm']:.2f} mm under {magnitude:.1f} N, but a finer "
            f"mesh moved that by {moved:.0%}, which could take it past the {bound:g} mm the spec "
            "allows, so it is not verified"
        )
    row["ok"] = fine
    return row


# ---- stability --------------------------------------------------------------------------------


def _stability(
    item: dict[str, Any],
    meshes: list[trimesh.Trimesh],
    material: Material | None,
    label: str,
    used: dict,
    problems: list[str],
) -> dict[str, Any]:
    name = f"stability {item['name']} of {label}"
    row: dict[str, Any] = {"name": item["name"], "on": label, "ok": False}
    if material is None:
        problems.append(
            f"{name}: no material: declare it in the spec "
            f'(["material", "PLA"], one of {sorted(MATERIALS)})'
        )
        return row
    if not meshes:
        problems.append(f"{name}: there is no printed part to measure")
        return row
    used[material.name] = material
    from cadverify.cadcheck import section

    down = np.asarray(item["down"], float)
    down = down / np.linalg.norm(down)
    basis = section.frame(down)  # rows u, v and the direction down
    every = np.vstack([m.vertices for m in meshes])
    lowest = float((every @ basis[2]).max())
    resting = every[every @ basis[2] >= lowest - SUPPORT_TOLERANCE_MM]
    polygon = shapely.MultiPoint(resting @ basis[:2].T).convex_hull
    volume = sum(float(m.volume) for m in meshes)
    center = sum(float(m.volume) * np.asarray(m.center_mass) for m in meshes) / volume
    solid_kg = volume * material.density_g_cm3 / 1e6
    row.update(
        mass_kg_solid=round(solid_kg, 4),
        center_of_mass=np.round(center, 2).tolist(),
        support_area_mm2=round(float(polygon.area), 1),
        carries=item["carries"],
    )
    worst: dict[str, float] | None = None
    for fill in FILLS:
        masses = [fill * solid_kg] + [c["kg"] for c in item["carries"]]
        points = [center] + [np.asarray(c["at"], float) for c in item["carries"]]
        total = sum(masses)
        com = sum(w * p for w, p in zip(masses, points, strict=True)) / total
        spot = shapely.Point(*(com @ basis[:2].T))
        margin = float(polygon.exterior.distance(spot))
        if not polygon.contains(spot):
            margin = -margin
        height = max(lowest - float(com @ basis[2]), 1e-6)
        tilt = math.degrees(math.atan2(max(margin, 0.0), height))
        if worst is None or margin < worst["margin_mm"]:
            worst = {
                "fill": fill,
                "margin_mm": round(margin, 2),
                "tilt_deg": round(tilt, 1),
                "height_mm": round(height, 1),
            }
    row["worst"] = worst
    need = item.get("min_tilt_deg", MIN_TILT_DEG)
    row["min_tilt_deg"] = need
    fine = worst["margin_mm"] > 0 and worst["tilt_deg"] >= need
    if not fine:
        problems.append(
            f"{name}: it tips: printed at {worst['fill']:.0%}, its center of gravity with what it "
            f"carries is {worst['margin_mm']} mm inside what it stands on ({worst['tilt_deg']}° "
            f"before it tips, {need:g}° asked): a wider base, or weight lower down"
        )
    row["ok"] = fine
    return row
