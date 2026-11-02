/* Headphone stand in three parts: base, post, hanger.
   Each part is exported in its print orientation (rests on min z, +Z up).
   Joints: square slip fit 22/22.4 (base-post) and 18/18.4 (post-hanger),
   0.2 mm/side nominal clearance. */

part = "base"; // [base,post,hanger,assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
base_L = 180; base_W = 140; base_H = 14; base_corner_r = 12;
base_sock_S = 22.4; base_sock_straight_top = 12.5; base_sock_floor = 6;
base_flare_top_S = 25.4;

post_bot_tenon_S = 22; post_bot_tenon_H = 8;
post_cone_H = 4; post_body_bot_S = 30; post_body_top_S = 24; post_body_H = 224;
post_top_tenon_S = 18; post_top_tenon_H = 8;

hanger_L = 110; hanger_W = 44; hanger_slab_H = 6; hanger_ridge_R = 22;
hanger_ridge_L = 90; hanger_sock_S = 18.4; hanger_sock_H = 8.1;
hanger_roof_base = 7.9; hanger_roof_H = 9.2;

post_Z = 6;
hanger_Z = 242; // post shoulder (236+6) -> hanger top 242+28 = 270

// ---------- modules (print orientation, min z = 0) ----------
module base() {
    difference() {
        linear_extrude(height = base_H)
            hull() {
                for (sx = [-1, 1], sy = [-1, 1])
                    translate([sx*(base_L/2-base_corner_r), sy*(base_W/2-base_corner_r)])
                        circle(r = base_corner_r, $fn = 48);
            }
        // straight socket
        translate([-base_sock_S/2, -base_sock_S/2, base_sock_floor])
            cube([base_sock_S, base_sock_S, base_H - base_sock_floor + 0.2]);
        // 45 deg entry flare
        translate([0, 0, base_sock_straight_top])
            linear_extrude(height = base_H - base_sock_straight_top + 0.2,
                           scale = base_flare_top_S/base_sock_S)
                square([base_sock_S, base_sock_S], center = true);
    }
}

module post() {
    // bottom tenon
    translate([-post_bot_tenon_S/2, -post_bot_tenon_S/2, 0])
        cube([post_bot_tenon_S, post_bot_tenon_S, post_bot_tenon_H]);
    // 45 deg collar cone 22 -> 30
    translate([0, 0, post_bot_tenon_H])
        linear_extrude(height = post_cone_H, scale = post_body_bot_S/post_bot_tenon_S)
            square([post_bot_tenon_S, post_bot_tenon_S], center = true);
    // tapered body 30 -> 24
    translate([0, 0, post_bot_tenon_H + post_cone_H])
        linear_extrude(height = post_body_H, scale = post_body_top_S/post_body_bot_S)
            square([post_body_bot_S, post_body_bot_S], center = true);
    // top tenon
    translate([-post_top_tenon_S/2, -post_top_tenon_S/2,
               post_bot_tenon_H + post_cone_H + post_body_H])
        cube([post_top_tenon_S, post_top_tenon_S, post_top_tenon_H]);
}

module hanger() {
    difference() {
        union() {
            // bottom slab with rounded plan corners
            linear_extrude(height = hanger_slab_H)
                hull() {
                    for (sx = [-1, 1], sy = [-1, 1])
                        translate([sx*(hanger_L/2-6), sy*(hanger_W/2-6)])
                            circle(r = 6, $fn = 32);
                }
            // rounded crown: top half of a horizontal cylinder along X
            intersection() {
                translate([0, 0, hanger_slab_H])
                    rotate([0, 90, 0])
                        cylinder(r = hanger_ridge_R, h = hanger_ridge_L,
                                 center = true, $fn = 128);
                translate([-hanger_ridge_L/2, -hanger_W/2, hanger_slab_H - 0.1])
                    cube([hanger_ridge_L, hanger_W, hanger_ridge_R + 0.1]);
            }
        }
        // straight socket from the bed face, top meets roof base exactly
        translate([-hanger_sock_S/2, -hanger_sock_S/2, -0.1])
            cube([hanger_sock_S, hanger_sock_S, hanger_roof_base + 0.1]);
        // 45 deg pyramid roof inside (no flat ceiling -> no supports)
        translate([0, 0, hanger_roof_base])
            linear_extrude(height = hanger_roof_H, scale = 0)
                square([hanger_sock_S, hanger_sock_S], center = true);
    }
}

module assembly() {
    instance("base_1", "base") translate([0, 0, 0]) base();
    instance("post_1", "post") translate([0, 0, post_Z]) post();
    instance("hanger_1", "hanger") translate([0, 0, hanger_Z]) hanger();
}

// ---------- spec ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-90, -70, 0], [90, 70, 14]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base_bottom", "-z", 20000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["base_plate", "material", [[-90, -70, 0], [90, 70, 6]], 0.9],
            ["socket_void", "void", [[-11.2, -11.2, 6], [11.2, 11.2, 12.5]], 0.9],
            ["mouth_flare", "hole", [0, 0, 20], [0, 0, -1], [[0, 28.2], [1.5, 25.3]]],
            ["floor", "thickness", [0, 0, -5], [0, 0, 1], 6]
        ]]
    ]);
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-15, -15, 0], [15, 15, 244]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["tenon_bottom", "-z", 400]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bottom_tenon", "material", [[-11, -11, 0], [11, 11, 8]], 0.9],
            ["collar", "material", [[-10, -10, 8], [10, 10, 12]], 0.9],
            ["body_inner", "material", [[-11, -11, 30], [11, 11, 100]], 0.9],
            ["top_tenon", "material", [[-9, -9, 236], [9, 9, 244]], 0.9],
            ["side_wall", "thickness", [-30, 0, 100], [1, 0, 0], 27.6]
        ]]
    ]);
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-55, -22, 0], [55, 22, 28]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["hanger_bottom", "-z", 3500]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["wing_solid", "material", [[25, -20, 0], [50, 20, 6]], 0.9],
            ["ridge_solid", "material", [[25, -6, 10], [40, 6, 20]], 0.9],
            ["socket_void", "void", [[-9.2, -9.2, 0], [9.2, 9.2, 8]], 0.9],
            ["roof_void", "void", [[-9.2, -9.2, 8], [9.2, 9.2, 17.1]], 0.3],
            ["socket_entry", "hole", [0, 0, -5], [0, 0, 1], [[0, 20.8], [8, 20.8]]],
            ["crown_width", "thickness", [0, -30, 20], [0, 1, 0], 33.9],
            ["crown_floor", "thickness", [0, 0, 35], [0, 0, -1], 10.9],
            ["crown_round", "view", [[-20, -22, 20], [20, 22, 28]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-90, -70, 0], [90, 70, 270]]],
        ["support_faces", [["desk", "-z", 20000]]],
        ["allowed_interferences", []],
        ["motions", []],
        ["assembly_order", [
            [["base_1"], [0, 0, 0]],
            [["post_1"], [0, 0, -1]],
            [["hanger_1"], [0, 0, -1]]
        ]]
    ]);
}

// ---------- output ----------
if (part == "base") base();
else if (part == "post") post();
else if (part == "hanger") hanger();
else if (part == "assembly") assembly();
