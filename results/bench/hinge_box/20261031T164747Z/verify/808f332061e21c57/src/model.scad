// Box with print-in-place hinge
// One print, printed closed (assembly pose = print pose), lid swings on a
// captive pin.  All dimensions in mm.  +Z up, rests on bed in closed pose.
//
// Clearances chosen for PLA / 0.4 mm nozzle on Bambu A1:
//   pin-to-bore radial 0.6, knuckle axial gap 0.8, lid rim gap 0.5,
//   barrel-to-body/lid scoop 0.6, barrel-to-shelf 0.65, catch 0.3-0.4.

part = "assembly"; // [assembly, body, lid, pin]

/* [Dimensions] */
W = 80;          // overall width  (X, along hinge)
D = 60;          // overall depth  (Y, front -Y to back +Y)
H = 40;          // overall height (Z)
wall = 2.4;
floor_t = 2.4;
top_t = 2.4;
body_h = 30;     // body rim top
lid_gap = 0.5;   // vertical print-in-place gap at the rim
lid_bottom = body_h + lid_gap;      // 30.5
lid_top = H;                        // 40

axis_y = 26;                 // hinge axis position
axis_z = body_h + 0.25;      // 30.25, mid rim-gap
barrel_R = 4;
bore_R = 2.6;
bore_d = 2 * bore_R;
scoop_R = 4.6;               // clearance scoop in back walls (0.6 over barrel)
pin_R = 2.0;
cap_R = 3.6;
seg_len = 12;
axial_gap = 0.8;
hinge_x0 = -31.6;            // 5 knuckles: 5*12 + 4*0.8 = 63.2 span
pin_len = 68.4;              // cap outer to cap outer
back_face = 23;              // main enclosure back outer face
back_inner = back_face - wall;   // 20.6

knuckle_min_z = axis_z - barrel_R;   // 26.25 (lid local zero)
tab_front_y = -27.3;
bump_front_y = -28.0;

cadverify_only = "";
module instance(name, p, unit = 1) {
    echo(cadverify_instance = [name, p, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- 2D hinge profiles: profile coords are [Z, Y] ---------- */
module barrel_outer_profile(r = barrel_R) {
    intersection() {
        translate([axis_z, axis_y]) circle(r = r, $fn = 72);
        translate([axis_z, axis_y])
            polygon(points = [[5, -5], [5, 5], [0, r], [-r, 0], [0, -r]]);
    }
}
module bore_profile() {
    union() {
        translate([axis_z, axis_y]) circle(r = bore_R, $fn = 72);
        // teardrop top so the bore ceiling is self-supporting
        translate([axis_z, axis_y])
            polygon(points = [[0, -bore_R], [3.4, 0], [0, bore_R]]);
    }
}
module body_knuckle_profile() {
    difference() {
        union() {
            barrel_outer_profile();
            // stem forward/down to body back wall + hinge shelf
            // (top kept at 29.8: 0.7 mm below the lid rim plane)
            polygon(points = [[25.6, 20.0], [29.8, 20.0],
                              [29.8, 26.5], [25.6, 26.5]]);
        }
        bore_profile();
    }
}
module lid_knuckle_profile() {
    difference() {
        union() {
            barrel_outer_profile();
            // stem forward/up to lid back wall
            // (bottom kept at 30.7: 0.7 mm above the body rim plane)
            polygon(points = [[30.7, 20.0], [35.0, 20.0],
                              [35.0, 26.5], [30.7, 26.5]]);
        }
        bore_profile();
    }
}
// extrude a [Z,Y] profile along X: segment occupies x0 .. x0+len
module extrude_x(x_end, len) {
    translate([x_end, 0, 0]) rotate([0, -90, 0])
        linear_extrude(height = len) children();
}
module knuckle(x0, is_lid) {
    extrude_x(x0 + seg_len, seg_len) {
        if (is_lid) lid_knuckle_profile(); else body_knuckle_profile();
    }
}
module knuckles() {
    for (i = [0 : 4]) {
        x0 = hinge_x0 + i * (seg_len + axial_gap);
        knuckle(x0, i % 2 == 1);   // body, lid, body, lid, body
    }
}
module body_knuckles() {
    for (i = [0 : 2]) knuckle(hinge_x0 + (2 * i) * (seg_len + axial_gap), false);
}
module lid_knuckles() {
    for (i = [0 : 1]) knuckle(hinge_x0 + (2 * i + 1) * (seg_len + axial_gap), true);
}

/* ---------- body (assembly coords = print coords) ---------- */
module scoop_cutter() {
    translate([-36, axis_y, axis_z]) rotate([0, 90, 0])
        cylinder(h = 72, r = scoop_R, $fn = 72);
}
module body_geom() {
    difference() {
        union() {
            // floor slab, extends under the hinge pocket to full depth
            translate([-W/2, -D/2, 0]) cube([W, D, floor_t]);
            // front wall
            translate([-W/2, -D/2, 0]) cube([W, wall, body_h]);
            // side walls
            translate([-W/2, -D/2, 0]) cube([wall, back_face + D/2, body_h]);
            translate([W/2 - wall, -D/2, 0]) cube([wall, back_face + D/2, body_h]);
            // back wall with hinge clearance scoop
            difference() {
                translate([-W/2, back_inner, 0]) cube([W, wall, body_h]);
                scoop_cutter();
            }
            // hinge support shelf under the barrels (barrels float 0.65 above it)
            translate([-36, 21, 24.0]) cube([72, 8.6, 1.6]);
            body_knuckles();
        }
        // front catch detent groove, open to the inner face
        translate([-3.6, -28.35, 27.5]) cube([7.2, 0.8, 2.0]);
    }
}

/* ---------- lid (assembly coords) ---------- */
module lid_geom() {
    union() {
        // top plate, extends back over the hinge to full depth
        translate([-W/2, -D/2, lid_top - top_t]) cube([W, D, top_t]);
        // front wall
        translate([-W/2, -D/2, lid_bottom]) cube([W, wall, lid_top - lid_bottom]);
        // side walls
        translate([-W/2, -D/2, lid_bottom])
            cube([wall, back_face + D/2, lid_top - lid_bottom]);
        translate([W/2 - wall, -D/2, lid_bottom])
            cube([wall, back_face + D/2, lid_top - lid_bottom]);
        // back wall with hinge clearance scoop
        difference() {
            translate([-W/2, back_inner, lid_bottom])
                cube([W, wall, lid_top - lid_bottom]);
            scoop_cutter();
        }
        lid_knuckles();
        // front catch tongue: hangs from the lid top inside the front wall
        translate([-5, tab_front_y, 26.5]) cube([10, 1.2, 11.2]);
        // catch bump (engages body detent groove when closed)
        translate([-3, bump_front_y, 27.9]) cube([6, 0.7, 1.2]);
    }
}
module lid_part() {
    translate([0, 0, -knuckle_min_z]) lid_geom();
}

/* ---------- pin (local coords: axis at y=0, z=cap_R) ---------- */
module pin_geom() {
    union() {
        translate([-pin_len/2, axis_y, axis_z]) rotate([0, 90, 0])
            cylinder(h = pin_len, r = pin_R, $fn = 48);
        for (s = [-1, 1]) {
            x0 = s < 0 ? -34.2 : 32.2;
            extrude_x(x0 + 2.0, 2.0) barrel_outer_profile(cap_R);
        }
    }
}
module pin_part() {
    translate([0, -axis_y, -(axis_z - cap_R)]) pin_geom();
}

module body_part() { body_geom(); }

/* ---------- specs ---------- */
if (part == "body") {
    echo(cadverify_spec = [
        ["bounds", [[-W/2, -D/2, 0], [W/2, D/2, axis_z + barrel_R]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge barrels, bore ceilings and shelf underside print over the hinge pocket / 0.65 mm above the shelf, no supports",
                [[-36, 20, 23], [36, 30, 35]]],
            ["catch groove ceiling inside front wall",
                [[-4, -29, 27], [4, -27, 30]]]
        ]],
        ["copies", 1],
        ["details", [
            ["floor_thickness", "thickness", [0, -10, -1], [0, 0, 1], floor_t],
            ["front_wall_thickness", "thickness", [10, -31, 15], [0, 1, 0], wall],
            ["cavity", "void", [[-35, -25, 5], [35, 16, 28]], 0.98],
            ["hinge_shelf", "material", [[-35, 22, 24.1], [35, 29, 25.5]], 0.9],
            ["body_knuckle_stem", "material", [[-30, 21, 26], [-21, 23, 29]], 0.9],
            ["pin_bore_body", "void", [[-5, 25, 29.25], [5, 27, 31.25]], 0.98],
            ["pin_bore_body_hole", "hole", [-34, axis_y, axis_z], [1, 0, 0],
                [[0, bore_d], [5, bore_d], [11, bore_d]]],
            ["hinge_knuckles", "view", [[-33, 21, 25], [33, 30, 35]]]
        ]]
    ]);
    body_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-W/2, -D/2, 0], [W/2, D/2, lid_top - knuckle_min_z]]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["lid top ceiling bridges between the lid walls",
                [[-38, -28, lid_top - top_t - knuckle_min_z - 0.35],
                 [38, 30, lid_top - top_t - knuckle_min_z + 0.35]]],
            ["hinge barrels and bore ceilings print over the hinge shelf gap, no supports",
                [[-40, 20, 0], [40, 30, 9]]],
            ["lid rim underside prints 0.5 mm above the body rim (print-in-place gap)",
                [[-40, -30, 3.4], [40, 23, 5.2]]],
            ["catch tongue underside inside the box",
                [[-6, -28, 0], [6, -26, 1.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top_thickness", "thickness", [0, 0, lid_top - knuckle_min_z + 1], [0, 0, -1], top_t],
            ["lid_cavity", "void", [[-35, -25, 5], [35, 16, 11]], 0.95],
            ["catch_tongue", "material", [[-4, -27.2, 1], [4, -26.3, 8]], 0.9],
            ["catch_bump", "material", [[-2.9, -27.95, 1.7], [2.9, -27.4, 2.8]], 0.9],
            ["pin_bore_lid", "void",
                [[-17, 25, axis_z - knuckle_min_z - 1], [-8, 27, axis_z - knuckle_min_z + 1]], 0.98],
            ["pin_bore_lid_hole", "hole", [-21, axis_y, axis_z - knuckle_min_z], [1, 0, 0],
                [[0, bore_d], [5, bore_d], [11, bore_d]]],
            ["catch_tongue_view", "view", [[-6, -29, 0], [6, -25, 6]]],
            ["hinge_knuckles_lid", "view", [[-33, 20, 0], [33, 30, 9]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-pin_len/2, -cap_R, 0], [pin_len/2, cap_R, 2 * cap_R]]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["pin shaft and caps print inside the knuckle bores, 0.6 mm radial gap, no supports",
                [[-35, -2, 1.4], [35, 2, 2.3]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_shaft_diameter", "thickness", [0, 0, -1], [0, 0, 1], 2 * pin_R],
            ["pin_cap", "material", [[32.4, -1, 2.6], [34.0, 1, 4.6]], 0.9],
            ["pin_cap_view", "view", [[31, -cap_R, 0], [34.2, cap_R, 2 * cap_R]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-W/2, -D/2, 0], [W/2, D/2, H]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0, axis_y, axis_z], [-1, 0, 0], [0, 110],
                ["flex", [["lid", "body", 0.7,
                    "front catch bump slides out of its detent groove; the catch tongue flexes back"]]]]
        ]],
        ["assembly_order", [
            // print-in-place: all three parts come off the bed already
            // assembled (the pin is captive and cannot be inserted later)
            [["body", "lid", "pin"], [0, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge barrels, pin and bore ceilings print without supports over the hinge pocket/shelf",
                [[-36, 20, 23], [36, 30, 35]]],
            ["lid top ceiling bridges between the lid walls over the closed cavity",
                [[-40, -30, 37], [40, 30, 40]]],
            ["lid rim and catch tongue undersides print over the 0.5 mm rim gap / body",
                [[-40, -30, 26], [40, 23, 31]]]
        ]]
    ]);
    instance("body", "body") body_part();
    instance("lid", "lid") translate([0, 0, knuckle_min_z]) lid_part();
    instance("pin", "pin") translate([0, axis_y, axis_z - cap_R]) pin_part();
} else {
    assert(false, "unknown part");
}
