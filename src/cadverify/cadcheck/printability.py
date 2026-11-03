"""printability_report: overhangs by face normal in the print orientation, bridges, and bed fit.

The mesh is taken as exported: +Z is the build direction and the lowest faces rest on the bed.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import shapely
import trimesh

from cadverify.cadcheck.mesh import load_exact
from cadverify.cadcheck.section import polygons_from_segments

# Bambu Lab A1 build volume (bambulab.com/en/a1, "Build Volume 256 × 256 × 256 mm³").
PRINTERS = {"bambu_a1": (256.0, 256.0, 256.0)}
MAX_OVERHANG_DEG = 45.0
# Faces within this many degrees of the limit count as at the limit: a 90° countersink is
# exactly 45° and must not flicker in and out of the report with floating point noise.
ANGLE_TOLERANCE_DEG = 0.1
BED_TOLERANCE_MM = 0.01
DECLARED_TOLERANCE_MM = 0.5
MAX_ZONES = 25
# A downward face steeper than 60° rests on little of the layer under it, and the A1's slicer
# supports it by default (Bambu Studio's threshold angle, 30° to the horizontal). Without support
# it holds like a bridge, in the air from the material under its lowest edge; within 1° of flat,
# it is a flat ceiling.
BRIDGE_DEG = 60.0
FLAT_DEG = 89.0
# The longest bridge that prints clean with a 0.4 mm nozzle. A quick FDM design guide gives 10 mm
# as the longest unsupported bridge (Xometry); Protolabs Network, about 5 mm without sagging.
# Every point of a bridge is then at most half of it from what holds it.
MAX_BRIDGE_MM = 10.0
# What holds a ceiling: the material from half a layer (0.2 mm) to START_GAP_MM under its lowest
# point, which holds it through the gap the way a support does; on the bed, its first layer.
BRIDGE_BELOW_MM = 0.1
# A ceiling none of whose points is this close to that section has nothing to start from.
BRIDGE_ANCHOR_MM = 0.5
# A flat strip narrower than two 0.4 mm lines is not judged: the lowest facet of a round pin
# lies flat or not depending on its $fn, and droops into the clearance under it either way.
BRIDGE_MIN_WIDTH_MM = 0.8
BRIDGE_GRID_MM = 0.25  # finer for small ceilings: at most BRIDGE_POINTS sample points
BRIDGE_POINTS = 100_000
# A body that does not rest on the bed starts printing at its lowest layers (START_BAND_MM, two
# layers). It may start over material up to START_GAP_MM under them, drooping into a print in
# place clearance (1 mm at most); farther, or over nothing, it starts in the air.
START_BAND_MM = 0.4
START_GAP_MM = 1.0
START_STEP_MM = 0.1


def printability_report(
    path: str | Path,
    allowed: list[dict[str, Any]] | None = None,
    printer: str = "bambu_a1",
    max_overhang_deg: float = MAX_OVERHANG_DEG,
) -> dict[str, Any]:
    """The printability of the STL at `path` (mesh_printability)."""
    return mesh_printability(load_exact(path), allowed, printer, max_overhang_deg)


def mesh_printability(
    mesh: trimesh.Trimesh,
    allowed: list[dict[str, Any]] | None = None,
    printer: str = "bambu_a1",
    max_overhang_deg: float = MAX_OVERHANG_DEG,
) -> dict[str, Any]:
    """Overhang zones steeper than `max_overhang_deg` from vertical, and whether the part fits.

    - The overhang angle of a downward face is measured from vertical: a wall is 0°, a flat
      ceiling 90°. Faces resting on the bed (at the lowest z, facing straight down) are the base.
    - Overhang faces connected through edges form a zone. A zone is `declared` when it lies
      inside one of the `allowed` boxes ([{"name", "bounds"}], from the spec) with 0.5 mm slack.
    - A zone's faces steeper than 60° print as a bridge (`flat` within 1° of flat). Each
      connected piece of them is measured against the material from half a layer to 1 mm under
      its lowest point (the mesh's sections there): `farthest_mm`, the farthest any of its
      points is from that material, seen from above, so a bridge over it spans at least twice
      that (`bridge_mm`), whatever direction it is laid in; or `floating`, when no point of it
      is within 0.5 mm of that material. A zone keeps its worst piece under `bridge`; pieces
      narrower than 0.8 mm (the widest circle that fits in them) are left out.
    - `in_the_air`: every body (a connected piece of the mesh) that does not rest on the bed and
      has no other body under its lowest two layers within 1 mm: it starts printing in the air,
      whatever the angle of its faces (a lid printed standing, hung from its hinge).
    - `fits_bed` compares the part's size with the printer's build volume.
    - `allowed_coverage`: the share of the part's surface inside the allowed boxes (faces whose
      center is in one, with the same slack), in all and per box. A box that covers almost the
      whole part exempts every overhang it may have: one session declared 91 % and 100 %.
    """
    bed = PRINTERS[printer]
    if len(mesh.faces) == 0:
        return {"ok": False, "error": "empty mesh"}
    allowed = allowed or []
    areas = mesh.area_faces
    overhang, angle, on_bed = overhang_faces(mesh, max_overhang_deg)
    zones = overhang_zones(mesh, overhang, angle, allowed)
    for zone in zones:
        zone["bridge"] = bridge(mesh, zone["_faces"][angle[zone["_faces"]] >= BRIDGE_DEG], angle)
    undeclared = [z for z in zones if not z["declared"]]

    size = mesh.extents
    fits = bool(np.all(size <= np.array(bed) + 1e-6))
    return {
        "ok": True,
        "printer": printer,
        "bed_mm": list(bed),
        "size": np.round(size, 3).tolist(),
        "fits_bed": fits,
        "bed_margin_mm": np.round((np.array(bed) - size) / [2, 2, 1], 2).tolist(),
        "z_min": round(float(mesh.bounds[0][2]), 3),
        "base_area_mm2": round(float(areas[on_bed].sum()), 1),
        "max_overhang_deg": max_overhang_deg,
        "bridge_deg": BRIDGE_DEG,
        "max_bridge_mm": MAX_BRIDGE_MM,
        "overhang_area_mm2": round(float(areas[overhang].sum()), 2),
        "zones_total": len(zones),
        "zones_undeclared": len(undeclared),
        "undeclared_area_mm2": round(sum(z["area_mm2"] for z in undeclared), 2),
        "zones": _cap(zones),
        "in_the_air": in_the_air(mesh),
        "allowed_coverage": allowed_coverage(mesh, allowed),
    }


def allowed_coverage(mesh: trimesh.Trimesh, allowed: list[dict[str, Any]]) -> dict[str, Any]:
    areas, centers = mesh.area_faces, mesh.triangles_center
    total = float(areas.sum()) or 1.0
    union = np.zeros(len(areas), bool)
    per_box = []
    for box in allowed:
        lo, hi = np.array(box["bounds"]) + [[-DECLARED_TOLERANCE_MM], [DECLARED_TOLERANCE_MM]]
        inside = np.all((centers >= lo) & (centers <= hi), axis=1)
        union |= inside
        per_box.append({"name": box["name"], "share": round(float(areas[inside].sum()) / total, 4)})
    return {"share": round(float(areas[union].sum()) / total, 4), "per_box": per_box}


def overhang_faces(
    mesh: trimesh.Trimesh, max_overhang_deg: float = MAX_OVERHANG_DEG, z_min: float | None = None
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Per face: steeper than the limit (and not resting on the bed), the overhang angle and
    whether it rests on the bed. `z_min` is the bed height (default: the mesh's lowest z)."""
    normals, areas = mesh.face_normals, mesh.area_faces
    z_min = float(mesh.bounds[0][2]) if z_min is None else z_min
    corner_z = mesh.vertices[mesh.faces][:, :, 2]
    down = np.clip(-normals[:, 2], -1.0, 1.0)
    on_bed = (down > np.cos(np.radians(1.0))) & np.all(corner_z <= z_min + BED_TOLERANCE_MM, axis=1)
    angle = 90.0 - np.degrees(np.arccos(down))  # 90 = flat ceiling, 0 = wall, < 0 = faces up
    overhang = (angle > max_overhang_deg + ANGLE_TOLERANCE_DEG) & ~on_bed & (areas > 0)
    return overhang, angle, on_bed


def overhang_zones(
    mesh: trimesh.Trimesh, overhang: np.ndarray, angle: np.ndarray, allowed: list[dict]
) -> list[dict[str, Any]]:
    """Connected overhang faces as zones, largest first, with ids v1, v2... Each zone also
    keeps its face indices under "_faces" (dropped from the report)."""
    areas = mesh.area_faces
    zones = []
    for faces in _zones(mesh, overhang):
        corners = mesh.vertices[mesh.faces[faces]].reshape(-1, 3)
        bounds = np.array([corners.min(axis=0), corners.max(axis=0)])
        match = next((a["name"] for a in allowed if _inside(bounds, a["bounds"])), None)
        zones.append(
            {
                "area_mm2": round(float(areas[faces].sum()), 2),
                "max_angle_deg": round(float(angle[faces].max()), 1),
                "bounds": np.round(bounds, 2).tolist(),
                "faces": len(faces),
                "declared": match is not None,
                "declared_as": match,
                "_faces": faces,
            }
        )
    zones.sort(key=lambda z: -z["area_mm2"])
    for i, zone in enumerate(zones, 1):
        zone["id"] = f"v{i}"
    return zones


def bridge(mesh: trimesh.Trimesh, faces: np.ndarray, angle: np.ndarray) -> dict[str, Any] | None:
    """The worst piece of `faces` as a bridge (mesh_printability), None without one. `angle` is
    the overhang angle of every face of the mesh."""
    selected = np.zeros(len(mesh.faces), bool)
    selected[faces] = True
    bed = float(mesh.bounds[0][2])
    worst = None
    for piece in _zones(mesh, selected):
        triangles = mesh.vertices[mesh.faces[piece]]
        ceiling = shapely.union_all(shapely.polygons(triangles[:, :, :2])).buffer(0)
        if ceiling.is_empty or ceiling.area <= 0:
            continue
        radius = shapely.maximum_inscribed_circle(ceiling, BRIDGE_MIN_WIDTH_MM / 20).length
        if 2 * radius < BRIDGE_MIN_WIDTH_MM:
            continue
        low, high = float(triangles[:, :, 2].min()), float(triangles[:, :, 2].max())
        below = _under(mesh, low, bed)
        row: dict[str, Any] = {
            "z": round(low, 2),
            "z_top": round(high, 2),
            "flat": bool(angle[piece].min() >= FLAT_DEG),
            "area_mm2": round(float(ceiling.area), 1),
            "bounds_xy": np.round(np.reshape(ceiling.bounds, (2, 2)), 2).tolist(),
        }
        if below.is_empty or below.distance(ceiling) > BRIDGE_ANCHOR_MM:
            row.update(floating=True, farthest_mm=None, bridge_mm=None)
        else:
            far = float(shapely.distance(_samples(ceiling), below).max())
            row.update(floating=False, farthest_mm=round(far, 2), bridge_mm=round(2 * far, 1))
        if worst is None or _worse(row, worst):
            worst = row
    return worst


def in_the_air(mesh: trimesh.Trimesh) -> list[dict[str, Any]]:
    """The bodies that start printing in the air (mesh_printability)."""
    bodies = mesh.split(only_watertight=False)
    if len(bodies) < 2:
        return []  # one body: its lowest point is the bed
    bed = float(mesh.bounds[0][2])
    out = []
    for i, body in enumerate(bodies):
        low = float(body.bounds[0][2])
        if low <= bed + BED_TOLERANCE_MM:
            continue
        levels = (low + 0.05, low + START_BAND_MM / 2, low + START_BAND_MM)
        start = shapely.union_all([_section(body, z) for z in levels])
        if start.is_empty:
            lowest = body.vertices[body.vertices[:, 2] <= low + START_BAND_MM]
            start = shapely.multipoints(lowest[:, :2]).buffer(START_STEP_MM)
        others = trimesh.util.concatenate([b for j, b in enumerate(bodies) if j != i])
        depths = np.arange(START_STEP_MM, START_GAP_MM + 1e-9, START_STEP_MM)
        if not any(_section(others, low - d).intersection(start).area > 1e-6 for d in depths):
            out.append(
                {
                    "z": round(low, 2),
                    "bounds": np.round(body.bounds, 2).tolist(),
                    "volume_mm3": round(float(abs(body.volume)), 1),
                }
            )
    return out


def _under(mesh: trimesh.Trimesh, z: float, bed: float):
    """The material that can hold a face whose lowest point is at height z (BRIDGE_BELOW_MM)."""
    depths = np.arange(BRIDGE_BELOW_MM, START_GAP_MM + 1e-9, START_STEP_MM)
    levels = sorted({round(max(z - d, bed + BRIDGE_BELOW_MM / 2), 6) for d in depths})
    return shapely.union_all([_section(mesh, level) for level in levels])


def _section(mesh: trimesh.Trimesh, z: float):
    """The mesh's section at height z, as one shapely geometry."""
    lines = trimesh.intersections.mesh_plane(mesh, [0, 0, 1], [0, 0, z])
    segments = np.asarray(lines).reshape(-1, 2, 3)[:, :, :2]
    return shapely.union_all(polygons_from_segments(segments)[0])


def _samples(ceiling) -> np.ndarray:
    """Points of the ceiling: a grid inside it and the vertices of its outline."""
    lo_x, lo_y, hi_x, hi_y = ceiling.bounds
    step = max(BRIDGE_GRID_MM, float(np.sqrt((hi_x - lo_x) * (hi_y - lo_y) / BRIDGE_POINTS)))
    x, y = np.meshgrid(np.arange(lo_x, hi_x + step, step), np.arange(lo_y, hi_y + step, step))
    x, y = x.ravel(), y.ravel()
    inside = shapely.contains_xy(ceiling, x, y)
    outline = shapely.get_coordinates(shapely.boundary(ceiling))
    grid = np.column_stack([x[inside], y[inside]])
    return shapely.points(np.vstack([grid, outline]))


def _worse(a: dict[str, Any], b: dict[str, Any]) -> bool:
    if a["floating"] != b["floating"]:
        return a["floating"]
    return (a["bridge_mm"] or 0.0) > (b["bridge_mm"] or 0.0)


def _zones(mesh: trimesh.Trimesh, selected: np.ndarray) -> list[np.ndarray]:
    """Connected components of the selected faces through shared edges."""
    index = np.flatnonzero(selected)
    if len(index) == 0:
        return []
    pairs = mesh.face_adjacency
    pairs = pairs[selected[pairs[:, 0]] & selected[pairs[:, 1]]]
    # Without a shared edge, trimesh returns each face as a list, not an array.
    components = trimesh.graph.connected_components(pairs, nodes=index, min_len=1)
    return [np.asarray(c, dtype=int) for c in components]


def _inside(bounds: np.ndarray, box: list[list[float]]) -> bool:
    lo, hi = np.array(box) + [[-DECLARED_TOLERANCE_MM], [DECLARED_TOLERANCE_MM]]
    return bool(np.all(bounds[0] >= lo) and np.all(bounds[1] <= hi))


def _cap(zones: list[dict]) -> list[dict]:
    """Undeclared zones first, then the largest; the counts above cover all of them."""
    ordered = sorted(zones, key=lambda z: (z["declared"], -z["area_mm2"]))
    return [{k: v for k, v in z.items() if k != "_faces"} for z in ordered[:MAX_ZONES]]
