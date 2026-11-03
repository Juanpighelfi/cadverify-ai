use <cadverify_parts.scad>

// Knob for 6 mm D-shaft (4.5 across flat), M3 set screw in captive nut.
// Print orientation: base (shaft side) on bed at z=0, pointer on top at z=18.

part = "knob"; // [knob, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* Parameters (mm) */
knob_d_body = 28;      // body diameter
knob_h = 18;           // total height
top_cham_h = 2.0;      // top chamfer height
top_d = 25;            // top face diameter (chamfer ~37 deg from vertical)
rib_n = 30;
rib_w = 1.5;
rib_r_in = 13.0;
rib_r_out = 15.0;
bore_d = 6.2;          // D bore diameter (6.0 shaft + 0.2)
bore_flat_y = 1.6;     // flat plane: opposite wall -3.1, flat-to-wall 4.7 (shaft 4.5 + 0.2)
bore_depth = 15;       // blind, from base
screw_z = 9;           // screw axis height
screw_d = 3.0;
pocket_af = 5.8;       // hex across flats (nut 5.5 + 0.3 slide)
pocket_y0 = 11.6;      // pocket bottom (nut inner face seat)
pocket_y1 = 16.0;      // past outer surface, open entry from side
pointer_x0 = 1.0;
pointer_x1 = 11.0;
pointer_w = 1.5;
pointer_depth = 1.0;

module knob_part() {
    difference() {
        union() {
            cylinder(d = knob_d_body, h = knob_h - top_cham_h, $fn = 128);
            translate([0, 0, knob_h - top_cham_h])
                cylinder(d1 = knob_d_body, d2 = top_d, h = top_cham_h, $fn = 128);
            // knurl ribs, straight vertical (nut pocket cuts the entry through them)
            for (i = [0 : rib_n - 1])
                rotate([0, 0, i * 360 / rib_n])
                    translate([(rib_r_in + rib_r_out) / 2, 0, (knob_h - top_cham_h) / 2])
                        cube([rib_r_out - rib_r_in, rib_w, knob_h - top_cham_h], center = true);
        }
        // pointer groove on top, along +X
        translate([pointer_x0, -pointer_w / 2, knob_h - pointer_depth])
            cube([pointer_x1 - pointer_x0, pointer_w, pointer_depth + 1]);
        // D bore, blind from base
        intersection() {
            translate([0, 0, -1]) cylinder(d = bore_d, h = bore_depth + 1, $fn = 64);
            translate([-10, -10, -1]) cube([20, bore_flat_y + 10, bore_depth + 1]);
        }
        // hex nut pocket, axis Y, flat on top
        translate([0, (pocket_y0 + pocket_y1) / 2, screw_z])
            rotate([90, 0, 0])
                cylinder(d = pocket_af / cos(30), h = pocket_y1 - pocket_y0, $fn = 6, center = true);
        // 3 mm screw hole, pocket bottom to bore
        translate([0, 5.9, screw_z])
            rotate([90, 0, 0])
                cylinder(d = screw_d, h = 11.8, $fn = 32, center = true);
    }
}

// external D shaft: 6 mm dia, flat faces +Y at y=1.5, z from -10 to 14.8
module shaft_ext() {
    intersection() {
        cylinder(d = 6.0, h = 24.8, $fn = 48);
        translate([-10, -10, 0]) cube([20, 1.5 + 10, 24.8]);
    }
}

if (part == "knob") {
    echo(cadverify_spec = [
        ["bounds", [[-15, -15, 0], [15, 15, 18]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 400]]],
        ["overhangs_allowed", [
            ["d_bore_ceiling", [[-4, -4, 13.5], [4, 4, 15.5]]],
            ["nut_pocket_ceiling", [[-3.5, 11.0, 6.0], [3.5, 16.5, 12.5]]],
            ["screw_hole_top", [[-2, -0.5, 7.0], [2, 12.0, 11.0]]]
        ]],
        ["copies", 1],
        ["details", [
            ["knurl_rib", "material", [[13.0, -0.75, 4], [15.0, 0.75, 12]], 0.8],
            ["pointer_groove", "void", [[1.0, -0.75, 17.0], [11.0, 0.75, 18.01]], 0.9],
            ["nut_pocket", "void", [[-1.5, 12.0, 7.5], [1.5, 14.0, 10.5]], 0.9],
            ["d_bore", "void", [[-2.0, -2.0, 1.0], [2.0, 1.0, 14.0]], 0.9],
            ["screw_hole", "hole", [0, 20, 9], [0, -1, 0], [[0, 6.1], [3, 3.0], [8, 3.0]]],
            ["top_floor", "thickness", [0, 0, 20], [0, 0, -1], 3.0],
            ["pointer_view", "view", [[1.0, -1.5, 16.8], [11.0, 1.5, 18.2]]]
        ]]
    ]);
    knob_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-15, -15, -10], [15, 15, 18]]],
        ["assembly_order", [
            [["knob"], [0, 0, 0]],
            [["nut"], [0, -1, 0]],
            [["shaft"], [0, 0, 1]]
        ]]
    ]);
    instance("knob", "knob") knob_part();
    instance("nut", "standard:m3_nut") translate([0, 14.0, 9]) rotate([90, 0, 0]) m3_nut();
    instance("shaft", "external") translate([0, 0, -10]) shaft_ext();
}
