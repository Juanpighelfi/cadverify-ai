"""The details of a spec (cadcheck.details), the allowed coverage of printability and the
assembly (cadcheck.assembly: inside the sandbox image only, it needs OpenSCAD and EGL).

The three details are defects a model left in its own parts, rebuilt as small synthetic ones: a
rib that is not there, a rope flare sunk under a lip, and a pin entry chamfered the wrong way.
"""

import os
from pathlib import Path

import manifold3d
import numpy as np
import pytest
import trimesh

from cadverify.cadcheck import details
from cadverify.cadcheck.printability import allowed_coverage
from cadverify.cadcheck.spec import SpecError, parse_spec

in_sandbox = pytest.mark.skipif(
    os.environ.get("CADVERIFY_SANDBOX") != "1", reason="runs inside the sandbox image"
)
FN = 64


def _mesh(solid: manifold3d.Manifold) -> trimesh.Trimesh:
    mesh = solid.to_mesh()
    return trimesh.Trimesh(np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts))


def _measure(solid: manifold3d.Manifold, *declared: dict) -> list[dict]:
    return details.measure(_mesh(solid), solid, list(declared))


def _cone(d_top: float, d_bottom: float, z_bottom: float, z_top: float, x=15.0, y=15.0):
    height = z_top - z_bottom
    cone = manifold3d.Manifold.cylinder(height, d_bottom / 2, d_top / 2, FN)
    return cone.translate((x, y, z_bottom))


def _bore(d: float, z_bottom: float, z_top: float, x=15.0, y=15.0):
    return _cone(d, d, z_bottom, z_top, x, y)


# ---- details ------------------------------------------------------------------------------


def test_a_rib_that_is_not_there():
    plate = manifold3d.Manifold.cube((40, 40, 4))
    rib = manifold3d.Manifold.cube((2, 40, 8)).translate((10, 0, 4))
    declared = {"name": "rib", "kind": "material", "box": [[10, 5, 5], [12, 35, 11]]}
    declared["fraction"] = 0.9
    (missing,) = _measure(plate, declared)
    assert not missing["ok"] and missing["material_fraction"] == 0.0
    (there,) = _measure(plate + rib, declared)
    assert there["ok"] and there["material_fraction"] == pytest.approx(1.0)
    slot = {"name": "slot", "kind": "void", "box": [[20, 5, 5], [22, 35, 11]], "fraction": 1}
    assert _measure(plate + rib, slot)[0]["ok"]


def test_a_flare_sunk_under_a_lip_and_the_flare_at_the_face():
    plate = manifold3d.Manifold.cube((30, 30, 10))
    flare = {
        "name": "flare",
        "kind": "hole",
        "point": [15, 15, 15],
        "direction": [0, 0, -1],
        "diameters": [[0, 14], [2, 10]],
    }
    # The bug: the cone starts 0.5 mm under the face, below a Ø10 lip.
    sunk = plate - _bore(10, -1, 11) - _cone(14, 10, 7.5, 9.5)
    (bad,) = _measure(sunk, flare)
    assert not bad["ok"] and bad["mouth"] == pytest.approx([15, 15, 10], abs=1e-3)
    measured = {c["depth_mm"]: c["measured_mm"] for c in bad["diameters"]}
    assert measured[0] == pytest.approx(10, abs=0.05) and measured[2] == pytest.approx(11, abs=0.1)
    profile = dict((d, v) for d, v in bad["profile"])
    assert profile[0.75] == pytest.approx(13.5, abs=0.1)  # the cone, under the lip
    (good,) = _measure(plate - _bore(10, -1, 11) - _cone(14, 10, 8, 10.01), flare)
    assert good["ok"], good


def test_a_pin_entry_chamfered_the_wrong_way():
    block = manifold3d.Manifold.cube((20, 20, 20))

    def along_y(solid):  # a solid along +z from the origin, turned to go into y = 20 along -y
        return solid.rotate((90, 0, 0)).translate((10, 20, 10))

    bore = along_y(_cone(9.2, 9.2, 0, 15, 0, 0)).translate((0, 0.01, 0))
    entry = {
        "name": "entry",
        "kind": "hole",
        "point": [10, 25, 10],
        "direction": [0, -1, 0],
        "diameters": [[0, 11], [1, 9.2], [3, 9.2]],
    }
    wrong = along_y(_cone(11.45, 9.2, -0.01, 1.5, 0, 0))  # narrow at the mouth, wide inside
    (bad,) = _measure(block - bore - wrong, entry)
    assert not bad["ok"] and bad["diameters"][0]["measured_mm"] == pytest.approx(9.2, abs=0.15)
    right = along_y(_cone(9.2, 11, -0.01, 1, 0, 0))
    (good,) = _measure(block - bore - right, entry)
    assert good["ok"], good


def test_thickness_view_boxes_and_bad_points():
    shell = manifold3d.Manifold.cube((20, 20, 20)) - manifold3d.Manifold.cube(
        (16, 16, 16)
    ).translate((2, 2, 2))
    side = {"name": "wall", "kind": "thickness", "point": [-5, 10, 10], "direction": [1, 0, 0]}
    (wall,) = _measure(shell, {**side, "mm": 2})
    assert wall["ok"] and wall["measured_mm"] == pytest.approx(2) and wall["enters_at"][0] == 0
    assert not _measure(shell, {**side, "mm": 3})[0]["ok"]
    view = {"name": "relief", "kind": "view", "box": [[-1, -1, -1], [1, 1, 1]]}
    assert _measure(shell, view)[0]["ok"]
    air = _measure(shell, {**view, "box": [[50, 50, 50], [51, 51, 51]]})[0]
    assert not air["ok"] and air["material_fraction"] == 0
    inside = {**side, "point": [1, 10, 10]}
    assert "inside the material" in _measure(shell, {**inside, "mm": 2})[0]["error"]
    hole = {
        "name": "blind",
        "kind": "hole",
        "point": [10, 10, 25],
        "direction": [0, 0, -1],
        "diameters": [[0, 5]],
    }
    assert "there is no hole on that axis" in _measure(shell, hole)[0]["error"]


def test_the_spec_declares_details_and_the_assembly_keys():
    spec = parse_spec(
        '[["bounds", [[0, 0, 0], [1, 1, 1]]], ["copies", 2], ["details", [["n", "material", '
        '[[0, 0, 0], [1, 1, 1]], 0.8], ["h", "hole", [0, 0, 2], [0, 0, -2], [[0, 5]]]]]]'
    )
    assert spec["copies"] == 2 and spec["details"][1]["direction"] == [0, 0, -1]
    assembly = parse_spec(
        '[["motions", [["hinge", ["a"], "rotate", [0, 0, 0], [0, 0, 1], [90, 0]]]], '
        '["assembly_order", [[["a"], [0, 0, 0]], '
        '[["b"], [0, 0, -1], ["rotate", [0, 0, 0], [0, 0, 1], 30]]]]]',
        assembly=True,
    )
    assert assembly["bounds"] is None and assembly["bodies"] is None
    assert assembly["motions"][0]["range"] == [0, 90]
    assert assembly["assembly_order"][1]["turn"]["degrees"] == 30
    with pytest.raises(SpecError, match="they belong to each part"):
        parse_spec('[["bodies", 2]]', assembly=True)
    with pytest.raises(SpecError, match="the fraction goes from 0 to 1"):
        parse_spec(
            '[["bounds", [[0, 0, 0], [1, 1, 1]]], ["details", [["n", "void", '
            "[[0, 0, 0], [1, 1, 1]], 2]]]]"
        )
    with pytest.raises(SpecError, match="repeats"):
        parse_spec(
            '[["bounds", [[0, 0, 0], [1, 1, 1]]], ["details", [["n", "view", '
            '[[0, 0, 0], [1, 1, 1]]], ["n", "view", [[0, 0, 0], [1, 1, 1]]]]]]'
        )


def test_allowed_coverage_is_the_share_of_the_surface_in_the_boxes():
    box = trimesh.creation.box((10, 10, 10))
    box.apply_translation((5, 5, 5))
    whole = [{"name": "all", "bounds": [[-1, -1, -1], [11, 11, 11]]}]
    assert allowed_coverage(box, whole) == {
        "share": 1.0,
        "per_box": [{"name": "all", "share": 1.0}],
    }
    top = [{"name": "roof", "bounds": [[-1, -1, 9.5], [11, 11, 10.5]]}]
    assert allowed_coverage(box, top + whole)["per_box"][0]["share"] == pytest.approx(
        1 / 6, abs=1e-3
    )
    assert allowed_coverage(box, top)["share"] == pytest.approx(1 / 6, abs=1e-3)


# ---- the assembly (in the image) ----------------------------------------------------------

MODEL = """\
part = "assembly"; // [assembly, base, pin]
pin_diameter = 8;
pin_x = 20;
pin_scale = 1;
entry = [0, 0, -1];
turn_axis = [0, 0, 1];
no_pin = false;
loose = false;
two_units = false;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module base() difference() {
    cube([40, 40, 10]);
    translate([20, 20, -1]) cylinder(d = 8.4, h = 12, $fn = 48);
}
module pin() union() {
    cylinder(d = pin_diameter, h = 14, $fn = 48);
    translate([0, 0, 14]) cylinder(d = 12, h = 3, $fn = 48);
}
module unit(n) {
    instance(str("base", n), "base", n) translate([40 * (n - 1), 0, 0]) base();
    if (!no_pin)
        instance(str("pin", n), "pin", n)
            translate([pin_x + 40 * (n - 1), 20, 0]) scale(pin_scale) pin();
}
if (part == "assembly") {
    unit(1);
    if (two_units) unit(2);
    if (loose) translate([100, 0, 0]) cube(5);
    echo(cadverify_spec = [
        ["motions", [["pin turn", ["pin1"], "rotate", [20, 20, 0], turn_axis, [0, 90]]]],
        ["assembly_order", concat([[["base1"], [0, 0, 0]], [["pin1"], entry]],
            two_units ? [[["base2"], [-1, 0, 0]], [["pin2"], [0, 0, -1]]] : [])]
    ]);
} else if (part == "base") {
    base();
    echo(cadverify_spec = [["bounds", [[0, 0, 0], [40, 40, 10]]]]);
} else if (part == "pin") {
    pin();
    echo(cadverify_spec = [
        ["bounds", [[-6, -6, 0], [6, 6, 17]]],
        ["overhangs_allowed", [["head", [[-6, -6, 13.5], [6, 6, 14.5]]]]]
    ]);
}
"""

RINGS = """\
part = "assembly"; // [assembly, ring]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module ring() rotate_extrude($fn = 48) translate([15, 0]) circle(r = 2.5, $fn = 24);
if (part == "assembly") {
    instance("a", "ring") ring();
    instance("b", "ring") translate([15, 0, 0]) rotate([90, 0, 0]) ring();
    echo(cadverify_spec = [["assembly_order", [[["a"], [0, 0, 0]], [["b"], [0, 0, -1]]]]]);
} else {
    ring();
    echo(cadverify_spec = [["bounds", [[-17.5, -17.5, -2.5], [17.5, 17.5, 2.5]]], ["copies", 2]]);
}
"""


def _report(tmp_path, source=MODEL, requirements=None, **params):
    from cadverify.cadcheck.assembly import assembly_report

    for name, value in params.items():
        line = next(x for x in source.splitlines() if x.startswith(f"{name} = "))
        literal = str(value).lower() if isinstance(value, bool) else str(value)
        source = source.replace(line, f"{name} = {literal};")
    tmp_path.mkdir(parents=True, exist_ok=True)
    path = tmp_path / "model.scad"
    path.write_text(source)
    return assembly_report(path, tmp_path / "assembly", requirements=requirements)


@in_sandbox
def test_an_assembly_that_fits(tmp_path):
    report = _report(tmp_path)
    assert report["ok"], report["problems"]
    assert [i["name"] for i in report["instances"]] == ["base1", "pin1"]
    assert all(i["congruent"] for i in report["instances"])
    (pair,) = report["pairs"]
    assert pair["contact"] and pair["gap_mm"] == pytest.approx(0.2, abs=0.02)
    assert report["motions"][0]["ok"] and report["assembly_order_ok"]


@in_sandbox
def test_an_overlap_a_missing_part_a_loose_part_and_geometry_outside(tmp_path):
    overlap = _report(tmp_path / "a", pin_diameter=10)["problems"]["G3"]
    assert any("base1 and pin1 overlap" in p for p in overlap)
    missing = _report(tmp_path / "b", no_pin=True)["problems"]["G3"]
    assert "the part pin is not in the assembly (unit 1)" in missing
    loose = _report(tmp_path / "c", pin_x=100)["problems"]["G3"]
    assert any("is not one group" in p for p in loose)
    outside = _report(tmp_path / "d", loose=True)["problems"]["G3"]
    assert any("outside instance()" in p for p in outside)
    scaled = _report(tmp_path / "e", pin_scale=1.1)["problems"]["G3"]
    assert any("is not the part pin that is printed" in p for p in scaled)


@in_sandbox
def test_the_units_the_request_chains(tmp_path):
    one = _report(tmp_path / "a", requirements={"units": 2})["problems"]["G3"]
    assert any("does not show unit 2" in p for p in one)
    two = _report(tmp_path / "b", requirements={"units": 2}, two_units=True)
    assert two["ok"], two["problems"]
    assert two["units"] == {"required": 2, "present": [1, 2], "links": [[1, 2]]}


@in_sandbox
def test_a_motion_that_collides_and_an_entry_that_is_blocked(tmp_path):
    swing = _report(tmp_path / "a", turn_axis="[1, 0, 0]")
    (problem,) = swing["problems"]["G4"]
    assert problem.startswith("motion pin turn: collides between")
    collision = swing["motions"][0]["collisions"]
    assert Path(collision["overlap_stl"]).exists() and Path(collision["posed_stl"]).exists()
    side = _report(tmp_path / "b", entry="[1, 0, 0]")["problems"]["G4"]
    assert len(side) == 1 and "does not go in moving along [1, 0, 0]" in side[0]
    assert "it would go in along -z" in side[0]


@in_sandbox
def test_a_closed_ring_does_not_go_into_another(tmp_path):
    report = _report(tmp_path, source=RINGS)
    (problem,) = report["problems"]["G4"]
    assert "it goes in along no axis direction" in problem
    assert report["copies"] == [{"part": "ring", "expected": 2, "placed": 2, "ok": True}]
