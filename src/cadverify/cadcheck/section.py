"""Cuts of a mesh by a plane, for render_view: the 2D profile with its numbers, the cut solid with
its cap, and the through holes along X, Y and Z.

Two engines:

- manifold3d: the mesh as a Manifold, cut exactly with `trim_by_plane` (a closed solid) and
  sliced with `slice` after rotating the plane to z = 0. Needs a closed, consistently oriented
  mesh.
- trimesh: the triangles intersected with the plane (`mesh_plane`); the segments are joined into
  polygons with shapely (even-odd rule) and the cap is the profile triangulated. Works on any
  mesh, open ones included, and reports the chains that do not close.

`engine="auto"` uses manifold3d and falls back to trimesh when the mesh is not a valid manifold.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any

import manifold3d
import numpy as np
import scipy.sparse
import shapely
import trimesh
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

ENGINES = ("auto", "manifold", "trimesh")
GRID_MM = 1e-6  # segment endpoints this close are one point, then snapped to this grid
ON_PLANE_MM = 1e-5
END_INSET_MM = 0.05  # holes are measured this far inside each end
MAX_LEVELS = 400  # per axis for the hole search
NOT_MANIFOLD = "manifold3d does not accept the mesh (it is not a closed, oriented solid)"
FALLBACK = "mesh not accepted by manifold3d (open or badly oriented): cut with trimesh"


def frame(normal) -> np.ndarray:
    """Rows: u (right), v (up) and the unit normal, a right-handed basis (u × v = n).

    Seen from the +normal side, u points right and v up; v follows +Z when the plane is not
    horizontal, and +Y (or -Y looking up from below) when it is, as the views of render_sheet.
    """
    n = np.asarray(normal, float)
    n = n / np.linalg.norm(n)
    if abs(n[2]) < 0.99:
        up = np.array([0.0, 0.0, 1.0])
    else:
        up = np.array([0.0, 1.0 if n[2] > 0 else -1.0, 0.0])
    u = np.cross(up, n)
    u /= np.linalg.norm(u)
    return np.stack([u, np.cross(n, u), n])


@dataclass
class Profile:
    """The section of a mesh by a plane, in the plane's (u, v) coordinates (mm)."""

    origin: np.ndarray
    basis: np.ndarray  # rows u, v, n
    polygons: list[shapely.Polygon]
    engine: str
    open_chains: int = 0  # chains that do not close: the mesh is open along the cut
    seconds: float = 0.0
    note: str | None = None

    def lift(self, uv: np.ndarray) -> np.ndarray:
        uv = np.atleast_2d(np.asarray(uv, float))
        return self.origin + uv[:, :1] * self.basis[0] + uv[:, 1:2] * self.basis[1]

    def numbers(self, max_regions: int = 20) -> dict[str, Any]:
        regions = sorted(self.polygons, key=lambda p: -p.area)
        out: dict[str, Any] = {
            "engine": self.engine,
            "area_mm2": round(float(sum(p.area for p in regions)), 2),
            "regions": len(regions),
            "contours": sum(1 + len(p.interiors) for p in regions),
            "holes": sum(len(p.interiors) for p in regions),
            "open_chains": self.open_chains,
            "u_axis": _axis_name(self.basis[0]),
            "v_axis": _axis_name(self.basis[1]),
        }
        if regions:
            union = shapely.MultiPolygon(regions)
            out["bounds_uv"] = _r(np.reshape(union.bounds, (2, 2)))
            out["bounds_3d"] = _bounds_3d(self, union)
        out["region_list"] = [
            {
                "area_mm2": round(p.area, 2),
                "holes": len(p.interiors),
                "hole_diameters_mm": [
                    round(_equivalent_diameter(shapely.Polygon(r)), 2) for r in p.interiors
                ][:10],
                "bounds_uv": _r(np.reshape(p.bounds, (2, 2))),
                "bounds_3d": _bounds_3d(self, p),
            }
            for p in regions[:max_regions]
        ]
        if self.note:
            out["note"] = self.note
        return out


@dataclass
class Cut:
    """The part on the -normal side of the plane, with the cap faces marked."""

    mesh: trimesh.Trimesh
    cap: np.ndarray  # bool per face
    profile: Profile
    engine: str
    seconds: float = 0.0
    extra: dict[str, Any] = field(default_factory=dict)


def to_manifold(mesh: trimesh.Trimesh) -> manifold3d.Manifold | None:
    """The mesh as a Manifold, or None when manifold3d does not accept it.

    manifold3d accepts a closed shell listed inside out and then cuts it as empty space (a box
    with its faces reversed gives a section of 0 mm²), so a shell of negative volume is
    rejected here too.
    """
    if len(mesh.faces) == 0:
        return None
    solid = manifold3d.Manifold(
        manifold3d.Mesh64(
            vert_properties=np.array(mesh.vertices, dtype=np.float64, order="C"),
            tri_verts=np.array(mesh.faces, dtype=np.uint64, order="C"),
        )
    )
    if solid.status() != manifold3d.Error.NoError or solid.is_empty():
        return None
    if any(part.volume() <= 0 for part in solid.decompose()):
        return None
    return solid


def profile(mesh: trimesh.Trimesh, origin, normal, engine: str = "auto", solid=None) -> Profile:
    """The section of `mesh` by the plane through `origin` with `normal`.

    `solid` is the mesh as a Manifold when the caller already has it.
    """
    t0 = time.perf_counter()
    origin = np.asarray(origin, float)
    basis = frame(normal)
    note = None
    if engine != "trimesh":
        solid = solid if solid is not None else to_manifold(mesh)
        if solid is not None:
            polygons = _manifold_profile(solid, origin, basis)
            return Profile(origin, basis, polygons, "manifold", 0, time.perf_counter() - t0)
        if engine == "manifold":
            raise ValueError(NOT_MANIFOLD)
        note = FALLBACK
    lines = trimesh.intersections.mesh_plane(mesh, basis[2], origin)
    uv = (np.asarray(lines).reshape(-1, 3) - origin) @ basis[:2].T
    polygons, open_chains = polygons_from_segments(uv.reshape(-1, 2, 2))
    return Profile(origin, basis, polygons, "trimesh", open_chains, time.perf_counter() - t0, note)


def cut(mesh: trimesh.Trimesh, origin, normal, engine: str = "auto") -> Cut:
    """Remove the half-space the normal points to; the cap faces face +normal."""
    t0 = time.perf_counter()
    origin = np.asarray(origin, float)
    basis = frame(normal)
    n = basis[2]
    solid = to_manifold(mesh) if engine != "trimesh" else None
    if solid is None and engine == "manifold":
        raise ValueError(NOT_MANIFOLD)
    prof = profile(mesh, origin, n, "manifold" if solid is not None else "trimesh", solid)
    if solid is None and engine == "auto":
        prof.note = FALLBACK
    if solid is not None:
        kept = solid.trim_by_plane(tuple(-n), float(-n @ origin)).to_mesh64()
        part = trimesh.Trimesh(
            np.asarray(kept.vert_properties)[:, :3], np.asarray(kept.tri_verts), process=False
        )
        distance = (part.vertices - origin) @ n
        on_plane = np.all(np.abs(distance[part.faces]) < ON_PLANE_MM, axis=1)
        cap = on_plane & (part.face_normals @ n > 0.999)
        return Cut(part, cap, prof, "manifold", time.perf_counter() - t0)
    sliced = trimesh.intersections.slice_mesh_plane(mesh, -n, origin, cap=False)
    cap_mesh = triangulate(prof)
    part = trimesh.util.concatenate([sliced, cap_mesh]) if len(cap_mesh.faces) else sliced
    cap = np.zeros(len(part.faces), bool)
    cap[len(sliced.faces) :] = True
    return Cut(part, cap, prof, "trimesh", time.perf_counter() - t0)


def triangulate(prof: Profile) -> trimesh.Trimesh:
    """The profile's polygons as triangles on the plane, facing +normal."""
    triangles = []
    for polygon in prof.polygons:
        for tri in shapely.get_parts(shapely.constrained_delaunay_triangles(polygon)):
            xy = np.asarray(tri.exterior.coords)[:3]
            if _signed_area(xy) < 0:
                xy = xy[::-1]
            triangles.append(xy)
    if not triangles:
        return trimesh.Trimesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64), process=False)
    uv = np.concatenate(triangles)
    vertices = prof.lift(uv)
    faces = np.arange(len(vertices)).reshape(-1, 3)
    return trimesh.Trimesh(vertices, faces, process=False)


def polygons_from_segments(segments: np.ndarray) -> tuple[list[shapely.Polygon], int]:
    """Join 2D segments (k, 2, 2) into polygons by the even-odd rule.

    The two triangles sharing an edge give the same point up to rounding: endpoints within 1e-6
    mm are merged into one before they are snapped to a 1e-6 mm grid, since two copies of a
    point halfway between grid lines can round apart. Returns the polygons and the number of
    chains that do not close.
    """
    if len(segments) == 0:
        return [], 0
    points = np.asarray(segments, dtype=float).reshape(-1, 2)
    pairs = cKDTree(points).query_pairs(GRID_MM, output_type="ndarray")
    graph = scipy.sparse.coo_matrix(
        (np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(len(points), len(points))
    )
    _, label = connected_components(graph, directed=False)
    _, first = np.unique(label, return_index=True)
    merged = points[first[label]].reshape(-1, 2, 2)
    lines = shapely.set_precision(shapely.linestrings(merged), GRID_MM)
    lines = lines[~shapely.is_empty(lines) & (shapely.length(lines) > 0)]
    faces, cuts, dangles, invalid = shapely.polygonize_full(lines)
    filled = shapely.Polygon()
    for face in shapely.get_parts(faces):
        filled = filled.symmetric_difference(shapely.Polygon(face.exterior))
    polygons = [p for p in shapely.get_parts(filled) if isinstance(p, shapely.Polygon) and p.area]
    open_chains = sum(len(shapely.get_parts(g)) for g in (cuts, dangles, invalid))
    return polygons, open_chains


def through_holes(
    mesh: trimesh.Trimesh, engine: str = "auto", max_levels: int = MAX_LEVELS
) -> list[dict[str, Any]]:
    """Holes along X, Y or Z that cross the part: their axis, position and diameters.

    For each axis, the part is sliced at one level between every pair of distinct vertex
    coordinates (the topology of a section only changes at vertices). A hole is a chain of
    inner contours that overlap from one level to the next; it is a through hole when the
    material is open at both ends. Each end's diameter is measured 0.05 mm inside the end, so
    a countersink or a counterbore shows on the side where it is. Oblique holes are not found.
    """
    solid = to_manifold(mesh) if engine != "trimesh" else None
    holes: list[dict[str, Any]] = []
    for axis in range(3):
        normal = np.eye(3)[axis]
        coords = np.unique(np.round(mesh.vertices[:, axis], 4))
        if len(coords) < 2:
            continue
        levels = (coords[:-1] + coords[1:]) / 2
        if len(levels) > max_levels:
            levels = levels[np.linspace(0, len(levels) - 1, max_levels).round().astype(int)]
        sections = [_section_at(mesh, solid, normal, z) for z in levels]
        for chain in _hole_chains(sections):
            first, last = chain[0], chain[-1]
            below = sections[first[0] - 1] if first[0] > 0 else None
            above = sections[last[0] + 1] if last[0] + 1 < len(sections) else None
            open_below = below is None or not _covers(below, sections[first[0]][1][first[1]])
            open_above = above is None or not _covers(above, sections[last[0]][1][last[1]])
            if not (open_below and open_above):
                continue
            start = float(coords[np.searchsorted(coords, levels[first[0]]) - 1])
            end = float(coords[np.searchsorted(coords, levels[last[0]])])
            holes.append(_describe_hole(mesh, solid, axis, chain, sections, start, end))
    for i, hole in enumerate(holes, 1):
        hole["id"] = f"a{i}"
    return holes


def _describe_hole(mesh, solid, axis, chain, sections, start, end) -> dict[str, Any]:
    rings = [sections[level][1][index] for level, index in chain]
    narrowest = min(rings, key=lambda r: r.area)
    normal = np.eye(3)[axis]
    ends = []
    for z in (start + END_INSET_MM, end - END_INSET_MM):
        polygons, inner = _section_at(mesh, solid, normal, z)
        ring = next((r for r in inner if r.intersects(narrowest)), None)
        ends.append(round(_equivalent_diameter(ring), 2) if ring is not None else None)
    center2d = np.array(narrowest.centroid.coords[0])
    center = np.insert(center2d, axis, (start + end) / 2)
    region = shapely.unary_union(rings)
    return {
        "axis": "xyz"[axis],
        "center": _r(center),
        "from": round(start, 3),
        "to": round(end, 3),
        "length_mm": round(end - start, 3),
        "min_diameter_mm": round(_equivalent_diameter(narrowest), 2),
        "diameter_at_from_mm": ends[0],
        "diameter_at_to_mm": ends[1],
        "_footprint": region,  # 2D region (in the other two axes) for highlighting faces
    }


def hole_faces(mesh: trimesh.Trimesh, holes: list[dict[str, Any]]) -> np.ndarray:
    """Index of the hole each face belongs to (-1: none), by its centroid inside the hole."""
    owner = np.full(len(mesh.faces), -1)
    if not holes or len(mesh.faces) == 0:
        return owner
    centroids = mesh.triangles_center
    for i, hole in enumerate(holes):
        axis = "xyz".index(hole["axis"])
        others = [a for a in range(3) if a != axis]
        along = centroids[:, axis]
        inside_run = (along >= hole["from"] - 1e-3) & (along <= hole["to"] + 1e-3)
        footprint = hole["_footprint"].buffer(0.02)
        candidates = np.flatnonzero(inside_run & (owner < 0))
        if len(candidates) == 0:
            continue
        points = shapely.points(centroids[candidates][:, others])
        owner[candidates[shapely.contains(footprint, points)]] = i
    return owner


def _section_at(mesh, solid, normal, z) -> tuple[list[shapely.Polygon], list[shapely.Polygon]]:
    """Polygons of the section at height z along an axis, and their inner contours (filled).

    The plane coordinates are the two other axes in increasing order, so the hole footprints
    of one axis can be compared with face centroids directly.
    """
    axis = int(np.argmax(normal))
    others = [a for a in range(3) if a != axis]
    if solid is not None:
        # Rotate the axis to z with the other two in order: a permutation, then slice.
        perm = np.zeros((3, 4))
        perm[0, others[0]] = perm[1, others[1]] = perm[2, axis] = 1.0
        polygons = _cross_section_polygons(solid.transform(perm).slice(float(z)))
    else:
        lines = trimesh.intersections.mesh_plane(mesh, normal, normal * z)
        segments = np.asarray(lines).reshape(-1, 2, 3)[:, :, others]
        polygons, _ = polygons_from_segments(segments)
    inner = [shapely.Polygon(r) for p in polygons for r in p.interiors]
    return polygons, inner


def _hole_chains(sections) -> list[list[tuple[int, int]]]:
    """Inner contours linked level to level when they overlap; each chain is one hole."""
    parent: dict[tuple[int, int], tuple[int, int]] = {}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for level, (_, inner) in enumerate(sections):
        for index in range(len(inner)):
            parent[(level, index)] = (level, index)
    for level in range(len(sections) - 1):
        lower, upper = sections[level][1], sections[level + 1][1]
        if not lower or not upper:
            continue
        tree = shapely.STRtree(upper)
        for i, ring in enumerate(lower):
            for j in tree.query(ring, predicate="intersects"):
                if ring.intersection(upper[j]).area > 1e-6:
                    parent[find((level, i))] = find((level + 1, int(j)))
    groups: dict[tuple[int, int], list[tuple[int, int]]] = {}
    for node in parent:
        groups.setdefault(find(node), []).append(node)
    # Links only join consecutive levels, so each chain covers a contiguous run of levels; one
    # that splits or merges keeps all its contours, and its ends are its first and last level.
    return [sorted(nodes) for nodes in groups.values()]


def _covers(section, region: shapely.Polygon) -> bool:
    """Is the region's interior point inside the material of the section?"""
    polygons = section[0]
    point = region.representative_point()
    return any(p.contains(point) for p in polygons)


def _manifold_profile(solid, origin: np.ndarray, basis: np.ndarray) -> list[shapely.Polygon]:
    affine = np.hstack([basis, (-basis @ origin)[:, None]])
    return _cross_section_polygons(solid.transform(affine).slice(0.0))


def _cross_section_polygons(section) -> list[shapely.Polygon]:
    polygons = []
    for region in section.decompose():
        rings = [np.asarray(r) for r in region.to_polygons() if len(r) >= 3]
        outer = [r for r in rings if _signed_area(r) > 0]
        holes = [r for r in rings if _signed_area(r) < 0]
        for ring in outer:
            shell = shapely.Polygon(ring)
            inside = [h for h in holes if shell.contains(shapely.Point(h[0]))]
            polygons.append(shapely.Polygon(ring, inside))
    return polygons


def _signed_area(ring: np.ndarray) -> float:
    x, y = ring[:, 0], ring[:, 1]
    return 0.5 * float(np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y))


def _equivalent_diameter(polygon: shapely.Polygon | None) -> float:
    return float(2 * np.sqrt(polygon.area / np.pi)) if polygon is not None else 0.0


def _bounds_3d(prof: Profile, geometry) -> list:
    coords = np.vstack([np.asarray(p.exterior.coords) for p in shapely.get_parts(geometry)])
    points = prof.lift(coords)
    return _r(np.array([points.min(axis=0), points.max(axis=0)]))


def _axis_name(vector: np.ndarray) -> str:
    i = int(np.argmax(np.abs(vector)))
    if np.isclose(abs(vector[i]), 1.0):
        return ("+" if vector[i] > 0 else "-") + "XYZ"[i]
    return "[" + ", ".join(f"{c:.3f}" for c in vector) + "]"


def _r(array) -> list:
    return np.round(np.asarray(array, float), 3).tolist()
