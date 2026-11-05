"""Linear elasticity on a triangle mesh: tetrahedra from gmsh, quadratic elements from scikit-fem.

The harness needs what a load does to a part it did not design, without being told which part of
it bends. So the part itself is the model: a closed mesh is filled with tetrahedra, sized from the
walls it finds (`sizes`), and solved for a unit load. Everything is linear, so the unit field is
scaled afterwards, and two bodies in contact are two springs in series (cadcheck.behaviour).

Strain and stress peak on the surface, and a sharp inner corner makes them infinite in theory, so
a peak depends on the mesh unless it is taken over some length. Here it is the surface around each
node, PEAK_RADIUS_MM across on either side: a line of the 0.4 mm nozzle, the smallest thing the
printer draws. Averaging along the surface keeps a bending strain (a wall's outer fiber is the
same along it), where averaging through the wall would lose it.

Deterministic: one thread, a fixed order, and gmsh's own random factor. Accepted against closed
forms, on refinement and on time in tests/test_behaviour.py and docs/architecture.md.
"""

from __future__ import annotations

import math
import multiprocessing
import tempfile
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import scipy.sparse.linalg as sla
import trimesh
from scipy.spatial import cKDTree

PEAK_RADIUS_MM = 0.4
SIZE_MIN_MM = 0.2  # the smallest tetrahedron, at a peak: half the nozzle's line
HOT_SIZE_MM = 0.3  # around a peak, so that its average over PEAK_RADIUS_MM has nodes to take
SIZE_MAX_MM = 3.0
SIZE_PER_THICKNESS = 0.8  # a quadratic element bends well with about one per wall (test_behaviour)
GROWTH = 0.35  # how fast the size grows with the distance from the load
MAX_TETS = 22_000  # about 110k unknowns: 40 s and 2 GB to factor, in 2 CPUs and 4 GB
SAMPLE_EDGE_MM = 0.6
SAMPLES_MAX = 60_000
NEIGHBORS = 16
VOLUME_TOLERANCE = 0.03  # of the mesh's volume, for the tetrahedra that fill it
MESH_TIMEOUT_S = 300


class MeshingError(RuntimeError):
    """gmsh could not fill the part: a gate is red for it, with this reason."""


@dataclass
class Tets:
    points: np.ndarray
    tets: np.ndarray
    seconds: float
    method: str


@dataclass
class Unit:
    """A part under a unit load: its surface nodes with the stress there (MPa per N)."""

    points: np.ndarray
    stress: np.ndarray  # (n, 3, 3)
    keep: np.ndarray  # the nodes a peak may be at: away from the load and the fixed faces
    faces: np.ndarray  # the surface's triangles, as indices of `points`
    compliance: float  # mm of the loaded surface's mean displacement per N
    largest: float  # mm of the part's largest displacement per N
    tets: int
    unknowns: int
    seconds: float
    method: str


def wall_sizes(mesh: trimesh.Trimesh) -> tuple[np.ndarray, np.ndarray]:
    """Points on the surface and the wall each one is on, in mm: the nearest surface facing the
    other way behind it. A surface with nothing facing it nearby is on a thick part (inf)."""
    # Sampled, not subdivided: the long thin triangles of a cap or a thread multiply without end
    # when split down to a length. The seed keeps the result the same from run to run.
    area = max(float(mesh.area), 1.0)
    edge = max(SAMPLE_EDGE_MM, math.sqrt(area / SAMPLES_MAX))
    count = min(int(area / edge**2) + 1, SAMPLES_MAX)
    samples, index = trimesh.sample.sample_surface(mesh, count, seed=0)
    centers = np.vstack([samples, mesh.triangles_center])
    normals = np.vstack([mesh.face_normals[index], mesh.face_normals])
    walls = np.full(len(centers), np.inf)
    # Each of the six directions against what faces away from it: on a fine mesh, the nearest
    # points of any surface are all on the point's own face.
    for axis in np.vstack([np.eye(3), -np.eye(3)]):
        mine = np.nonzero(normals @ axis >= np.max(np.abs(normals), axis=1) - 1e-9)[0]
        away = np.nonzero(normals @ axis < -0.3)[0]
        if not len(mine) or not len(away):
            continue
        k = min(NEIGHBORS, len(away))
        _, near = cKDTree(centers[away]).query(centers[mine], k=k)
        near = away[near.reshape(len(mine), k)]
        apart = centers[near] - centers[mine, None]
        behind = np.einsum("ijk,ik->ij", apart, -normals[mine])
        facing = np.einsum("ijk,ik->ij", normals[near], normals[mine]) < -0.5
        distance = np.linalg.norm(apart, axis=2)
        distance[~(facing & (behind > 0.5 * distance))] = np.inf
        walls[mine] = distance.min(axis=1)
    return centers, walls


def sizes(
    mesh: trimesh.Trimesh,
    load_points: np.ndarray | None,
    near_mm: float,
    hot_points: np.ndarray | None = None,
) -> Callable[[np.ndarray], np.ndarray]:
    """The tetrahedron size at any point: from the wall it is in, and close to the load and to
    the peaks of an earlier solve."""
    centers, walls = wall_sizes(mesh)
    wall = np.clip(SIZE_PER_THICKNESS * walls, SIZE_MIN_MM, SIZE_MAX_MM)
    surface = cKDTree(centers)
    load = cKDTree(load_points) if load_points is not None and len(load_points) else None
    hot = cKDTree(hot_points) if hot_points is not None and len(hot_points) else None

    def size(points: np.ndarray) -> np.ndarray:
        out = wall[surface.query(points)[1]]
        if load is not None:
            out = np.minimum(out, near_mm + GROWTH * load.query(points)[0])
        if hot is not None:
            out = np.minimum(out, HOT_SIZE_MM + GROWTH * hot.query(points)[0])
        return np.clip(out, SIZE_MIN_MM, SIZE_MAX_MM)

    return size


def tetrahedra(mesh: trimesh.Trimesh, size: Callable[[np.ndarray], np.ndarray]) -> Tets:
    """The mesh filled with tetrahedra: its surface remeshed by gmsh when gmsh can parametrize it,
    split into smaller triangles first when not, and those triangles kept as a last resort. Raises
    MeshingError when none fills its volume."""
    t0 = time.perf_counter()
    errors = []
    for method, surface, build in (
        ("remeshed", lambda: mesh, _remeshed),
        ("remeshed, split first", lambda: _split(mesh, size), _remeshed),
        ("its own surface", lambda: _split(mesh, size), _as_is),
    ):
        try:
            points, tets = _isolated(surface(), size, build)
        except Exception as exc:  # gmsh raises a bare Exception with its message
            errors.append(f"{method}: {exc}")
            continue
        volume = _tets_volume(points, tets)
        if abs(volume - abs(mesh.volume)) > VOLUME_TOLERANCE * abs(mesh.volume):
            errors.append(f"{method}: {volume:.1f} mm³ of tetrahedra for {mesh.volume:.1f} mm³")
            continue
        return Tets(points, tets, time.perf_counter() - t0, method)
    raise MeshingError("; ".join(errors))


def _split(mesh: trimesh.Trimesh, size: Callable[[np.ndarray], np.ndarray]) -> trimesh.Trimesh:
    """The same surface in triangles of about the mesh's size. gmsh keeps a surface it cannot remesh
    as it is, and a long triangle makes an element as long: a drawer of 216 tetrahedra took half
    the deflection it does on 21,821, and refining did not show it, its surface being the same."""
    from cadverify.cadcheck import section

    solid = section.to_manifold(mesh)
    if solid is None:
        return mesh
    out = solid.refine_to_length(float(np.median(size(mesh.triangles_center)))).to_mesh()
    return trimesh.Trimesh(
        np.asarray(out.vert_properties)[:, :3], np.asarray(out.tri_verts), process=False
    )


def _tets_volume(points: np.ndarray, tets: np.ndarray) -> float:
    a = points[tets[:, 0]]
    edges = np.stack([points[tets[:, k]] - a for k in (1, 2, 3)], axis=1)
    return float(np.abs(np.linalg.det(edges)).sum() / 6)


def _isolated(mesh, size, build) -> tuple[np.ndarray, np.ndarray]:
    """gmsh in a process of its own. On some surfaces it does not raise, it dies with a segfault, or
    it does not come back, and either has to be one more failed attempt, not the end of G6."""
    # Forked, since `size` is a closure. Python warns about forking with the threads BLAS keeps; the
    # child calls no BLAS, and if it ever hung the timeout makes that a failed attempt too.
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        child = multiprocessing.get_context("fork").Process(
            target=_gmsh_to_file, args=(mesh, size, build, folder)
        )
        child.start()
        child.join(MESH_TIMEOUT_S)
        if child.is_alive():
            child.kill()
            child.join()
            raise RuntimeError(f"gmsh ran over {MESH_TIMEOUT_S} s")
        if (folder / "error.txt").exists():
            raise RuntimeError((folder / "error.txt").read_text(encoding="utf-8"))
        if child.exitcode != 0 or not (folder / "tets.npz").exists():
            raise RuntimeError(f"gmsh died (exit {child.exitcode})")
        with np.load(folder / "tets.npz") as found:
            return found["points"], found["tets"]


def _gmsh_to_file(mesh, size, build, folder: Path) -> None:
    try:
        points, tets = _gmsh(mesh, size, build)
    except Exception as exc:  # gmsh raises a bare Exception with its message
        (folder / "error.txt").write_text(str(exc), encoding="utf-8")
        return
    np.savez(folder / "tets.npz", points=points, tets=tets)


def _gmsh(mesh, size, build) -> tuple[np.ndarray, np.ndarray]:
    import gmsh

    gmsh.initialize()
    try:
        for name, value in (
            ("General.Terminal", 0),
            ("General.NumThreads", 1),
            ("Mesh.MeshSizeFromCurvature", 0),
            ("Mesh.MeshSizeExtendFromBoundary", 0),
            ("Mesh.MeshSizeFromPoints", 0),
            ("Mesh.Algorithm", 6),
            ("Mesh.Algorithm3D", 1),
            ("Mesh.Optimize", 1),
            ("Mesh.OptimizeNetgen", 1),
            ("Mesh.RandomSeed", 1),
        ):
            gmsh.option.setNumber(name, value)
        gmsh.model.add("part")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "part.stl"
            path.write_bytes(trimesh.exchange.stl.export_stl_ascii(mesh).encode())
            gmsh.merge(str(path))

        known: dict[tuple[int, int, int], float] = {}

        def field(dim, tag, x, y, z, lc):
            # gmsh asks for many near points: once for each cell of a quarter of a mm.
            key = (round(4 * x), round(4 * y), round(4 * z))
            if key not in known:
                known[key] = float(size(np.array([[x, y, z]]))[0])
            return known[key]

        build(gmsh, field)
        gmsh.model.mesh.generate(3)
        tags, coords, _ = gmsh.model.mesh.getNodes()
        points = coords.reshape(-1, 3)
        types, _, nodes = gmsh.model.mesh.getElements(3)
        if 4 not in list(types):
            raise RuntimeError("gmsh made no tetrahedra")
        lookup = np.zeros(int(tags.max()) + 1, int)
        lookup[tags.astype(int)] = np.arange(len(tags))
        tets = lookup[nodes[list(types).index(4)].astype(int)].reshape(-1, 4)
    finally:
        gmsh.clear()
        gmsh.finalize()
    used = np.unique(tets)
    remap = np.zeros(len(points), int)
    remap[used] = np.arange(len(used))
    return points[used], remap[tets]


def _remeshed(gmsh, field) -> None:
    gmsh.model.mesh.classifySurfaces(math.radians(40), True, True, math.pi)
    gmsh.model.mesh.createGeometry()
    loop = gmsh.model.geo.addSurfaceLoop([e[1] for e in gmsh.model.getEntities(2)])
    gmsh.model.geo.addVolume([loop])
    gmsh.model.geo.synchronize()
    gmsh.model.mesh.setSizeCallback(field)


def _as_is(gmsh, field) -> None:
    gmsh.model.mesh.classifySurfaces(math.radians(40), True, False, math.pi)
    gmsh.model.mesh.createTopology()
    loop = gmsh.model.geo.addSurfaceLoop([e[1] for e in gmsh.model.getEntities(2)])
    gmsh.model.geo.addVolume([loop])
    gmsh.model.geo.synchronize()
    gmsh.model.mesh.setSizeCallback(field)


def _boundary(m) -> tuple[np.ndarray, np.ndarray]:
    """The boundary facets of a skfem mesh and their centers."""
    facets = m.boundary_facets()
    return facets, m.p[:, m.facets[:, facets]].mean(axis=1).T


def solve_unit(
    tets: Tets,
    modulus: float,
    poisson: float,
    loaded: Callable[[np.ndarray], np.ndarray],
    fixed: Callable[[np.ndarray], np.ndarray],
    direction: np.ndarray | None = None,
) -> Unit:
    """The part with the facets `fixed` picks held still, under 1 N spread over the facets `loaded`
    picks: pressing on them along their normals, or along `direction` if given. Both take the
    facets' centers. The compliance is how far the loaded surface moves on average, along that
    same push. Raises MeshingError when there is nothing to load or to hold."""
    from skfem import (
        Basis,
        BilinearForm,
        ElementTetP1,
        ElementTetP2,
        ElementVector,
        FacetBasis,
        Functional,
        LinearForm,
        MeshTet,
    )
    from skfem.helpers import ddot, eye, sym_grad, trace

    t0 = time.perf_counter()
    # skfem wants right-handed tetrahedra.
    points, cells = tets.points, tets.tets.copy()
    a = points[cells[:, 0]]
    edges = np.stack([points[cells[:, k]] - a for k in (1, 2, 3)], axis=1)
    flip = np.linalg.det(edges) < 0
    cells[flip, 2], cells[flip, 3] = cells[flip, 3], cells[flip, 2].copy()
    m = MeshTet(np.array(points.T, order="F"), np.array(cells.T, order="F"))
    element = ElementVector(ElementTetP2())
    basis = Basis(m, element, intorder=2)
    lam = modulus * poisson / ((1 + poisson) * (1 - 2 * poisson))
    mu = modulus / (2 * (1 + poisson))

    @BilinearForm
    def stiffness(u, v, w):
        e = sym_grad(u)
        return ddot(2 * mu * e + lam * eye(trace(e), 3), sym_grad(v))

    facets, centers = _boundary(m)
    load = facets[loaded(centers)]
    held = facets[fixed(centers)]
    if not len(load):
        raise MeshingError("no surface of the mesh is under the load")
    if not len(held):
        raise MeshingError("no surface of the mesh is held")
    on_load = FacetBasis(m, element, facets=load, intorder=3)
    area = float(
        Functional(lambda w: 1.0 + 0 * w.x[0]).assemble(
            FacetBasis(m, ElementTetP1(), facets=load, intorder=3)
        )
    )

    def push(w):
        if direction is not None:
            return np.broadcast_to(np.reshape(direction, (3, 1, 1)), w.n.shape)
        return -w.n

    @LinearForm
    def force(v, w):
        p = push(w)
        return (v[0] * p[0] + v[1] * p[1] + v[2] * p[2]) / area

    @Functional
    def moved(w):
        p = push(w)
        return (w.u[0] * p[0] + w.u[1] * p[1] + w.u[2] * p[2]) / area

    K = stiffness.assemble(basis)
    f = force.assemble(on_load)
    held_dofs = basis.get_dofs(facets=held).all()
    free = np.setdiff1d(np.arange(basis.N), held_dofs)
    lu = sla.splu(
        K[free][:, free].tocsc(), permc_spec="MMD_AT_PLUS_A", options={"SymmetricMode": True}
    )
    x = np.zeros(basis.N)
    x[free] = lu.solve(np.asarray(f)[free])
    del lu
    compliance = float(moved.assemble(on_load, u=on_load.interpolate(x)))
    # The stress at the corners of each tetrahedron, averaged at each node.
    corners = np.array([[0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]])
    at_nodes = Basis(m, element, quadrature=(corners, np.ones(4) / 24))
    grad = at_nodes.interpolate(x).grad
    strain = 0.5 * (grad + np.swapaxes(grad, 0, 1))
    tr = np.trace(strain, axis1=0, axis2=1)
    stress = 2 * mu * strain + lam * np.einsum("ij,kl->ijkl", np.eye(3), tr)
    n_nodes = m.p.shape[1]
    total = np.zeros((n_nodes, 3, 3))
    count = np.zeros(n_nodes)
    # Weighted by volume: a sliver's gradient is noise, and a sliver has almost none.
    volume = np.abs(np.linalg.det(edges))
    for corner in range(4):
        nodes = m.t[corner]
        np.add.at(total, nodes, np.moveaxis(stress[:, :, :, corner], 2, 0) * volume[:, None, None])
        np.add.at(count, nodes, volume)
    nodal = total / np.maximum(count, 1e-12)[:, None, None]
    # The surface's nodes, with the area around each one.
    all_facets, _ = _boundary(m)
    corners_of = m.facets[:, all_facets]
    surface = np.unique(corners_of)
    triangle = np.moveaxis(m.p[:, corners_of], 0, 2)  # (corner, facet, xyz)
    cross = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
    each = np.linalg.norm(cross, axis=1) / 6
    weight = np.zeros(n_nodes)
    for corner in range(3):
        np.add.at(weight, corners_of[corner], each)
    positions = m.p[:, surface].T
    tree = cKDTree(positions)
    around = tree.query_ball_point(positions, PEAK_RADIUS_MM)
    smooth = np.zeros((len(surface), 3, 3))
    w = weight[surface]
    tensors = nodal[surface]
    for i, near in enumerate(around):
        near = np.asarray(near)
        smooth[i] = (tensors[near] * w[near, None, None]).sum(axis=0) / max(w[near].sum(), 1e-12)
    # A peak next to the load or to what holds the part is the model's, not the part's.
    away = np.ones(len(surface), bool)
    for chosen in (load, held):
        ends = np.unique(m.facets[:, chosen])
        hit = cKDTree(m.p[:, ends].T).query(positions)[0]
        away &= hit > PEAK_RADIUS_MM
    largest = float(np.linalg.norm(x[basis.nodal_dofs[:3]], axis=0).max())
    order = np.zeros(n_nodes, int)
    order[surface] = np.arange(len(surface))
    return Unit(
        points=positions,
        stress=smooth,
        keep=away,
        faces=order[corners_of].T,
        compliance=compliance,
        largest=largest,
        tets=m.t.shape[1],
        unknowns=basis.N,
        seconds=time.perf_counter() - t0,
        method=tets.method,
    )


def filled(
    mesh: trimesh.Trimesh,
    load_points: np.ndarray | None,
    near_mm: float,
    scale: float = 1.0,
    hot_points: np.ndarray | None = None,
    max_tets: int = MAX_TETS,
) -> Tets:
    """The mesh filled at `scale` of its sizes, coarser until it is under `max_tets`."""
    size = sizes(mesh, load_points, near_mm, hot_points)
    factor = scale
    while True:
        tets = tetrahedra(mesh, lambda p, f=factor: np.maximum(size(p) * f, SIZE_MIN_MM))
        if len(tets.tets) <= max_tets:
            return tets
        factor *= max(1.1, (len(tets.tets) / max_tets) ** (1 / 3))


def hot_spots(unit: Unit, up: Any = (0.0, 0.0, 1.0), count: int = 2, apart_mm: float = 2.0):
    """Where a unit field peaks, in tension and along `up`: the few highest points, each at least
    `apart_mm` from the others, to refine around them."""
    up = np.asarray(up, float) / np.linalg.norm(up)
    where = unit.points[unit.keep]
    if not len(where):
        return np.zeros((0, 3))
    s = unit.stress[unit.keep]
    chosen: list[np.ndarray] = []
    for value in (np.linalg.eigvalsh(s)[:, -1], np.einsum("i,nij,j->n", up, s, up)):
        taken = 0
        for i in np.argsort(-value):
            if taken == count:
                break
            if value[i] <= 0:
                break
            if all(np.linalg.norm(where[i] - c) >= apart_mm for c in chosen):
                chosen.append(where[i])
                taken += 1
    return np.array(chosen) if chosen else np.zeros((0, 3))


def peaks(unit: Unit, force: float, modulus: float, up: Any = (0.0, 0.0, 1.0)) -> dict[str, Any]:
    """The peak tension in a unit field scaled to `force` N: the largest principal stress, and
    the stress along `up` (the print's Z: what pulls layers apart), each with where it is. A
    strain here is that stress over the modulus: the outer fiber's strain, as a snap's formula
    gives it."""
    up = np.asarray(up, float) / np.linalg.norm(up)
    s = unit.stress[unit.keep] * force
    where = unit.points[unit.keep]
    if not len(s):
        return {"tension_mpa": 0.0, "z_tension_mpa": 0.0, "at": None, "z_at": None}
    principal = np.linalg.eigvalsh(s)[:, -1]
    along = np.einsum("i,nij,j->n", up, s, up)
    i, k = int(np.argmax(principal)), int(np.argmax(along))
    return {
        "tension_mpa": round(max(float(principal[i]), 0.0), 3),
        "strain_pct": round(100 * max(float(principal[i]), 0.0) / modulus, 3),
        "at": np.round(where[i], 2).tolist(),
        "z_tension_mpa": round(max(float(along[k]), 0.0), 3),
        "z_strain_pct": round(100 * max(float(along[k]), 0.0) / modulus, 3),
        "z_at": np.round(where[k], 2).tolist(),
    }


def strain_map(unit: Unit, force: float, modulus: float) -> np.ndarray:
    """The tension over the modulus at each surface node, under `force` N."""
    return np.maximum(np.linalg.eigvalsh(unit.stress * force)[:, -1], 0.0) / modulus


def faces_ahead(triangles: np.ndarray, origin: np.ndarray, direction: np.ndarray) -> int:
    """How many triangles a ray goes through, past the ones at its origin."""
    a = triangles[:, 0]
    ab = triangles[:, 1] - a
    ac = triangles[:, 2] - a
    across = np.cross(direction, ac)
    det = (ab * across).sum(axis=1)
    facing = np.abs(det) > 1e-12
    a, ab, ac, across, det = a[facing], ab[facing], ac[facing], across[facing], det[facing]
    to_origin = origin - a
    up = np.cross(to_origin, ab)
    u = (to_origin * across).sum(axis=1) / det
    v = (up * direction).sum(axis=1) / det
    t = (up * ac).sum(axis=1) / det
    return int(((u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0.01)).sum())


def clear_view(mesh: trimesh.Trimesh, peak: np.ndarray, normal: np.ndarray) -> np.ndarray:
    """Where to see the peak from: toward the outside there, turned a little so the shape reads as
    a solid, unless the part stands in the way. The peak under a floating arm faces the plate, and
    along its own normal the picture is the bottom of the plate. Then the first direction around
    it with nothing in between, or the one with the least."""
    wanted = [normal + 0.5 * np.array([0.6, -0.6, 0.6])]
    for elevation in np.radians((35.0, 15.0, 60.0, 0.0, -15.0, -35.0)):
        around = [
            np.array([math.cos(a) * math.cos(elevation), math.sin(a) * math.cos(elevation), 0.0])
            + np.array([0.0, 0.0, math.sin(elevation)])
            for a in np.radians(np.arange(0.0, 360.0, 45.0))
        ]
        wanted += sorted(around, key=lambda eye: -float(eye[:2] @ normal[:2]))
    triangles = mesh.triangles
    origin = peak + 0.05 * normal  # just off the surface: along it, a ray would graze its own edges
    best, fewest = wanted[0], None
    for eye in wanted:
        if np.linalg.norm(eye) < 1e-6:
            continue
        ahead = faces_ahead(triangles, origin, eye / np.linalg.norm(eye))
        if ahead == 0:
            return eye / np.linalg.norm(eye)
        if fewest is None or ahead < fewest:
            best, fewest = eye, ahead
    return best / np.linalg.norm(best)


def draw_strain(
    unit: Unit, strain: np.ndarray, limit: float, peak: Any, out: Path, caption: str
) -> None:
    """A PNG of the surface: white to red up to `limit`, a black dot at the peak, seen from where
    the peak can be seen."""
    import moderngl
    from PIL import ImageDraw

    from cadverify.cadcheck.render import Layer, basis_from, draw, font, orthographic

    mesh = trimesh.Trimesh(unit.points, unit.faces, process=False)
    # The facets of a volume mesh come in no order. The renderer paints a back face magenta to show
    # a flaw in a part's mesh, which this one is not: here it would only line the silhouettes.
    trimesh.repair.fix_normals(mesh, multibody=True)
    ratio = np.clip(strain[mesh.faces].mean(axis=1) / max(limit, 1e-9), 0.0, 1.0)
    colors = np.stack([np.ones_like(ratio), 1 - 0.85 * ratio, 1 - 0.85 * ratio], axis=1)
    peak = np.asarray(peak, float)
    nearest = int(np.argmin(np.linalg.norm(mesh.triangles_center - peak, axis=1)))
    eye = clear_view(mesh, peak, mesh.face_normals[nearest])
    basis = basis_from(eye, np.array([0.0, 0.0, 1.0]))
    tile = (900, 640)
    projection = orthographic(basis, mesh.vertices, tile, (20, 50, 20, 20))
    ctx = moderngl.create_context(standalone=True, backend="egl")
    try:
        image = draw(ctx, [Layer(mesh, colors)], [], projection, back=(0.55, 0.55, 0.55))
    finally:
        ctx.release()
    pixels, _ = projection.to_pixels(peak[None])
    x, y = pixels[0]
    pen = ImageDraw.Draw(image)
    pen.ellipse((x - 7, y - 7, x + 7, y + 7), outline=(0, 0, 0), width=3)
    pen.text((20, 16), caption, fill=(20, 20, 20), font=font(19))
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
