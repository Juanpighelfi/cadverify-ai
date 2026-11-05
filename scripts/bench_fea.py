"""The acceptance of G6's solver: a straight cantilever and a ring pinched across its diameter
against their closed forms, how far a finer mesh moves them, whether two runs agree, and the time.
Runs in the sandbox image, at the limits of a verification:

    docker run --rm --cpus 2 --memory 4g --memory-swap 4g -v "$PWD/scripts:/s:ro" \
        cadverify-sandbox python /s/bench_fea.py > results/g6_recomputed/bench_fea.json

Closed forms: a cantilever's L^3/(3EI) + L/(kGA), k = 5/6, and its root's tension FL(t/2)/I; a thin
ring pinched by two opposite forces, by Castigliano's theorem on its bending energy,
(pi/4 - 2/pi) FR^3/(EI), which is 0.1488 FR^3/(EI), and (1/pi) FR(t/2)/I at the load, which is
0.3183 FR(t/2)/I.
"""

from __future__ import annotations

import hashlib
import json
import resource
import sys
import time

import manifold3d
import numpy as np
import trimesh

from cadverify.cadcheck import fea

E, NU = 2750.0, 0.35


def cantilever(length: float, width: float, thick: float, scale: float):
    box = trimesh.creation.box((length, width, thick))
    box.apply_translation((length / 2, 0, 0))
    tips = box.vertices[box.vertices[:, 0] > length - 1e-6]

    def solve(hot, sc):
        tets = fea.filled(box, tips, max(thick, 0.5), sc, hot)
        return tets, fea.solve_unit(
            tets,
            E,
            NU,
            lambda c: c[:, 0] > length - 1e-6,
            lambda c: c[:, 0] < 1e-6,
            direction=np.array([0, 0, 1.0]),
        )

    up = np.array([1.0, 0.0, 0.0])
    tets, unit = solve(None, 1.0)
    tets, unit = solve(fea.hot_spots(unit, up), scale)
    inertia = width * thick**3 / 12
    shear = E / (2 * (1 + NU))
    compliance = length**3 / (3 * E * inertia) + length / (5 / 6 * width * thick * shear)
    return tets, unit, compliance, length * (thick / 2) / inertia, up


def ring(radius: float, thick: float, width: float, scale: float):
    outer_r, inner_r = radius + thick / 2, radius - thick / 2
    outer = manifold3d.Manifold.cylinder(width, outer_r, outer_r, 256)
    inner = manifold3d.Manifold.cylinder(width + 2, inner_r, inner_r, 256).translate((0, 0, -1))
    mesh = (outer - inner).to_mesh()
    body = trimesh.Trimesh(np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts))
    points = body.vertices[body.vertices[:, 1] > outer_r - 0.05]

    def solve(hot, sc):
        tets = fea.filled(body, points, 1.0, sc, hot)
        return tets, fea.solve_unit(
            tets,
            E,
            NU,
            lambda c: c[:, 1] > outer_r - 0.05,
            lambda c: c[:, 1] < -(outer_r - 0.05),
            direction=np.array([0, -1.0, 0]),
        )

    up = np.array([0.0, 0.0, 1.0])
    tets, unit = solve(None, 1.0)
    tets, unit = solve(fea.hot_spots(unit, up), scale)
    inertia = width * thick**3 / 12
    return (
        tets,
        unit,
        0.1488 * radius**3 / (E * inertia),
        0.3183 * radius * (thick / 2) / inertia,
        up,
    )


CASES = (
    ("cantilever L20 b6 t2", cantilever, (20, 6, 2)),
    ("cantilever L10 b4 t1", cantilever, (10, 4, 1)),
    ("cantilever L6.9 b6 t1.8", cantilever, (6.9, 6, 1.8)),
    ("ring R20 t3 b8", ring, (20, 3, 8)),
    ("ring R12 t1.5 b5", ring, (12, 1.5, 5)),
)


def main() -> int:
    rows = []
    for name, shape, args in CASES:
        previous = None
        for scale in (1.0, 0.7):
            started = time.perf_counter()
            tets, unit, compliance, tension, up = shape(*args, scale)
            peak = fea.peaks(unit, 1.0, E, up)
            rows.append(
                {
                    "case": name,
                    "scale": scale,
                    "tets": unit.tets,
                    "unknowns": int(unit.unknowns),
                    "compliance_vs_closed_form": round(unit.compliance / compliance, 3),
                    "tension_vs_closed_form": round(peak["tension_mpa"] / tension, 3),
                    "compliance_change_refining": None
                    if previous is None
                    else round(abs(unit.compliance - previous) / unit.compliance, 3),
                    "seconds": round(time.perf_counter() - started, 1),
                    "peak_rss_gb": round(
                        resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6, 2
                    ),
                }
            )
            previous = unit.compliance
    first, second = cantilever(20, 6, 2, 1.0), cantilever(20, 6, 2, 1.0)
    agree = (
        hashlib.sha256(first[1].stress.tobytes()).digest()
        == hashlib.sha256(second[1].stress.tobytes()).digest()
    )
    json.dump({"rows": rows, "deterministic": bool(agree)}, sys.stdout, indent=1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
