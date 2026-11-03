// Wall-mounted spool holder on a 608 bearing (8 mm bore, 22 mm OD, 7 mm wide).
// - bracket: wall plate with two countersunk 4 mm wood-screw holes, 75 mm arm,
//   twin anti-sag gussets, 8 mm axle. Prints plate-down, arm up, no supports.
// - hub: 52.6 mm barrel for the 53 mm spool hole, 21.8 mm press seat for the
//   608 bearing, 8.6 mm axle clearance bore. Prints flange-down, no supports.
// Assembly: bracket screwed to wall (wall plane y=0), hub + bearing on axle.

use <cadverify_parts.scad>

// [bracket:Bracket, hub:Hub, assembly:Assembly]
part = "bracket";

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
plate_w = 60; plate_h = 50; plate_t = 8;   // wall plate
hole_d = 4.2; hole_y = 17; csk_d = 8.5;    // 4 mm wood screws, 90 deg csk
arm_w = 14; arm_d = 24; arm_l = 75;        // arm, 75 long from plate face
axle_d = 7.9; axle_l = 20; axle_tip = 2;   // axle (slip fit in 8 mm bore)
fin_t = 5;                                 // gusset thickness
hub_flange_d = 70; hub_flange_t = 6;
hub_barrel_d = 52.6; hub_barrel_l = 30;    // slip fit in 53 mm spool hole
seat_d = 21.8; seat_h = 7.4;               // press seat for 22 mm bearing OD
bore_d = 8.6;                              // axle clearance bore

hub_h = hub_flange_t + hub_barrel_l;       // 36
seat_floor = hub_h - seat_h;               // 28.6
arm_top = plate_t + arm_l;                 // 83
axle_top = arm_top + axle_l + axle_tip;    // 105

module bracket() {
    difference() {
        union() {
            translate([-plate_w/2, -plate_h/2, 0]) cube([plate_w, plate_h, plate_t]);
            translate([-arm_w/2, -arm_d/2, plate_t]) cube([arm_w, arm_d, arm_l]);
            for (fx = [arm_w/2 - 0.5, -arm_w/2 - fin_t + 0.5])
                hull() {
                    translate([fx, -22, plate_t]) cube([fin_t, 42, 2]);
                    translate([fx, -2, 48]) cube([fin_t, 4, 4]);
                }
            translate([0, 0, arm_top]) cylinder(d = axle_d, h = axle_l, $fn = 64);
            translate([0, 0, arm_top + axle_l]) cylinder(d1 = axle_d, d2 = 6, h = axle_tip, $fn = 64);
        }
        for (sy = [-hole_y, hole_y]) {
            translate([0, sy, -0.5]) cylinder(d = hole_d, h = plate_t + 0.5, $fn = 32);
            translate([0, sy, plate_t - (csk_d - hole_d)/2])
                cylinder(d1 = hole_d, d2 = csk_d, h = (csk_d - hole_d)/2 + 0.01, $fn = 48);
        }
    }
}

module hub() {
    difference() {
        union() {
            cylinder(d = hub_flange_d, h = hub_flange_t, $fn = 128);
            translate([0, 0, hub_flange_t]) cylinder(d = hub_barrel_d, h = hub_barrel_l - 2, $fn = 128);
            // spool lead-in chamfer, 2 mm x 45 deg, built into the profile
            translate([0, 0, hub_h - 2])
                cylinder(d1 = hub_barrel_d, d2 = hub_barrel_d - 4, h = 2, $fn = 128);
        }
        // bearing press seat (mouth on back face)
        translate([0, 0, seat_floor]) cylinder(d = seat_d, h = seat_h + 0.01, $fn = 96);
        // axle clearance bore through to the front face
        translate([0, 0, -0.5]) cylinder(d = bore_d, h = seat_floor + 0.5, $fn = 48);
    }
}

if (part == "bracket") {
    echo(cadverify_spec = [
        ["bounds", [[-plate_w/2, -plate_h/2, 0], [plate_w/2, plate_h/2, axle_top]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 2000]]],
        ["copies", 1],
        ["details", [
            ["plate", "material", [[-plate_w/2, -plate_h/2, 0], [plate_w/2, plate_h/2, plate_t]], 0.9],
            ["arm", "material", [[-arm_w/2, -arm_d/2, plate_t], [arm_w/2, arm_d/2, arm_top]], 0.95],
            ["gusset_left", "material", [[-arm_w/2 - fin_t + 0.5, -22, plate_t], [-arm_w/2 + 0.5, 20, 52]], 0.45],
            ["gusset_right", "material", [[arm_w/2 - 0.5, -22, plate_t], [arm_w/2 - 0.5 + fin_t, 20, 52]], 0.45],
            ["axle", "material", [[-4, -4, arm_top], [4, 4, axle_top]], 0.6],
            ["screw_hole_front", "hole", [0, hole_y, 10], [0, 0, -1], [[0, 8.5], [2.2, 4.2], [8, 4.2]]],
            ["screw_hole_back", "hole", [0, -hole_y, 10], [0, 0, -1], [[0, 8.5], [2.2, 4.2], [8, 4.2]]],
            ["plate_thickness", "thickness", [20, 0, -1], [0, 0, 1], 8]
        ]]
    ]);
    bracket();
} else if (part == "hub") {
    echo(cadverify_spec = [
        ["bounds", [[-hub_flange_d/2, -hub_flange_d/2, 0], [hub_flange_d/2, hub_flange_d/2, hub_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 3000]]],
        ["copies", 1],
        ["details", [
            ["flange", "material", [[-hub_flange_d/2, -hub_flange_d/2, 0], [hub_flange_d/2, hub_flange_d/2, hub_flange_t]], 0.7],
            ["barrel", "material", [[-hub_barrel_d/2, -hub_barrel_d/2, hub_flange_t], [hub_barrel_d/2, hub_barrel_d/2, hub_h]], 0.6],
            ["bearing_seat", "void", [[-seat_d/2, -seat_d/2, seat_floor], [seat_d/2, seat_d/2, hub_h]], 0.7],
            ["axle_bore", "hole", [0, 0, -1], [0, 0, 1], [[0, 8.6], [27, 8.6], [30, 21.8]]],
            ["barrel_wall", "thickness", [30, 0, 20], [-1, 0, 0], 22],
            ["spool_fit", "view", [[24, -5, 10], [28, 5, 30]]]
        ]]
    ]);
    hub();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-hub_flange_d/2, 0, -hub_flange_d/2], [hub_flange_d/2, 119, hub_flange_d/2]]],
        ["support_faces", [["wall", "-y", 2500]]],
        ["allowed_interferences", [["hub", "bearing", "press fit bearing OD 22 in 21.8 seat"]]],
        ["motions", [
            ["hub_spin", ["hub", "bearing"], "rotate", [0, 90, 0], [0, 1, 0], [0, 360]]
        ]],
        ["assembly_order", [
            [["bracket"], [0, 0, 0]],
            [["bearing"], [0, -1, 0]],
            [["hub"], [0, -1, 0]]
        ]]
    ]);
    instance("bracket", "bracket") rotate([-90, 0, 0]) bracket();
    instance("bearing", "standard:bearing_608") translate([0, 90.2, 0]) rotate([90, 0, 0]) bearing_608();
    instance("hub", "hub") translate([0, 119, 0]) rotate([90, 0, 0]) hub();
}
