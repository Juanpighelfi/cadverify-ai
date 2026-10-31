"""The details a part announces, measured on its mesh: what the spec's `details` declare.

Each detail names a feature and says how to check it, in the coordinates of the exported part:

- material: a box at least this fraction full (a rib, a boss, a medallion);
- void: a box at least this fraction empty (a slot, a groove, a channel);
- hole: a hole along an axis, from a point outside the part on its axis and a direction into
  it, with the diameter it must have at each depth from its mouth (a countersink, a flared
  entry, a counterbore);
- thickness: the material crossed along a ray, from a point outside the part (a wall, a floor);
- view: a box with a feature no number describes (a texture, a shape); the box must touch the
  part's surface, and the model must look at it up close (agent/gates.py, G8).

A detail exists in the code and not in the mesh more often than it seems: an offset that empties
a profile, a cone sunk below the face it should flare, a chamfer the wrong way round. The
measurement is what the mesh has, not what the code says.
"""

from __future__ import annotations

from typing import Any

import manifold3d
import numpy as np
import shapely
import trimesh

from cadverify.cadcheck import section

KINDS = ("material", "void", "hole", "thickness", "view")
HOLE_TOLERANCE_MM = 0.2  # or HOLE_TOLERANCE_REL of the diameter, whichever is larger
HOLE_TOLERANCE_REL = 0.03
THICKNESS_TOLERANCE_MM = 0.1  # or THICKNESS_TOLERANCE_REL of the thickness
THICKNESS_TOLERANCE_REL = 0.03
MOUTH_INSET_MM = 0.05  # depth 0 is measured this far inside the mouth, as the through holes
SCAN_STEP_MM = 0.1
PROFILE_DEPTHS = (0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 7.5, 10.0, 15.0, 20.0)
MAX_PROFILE = 16


def measure(mesh: trimesh.Trimesh, solid, details: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Each declared detail with what the mesh measures and whether it matches."""
    return [_measure(mesh, solid, d) for d in details]


def _measure(mesh, solid, detail: dict[str, Any]) -> dict[str, Any]:
    kind = detail["kind"]
    base = {"name": detail["name"], "kind": kind}
    if solid is None and kind != "thickness":
        return {**base, "ok": False, "error": section.NOT_MANIFOLD}
    if kind in ("material", "void", "view"):
        fraction = fill_fraction(solid, detail["box"])
        result = {**base, "box": detail["box"], "material_fraction": round(fraction, 4)}
        if kind == "material":
            return {
                **result,
                "min_fraction": detail["fraction"],
                "ok": fraction >= detail["fraction"],
            }
        if kind == "void":
            empty = 1.0 - fraction
            return {
                **result,
                "min_empty_fraction": detail["fraction"],
                "ok": empty >= detail["fraction"],
            }
        # A box all material or all air is not where a surface feature is.
        return {**result, "ok": 0.0 < fraction < 1.0, "needs": "a close view"}
    if kind == "hole":
        return {**base, **hole(solid, detail["point"], detail["direction"], detail["diameters"])}
    return {**base, **thickness(mesh, detail["point"], detail["direction"], detail["mm"])}


def fill_fraction(solid: manifold3d.Manifold, box: list[list[float]]) -> float:
    lo, hi = np.asarray(box, float)
    size = hi - lo
    volume = float(np.prod(size))
    if volume <= 0:
        return 0.0
    cube = manifold3d.Manifold.cube(tuple(size)).translate(tuple(lo))
    return min(max((solid ^ cube).volume() / volume, 0.0), 1.0)


def hole(solid, point, direction, expected: list[list[float]]) -> dict[str, Any]:
    """The hole whose axis passes through `point` along `direction`: where its mouth is, its
    diameter (of the circle with the same area) at each expected depth, and a profile."""
    p = np.asarray(point, float)
    basis = section.frame(direction)
    local = solid.transform(np.hstack([basis, (-basis @ p)[:, None]]))  # axis -> +z, p -> 0
    lo, hi = local.bounding_box()[2], local.bounding_box()[5]

    def state(t: float) -> tuple[str, shapely.Polygon | None]:
        if not lo <= t <= hi:
            return "outside", None
        origin = shapely.Point(0.0, 0.0)
        for polygon in section._cross_section_polygons(local.slice(t)):
            if polygon.contains(origin):
                return "material", None
            if shapely.Polygon(polygon.exterior).contains(origin):
                ring = next(
                    (r for r in polygon.interiors if shapely.Polygon(r).contains(origin)), None
                )
                return "hole", shapely.Polygon(ring) if ring is not None else None
        return "outside", None

    start, _ = state(0.0)
    if start == "material":
        return {"ok": False, "error": "the point is inside the material: it goes outside the part"}
    step = SCAN_STEP_MM if start == "outside" else -SCAN_STEP_MM
    # Forward, from just before the part; backward (the point is inside the hole), from it.
    t = max(0.0, lo - SCAN_STEP_MM) if start == "outside" else 0.0
    mouth = None
    while min(lo, 0.0) - SCAN_STEP_MM <= t <= max(hi, 0.0) + SCAN_STEP_MM:
        nxt = t + step
        found, _ = state(nxt)
        if start == "outside" and found == "material":
            return {
                "ok": False,
                "error": f"the axis enters material {nxt:.2f} mm from the point without going "
                "through a hole: there is no hole on that axis",
            }
        if (start == "outside") == (found == "hole"):
            outside, inside = (t, nxt) if start == "outside" else (nxt, t)
            for _ in range(10):  # bisection to 0.1 µm
                middle = (outside + inside) / 2
                if state(middle)[0] == "hole":
                    inside = middle
                else:
                    outside = middle
            mouth = inside
            break
        t = nxt
    if mouth is None:
        return {"ok": False, "error": "there is no closed hole on that axis"}

    def diameter(depth: float) -> float | None:
        kind, ring = state(mouth + max(depth, MOUTH_INSET_MM))
        return round(2 * float(np.sqrt(ring.area / np.pi)), 3) if ring is not None else None

    deepest = max(d for d, _ in expected)
    depths = sorted({d for d in PROFILE_DEPTHS if d <= deepest + 2.0} | {d for d, _ in expected})
    profile = [[d, diameter(d)] for d in depths[:MAX_PROFILE]]
    checks, ok = [], True
    for depth, want in expected:
        got = diameter(depth)
        tol = max(HOLE_TOLERANCE_MM, HOLE_TOLERANCE_REL * want)
        good = got is not None and abs(got - want) <= tol
        ok &= good
        checks.append({"depth_mm": depth, "expected_mm": want, "measured_mm": got, "ok": good})
    mouth_point = p + mouth * basis[2]
    return {
        "ok": ok,
        "mouth": section._r(mouth_point),
        "mouth_from_point_mm": round(mouth, 3),
        "diameters": checks,
        "profile": profile,
        "note": "Ø of the circle with the same area, at each depth from the mouth (the first "
        f"closed section around the axis, coming from the point); 0 = {MOUTH_INSET_MM} mm",
    }


def thickness(mesh: trimesh.Trimesh, point, direction, expected: float) -> dict[str, Any]:
    """Material crossed along the ray from `point`: from where it enters to where it leaves."""
    p = np.asarray(point, float)
    d = np.asarray(direction, float)
    d = d / np.linalg.norm(d)
    locations, _, faces = mesh.ray.intersects_location([p], [d], multiple_hits=True)
    if len(locations) == 0:
        return {"ok": False, "error": "the ray does not hit the part"}
    t = (locations - p) @ d
    order = np.argsort(t)
    t, faces = t[order], faces[order]
    entering = mesh.face_normals[faces] @ d < 0
    keep = np.ones(len(t), bool)
    keep[1:] = np.diff(t) > 1e-6  # an edge or a vertex hit twice
    t, entering = t[keep], entering[keep]
    if not entering[0]:
        return {"ok": False, "error": "the point is inside the material: it goes outside the part"}
    exits = np.flatnonzero(~entering)
    if not len(exits):
        return {"ok": False, "error": "the ray enters the part and does not leave it"}
    measured = float(t[exits[0]] - t[0])
    tol = max(THICKNESS_TOLERANCE_MM, THICKNESS_TOLERANCE_REL * expected)
    return {
        "ok": abs(measured - expected) <= tol,
        "expected_mm": expected,
        "measured_mm": round(measured, 3),
        "enters_at": section._r(p + t[0] * d),
        "tolerance_mm": round(tol, 3),
    }
