"""The part's verifiable specification and its check against the exported mesh.

The .scad declares what the part must measure with a structured echo, computed from its own
parameters, in the coordinates of the exported part (oriented for printing, in mm):

    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [130, 120, 50]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["wall", "-x", 5000], ["shelf", "-y", 5500]]],
        ["overhangs_allowed", [["hole roofs", [[95, -1, 0], [105, 7, 50]]]]]
    ]);

Only `bounds` is required. OpenSCAD cannot measure geometry, so the echo can only restate the
design intent; the harness measures the mesh and compares.

Two more keys for a part: `copies`, how many of it one unit needs (the assembly must place that
many), and `details`, the features the part announces, each with how to measure it
(cadcheck.details):

    ["copies", 2],
    ["details", [["arm rib", "material", [[x, y, z], [x, y, z]], 0.8],
                 ["slot", "void", [[x, y, z], [x, y, z]], 0.9],
                 ["flared mouth", "hole", [x, y, z], [dx, dy, dz], [[0, 14], [2, 10]]],
                 ["wall", "thickness", [x, y, z], [dx, dy, dz], 2.4],
                 ["emblem", "view", [[x, y, z], [x, y, z]]]]]

The assembly (`part = "assembly"`) declares instead, in assembly coordinates
(cadcheck.assembly):

    ["allowed_interferences", [["pin_right", "arm_top", "press fit"]]],
    ["motions", [["hinge", ["lid"], "rotate", [x, y, z], [ax, ay, az], [0, 90]],
                 ["drawer", ["tray"], "slide", [dx, dy, dz], [0, 30]]]],
    ["assembly_order", [[["base"], [0, 0, 0]],
                        [["insert"], [0, 0, -1]],
                        [["lid"], [0, 0, 1], ["rotate", [x, y, z], [ax, ay, az], 90]]]]

The assembly's own `bounds` (optional) and `support_faces` are measured on its instances
together. Bodies, through holes, overhangs, copies and details belong to each part: the assembly
is not printed, and its count of bodies or holes says nothing a part's spec does not.
"""

from __future__ import annotations

import json
import re
from typing import Any

import numpy as np
import trimesh

from cadverify.cadcheck import details as details_mod

SPEC_NAME = "cadverify_spec"
BOUNDS_TOLERANCE_MM = 0.2  # faceting of $fn circles stays below this at the usual sizes
PLANE_TOLERANCE_MM = 0.01
_FACING = np.cos(np.radians(1.0))
DIRECTIONS = {"+x": (0, 1), "-x": (0, -1), "+y": (1, 1), "-y": (1, -1), "+z": (2, 1), "-z": (2, -1)}
_AXES = "xyz"
_KEYS = {"bounds", "bodies", "through_holes", "support_faces", "overhangs_allowed"}
PART_KEYS = _KEYS | {"copies", "details"}
ASSEMBLY_KEYS = {"bounds", "support_faces", "allowed_interferences", "motions", "assembly_order"}
MOTIONS = ("rotate", "slide")


class SpecError(ValueError):
    """The echo is there but malformed; the message says what to fix."""


def find_spec(echo: list[str], assembly: bool = False) -> dict[str, Any] | None:
    """The parsed `cadverify_spec` echo, None when the program does not print one."""
    prefix = f"{SPEC_NAME} = "
    values = list(dict.fromkeys(e.removeprefix(prefix) for e in echo if e.startswith(prefix)))
    if not values:
        return None
    if len(values) > 1:
        raise SpecError(f"{SPEC_NAME} was printed {len(values)} times with different values")
    return parse_spec(values[0], assembly)


def parse_spec(text: str, assembly: bool = False) -> dict[str, Any]:
    try:
        data = json.loads(re.sub(r"\bundef\b", "null", text))
    except json.JSONDecodeError as exc:
        raise SpecError(f"{SPEC_NAME} is not a valid vector: {exc}") from None
    if not isinstance(data, list) or not all(_is_pair(p) for p in data):
        raise SpecError(f'{SPEC_NAME} must be a list of ["key", value] pairs')
    pairs = dict(data)
    if len(pairs) != len(data):
        raise SpecError(f"{SPEC_NAME} repeats a key")
    keys = ASSEMBLY_KEYS if assembly else PART_KEYS
    if unknown := set(pairs) - keys:
        where = "of the assembly" if assembly else "of a part"
        hint = ""
        if assembly and unknown <= PART_KEYS:
            hint = ": they belong to each part, in its own spec"
        raise SpecError(
            f"Unknown keys in the {SPEC_NAME} {where}: {sorted(unknown)}{hint}; valid: "
            f"{sorted(keys)}"
        )
    if "bounds" not in pairs and not assembly:
        raise SpecError(f'{SPEC_NAME} needs ["bounds", [[xmin, ymin, zmin], [xmax, ymax, zmax]]]')
    spec = {
        "bounds": _bounds(pairs["bounds"], "bounds") if "bounds" in pairs else None,
        "bodies": None if assembly else _count(pairs.get("bodies", 1), "bodies", minimum=1),
        "through_holes": None,
        "support_faces": [],
        "overhangs_allowed": [],
    }
    if pairs.get("through_holes") is not None:
        spec["through_holes"] = _count(pairs["through_holes"], "through_holes", minimum=0)
    for item in _list(pairs.get("support_faces", []), "support_faces"):
        if not (
            isinstance(item, list)
            and len(item) == 3
            and isinstance(item[0], str)
            and item[1] in DIRECTIONS
            and _number(item[2])
            and item[2] > 0
        ):
            raise SpecError(
                f'support_faces: each face is ["name", direction, minimum area in mm²] with '
                f"the direction in {list(DIRECTIONS)}; got {item!r}"
            )
        spec["support_faces"].append(
            {"name": item[0], "direction": item[1], "min_area_mm2": item[2]}
        )
    for item in _list(pairs.get("overhangs_allowed", []), "overhangs_allowed"):
        if not (isinstance(item, list) and len(item) == 2 and isinstance(item[0], str)):
            raise SpecError(
                f'overhangs_allowed: each zone is ["reason", [[xmin, ymin, zmin], [xmax, ymax, '
                f"zmax]]]; got {item!r}"
            )
        spec["overhangs_allowed"].append(
            {"name": item[0], "bounds": _bounds(item[1], f"overhangs_allowed {item[0]!r}")}
        )
    if assembly:
        spec.update(_assembly_keys(pairs))
    else:
        spec["copies"] = _count(pairs.get("copies", 1), "copies", minimum=1)
        spec["details"] = _details(pairs.get("details", []))
    return spec


def _details(value: Any) -> list[dict[str, Any]]:
    usage = (
        'details: each detail is ["name", kind, ...]: "material" or "void" with a box and the '
        'fraction (0 to 1) that must be full or empty; "hole" with a point outside the part on the '
        'axis, the direction inward and [[depth, diameter], ...]; "thickness" with a point '
        'outside the part, the direction inward and the mm; "view" with a box'
    )
    out, names = [], set()
    for item in _list(value, "details"):
        if not (isinstance(item, list) and len(item) >= 3 and isinstance(item[0], str)):
            raise SpecError(f"{usage}; got {item!r}")
        name, kind, args = item[0], item[1], item[2:]
        if name in names:
            raise SpecError(f"details: the name {name!r} repeats")
        names.add(name)
        where = f"details {name!r}"
        if kind in ("material", "void") and len(args) == 2:
            fraction = args[1]
            if not (_number(fraction) and 0 < fraction <= 1):
                raise SpecError(f"{where}: the fraction goes from 0 to 1; got {fraction!r}")
            detail = {"box": _bounds(args[0], where), "fraction": float(fraction)}
        elif kind == "view" and len(args) == 1:
            detail = {"box": _bounds(args[0], where)}
        elif kind == "hole" and len(args) == 3:
            diameters = _list(args[2], where)
            ok = diameters and all(
                isinstance(d, list)
                and len(d) == 2
                and _number(d[0])
                and _number(d[1])
                and d[0] >= 0
                and d[1] > 0
                for d in diameters
            )
            if not ok:
                raise SpecError(f"{where}: the diameters are [[depth >= 0, Ø > 0], ...]")
            detail = {
                "point": _vector(args[0], where),
                "direction": _direction(args[1], where),
                "diameters": [[float(a), float(b)] for a, b in diameters],
            }
        elif kind == "thickness" and len(args) == 3:
            if not (_number(args[2]) and args[2] > 0):
                raise SpecError(f"{where}: the thickness is a number of mm > 0")
            detail = {
                "point": _vector(args[0], where),
                "direction": _direction(args[1], where),
                "mm": float(args[2]),
            }
        else:
            raise SpecError(f"{usage}; got {item!r}")
        out.append({"name": name, "kind": kind, **detail})
    return out


def _assembly_keys(pairs: dict[str, Any]) -> dict[str, Any]:
    allowed = []
    for item in _list(pairs.get("allowed_interferences", []), "allowed_interferences"):
        if not (
            isinstance(item, list) and len(item) == 3 and all(isinstance(x, str) for x in item)
        ):
            raise SpecError(
                'allowed_interferences: each one is ["instance", "instance", "reason"]; '
                f"got {item!r}"
            )
        allowed.append({"a": item[0], "b": item[1], "reason": item[2]})
    motions = []
    for item in _list(pairs.get("motions", []), "motions"):
        usage = (
            'motions: ["name", ["instance", ...], "rotate", point, axis, [from, to]] (degrees) '
            'or ["name", ["instance", ...], "slide", direction, [from, to]] (mm)'
        )
        if not (isinstance(item, list) and len(item) >= 5 and isinstance(item[0], str)):
            raise SpecError(f"{usage}; got {item!r}")
        name, moving, kind = item[0], _names(item[1], f"motions {item[0]!r}"), item[2]
        where = f"motions {name!r}"
        if kind == "rotate" and len(item) == 6:
            motion = {
                "point": _vector(item[3], where),
                "axis": _direction(item[4], where),
                "range": _range(item[5], where),
            }
        elif kind == "slide" and len(item) == 5:
            motion = {"axis": _direction(item[3], where), "range": _range(item[4], where)}
        else:
            raise SpecError(f"{usage}; got {item!r}")
        motions.append({"name": name, "instances": moving, "kind": kind, **motion})
    steps = []
    for item in _list(pairs.get("assembly_order", []), "assembly_order"):
        usage = (
            'assembly_order: each step is [["instance", ...], direction it comes in from] or, if '
            'it turns after it comes in, [["instance", ...], direction, ["rotate", point, axis, '
            "degrees]]"
        )
        if not (isinstance(item, list) and len(item) in (2, 3)):
            raise SpecError(f"{usage}; got {item!r}")
        where = f"assembly_order {item[0]!r}"
        step = {"instances": _names(item[0], where), "direction": _vector(item[1], where)}
        if len(item) == 3:
            turn = item[2]
            if not (isinstance(turn, list) and len(turn) == 4 and turn[0] == "rotate"):
                raise SpecError(f"{usage}; got {item!r}")
            if not _number(turn[3]):
                raise SpecError(f"{where}: the turn is a number of degrees")
            step["turn"] = {
                "point": _vector(turn[1], where),
                "axis": _direction(turn[2], where),
                "degrees": float(turn[3]),
            }
        steps.append(step)
    return {"allowed_interferences": allowed, "motions": motions, "assembly_order": steps}


def _names(value: Any, where: str) -> list[str]:
    if isinstance(value, str):
        value = [value]
    if not (isinstance(value, list) and value and all(isinstance(v, str) for v in value)):
        raise SpecError(f"{where}: the instances are a list of names")
    return list(value)


def _vector(value: Any, where: str) -> list[float]:
    if not (isinstance(value, list) and len(value) == 3 and all(map(_number, value))):
        raise SpecError(f"{where}: expected a vector [x, y, z]; got {value!r}")
    return [float(v) for v in value]


def _direction(value: Any, where: str) -> list[float]:
    vector = _vector(value, where)
    norm = float(np.linalg.norm(vector))
    if norm < 1e-9:
        raise SpecError(f"{where}: the direction cannot be zero")
    return [v / norm for v in vector]


def _range(value: Any, where: str) -> list[float]:
    if not (isinstance(value, list) and len(value) == 2 and all(map(_number, value))):
        raise SpecError(f"{where}: the range is [from, to]")
    lo, hi = sorted(float(v) for v in value)
    if hi - lo <= 0:
        raise SpecError(f"{where}: the range cannot be empty")
    return [lo, hi]


def check_spec(mesh: trimesh.Trimesh, report: dict[str, Any], spec: dict[str, Any]) -> dict:
    """Bounds, body count, through holes, support faces and details of the mesh against the
    spec. The assembly's own spec checks only what it declares of the part keys."""
    checks: dict[str, Any] = {}
    if spec.get("bounds") is not None:
        checks["bounds"] = _check_bounds(report["bounds"], spec["bounds"])
    if spec["bodies"] is not None:
        checks["bodies"] = {
            "ok": report["bodies"] == spec["bodies"],
            "expected": spec["bodies"],
            "actual": report["bodies"],
        }
    if spec["through_holes"] is not None:
        checks["through_holes"] = {
            "ok": report["through_holes"] == spec["through_holes"],
            "expected": spec["through_holes"],
            "actual": report["through_holes"],
        }
    checks["support_faces"] = [support_face(mesh, **face) for face in spec["support_faces"]]
    checks["details"] = []
    if spec.get("details"):
        from cadverify.cadcheck.section import to_manifold

        checks["details"] = details_mod.measure(mesh, to_manifold(mesh), spec["details"])
    ok = (
        all(c["ok"] for c in checks.values() if isinstance(c, dict))
        and all(f["ok"] for f in checks["support_faces"])
        and all(d["ok"] for d in checks["details"])
    )
    return {"ok": bool(ok), **checks}


def support_face(
    mesh: trimesh.Trimesh, name: str, direction: str, min_area_mm2: float
) -> dict[str, Any]:
    """Is the outermost plane of the part in `direction` a flat face of at least the area?

    A part rests flush on a wall or a shelf only if nothing sticks out past its contact face,
    so the face must lie on the extreme plane. When it does not, `largest_flat_face` says where
    the biggest flat face in that direction is and `protrusion_mm` how far material sticks out.
    """
    axis, sign = DIRECTIONS[direction]
    coord = sign * mesh.vertices[:, axis]
    extreme = float(coord.max())
    corner = coord[mesh.faces]
    flat = (sign * mesh.face_normals[:, axis] > _FACING) & (
        np.ptp(corner, axis=1) <= PLANE_TOLERANCE_MM
    )
    on_extreme = flat & np.all(corner >= extreme - PLANE_TOLERANCE_MM, axis=1)
    area = float(mesh.area_faces[on_extreme].sum())
    result: dict[str, Any] = {
        "name": name,
        "direction": direction,
        "ok": area >= min_area_mm2,
        "min_area_mm2": min_area_mm2,
        "area_on_extreme_plane_mm2": round(area, 1),
        "extreme_plane": f"{_AXES[axis]} = {_mm(sign * extreme)}",
    }
    if flat.any():
        levels = np.round(corner[flat].mean(axis=1) / PLANE_TOLERANCE_MM).astype(np.int64)
        unique, inverse = np.unique(levels, return_inverse=True)
        areas = np.bincount(inverse, weights=mesh.area_faces[flat])
        best = int(np.argmax(areas))
        level = unique[best] * PLANE_TOLERANCE_MM
        result["largest_flat_face"] = {
            "plane": f"{_AXES[axis]} = {_mm(sign * level)}",
            "area_mm2": round(float(areas[best]), 1),
        }
        protrusion = extreme - level
        if protrusion > PLANE_TOLERANCE_MM:
            result["protrusion_mm"] = round(protrusion, 3)
    return result


def _check_bounds(actual: list, expected: list) -> dict[str, Any]:
    deviations = []
    for side, label in ((0, "min"), (1, "max")):
        for axis in range(3):
            delta = actual[side][axis] - expected[side][axis]
            if abs(delta) > BOUNDS_TOLERANCE_MM:
                deviations.append(
                    f"{label} {_AXES[axis]}: measured {actual[side][axis]:.3f}, specified "
                    f"{expected[side][axis]:g} (off by {delta:+.3f} mm)"
                )
    return {
        "ok": not deviations,
        "expected": expected,
        "actual": actual,
        "tolerance_mm": BOUNDS_TOLERANCE_MM,
        "deviations": deviations,
    }


def _mm(value: float) -> str:
    return f"{value + 0.0:.3f}".replace("-0.000", "0.000")


def _is_pair(item: Any) -> bool:
    return isinstance(item, list) and len(item) == 2 and isinstance(item[0], str)


def _number(value: Any) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool)


def _list(value: Any, key: str) -> list:
    if not isinstance(value, list):
        raise SpecError(f"{key} must be a list")
    return value


def _count(value: Any, key: str, minimum: int) -> int:
    if not (_number(value) and float(value).is_integer() and value >= minimum):
        raise SpecError(f"{key} must be an integer >= {minimum}; got {value!r}")
    return int(value)


def _bounds(value: Any, key: str) -> list[list[float]]:
    ok = (
        isinstance(value, list)
        and len(value) == 2
        and all(isinstance(c, list) and len(c) == 3 and all(map(_number, c)) for c in value)
    )
    if not ok or any(lo > hi for lo, hi in zip(value[0], value[1], strict=True)):
        raise SpecError(
            f"{key} must be [[xmin, ymin, zmin], [xmax, ymax, zmax]] with min <= max; got {value!r}"
        )
    return [[float(v) for v in corner] for corner in value]
