"""slice_report: what a real slicer makes of a part: its grams, its hours, and whether it prints
what was drawn. The mesh can be right and the print wrong: a wall thinner than a line of plastic
is in the STL and not in the G-code.

PrusaSlicer, pinned in the image, with the profile of this directory (a Bambu Lab A1 at 0.4 mm and
0.2 mm layers) and its Arachne walls, the walls Bambu Studio uses too. Run twice:

- as it would print, for the grams and the hours. The hours are the slicer's estimate on the
  machine's public limits, not what the printer's firmware will report;
- solid (100% infill), where the plastic should cover the whole section: each line of the G-code
  drawn as a stroke of its own width, against the section of the mesh at the middle of that layer.
  What is left over on the edge of the section, past a small area, for three layers or more, is a
  part of the drawing the slicer does not print. That leaves G5 red (agent/gates.py).

The thickness of the walls against the line width is reported too: a wall of one line prints, and
is weak, and that is for the designer to know.
"""

from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path
from typing import Any

import numpy as np
import shapely
import trimesh

from cadverify.cadcheck.materials import MATERIALS
from cadverify.cadcheck.mesh import load_exact

PROFILE = Path(__file__).with_name("slicer") / "a1_04.ini"
CENTER = (128.0, 128.0)
ENGINE = "PrusaSlicer 2.9.2"
SLICE_TIMEOUT_S = 180
LINE_WIDTH_MM = 0.42
MAX_COMPARED_LAYERS = 60
TOLERANCE_MM = 0.02  # a stroke's edge against the mesh's: the slicer's own rounding
OPENING_MM = 0.02  # what is thinner than twice this is a seam between strokes, not a wall
LAYER_MM = 0.2
LOST_AREA_MM2 = 0.4
LOST_NEAR_MM = 3.0  # the same region, a layer later, is within this
LOST_MIN_LAYERS = 3
ON_THE_EDGE = 0.3  # the share of a leftover's outline that has to lie on the section's own edge


def slice_report(
    stl: str | Path, out_dir: str | Path, material: str | None = None
) -> dict[str, Any]:
    """The report of an STL, as it is oriented for printing. `ok` says that it ran."""
    t0 = time.perf_counter()
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stl = Path(stl)
    name = material if material in MATERIALS else "PLA"
    density = MATERIALS[name].density_g_cm3
    report: dict[str, Any] = {
        "ok": False,
        "engine": ENGINE,
        "profile": PROFILE.stem,
        "material": name,
        "material_assumed": material not in MATERIALS,
        "line_width_mm": LINE_WIDTH_MM,
    }
    mesh = load_exact(stl)
    try:
        printed = _slice(stl, out_dir / f"{stl.stem}.gcode", density)
        solid = _slice(
            stl,
            out_dir / f"{stl.stem}.solid.gcode",
            density,
            "--fill-density",
            "100%",
            "--fill-pattern",
            "rectilinear",
            "--top-solid-layers",
            "0",
            "--bottom-solid-layers",
            "0",
        )
    except _SlicerError as exc:
        report["error"] = str(exc)
        report["seconds"] = round(time.perf_counter() - t0, 1)
        return report
    report.update(_totals(printed))
    report.update(_walls(mesh))
    report.update(_compare(mesh, solid))
    report["ok"] = True
    report["seconds"] = round(time.perf_counter() - t0, 1)
    printed.unlink(missing_ok=True)
    solid.unlink(missing_ok=True)
    return report


class _SlicerError(RuntimeError):
    pass


def _slice(stl: Path, out: Path, density: float, *extra: str) -> Path:
    command = ["prusa-slicer", "--export-gcode", "--load", str(PROFILE)]
    command += ["--center", f"{CENTER[0]:g},{CENTER[1]:g}", "--filament-density", f"{density:g}"]
    command += [*extra, "--output", str(out), str(stl)]
    try:
        run = subprocess.run(
            command, capture_output=True, text=True, timeout=SLICE_TIMEOUT_S, check=False
        )
    except subprocess.TimeoutExpired as exc:
        raise _SlicerError(f"the slicer ran over {SLICE_TIMEOUT_S} s") from exc
    except OSError as exc:
        raise _SlicerError(f"the slicer did not start: {exc}") from exc
    if run.returncode != 0 or not out.exists():
        said = (run.stderr or run.stdout).strip().splitlines()[-3:]
        raise _SlicerError(f"the slicer failed (exit {run.returncode}): {' '.join(said)[:400]}")
    return out


_TIME = re.compile(r"(?:(\d+)d\s*)?(?:(\d+)h\s*)?(?:(\d+)m\s*)?(?:(\d+)s)?")


def _totals(gcode: Path) -> dict[str, Any]:
    """Grams and hours, from the comments the slicer leaves at the end of its G-code."""
    grams, hours, metres = None, None, None
    for line in gcode.read_text(encoding="utf-8", errors="replace").splitlines()[-400:]:
        if line.startswith("; total filament used [g]") or (
            line.startswith("; filament used [g]") and grams is None
        ):
            grams = float(line.split("=")[1])
        elif line.startswith("; filament used [mm]"):
            metres = float(line.split("=")[1]) / 1000
        elif line.startswith("; estimated printing time (normal mode)"):
            days, h, m, s = _TIME.search(line.split("=")[1].strip()).groups()
            seconds = 86400 * int(days or 0) + 3600 * int(h or 0) + 60 * int(m or 0) + int(s or 0)
            hours = seconds / 3600
    return {
        "grams": None if grams is None else round(grams, 1),
        "hours": None if hours is None else round(hours, 2),
        "filament_m": None if metres is None else round(metres, 2),
    }


def _walls(mesh: trimesh.Trimesh) -> dict[str, Any]:
    """How thin the walls are against a line of plastic."""
    from cadverify.cadcheck.fea import wall_sizes

    centers, walls = wall_sizes(mesh)
    finite = np.isfinite(walls)
    if not finite.any():
        return {"thinnest_wall_mm": None, "lines_in_thinnest_wall": None}
    thin = float(np.percentile(walls[finite], 1))
    where = centers[finite][int(np.argmin(np.abs(walls[finite] - thin)))]
    return {
        "thinnest_wall_mm": round(thin, 2),
        "thinnest_at": np.round(where, 2).tolist(),
        "lines_in_thinnest_wall": round(thin / LINE_WIDTH_MM, 1),
    }


def parse_layers(gcode: Path) -> list[dict[str, Any]]:
    """Each layer's top Z, height and strokes: [x0, y0, x1, y1, width]. Only what extrudes while it
    moves; relative E, as the profile asks for."""
    layers: list[dict[str, Any]] = []
    x = y = 0.0
    width, height = LINE_WIDTH_MM, 0.2
    current: dict[str, Any] | None = None
    number = re.compile(r"([XYZEF])(-?\d*\.?\d+)")
    for line in gcode.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(";Z:"):
            current = {"z": float(line[3:]), "height": height, "strokes": []}
            layers.append(current)
        elif line.startswith(";HEIGHT:"):
            height = float(line[8:])
            if current is not None:
                current["height"] = height
        elif line.startswith(";WIDTH:"):
            width = float(line[7:])
        elif line.startswith(("G1 ", "G0 ")):
            words = dict(number.findall(line.split(";")[0]))
            nx, ny = float(words.get("X", x)), float(words.get("Y", y))
            if float(words.get("E", 0.0)) > 0 and (nx != x or ny != y) and current is not None:
                current["strokes"].append((x, y, nx, ny, width))
            x, y = nx, ny
    return layers


def _compare(mesh: trimesh.Trimesh, gcode: Path) -> dict[str, Any]:
    """The section of the mesh against the strokes of the solid slice, layer by layer."""
    from cadverify.cadcheck import section

    solid = section.to_manifold(mesh)
    if solid is None:
        return {"lost": [], "compared_layers": 0, "not_compared": "the mesh is not a closed solid"}
    low, high = mesh.bounds
    by_height = {round(layer["z"], 3): layer["strokes"] for layer in parse_layers(gcode)}
    # The mesh's layers, not the G-code's: a wall the slicer drops can leave a layer with no plastic
    # at all, or end the print early, and those are the layers that matter most.
    count = max(1, int(round((high[2] - low[2]) / LAYER_MM)))
    layers = [LAYER_MM * (i + 1) for i in range(count)]
    shift = np.array([CENTER[0] - (low[0] + high[0]) / 2, CENTER[1] - (low[1] + high[1]) / 2])
    step = max(1, len(layers) // MAX_COMPARED_LAYERS)
    seen: list[dict[str, Any]] = []
    ratios = []
    for top in layers[::step]:
        z = low[2] + top - LAYER_MM / 2
        polygons = section._cross_section_polygons(solid.slice(float(z)))
        if not polygons:
            continue
        drawn = shapely.union_all(polygons)
        strokes = by_height.get(round(top, 3)) or []
        if strokes:
            strokes = np.asarray(strokes)
            lines = shapely.linestrings(strokes[:, :4].reshape(-1, 2, 2) - shift)
            printed = shapely.union_all(shapely.buffer(lines, strokes[:, 4] / 2, quad_segs=2))
            lengths = np.linalg.norm(strokes[:, 2:4] - strokes[:, :2], axis=1)
            ratios.append(float((lengths * strokes[:, 4]).sum() / max(drawn.area, 1e-6)))
            left = drawn.difference(printed.buffer(TOLERANCE_MM))
        else:
            ratios.append(0.0)
            left = drawn
        opened = left.buffer(-OPENING_MM).buffer(OPENING_MM)
        edge = drawn.boundary.buffer(TOLERANCE_MM + 2 * OPENING_MM)
        for piece in getattr(opened, "geoms", [opened]):
            if piece.is_empty or piece.area < LOST_AREA_MM2:
                continue
            # A wall the slicer drops is on the edge of the section. A gap inside it, between the
            # walls and the infill of a round part, is how any print fills a section.
            on_edge = piece.boundary.intersection(edge).length / max(piece.boundary.length, 1e-6)
            if on_edge < ON_THE_EDGE:
                continue
            point = piece.representative_point()
            seen.append(
                {
                    "z": round(float(z), 2),
                    "at": [round(point.x, 2), round(point.y, 2)],
                    "area_mm2": round(piece.area, 2),
                    "across_mm": round(2 * piece.area / max(piece.length, 1e-6), 2),
                }
            )
    return {
        "layers": len(layers),
        "compared_layers": len(layers[::step]),
        "extruded_vs_section": {
            "lowest": round(min(ratios), 3) if ratios else None,
            "median": round(float(np.median(ratios)), 3) if ratios else None,
        },
        "lost": _lasting(seen),
    }


def _lasting(seen: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """The regions left over on enough compared layers, each once, the largest first. One on a
    layer or two is the tip of a slope or a seam, not a wall."""
    groups: list[dict[str, Any]] = []
    for item in seen:
        at = np.array(item["at"])
        for group in groups:
            if np.linalg.norm(np.array(group["at"]) - at) <= LOST_NEAR_MM:
                group["layers"] += 1
                group["z_to"] = item["z"]
                group["area_mm2"] = max(group["area_mm2"], item["area_mm2"])
                break
        else:
            groups.append({**item, "z_to": item["z"], "layers": 1})
    lasting = [g for g in groups if g["layers"] >= LOST_MIN_LAYERS]
    return sorted(lasting, key=lambda g: -g["area_mm2"])[:10]
