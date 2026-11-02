"""printability_report: overhangs by face normal in the print orientation, and bed fit.

The mesh is taken as exported: +Z is the build direction and the lowest faces rest on the bed.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import trimesh

from cadverify.cadcheck.mesh import load_exact

# Bambu Lab A1 build volume (bambulab.com/en/a1, "Build Volume 256 × 256 × 256 mm³").
PRINTERS = {"bambu_a1": (256.0, 256.0, 256.0)}
MAX_OVERHANG_DEG = 45.0
# Faces within this many degrees of the limit count as at the limit: a 90° countersink is
# exactly 45° and must not flicker in and out of the report with floating point noise.
ANGLE_TOLERANCE_DEG = 0.1
BED_TOLERANCE_MM = 0.01
DECLARED_TOLERANCE_MM = 0.5
MAX_ZONES = 25


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
        "overhang_area_mm2": round(float(areas[overhang].sum()), 2),
        "zones_total": len(zones),
        "zones_undeclared": len(undeclared),
        "undeclared_area_mm2": round(sum(z["area_mm2"] for z in undeclared), 2),
        "zones": _cap(zones),
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


def _zones(mesh: trimesh.Trimesh, selected: np.ndarray) -> list[np.ndarray]:
    """Connected components of the selected faces through shared edges."""
    index = np.flatnonzero(selected)
    if len(index) == 0:
        return []
    pairs = mesh.face_adjacency
    pairs = pairs[selected[pairs[:, 0]] & selected[pairs[:, 1]]]
    return trimesh.graph.connected_components(pairs, nodes=index, min_len=1)


def _inside(bounds: np.ndarray, box: list[list[float]]) -> bool:
    lo, hi = np.array(box) + [[-DECLARED_TOLERANCE_MM], [DECLARED_TOLERANCE_MM]]
    return bool(np.all(bounds[0] >= lo) and np.all(bounds[1] <= hi))


def _cap(zones: list[dict]) -> list[dict]:
    """Undeclared zones first, then the largest; the counts above cover all of them."""
    ordered = sorted(zones, key=lambda z: (z["declared"], -z["area_mm2"]))
    return [{k: v for k, v in z.items() if k != "_faces"} for z in ordered[:MAX_ZONES]]
