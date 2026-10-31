"""render_sheet: a multi-view sheet of an exported mesh, drawn by our own OpenGL renderer.

OpenSCAD draws either silhouettes or the whole triangulation.
This sheet has flat shading in one color with the light at the camera, darker with depth; the
sharp edges (dihedral angle above 30°) and the outline of curved surfaces as lines with hidden
lines removed; and open or non-manifold edges in red, drawn through the part so they are never
hidden. Faces seen from behind (an inside-out shell, or the inside of the part through a hole in
the mesh) are magenta.

Every view of the sheet is orthographic. The drawing core (`Layer`, `Lines`, `Projection` and
`draw`) is shared with render_view (cadcheck.view), which adds free cameras, perspective, cuts
and highlights. The context is headless OpenGL through EGL on Mesa's llvmpipe, the same stack
OpenSCAD uses in the sandbox image.
"""

from __future__ import annotations

import hashlib
import math
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFont

from cadverify.cadcheck.mesh import load_exact

SHARP_EDGE_DEG = 30.0
TILE = (600, 450)
HEADER = 64
SUPERSAMPLE = 2
MARGIN = (24, 46, 24, 66)  # left, top, right, bottom: the bottom band holds axes and scale

BODY = (0.62, 0.72, 0.82)
BACK = (0.85, 0.25, 0.75)
LINE = (0.10, 0.12, 0.16)
DEFECT = (0.90, 0.05, 0.05)


@dataclass(frozen=True)
class View:
    label: str
    eye: tuple[float, float, float]  # direction from the part towards the camera
    up: tuple[float, float, float]
    from_text: str


VIEWS = {
    "iso": View("ISO", (1, -1, 1), (0, 0, 1), "from +X -Y +Z"),
    "iso_back": View("ISO BACK", (-1, 1, 1), (0, 0, 1), "from -X +Y +Z"),
    "front": View("FRONT", (0, -1, 0), (0, 0, 1), "from -Y"),
    "side": View("SIDE", (1, 0, 0), (0, 0, 1), "from +X"),
    "top": View("TOP", (0, 0, 1), (0, 1, 0), "from +Z"),
    "bottom": View("BOTTOM", (0, 0, -1), (0, -1, 0), "from -Z"),
}

_FACE_VS = """
#version 330
uniform mat4 mvp;
in vec3 in_pos;
in vec3 in_normal;
in vec3 in_color;
flat out vec3 v_normal;
flat out vec3 v_color;
void main() {
    gl_Position = mvp * vec4(in_pos, 1.0);
    v_normal = in_normal;
    v_color = in_color;
}
"""
_FACE_FS = """
#version 330
uniform vec3 light;
uniform vec3 back;
uniform vec2 depth_range;
flat in vec3 v_normal;
flat in vec3 v_color;
out vec4 color;
void main() {
    if (!gl_FrontFacing) { color = vec4(back, 1.0); return; }
    float d = max(dot(v_normal, light), 0.0);
    // Depth cue: the farther a face, the darker, so parallel faces at different depths differ.
    float far = smoothstep(depth_range.x, depth_range.y, gl_FragCoord.z);
    color = vec4(v_color * (0.30 + 0.70 * d) * (1.0 - 0.45 * far), 1.0);
}
"""
_LINE_VS = """
#version 330
uniform mat4 mvp;
in vec3 in_pos;
void main() { gl_Position = mvp * vec4(in_pos, 1.0); }
"""
_LINE_FS = """
#version 330
uniform vec3 rgb;
out vec4 color;
void main() { color = vec4(rgb, 1.0); }
"""
_LAYER_FS = """
#version 330
uniform int layer;
out vec4 color;
void main() {
    int n = layer + 1;
    color = vec4(float(n & 255) / 255.0, float((n >> 8) & 255) / 255.0, 0.0, 1.0);
}
"""


@dataclass
class Edges:
    """Undirected edges of a mesh, classified once for every view."""

    sharp: np.ndarray  # (k, 2) vertex indices
    smooth: np.ndarray  # (m, 2) vertex indices of manifold edges that are not sharp
    smooth_faces: np.ndarray  # (m, 2) the two faces of each smooth edge
    open: np.ndarray  # used by one face
    nonmanifold: np.ndarray  # used by three or more faces

    def silhouette(self, normals: np.ndarray, eye: np.ndarray) -> np.ndarray:
        """Smooth edges between a face turned towards the camera and one turned away."""
        facing = normals @ eye
        return self.smooth[facing[self.smooth_faces[:, 0]] * facing[self.smooth_faces[:, 1]] < 0]


def classify_edges(mesh: trimesh.Trimesh, sharp_deg: float = SHARP_EDGE_DEG) -> Edges:
    edges = np.sort(mesh.faces[:, [0, 1, 1, 2, 2, 0]].reshape(-1, 2), axis=1)
    face_of = np.repeat(np.arange(len(mesh.faces)), 3)
    unique, inverse, counts = np.unique(edges, axis=0, return_inverse=True, return_counts=True)
    order = np.argsort(inverse, kind="stable")
    first = np.searchsorted(inverse[order], np.arange(len(unique)))
    manifold = np.flatnonzero(counts == 2)
    pair = np.stack([face_of[order[first[manifold]]], face_of[order[first[manifold] + 1]]], 1)
    normals = mesh.face_normals
    cos = np.einsum("ij,ij->i", normals[pair[:, 0]], normals[pair[:, 1]])
    # A degenerate triangle has a zero normal: it neither makes nor hides a sharp edge.
    degenerate = ~np.any(normals[pair[:, 0]], axis=1) | ~np.any(normals[pair[:, 1]], axis=1)
    sharp = (cos < math.cos(math.radians(sharp_deg))) & ~degenerate
    return Edges(
        sharp=unique[manifold[sharp]],
        smooth=unique[manifold[~sharp]],
        smooth_faces=pair[~sharp],
        open=unique[counts == 1],
        nonmanifold=unique[counts > 2],
    )


def camera(view: View) -> np.ndarray:
    """Rows: screen right, screen up and towards the camera, a right-handed basis."""
    return basis_from(view.eye, view.up)


def basis_from(eye, up) -> np.ndarray:
    eye = np.array(eye, float) / np.linalg.norm(eye)
    right = np.cross(up, eye)
    right /= np.linalg.norm(right)
    return np.stack([right, np.cross(eye, right), eye])


def nice_length(max_mm: float) -> float:
    """The largest 1, 2 or 5 × 10^k not above max_mm."""
    exponent = math.floor(math.log10(max_mm))
    return max(m * 10.0**exponent for m in (1, 2, 5) if m * 10.0**exponent <= max_mm)


# ---- drawing core ---------------------------------------------------------------------------


@dataclass
class Layer:
    """A mesh drawn with one color per face (RGB in 0..1)."""

    mesh: trimesh.Trimesh
    colors: np.ndarray  # (F, 3)


@dataclass
class Lines:
    segments: np.ndarray  # (k, 2, 3)
    rgb: tuple[float, float, float]
    width: float  # in supersampled pixels
    on_top: bool = False  # drawn without the depth test, so nothing hides them


@dataclass
class Projection:
    """Where the camera looks and how: mvp maps world mm to clip space for one tile."""

    basis: np.ndarray  # rows: screen right, screen up, towards the camera
    mvp: np.ndarray  # (4, 4)
    tile: tuple[int, int]
    px_per_mm: float | None  # None in perspective
    perspective: bool = False

    def to_pixels(self, points: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Tile pixel coordinates of 3D points (y down) and whether each is in front."""
        h = np.hstack([np.atleast_2d(points), np.ones((len(np.atleast_2d(points)), 1))])
        clip = h @ self.mvp.T
        w = clip[:, 3]
        front = w > 1e-9
        ndc = clip[:, :2] / np.where(front, w, 1.0)[:, None]
        px = np.stack(
            [(ndc[:, 0] + 1) / 2 * self.tile[0], (1 - ndc[:, 1]) / 2 * self.tile[1]], axis=1
        )
        return px, front


def orthographic(
    basis: np.ndarray,
    points: np.ndarray,
    tile: tuple[int, int],
    margin: tuple[int, int, int, int],
    focus: tuple[np.ndarray, float] | None = None,
) -> Projection:
    """Orthographic camera that fits `points` in the tile, or the cube of `focus` (center,
    size in mm) when given. The depth range always covers every point."""
    left, top, right, bottom = margin
    room = np.array([tile[0] - left - right, tile[1] - top - bottom], float)
    if focus is None:
        center = (points.min(axis=0) + points.max(axis=0)) / 2
        local = (points - center) @ basis.T
        lo, hi = local.min(axis=0), local.max(axis=0)
        scale = float(np.min(room / np.maximum(hi[:2] - lo[:2], 1e-9)))  # tile px per mm
        mid = (lo[:2] + hi[:2]) / 2
    else:
        center, size = np.asarray(focus[0], float), float(focus[1])
        scale = float(np.min(room / max(size, 1e-6)))
        mid = np.zeros(2)
    local_z = (points - center) @ basis[2]
    depth = max(float(np.abs(local_z).max()), 1e-6) * 1.05
    # Where the drawing area's center sits in normalized device coordinates.
    offset = np.array([(left - right) / tile[0], (bottom - top) / tile[1]])
    mvp = np.zeros((4, 4))
    mvp[0, :3] = basis[0] * 2 * scale / tile[0]
    mvp[1, :3] = basis[1] * 2 * scale / tile[1]
    mvp[2, :3] = -basis[2] / depth
    mvp[:2, 3] = -mid * 2 * scale / np.array(tile) + offset
    mvp[:3, 3] -= mvp[:3, :3] @ center
    mvp[3, 3] = 1.0
    return Projection(basis, mvp, tile, scale)


def perspective(
    basis: np.ndarray,
    points: np.ndarray,
    tile: tuple[int, int],
    margin: tuple[int, int, int, int],
    focus: tuple[np.ndarray, float] | None = None,
    fov_deg: float = 35.0,
) -> Projection:
    """Perspective camera looking along -basis[2] at the center of `points` (or of `focus`).

    Without a focus the camera backs off just enough for every point to fall inside the
    drawing area; with one, the focus size fills the drawing area at the focus point.
    """
    left, top, right, bottom = margin
    room = np.array([tile[0] - left - right, tile[1] - top - bottom], float)
    f = 1.0 / math.tan(math.radians(fov_deg) / 2)
    k = min(room) / np.array(tile, float)  # square pixels: the smaller side of the area sets f
    if focus is None:
        center = (points.min(axis=0) + points.max(axis=0)) / 2
        local = (points - center) @ basis.T
        # A point at (x, y, z) in camera axes projects to f·k·x / (d - z) in NDC, which must
        # stay within room / tile: d >= z + f·k·|x|·tile / room, for x and for y.
        reach = np.abs(local[:, :2]) * f * k * np.array(tile) / room
        distance = float((local[:, 2] + reach.max(axis=1)).max()) * 1.02
        distance = max(distance, float(local[:, 2].max()) + 1e-3)
    else:
        center = np.asarray(focus[0], float)
        distance = max(float(focus[1]) / 2, 1e-3) * f * 1.05
    eye_pos = center + basis[2] * distance
    along = (points - eye_pos) @ -basis[2]
    near = max(float(along.min()) * 0.9, distance * 0.02)
    far = max(float(along.max()) * 1.1, near * 2)
    view = np.eye(4)
    view[:3, :3] = basis
    view[:3, 3] = -basis @ eye_pos
    proj = np.zeros((4, 4))
    proj[0, 0] = f * k[0]
    proj[1, 1] = f * k[1]
    proj[2, 2] = -(far + near) / (far - near)
    proj[2, 3] = -2 * far * near / (far - near)
    proj[3, 2] = -1.0
    offset = np.array([(left - right) / tile[0], (bottom - top) / tile[1]])
    proj[0] += offset[0] * proj[3]
    proj[1] += offset[1] * proj[3]
    return Projection(basis, proj @ view, tile, None, perspective=True)


def draw(
    ctx, layers: list[Layer], lines: list[Lines], projection: Projection, back=BACK
) -> Image.Image:
    """Render the layers and lines into one tile (supersampled, then reduced)."""
    import moderngl

    tile = projection.tile
    size = (tile[0] * SUPERSAMPLE, tile[1] * SUPERSAMPLE)
    mvp_bytes = projection.mvp.T.astype("f4").tobytes()  # column-major for GLSL
    fbo = ctx.framebuffer(
        color_attachments=[ctx.renderbuffer(size, components=4)],
        depth_attachment=ctx.depth_renderbuffer(size),
    )
    fbo.use()
    ctx.viewport = (0, 0, *size)
    ctx.clear(1.0, 1.0, 1.0, 1.0, depth=1.0)
    ctx.enable(moderngl.DEPTH_TEST)
    ctx.depth_func = "<="

    faces = ctx.program(vertex_shader=_FACE_VS, fragment_shader=_FACE_FS)
    faces["mvp"].write(mvp_bytes)
    basis = projection.basis
    light = basis[2] + 0.35 * basis[1] - 0.25 * basis[0]
    faces["light"].value = tuple(light / np.linalg.norm(light))
    faces["back"].value = back
    faces["depth_range"].value = _depth_range(projection, layers)
    released = [faces, fbo]
    ctx.polygon_offset = (1.0, 1.0)  # pushes faces back so the edges on them pass the test
    for layer in layers:
        mesh = layer.mesh
        if len(mesh.faces) == 0:
            continue
        positions = mesh.vertices[mesh.faces].reshape(-1, 3)
        normals = np.repeat(mesh.face_normals, 3, axis=0)
        colors = np.repeat(np.asarray(layer.colors, float), 3, axis=0)
        data = np.hstack([positions, normals, colors]).astype("f4")
        vbo = ctx.buffer(data.tobytes())
        vao = ctx.vertex_array(faces, [(vbo, "3f 3f 3f", "in_pos", "in_normal", "in_color")])
        vao.render(moderngl.TRIANGLES)
        released += [vao, vbo]
    ctx.polygon_offset = (0.0, 0.0)

    program = ctx.program(vertex_shader=_LINE_VS, fragment_shader=_LINE_FS)
    program["mvp"].write(mvp_bytes)
    released.append(program)
    for group in sorted(lines, key=lambda g: g.on_top):
        if group.on_top:
            ctx.disable(moderngl.DEPTH_TEST)
        _draw_lines(ctx, program, group.segments, group.rgb, group.width)

    raw = fbo.read(components=3)
    image = Image.frombytes("RGB", size, raw).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    for obj in released:
        obj.release()
    return image.reduce(SUPERSAMPLE)


def layer_map(ctx, layers: list[Layer], projection: Projection) -> np.ndarray:
    """Which layer each pixel of the tile shows (-1: none), with draw()'s depth test: what the
    camera sees of each part, the caps of a cut included. (rows, columns), row 0 at the top."""
    import moderngl

    width, height = projection.tile
    fbo = ctx.framebuffer(
        color_attachments=[ctx.renderbuffer((width, height), components=4)],
        depth_attachment=ctx.depth_renderbuffer((width, height)),
    )
    fbo.use()
    ctx.viewport = (0, 0, width, height)
    ctx.clear(0.0, 0.0, 0.0, 1.0, depth=1.0)
    ctx.enable(moderngl.DEPTH_TEST)
    ctx.depth_func = "<="
    program = ctx.program(vertex_shader=_LINE_VS, fragment_shader=_LAYER_FS)
    program["mvp"].write(projection.mvp.T.astype("f4").tobytes())
    released = [program, fbo]
    for i, layer in enumerate(layers):
        mesh = layer.mesh
        if len(mesh.faces) == 0:
            continue
        program["layer"].value = i
        vbo = ctx.buffer(mesh.vertices[mesh.faces].reshape(-1, 3).astype("f4").tobytes())
        vao = ctx.vertex_array(program, [(vbo, "3f", "in_pos")])
        vao.render(moderngl.TRIANGLES)
        released += [vao, vbo]
    raw = np.frombuffer(fbo.read(components=3), dtype=np.uint8).reshape(height, width, 3)[::-1]
    for obj in released:
        obj.release()
    return raw[:, :, 0].astype(int) + 256 * raw[:, :, 1].astype(int) - 1


def _depth_range(projection: Projection, layers: list[Layer]) -> tuple[float, float]:
    """Window depth (gl_FragCoord.z) of the nearest and farthest drawn vertex in the tile (of
    every vertex when none is: a zoom into one large face)."""
    points = [layer.mesh.vertices for layer in layers if len(layer.mesh.faces)]
    if not points:
        return (0.0, 1.0)
    h = np.hstack([np.vstack(points), np.ones((sum(len(p) for p in points), 1))])
    clip = h @ projection.mvp.T
    ndc = clip[:, :3] / np.maximum(clip[:, 3:4], 1e-9)
    inside = np.all(np.abs(ndc[:, :2]) <= 1.0, axis=1)
    z = (np.clip(ndc[inside if inside.any() else slice(None), 2], -1, 1) + 1) / 2
    return (float(z.min()), float(z.max()))


def _draw_lines(ctx, program, segments: np.ndarray, rgb, width: float) -> None:
    import moderngl

    if len(segments) == 0:
        return
    program["rgb"].value = rgb
    vbo = ctx.buffer(np.asarray(segments).reshape(-1, 3).astype("f4").tobytes())
    vao = ctx.vertex_array(program, [(vbo, "3f", "in_pos")])
    ctx.line_width = width
    vao.render(moderngl.LINES)
    vao.release()
    vbo.release()


def edge_lines(mesh: trimesh.Trimesh, edges: Edges, eye: np.ndarray) -> list[Lines]:
    """Sharp edges and outline (hidden ones removed), and open or non-manifold edges on top."""
    outline = np.vstack([edges.sharp, edges.silhouette(mesh.face_normals, eye)])
    defects = np.vstack([edges.open, edges.nonmanifold])
    return [
        Lines(mesh.vertices[outline], LINE, 3.0),
        Lines(mesh.vertices[defects], DEFECT, 6.0, on_top=True),
    ]


# ---- the sheet ------------------------------------------------------------------------------


def render_sheet(
    path: str | Path,
    out: str | Path,
    views: list[str] | None = None,
    title: str | None = None,
) -> dict[str, Any]:
    """Render the views of the mesh at `path` into one PNG at `out`."""
    t0 = time.perf_counter()
    views = views or list(VIEWS)
    if unknown := [v for v in views if v not in VIEWS]:
        return {"ok": False, "error": f"Unknown views: {unknown}; valid: {list(VIEWS)}"}
    # The SHA-256 of the file drawn: gate G7 asks for the sheet of the verified export.
    stl_sha256 = hashlib.sha256(Path(path).read_bytes()).hexdigest()
    mesh = load_exact(path)
    if len(mesh.faces) == 0:
        return {"ok": False, "error": "empty mesh"}
    edges = classify_edges(mesh)

    import moderngl  # imported here so the geometry above stays usable without OpenGL

    ctx = moderngl.create_context(standalone=True, backend="egl")
    try:
        tiles = [_render_view(ctx, mesh, edges, VIEWS[name]) for name in views]
        renderer = ctx.info["GL_RENDERER"]
    finally:
        ctx.release()

    cols = min(3, len(tiles))
    rows = math.ceil(len(tiles) / cols)
    sheet = Image.new("RGB", (cols * TILE[0], HEADER + rows * TILE[1]), "white")
    for i, tile in enumerate(tiles):
        sheet.paste(tile, ((i % cols) * TILE[0], HEADER + (i // cols) * TILE[1]))
    _header(sheet, title or Path(path).name, mesh, edges)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return {
        "ok": True,
        "path": str(out),
        "views": views,
        "size": list(sheet.size),
        "stl_sha256": stl_sha256,
        "triangles": len(mesh.faces),
        "edges": {
            "sharp": len(edges.sharp),
            "open": len(edges.open),
            "nonmanifold": len(edges.nonmanifold),
        },
        "renderer": renderer,
        "seconds": round(time.perf_counter() - t0, 3),
    }


def _render_view(ctx, mesh: trimesh.Trimesh, edges: Edges, view: View) -> Image.Image:
    basis = camera(view)
    projection = orthographic(basis, mesh.vertices, TILE, MARGIN)
    colors = np.tile(BODY, (len(mesh.faces), 1))
    tile = draw(ctx, [Layer(mesh, colors)], edge_lines(mesh, edges, basis[2]), projection)
    local = mesh.vertices @ basis.T
    extent = local.max(axis=0)[:2] - local.min(axis=0)[:2]
    _annotate(tile, view.label, view.from_text, basis, projection.px_per_mm, extent)
    return tile


# In the sandbox image (fonts-dejavu-core from the pinned base). Pillow's bundled default font
# has no glyphs for × or °.
FONT = Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")


def font(size: int) -> ImageFont.ImageFont:
    if FONT.exists():
        return ImageFont.truetype(str(FONT), size)
    return ImageFont.load_default(size=size)


def _annotate(
    tile: Image.Image, label: str, from_text: str, basis: np.ndarray, scale, extent
) -> None:
    draw_ = ImageDraw.Draw(tile)
    w, h = tile.size
    draw_.rectangle([0, 0, w - 1, h - 1], outline="#9aa0a6")
    draw_.text((12, 10), label, fill="black", font=font(22))
    label_end = draw_.textlength(label, font=font(22))
    draw_.text((20 + label_end, 15), from_text, fill="#555555", font=font(15))

    axis_names = ["X", "Y", "Z"]
    screen = [axis_names[int(np.argmax(np.abs(basis[i])))] for i in range(2)]
    aligned = all(np.isclose(np.abs(basis[i]).max(), 1.0) for i in range(2))
    if aligned and extent is not None:
        text = f"{screen[0]} {extent[0]:.1f} mm  ·  {screen[1]} {extent[1]:.1f} mm"
        draw_.text((w - 12, 15), text, fill="#333333", font=font(15), anchor="ra")
    if scale is not None and (aligned or extent is None):
        scale_bar(draw_, w, h, scale)
    axes(draw_, basis, (40, h - 36))


def scale_bar(draw_: ImageDraw.ImageDraw, w: int, h: int, scale: float) -> None:
    length = nice_length(0.25 * (w - 40) / scale)
    px = length * scale
    x1, y = w - 18, h - 16
    x0 = x1 - px
    draw_.line([(x0, y), (x1, y)], fill="black", width=2)
    for x in (x0, x1):
        draw_.line([(x, y - 6), (x, y + 2)], fill="black", width=2)
    draw_.text(((x0 + x1) / 2, y - 8), f"{length:g} mm", fill="black", font=font(15), anchor="md")


def axes(draw_: ImageDraw.ImageDraw, basis: np.ndarray, origin: tuple[int, int]) -> None:
    """Axis triad: X red, Y green, Z blue; an axis along the view is a dot (towards the camera)
    or a cross (away from it)."""
    colors = ["#d62728", "#2ca02c", "#1f5fd6"]
    ox, oy = origin
    screen = np.stack([basis[0], -basis[1]], axis=1)  # pixel direction of each axis
    in_plane = np.hypot(screen[:, 0], screen[:, 1]) >= 0.3
    # The label of an axis along the view goes where no arrow points.
    away = -screen[in_plane].sum(axis=0)
    away = away / np.linalg.norm(away) if np.linalg.norm(away) > 1e-6 else np.array([-0.7, 0.7])
    for i, name in enumerate("XYZ"):
        dx, dy = screen[i]
        if not in_plane[i]:
            r = 6
            draw_.ellipse([ox - r, oy - r, ox + r, oy + r], outline=colors[i], width=2)
            if basis[2][i] > 0:
                draw_.ellipse([ox - 2, oy - 2, ox + 2, oy + 2], fill=colors[i])
            else:
                draw_.line([(ox - 4, oy - 4), (ox + 4, oy + 4)], fill=colors[i], width=2)
                draw_.line([(ox - 4, oy + 4), (ox + 4, oy - 4)], fill=colors[i], width=2)
            label = (ox + 15 * away[0], oy + 15 * away[1])
            draw_.text(label, name, fill=colors[i], font=font(14), anchor="mm")
            continue
        tip = (ox + 18 * dx, oy + 18 * dy)
        draw_.line([(ox, oy), tip], fill=colors[i], width=3)
        draw_.text((ox + 26 * dx, oy + 26 * dy), name, fill=colors[i], font=font(14), anchor="mm")


def legend(
    draw_: ImageDraw.ImageDraw,
    items: list[tuple[str, tuple[float, float, float], str]],
    xy,
    max_width: float | None = None,
) -> int:
    """Legend entries ("box" | "line", RGB in 0..1, text), wrapped to `max_width`. Returns the
    number of rows drawn (24 px each)."""
    x0, y = xy
    x, rows = x0, 1
    for kind, color, text in items:
        width = 24 + draw_.textlength(text, font=font(15)) + 26
        if max_width is not None and x > x0 and x + width - 26 > x0 + max_width:
            x, y, rows = x0, y + 24, rows + 1
        rgb = tuple(int(c * 255) for c in color)
        if kind == "box":
            draw_.rectangle([x, y + 2, x + 14, y + 16], fill=rgb, outline="#555555")
        else:
            draw_.line([(x, y + 9), (x + 18, y + 9)], fill=rgb, width=3)
        draw_.text((x + 24, y), text, fill="#333333", font=font(15))
        x += width
    return rows


def _header(sheet: Image.Image, title: str, mesh: trimesh.Trimesh, edges: Edges) -> None:
    draw_ = ImageDraw.Draw(sheet)
    sx, sy, sz = mesh.extents
    line = (
        f"{title}  ·  {len(mesh.faces)} triangles  ·  {sx:.1f} × {sy:.1f} × {sz:.1f} mm  ·  "
        f"open edges {len(edges.open)}  ·  non-manifold edges {len(edges.nonmanifold)}"
    )
    draw_.text((12, 8), line, fill="black", font=font(18))
    legend(
        draw_,
        [
            ("box", BODY, "part"),
            ("box", BACK, "face seen from behind (inverted or exposed interior)"),
            ("line", LINE, "sharp edges (> 30°) and outlines"),
            ("line", DEFECT, "open / non-manifold edges"),
        ],
        (12, 38),
    )
