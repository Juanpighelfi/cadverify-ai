"""mesh_report: watertightness, bad edges, volume, bounds and body count of an exported mesh."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import trimesh

MAX_LOCATIONS = 10


def mesh_report(path: str | Path) -> dict[str, Any]:
    """Basic geometric facts of a mesh file, in its own units (mm for OpenSCAD)."""
    return report_from_mesh(load_exact(path))


def report_from_mesh(mesh: trimesh.Trimesh) -> dict[str, Any]:
    """mesh_report of a mesh loaded with load_exact.

    - `bad_edges`: undirected edges not shared by exactly two triangles (holes, non-manifold
      joints); `bad_edge_locations` lists the midpoints of the first few.
    - Shells are triangles connected through manifold edges. `bodies` have positive signed
      volume; a negative shell is a `cavity` when it lies inside a body (a part with an enclosed
      void is 1 body and 1 cavity) and an `inverted_shell` otherwise (its faces point inwards).
      Volumes and shell counts are only meaningful when the mesh is watertight.
    - `through_holes`: total genus of the bodies (a plate with 4 holes has 4), from the Euler
      characteristic of each shell; None when the mesh is not watertight.
    """
    if len(mesh.faces) == 0:
        return {"triangles": 0, "watertight": False, "bad_edges": None, "bodies": 0}

    edges, counts = np.unique(mesh.edges_sorted, axis=0, return_counts=True)
    bad = edges[counts != 2]

    triangles = mesh.triangles
    signed = np.einsum("ij,ij->i", triangles[:, 0], np.cross(triangles[:, 1], triangles[:, 2])) / 6
    shells = trimesh.graph.connected_components(
        mesh.face_adjacency, nodes=np.arange(len(mesh.faces)), min_len=1
    )
    volumes = [signed[faces].sum() for faces in shells]
    bodies = [faces for faces, v in zip(shells, volumes, strict=True) if v > 0]
    negative = [faces for faces, v in zip(shells, volumes, strict=True) if v < 0]
    body_triangles = triangles[np.concatenate(bodies)] if bodies else triangles[:0]
    cavities = sum(
        _winding_number(triangles[faces[0]].mean(axis=0), body_triangles) > 0.5
        for faces in negative
    )

    return {
        "triangles": len(mesh.faces),
        "watertight": bool(mesh.is_watertight),
        "winding_consistent": bool(mesh.is_winding_consistent),
        "bad_edges": len(bad),
        "bad_edge_locations": _round(mesh.vertices[bad[:MAX_LOCATIONS]].mean(axis=1)),
        "volume_mm3": round(float(signed.sum()), 3),
        "bounds": _round(mesh.bounds),
        "size": _round(mesh.extents),
        "bodies": len(bodies),
        "cavities": int(cavities),
        "inverted_shells": len(negative) - int(cavities),
        "through_holes": sum(_genus(mesh.faces[f]) for f in bodies) if mesh.is_watertight else None,
    }


def load_exact(path: str | Path) -> trimesh.Trimesh:
    """Load a mesh merging only vertices written with identical coordinates.

    trimesh's default merge tolerance (1e-8) fuses distinct vertices that OpenSCAD 2026.10
    leaves 1e-9 mm apart and fabricates bad edges in meshes that are closed.
    """
    raw = trimesh.load_mesh(Path(path), process=False)
    if len(raw.faces) == 0:
        return trimesh.Trimesh(np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64), process=False)
    vertices, inverse = np.unique(
        raw.vertices[raw.faces].reshape(-1, 3), axis=0, return_inverse=True
    )
    return trimesh.Trimesh(vertices, inverse.reshape(-1, 3), process=False)


def _genus(faces: np.ndarray) -> int:
    """Genus of one closed shell: V - E + F = 2 - 2g."""
    edges = np.unique(np.sort(faces[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), axis=1), axis=0)
    euler = len(np.unique(faces)) - len(edges) + len(faces)
    return (2 - euler) // 2


def _winding_number(point: np.ndarray, triangles: np.ndarray) -> float:
    """Generalized winding number: about 1 inside outward-facing closed shells, 0 outside."""
    a, b, c = (triangles[:, i] - point for i in range(3))
    la, lb, lc = (np.linalg.norm(v, axis=1) for v in (a, b, c))

    def dot(u: np.ndarray, v: np.ndarray) -> np.ndarray:
        return np.einsum("ij,ij->i", u, v)

    # Van Oosterom & Strackee: tan(solid angle / 2) of each triangle seen from the point.
    numerator = dot(a, np.cross(b, c))
    denominator = la * lb * lc + dot(a, b) * lc + dot(a, c) * lb + dot(b, c) * la
    return float(np.arctan2(numerator, denominator).sum() / (2 * np.pi))


def _round(array: np.ndarray) -> list:
    return np.round(array, 3).tolist()
