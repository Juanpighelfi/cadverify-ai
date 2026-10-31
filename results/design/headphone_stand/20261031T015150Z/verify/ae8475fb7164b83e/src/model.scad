// Headphone stand in three parts: base, post, hanger.
// No glue, no screws. Rectangular tenon/socket press/clearance fits;
// rectangular sections stop the hanger spinning on the post.
// Print orientations:
//   base   - flat on the bed, socket up
//   post   - lying on its back face, long axis along X
//   hanger - lying on one side face, saddle profile in the X/Y plane
// Assembled top of hanger is 270 mm above the desk.

part = "base"; // [base, post, hanger, assembly]
cadverify_only = "";

$fn = 64;

/* Dimensions (mm) */
base_w = 190;
base_d = 150;
base_t = 16;
base_r = 18;

desk_to_hanger_top = 270;

post_len_print = 241;       // use z 7..248
hanger_len = 124;           // use/print x -62..62
hanger_width = 36;          // use y -18..18
hanger_h_print = 38;        // use z 232..270 at centre

/* Socket / tenon geometry (use coordinates, for reference)
   Post main section:  x -16..16, y -13..13
   Bottom tenon:       x -12..12, y -13..7,  z 7..16   (base socket z 6..16)
   Top tenon:          x -12..12, y -13..3,  z 232..248 (hanger socket from z 232)
   Sockets are tenon size + 0.3 mm clearance per side, with flared mouths.
*/

module instance(name, part_name, unit = 1) {
    echo(cadverify_instance = [name, part_name, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module box3(x0, x1, y0, y1, z0, z1) {
    translate([x0, y0, z0]) cube([x1 - x0, y1 - y0, z1 - z0]);
}

module rounded_rect(w, d, r) {
    offset(r = r) square([w - 2 * r, d - 2 * r], center = true);
}

/* ---------------- BASE (print = use orientation) ---------------- */
module base_part() {
    difference() {
        union() {
            linear_extrude(12) rounded_rect(base_w, base_d, base_r);
            // 45-ish top edge taper: inset 3 mm over 4 mm height
            hull() {
                translate([0, 0, 12]) linear_extrude(0.2)
                    rounded_rect(base_w, base_d, base_r);
                translate([0, 0, base_t - 0.2]) linear_extrude(0.2)
                    rounded_rect(base_w - 6, base_d - 6, base_r - 3);
            }
        }
        // socket for post bottom tenon: 24.6 x 20.6, centre y=-3, floor z=6
        box3(-12.3, 12.3, -13.3, 7.3, 6, 17);
        // flared socket mouth (entry chamfer), 28.6 x 24.6 at the top face
        hull() {
            translate([0, -3, 15.9]) cube([28.6, 24.6, 0.2], center = true);
            translate([0, -3, 12.9]) cube([24.6, 20.6, 0.2], center = true);
        }
    }
}

/* ---------------- POST (print orientation) ----------------
   Print axes: X = use Z (length, 0 at bottom-tenon tip), Y = use X, Z = use Y + 13.
   Every section reaches Z=0 (the use back face), so it lies flat on the bed. */
module post_part() {
    union() {
        // bottom tenon, tapered lead-in in plan, 24 wide x 20 deep
        linear_extrude(20)
            polygon([[0, -9], [3, -12], [9, -12], [9, 12], [3, 12], [0, 9]]);
        // main shaft 32 x 26
        box3(9, 225, -16, 16, 0, 26);
        // bottom collar 52 wide, sits on the base top
        box3(9, 19, -26, 26, 0, 26);
        // top collar 48 wide, supports the hanger underside
        box3(217, 225, -24, 24, 0, 26);
        // top tenon, tapered lead-in in plan, 24 wide x 16 deep
        linear_extrude(16)
            polygon([[225, -12], [238, -12], [241, -9], [241, 9], [238, 12], [225, 12]]);
    }
}

/* ---------------- HANGER (print orientation) ----------------
   Print axes: X = use X, Y = use Z - 232, Z = use Y side face (0 on the bed).
   The saddle profile (parabolic top and bottom) is extruded across the width. */
module hanger_profile() {
    top = [for (i = [0 : 20]) let (x = -62 + 124 * i / 20)
        [x, hanger_h_print - 14 * pow(x / 62, 2)]];
    bot = [for (i = [20 : -1 : 0]) let (x = -62 + 124 * i / 20)
        [x, 12 * pow(x / 62, 2)]];
    polygon(concat(top, bot));
}

// Prismatic cutter in the Y/Z plane, extruded along X from -75 to 75.
// yz points are [y, z]; the region is the polygon given.
module cutter_yz(yz) {
    pts = [for (p = yz) [-p[1], p[0]]];   // local x = -z, local y = y
    translate([-75, 0, 0]) rotate([0, 90, 0]) linear_extrude(150) polygon(pts);
}

module hanger_part() {
    difference() {
        // saddle body: profile extruded 36 across
        linear_extrude(hanger_width) hanger_profile();
        // rounded (chamfered) longitudinal edges of the saddle top:
        // in print these cut the Y=profile-top / Z=0 and Z=36 corners.
        cutter_yz([[32, 36], [44, 30], [44, 52], [32, 52]]);   // Z=36 side
        cutter_yz([[32, -12], [44, -12], [44, 12], [32, 0]]);  // Z=0 side
        // socket for post top tenon: x -12.3..12.3, print z 14.7..31.3, depth to y=18
        box3(-12.3, 12.3, -2, 18, 14.7, 31.3);
        // flared socket mouth at the underside (print y = 0 face of the pocket)
        hull() {
            box3(-14.3, 14.3, -1.0, -0.8, 12.7, 33.3);
            box3(-12.3, 12.3, 5.0, 5.2, 14.7, 31.3);
        }
    }
}

/* ---------------- VERIFIABLE SPECS ---------------- */
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-base_w/2, -base_d/2, 0], [base_w/2, base_d/2, base_t]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bottom", "-z", 20000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["base_plate", "material", [[-80, -60, 1], [80, 60, 5]], 0.95],
            ["socket", "void", [[-11, -12, 10], [11, 6, 16.5]], 0.95],
            ["socket_mouth_flare", "void", [[-13, -14, 15], [13, 8, 17]], 0.90],
            ["socket_floor", "thickness", [0, -3, 20], [0, 0, -1], 6],
            ["base_plate_thickness", "thickness", [60, 40, 20], [0, 0, -1], 16],
            ["top_edge_taper", "view", [[70, -20, 11], [96, 20, 17]]]
        ]]
    ]);
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[0, -26, 0], [post_len_print, 26, 26]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["back", "-z", 6000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["main_shaft", "material", [[50, -14, 2], [100, 14, 24]], 0.95],
            ["bottom_collar", "material", [[10, -25, 2], [18, 25, 24]], 0.90],
            ["top_collar", "material", [[218, -23, 2], [224, 23, 24]], 0.90],
            ["beside_bottom_tenon", "void", [[1, 14, 2], [8, 20, 24]], 0.95],
            ["beside_top_tenon", "void", [[226, 14, 18], [240, 20, 24]], 0.95],
            ["shaft_depth", "thickness", [50, 0, -5], [0, 0, 1], 26],
            ["shaft_width", "thickness", [50, -30, 13], [0, 1, 0], 32],
            ["top_tenon", "view", [[215, -15, 0], [242, 15, 20]]]
        ]]
    ]);
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-hanger_len/2, 0, 0], [hanger_len/2, hanger_h_print, hanger_width]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["side", "-z", 3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["saddle_centre", "material", [[-20, 28, 8], [20, 36, 28]], 0.90],
            ["socket", "void", [[-11, 2, 16], [11, 16, 30]], 0.95],
            ["material_above_socket", "thickness", [0, 45, 23], [0, -1, 0], 20],
            ["saddle_width", "thickness", [0, 20, -5], [0, 0, 1], 36],
            ["saddle_top_edge", "view", [[-25, 30, 28], [25, 39, 37]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-base_w/2, -base_d/2, 0], [base_w/2, base_d/2, desk_to_hanger_top]]],
        ["support_faces", [["desk", "-z", 20000]]],
        ["allowed_interferences", []],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["post"], [0, 0, -1]],
            [["hanger"], [0, 0, -1]]
        ]]
    ]);
}

/* ---------------- OUTPUT ---------------- */
if (part == "base") {
    base_part();
} else if (part == "post") {
    post_part();
} else if (part == "hanger") {
    hanger_part();
} else if (part == "assembly") {
    instance("base", "base") base_part();
    // print -> use: Xu=Yp, Yu=Zp-13, Zu=Xp+7
    instance("post", "post")
        multmatrix([[0, 1, 0, 0],
                    [0, 0, 1, -13],
                    [1, 0, 0, 7],
                    [0, 0, 0, 1]]) post_part();
    // print -> use: Xu=Xp, Yu=-Zp+18, Zu=Yp+232
    instance("hanger", "hanger")
        multmatrix([[1, 0, 0, 0],
                    [0, 0, -1, 18],
                    [0, 1, 0, 232],
                    [0, 0, 0, 1]]) hanger_part();
}
