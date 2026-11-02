// Headphone stand in three parts: base, post, hanger
// Print orientations = export orientations (+Z up, min z on bed)

part = "assembly"; // [base, post, hanger, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
base_d = 170;
base_plate_h = 10;
boss_d = 50;
boss_h = 12;
base_total_h = 22; // 10 + 12
socket_s = 24.4;  // square mortise in base
socket_depth = 12;
floor_h = 10;     // base_total_h - socket_depth

post_low_s = 24.0;
post_low_h = 12;
post_cham_h = 3;
post_shaft_x = 30;
post_shaft_y = 28;
post_shaft_h = 231;
post_up_s = 20.0;
post_up_h = 8;
post_total_h = 254; // 12+3+231+8

hanger_max_x = 40;
hanger_max_y = 140;
hanger_bot_x = 36;
hanger_bot_y = 132;
hanger_cham_h = 2;   // 0..2
hanger_straight_h = 6; // 2..8
hanger_taper_h = 4;  // 8..12
hanger_top_h = 2;    // 12..14
hanger_total_h = 14;
hanger_socket_s = 20.4;
hanger_socket_h = 8;
hanger_roof = 6; // 14-8

asm_top = 270;
asm_post_z = 10;    // post bottom = base floor
asm_hanger_z = 256; // hanger bottom, top = 270

$fn = 128;

// ---------- 2D helpers ----------
module rrect2d(w, l, r) {
    hull() {
        translate([-(w/2-r), -(l/2-r)]) circle(r=r, $fn=64);
        translate([(w/2-r), -(l/2-r)]) circle(r=r, $fn=64);
        translate([-(w/2-r), (l/2-r)]) circle(r=r, $fn=64);
        translate([(w/2-r), (l/2-r)]) circle(r=r, $fn=64);
    }
}

// ---------- parts (print orientation) ----------
module base() {
    difference() {
        union() {
            cylinder(d=base_d, h=base_plate_h);
            translate([0,0,base_plate_h]) cylinder(d=boss_d, h=boss_h);
        }
        // square blind socket, opens upward, floor faces up (no overhang)
        translate([-socket_s/2, -socket_s/2, floor_h]) cube([socket_s, socket_s, socket_depth+0.5]);
    }
}

module post() {
    union() {
        // lower tenon on bed
        translate([-post_low_s/2, -post_low_s/2, 0]) cube([post_low_s, post_low_s, post_low_h]);
        // 45 deg flare to shaft (downward-facing, exactly 45 deg -> allowed)
        translate([0,0,post_low_h])
            linear_extrude(height=post_cham_h, scale=[post_shaft_x/post_low_s, post_shaft_y/post_low_s])
                translate([-post_low_s/2, -post_low_s/2]) square([post_low_s, post_low_s]);
        // shaft
        translate([-post_shaft_x/2, -post_shaft_y/2, post_low_h+post_cham_h])
            cube([post_shaft_x, post_shaft_y, post_shaft_h]);
        // upper tenon (shoulder faces up -> no overhang)
        translate([-post_up_s/2, -post_up_s/2, post_low_h+post_cham_h+post_shaft_h])
            cube([post_up_s, post_up_s, post_up_h]);
    }
}

module hanger() {
    difference() {
        union() {
            // bottom 45deg chamfer: 36x132 -> 40x140 over h=2
            translate([0,0,0])
                linear_extrude(height=hanger_cham_h, scale=[hanger_max_x/hanger_bot_x, hanger_max_y/hanger_bot_y])
                    rrect2d(hanger_bot_x, hanger_bot_y, 10);
            // straight sides 2..8
            translate([0,0,hanger_cham_h])
                linear_extrude(height=hanger_straight_h)
                    rrect2d(hanger_max_x, hanger_max_y, 10);
            // upper taper 8..12 : 40x140 -> 34x124 (faces up/out, no overhang)
            translate([0,0,hanger_cham_h+hanger_straight_h])
                linear_extrude(height=hanger_taper_h, scale=[34/hanger_max_x, 124/hanger_max_y])
                    rrect2d(hanger_max_x, hanger_max_y, 10);
            // top chamfer 12..14 : 34x124 -> 32x122
            translate([0,0,hanger_cham_h+hanger_straight_h+hanger_taper_h])
                linear_extrude(height=hanger_top_h, scale=[32/34, 122/124])
                    rrect2d(34, 124, 9);
        }
        // blind square socket opening downward (ceiling bridged, declared)
        translate([-hanger_socket_s/2, -hanger_socket_s/2, -0.5])
            cube([hanger_socket_s, hanger_socket_s, hanger_socket_h+0.5]);
    }
}

// ---------- dispatch + specs ----------
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
            ["top", "view", [[-25, -25, 20], [25, 25, 22]]]
        ]]
    ]);
    base();
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-15, -14, 0], [15, 14, 254]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 400]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["lower_tenon", "material", [[-11, -11, 0], [11, 11, 12]], 0.9],
            ["upper_tenon", "material", [[-9, -9, 246], [9, 9, 254]], 0.9],
            ["shaft", "material", [[-13, -12, 100], [13, 12, 150]], 0.9],
            ["shaft_width", "thickness", [20, 0, 100], [-1, 0, 0], 30],
            ["top", "view", [[-15, -14, 240], [15, 14, 254]]]
        ]]
    ]);
    post();
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-20, -70, 0], [20, 70, 14]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 3000]]],
        ["overhangs_allowed", [["bridged socket ceiling", [[-10.2, -10.2, 7.5], [10.2, 10.2, 8.5]]]]],
        ["copies", 1],
        ["details", [
            ["socket", "void", [[-10, -10, 0], [10, 10, 8]], 0.9],
            ["roof", "thickness", [0, 0, 20], [0, 0, -1], 6],
            ["saddle_width", "thickness", [25, 0, 5], [-1, 0, 0], 40],
            ["saddle", "material", [[-15, -50, 2], [15, 50, 8]], 0.9],
            ["round_top", "view", [[-16, -61, 12], [16, 61, 14]]]
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
