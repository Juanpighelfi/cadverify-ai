/* Phone stand on a ball joint - PLA, 0.4mm nozzle, no supports */
// part selector: assembly (upright), base, holder
part = "assembly"; // [assembly, base, holder]

cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- parameters (mm) ---------- */
base_d = 90; base_r = 45; base_h = 6;
ball_r = 10; ball_d = 20;
ball_cz = 38; // ball center height in assembly/base coords (base bottom z=0)
neck_r = 6;   // post top radius where it meets ball
neck_top_z = ball_cz - 8; // 30, junction circle r=6 on sphere r=10
post_r_bot = 10;

socket_r = 10.6;
socket_open_r = 10.2; // > ball_r so ball passes with 0.2 clearance, < socket_r so lip remains
socket_open_d = socket_open_r*2; // 20.4
socket_max_d = socket_r*2; // 21.2
// opening plane is dz_open below centers:
dz_open = sqrt(socket_r*socket_r - socket_open_r*socket_open_r); // ~2.88
flat_dz = 10.2; // flat top height above centers (above ball top 10 + 0.2 clearance)
flat_r = sqrt(socket_r*socket_r - flat_dz*flat_dz); // ~2.88
socket_depth = dz_open + flat_dz; // ~13.08

holder_block_w = 90; holder_block_d = 34; holder_block_h = 28;
holder_bottom_z = ball_cz - dz_open; // 35.12 in assembly
// holder local: bottom z=0 at opening plane, socket center at dz_open
groove_w = 84; groove_d = 12; groove_h = 10;
groove_bottom_z = 18; // local
back_t = 6; back_h = 75;
front_t = 4; front_h = 12;
slot_w = 2;

$fn = 96;

/* ---------- base part (print orientation, bottom z=0) ---------- */
module base_part() {
    // base disc
    cylinder(h = base_h, r = base_r);
    // tapered post 6 -> neck_top_z
    translate([0,0,base_h])
        cylinder(h = neck_top_z - base_h, r1 = post_r_bot, r2 = neck_r);
    // ball
    translate([0,0,ball_cz])
        sphere(r = ball_r);
}

/* ---------- holder part (print orientation = use upright, bottom z=0) ---------- */
module holder_part() {
    difference() {
        union() {
            // base block 90 x 34 x 28, centered x/y, bottom z=0
            translate([-holder_block_w/2, -holder_block_d/2, 0])
                cube([holder_block_w, holder_block_d, holder_block_h]);
            // back plate: rear edge y [-17,-11], full width, 28 -> 28+75=103
            translate([-holder_block_w/2, -holder_block_d/2, holder_block_h])
                cube([holder_block_w, back_t, back_h]);
            // front lip: front edge y [13,17], 28 -> 40
            translate([-holder_block_w/2, holder_block_d/2 - front_t, holder_block_h])
                cube([holder_block_w, front_t, front_h]);
            // two gussets (vertical triangles, 4 thick in X) at x=±38
            for (sx = [-1,1])
                translate([sx*38 - 2, -11, holder_block_h])
                    rotate([0,0,0])
                        linear_extrude(height = 4, center = false)
                            // need thin in X, shape in YZ -> build in XY then rotate?
                            // build placeholder, replaced below via hull? use polyhedron
                            square([1,1]); // placeholder replaced
        }
        // --- subtractive features ---
        // phone groove on top: 84 x 12 x 10, centered, top open
        translate([-groove_w/2, -groove_d/2, groove_bottom_z])
            cube([groove_w, groove_d, holder_block_h - groove_bottom_z + 1]);
        // socket spherical cavity centered (0,0,dz_open), truncated
        translate([0,0,dz_open])
            sphere(r = socket_r);
        // opening cylinder below opening plane to bottom face
        translate([0,0,-1])
            cylinder(h = 2, r = socket_open_r);
        // flat top cut above flat plane (remove sphere cap above flat)
        translate([0,0,dz_open + flat_dz])
            cube([60,60,20], center = false);
        // flex slots: cross, open to bottom and sides, with 45deg roof tops
        // slot along X (thin in Y)
        translate([-holder_block_w/2, -slot_w/2, -1])
            cube([holder_block_w, slot_w, 11]);
        // slot along Y (thin in X)
        translate([-slot_w/2, -holder_block_d/2, -1])
            cube([slot_w, holder_block_d, 11]);
        // slot roofs (45deg prisms) to avoid flat ceilings: triangular top 2 wide, 1 tall? 
        // Actually make roof peak 1mm above slot top (10 -> 11), 45deg
        // slot X roof: prism along X, triangle in YZ with base 2 (y), height 1 (z)
        translate([-holder_block_w/2, 0, 10])
            rotate([0,90,0])
                linear_extrude(height = holder_block_w)
                    polygon(points = [[-1,0],[1,0],[0,1]]);
        // slot Y roof
        translate([0, -holder_block_d/2, 10])
            rotate([90,0,0])
                linear_extrude(height = holder_block_d)
                    polygon(points = [[-1,0],[1,0],[0,1]]);
    }
    // gussets added (union) with correct shape: triangular prisms thin in X
    for (sx = [-1,1]) {
        translate([sx*38 - 2, -11, holder_block_h])
            rotate([90,0,90])
                linear_extrude(height = 4)
                    polygon(points = [[0,0],[15,0],[0,20]]);
        // polygon in XY: x along Y (depth 15 forward), y up 20; extrude 4 in Z then rotated to thin-X
    }
}

// NOTE: placeholder gusset in difference union above creates tiny 1x1x4 nub inside part (fully enclosed, would create cavity).
// Remove it by rebuilding holder without placeholder: redefine cleanly below.
module holder_clean() {
    difference() {
        union() {
            translate([-holder_block_w/2, -holder_block_d/2, 0])
                cube([holder_block_w, holder_block_d, holder_block_h]);
            translate([-holder_block_w/2, -holder_block_d/2, holder_block_h])
                cube([holder_block_w, back_t, back_h]);
            translate([-holder_block_w/2, holder_block_d/2 - front_t, holder_block_h])
                cube([holder_block_w, front_t, front_h]);
            for (sx = [-1,1])
                translate([sx*38 - 2, -11, holder_block_h])
                    rotate([90,0,90])
                        linear_extrude(height = 4)
                            polygon(points = [[0,0],[15,0],[0,20]]);
        }
        translate([-groove_w/2, -groove_d/2, groove_bottom_z])
            cube([groove_w, groove_d, holder_block_h - groove_bottom_z + 1]);
        translate([0,0,dz_open])
            sphere(r = socket_r);
        translate([0,0,-1])
            cylinder(h = 2, r = socket_open_r);
        translate([-30,-30,dz_open + flat_dz])
            cube([60,60,20]);
        translate([-holder_block_w/2, -slot_w/2, -1])
            cube([holder_block_w, slot_w, 11]);
        translate([-slot_w/2, -holder_block_d/2, -1])
            cube([slot_w, holder_block_d, 11]);
        translate([-holder_block_w/2, 0, 10])
            rotate([0,90,0])
                linear_extrude(height = holder_block_w)
                    polygon(points = [[-1,0],[1,0],[0,1]]);
        translate([0, -holder_block_d/2, 10])
            rotate([90,0,0])
                linear_extrude(height = holder_block_d)
                    polygon(points = [[-1,0],[1,0],[0,1]]);
    }
}

/* ---------- specs ---------- */
// base bounds: x/y +-45, z 0..48
// holder local bounds: x +-45, y +-17, z 0..103
// assembly bounds: x +-45, y +-45, z 0..138.12

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-45,-45,0],[45,45,48]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base_bottom","-z",6000]]],
        ["overhangs_allowed", [["ball_seat", [[-11,-11,28],[11,11,36]]]]],
        ["copies", 1],
        ["details", [
            ["ball", "material", [[-5,-5,33],[5,5,43]], 0.9],
            ["post", "material", [[-3,-3,10],[3,3,25]], 0.9],
            ["base_floor", "thickness", [30,0,-1], [0,0,1], 6]
        ]]
    ]);
    base_part();
} else if (part == "holder") {
    echo(cadverify_spec = [
        ["bounds", [[-45,-17,0],[45,17,103]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["holder_bottom","-z",2000]]],
        ["overhangs_allowed", [["socket_ceiling", [[-6,-6,9],[6,6,14]]]]],
        ["copies", 1],
        ["details", [
            ["cradle_slot", "void", [[-42,-6,18],[42,6,28]], 0.9],
            ["socket", "void", [[-5,-5,2],[5,5,10]], 0.9],
            ["socket_mouth", "hole", [0,0,-5], [0,0,1], [[0,20.4],[2.9,21.2]]],
            ["back_wall", "thickness", [0,-22,60], [0,1,0], 6],
            ["front_lip", "material", [[-40,13.5,29],[40,16.5,39]], 0.9],
            ["flex_slot", "void", [[-20,-1,0],[20,1,10]], 0.9]
        ]]
    ]);
    holder_clean();
} else {
    // assembly: holder upright on ball
    echo(cadverify_spec = [
        ["bounds", [[-45,-45,0],[45,45,138.12]]],
        ["support_faces", [["base_bottom","-z",6000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["tilt", ["holder"], "rotate", [0,0,38], [1,0,0], [-30,30]],
            ["turn", ["holder"], "rotate", [0,0,38], [0,0,1], [0,360]]
        ]],
        ["assembly_order", [
            [["base"], [0,0,0]],
            [["holder"], [0,0,1]]
        ]]
    ]);
    instance("base", "base") base_part();
    instance("holder", "holder") translate([0,0,holder_bottom_z]) holder_clean();
}
