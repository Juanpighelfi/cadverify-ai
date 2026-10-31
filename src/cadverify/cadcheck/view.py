"""render_view: one view on demand, to see the part as a physical object.

What render_sheet does not: a free camera (a named view, a direction or azimuth and elevation),
orthographic or perspective; zoom to a box or to a point with a size in mm; a cut by any plane,
with the cut face in its own color and, next to the view, the 2D profile of the cut with a mm
grid and its numbers; several parts at once, exploded; and highlights: overhang zones, the
spec's support faces, the spec's bounds box and the through holes.

The request is a JSON object (cadcheck view < request.json):

    {"parts": [{"stl": "exports/a.stl", "label": "a", "spec": {...} or null}],
     "out": "renders/view-012.png",
     "camera": {"view": "iso"} | {"direction": [x, y, z]} | {"azimuth": a, "elevation": e},
     "projection": "orthographic" | "perspective",
     "zoom": {"center": [x, y, z], "size_mm": s} | {"box": [[x, y, z], [x, y, z]]},
     "cut": {"point": [x, y, z], "normal": [x, y, z]},
     "explode": mm,
     "highlight": ["overhangs", "support_faces", "spec_bounds", "holes", "details"],
     "title": "..."}

"details" draws each detail the spec declares (cadcheck.details) with its measurement: the box
of a material, void or view detail, the axis of a hole, the ray of a thickness. Every view
also says, for each declared detail, whether it is in the frame and how many pixels it spans
(`details_in_view`): a close look at a detail is what G7 asks for a "view" detail.

Every coordinate is in the parts' own mm, as exported. The cut removes the side its normal
points to, so the cut face looks towards +normal.
"""

from __future__ import annotations

import hashlib
import math
import time
from pathlib import Path
from typing import Any

import numpy as np
import shapely
import trimesh
from PIL import Image, ImageDraw
from scipy.ndimage import binary_erosion
from scipy.spatial import cKDTree

from cadverify.cadcheck import details as details_mod
from cadverify.cadcheck import section
from cadverify.cadcheck.mesh import load_exact
from cadverify.cadcheck.printability import overhang_faces, overhang_zones
from cadverify.cadcheck.render import (
    BACK,
    BODY,
    DEFECT,
    HEADER,
    LINE,
    VIEWS,
    Layer,
    Lines,
    axes,
    basis_from,
    classify_edges,
    draw,
    font,
    layer_map,
    legend,
    nice_length,
    orthographic,
    perspective,
    scale_bar,
)
from cadverify.cadcheck.spec import DIRECTIONS, support_face

VIEW_TILE = (1200, 900)
PROFILE_TILE = (900, 900)
VIEW_MARGIN = (30, 60, 30, 70)
HIGHLIGHTS = ("overhangs", "support_faces", "spec_bounds", "holes", "details")
# A detail is seen up close when its box spans at least this share of the tile's short side.
CLOSE_SHARE = 0.25
MAX_LABELS = 20
LABEL_INSET = 4  # px: a part's label point lies this far inside what is seen of it...
LABEL_MARGIN = 24  # px: ...and this far from the tile's border, when there is room

PART_COLORS = [BODY, (0.82, 0.74, 0.58), (0.75, 0.70, 0.86), (0.60, 0.80, 0.80), (0.86, 0.70, 0.66)]
CAP = (0.93, 0.50, 0.50)
OVERHANG = (1.00, 0.55, 0.00)
OVERHANG_OK = (0.95, 0.85, 0.30)
SUPPORT = (0.35, 0.75, 0.40)
HOLE = (0.55, 0.40, 0.85)
SPEC_BOX = (0.10, 0.35, 0.85)
DETAIL_OK = (0.05, 0.55, 0.45)
DETAIL_BAD = (0.85, 0.10, 0.20)
HOLE_TEXT = (60, 30, 120)  # a hole's diameter in the cut's profile


class ViewError(ValueError):
    """A request the tool cannot draw; the message says what to change."""


def render_view(request: dict[str, Any]) -> dict[str, Any]:
    t0 = time.perf_counter()
    try:
        return _render(request, t0)
    except ViewError as exc:
        return {"ok": False, "error": str(exc)}


def _render(request: dict[str, Any], t0: float) -> dict[str, Any]:
    parts = request.get("parts") or []
    if not parts:
        raise ViewError("At least one STL is needed")
    highlight = list(request.get("highlight") or [])
    if unknown := set(highlight) - set(HIGHLIGHTS):
        raise ViewError(f"Unknown highlights: {sorted(unknown)}; valid: {list(HIGHLIGHTS)}")
    loaded = []
    for i, part in enumerate(parts):
        mesh = load_exact(part["stl"])
        if len(mesh.faces) == 0:
            raise ViewError(f"{part['stl']}: empty mesh")
        sha = hashlib.sha256(Path(part["stl"]).read_bytes()).hexdigest()
        loaded.append(
            {**part, "label": part.get("label") or f"p{i + 1}", "mesh": mesh, "sha256": sha}
        )
    offsets = _explode(loaded, float(request.get("explode") or 0))
    cut = request.get("cut")
    plane = None
    if cut:
        normal = np.asarray(cut.get("normal"), float)
        point = np.asarray(cut.get("point"), float)
        if normal.shape != (3,) or point.shape != (3,) or np.linalg.norm(normal) < 1e-9:
            raise ViewError("cut: point and normal are vectors [x, y, z], the normal not zero")
        plane = (point, normal / np.linalg.norm(normal))

    basis, camera_text = _camera(request.get("camera") or {}, plane)
    result_parts, layers, lines, labels, profiles = [], [], [], [], []
    numbers: dict[str, Any] = {}
    for i, (part, offset) in enumerate(zip(loaded, offsets, strict=True)):
        color = PART_COLORS[i % len(PART_COLORS)]
        drawn = _part_scene(part, offset, plane, highlight, color, basis[2])
        layers.append(drawn["layer"])
        lines += drawn["lines"]
        labels += drawn["labels"]
        if drawn["profile"] is not None:
            profiles.append((part["label"], drawn["profile"]))
        result_parts.append(
            {
                "label": part["label"],
                "stl": part["stl"],
                "sha256": part["sha256"],
                "triangles": len(part["mesh"].faces),
                "bounds": _r(part["mesh"].bounds),
                "offset": _r(offset),
            }
        )
        for key, value in drawn["numbers"].items():
            numbers.setdefault(key, []).append({"part": part["label"], **value})

    points = np.vstack([layer.mesh.vertices for layer in layers if len(layer.mesh.faces)])
    focus = _focus(request.get("zoom"))
    persp = (request.get("projection") or "orthographic") == "perspective"
    make = perspective if persp else orthographic
    projection = make(basis, points, VIEW_TILE, VIEW_MARGIN, focus)

    import moderngl

    ctx = moderngl.create_context(standalone=True, backend="egl")
    try:
        tile = draw(ctx, layers, lines, projection, BACK)
        shown = layer_map(ctx, layers, projection) if len(loaded) > 1 else None
        renderer = ctx.info["GL_RENDERER"]
    finally:
        ctx.release()
    framing = _details_in_view(loaded, offsets, projection, plane)
    pixel_labels = _in_pixels(projection, labels)
    if shown is not None:
        part_labels, seen = _part_labels(loaded, layers, projection, shown)
        pixel_labels += part_labels
        for item, visible in zip(result_parts, seen, strict=True):
            item["visible"] = visible
    _labels(tile, pixel_labels)
    _annotate_view(tile, projection, camera_text, focus)
    panels = [tile]
    if profiles:
        panels.append(_profile_panel(profiles, plane))
    width = sum(p.size[0] for p in panels)
    used = _used_colors(layers, lines, len(loaded))
    title = _header_lines(
        request.get("title") or ", ".join(p["label"] for p in loaded), loaded, width - 24
    )
    rows = legend(ImageDraw.Draw(Image.new("RGB", (1, 1))), used, (12, 38), width - 24)
    header = HEADER + 24 * (rows - 1) + 24 * (len(title) - 1)
    sheet = Image.new("RGB", (width, header + VIEW_TILE[1]), "white")
    x = 0
    for panel in panels:
        sheet.paste(panel, (x, header))
        x += panel.size[0]
    _header(sheet, title, used)
    out = Path(request["out"])
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    result: dict[str, Any] = {
        "ok": True,
        "path": str(out),
        "size": list(sheet.size),
        "camera": {
            "direction": _r(basis[2]),
            "screen_right": _r(basis[0]),
            "screen_up": _r(basis[1]),
            "projection": "perspective" if persp else "orthographic",
            "mm_per_px": round(1 / projection.px_per_mm, 4) if projection.px_per_mm else None,
            "zoom": None if focus is None else {"center": _r(focus[0]), "size_mm": focus[1]},
        },
        "parts": result_parts,
        **numbers,
        **({"details_in_view": framing} if framing else {}),
        "renderer": renderer,
        "seconds": round(time.perf_counter() - t0, 3),
    }
    if plane is not None:
        result["cut_plane"] = {"point": _r(plane[0]), "normal": _r(plane[1])}
    return result


def _part_scene(part, offset, plane, highlight, base_color, eye) -> dict[str, Any]:
    """The faces, lines, labels and numbers one part contributes to the view."""
    mesh: trimesh.Trimesh = part["mesh"]
    spec = part.get("spec") or {}
    numbers: dict[str, Any] = {}
    labels: list[tuple[np.ndarray, str, tuple]] = []
    lines: list[Lines] = []
    edges = classify_edges(mesh)

    drawn, cap, prof = mesh, np.zeros(len(mesh.faces), bool), None
    if plane is not None:
        cut = section.cut(mesh, plane[0], plane[1])
        drawn, cap, prof = cut.mesh, cut.cap, cut.profile
        numbers["cut"] = prof.numbers()
    keep = (lambda p: (p - plane[0]) @ plane[1] <= 1e-6) if plane is not None else None

    colors = np.tile(base_color, (len(drawn.faces), 1))
    if "support_faces" in highlight:
        faces_ok, results = _support_faces(mesh, drawn, spec, eye)
        colors[faces_ok] = SUPPORT
        numbers["support_faces"] = {"faces": results}
        for item in results:
            if item.get("_anchor") is not None:
                text = _facing_text(item["name"], item["faces_camera"])
                labels.append((item.pop("_anchor") + offset, text, SUPPORT))
            item.pop("_anchor", None)
    if "holes" in highlight:
        holes = section.through_holes(mesh)
        owner = section.hole_faces(drawn, holes)
        colors[owner >= 0] = HOLE
        for hole in holes:
            hole.pop("_footprint")
            axis = "xyz".index(hole["axis"])
            a, b = np.array(hole["center"]), np.array(hole["center"])
            a[axis], b[axis] = hole["from"] - 4, hole["to"] + 4
            if keep is None or keep(np.array(hole["center"])):
                lines.append(Lines(_dashed(a + offset, b + offset, 2.0), HOLE, 4.0, on_top=True))
                ax = hole["axis"]
                ends = (
                    f"{ax}={hole['from']:g}: Ø{_mm(hole['diameter_at_from_mm'])} · "
                    f"{ax}={hole['to']:g}: Ø{_mm(hole['diameter_at_to_mm'])}"
                )
                labels.append((b + offset, f"{hole['id']} {ends}", HOLE))
        genus = _genus(mesh)
        numbers["holes"] = {
            "found_along_xyz": len(holes),
            "through_holes_total": genus,
            "holes": holes,
            "note": "diameter_at_from/to: measured 0.05 mm inside each end of the hole, "
            "at 'from' and 'to' along the axis",
        }
    if "overhangs" in highlight:
        zones, face_zone = _overhangs(mesh, drawn, cap, spec)
        for zone_index, zone in enumerate(zones):
            faces = face_zone == zone_index
            colors[faces] = OVERHANG_OK if zone["declared"] else OVERHANG
            zone["faces_camera"] = _faces_camera(drawn, faces, eye)
        numbers["overhangs"] = {
            "zones": len(zones),
            "undeclared": sum(not z["declared"] for z in zones),
            "zone_list": [{k: v for k, v in z.items() if k != "_faces"} for z in zones[:15]],
        }
        for zone in zones[:MAX_LABELS]:
            center = np.mean(np.reshape(zone["bounds"], (2, 3)), axis=0)
            if keep is None or keep(center):
                color = (0.6, 0.5, 0.0) if zone["declared"] else OVERHANG
                text = _facing_text(zone["id"], zone["faces_camera"])
                labels.append((center + offset, text, color))
    if "details" in highlight:
        found, detail_lines, detail_labels = _details(mesh, spec, offset, keep)
        numbers["details"] = {"details": found}
        lines += detail_lines
        labels += detail_labels
    if "spec_bounds" in highlight:
        box = spec.get("bounds")
        if box:
            edges_ = _box_edges(np.asarray(box, float)) + offset
            lines.append(Lines(edges_, SPEC_BOX, 3.0, on_top=True))
            numbers["spec_bounds"] = {
                "spec": box,
                "measured": _r(mesh.bounds),
                "deviation_mm": _r(mesh.bounds - np.asarray(box, float)),
            }
        else:
            numbers["spec_bounds"] = {"note": "the part has no cadverify_spec with bounds"}
    colors[cap] = CAP

    shifted = drawn.copy()
    shifted.apply_translation(offset)
    drawn_edges = classify_edges(shifted) if plane is not None else edges
    outline = np.vstack([drawn_edges.sharp, drawn_edges.silhouette(shifted.face_normals, eye)])
    # Defects come from the uncut part: a cut made with the trimesh fallback may leave its own
    # open edges, which are not defects of the part.
    defect_segments = mesh.vertices[np.vstack([edges.open, edges.nonmanifold])]
    if keep is not None and len(defect_segments):
        defect_segments = defect_segments[keep(defect_segments.mean(axis=1))]
    lines = [
        Lines(shifted.vertices[outline], LINE, 3.0),
        Lines(defect_segments + offset, DEFECT, 6.0, on_top=True),
        *lines,
    ]
    return {
        "layer": Layer(shifted, colors),
        "lines": lines,
        "labels": labels,
        "profile": prof,
        "numbers": numbers,
    }


def _details(mesh, spec, offset, keep) -> tuple[list[dict], list[Lines], list[tuple]]:
    """Each declared detail measured, drawn where it is and labeled with what was measured."""
    declared = spec.get("details") or []
    if not declared:
        return [{"note": "the part declares no details in cadverify_spec"}], [], []
    measured = details_mod.measure(mesh, section.to_manifold(mesh), declared)
    lines, labels = [], []
    for detail, result in zip(declared, measured, strict=True):
        color = DETAIL_OK if result["ok"] else DETAIL_BAD
        if "box" in detail:
            box = np.asarray(detail["box"], float)
            lines.append(Lines(_box_edges(box) + offset, color, 3.0, on_top=True))
            anchor = box[1]
        else:
            a, b = _detail_segment(detail)
            lines.append(Lines(_dashed(a + offset, b + offset, 1.0), color, 4.0, on_top=True))
            anchor = a
        if keep is None or keep(anchor) or "box" in detail:
            labels.append((anchor + offset, f"{detail['name']}: {_detail_text(result)}", color))
    return measured, lines, labels


def _detail_segment(detail: dict) -> tuple[np.ndarray, np.ndarray]:
    """The stretch of a hole's axis or a thickness's ray that the detail is about."""
    point = np.asarray(detail["point"], float)
    direction = np.asarray(detail["direction"], float)
    length = (
        max(d for d, _ in detail["diameters"]) + 3.0
        if detail["kind"] == "hole"
        else detail["mm"] + 3.0
    )
    return point, point + direction * length


def _detail_text(result: dict) -> str:
    if "error" in result:
        return result["error"]
    kind = result["kind"]
    if kind == "material":
        return f"{result['material_fraction']:.0%} material (asks ≥ {result['min_fraction']:.0%})"
    if kind == "void":
        empty = 1 - result["material_fraction"]
        return f"{empty:.0%} empty (asks ≥ {result['min_empty_fraction']:.0%})"
    if kind == "view":
        return "touches the surface" if result["ok"] else "the box does not touch the surface"
    if kind == "thickness":
        return f"{result['measured_mm']:.2f} mm (asks {result['expected_mm']:g})"
    parts = [
        f"Ø{_mm(c['measured_mm'])} at {c['depth_mm']:g} mm (asks {c['expected_mm']:g})"
        for c in result["diameters"]
    ]
    return " · ".join(parts)


def _details_in_view(loaded, offsets, projection, plane) -> list[dict[str, Any]]:
    """For every declared detail: whether it is in the frame and on the kept side of the cut,
    how many pixels it spans, and whether that is a close look (CLOSE_SHARE)."""
    out = []
    width, height = projection.tile
    for part, offset in zip(loaded, offsets, strict=True):
        for detail in (part.get("spec") or {}).get("details") or []:
            if "box" in detail:
                lo, hi = np.asarray(detail["box"], float)
                corners = np.array(
                    [
                        [x, y, z]
                        for x in (lo[0], hi[0])
                        for y in (lo[1], hi[1])
                        for z in (lo[2], hi[2])
                    ]
                )
            else:
                corners = np.array(_detail_segment(detail))
            corners = corners + offset
            px, front = projection.to_pixels(corners)
            center = px.mean(axis=0)
            in_frame = bool(front.all() and 0 <= center[0] < width and 0 <= center[1] < height)
            if plane is not None:
                in_frame &= bool(np.any((corners - plane[0]) @ plane[1] <= 1e-6))
            span = float(np.max(px.max(axis=0) - px.min(axis=0)))
            out.append(
                {
                    "part": part["label"],
                    "sha256": part["sha256"],
                    "name": detail["name"],
                    "kind": detail["kind"],
                    "in_frame": in_frame,
                    "span_px": round(span, 1),
                    "close": bool(in_frame and span >= CLOSE_SHARE * min(width, height)),
                }
            )
    return out


def _support_faces(mesh, drawn, spec, eye) -> tuple[np.ndarray, list[dict]]:
    """Faces of the drawn mesh on each declared support face's extreme plane, and the check."""
    selected = np.zeros(len(drawn.faces), bool)
    results = []
    for face in spec.get("support_faces") or []:
        check = support_face(mesh, face["name"], face["direction"], face["min_area_mm2"])
        axis, sign = DIRECTIONS[face["direction"]]
        extreme = float((sign * mesh.vertices[:, axis]).max())
        corner = sign * drawn.vertices[drawn.faces][:, :, axis]
        on_plane = np.all(corner >= extreme - section.ON_PLANE_MM * 100, axis=1)
        facing = sign * drawn.face_normals[:, axis] > math.cos(math.radians(1.0))
        mask = on_plane & facing
        selected |= mask
        # Weighted by area: small triangles around a hole would pull a plain mean onto it.
        anchor = (
            np.average(drawn.triangles_center[mask], axis=0, weights=drawn.area_faces[mask])
            if mask.any()
            else None
        )
        results.append(
            {**check, "faces_camera": _faces_camera(drawn, mask, eye), "_anchor": anchor}
        )
    if not spec.get("support_faces"):
        results.append({"note": "the part declares no support_faces in cadverify_spec"})
    return selected, results


def _faces_camera(drawn, faces: np.ndarray, eye: np.ndarray) -> bool | None:
    """Whether any of these faces turns towards the camera; None when none is drawn. A zone
    whose faces all turn away (an overhang seen from above) cannot be seen in this view."""
    if not faces.any():
        return None
    return bool((drawn.face_normals[faces] @ eye > 1e-6).any())


def _facing_text(text: str, faces_camera: bool | None) -> str:
    return f"{text} (facing away from the camera)" if faces_camera is False else text


def _overhangs(mesh, drawn, cap, spec) -> tuple[list[dict], np.ndarray]:
    """Overhang zones of the part (as printability_report) and, per drawn face, its zone."""
    overhang, angle, _ = overhang_faces(mesh)
    zones = overhang_zones(mesh, overhang, angle, spec.get("overhangs_allowed") or [])
    face_zone = np.full(len(drawn.faces), -1)
    if not zones:
        return zones, face_zone
    if drawn is mesh:
        for i, zone in enumerate(zones):
            face_zone[zone["_faces"]] = i
        return zones, face_zone
    # A cut splits faces: each overhang face of the drawn mesh takes the zone of the nearest
    # overhang face of the part (zones are connected faces, so neighbors share their zone).
    drawn_overhang, _, _ = overhang_faces(drawn, z_min=float(mesh.bounds[0][2]))
    drawn_overhang &= ~cap
    zone_of = np.full(len(mesh.faces), -1)
    for i, zone in enumerate(zones):
        zone_of[zone["_faces"]] = i
    source = np.flatnonzero(zone_of >= 0)
    tree = cKDTree(mesh.triangles_center[source])
    targets = np.flatnonzero(drawn_overhang)
    if len(targets):
        _, nearest = tree.query(drawn.triangles_center[targets])
        face_zone[targets] = zone_of[source[nearest]]
    return zones, face_zone


def _explode(parts: list[dict], distance: float) -> list[np.ndarray]:
    """Offsets that move each part away from the group's center by `distance` mm. Parts whose
    center is at the group's center (parts exported side by side for printing all sit near the
    origin) are spread along X instead."""
    if distance <= 0 or len(parts) < 2:
        return [np.zeros(3) for _ in parts]
    centers = np.array([p["mesh"].bounds.mean(axis=0) for p in parts])
    middle = centers.mean(axis=0)
    offsets = []
    for i, c in enumerate(centers):
        away = c - middle
        if np.linalg.norm(away) > 1.0:
            offsets.append(away / np.linalg.norm(away) * distance)
        else:
            offsets.append(np.array([(i - (len(parts) - 1) / 2) * distance, 0.0, 0.0]))
    return offsets


def _camera(spec: dict[str, Any], plane) -> tuple[np.ndarray, str]:
    """The camera basis and a text that says where it looks from."""
    if "view" in spec and spec["view"] is not None:
        if spec["view"] not in VIEWS:
            raise ViewError(f"Unknown view {spec['view']!r}; valid: {list(VIEWS)}")
        view = VIEWS[spec["view"]]
        return basis_from(view.eye, view.up), f"{view.label}, {view.from_text}"
    if spec.get("direction") is not None:
        eye = np.asarray(spec["direction"], float)
        if eye.shape != (3,) or np.linalg.norm(eye) < 1e-9:
            raise ViewError("direction is a nonzero vector [x, y, z], from the part to the camera")
        text = "from " + _vec(eye / np.linalg.norm(eye))
    elif spec.get("azimuth") is not None or spec.get("elevation") is not None:
        az_deg, el_deg = float(spec.get("azimuth") or 0), float(spec.get("elevation") or 0)
        az, el = math.radians(az_deg), math.radians(el_deg)
        eye = np.array([math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)])
        text = f"azimuth {az_deg:g}°, elevation {el_deg:g}°"
    elif plane is not None:
        # Looking at the cut face from its side, a little from above and from the right.
        basis = section.frame(plane[1])
        eye = basis[2] + 0.45 * basis[0] + 0.35 * basis[1]
        text = "towards the cut face, " + _vec(eye / np.linalg.norm(eye))
    else:
        view = VIEWS["iso"]
        return basis_from(view.eye, view.up), f"{view.label}, {view.from_text}"
    eye = eye / np.linalg.norm(eye)
    up = (0, 0, 1) if abs(eye[2]) < 0.99 else (0, 1 if eye[2] > 0 else -1, 0)
    return basis_from(eye, up), text


def _focus(zoom: dict[str, Any] | None) -> tuple[np.ndarray, float] | None:
    if not zoom:
        return None
    if zoom.get("box") is not None:
        box = np.asarray(zoom["box"], float)
        if box.shape != (2, 3) or np.any(box[1] < box[0]):
            raise ViewError("zoom.box is [[xmin, ymin, zmin], [xmax, ymax, zmax]]")
        return box.mean(axis=0), float(np.linalg.norm(box[1] - box[0]))
    center = np.asarray(zoom.get("center"), float)
    size = zoom.get("size_mm")
    if center.shape != (3,) or not isinstance(size, int | float) or size <= 0:
        raise ViewError("zoom is {center: [x, y, z], size_mm: s > 0} or {box: [[...], [...]]}")
    return center, float(size)


def _in_pixels(projection, labels) -> list[tuple[tuple[float, float], str, tuple]]:
    """Labels on 3D points as labels on the tile's pixels; those behind the camera drop."""
    if not labels:
        return []
    px, front = projection.to_pixels(np.array([p for p, _, _ in labels], float))
    return [
        ((float(x), float(y)), text, color)
        for (_, text, color), (x, y), ok in zip(labels, px, front, strict=True)
        if ok
    ]


def _labels(image: Image.Image, labels, text_px: int = 17, dot: bool = True) -> None:
    """Each label in a white box next to its point (in pixels), with a line back to the point
    when the box had to go elsewhere (_place_labels)."""
    d = ImageDraw.Draw(image)
    for (x, y), text, color, box, origin in _place_labels(labels, image.size, text_px):
        rgb = tuple(int(c * 255) for c in color)
        near = (min(max(x, box[0]), box[2]), min(max(y, box[1]), box[3]))
        if math.dist((x, y), near) > 10:
            d.line([(x, y), near], fill=rgb, width=1)
        d.rectangle(box, fill="white", outline=rgb)
        d.text(origin, text, fill=rgb, font=font(text_px))
        if dot:
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=rgb)


def _place_labels(labels, size: tuple[int, int], text_px: int = 17) -> list[tuple]:
    """Where each label's box goes: right of its point, or left of it when it would leave the
    tile; up or down when it would cover a box already placed; always inside the tile. Labels
    whose point is out of the tile are left out. Returns (point, text, color, box, origin)."""
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    placed: list[tuple] = []
    for (x, y), text, color in labels:
        if not (0 <= x < size[0] and 0 <= y < size[1]):
            continue
        left, top, right, bottom = d.textbbox((0, 0), text, font=font(text_px))
        w, h = right - left + 6, bottom - top + 4  # the box: the text and its padding
        bx = x + 8 + left - 3 if x + 8 + left - 3 + w <= size[0] - 1 else x - 8 - w
        bx = min(max(bx, 1), size[0] - 1 - w)
        base = min(max(y - 8 + top - 2, 1), size[1] - 1 - h)
        for dy in (0, 26, -26, 52, -52, 78, -78):
            by = min(max(base + dy, 1), size[1] - 1 - h)
            box = (bx, by, bx + w, by + h)
            if not any(_overlap(box, other[3]) for other in placed):
                break
        placed.append(((x, y), text, color, box, (bx + 3 - left, by + 2 - top)))
    return placed


def _overlap(a, b) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _annotate_view(tile: Image.Image, projection, camera_text: str, focus) -> None:
    d = ImageDraw.Draw(tile)
    w, h = tile.size
    d.rectangle([0, 0, w - 1, h - 1], outline="#9aa0a6")
    kind = "PERSPECTIVE" if projection.perspective else "ORTHOGRAPHIC"
    camera_x = 24 + d.textlength(kind, font=font(22))
    zoom = None if focus is None else f"zoom: center {_vec(focus[0], 1)}, {focus[1]:g} mm"
    # The camera text, the scale bar and the axes sit on white even where the part fills the
    # tile, as in a zoom.
    right = camera_x + d.textlength(camera_text, font=font(15))
    if zoom:
        right = max(right, 14 + d.textlength(zoom, font=font(15)))
    d.rectangle([2, 2, right + 10, 64 if zoom else 42], fill="white")
    d.text((14, 12), kind, fill="black", font=font(22))
    d.text((camera_x, 17), camera_text, fill="#555555", font=font(15))
    if zoom:
        d.text((14, 40), zoom, fill="#555555", font=font(15))
    d.rectangle([w - 300, h - 70, w - 2, h - 2], fill="white")
    d.rectangle([2, h - 80, 90, h - 2], fill="white")
    if projection.px_per_mm:
        scale_bar(d, w, h, projection.px_per_mm)
        d.text(
            (w - 18, h - 52),
            "scale on the view plane",
            fill="#666666",
            font=font(13),
            anchor="rs",
        )
    else:
        d.text(
            (w - 18, h - 16), "no scale: perspective", fill="#666666", font=font(14), anchor="rs"
        )
    axes(d, projection.basis, (44, h - 40))


def _profile_panel(profiles: list[tuple[str, section.Profile]], plane) -> Image.Image:
    """The 2D profile of the cut in the plane's (u, v) mm, with a grid and its numbers."""
    w, h = PROFILE_TILE
    panel = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(panel)
    d.rectangle([0, 0, w - 1, h - 1], outline="#9aa0a6")
    first = profiles[0][1]
    d.text((14, 12), "CUT PROFILE", fill="black", font=font(22))
    plane_text = f"plane through {_vec(plane[0], 2)}, normal {_vec(plane[1], 3)}"
    d.text((14, 40), plane_text, fill="#555555", font=font(14))
    polygons = [p for _, prof in profiles for p in prof.polygons]
    left, top, right, bottom = 80, 80, 30, 150
    if not polygons:
        message = "the plane does not cut the part"
        d.text((w / 2, h / 2), message, fill="#aa0000", font=font(20), anchor="mm")
        return panel
    union = shapely.MultiPolygon(polygons)
    (u0, v0, u1, v1) = union.bounds
    span = max(u1 - u0, v1 - v0, 1e-6)
    pad = 0.06 * span
    u0, v0, u1, v1 = u0 - pad, v0 - pad, u1 + pad, v1 + pad
    room = (w - left - right, h - top - bottom)
    scale = min(room[0] / (u1 - u0), room[1] / (v1 - v0))
    cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
    ox, oy = left + room[0] / 2, top + room[1] / 2

    def px(u, v):
        return (ox + (u - cu) * scale, oy - (v - cv) * scale)

    # Grid every nice step. When u or v runs along a world axis the ticks are that axis's
    # coordinate (X, Y or Z in mm, as in the rest of the tools); otherwise they are mm from
    # the plane's point.
    step = nice_length(max((u1 - u0), (v1 - v0)) / 6)
    axis_text = []
    for along, (lo, hi), name in ((0, (u0, u1), "u"), (1, (v0, v1), "v")):
        world, base, sign = _world_axis(first.basis[along], first.origin)
        if world is None:
            ticks = np.arange(math.ceil(lo / step) * step, hi + 1e-9, step)
            pairs = [(t, t) for t in ticks]
            axis_text.append(f"{name}: mm from the plane's point, {_vec(first.basis[along], 3)}")
        else:
            wlo, whi = sorted((base + sign * lo, base + sign * hi))
            ticks = np.arange(math.ceil(wlo / step) * step, whi + 1e-9, step)
            pairs = [((t - base) * sign, t) for t in ticks]
            direction = ("grows to the right", "grows upward")[along]
            if sign < 0:
                direction = ("grows to the left", "grows downward")[along]
            axis_text.append(
                f"{'horizontal' if along == 0 else 'vertical'}: {world} (mm), {direction}"
            )
        for coord, value in pairs:
            label = f"{value + 0.0:g}"
            if along == 0:
                x, _ = px(coord, cv)
                d.line([(x, top), (x, h - bottom)], fill="#e3e6ea", width=1)
                d.text((x, h - bottom + 6), label, fill="#555555", font=font(13), anchor="ma")
            else:
                _, y = px(cu, coord)
                d.line([(left, y), (w - right, y)], fill="#e3e6ea", width=1)
                d.text((left - 6, y), label, fill="#555555", font=font(13), anchor="rm")
    d.rectangle([left, top, w - right, h - bottom], outline="#b0b4b8")
    outside = []  # the diameters of holes too small to hold them, written next to them
    for _, prof in profiles:
        for polygon in prof.polygons:
            outer = [px(u, v) for u, v in polygon.exterior.coords]
            d.polygon(outer, fill=tuple(int(c * 255) for c in CAP), outline=(40, 40, 40), width=2)
            for ring in polygon.interiors:
                d.polygon(
                    [px(u, v) for u, v in ring.coords], fill="white", outline=(40, 40, 40), width=2
                )
                hole = shapely.Polygon(ring)
                text = f"Ø{2 * math.sqrt(hole.area / math.pi):.1f}"
                cx, cy = px(*hole.centroid.coords[0])
                ring_px = np.array([px(u, v) for u, v in ring.coords])
                (x0, y0), (x1, y1) = ring_px.min(axis=0), ring_px.max(axis=0)
                tl, tt, tr, tb = d.textbbox((0, 0), text, font=font(13))
                if tr - tl + 6 <= x1 - x0 and tb - tt + 4 <= y1 - y0:
                    d.text((cx, cy), text, fill=HOLE_TEXT, font=font(13), anchor="mm")
                else:
                    color = tuple(c / 255 for c in HOLE_TEXT)
                    outside.append(((float(x1), float(cy)), text, color))
    _labels(panel, outside, text_px=13, dot=False)
    # The plane's own point, where u = v = 0.
    x0, y0 = px(0.0, 0.0)
    if left <= x0 <= w - right and top <= y0 <= h - bottom:
        d.line([(x0 - 7, y0), (x0 + 7, y0)], fill="#1f5fd6", width=2)
        d.line([(x0, y0 - 7), (x0, y0 + 7)], fill="#1f5fd6", width=2)
    numbers = [prof.numbers() for _, prof in profiles]
    area = sum(n["area_mm2"] for n in numbers)
    regions = sum(n["regions"] for n in numbers)
    holes = sum(n["holes"] for n in numbers)
    width_u, height_v = union.bounds[2] - union.bounds[0], union.bounds[3] - union.bounds[1]
    y = h - bottom + 30
    d.text((left, y), "   ·   ".join(axis_text), fill="#333333", font=font(15))
    summary = (
        f"area {area:.1f} mm²  ·  {regions} region(s)  ·  {holes} hole(s)  ·  "
        f"box {width_u:.1f} × {height_v:.1f} mm"
    )
    d.text((left, y + 24), summary, fill="black", font=font(16))
    open_chains = sum(n["open_chains"] for n in numbers)
    if open_chains:
        d.text(
            (left, y + 50),
            f"{open_chains} open outlines: the mesh is open at the cut",
            fill="#aa0000",
            font=font(15),
        )
    d.text((left, y + 76), f"grid every {step:g} mm", fill="#666666", font=font(13))
    return panel


def _world_axis(direction: np.ndarray, origin: np.ndarray) -> tuple[str | None, float, float]:
    """("X" | "Y" | "Z", the origin's coordinate on it, +1 or -1) when `direction` is a world
    axis, else (None, 0, 0)."""
    i = int(np.argmax(np.abs(direction)))
    if not np.isclose(abs(direction[i]), 1.0, atol=1e-6):
        return None, 0.0, 0.0
    return "XYZ"[i], float(origin[i]), float(np.sign(direction[i]))


def _used_colors(layers, lines, n_parts) -> list[tuple[str, tuple, str]]:
    items = []
    colors = (
        np.vstack([np.asarray(layer.colors) for layer in layers]) if layers else np.zeros((0, 3))
    )

    def has(rgb):
        return bool(len(colors)) and bool(np.any(np.all(np.isclose(colors, rgb), axis=1)))

    items.append(("box", BODY, "part" if n_parts == 1 else "parts"))
    for rgb, text in (
        (CAP, "cut face"),
        (OVERHANG, "undeclared overhang > 45°"),
        (OVERHANG_OK, "declared overhang"),
        (SUPPORT, "support face (spec)"),
        (HOLE, "through hole"),
    ):
        if has(rgb):
            items.append(("box", rgb, text))
    if any(g.rgb == SPEC_BOX for g in lines):
        items.append(("line", SPEC_BOX, "spec bounds box"))
    if any(g.rgb == DETAIL_OK for g in lines):
        items.append(("line", DETAIL_OK, "detail that measures what it says"))
    if any(g.rgb == DETAIL_BAD for g in lines):
        items.append(("line", DETAIL_BAD, "detail that does not measure what it says"))
    items.append(("box", BACK, "face seen from behind"))
    items.append(("line", DEFECT, "open / non-manifold edge"))
    return items


def _header_lines(title: str, parts: list[dict], width: float) -> list[str]:
    """The title, the triangle count and every part's size, wrapped to `width` px: the title
    between words, the rest between items."""
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    triangles = sum(len(p["mesh"].faces) for p in parts)
    sizes = [
        f"{p['label']} " + " × ".join(f"{e:.1f}" for e in p["mesh"].extents) + " mm" for p in parts
    ]
    items = [(word, " ") for word in title.split()]
    items += [(text, "  ·  ") for text in [f"{triangles} triangles", *sizes]]
    lines = [""]
    for text, separator in items:
        joined = lines[-1] + separator + text if lines[-1] else text
        if lines[-1] and d.textlength(joined, font=font(18)) > width:
            lines.append(text)
        else:
            lines[-1] = joined
    return lines


def _header(sheet: Image.Image, title: list[str], used) -> None:
    d = ImageDraw.Draw(sheet)
    for i, line in enumerate(title):
        d.text((12, 8 + 24 * i), line, fill="black", font=font(18))
    legend(d, used, (12, 38 + 24 * (len(title) - 1)), sheet.size[0] - 24)


def _part_labels(loaded: list[dict], layers: list[Layer], projection, shown) -> tuple[list, list]:
    """Each part's label on a pixel the camera sees of it (the cap of a cut too), as near its
    top as there is one; a part it does not see (hidden inside or behind another, or out of the
    zoom) says so, next to where it is. `shown` is layer_map(): the part on each pixel.
    Returns the labels, in pixels, and per part whether it is seen."""
    labels, seen = [], []
    inset = np.ones((2 * LABEL_INSET + 1,) * 2, dtype=bool)
    for i, (part, layer) in enumerate(zip(loaded, layers, strict=True)):
        mesh = layer.mesh
        mask = shown == i
        seen.append(bool(mask.any()))
        if not len(mesh.faces):  # all of it on the side the cut removes
            continue
        top = mesh.bounds.mean(axis=0)
        top[2] = mesh.bounds[1][2]
        tx, ty = projection.to_pixels(top)[0][0]
        if mask.any():
            # Away from the part's outline and from the tile's border, when there is room.
            solid = binary_erosion(mask, structure=inset, border_value=0)
            inner = np.zeros_like(solid)
            inner[LABEL_MARGIN:-LABEL_MARGIN, LABEL_MARGIN:-LABEL_MARGIN] = True
            rows, cols = np.nonzero(next(m for m in (solid & inner, solid, mask) if m.any()))
            k = int(np.argmin((cols + 0.5 - tx) ** 2 + (rows + 0.5 - ty) ** 2))
            labels.append(((cols[k] + 0.5, rows[k] + 0.5), part["label"], (0.1, 0.1, 0.1)))
            continue
        px, front = projection.to_pixels(mesh.vertices)
        width, height = projection.tile
        in_tile = front & (px[:, 0] >= 0) & (px[:, 0] < width) & (px[:, 1] >= 0)
        in_tile &= px[:, 1] < height
        if in_tile.any():
            near = px[in_tile][np.argmin(np.linalg.norm(px[in_tile] - (tx, ty), axis=1))]
            text = f"{part['label']} (not visible)"
            labels.append(((float(near[0]), float(near[1])), text, (0.45, 0.45, 0.45)))
    return labels, seen


def _box_edges(box: np.ndarray) -> np.ndarray:
    lo, hi = box
    corners = np.array(
        [[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
    )
    pairs = [
        (0, 1),
        (2, 3),
        (4, 5),
        (6, 7),
        (0, 2),
        (1, 3),
        (4, 6),
        (5, 7),
        (0, 4),
        (1, 5),
        (2, 6),
        (3, 7),
    ]
    return np.concatenate(
        [
            _dashed(corners[a], corners[b], max(np.ptp(box, axis=0).max() / 40, 0.5))
            for a, b in pairs
        ]
    )


def _dashed(a: np.ndarray, b: np.ndarray, dash: float) -> np.ndarray:
    """Segments of a dashed line from a to b, dashes and gaps of `dash` mm."""
    length = float(np.linalg.norm(b - a))
    n = max(int(length / dash), 1)
    t = np.linspace(0, 1, n + 1)
    starts, ends = t[:-1][::2], t[1:][::2]
    return np.stack([a + np.outer(starts, b - a), a + np.outer(ends, b - a)], axis=1)


def _genus(mesh: trimesh.Trimesh) -> int | None:
    from cadverify.cadcheck.mesh import report_from_mesh

    return report_from_mesh(mesh)["through_holes"]


def _mm(value) -> str:
    return "?" if value is None else f"{value:.1f}"


def _vec(v, digits: int = 2) -> str:
    return "(" + ", ".join(f"{c:.{digits}f}" for c in np.asarray(v, float)) + ")"


def _r(array) -> list:
    return np.round(np.asarray(array, float), 3).tolist()
