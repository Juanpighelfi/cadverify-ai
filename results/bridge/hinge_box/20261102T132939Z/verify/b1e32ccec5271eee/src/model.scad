// Print-in-place hinged box, Bambu Lab A1 / PLA, 0.4 mm nozzle.
// Closed (assembly) size: 80 (X) x 60 (Y incl. hinge) x 40 (Z) mm.
// Box body is 30 mm high, lid is the top 10 mm.
// Hinge axis is offset below the lid top (axis_z = 20 = lid_top/2), so that
// with the lid swung 180 deg the lid plate lies flat on the bed behind the
// box: that is the print-in-place print pose (print_pose hinge_open = 180).
// Radial pin/bore clearance 0.5 mm, axial knuckle clearance 0.6 mm.

part = "assembly"; // [assembly, box, lid, pin]

$fn = 64;

W = 80;          // overall width
Dbody = 53;      // box/lid body depth (hinge knuckles extend this to 60)
Hbox = 30;       // box height, also lid seat plane
Hlid = 10;       // lid height
Htot = Hbox + Hlid; // 40
wall = 3;
axis_y = 56;     // hinge axis, behind body back face (53)
axis_z = 20;     // hinge axis height (= Htot/2, see header)
r_out = 4.0;     // knuckle outer radius
r_bore = 2.7;    // knuckle bore radius
r_pin = 2.1;     // pin radius (0.5 radial clearance)

// knuckle segments along X [x0, x1], 0.6 mm axial gaps
box_segs = [[8.8, 20.8], [34.0, 46.0], [59.2, 71.2]];
lid_segs = [[21.4, 33.4], [46.6, 58.6]];
pin_x0 = 11.0;   // pin spans 11..69 (0.6 clear of the end caps)
pin_len = 58;

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// 180 deg flip about the hinge axis (its own inverse): closed <-> print pose
module hinge_flip() {
    translate([0, axis_y, axis_z]) rotate([180, 0, 0])
        translate([0, -axis_y, -axis_z]) children();
}

module tube_x(x0, len, r) {
    translate([x0, axis_y, axis_z]) rotate([0, 90, 0]) cylinder(h = len, r = r);
}

// ---------------------------------------------------------------- box (print = assembly pose)
module box_part() {
    union() {
        // floor and shell
        cube([W, Dbody, 3]);                                   // floor
        translate([0, 0, 0]) cube([W, wall, Hbox]);            // front wall
        translate([0, 0, 0]) cube([wall, Dbody, Hbox]);        // left wall
        translate([W - wall, 0, 0]) cube([wall, Dbody, Hbox]); // right wall
        // back wall: low strip full width + upper parts only at box knuckles
        translate([0, Dbody - wall, 0]) cube([W, wall, 15]);
        for (s = [[0, 21.1], [33.7, 46.3], [58.9, 80]])
            translate([s[0], Dbody - wall, 14]) cube([s[1] - s[0], wall, Hbox - 15]);
        // hinge knuckles (box segments), arms and end caps
        for (i = [0 : len(box_segs) - 1]) {
            s = box_segs[i];
            difference() {
                tube_x(s[0], s[1] - s[0], r_out);
                tube_x(s[0] - 0.2, s[1] - s[0] + 0.4, r_bore);
            }
            // arm lug behind the back wall, bored through for the pin
            difference() {
                translate([(s[0] + s[1]) / 2 - 3.5, Dbody, axis_z - 3]) cube([7, 5.5, 6]);
                tube_x((s[0] + s[1]) / 2 - 3.8, 7.6, r_bore);
            }
            if (i == 0) tube_x(s[0], 1.6, r_out);              // left end cap
            if (i == len(box_segs) - 1) tube_x(s[1] - 1.6, 1.6, r_out); // right end cap
        }
        // front catch bump on the inside face of the front wall
        translate([34, wall, 27.7]) cube([12, 0.8, 1.6]);
    }
}

// ---------------------------------------------------------------- lid, in closed coordinates
module lid_closed() {
    union() {
        // cap: roof + perimeter skirt down to the seat plane (flush outside)
        translate([0, 0, Htot - 3]) cube([W, Dbody, 3]);       // roof
        translate([0, 0, Hbox]) cube([W, wall, Hlid]);         // front skirt
        translate([0, 0, Hbox]) cube([wall, Dbody, Hlid]);     // left skirt
        translate([W - wall, 0, Hbox]) cube([wall, Dbody, Hlid]); // right skirt
        translate([0, Dbody - wall, Hbox]) cube([W, wall, Hlid]); // back skirt
        // front catch tab, hanging inside the front wall, with snap groove
        difference() {
            translate([32, 3.4, 26]) cube([16, 2.8, 11]);
            translate([34, 3.4, 27.2]) cube([12, 0.9, 2.6]);   // groove
        }
        // hinge knuckles (lid segments) and their arms to the back skirt
        for (s = lid_segs) {
            difference() {
                tube_x(s[0], s[1] - s[0], r_out);
                tube_x(s[0] - 0.2, s[1] - s[0] + 0.4, r_bore);
            }
            difference() {
                hull() {
                    translate([(s[0] + s[1]) / 2 - 3.5, Dbody - wall, 31]) cube([7, 3.5, 6]);
                    tube_x((s[0] + s[1]) / 2 - 3.5, 7, r_out);
                }
                tube_x((s[0] + s[1]) / 2 - 3.8, 7.6, r_bore);
            }
        }
    }
}

// lid as printed: flipped 180 deg about the hinge axis, plate flat on the bed
module lid_part() { hinge_flip() lid_closed(); }

// ---------------------------------------------------------------- pin (print-local: lying on bed)
module pin_part() {
    translate([0, r_pin, r_pin]) rotate([0, 90, 0]) cylinder(h = pin_len, r = r_pin);
}

// ---------------------------------------------------------------- selector / assembly
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [W, 60, Hbox]]],
        ["bodies", 1],
        ["copies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge knuckles and arms, horizontal cylinders", [[8, 52, 16], [72, 60, 24]]],
            ["front catch bump underside, 0.8 mm ledge", [[34, 3, 27.2], [46, 3.9, 29.8]]]
        ]],
        ["details", [
            ["floor", "material", [[1, 1, 0.2], [79, 52, 2.8]], 1.0],
            ["cavity", "void", [[10, 10, 10], [70, 40, 29]], 1.0],
            ["catch_bump", "material", [[36, 3.1, 28.1], [44, 3.7, 29.1]], 1.0],
            ["back_notch", "void", [[23, 50.2, 15.5], [31, 52.8, 29]], 1.0],
            ["hinge_arm", "material", [[12, 53.3, 22.0], [18, 54.0, 22.8]], 1.0],
            ["front_wall", "thickness", [20, -2, 15], [0, 1, 0], 3],
            ["floor_thickness", "thickness", [20, 25, -2], [0, 0, 1], 3]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, 52, 0], [W, 112, 24]]],
        ["bodies", 1],
        ["copies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge knuckles and arms, horizontal cylinders", [[21, 52, 3], [59, 62, 24]]],
            ["catch groove ceiling, 0.9 mm deep groove", [[34, 107.5, 10], [46, 108.7, 13]]]
        ]],
        ["details", [
            ["tray_bottom", "material", [[1, 60, 0.2], [79, 111, 2.8]], 1.0],
            ["tray_cavity", "void", [[10, 70, 5], [70, 100, 9]], 1.0],
            ["catch_tab", "material", [[33, 106.2, 4], [47, 108.4, 9]], 1.0],
            ["catch_groove", "void", [[35, 107.8, 10.5], [45, 108.5, 12.5]], 1.0],
            ["hinge_bore", "void", [[22, 55, 19], [23.5, 57, 21]], 1.0],
            ["hinge_arm_block", "material", [[25, 59, 4], [30, 61, 8]], 1.0],
            ["roof_thickness", "thickness", [20, 80, -2], [0, 0, 1], 3],
            ["hinge_arm", "view", [[23, 52, 3], [31, 62, 24]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [pin_len, 4.2, 4.2]]],
        ["bodies", 1],
        ["copies", 1],
        ["overhangs_allowed", [
            ["pin underside, horizontal printed cylinder", [[0, 0.6, 0], [58, 3.6, 0.8]]]
        ]],
        ["details", [
            ["pin_shaft", "material", [[5, 1, 1], [50, 3.2, 3.2]], 1.0],
            ["pin_diameter", "thickness", [10, 2.1, -2], [0, 0, 1], 4.2]
        ]]
    ]);
    pin_part();
} else { // assembly, closed, plus print-in-place data
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [W, 60, Htot]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["motions", [
            ["hinge_open", ["lid"], "rotate", [0, axis_y, axis_z], [-1, 0, 0], [0, 180],
                ["flex", [["lid", "box", 0.8, "front catch tab snaps over the wall bump near closed"]]]]
        ]],
        ["assembly_order", [
            [["box", "lid", "pin"], [0, 0, 0]]
        ]],
        ["print_in_place", 0.5],
        ["print_pose", [["hinge_open", 180]]],
        ["overhangs_allowed", [
            ["hinge knuckles arms and pin in print pose", [[8, 52, 3], [72, 62, 24]]],
            ["front catch bump underside", [[34, 3, 27.2], [46, 3.9, 29.8]]],
            ["catch groove ceiling in print pose", [[34, 107.5, 10], [46, 108.7, 13]]]
        ]]
    ]);
    instance("box", "box") box_part();
    instance("lid", "lid") hinge_flip() lid_part();
    instance("pin", "pin") translate([pin_x0, axis_y - r_pin, axis_z - r_pin]) pin_part();
}
