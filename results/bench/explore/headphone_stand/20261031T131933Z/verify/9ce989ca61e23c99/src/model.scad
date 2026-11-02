/* Headphone stand in three parts: base, post, hanger */
/* [Parts] */
part = "base"; // [base,post,hanger,assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
base_L = 180;
base_W = 140;
base_H = 14;
base_corner_r = 12;
base_sock_S = 22.4;
base_sock_H = 8;
base_flare_H = 1.5;

post_bot_tenon_S = 22;
post_bot_tenon_H = 8;
post_bot_cham_H = 4;
post_body_bot_S = 30;
post_body_top_S = 24;
post_body_H = 232;
post_top_tenon_S = 18;
post_top_tenon_H = 8;
// total post height = 8+4+232+8 = 252

hanger_L = 110;
hanger_W = 44;
hanger_H = 20;
hanger_sock_S = 18.4;
hanger_sock_H = 8;
hanger_roof_H = 9.2; // half width, 45 deg pyramid

assembly_top = 270;
post_Z_in_assembly = 6;      // post print z0 sits at 6 in assembly
hanger_Z_in_assembly = 250;  // hanger print z0 sits at 250

// ---------- modules (print orientation, min z = 0) ----------
module base() {
    difference() {
        linear_extrude(height = base_H)
            hull() {
                translate([-base_L/2+base_corner_r, -base_W/2+base_corner_r]) circle(r = base_corner_r, $fn = 48);
                translate([ base_L/2-base_corner_r, -base_W/2+base_corner_r]) circle(r = base_corner_r, $fn = 48);
                translate([-base_L/2+base_corner_r,  base_W/2-base_corner_r]) circle(r = base_corner_r, $fn = 48);
                translate([ base_L/2-base_corner_r,  base_W/2-base_corner_r]) circle(r = base_corner_r, $fn = 48);
            }
        // straight socket 22.4 x 22.4 from z=6 to top
        translate([-base_sock_S/2, -base_sock_S/2, base_H - base_sock_H])
            cube([base_sock_S, base_sock_S, base_sock_H + 0.2]);
        // 45 deg entry flare, 1.5 tall: 22.4 at bottom -> 25.4 at top
        translate([0, 0, base_H - base_flare_H])
            linear_extrude(height = base_flare_H + 0.2, scale = (base_sock_S + 2*base_flare_H)/base_sock_S)
                square([base_sock_S, base_sock_S], center = true);
    }
}

module post() {
    // bottom tenon 22x22x8 on bed
    translate([-post_bot_tenon_S/2, -post_bot_tenon_S/2, 0])
        cube([post_bot_tenon_S, post_bot_tenon_S, post_bot_tenon_H]);
    // 45 deg frustum 22 -> 30, 4 tall
    translate([0, 0, post_bot_tenon_H])
        linear_extrude(height = post_bot_cham_H, scale = post_body_bot_S/post_bot_tenon_S)
            square([post_bot_tenon_S, post_bot_tenon_S], center = true);
    // tapered body 30 -> 24, 232 tall
    translate([0, 0, post_bot_tenon_H + post_bot_cham_H])
        linear_extrude(height = post_body_H, scale = post_body_top_S/post_body_bot_S)
            square([post_body_bot_S, post_body_bot_S], center = true);
    // top tenon 18x18x8
    translate([-post_top_tenon_S/2, -post_top_tenon_S/2, post_bot_tenon_H + post_bot_cham_H + post_body_H])
        cube([post_top_tenon_S, post_top_tenon_S, post_top_tenon_H]);
}

module hanger() {
    difference() {
        hull() {
            translate([-55, -22, 0]) cube([110, 44, 8]);
            translate([-50, -19, 0]) cube([20, 38, 14]);
            translate([-15, -16, 0]) cube([30, 32, 20]);
            translate([30, -19, 0]) cube([20, 38, 14]);
        }
        // straight socket 18.4x18.4, 0-8.1
        translate([-hanger_sock_S/2, -hanger_sock_S/2, -0.1])
            cube([hanger_sock_S, hanger_sock_S, hanger_sock_H + 0.2]);
        // 45 deg pyramid roof, base 18.4 at z=8, apex at z=17.2
        polyhedron(points = [[-9.2,-9.2,8],[9.2,-9.2,8],[9.2,9.2,8],[-9.2,9.2,8],[0,0,17.2]],
            faces = [[0,1,2,3],[0,1,4],[1,2,4],[2,3,4],[3,0,4]]);
    }
}

module assembly() {
    instance("base_1", "base") translate([0, 0, 0]) base();
    instance("post_1", "post") translate([0, 0, post_Z_in_assembly]) post();
    instance("hanger_1", "hanger") translate([0, 0, hanger_Z_in_assembly]) hanger();
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
            ["mouth_flare", "hole", [0, 0, 20], [0, 0, -1], [[0, 25.4], [1.5, 22.4]]],
            ["floor", "thickness", [0, 0, -5], [0, 0, 1], 6]
        ]]
    ]);
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-15, -15, 0], [15, 15, 252]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["tenon_bottom", "-z", 400]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bottom_tenon", "material", [[-11, -11, 0], [11, 11, 8]], 0.9],
            ["body_inner", "material", [[-11, -11, 30], [11, 11, 100]], 0.9],
            ["top_tenon", "material", [[-9, -9, 244], [9, 9, 252]], 0.9],
            ["side_wall", "thickness", [-30, 0, 100], [1, 0, 0], 27]
        ]]
    ]);
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-55, -22, 0], [55, 22, 20]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["hanger_bottom", "-z", 3500]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["base_solid", "material", [[-20, -15, 0], [20, 15, 8]], 0.9],
            ["center_top", "material", [[-15, -15, 12], [15, 15, 18]], 0.9],
            ["contact_patch", "material", [[-20, -15, 8], [20, 15, 12]], 0.9],
            ["socket_void", "void", [[-9.2, -9.2, 0], [9.2, 9.2, 8]], 0.9],
            ["roof_void", "void", [[-9.2, -9.2, 8], [9.2, 9.2, 17.2]], 0.3],
            ["socket_entry", "hole", [0, 0, -5], [0, 0, 1], [[0, 18.4], [8, 18.4]]],
            ["floor", "thickness", [0, 0, 30], [0, 0, -1], 2.5],
            ["edge_thickness", "thickness", [50, 0, 30], [0, 0, -1], 13]
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
