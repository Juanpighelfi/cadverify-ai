/* Wall-mounted spool holder on 608 bearing
   Print orientation: +Z up, parts rest on min z.
   Assembly: wall at y=0 (normal -y), arm along +y, up +z.
*/

part = "assembly"; // [bracket, hub, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
plate_x = 80;
plate_y = 60;
plate_t = 8;
hole_dx = 25;
screw_d = 4.5;
csk_d = 9;
csk_h = (csk_d - screw_d)/2; // 2.25, 90 deg cone
post_h = 75;
post_d1 = 30;
post_d2 = 20;
axle_d = 7.9;
axle_h = 9;
axle_cham_h = 1;
axle_cham_d2 = 5.9;
shoulder_z = plate_t + post_h; // 83
tip_z = shoulder_z + axle_h + axle_cham_h; // 93

flange_d = 72;
flange_t = 4;
barrel_d = 52.8;
barrel_h = 18; // z4-22
lead_h = 2;
lead_d2 = 48.8;
hub_top = flange_t + barrel_h + lead_h; // 24
pocket_d = 21.7;
pocket_bottom = 16.5;
pocket_cham_h = 1;
pocket_cham_d = 23.7;
bore_d = 9;

// ---------- bracket (print orientation) ----------
module rib_plus_y() {
    hull() {
        translate([-3, -1, 7]) cube([6, 2, 2]);
        translate([-3, 22, 7]) cube([6, 2, 2]);
        translate([-3, -1, 43]) cube([6, 2, 2]);
    }
}

module bracket() {
    difference() {
        union() {
            translate([-plate_x/2, -plate_y/2, 0]) cube([plate_x, plate_y, plate_t]);
            translate([0, 0, plate_t]) cylinder(h = post_h, d1 = post_d1, d2 = post_d2, $fn = 96);
            for (a = [0, 90, 180, 270]) rotate([0, 0, a]) rib_plus_y();
            translate([0, 0, shoulder_z]) cylinder(h = axle_h, d = axle_d, $fn = 64);
            translate([0, 0, shoulder_z + axle_h]) cylinder(h = axle_cham_h, d1 = axle_d, d2 = axle_cham_d2, $fn = 64);
        }
        for (sx = [-hole_dx, hole_dx]) {
            translate([sx, 0, -0.1]) cylinder(h = plate_t + 0.2, d = screw_d, $fn = 32);
            translate([sx, 0, plate_t - csk_h]) cylinder(h = csk_h + 0.01, d1 = screw_d, d2 = csk_d, $fn = 32);
        }
    }
}

// ---------- hub (print orientation) ----------
module hub() {
    difference() {
        union() {
            cylinder(h = flange_t, d = flange_d, $fn = 128);
            translate([0, 0, flange_t]) cylinder(h = barrel_h, d = barrel_d, $fn = 128);
            translate([0, 0, flange_t + barrel_h]) cylinder(h = lead_h, d1 = barrel_d, d2 = lead_d2, $fn = 128);
        }
        // bearing pocket mouth chamfer (top, opening up)
        translate([0, 0, hub_top - pocket_cham_h]) cylinder(h = pocket_cham_h + 0.01, d1 = pocket_d, d2 = pocket_cham_d, $fn = 64);
        // bearing pocket
        translate([0, 0, pocket_bottom]) cylinder(h = (hub_top - pocket_cham_h) - pocket_bottom + 0.01, d = pocket_d, $fn = 64);
        // axle clearance bore through
        translate([0, 0, -0.1]) cylinder(h = pocket_bottom + 0.2, d = bore_d, $fn = 48);
    }
}

// ---------- 608 bearing visual (external) ----------
module bearing_608() {
    difference() {
        cylinder(h = 7, d = 22, center = true, $fn = 96);
        cylinder(h = 7.4, d = 8, center = true, $fn = 48);
    }
}

// ---------- assembly ----------
module assembly_model() {
    // bracket: print (x,y,z) -> assembly (x, z, -y)  (rotate -90 about X)
    instance("bracket", "bracket") rotate([-90, 0, 0]) bracket();
    // bearing: axis Y, y 84..91, center 87.5
    instance("bearing", "external") translate([0, 87.5, 0]) rotate([-90, 0, 0]) bearing_608();
    // hub: print +Z -> assembly -Y, opening faces wall; top (24) at y=83.5, flange outer at 107.5
    instance("hub", "hub") translate([0, 107.5, 0]) rotate([90, 0, 0]) hub();
}

if (part == "bracket") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -30, 0], [40, 30, 93]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["wall", "-z", 4000]]],
        ["overhangs_allowed", [
            ["countersunk screw cones", [[-29.6, -4.6, 5.5], [-20.4, 4.6, 8.2]]],
            ["countersunk screw cones", [[20.4, -4.6, 5.5], [29.6, 4.6, 8.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["rib", "material", [[-3, 0, 8], [3, 12, 30]], 0.8],
            ["screw_hole_left", "hole", [-25, 0, 10], [0, 0, -1], [[0, 9], [2.25, 4.5], [7, 4.5]]],
            ["screw_hole_right", "hole", [25, 0, 10], [0, 0, -1], [[0, 9], [2.25, 4.5], [7, 4.5]]],
            ["plate", "thickness", [20, 20, -1], [0, 0, 1], 8]
        ]]
    ]);
    bracket();
} else if (part == "hub") {
    echo(cadverify_spec = [
        ["bounds", [[-36, -36, 0], [36, 36, 24]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["barrel", "material", [[15, 0, 5], [22, 6, 15]], 0.9],
            ["bearing_pocket", "hole", [0, 0, 26], [0, 0, -1], [[0, 23.7], [1, 21.7], [6.5, 21.7], [7.6, 9], [20, 9]]],
            ["flange", "thickness", [30, 0, -1], [0, 0, 1], 4],
            ["barrel_wall", "thickness", [30, 0, 20], [-1, 0, 0], 15.5]
        ]]
    ]);
    hub();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, 0, -36], [40, 107.5, 36]]],
        ["support_faces", [["wall", "-y", 4000]]],
        ["allowed_interferences", [["hub", "bearing", "press fit 0.3mm diametral"]]],
        ["motions", [
            ["spin", ["hub", "bearing"], "rotate", [0, 87.5, 0], [0, 1, 0], [0, 360]]
        ]],
        ["assembly_order", [
            [["bracket"], [0, 0, 0]],
            [["bearing"], [0, -1, 0]],
            [["hub"], [0, -1, 0]]
        ]]
    ]);
    assembly_model();
}
