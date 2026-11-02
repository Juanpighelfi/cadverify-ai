// Small print-in-place hinged box
// Printed closed, in one print, on a Bambu Lab A1 (PLA, 0.4 mm nozzle).
// The pin is integral with the box body: the lid knuckles are printed
// around it with 0.4 mm radial clearance and break free by hand.
// Dimensions are in mm.  Assembly coordinates: x 0..80 (left..right),
// y 0..60 (front..back incl. hinge), z 0..40 (bed..closed top).

part = "assembly"; // [assembly, body, lid]

$fn = 64;

// Overall / main dimensions
W = 80;              // outside width  (x)
D_main = 55;         // box depth excluding hinge barrels (y)
D_all = 60;          // outside depth incl. hinge barrels (y)
H_body = 30;         // body rim height
part_gap = 0.4;      // print-in-place clearance between body and lid
lid_bottom = H_body + part_gap;   // 30.4
H_total = 40;        // closed height; lid is H_total-lid_bottom = 9.6
wall = 2.4;
floor_t = 2.4;

// Hinge
axis_y = 57;
axis_z = 31.5;
knuckle_r = 3.0;
groove_r = knuckle_r + part_gap;  // 3.4 rotating clearance recess
bore_r = 1.7;                     // lid knuckle bore
pin_r = 1.3;                      // integral pin (bore_r-pin_r = 0.4)
seg_len = 8.4;
seg_gap = 0.8666667;
seg0 = 8;
function seg_x(i) = seg0 + i * (seg_len + seg_gap);

// Front catch (in assembly coordinates)
// channel x 35..45, tab x 36.5..43.5, ridge z 24..25.2
catch_tab_bottom = 20;            // also lid part local z = 0
lid_shift = catch_tab_bottom;     // assembly z -> lid local z

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------------------------------------------------------------- helpers
module box_at(x1, y1, z1, x2, y2, z2)
    translate([x1, y1, z1]) cube([x2 - x1, y2 - y1, z2 - z1]);

module cyl_x(x1, x2, yc, zc, r, fn = 64)
    translate([x1, yc, zc]) rotate([0, 90, 0])
        cylinder(h = x2 - x1, r = r, $fn = fn);

// ---------------------------------------------------------------- body
module body_geom() {
    union() {
        difference() {
            box_at(0, 0, 0, W, D_main, H_body);
            // interior cavity
            box_at(wall, wall, floor_t, W - wall, D_main - wall, H_body + 1);
            // recess that the lid hinge barrels rotate in
            cyl_x(6, 74, axis_y, axis_z, groove_r);
            // front catch channel
            box_at(35, -1, 18, 45, 1.9, H_body + 1);
        }
        // hinge barrels (body segments 0,2,4,6), lower web to the back wall
        for (i = [0, 2, 4, 6]) {
            cyl_x(seg_x(i), seg_x(i) + seg_len, axis_y, axis_z, knuckle_r);
            box_at(seg_x(i), 54, 28.5, seg_x(i) + seg_len, 58, axis_z);
        }
        // pin, integral with the body, spanning all knuckles
        cyl_x(4.5, 75.5, axis_y, axis_z, pin_r, 48);
        // catch ridge and its interior backing pad
        box_at(35, 1.2, 24, 45, 3.8, 25.2);       // ridge (front face y=1.2)
        box_at(34, 1.9, 17, 46, 3.8, H_body);     // backing pad inside box
    }
}

// ---------------------------------------------------------------- lid
module lid_geom() {
    difference() {
        union() {
            difference() {
                box_at(0, 0, lid_bottom, W, D_main, H_total);
                // hollow cap: 45-degree pyramidal ceiling
                hull() {
                    box_at(wall, wall, lid_bottom, W - wall, D_main - wall,
                           lid_bottom + 0.2);
                    box_at(wall + 7.2, wall + 7.2, 37.4, W - wall - 7.2,
                           D_main - wall - 7.2, 37.6);
                }
                // recess that the body hinge barrels rotate in
                cyl_x(6, 74, axis_y, axis_z, groove_r);
            }
            // hinge barrels (lid segments 1,3,5), upper web to back wall
            for (i = [1, 3, 5]) {
                cyl_x(seg_x(i), seg_x(i) + seg_len, axis_y, axis_z, knuckle_r);
                box_at(seg_x(i), 54, axis_z, seg_x(i) + seg_len, 58, 34.5);
            }
            // front catch tab and its snap bump
            box_at(36.5, 0.45, catch_tab_bottom, 43.5, 1.15, lid_bottom + 0.6);
            box_at(37.5, 1.15, 22.4, 42.5, 1.85, 23.6);
        }
        // bore through the lid barrels, around the integral pin
        cyl_x(3, 77, axis_y, axis_z, bore_r);
    }
}

// ---------------------------------------------------------------- specs
if (part == "body") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [W, D_all, axis_z + knuckle_r]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge barrels, pin and bore surfaces bridge between knuckles and the back wall; printed without supports", [[4, 53, 28], [76, 60, 35]]],
            ["catch ridge underside bridges the front catch channel", [[33, 0, 17], [47, 4, 31]]]
        ]],
        ["copies", 1],
        ["details", [
            ["floor", "thickness", [40, 27, -2], [0, 0, 1], floor_t],
            ["front_wall", "thickness", [20, -2, 15], [0, 1, 0], wall],
            ["side_wall", "thickness", [-2, 27, 15], [1, 0, 0], wall],
            ["interior", "void", [[10, 10, 8], [70, 45, 26]], 0.95],
            ["body_knuckle", "material", [[10, 56.2, 33.6], [14, 57.8, 34.3]], 0.85],
            ["pin", "material", [[19, 56.4, 30.9], [21, 57.6, 32.1]], 0.9],
            ["catch_ridge", "material", [[37, 1.3, 24.2], [43, 2.2, 25.0]], 0.9],
            ["catch_channel", "void", [[36, 0, 19], [44, 1.0, 22]], 0.95],
            ["hinge", "view", [[4, 52, 27], [76, 60, 35]]]
        ]]
    ]);
    body_geom();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [W, D_all, H_total - lid_shift]]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["hinge barrels and bore bridge between knuckles and the back wall; printed without supports", [[4, 53, 8], [76, 60, 15]]],
            ["lid rim and pyramidal cavity ceiling bridge over the box cavity from the skirt, hinge and catch tab", [[0, 0, 10], [80, 55, 18]]],
            ["catch bump underside is a small snap face on the front tab", [[35, 0, 0], [45, 2, 4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [40, 27, 22], [0, 0, -1], 2.4],
            ["front_skirt", "thickness", [20, -2, 10.6], [0, 1, 0], wall],
            ["side_skirt", "thickness", [-2, 27, 10.6], [1, 0, 0], wall],
            ["lid_cavity", "void", [[12, 10, 12], [68, 44, 16]], 0.95],
            ["lid_knuckle", "material", [[19, 56.2, 13.6], [23, 57.8, 14.3]], 0.85],
            ["lid_bore", "hole", [seg_x(1), axis_y, axis_z - lid_shift], [1, 0, 0], [[0, 3.4], [7.5, 3.4]]],
            ["catch_tab", "material", [[37, 0.5, 1], [43, 1.1, 5]], 0.9],
            ["catch_bump", "material", [[38, 1.2, 2.6], [42, 1.8, 3.4]], 0.9],
            ["hinge", "view", [[4, 52, 7], [76, 60, 15]]],
            ["catch", "view", [[33, -1, 0], [47, 3, 12]]]
        ]]
    ]);
    translate([0, 0, -lid_shift]) lid_geom();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [W, D_all, H_total]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["assembly_order", [
            [["body"], [0, 0, 0]],
            [["lid"], [0, 0, 1]]
        ]],
        ["allowed_interferences", []],
        ["motions", [
            ["open_lid", ["lid"], "rotate", [40, axis_y, axis_z], [-1, 0, 0], [0, 115],
                ["flex", [["lid", "body", 0.5, "catch bump rides over the front ridge and springs back; free when closed and when open"]]]]
        ]],
        ["print_in_place", part_gap],
        ["overhangs_allowed", [
            ["hinge barrels, pin and bore surfaces bridge between knuckles and the back wall; printed without supports", [[4, 53, 28], [76, 60, 35]]],
            ["lid rim and pyramidal cavity ceiling bridge over the box cavity from the skirt, hinge and catch tab", [[0, 0, 30], [80, 55, 38]]],
            ["catch ridge and bump undersides bridge the front catch channel", [[33, 0, 17], [47, 4, 31]]]
        ]]
    ]);
    instance("body", "body") body_geom();
    instance("lid", "lid") lid_geom();
}
