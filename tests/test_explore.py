"""The exploration tools: cuts and holes (section), the model's code (run), and the views
(render_view, inside the sandbox image only: it needs OpenSCAD and EGL).
"""

import hashlib
import itertools
import json
import os
import resource
from pathlib import Path

import numpy as np
import pytest
import trimesh
from PIL import Image, ImageDraw

from cadverify.cadcheck import run, section

ROOT = Path(__file__).parents[1]
BRACKET = ROOT / "tests/fixtures/l_bracket_protrusion.scad"
in_sandbox = pytest.mark.skipif(
    os.environ.get("CADVERIFY_SANDBOX") != "1", reason="runs inside the sandbox image"
)


def _box(extents=(40, 30, 20)) -> trimesh.Trimesh:
    box = trimesh.creation.box(extents)
    box.apply_translation(np.array(extents) / 2)
    return box


def _countersunk_plate() -> trimesh.Trimesh:
    """40 x 30 x 5 plate, a Ø6 hole at (20, 15) and a 90° countersink opening Ø9 at z = 5."""
    import manifold3d

    plate = manifold3d.Manifold.cube((40, 30, 5))
    bore = manifold3d.Manifold.cylinder(10, 3, 3, 48).translate((20, 15, -2.5))
    cone = manifold3d.Manifold.cylinder(3, 3, 6, 48).translate((20, 15, 3.5))
    mesh = (plate - bore - cone).to_mesh()
    return trimesh.Trimesh(np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts))


# ---- section ---------------------------------------------------------------------------------


def test_cut_keeps_the_side_against_the_normal_and_closes_it():
    cut = section.cut(_box(), (20, 15, 10), (0, 1, 0))
    assert cut.engine == "manifold"
    assert cut.mesh.is_watertight
    assert cut.mesh.bounds.tolist() == [[0, 0, 0], [40, 15, 20]]
    assert cut.mesh.volume == pytest.approx(12_000)
    caps = cut.mesh.face_normals[cut.cap]
    assert np.allclose(caps, [0, 1, 0])
    numbers = cut.profile.numbers()
    assert numbers["area_mm2"] == pytest.approx(800)
    assert (numbers["regions"], numbers["holes"], numbers["open_chains"]) == (1, 0, 0)


def test_profile_of_a_plate_with_a_hole():
    numbers = section.profile(_countersunk_plate(), (20, 15, 1), (0, 0, 1)).numbers()
    assert numbers["regions"] == 1 and numbers["holes"] == 1
    hole = numbers["region_list"][0]["hole_diameters_mm"][0]
    assert hole == pytest.approx(6, abs=0.05)


def test_through_holes_measure_each_end():
    (hole,) = section.through_holes(_countersunk_plate())
    assert hole["axis"] == "z" and hole["center"][:2] == pytest.approx([20, 15], abs=0.05)
    assert (hole["from"], hole["to"]) == (0, 5)
    assert hole["diameter_at_from_mm"] == pytest.approx(6, abs=0.05)
    assert hole["diameter_at_to_mm"] == pytest.approx(9, abs=0.2)  # the countersink's side


def test_an_open_mesh_falls_back_to_trimesh():
    box = _box()
    box.update_faces(np.arange(len(box.faces)) > 1)
    box.remove_unreferenced_vertices()
    assert section.to_manifold(box) is None
    cut = section.cut(box, (20, 15, 10), (0, 1, 0))
    assert cut.engine == "trimesh"


def test_an_inside_out_shell_is_not_cut_as_empty_space():
    box = _box()
    box.invert()
    assert section.to_manifold(box) is None


# ---- run -------------------------------------------------------------------------------------
# run() limits the processes of its user (RLIMIT_NPROC). In the sandbox that user is the
# session's own id; here it may be the host's user, with hundreds of processes, so these tests
# keep the current hard limit (the limit itself: the fork bomb of tests/test_hostile_docker.py).
# They run in the image, which has `python` on the PATH that run() uses.


def _run(kind, code, tmp_path, **kwargs):
    nproc = resource.getrlimit(resource.RLIMIT_NPROC)[1]
    return run.run(kind, code, cwd=str(tmp_path), nproc=nproc, **kwargs)


@in_sandbox
def test_run_returns_output_exit_code_and_time(tmp_path):
    r = _run("shell", "echo hello; echo error >&2; exit 3", tmp_path)
    assert (r["stdout"], r["stderr"], r["exit_code"], r["ok"]) == ("hello\n", "error\n", 3, False)
    r = _run("python", "import os; print(os.getcwd())", tmp_path)
    assert r["ok"] and r["stdout"].strip() == str(tmp_path)
    # The model's own OpenSCAD finds the standard parts, as the harness's exports do.
    (tmp_path / "nut.scad").write_text("use <cadverify_parts.scad>\nm3_nut();\n")
    r = _run("shell", "openscad -o nut.stl nut.scad 2>&1 && test -s nut.stl", tmp_path)
    assert r["ok"], r["stdout"]


@in_sandbox
def test_run_cuts_the_whole_group_at_the_timeout(tmp_path):
    r = _run("shell", "sleep 30 & sleep 30; echo never", tmp_path, timeout_s=1)
    assert r["timed_out"] and not r["ok"] and r["seconds"] < 5 and "never" not in r["stdout"]


@in_sandbox
def test_run_keeps_the_head_and_tail_of_long_output(tmp_path):
    code = "import sys; sys.stdout.write('a' * 100_000 + 'END')"
    r = _run("python", code, tmp_path, max_stdout=1000)
    assert r["stdout"].startswith("a" * 750) and r["stdout"].endswith("END")
    assert r["stdout_omitted_bytes"] == 100_003 - 1000
    assert "bytes left out" in r["stdout"]


@in_sandbox
def test_run_refuses_unknown_kinds_and_huge_programs(tmp_path):
    assert not _run("ruby", "puts 1", tmp_path)["ok"]
    assert "write it in parts" in _run("shell", "#" * 200_000, tmp_path)["error"]


def test_manifest_hashes_every_scad_and_lists_links_apart(tmp_path):
    (tmp_path / "exports").mkdir()
    (tmp_path / "model.scad").write_text("cube(1);")
    (tmp_path / "exports" / "copy.scad").write_text("cube(2);")
    (tmp_path / "a.stl").write_text("solid")
    (tmp_path / "link.scad").symlink_to("/etc/hostname")
    m = run.manifest(str(tmp_path))
    assert m["files"]["model.scad"][2] == hashlib.sha256(b"cube(1);").hexdigest()
    assert m["files"]["exports/copy.scad"][2] == hashlib.sha256(b"cube(2);").hexdigest()
    assert m["files"]["a.stl"][2] is None
    assert m["other"] == ["link.scad"] and "link.scad" not in m["files"]


def test_normalize_image_caps_the_size_and_stays_in_the_workspace(tmp_path):
    Image.new("RGBA", (4000, 1000), (255, 0, 0, 128)).save(tmp_path / "big.png")
    r = run.normalize_image("big.png", "renders/v.png", 1568, 1_800_000, root=str(tmp_path))
    assert r["ok"] and r["source_size"] == [4000, 1000] and r["size"] == [1568, 392]
    assert Image.open(tmp_path / "renders/v.png").mode == "RGB"
    (tmp_path / "text.png").write_text("not an image")
    assert not run.normalize_image("text.png", "x.png", 100, 10_000, root=str(tmp_path))["ok"]
    outside = run.normalize_image("../outside.png", "x.png", 100, 10_000, root=str(tmp_path))
    assert "is not a file of the workspace" in outside["error"]


@in_sandbox
def test_run_returns_when_a_background_child_keeps_the_pipes(tmp_path):
    # The sandbox's reap kills such children after every call (tests/test_hostile_docker.py).
    r = _run("shell", "sleep 30 & echo $!", tmp_path)
    pid = int(r["stdout"])
    try:
        assert r["ok"] and r["seconds"] < 3
        assert Path(f"/proc/{pid}").exists()
    finally:
        os.kill(pid, 9)


# ---- render_view (in the image) --------------------------------------------------------------


@pytest.fixture(scope="module")
def bracket(tmp_path_factory):
    from cadverify.cadcheck import scad_export

    out = tmp_path_factory.mktemp("bracket")
    export = scad_export(BRACKET, out_dir=out)
    assert export["ok"] and export["sha256"]
    return {"stl": export["path"], "label": "bracket", "spec": None}


@in_sandbox
def test_render_sheet_reports_the_sha_of_the_stl(bracket, tmp_path):
    from cadverify.cadcheck.render import render_sheet

    result = render_sheet(bracket["stl"], tmp_path / "s.png", ["iso"])
    assert result["stl_sha256"] == hashlib.sha256(Path(bracket["stl"]).read_bytes()).hexdigest()


@in_sandbox
def test_a_view_says_which_declared_details_it_shows_up_close(bracket, tmp_path):
    from cadverify.cadcheck.view import render_view

    spec = {
        "details": [
            {"name": "corner", "kind": "view", "box": [[-3, -3, -3], [3, 3, 3]]},
            {"name": "far", "kind": "view", "box": [[200, 200, 200], [201, 201, 201]]},
        ]
    }
    request = {
        "parts": [{**bracket, "spec": spec}],
        "out": str(tmp_path / "v.png"),
        "zoom": {"center": [0, 0, 0], "size_mm": 20},
    }
    result = render_view(request)
    assert result["ok"], result
    json.dumps(result)  # plain JSON: a numpy bool here crashed the views of an early session
    framing = {d["name"]: d for d in result["details_in_view"]}
    assert framing["corner"]["in_frame"] is True and framing["corner"]["close"] is True
    assert framing["far"]["in_frame"] is False and framing["far"]["close"] is False


@in_sandbox
def test_a_view_with_a_cut_shows_the_protrusion(bracket, tmp_path):
    from cadverify.cadcheck.view import render_view

    request = {
        "parts": [bracket],
        "out": str(tmp_path / "v.png"),
        "cut": {"point": [10, 10, 25], "normal": [0, 0, 1]},
        "zoom": {"center": [0, 6, 25], "size_mm": 30},
    }
    result = render_view(request)
    assert result["ok"], result
    assert Image.open(tmp_path / "v.png").size == tuple(result["size"])
    assert result["size"][0] == 2100  # the view and the profile
    (cut,) = result["cut"]
    assert cut["regions"] >= 1 and cut["open_chains"] == 0
    assert min(cut["bounds_3d"][0][0], cut["bounds_3d"][1][0]) == pytest.approx(-2, abs=0.01)
    assert result["camera"]["zoom"]["size_mm"] == 30 and result["camera"]["mm_per_px"]


@in_sandbox
def test_a_view_finds_the_holes_and_their_countersinks(bracket, tmp_path):
    from cadverify.cadcheck.view import render_view

    request = {"parts": [bracket], "out": str(tmp_path / "h.png"), "highlight": ["holes"]}
    result = render_view(request)
    (holes,) = result["holes"]
    axes = sorted(h["axis"] for h in holes["holes"])
    assert axes == ["x", "x", "y"] and holes["through_holes_total"] == 3
    for hole in holes["holes"]:  # countersinks open away from the wall and the shelf
        assert hole["diameter_at_from_mm"] < hole["diameter_at_to_mm"]


@in_sandbox
def test_a_zone_turned_away_from_the_camera_says_so(bracket, tmp_path):
    from cadverify.cadcheck.view import render_view

    def rib_floor(view):
        request = {
            "parts": [bracket],
            "out": str(tmp_path / f"{view}.png"),
            "camera": {"view": view},
        }
        result = render_view({**request, "highlight": ["overhangs"]})
        zones = result["overhangs"][0]["zone_list"]
        return max(zones, key=lambda z: z["area_mm2"])  # the floating rib's floor, facing -z

    assert rib_floor("top")["faces_camera"] is False
    assert rib_floor("bottom")["faces_camera"] is True


@in_sandbox
def test_view_options_and_errors(bracket, tmp_path):
    from cadverify.cadcheck.view import render_view

    out = str(tmp_path / "o.png")
    persp = render_view(
        {"parts": [bracket], "out": out, "projection": "perspective", "camera": {"azimuth": 30}}
    )
    assert persp["ok"] and persp["camera"]["mm_per_px"] is None
    two = render_view({"parts": [bracket, {**bracket, "label": "b"}], "out": out, "explode": 50})
    assert [p["offset"] for p in two["parts"]] == [[-25.0, 0.0, 0.0], [25.0, 0.0, 0.0]]
    bad = render_view({"parts": [bracket], "out": out, "highlight": ["everything"]})
    assert not bad["ok"] and "Unknown highlights" in bad["error"]
    bad = render_view(
        {"parts": [bracket], "out": out, "cut": {"point": [0, 0], "normal": [0, 0, 0]}}
    )
    assert not bad["ok"] and "cut" in bad["error"]
    bad = render_view({"parts": [bracket], "out": out, "camera": {"view": "roof"}})
    assert not bad["ok"] and "Unknown view" in bad["error"]


@in_sandbox
def test_a_part_hidden_behind_another_says_so(tmp_path):
    from cadverify.cadcheck.view import render_view

    wall = trimesh.creation.box((10, 100, 100))
    wall.apply_translation((55, 0, 0))  # x 50..60, in front of the block seen from +x
    block = trimesh.creation.box((10, 10, 10))
    for name, mesh in (("wall", wall), ("block", block)):
        mesh.export(tmp_path / f"{name}.stl")
    parts = [{"stl": str(tmp_path / f"{n}.stl"), "label": n} for n in ("wall", "block")]
    out = str(tmp_path / "v.png")
    front = render_view({"parts": parts, "out": out, "camera": {"direction": [1, 0, 0]}})
    assert [p["visible"] for p in front["parts"]] == [True, False]
    side = render_view({"parts": parts, "out": out, "camera": {"direction": [0, -1, 0.3]}})
    assert [p["visible"] for p in side["parts"]] == [True, True]


@in_sandbox
def test_a_part_seen_between_its_vertices_is_seen(tmp_path):
    """A zoom into the middle of a long bar, whole or cut, shows no vertex of it: what the
    camera sees of each part comes from the pixels, the cut face included."""
    from cadverify.cadcheck.view import render_view

    bar = trimesh.creation.box((400, 10, 10))
    far = trimesh.creation.box((10, 10, 10))
    far.apply_translation((0, 0, 100))
    for name, mesh in (("bar", bar), ("far", far)):
        mesh.export(tmp_path / f"{name}.stl")
    parts = [{"stl": str(tmp_path / f"{n}.stl"), "label": n} for n in ("bar", "far")]
    zoom = {"box": [[-10, -5, -5], [10, 5, 5]]}
    for cut in (None, {"point": [0, 0, 0], "normal": [0, 1, 0]}):
        request = {"parts": parts, "out": str(tmp_path / "v.png"), "zoom": zoom, "cut": cut}
        view = render_view(request)
        assert [p["visible"] for p in view["parts"]] == [True, False]


def test_labels_stay_inside_the_view():
    from cadverify.cadcheck.view import _place_labels

    size = (400, 300)
    labels = [((395.0, 150.0), "part_with_a_long_name", (0, 0, 0))]
    labels += [((200.0, 295.0), f"part_{i}", (0, 0, 0)) for i in range(4)]
    labels.append(((500.0, 10.0), "outside", (0, 0, 0)))
    placed = _place_labels(labels, size)
    assert [text for _, text, _, _, _ in placed] == ["part_with_a_long_name"] + [
        f"part_{i}" for i in range(4)
    ]
    for _, _, _, box, _ in placed:
        assert 0 <= box[0] < box[2] <= size[0] and 0 <= box[1] < box[3] <= size[1]
    assert placed[0][3][2] < 395  # no room on the right of its point: it goes to the left
    boxes = [box for _, _, _, box, _ in placed[1:]]
    assert not any(a[1] < b[3] and b[1] < a[3] for a, b in itertools.combinations(boxes, 2))


@in_sandbox
def test_the_view_title_wraps_and_lists_every_part(bracket, tmp_path):
    from cadverify.cadcheck.render import font
    from cadverify.cadcheck.view import _header_lines, render_view

    parts = [{**bracket, "label": f"part_{i}"} for i in range(6)]
    loaded = [{**p, "mesh": trimesh.load(p["stl"])} for p in parts]
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    long_title = "a view of the six parts together, moved apart to see the joints " * 3
    lines = {title: _header_lines(title, loaded, 1176) for title in ("six", long_title)}
    for wrapped in lines.values():
        assert all(draw.textlength(line, font=font(18)) <= 1176 for line in wrapped)
        assert all(f"{p['label']} " in " ".join(wrapped) for p in parts)
    assert len(lines[long_title]) > len(lines["six"]) > 1
    sizes = {
        title: render_view({"parts": parts, "out": str(tmp_path / "v.png"), "title": title})[
            "size"
        ][1]
        for title in lines
    }
    assert sizes[long_title] - sizes["six"] == 24 * (len(lines[long_title]) - len(lines["six"]))
