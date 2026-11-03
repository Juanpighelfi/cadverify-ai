"""Offline tests of the checks: spec echo, printability, source edits and sheet geometry.

Meshes are synthetic and written as ASCII STL with full doubles, as OpenSCAD writes them. The
OpenGL rendering itself is covered inside the sandbox image (tests/test_sandbox.py).
"""

import numpy as np
import pytest
import trimesh

from cadverify.cadcheck.files import scad_patch, scad_write
from cadverify.cadcheck.mesh import load_exact, mesh_report, report_from_mesh
from cadverify.cadcheck.printability import printability_report
from cadverify.cadcheck.render import VIEWS, camera, classify_edges, nice_length
from cadverify.cadcheck.section import polygons_from_segments
from cadverify.cadcheck.spec import SpecError, check_spec, find_spec, parse_spec
from cadverify.cadcheck.verify import printable_parts


def _stl(tmp_path, mesh, name="part.stl"):
    lines = ["solid part"]
    for triangle in mesh.triangles:
        lines += ["facet normal 0 0 0", "outer loop"]
        lines += [f"vertex {x!r} {y!r} {z!r}" for x, y, z in triangle.tolist()]
        lines += ["endloop", "endfacet"]
    path = tmp_path / name
    path.write_text("\n".join([*lines, "endsolid part"]) + "\n")
    return path


def _box(size, corner=(0, 0, 0)):
    """Axis-aligned box from `corner`, like OpenSCAD's cube()."""
    return trimesh.creation.box(size).apply_translation(np.add(corner, np.divide(size, 2)))


def _l_bracket(protrusion=False):
    """The L bracket in print orientation: wall flange on x = 0, shelf flange on y = 0.

    With `protrusion`, a cylinder of r = 8 centered on the inner corner sticks 2 mm out of
    both faces, the defect of tests/fixtures/l_bracket_protrusion.scad.
    """
    part = _box((6, 120, 50)).union(_box((130, 6, 50)))
    if protrusion:
        part = part.union(
            trimesh.creation.cylinder(8, 50, sections=64).apply_translation((6, 6, 25))
        )
    return part


SPEC = (
    '[["bounds", [[0, 0, 0], [130, 120, 50]]], ["bodies", 1], ["through_holes", 0], '
    '["support_faces", [["wall", "-x", 5000], ["shelf", "-y", 5500]]], '
    '["overhangs_allowed", [["roof", [[0, 100, 0], [10, 130, 50]]]]]]'
)


def test_parse_spec_reads_every_key():
    spec = parse_spec(SPEC)
    assert spec["bounds"] == [[0, 0, 0], [130, 120, 50]]
    assert spec["bodies"] == 1 and spec["through_holes"] == 0
    assert spec["support_faces"][1] == {"name": "shelf", "direction": "-y", "min_area_mm2": 5500}
    assert spec["overhangs_allowed"] == [{"name": "roof", "bounds": [[0, 100, 0], [10, 130, 50]]}]


def test_parse_spec_defaults_and_undef():
    spec = parse_spec('[["bounds", [[0, 0, 0], [1, 1, 1]]], ["through_holes", undef]]')
    assert spec["bodies"] == 1 and spec["through_holes"] is None
    assert spec["support_faces"] == [] and spec["overhangs_allowed"] == []


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ('[["bodies", 1]]', "needs"),
        ('[["bounds", [[0, 0, 0], [1, 1, 1]]], ["bound", 1]]', "Unknown keys"),
        ('[["bounds", [[0, 0, 0], [1, 1]]]]', "bounds must be"),
        ('[["bounds", [[2, 0, 0], [1, 1, 1]]]]', "min <= max"),
        ('[["bounds", [[0, 0, 0], [1, 1, 1]]], ["bodies", 1.5]]', "integer"),
        ('[["bounds", [[0, 0, 0], [1, 1, 1]]], ["support_faces", [["a", "x", 5]]]]', "direction"),
        ('[["bounds", [[0, 0, 0], [1, 1, 1]]], ["bounds", [[0, 0, 0], [1, 1, 1]]]]', "repeats"),
        ("[1, 2]", "pairs"),
        ("[[", "is not a valid vector"),
    ],
)
def test_parse_spec_rejects_malformed_specs(text, message):
    with pytest.raises(SpecError, match=message):
        parse_spec(text)


def test_find_spec_in_echo_lines():
    assert find_spec(['"something else"', "x = 2"]) is None
    line = f"cadverify_spec = {SPEC}"
    assert find_spec(["x = 2", line, line])["bodies"] == 1  # a repeated identical echo is fine
    with pytest.raises(SpecError, match="different values"):
        find_spec([line, 'cadverify_spec = [["bounds", [[0, 0, 0], [1, 1, 1]]]]'])


def _check(tmp_path, mesh, spec_text=SPEC):
    loaded = load_exact(_stl(tmp_path, mesh))
    return check_spec(loaded, report_from_mesh(loaded), parse_spec(spec_text))


def test_spec_check_passes_the_intended_bracket(tmp_path):
    result = _check(tmp_path, _l_bracket())
    assert result["ok"], result
    wall, shelf = result["support_faces"]
    assert wall["area_on_extreme_plane_mm2"] == 6000 and "protrusion_mm" not in wall
    assert shelf["area_on_extreme_plane_mm2"] == 6500


def test_spec_check_catches_the_protrusion(tmp_path):
    result = _check(tmp_path, _l_bracket(protrusion=True))
    assert not result["ok"]
    assert result["bounds"]["deviations"] == [
        "min x: measured -2.000, specified 0 (off by -2.000 mm)",
        "min y: measured -2.000, specified 0 (off by -2.000 mm)",
    ]
    for face in result["support_faces"]:
        assert not face["ok"] and face["area_on_extreme_plane_mm2"] == 0
        assert face["protrusion_mm"] == 2.0
    assert result["support_faces"][0]["largest_flat_face"]["plane"] == "x = 0.000"


def test_spec_check_counts_bodies_and_holes(tmp_path):
    plate = _box((40, 40, 5))
    for x in (10, 30):
        plate = plate.difference(trimesh.creation.cylinder(3, 20).apply_translation((x, 20, 0)))
    floating = trimesh.util.concatenate([plate, _box((2, 2, 2), (50, 0, 0))])
    result = _check(
        tmp_path,
        floating,
        '[["bounds", [[0, 0, 0], [52, 40, 5]]], ["bodies", 1], ["through_holes", 3]]',
    )
    assert result["bodies"] == {"ok": False, "expected": 1, "actual": 2}
    assert result["through_holes"] == {"ok": False, "expected": 3, "actual": 2}
    assert result["bounds"]["ok"] and not result["ok"]


def test_mesh_report_counts_through_holes(tmp_path):
    plate = _box((40, 40, 5))
    for x, y in ((10, 10), (30, 10), (10, 30), (30, 30)):
        plate = plate.difference(trimesh.creation.cylinder(3, 20).apply_translation((x, y, 0)))
    assert mesh_report(_stl(tmp_path, plate))["through_holes"] == 4
    assert mesh_report(_stl(tmp_path, _box((1, 1, 1))))["through_holes"] == 0


def test_a_section_closes_where_two_copies_of_a_corner_round_apart():
    # The two triangles at a corner give it an ulp apart, halfway between two 1e-6 mm grid lines:
    # snapped alone, the copies land on different grid points and the outline does not close.
    y = 29.0999985
    below = np.nextafter(y, 0)
    corners = [[0, 0], [40, 0], [40, y], [0, y]]
    segments = np.array([[corners[i], corners[(i + 1) % 4]] for i in range(4)], dtype=float)
    segments[3, 0] = [0, below]
    polygons, open_chains = polygons_from_segments(segments)
    assert open_chains == 0 and [round(p.area, 3) for p in polygons] == [round(40 * y, 3)]


def test_printability_box_on_the_bed_has_no_overhangs(tmp_path):
    report = printability_report(_stl(tmp_path, _box((20, 30, 10))))
    assert report["zones_total"] == 0 and report["fits_bed"]
    assert report["base_area_mm2"] == 600 and report["z_min"] == 0
    assert report["bed_margin_mm"] == [118, 113, 246]


def test_printability_groups_a_cantilever_ceiling_into_one_zone(tmp_path):
    # A T: a 10 mm post with a 50 × 10 mm top plate overhanging 20 mm on each side.
    t = _box((10, 10, 20), (20, 0, 0)).union(_box((50, 10, 4), (0, 0, 20)))
    report = printability_report(_stl(tmp_path, t))
    assert report["zones_total"] == 2  # the two ceilings are not connected by an edge
    assert [z["area_mm2"] for z in report["zones"]] == [200, 200]
    assert all(z["max_angle_deg"] == 90 for z in report["zones"])
    assert report["zones_undeclared"] == 2

    allowed = [{"name": "left", "bounds": [[0, 0, 19.8], [20, 10, 20.2]]}]
    declared = printability_report(_stl(tmp_path, t), allowed)
    assert declared["zones_undeclared"] == 1
    assert [z["declared_as"] for z in declared["zones"]] == [None, "left"]
    # Each ceiling hangs 20 mm from the post: a bridge would have to span 40 mm to hold its edge.
    assert declared["zones"][1]["bridge"]["farthest_mm"] == pytest.approx(20, abs=0.3)


def test_printability_measures_each_flat_ceiling_as_a_bridge(tmp_path):
    walls = _box((5, 20, 20)).union(_box((5, 20, 20), (55, 0, 0)))
    arch = walls.union(_box((60, 20, 3), (0, 0, 20)))
    (zone,) = printability_report(_stl(tmp_path, arch))["zones"]
    assert zone["bridge"] == {
        "z": 20.0,
        "z_top": 20.0,
        "flat": True,
        "area_mm2": 1000.0,
        "bounds_xy": [[5.0, 0.0], [55.0, 20.0]],
        "floating": False,
        "farthest_mm": 25.0,
        "bridge_mm": 50.0,
    }
    short = (
        _box((5, 20, 20)).union(_box((5, 20, 20), (13, 0, 0))).union(_box((18, 20, 3), (0, 0, 20)))
    )
    assert printability_report(_stl(tmp_path, short))["zones"][0]["bridge"]["bridge_mm"] == 8.0
    # A plate in the air beside a tower: nothing under it to start from.
    floating = trimesh.util.concatenate([_box((5, 5, 30)), _box((10, 10, 2), (8, 0, 10))])
    (plate,) = printability_report(_stl(tmp_path, floating))["zones"]
    assert plate["bridge"]["floating"] and plate["bridge"]["bridge_mm"] is None
    # The same plate 0.5 mm over a block: the block holds it through the gap, as a support would.
    held = trimesh.util.concatenate([floating, _box((10, 10, 9.5), (8, 0, 0))])
    held_plate = printability_report(_stl(tmp_path, held))["zones"][0]["bridge"]
    assert held_plate["farthest_mm"] == 0.0


def test_overhang_faces_that_share_no_edge_are_zones_of_their_own():
    from cadverify.cadcheck.printability import _zones

    box = trimesh.creation.box((10, 10, 10))
    top, bottom = (
        np.flatnonzero(box.face_normals[:, 2] > 0.9)[0],
        np.flatnonzero(box.face_normals[:, 2] < -0.9)[0],
    )
    selected = np.zeros(len(box.faces), bool)
    selected[[top, bottom]] = True
    zones = _zones(box, selected)
    assert sorted(int(z[0]) for z in zones) == sorted([int(top), int(bottom)])
    assert all(isinstance(z, np.ndarray) and z.dtype.kind == "i" for z in zones)
    angle = np.zeros(len(box.faces))
    assert zones[0][angle[zones[0]] >= 0].tolist() == zones[0].tolist()  # indexable by a mask


def test_printability_measures_the_part_of_an_overhang_steeper_than_60_degrees(tmp_path):
    def ledge(degrees, out):  # a wall with a ledge whose underside rises `degrees` from vertical
        rise = out / np.tan(np.radians(degrees))
        side = np.array(
            [[4, 0, 20 - rise / out], [5 + out, 0, 20 + rise], [5 + out, 0, 23 + rise], [4, 0, 23]]
        )
        wedge = trimesh.convex.convex_hull(np.vstack([side, side + [0, 20, 0]]))
        return _box((5, 20, 30)).union(wedge)

    (steep,) = printability_report(_stl(tmp_path, ledge(80, 10)))["zones"]
    assert steep["bridge"]["flat"] is False and steep["bridge"]["z"] == 20.0
    assert steep["bridge"]["farthest_mm"] == 10.0 and steep["bridge"]["bridge_mm"] == 20.0
    assert printability_report(_stl(tmp_path, ledge(80, 4)))["zones"][0]["bridge"]["bridge_mm"] == 8
    (sloped,) = printability_report(_stl(tmp_path, ledge(50, 10)))["zones"]
    assert (
        sloped["max_angle_deg"] == 50 and sloped["bridge"] is None
    )  # each layer rests on the last
    # A hole across a block: the top of its curved roof is steep, held by the sides of the hole.
    hole = trimesh.creation.cylinder(3, 30, sections=48)
    hole.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [0, 1, 0], [0, 0, 0]))
    block = _box((20, 20, 20), (-10, -10, -10)).difference(hole)
    (roof,) = printability_report(_stl(tmp_path, block))["zones"]
    assert not roof["bridge"]["floating"] and roof["bridge"]["bridge_mm"] == pytest.approx(3.3)
    # A pin lying 0.3 mm over a plate starts over it; 3 mm over it, it starts in the air.
    pin = trimesh.creation.cylinder(2, 10, sections=48)
    pin.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))
    over = trimesh.util.concatenate([_box((10, 10, 5)), pin.copy().apply_translation([5, 5, 7.3])])
    (underside,) = printability_report(_stl(tmp_path, over))["zones"]
    assert underside["bridge"]["farthest_mm"] == 0.0
    high = trimesh.util.concatenate([_box((10, 10, 5)), pin.apply_translation([5, 5, 10])])
    report = printability_report(_stl(tmp_path, high))
    assert report["zones"][0]["bridge"]["floating"] and len(report["in_the_air"]) == 1


def test_printability_finds_the_bodies_that_start_in_the_air(tmp_path):
    def body(z):  # a block standing on its edge, hung over a plate: its faces slope at 45°
        block = _box((10, 10, 10), (-5, -5, -5))
        block.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 4, [1, 0, 0]))
        return block.apply_translation([5, 5, z + 5 * np.sqrt(2)])

    plate = _box((10, 10, 5))
    near = printability_report(_stl(tmp_path, trimesh.util.concatenate([plate, body(5.4)])))
    assert near["in_the_air"] == []  # 0.4 mm over the plate: it droops into the clearance
    far = printability_report(_stl(tmp_path, trimesh.util.concatenate([plate, body(6.5)])))
    (hung,) = far["in_the_air"]
    assert hung["z"] == 6.5 and hung["volume_mm3"] == pytest.approx(1000, rel=1e-3)
    assert all(z["bridge"] is None for z in far["zones"])  # none steep enough to be a bridge
    assert printability_report(_stl(tmp_path, plate))["in_the_air"] == []


def test_printability_45_degree_chamfer_is_not_an_overhang(tmp_path):
    # A wedge whose underside rises at exactly 45°.
    wedge = trimesh.Trimesh(
        [
            [0, 0, 0],
            [10, 0, 0],
            [0, 0, 10],
            [20, 0, 10],
            [0, 5, 0],
            [10, 5, 0],
            [0, 5, 10],
            [20, 5, 10],
        ],
        [
            [0, 2, 1],
            [1, 2, 3],
            [4, 5, 6],
            [5, 7, 6],
            [0, 1, 4],
            [1, 5, 4],
            [2, 6, 3],
            [3, 6, 7],
            [0, 4, 2],
            [2, 4, 6],
            [1, 3, 5],
            [3, 7, 5],
        ],
    )
    trimesh.repair.fix_normals(wedge)
    report = printability_report(_stl(tmp_path, wedge))
    assert report["zones_total"] == 0
    steeper = printability_report(_stl(tmp_path, wedge), max_overhang_deg=40)
    assert steeper["zones_total"] == 1 and steeper["zones"][0]["max_angle_deg"] == 45


def test_printability_part_larger_than_the_bed(tmp_path):
    report = printability_report(_stl(tmp_path, _box((300, 10, 10))))
    assert not report["fits_bed"] and report["bed_margin_mm"][0] == -22


def test_scad_write_and_patch(tmp_path):
    assert scad_write("model.scad", "a = 1;\nb = 2;\n", tmp_path)["lines"] == 2
    result = scad_patch("model.scad", "b = 2;", "b = 3;", tmp_path)
    assert result["ok"] and result["line"] == 2
    assert (tmp_path / "model.scad").read_text() == "a = 1;\nb = 3;\n"


def test_scad_patch_needs_exactly_one_occurrence(tmp_path):
    scad_write("m.scad", "x = 1;\nx = 1;\n  y = 2;\n", tmp_path)
    twice = scad_patch("m.scad", "x = 1;", "x = 2;", tmp_path)
    assert not twice["ok"] and twice["occurrences"] == 2
    missing = scad_patch("m.scad", "y = 2;\nz", "", tmp_path)
    assert not missing["ok"] and missing["occurrences"] == 0 and "hint" not in missing
    spaces = scad_patch("m.scad", "y=2;", "y = 3;", tmp_path)
    assert spaces["occurrences"] == 0 and "whitespace" in spaces["hint"]
    assert (tmp_path / "m.scad").read_text() == "x = 1;\nx = 1;\n  y = 2;\n"


@pytest.mark.parametrize("path", ["../fuera.scad", "/etc/x.scad", "notas.txt", "."])
def test_scad_write_stays_in_the_workspace(tmp_path, path):
    root = tmp_path / "work"
    root.mkdir()
    assert not scad_write(path, "cube(1);", root)["ok"]
    assert not (tmp_path / "fuera.scad").exists()


def test_classify_edges_of_a_box_and_an_open_box():
    box = _box((10, 10, 10))
    edges = classify_edges(box)
    assert len(edges.sharp) == 12 and len(edges.open) == 0 and len(edges.nonmanifold) == 0
    opened = trimesh.Trimesh(box.vertices, box.faces[1:], process=False)
    assert len(classify_edges(opened).open) == 3


def test_cylinder_outline_comes_from_the_silhouette():
    cylinder = trimesh.creation.cylinder(5, 10, sections=64)
    edges = classify_edges(cylinder)
    assert len(edges.sharp) == 2 * 64  # the two rims; the side facets meet at 5.6°
    front = camera(VIEWS["front"])
    assert len(edges.silhouette(cylinder.face_normals, front[2])) == 2  # left and right sides


@pytest.mark.parametrize("name", list(VIEWS))
def test_cameras_are_right_handed(name):
    basis = camera(VIEWS[name])
    assert np.allclose(basis @ basis.T, np.eye(3))
    assert np.allclose(np.cross(basis[0], basis[1]), basis[2])


def test_axis_views_show_the_expected_axes():
    assert np.allclose(camera(VIEWS["front"])[:2], [[1, 0, 0], [0, 0, 1]])
    assert np.allclose(camera(VIEWS["side"])[:2], [[0, 1, 0], [0, 0, 1]])
    assert np.allclose(camera(VIEWS["top"])[:2], [[1, 0, 0], [0, 1, 0]])
    assert np.allclose(camera(VIEWS["bottom"])[:2], [[1, 0, 0], [0, -1, 0]])


def test_nice_length():
    assert [nice_length(v) for v in (37, 20, 9.9, 0.7)] == [20, 20, 5, 0.5]


def test_printable_parts():
    source = 'part = "assembly"; // [assembly, base, lid]\n'
    assert printable_parts(source) == ["base", "lid"]
    assert printable_parts("cube(1);\n") == [None]
