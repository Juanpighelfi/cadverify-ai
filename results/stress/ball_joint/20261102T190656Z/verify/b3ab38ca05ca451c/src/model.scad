/* Phone stand on a ball joint - PLA, 0.4mm nozzle, no supports */
part = "assembly"; // [assembly, base, holder]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- parameters (mm) ---------- */
base_r = 45; base_h = 6;
ball_r = 10;
ball_cz = 38;              // ball center height (base bottom z=0)
neck_r = 6;
neck_top_z = 30;
post_r_bot = 10;

socket_r = 9.8;            // 0.2 grip press on the ball
socket_open_r = 9.75;      // snap lip (0.25 transit over equator)
dz_open = sqrt(socket_r*socket_r - socket_open_r*socket_open_r);
flat_dz = 10.2;
cone_base_dz = socket_r*cos(45);
cone_base_r = socket_r*sin(45);
cone_h = flat_dz - cone_base_dz;
cone_top_r = cone_base_r - cone_h;

holder_block_w = 90; holder_block_d = 34; holder_block_h = 28;
holder_bottom_z = ball_cz - dz_open;
groove_w = 84; groove_d = 12;
groove_bottom_z = 18;
back_t = 6; back_h = 75;
front_t = 4; front_h = 12;

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
            // base block
            translate([-holder_block_w/2, -holder_block_d/2, 0])
                cube([holder_block_w, holder_block_d, holder_block_h]);
            // back plate (phone rest)
            translate([-holder_block_w/2, -holder_block_d/2, holder_block_h])
                cube([holder_block_w, back_t, back_h]);
            // front lip
            translate([-holder_block_w/2, holder_block_d/2 - front_t, holder_block_h])
                cube([holder_block_w, front_t, front_h]);
            // gussets: hull wedges clear of the phone groove (groove ends at |x|=42)
            for (sx = [-1,1]) {
                x0 = (sx > 0) ? 42 : -45;
                hull() {
                    translate([x0, -11, 28]) cube([3,2,2]);
                    translate([x0, 2, 28]) cube([3,2,2]);
                    translate([x0, -11, 46]) cube([3,2,2]);
                }
            }
        }
        // phone groove (open top, flush cut so gusset feet stay supported)
        translate([-groove_w/2, -groove_d/2, groove_bottom_z])
            cube([groove_w, groove_d, holder_block_h - groove_bottom_z]);
        // socket void: sphere up to 45 deg + 45 deg cone + mouth
        union() {
            intersection() {
                translate([0,0,dz_open]) sphere(r = socket_r);
                translate([-20,-20,-1]) cube([40,40,(dz_open+cone_base_dz)+1]);
            }
            translate([0,0,dz_open+cone_base_dz])
                cylinder(h = cone_h + 0.01, r1 = cone_base_r, r2 = cone_top_r);
            translate([0,0,-1]) cylinder(h = 2, r = socket_open_r);
        }
        // flex slots, blind (2 mm bridges on top, declared)
        translate([-15,-1,-1]) cube([30,2,10]);
        translate([-1,-13,-1]) cube([2,26,10]);
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
        ["overhangs_allowed", [
            ["socket_ceiling", [[-5,-5,9],[5,5,13]]],
            ["slot_top_x", [[-16,-2,8],[16,2,10]]],
            ["slot_top_y", [[-2,-14,8],[2,14,10]]]
        ]],
        ["copies", 1],
        ["details", [
            ["cradle_slot", "void", [[-42,-6,18],[42,6,28]], 0.9],
            ["socket", "void", [[-4,-4,2],[4,4,7]], 0.9],
            ["mouth", "void", [[-8,-8,0],[8,8,1]], 0.8],
            ["lip", "material", [[10,2,0],[14,6,2]], 0.9],
            ["flex_slot", "void", [[-15,-1,0],[15,1,8]], 0.9],
            ["back_wall", "thickness", [0,-22,60], [0,1,0], 6],
            ["front_lip", "material", [[-40,13.5,29],[40,16.5,39]], 0.9]
        ]]
    ]);
    holder_part();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-45,-45,0],[45,45,140.01]]],
        ["support_faces", [["base_bottom","-z",6000]]],
        ["allowed_interferences", [["base","holder","ball press fit"]]],
        ["motions", [
            ["tilt", ["holder"], "rotate", [0,0,38], [1,0,0], [-30,30]],
            ["turn", ["holder"], "rotate", [0,0,38], [0,0,1], [0,360]]
        ]],
        ["assembly_order", [
            [["base"], [0,0,0]],
            [["holder"], [0,0,-1]]
        ]]
    ]);
    instance("base", "base") base_part();
    instance("holder", "holder") translate([0,0,holder_bottom_z]) holder_part();
}
