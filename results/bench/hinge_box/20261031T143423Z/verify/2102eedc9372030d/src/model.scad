// Box with print-in-place hinge (v3: global bore subtraction, hinge cutouts)
part = "box";
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

Rkn = 3.2; rbore = 2.2; rpin = 1.9;
yh = -30.5; zh = 30.8;
lid_zh = 3.4;
lid_lift = 27.4;
pin_lift_z = 27.8; pin_shift_y = -30.5;
k0x0=-30; k0x1=-18.32;
k1x0=-17.92; k1x1=-6.24;
k2x0=-5.84; k2x1=5.84;
k3x0=6.24; k3x1=17.92;
k4x0=18.32; k4x1=30;

$fn = 64;

module xcyl(x0, x1, r, y, z) {
    translate([x0, y, z]) rotate([0, 90, 0]) cylinder(r = r, h = x1 - x0);
}

module box_part() {
    difference() {
        union() {
            translate([-40, -30, 0]) cube([80, 60, 2.4]);
            translate([-40, 27.6, 2.4]) cube([80, 2.4, 27.6]);
            translate([-40, -30, 2.4]) cube([80, 2.4, 24.6]);
            translate([-40, -30, 27.0]) cube([11, 2.4, 3.0]);
            translate([29, -30, 27.0]) cube([11, 2.4, 3.0]);
            translate([-40, -27.6, 2.4]) cube([2.4, 55.2, 27.6]);
            translate([37.6, -27.6, 2.4]) cube([2.4, 55.2, 27.6]);
            translate([-3, 27.0, 27.5]) cube([6, 0.6, 1.5]);
            xcyl(k0x0, k0x1, Rkn, yh, zh);
            xcyl(k2x0, k2x1, Rkn, yh, zh);
            xcyl(k4x0, k4x1, Rkn, yh, zh);
            translate([k0x0, -31, 27.6]) cube([k0x1-k0x0, 3.4, 3.2]);
            translate([k2x0, -31, 27.6]) cube([k2x1-k2x0, 3.4, 3.2]);
            translate([k4x0, -31, 27.6]) cube([k4x1-k4x0, 3.4, 3.2]);
        }
        xcyl(k0x0-0.06, k0x1+0.06, rbore, yh, zh);
        xcyl(k2x0-0.06, k2x1+0.06, rbore, yh, zh);
        xcyl(k4x0-0.06, k4x1+0.06, rbore, yh, zh);
    }
}

module lid_part() {
    difference() {
        union() {
            translate([-40, -30, 10.6]) cube([80, 60, 2.4]);
            translate([-40, 27.6, 3]) cube([80, 2.4, 7.6]);
            translate([k1x0, -30, 3]) cube([k1x1-k1x0, 2.4, 7.6]);
            translate([k3x0, -30, 3]) cube([k3x1-k3x0, 2.4, 7.6]);
            translate([-40, -30, 3]) cube([10, 2.4, 7.6]);
            translate([30, -30, 3]) cube([10, 2.4, 7.6]);
            translate([-40, -27.6, 3]) cube([2.4, 55.2, 7.6]);
            translate([37.6, -27.6, 3]) cube([2.4, 55.2, 7.6]);
            translate([-37.2, 25.2, 0]) cube([74.4, 2.0, 10.6]);
            translate([-37.2, -27.2, 0]) cube([74.4, 2.0, 10.6]);
            translate([-37.2, -25.2, 0]) cube([2.0, 50.4, 10.6]);
            translate([35.2, -25.2, 0]) cube([2.0, 50.4, 10.6]);
            xcyl(k1x0, k1x1, Rkn, yh, lid_zh);
            xcyl(k3x0, k3x1, Rkn, yh, lid_zh);
            translate([k1x0, -31, 0]) cube([k1x1-k1x0, 3.4, 5]);
            translate([k3x0, -31, 0]) cube([k3x1-k3x0, 3.4, 5]);
        }
        xcyl(k1x0-0.06, k1x1+0.06, rbore, yh, lid_zh);
        xcyl(k3x0-0.06, k3x1+0.06, rbore, yh, lid_zh);
        translate([-3.3, 26.3, -0.05]) cube([6.6, 1.5, 2.05]);
    }
}

module pin_part() {
    union() {
        xcyl(-32.4, 32.4, rpin, 0, 3);
        xcyl(30.4, 32.4, 3, 0, 3);
        xcyl(-32.4, -30.4, 3, 0, 3);
    }
}

if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.7, 0], [40, 30, 34.0]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [["hinge knuckles, bores and wall cutouts print in place", [[-30.2, -33.9, 26.5], [30.2, -27.1, 33.5]]]]],
        ["copies", 1],
        ["details", [
            ["floor", "thickness", [0, 0, -1], [0, 0, 1], 2.4],
            ["front_wall", "thickness", [0, 31, 15], [0, -1, 0], 2.4],
            ["cavity", "void", [[-37.6, -27.6, 2.4], [37.6, 27.6, 29.9]], 0.9],
            ["hinge_bore", "hole", [-31, -30.5, 30.8], [1, 0, 0], [[0, 4.4], [11.6, 4.4]]],
            ["catch_bump", "material", [[-3, 27.0, 27.5], [3, 27.6, 29.0]], 0.9],
            ["hinge_view", "view", [[-30, -34, 26.5], [30, -27, 34.5]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.7, 0], [40, 30, 13]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 300]]],
        ["overhangs_allowed", [
            ["hinge knuckles and bores print in place", [[-18.2, -33.9, 0], [18.2, -27.1, 4.2]]],
            ["skirt cutout top bridges", [[-30.2, -30.2, 6.5], [30.2, -27.4, 7.5]]],
            ["lid top bridging over plug cavity", [[-37.2, -24.9, 10.1], [37.2, 25.2, 11.1]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 0, 14], [0, 0, -1], 2.4],
            ["skirt", "thickness", [0, 31, 6], [0, -1, 0], 2.4],
            ["plug_cavity", "void", [[-35.2, -24.9, 0], [35.2, 25.2, 10.5]], 0.9],
            ["hinge_bore", "hole", [-18.6, -30.5, 3.4], [1, 0, 0], [[0, 4.4], [11.6, 4.4]]],
            ["catch_notch", "void", [[-3.3, 26.3, 0], [3.3, 27.8, 2.0]], 0.9],
            ["catch_view", "view", [[-5, 26, 0], [5, 28.5, 3]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-32.4, -3, 0], [32.4, 3, 6]]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [["pin shaft underside bridges with 0.3 gap", [[-32.4, -1.9, 0], [32.4, 1.9, 1.6]]]]],
        ["copies", 1],
        ["details", [
            ["shaft", "thickness", [0, 3, 3], [0, -1, 0], 3.8],
            ["head", "material", [[30.4, -3, 0], [32.4, 3, 6]], 0.7],
            ["pin_view", "view", [[-32.4, -3, 0], [32.4, 3, 6]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.7, 0], [40, 30, 40.4]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid"], "rotate", [0, -30.5, 30.8], [1, 0, 0], [0, 110], ["flex", [["lid", "box", 0.5, "catch bump clearance pass"]]]]
        ]],
        ["assembly_order", [
            [["box"], [0, 0, 0]],
            [["lid"], [0, 0, -1]],
            [["pin"], [1, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge undersides, pin bridge and cutouts in place", [[-33, -34, 26.5], [33, -27, 34.8]]],
            ["lid top bridging over box cavity", [[-37.2, -24.9, 37.5], [37.2, 25.2, 38.5]]]
        ]]
    ]);
    instance("box", "box") box_part();
    instance("lid", "lid") translate([0, 0, lid_lift]) lid_part();
    instance("pin", "pin") translate([0, pin_shift_y, pin_lift_z]) pin_part();
}
