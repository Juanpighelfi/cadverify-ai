// Headphone stand in three parts: base, post, hanger.
// Each part is modeled in its print orientation (+Z up, min z on the bed).
// Assembly: square slip-fit tenons (spin-proof), no glue or screws.

part = "assembly"; // [base, post, hanger, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- dimensions (mm) ----------
// base: 170 mm disc, 10 mm plate + 50 mm boss, 24.4 mm square blind socket
base_d = 170;
base_plate_h = 10;
boss_d = 50;
base_total_h = 22;
socket_s = 24.4;
socket_floor = 10;          // socket from z=10 (floor) to z=22 (mouth)

// post: 24 mm lower tenon, flare, 30x28 shaft, 20 mm upper tenon; 252 tall
post_low_s = 24.0;
post_low_h = 12;
post_flare_h = 5;           // 24x24 -> 30x28 over 5 mm (31 deg, no support needed)
post_shaft_x = 30;
post_shaft_y = 28;
post_shaft_h = 227;         // z 17..244
post_up_s = 20.0;
post_up_h = 8;              // z 244..252
post_total_h = 252;

// hanger: 40x140 footprint, bottom chamfer, straight sides, arched crown (top 16)
h_bot_x = 37; h_bot_y = 136;
h_max_x = 40; h_max_y = 140;
h_cham_h = 3;               // 0..3, 26.6 deg underside
h_straight_h = 7;           // 3..10
h_cap_h = 6;                // 10..16 tapered cap cut by lengthwise arch
h_cap_bx = 38; h_cap_by = 124;
h_cap_tx = 34; h_cap_ty = 120;
h_arch_r = 400; h_arch_cz = -384;   // arch apex z=16 at center, ~11.5 at ends
hanger_total_h = 16;
h_sock_s = 20.4;
h_sock_h = 8;               // blind socket 0..8, roof 8..16 (8 mm at center)

// assembly heights: base 0..22, post bottom on socket floor (z=10), hanger on shaft shoulder
asm_post_z = 10;            // post 10..262
asm_hanger_z = 254;         // hanger 254..270, socket ceiling (262) on post top
asm_top = 270;

$fn = 128;

module rrect2d(w, l, r) {
    hull() {
        translate([-(w/2-r), -(l/2-r)]) circle(r=r, $fn=48);
        translate([(w/2-r), -(l/2-r)]) circle(r=r, $fn=48);
        translate([-(w/2-r), (l/2-r)]) circle(r=r, $fn=48);
        translate([(w/2-r), (l/2-r)]) circle(r=r, $fn=48);
    }
}

module base() {
    difference() {
        union() {
            cylinder(d=base_d, h=base_plate_h);
            translate([0, 0, base_plate_h]) cylinder(d=boss_d, h=base_total_h - base_plate_h);
        }
        translate([-socket_s/2, -socket_s/2, socket_floor])
            cube([socket_s, socket_s, base_total_h - socket_floor + 0.5]);
    }
}

module post() {
    union() {
        translate([-post_low_s/2, -post_low_s/2, 0])
            cube([post_low_s, post_low_s, post_low_h]);
        translate([0, 0, post_low_h])
            linear_extrude(height=post_flare_h,
                scale=[post_shaft_x/post_low_s, post_shaft_y/post_low_s])
                translate([-post_low_s/2, -post_low_s/2])
                    square([post_low_s, post_low_s]);
        translate([-post_shaft_x/2, -post_shaft_y/2, post_low_h + post_flare_h])
            cube([post_shaft_x, post_shaft_y, post_shaft_h]);
        translate([-post_up_s/2, -post_up_s/2, post_low_h + post_flare_h + post_shaft_h])
            cube([post_up_s, post_up_s, post_up_h]);
    }
}

module hanger() {
    difference() {
        union() {
            // bottom chamfer: uniform 2 mm offset over 3 mm (33.7 deg, no supports)
            hull() {
                translate([0, 0, 0]) linear_extrude(height=0.1)
                    rrect2d(36, 136, 8);
                translate([0, 0, h_cham_h - 0.1]) linear_extrude(height=0.1)
                    rrect2d(h_max_x, h_max_y, 10);
            }
            // straight sides
            translate([0, 0, h_cham_h])
                linear_extrude(height=h_straight_h)
                    rrect2d(h_max_x, h_max_y, 10);
            // crown: tapered cap cut by a lengthwise arch (curved arm)
            intersection() {
                translate([0, 0, h_cham_h + h_straight_h])
                    linear_extrude(height=h_cap_h,
                        scale=[h_cap_tx/h_cap_bx, h_cap_ty/h_cap_by])
                        rrect2d(h_cap_bx, h_cap_by, 9);
                translate([-40, 0, h_arch_cz]) rotate([0, 90, 0])
                    cylinder(r=h_arch_r, h=80, $fn=256);
            }
        }
        // blind square socket, mouth down
        translate([-h_sock_s/2, -h_sock_s/2, -0.5])
            cube([h_sock_s, h_sock_s, h_sock_h + 0.5]);
    }
}

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-85, -85, 0], [85, 85, 22]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 15000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["socket", "void", [[-12, -12, 10], [12, 12, 22]], 0.9],
            ["floor", "thickness", [0, 0, -1], [0, 0, 1], 10],
            ["plate", "material", [[-80, -10, 0], [80, 10, 2]], 0.9],
            ["boss", "material", [[-20, -20, 10], [20, 20, 22]], 0.5],
            ["boss_width", "thickness", [30, 20, 16], [-1, 0, 0], 30],
            ["socket_span", "thickness", [30, 0, 16], [-1, 0, 0], 25.6],
            ["socket_corner", "void", [[7.5, -12.2, 12], [12.2, -7.5, 20]], 0.9],
            ["top", "view", [[-25, -25, 20], [25, 25, 22]]]
        ]]
    ]);
    base();
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-15, -14, 0], [15, 14, 252]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 400]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["lower_tenon", "material", [[-11, -11, 0], [11, 11, 12]], 0.9],
            ["low_tenon_width", "thickness", [20, 0, 6], [-1, 0, 0], 24],
            ["low_tenon_corner", "material", [[10, -12, 1], [12, -10, 11]], 0.9],
            ["upper_tenon", "material", [[-9, -9, 244], [9, 9, 252]], 0.9],
            ["up_tenon_width", "thickness", [15, 0, 248], [-1, 0, 0], 20],
            ["up_tenon_corner", "material", [[8, -10, 245], [10, -8, 251]], 0.9],
            ["shaft", "material", [[-13, -12, 100], [13, 12, 150]], 0.9],
            ["shaft_width", "thickness", [20, 0, 100], [-1, 0, 0], 30],
            ["top", "view", [[-15, -14, 238], [15, 14, 252]]]
        ]]
    ]);
    post();
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-20, -70, 0], [20, 70, 16]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 3000]]],
        ["overhangs_allowed", [["bridged socket ceiling", [[-10.2, -10.2, 7.5], [10.2, 10.2, 8.5]]]]],
        ["copies", 1],
        ["details", [
            ["socket", "void", [[-10, -10, 0], [10, 10, 8]], 0.9],
            ["sock_wall", "thickness", [25, 0, 4], [-1, 0, 0], 19.6],
            ["sock_corner", "void", [[7.5, -10.2, 1], [10.2, -7.5, 7]], 0.9],
            ["chamfer_width", "thickness", [25, 30, 1], [-1, 0, 0], 37.3],
            ["crown_center", "material", [[-16, -10, 13], [16, 10, 15]], 0.9],
            ["crown_end", "void", [[-15, 50, 13], [15, 62, 14.5]], 0.9],
            ["plan_corner", "void", [[17.5, 67.5, 4], [19.5, 69.5, 6]], 0.9],
            ["saddle_width", "thickness", [25, 30, 5], [-1, 0, 0], 40],
            ["saddle", "material", [[-19, -50, 3], [-11, 50, 8]], 0.9],
            ["round_top", "view", [[-17, -60, 13], [17, 60, 16]]]
        ]]
    ]);
    hanger();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-85, -85, 0], [85, 85, 270]]],
        ["support_faces", [["desk", "-z", 15000]]],
        ["allowed_interferences", []],
        ["motions", []],
        ["assembly_order", [
            [["base1"], [0, 0, 0]],
            [["post1"], [0, 0, -1]],
            [["hanger1"], [0, 0, -1]]
        ]],
        ["overhangs_allowed", []]
    ]);
    instance("base1", "base") base();
    instance("post1", "post") translate([0, 0, asm_post_z]) post();
    instance("hanger1", "hanger") translate([0, 0, asm_hanger_z]) hanger();
}
