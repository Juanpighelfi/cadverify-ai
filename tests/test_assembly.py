"""The details of a spec (cadcheck.details), the allowed coverage of printability and the
assembly (cadcheck.assembly: its reports inside the sandbox image only, they need OpenSCAD
and EGL).

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


def test_a_motion_may_flex_and_an_assembly_may_print_in_place():
    flex = '["flex", [["lid", "jar", 0.5, "the detent bump rides over the ramp"]]]'
    assembly = parse_spec(
        f'[["motions", [["lock", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [0, 90], {flex}], '
        '["drawer", ["tray"], "slide", [1, 0, 0], [0, 30]]]], ["print_in_place", 0.3], '
        '["overhangs_allowed", [["pin underside", [[0, 0, 5], [10, 10, 6]]]]]]',
        assembly=True,
    )
    lock, drawer = assembly["motions"]
    assert lock["flex"] == [
        {"a": "lid", "b": "jar", "max_mm": 0.5, "reason": "the detent bump rides over the ramp"}
    ]
    assert drawer["flex"] == [] and assembly["print_in_place"] == {"min_gap_mm": 0.3}
    assert assembly["overhangs_allowed"][0]["name"] == "pin underside"
    assert parse_spec("[]", assembly=True)["print_in_place"] is None

    slide = '["s", ["tray"], "slide", [1, 0, 0], [0, 30], ["flex", [{}]]]'
    for bad in ('["tray", "body", 1.5, "deep"]', '["tray", "tray", 0.5, "self"]', '["tray"]'):
        with pytest.raises(SpecError, match="the flex is"):
            parse_spec(f'[["motions", [{slide.format(bad)}]]]', assembly=True)
    with pytest.raises(SpecError, match="from 0.2 to 1.0 mm"):
        parse_spec('[["print_in_place", 0.1]]', assembly=True)
    with pytest.raises(SpecError, match="overhangs_allowed of the assembly is for print_in_place"):
        parse_spec('[["overhangs_allowed", [["a", [[0, 0, 0], [1, 1, 1]]]]]]', assembly=True)


def test_an_assembly_printed_in_place_may_print_in_another_pose():
    hinge = '["hinge", ["lid"], "rotate", [0, 30, 10], [1, 0, 0], [0, 180]]'
    spec = f'[["motions", [{hinge}]], ["print_in_place", 0.3], ["print_pose", [["hinge", 180]]]]'
    assert parse_spec(spec, assembly=True)["print_pose"] == [{"motion": "hinge", "value": 180.0}]
    assert parse_spec(f'[["motions", [{hinge}]]]', assembly=True)["print_pose"] == []
    for pose, message in [
        ('[["hinge", 200]]', r"in the motion's range \[0, 180\]; got 200"),
        ('[["drawer", 10]]', "there is no motion 'drawer'"),
        ('[["hinge"]]', r'each entry is \["motion", value\]'),
    ]:
        with pytest.raises(SpecError, match=message):
            parse_spec(spec.replace('[["hinge", 180]]', pose), assembly=True)
    with pytest.raises(SpecError, match="print_pose .* needs print_in_place"):
        parse_spec(f'[["motions", [{hinge}]], ["print_pose", [["hinge", 90]]]]', assembly=True)


def test_a_motion_may_screw_and_drive_other_instances():
    drives = (
        '["drives", [[["planet"], "rotate", [10, 0, 0], [0, 0, 1], -2], '
        '[["rack"], "slide", [1, 0, 0], 0.1]]]'
    )
    assembly = parse_spec(
        '[["motions", [["open", ["cap"], "screw", [0, 0, 0], [0, 0, 2], -3, [0, -720]], '
        f'["crank", ["sun"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360], {drives}]]], '
        '["assembly_order", [[["jar"], [0, 0, 0]], '
        '[["cap"], [0, 0, -1], ["screw", [0, 0, 0], [0, 0, 1], -3, 720]]]]]',
        assembly=True,
    )
    screw, crank = assembly["motions"]
    assert screw["kind"] == "screw" and screw["pitch_mm"] == -3 and screw["axis"] == [0, 0, 1]
    assert screw["range"] == [-720, 0] and screw["drives"] == []
    planet, rack = crank["drives"]
    assert planet == {
        "instances": ["planet"],
        "kind": "rotate",
        "point": [10, 0, 0],
        "axis": [0, 0, 1],
        "ratio": -2,
    }
    assert rack == {"instances": ["rack"], "kind": "slide", "axis": [1, 0, 0], "ratio": 0.1}
    turn = assembly["assembly_order"][1]["turn"]
    assert turn["kind"] == "screw" and turn["pitch_mm"] == -3 and turn["degrees"] == 720

    motion = '["m", ["cap"], "rotate", [0, 0, 0], [0, 0, 1], [0, 90], {}]'
    for bad, message in [
        ('["drives", [[["b"], "rotate", [0, 0, 0], [0, 0, 1], 0]]]', "drives is"),
        ('["drives", [[["b"], "spin", [0, 0, 0], [0, 0, 1], 1]]]', "drives is"),
        (
            '["drives", [[["b"], "slide", [1, 0, 0], 1], [["b"], "slide", [0, 1, 0], 1]]]',
            "in one group of its drives only",
        ),
        ('["drives", []], ["drives", []]', "motions:"),
    ]:
        with pytest.raises(SpecError, match=message):
            parse_spec(f'[["motions", [{motion.format(bad)}]]]', assembly=True)
    drawer = '["d", ["tray"], "slide", [1, 0, 0], [0, 30], ["stops", [30, 0]]]'
    stops = parse_spec(f'[["motions", [{drawer}]], ["held", ["tray"]]]', assembly=True)
    assert stops["motions"][0]["stops"] == [0, 30] and stops["held"] == ["tray"]
    with pytest.raises(SpecError, match="a stop is an end of the range it sweeps, 0 or 30; got 20"):
        parse_spec(f'[["motions", [{drawer.replace("30, 0]", "20]")}]]]', assembly=True)
    detent = '["flex", [["lid", "base", 0.4, "the bump clicks into each notch"]]]'
    dial = '["d", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360], {}]'
    clicks = dial.format(detent + ', ["rests", [360, 0, 120, 240]]')
    rests = parse_spec(f'[["motions", [{clicks}]]]', assembly=True)
    assert rests["motions"][0]["rests"] == [0, 120, 240, 360]
    for bad, message in [
        ('["rests", [0, 120]]', "rests are where a detent holds the motion, so it needs the flex"),
        (detent + ', ["rests", [0, 400]]', "a rest is a value of the range it sweeps, 0 to 360"),
        (detent + ', ["rests", []]', "rests is"),
    ]:
        with pytest.raises(SpecError, match=message):
            parse_spec(f'[["motions", [{dial.format(bad)}]]]', assembly=True)
    with pytest.raises(SpecError, match="the pitch of a screw"):
        parse_spec(
            '[["motions", [["m", ["c"], "screw", [0, 0, 0], [0, 0, 1], 0, [0, 90]]]]]',
            assembly=True,
        )


def test_a_driven_instance_turns_on_its_axis_and_is_carried_by_the_motion():
    from cadverify.cadcheck.assembly import _pose, _poses, rotation, translation

    screw = {"kind": "screw", "point": [0, 0, 0], "axis": [0, 0, 1], "pitch_mm": 4}
    assert np.allclose(
        _pose(screw, 90), translation([0, 0, 1], 1) @ rotation([0, 0, 0], [0, 0, 1], 90)
    )
    # The carrier turns 30° about the center; its planet also turns -60° on its own pin.
    carrier = {"name": "c", "instances": ["carrier", "planet"], "kind": "rotate"}
    carrier.update(point=[0, 0, 0], axis=[0, 0, 1], range=[0, 360])
    carrier["drives"] = [
        {
            "instances": ["planet"],
            "kind": "rotate",
            "point": [10, 0, 0],
            "axis": [0, 0, 1],
            "ratio": -2,
        },
        {"instances": ["sun"], "kind": "rotate", "point": [0, 0, 0], "axis": [0, 0, 1], "ratio": 3},
    ]
    poses = _poses(carrier, 30)
    assert np.allclose(poses["carrier"], rotation([0, 0, 0], [0, 0, 1], 30))
    assert np.allclose(poses["sun"], rotation([0, 0, 0], [0, 0, 1], 90))
    planet = rotation([0, 0, 0], [0, 0, 1], 30) @ rotation([10, 0, 0], [0, 0, 1], -60)
    assert np.allclose(poses["planet"], planet)
    # Its pin, at 10 mm, ends where the carrier takes it.
    pin = poses["planet"] @ [10, 0, 0, 1]
    assert np.allclose(pin[:3], [10 * np.cos(np.pi / 6), 10 * np.sin(np.pi / 6), 0])


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
hole = 8.4;
in_place = 0;
print_pose = false;
head_allowed = false;
press = false;
whole = false;
no_pin = false;
loose = false;
two_units = false;
together = false;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module base() difference() {
    cube([40, 40, 10]);
    translate([20, 20, -1]) cylinder(d = hole, h = 12, $fn = 48);
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
        ["motions", [["pin turn", whole ? ["pin1", "base1"] : ["pin1"], "rotate", [20, 20, 0],
            turn_axis, [0, 90]]]],
        ["assembly_order", together ? [[["base1", "pin1"], [0, 0, 0]]]
            : concat([[["base1"], [0, 0, 0]], [["pin1"], entry]],
                two_units ? [[["base2"], [-1, 0, 0]], [["pin2"], [0, 0, -1]]] : [])],
        each (in_place > 0 ? [["print_in_place", in_place]] : []),
        each (print_pose ? [["print_pose", [["pin turn", 90]]]] : []),
        each (head_allowed ? [["overhangs_allowed", [["pin head", [[14, 14, 13.5],
            [26, 26, 14.5]]]]]] : []),
        each (press ? [["allowed_interferences", [["base1", "pin1", "press fit"]]]] : [])
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


# A slider that rides over a ridge on its base: an elastic catch when the motion declares it.
SLIDER = """\
part = "assembly"; // [assembly, base, slider]
ridge = 0.6;
travel = 40;
flex_mm = 0.5;
with_flex = true;
stops = [];
rests = [];
wall = false;
entry = [0, 0, -1];
entry_flex = false;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module base() union() {
    cube([60, 8, 10]);
    translate([29, 0, 10]) cube([2, 8, ridge]);
    if (wall) translate([44, 0, 10]) cube([2, 8, 6]);
}
module slider() cube([4, 8, 5]);
if (part == "assembly") {
    instance("base1", "base") base();
    instance("slider1", "slider") translate([0, 0, 10.2]) slider();
    flex = [["flex", [["slider1", "base1", flex_mm, "the catch rides over the ridge"]]]];
    echo(cadverify_spec = [
        ["motions", [concat(["slide", ["slider1"], "slide", [1, 0, 0], [0, travel]],
            with_flex ? flex : [], len(stops) ? [["stops", stops]] : [],
            len(rests) ? [["rests", rests]] : [])]],
        ["assembly_order", [[["base1"], [0, 0, 0]],
            concat([["slider1"], entry], entry_flex ? flex : [])]]
    ]);
} else if (part == "base") {
    base();
    echo(cadverify_spec = [["bounds", [[0, 0, 0], [60, 8, wall ? 16 : 10 + ridge]]]]);
} else {
    slider();
    echo(cadverify_spec = [["bounds", [[0, 0, 0], [4, 8, 5]]]]);
}
"""


# A nut on a threaded rod, both single-start helices (an off-center circle, twisted): it moves
# only by screwing along the rod.
SCREW = """\
part = "assembly"; // [assembly, rod, nut]
thread = 4;
kind = "screw";
pitch = 4;
entry = "screw";
$fn = 48;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module helix(r, h) linear_extrude(height = h, twist = -360 * h / thread, slices = 8 * h)
    translate([0.8, 0]) circle(r = r);
module rod() helix(4, 20);
module nut() difference() {
    translate([-8, -8, 10]) cube([16, 16, 6]);
    translate([0, 0, -1]) rotate([0, 0, -360 / thread]) helix(4.4, 30);
}
if (part == "assembly") {
    instance("rod1", "rod") rod();
    instance("nut1", "nut") nut();
    axis = [[0, 0, 0], [0, 0, 1]];
    along = kind == "screw" ? concat(["screw"], axis, [pitch]) : concat(["rotate"], axis);
    turn = concat([entry], axis, entry == "screw" ? [4, -1080] : [-1080]);
    echo(cadverify_spec = [
        ["motions", [concat(["up", ["nut1"]], along, [[0, 360]])]],
        ["assembly_order", [[["rod1"], [0, 0, 0]], [["nut1"], [0, 0, -1], turn]]]
    ]);
} else if (part == "rod") {
    rod();
    echo(cadverify_spec = [["bounds", [[-4.8, -4.8, 0], [4.8, 4.8, 20]]]]);
} else {
    nut();
    echo(cadverify_spec = [["bounds", [[-8, -8, 10], [8, 8, 16]]]]);
}
"""


# Two gears side by side, the second cut by the first as they turn together at -1: one turns
# only when it drives the other.
GEARS = """\
part = "assembly"; // [assembly, pins, cut]
ratio = -1;
driven = true;
d = 21;
$fn = 32;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module pins() union() {
    circle(r = 9.5);
    for (i = [0:9]) rotate(i * 36) translate([10.5, 0]) circle(r = 1.6);
}
module cut() difference() {
    translate([d, 0]) circle(r = 12.1);
    for (t = [0:2:358]) translate([d, 0]) rotate(t) translate([-d, 0]) rotate(t)
        offset(r = 0.3) pins();
}
if (part == "assembly") {
    instance("a", "pins") linear_extrude(5) pins();
    instance("b", "cut") linear_extrude(5) cut();
    drives = driven ? [["drives", [[["b"], "rotate", [d, 0, 0], [0, 0, 1], ratio]]]] : [];
    echo(cadverify_spec = [
        ["motions", [concat(["turn", ["a"], "rotate", [0, 0, 0], [0, 0, 1], [0, 72]], drives)]],
        ["assembly_order", [[["a"], [0, 0, 0]], [["b"], [0, 0, -1]]]]
    ]);
} else if (part == "pins") {
    linear_extrude(5) pins();
    echo(cadverify_spec = [["bounds", [[-12.1, -12.1, 0], [12.1, 12.1, 5]]]]);
} else {
    linear_extrude(5) cut();
    echo(cadverify_spec = [["bounds", [[9, -12.1, 0], [33.1, 12.1, 5]]]]);
}
"""


# A block with a pocket for an M3 nut, and the standard nut in it.
NUT = """\
part = "assembly"; // [assembly, block]
nut_scale = 1;
name = "m3_nut";
pocket = 5.8;
use <cadverify_parts.scad>
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module block() difference() {
    translate([-6, -6, 0]) cube([12, 12, 4]);
    translate([0, 0, 1.4]) cylinder(d = pocket / cos(30), h = 3, $fn = 6);
    translate([0, 0, -1]) cylinder(d = 3.4, h = 6, $fn = 24);
}
if (part == "assembly") {
    instance("block1", "block") block();
    instance("nut1", str("standard:", name)) translate([0, 0, 1.5]) scale(nut_scale) m3_nut();
    echo(cadverify_spec = [["assembly_order", [[["block1"], [0, 0, 0]], [["nut1"], [0, 0, -1]]]]]);
} else {
    block();
    echo(cadverify_spec = [["bounds", [[-6, -6, 0], [6, 6, 4]]]]);
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
def test_a_standard_part_is_the_part_of_the_library(tmp_path):
    report = _report(tmp_path / "a", NUT)
    assert report["ok"], report["problems"]
    nut = next(i for i in report["instances"] if i["name"] == "nut1")
    assert nut["congruent"] and report["copies"] == [
        {"part": "block", "expected": 1, "placed": 1, "ok": True}
    ]
    (problem,) = _report(tmp_path / "b", NUT, nut_scale=0.95)["problems"]["G3"]
    assert problem.startswith("the instance nut1 is not the standard part m3_nut()")
    (problem,) = _report(tmp_path / "c", NUT, name='"m4_nut"')["problems"]["G3"]
    assert problem.startswith("there is no standard part 'm4_nut': cadverify_parts.scad has")
    # A pocket drawn for a nut smaller than the standard one: the real nut does not go in.
    (problem,) = _report(tmp_path / "d", NUT, pocket=5.4)["problems"]["G3"]
    assert problem.startswith("block1 and nut1 overlap")


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
    # Base and pin swung together: nothing moves against anything, so nothing collides either.
    (whole,) = _report(tmp_path / "w", turn_axis="[1, 0, 0]", whole=True)["problems"]["G4"]
    assert whole.startswith("motion pin turn: it moves every instance together")
    side = _report(tmp_path / "b", entry="[1, 0, 0]")["problems"]["G4"]
    assert len(side) == 1 and "does not go in moving along [1, 0, 0]" in side[0]
    assert "it would go in along -z" in side[0]
    # Placed together in the first step, the pin never comes in: only a print starts that way.
    (together,) = _report(tmp_path / "t", together=True)["problems"]["G4"]
    assert together.startswith("assembly_order, step 1 places base1, pin1 together")
    printed = _report(tmp_path / "p", together=True, hole=8.8, in_place=0.3, head_allowed=True)
    assert printed["problems"]["G4"] == [], printed["problems"]


@in_sandbox
def test_a_press_fit_is_swept_and_pushed_in_as_a_fit(tmp_path):
    # The pin 0.1 mm into the wall of its hole, declared as a press fit.
    fit = _report(tmp_path / "a", pin_diameter=8.6, press=True)
    assert fit["ok"], fit["problems"]
    assert [p.get("permitted") for p in fit["pairs"]] == ["press fit"]
    # Turning in its hole stays a fit all the way round; swinging out through the base does not.
    swing = _report(tmp_path / "b", pin_diameter=8.6, press=True, turn_axis="[1, 0, 0]")
    (problem,) = swing["problems"]["G4"]
    assert problem.startswith("motion pin turn: collides between") and "pin1 with base1" in problem
    # Pushed in from above it goes in; from below, its head would cross the base.
    below = _report(tmp_path / "c", pin_diameter=8.6, press=True, entry="[0, 0, 1]")
    (problem,) = below["problems"]["G4"]
    assert "does not go in moving along [0, 0, 1]: it hits base1" in problem
    assert "it would go in along -z" in problem


@in_sandbox
def test_a_part_printed_in_place_is_held_by_the_others():
    from cadverify.cadcheck.assembly import _held

    # A pin through a 6 mm hole in a plate, 0.5 mm clear all round, with a cap under the plate.
    plate = manifold3d.Manifold.cube((20, 20, 4)) - _bore(6, -1, 5, x=10, y=10)
    pin = _bore(5, -1.5, 5.5, x=10, y=10) + _bore(9, -2.5, -1.5, x=10, y=10)

    def judged(pin):
        pair = (("plate", plate), ("pin", pin))
        instances = [
            {"name": n, "part": n, "unit": 1, "_mesh": _mesh(s), "_solid": s} for n, s in pair
        ]
        problems: list[str] = []
        return [r["free"] for r in _held(instances, [], True, problems)], problems

    # Capped at the top too, it goes nowhere: the caps stop it along the axis, the hole across.
    assert judged(pin + _bore(9, 5.5, 6.5, x=10, y=10)) == ([[], []], [])
    free, problems = judged(pin)
    assert free == [["+z"], ["-z"]]
    assert problems[1].startswith(
        "pin is not held: printed in place, it comes off the others moving along -z"
    )
    # Assembled and not printed, `held` lists what has to stay on.
    pair = [("plate", plate), ("pin", pin)]
    instances = [{"name": n, "part": n, "unit": 1, "_mesh": _mesh(s), "_solid": s} for n, s in pair]
    problems = []
    assert _held(instances, ["pin", "cap"], False, problems) == [
        {"instance": "pin", "free": ["-z"]}
    ]
    assert problems[0] == "held: there are no instances ['cap']"
    assert problems[1].startswith("pin is not held: assembled, it comes off the others moving")


@in_sandbox
def test_a_closed_ring_does_not_go_into_another(tmp_path):
    report = _report(tmp_path, source=RINGS)
    (problem,) = report["problems"]["G4"]
    assert "it goes in along no axis direction" in problem
    assert report["copies"] == [{"part": "ring", "expected": 2, "placed": 2, "ok": True}]


@in_sandbox
def test_a_catch_that_flexes_over_a_ridge(tmp_path):
    rigid = _report(tmp_path / "a", SLIDER, with_flex=False)
    (problem,) = rigid["problems"]["G4"]
    assert problem.startswith("motion slide: collides between")
    report = _report(tmp_path / "b", SLIDER)
    assert report["ok"], report["problems"]
    (flex,) = report["motions"][0]["flex"]
    assert flex["ok"] and flex["depth_mm"] == pytest.approx(0.4, abs=0.01)
    assert flex["poses"][0] > 24 and flex["poses"][1] < 32 and Path(flex["overlap_stl"]).exists()
    shallow = _report(tmp_path / "c", SLIDER, flex_mm=0.3)
    (problem,) = shallow["problems"]["G4"]
    assert "slider1 goes 0.4 mm deep into base1" in problem and "than the 0.3 mm" in problem
    stuck = _report(tmp_path / "d", SLIDER, travel=28)
    (problem,) = stuck["problems"]["G4"]
    assert "still overlap at 28 mm, an end of its range" in problem
    # Short of the ridge, the catch rides over nothing: a flex declared that never bends.
    (problem,) = _report(tmp_path / "e", SLIDER, travel=20)["problems"]["G4"]
    assert problem.startswith("motion slide: slider1 and base1 never overlap along it")


@in_sandbox
def test_a_nut_screws_along_its_rod(tmp_path):
    report = _report(tmp_path / "a", SCREW)
    assert report["ok"], report["problems"]
    assert report["motions"][0]["kind"] == "screw" and report["motions"][0]["pitch_mm"] == 4
    # Turned without going up, or screwed the wrong way, the thread hits the rod's.
    for name, params in [("b", {"kind": '"rotate"'}), ("c", {"pitch": -4})]:
        (problem,) = _report(tmp_path / name, SCREW, **params)["problems"]["G4"]
        assert problem.startswith("motion up: collides between") and "nut1 with rod1" in problem
    # Turned into place without screwing, it comes down through the thread and turns through it.
    straight, turning = _report(tmp_path / "d", SCREW, entry='"rotate"')["problems"]["G4"]
    assert "step 2: nut1 does not go in moving along [0, 0, -1]: it hits rod1" in straight
    assert turning.startswith("assembly_order, step 2: turning -1080° into place, nut1 hits rod1")


@in_sandbox
def test_a_gear_turns_when_it_drives_the_other(tmp_path):
    report = _report(tmp_path / "a", GEARS)
    assert report["ok"], report["problems"]
    assert report["motions"][0]["drives"] == [{"instances": ["b"], "ratio": -1.0}]
    for name, params in [("b", {"driven": False}), ("c", {"ratio": -0.9})]:
        (problem,) = _report(tmp_path / name, GEARS, **params)["problems"]["G4"]
        assert problem.startswith("motion turn: collides between") and "with" in problem


@in_sandbox
def test_a_motion_stops_where_a_part_is_in_its_way(tmp_path):
    report = _report(tmp_path / "a", SLIDER, wall=True, stops="[0, 40]")
    (problem,) = report["problems"]["G4"]
    assert problem.startswith("motion slide: it does not stop at 0 mm: moved 2 mm past it")
    stops = report["motions"][0]["stops"]
    assert stops[0] == {"at": 0, "ok": False}
    # The wall is on the base the slider flexes against: it stops it once deeper than the flex.
    assert stops[1]["ok"] and stops[1]["by"] == ["slider1", "base1"]
    assert 0.5 <= stops[1]["after"] <= 0.75
    # Short of the ridge, the ridge stops it; declared as a flex it rides over, it does not (and
    # the flex, never reached, bends nothing).
    stopped = _report(tmp_path / "b", SLIDER, travel=24, stops="[24]", with_flex=False)
    assert stopped["ok"], stopped["problems"]
    never, rides = _report(tmp_path / "c", SLIDER, travel=24, stops="[24]")["problems"]["G4"]
    assert "never overlap" in never and rides.startswith("motion slide: it does not stop at 24")


@in_sandbox
def test_a_detent_rests_free_and_rides_over_its_ridge_between_rests(tmp_path):
    report = _report(tmp_path / "a", SLIDER, rests="[0, 40]")
    assert report["ok"], report["problems"]
    assert report["motions"][0]["rests"] == [
        {"at": 0, "ok": True, "rides_to_next": True},
        {"at": 40, "ok": True},
    ]
    # A rest short of the ridge: nothing holds the slider between 0 and 10 mm.
    (problem,) = _report(tmp_path / "b", SLIDER, rests="[0, 10, 40]")["problems"]["G4"]
    assert problem.startswith("motion slide: between its rests 0 mm and 10 mm, its flex rides")
    # A rest on the ridge: the catch is still bent there.
    (problem,) = _report(tmp_path / "c", SLIDER, rests="[0, 28, 40]")["problems"]["G4"]
    assert problem.startswith("motion slide: at its rest 28 mm, slider1 and base1 overlap")


@in_sandbox
def test_a_part_that_snaps_in_as_it_comes_in(tmp_path):
    # Slid on from the far end, the slider rides over the ridge: rigid, it does not go in.
    rigid = dict(with_flex=False, travel=20, entry="[-1, 0, 0]")
    (problem,) = _report(tmp_path / "a", SLIDER, **rigid)["problems"]["G4"]
    assert "does not go in moving along [-1, 0, 0]: it hits base1" in problem
    snaps = _report(tmp_path / "b", SLIDER, entry_flex=True, **rigid)
    assert snaps["ok"], snaps["problems"]
    (flex,) = snaps["assembly_steps"][1]["flex"]
    assert flex["ok"] and flex["depth_mm"] == pytest.approx(0.4, abs=0.01)
    (problem,) = _report(tmp_path / "c", SLIDER, entry_flex=True, flex_mm=0.3, **rigid)["problems"][
        "G4"
    ]
    assert problem.startswith("assembly_order, step 2: slider1 goes 0.4 mm deep into base1")
    # Set down from above, it meets no ridge: nothing snaps.
    (problem,) = _report(tmp_path / "d", SLIDER, with_flex=False, travel=20, entry_flex=True)[
        "problems"
    ]["G4"]
    assert problem.startswith("assembly_order, step 2: slider1 and base1 never overlap as it")


def test_how_deep_a_flex_goes():
    from cadverify.cadcheck.assembly import _flex_depth

    def triangles(solid):
        mesh = solid.to_mesh()
        return np.asarray(mesh.vert_properties)[:, :3][np.asarray(mesh.tri_verts)]

    block = manifold3d.Manifold.cube((40, 40, 40), True)
    for z, limit, expected in [
        (21.7, 0.5, (0.3, "measured")),  # a pin 0.3 mm into the block's top
        (21.7, 0.2, (0.3, "measured")),
        (0.0, 0.5, (1.0, "at least")),  # a pin buried in it, its faces 18 mm away
    ]:
        pin = manifold3d.Manifold.cube((4, 4, 4), True).translate((0, 0, z))
        hit = {"_solid": pin ^ block}
        depth, kind, _ = _flex_depth(hit, triangles(pin), triangles(block), limit)
        assert (depth, kind) == (pytest.approx(expected[0], abs=0.01), expected[1])
    # A plate as deep in the block as its flex, across a wide face: the farthest vertex from the
    # face it is under bounds it, where its center plus its radius cannot.
    for width, z, expected in [(30, 21.2, 0.8), (30, 21.3, 0.7), (4, 21.2, 0.8)]:
        plate = manifold3d.Manifold.cube((width, width, 4), True).translate((0, 0, z))
        hit = {"_solid": plate ^ block}
        depth, kind, _ = _flex_depth(hit, triangles(plate), triangles(block), 0.8)
        assert (depth, kind) == (pytest.approx(expected, abs=0.01), "measured")
    # Two pins, one deeper: each is measured near itself, the deeper one counts.
    pins = [
        manifold3d.Manifold.cube((4, 4, 4), True).translate((x, 0, z))
        for x, z in [(-10, 21.7), (10, 21.4)]
    ]
    both = manifold3d.Manifold.batch_boolean(pins, manifold3d.OpType.Add)
    hit = {"_solid": both ^ block}
    depth, kind, _ = _flex_depth(hit, triangles(both), triangles(block), 0.8)
    assert (depth, kind) == (pytest.approx(0.6, abs=0.01), "measured")


@in_sandbox
def test_an_assembly_printed_in_place(tmp_path):
    report = _report(tmp_path / "a", hole=8.8, in_place=0.3)
    assert report["problems"]["G5"] == [], report["problems"]
    printed = report["print_in_place"]
    assert printed["instances"] == ["base1", "pin1"]
    assert [g["gap_mm"] for g in printed["gaps"]] == [pytest.approx(0.39, abs=0.01)]
    (zone,) = printed["printability"]["zones"]  # the underside of the pin's head
    assert not zone["declared"] and zone["max_angle_deg"] == 90.0
    declared = _report(tmp_path / "b", hole=8.8, in_place=0.3, head_allowed=True)
    assert declared["print_in_place"]["printability"]["zones"][0]["declared_as"] == "pin head"
    (tight,) = _report(tmp_path / "c", in_place=0.3)["problems"]["G5"]
    assert "base1 and pin1 are 0.2 mm apart: printed in place they fuse" in tight
    # Turned 90° about its own axis, the pin prints the same: the pose is measured again.
    posed = _report(tmp_path / "d", hole=8.8, in_place=0.3, print_pose=True, head_allowed=True)
    assert posed["problems"]["G5"] == [], posed["problems"]
    assert posed["print_in_place"]["pose"] == [{"motion": "pin turn", "value": 90.0}]
    assert [g["gap_mm"] for g in posed["print_in_place"]["gaps"]] == [pytest.approx(0.39, abs=0.01)]
    assert Path(posed["print_in_place"]["stl"]).exists()


def test_a_box_prints_in_place_open_where_closed_its_lid_would_bridge(tmp_path):
    from cadverify.agent.gates import print_in_place_problems
    from cadverify.cadcheck.assembly import _pairs, _print_in_place

    # A tray 40 × 30 × 20 with 2 mm walls, and its lid 0.3 mm above it, hinged at the back on an
    # axis at half the closed height: turned 180°, the lid lies on the bed behind the tray.
    tray = manifold3d.Manifold.cube((40, 30, 20)) - manifold3d.Manifold.cube(
        (36, 26, 20)
    ).translate((2, 2, 2))
    lid = manifold3d.Manifold.cube((40, 30, 2)).translate((0, 0, 20.3))
    instances = [
        {"name": n, "part": n, "unit": 1, "_mesh": _mesh(s), "_solid": s}
        for n, s in (("tray", tray), ("lid", lid))
    ]
    hinge = {"name": "hinge", "instances": ["lid"], "kind": "rotate", "range": [0, 180]}
    hinge.update(point=[0, 30.15, 11.15], axis=[1, 0, 0])
    spec = {"print_in_place": {"min_gap_mm": 0.3}, "motions": [hinge], "overhangs_allowed": []}
    spec["print_pose"] = []

    def judged(spec, out):
        out.mkdir()
        g5: list[str] = []
        report = _print_in_place(instances, spec, _pairs(instances, {}, out, []), {}, out, g5)
        return report, print_in_place_problems({"print_in_place": report, "problems": {"G5": g5}})

    # Closed, the rim holds the edge of the lid's ceiling 0.3 mm under it, and the middle of the
    # ceiling is 13 mm from the rim: a bridge of 26 mm.
    closed, problems = judged(spec, tmp_path / "closed")
    (problem,) = problems
    assert problem.startswith("assembly as printed in place: undeclared 90.0° overhang")
    assert (
        "has a point 13.0 mm from any material under it: a bridge that reaches it spans " in problem
    )
    assert problem.endswith(
        "26.0 mm or more, and a bridge prints clean up to 10 mm: hold it from "
        "below, narrow it, or print it in another pose: declaring it is not enough"
    )
    open_, problems = judged(
        dict(spec, print_pose=[{"motion": "hinge", "value": 180}]), tmp_path / "o"
    )
    assert problems == [] and open_["pose"] == [{"motion": "hinge", "value": 180}]
    assert open_["gaps"] == [{"a": "tray", "b": "lid", "gap_mm": 0.3, "ok": True}]
    assert open_["printability"]["zones_total"] == 0
    assert open_["printability"]["size"] == [40.0, 60.3, 20.0]
    assert Path(open_["stl"]).exists()
