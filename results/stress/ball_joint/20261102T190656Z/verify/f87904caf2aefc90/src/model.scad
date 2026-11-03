/* Phone stand on a ball joint - PLA, 0.4mm nozzle, no supports */
part = "assembly"; // [assembly, base, holder]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- parameters (mm) ---------- */
base_d = 90; base_r = 45; base_h = 6;
ball_r = 10;
ball_cz = 38;
neck_r = 6;
neck_top_z = ball_cz - 8; // 30
post_r_bot = 10;

socket_r = 10.6;
socket_open_r = 10.2;
socket_open_d = 20.4;
dz_open = sqrt(socket_r*socket_r - socket_open_r*socket_open_r); // ~2.884
flat_dz = 10.2;
socket_depth = dz_open + flat_dz; // ~13.08
// printable cone top: sphere up to 45deg, then 45deg cone to flat
cone_base_dz = socket_r*cos(45); // ~7.495 above center
cone_base_r = socket_r*sin(45);  // ~7.495
cone_h = flat_dz - cone_base_dz; // ~2.705
cone_top_r = cone_base_r - cone_h; // ~4.79

holder_block_w = 90; holder_block_d = 34; holder_block_h = 28;
holder_bottom_z = ball_cz - dz_open; // ~35.116 in assembly
groove_w = 84; groove_d = 12; groove_h = 10;
groove_bottom_z = 18;
back_t = 6; back_h = 75;
front_t = 4; front_h = 12;
slot_w = 2;

$fn = 96;

module base_part() {
    cylinder(h = base_h, r = base_r);
    translate([0,0,base_h])
        cylinder(h = neck_top_z - base_h, r1 = post_r_bot, r2 = neck_r);
    translate([0,0,ball_cz])
        sphere(r = ball_r);
}

module holder_part() {
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
        // phone groove
        translate([-groove_w/2, -groove_d/2, groove_bottom_z])
            cube([groove_w, groove_d, holder_block_h - groove_bottom_z + 1]);
        // socket void: sphere clipped at cone base + cone + opening
        union() {
            intersection() {
                translate([0,0,dz_open]) sphere(r = socket_r);
                translate([-20,-20,-1]) cube([40,40,(dz_open+cone_base_dz)+1]);
            }
            translate([0,0,dz_open+cone_base_dz])
                cylinder(h = cone_h + 0.01, r1 = cone_base_r, r2 = cone_top_r);
            translate([0,0,-1]) cylinder(h = 2, r = socket_open_r);
        }
        // flex slots with pointed (45deg) roofs
        translate([-holder_block_w/2, -slot_w/2, -1])
            cube([holder_block_w, slot_w, 11]);
        translate([-slot_w/2, -holder_block_d/2, -1])
            cube([slot_w, holder_block_d, 11]);
        // roof of X-slot: triangle in (y=lateral, z=vertical), extruded along X
        translate([-holder_block_w/2, 0, 10])
            rotate([0,90,0])
                linear_extrude(height = holder_block_w)
                    polygon(points = [[0,-1],[0,1],[-1,0]]);
        // roof of Y-slot: triangle extruded along Y
        translate([0, -holder_block_d/2, 10])
            rotate([90,0,0])
                linear_extrude(height = holder_block_d)
                    polygon(points = [[-1,0],[1,0],[0,-1]]);
    }
}

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
    holder_part();
} else {
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
    instance("holder", "holder") translate([0,0,holder_bottom_z]) holder_part();
}
