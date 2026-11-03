use <cadverify_parts.scad>

// Knob for 6mm D-shaft with M3 nut set screw
// Print orientation: base (shaft side) on bed at z=0, top with pointer at z=18.

part = "knob"; // [knob, assembly]
cadverify_only = "";

/* Parameters */
knob_d_body = 28;        // main body diameter
knob_d_max = 30;         // across ribs
knob_h = 18;             // total height
rib_n = 30;
rib_w = 1.5;
rib_r_in = 13.0;
rib_r_out = 15.0;
top_cham_h = 2.0;
top_d = 24;              // top face diameter
bore_d = 6.2;            // D bore diameter (shaft 6.0 + clearance)
bore_flat_y = 1.6;       // flat plane y (opposite wall at -3.1, flat-to-wall 4.7)
bore_depth = 15;         // from base z=0 up
screw_z = 9;             // set screw axis height
screw_d = 3.0;
pocket_af = 5.8;         // hex across flats (nut 5.5 + clearance)
pocket_y0 = 11.6;        // pocket bottom (inner)
pocket_y1 = 16.0;        // pocket extends past surface
nut_y0 = 11.6;           // nut inner face sits on pocket bottom
nut_y1 = 14.0;           // nut outer face (flush with body r=14)
pointer_x0 = 1.0;
pointer_x1 = 11.0;
pointer_w = 1.5;
pointer_depth = 1.0;

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module knob_body() {
    difference() {
        union() {
            // main body
            cylinder(d = knob_d_body, h = knob_h - top_cham_h, $fn = 128);
            // top chamfer 45deg: 28 -> 24 over 2mm
            translate([0, 0, knob_h - top_cham_h])
                cylinder(d1 = knob_d_body, d2 = top_d, h = top_cham_h, $fn = 128);
            // knurl ribs (straight, vertical, no overhang)
            for (i = [0 : rib_n - 1])
                rotate([0, 0, i * 360 / rib_n])
                    translate([(rib_r_in + rib_r_out) / 2, 0, (knob_h - top_cham_h) / 2])
                        cube([rib_r_out - rib_r_in, rib_w, knob_h - top_cham_h], center = true);
        }
        // pointer groove on top, along +X
        translate([(pointer_x0 + pointer_x1) / 2, 0, knob_h - pointer_depth])
            cube([pointer_x1 - pointer_x0, pointer_w, pointer_depth + 1], center = false);
        // D bore from base, 15 deep
        translate([0, 0, -1])
            intersection() {
                cylinder(d = bore_d, h = bore_depth + 1, $fn = 64);
                // keep y <= bore_flat_y
                translate([0, (bore_flat_y - 20) / 2 - 0 + 0, 0])
                    cube([20, 20, bore_depth + 1], center = false);
            }
        // hex nut pocket, axis Y, flat on top
        translate([0, (pocket_y0 + pocket_y1) / 2, screw_z])
            rotate([90, 0, 0])
                cylinder(d = pocket_af / cos(30), h = pocket_y1 - pocket_y0, $fn = 6, center = true);
        // 3mm screw hole from pocket bottom to bore
        translate([0, 5.9, screw_z])
            rotate([90, 0, 0])
                cylinder(d = screw_d, h = 11.8, $fn = 32, center = true);
    }
}

// D-bore helper: cube for clipping: need y in [-10, bore_flat_y]
module knob_part() {
    difference() {
        union() {
            cylinder(d = knob_d_body, h = knob_h - top_cham_h, $fn = 128);
            translate([0, 0, knob_h - top_cham_h])
                cylinder(d1 = knob_d_body, d2 = top_d, h = top_cham_h, $fn = 128);
            for (i = [0 : rib_n - 1])
                rotate([0, 0, i * 360 / rib_n])
                    translate([(rib_r_in + rib_r_out) / 2, 0, (knob_h - top_cham_h) / 2])
                        cube([rib_r_out - rib_r_in, rib_w, knob_h - top_cham_h], center = true);
        }
        // pointer groove
        translate([(pointer_x0 + pointer_x1) / 2 - (pointer_x1 - pointer_x0)/2, -pointer_w/2, knob_h - pointer_depth])
            cube([pointer_x1 - pointer_x0, pointer_w, pointer_depth + 1]);
        // D bore
        intersection() {
            translate([0, 0, -1]) cylinder(d = bore_d, h = bore_depth + 1, $fn = 64);
            translate([-10, -10, -1]) cube([20, bore_flat_y + 10, bore_depth + 1]);
        }
        // hex pocket
        translate([0, (pocket_y0 + pocket_y1) / 2, screw_z])
            rotate([90, 0, 0])
                cylinder(d = pocket_af / cos(30), h = pocket_y1 - pocket_y0, $fn = 6, center = true);
        // screw hole
        translate([0, 5.9, screw_z])
            rotate([90, 0, 0])
                cylinder(d = screw_d, h = 11.8, $fn = 32, center = true);
    }
}

// external shaft: 6mm D, flat faces +Y at y=1.5, from z=-10 to 14.8
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
            ["nut_pocket_ceiling", [[-3.5, 11.0, 8.0], [3.5, 16.5, 12.5]]],
            ["screw_hole_top", [[-2, -0.5, 7.0], [2, 12.0, 11.0]]]
        ]],
        ["copies", 1],
        ["details", [
            ["knurl_rib", "material", [[13.0, -0.75, 4], [15.0, 0.75, 12]], 0.8],
            ["pointer_groove", "void", [[1.0, -0.75, 17.0], [11.0, 0.75, 18.01]], 0.9],
            ["nut_pocket", "void", [[-2.6, 11.7, 6.5], [2.6, 15.5, 11.5]], 0.7],
            ["d_bore", "void", [[-2.9, -2.9, 0.5], [2.9, 1.4, 14.5]], 0.9],
            ["screw_hole", "hole", [0, 14.5, 9], [0, -1, 0], [[0, 3.0], [8, 3.0]]],
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
    // knob at identity (print orientation = use orientation, base down)
    instance("knob", "knob") knob_part();
    // nut in pocket: m3_nut axis Z -> axis Y, outer face at y=14
    instance("nut", "standard:m3_nut") translate([0, 14.0, 9]) rotate([90, 0, 0]) m3_nut();
    // shaft fully seated: top at 14.8 (0.2 below bore ceiling 15)
    instance("shaft", "external") translate([0, 0, -10]) shaft_ext();
}
