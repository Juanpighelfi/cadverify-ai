// Phone stand on a ball joint — PLA, no supports, Bambu Lab A1 0.4mm
/* [Parts] */
part = "assembly"; // [assembly:Assembly, base:Base, holder:Holder]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
base_d = 90; base_r = 45; base_t = 6;
ball_d = 20; ball_r = 10; ball_cz = 38;
post_r_base = 12;
post_r_neck = 4.0;
post_r_top = 5.5;
post_top_z = ball_cz - sqrt(ball_r*ball_r - post_r_top*post_r_top); // 29.648
post_neck_z = post_top_z - 2; // collar 2mm

holder_W = 88; holder_x0 = -44; holder_x1 = 44;
holder_y0 = -11; holder_y1 = 12;
holder_back_y0 = -11; holder_back_y1 = -5;
holder_front_y0 = 7; holder_front_y1 = 12;
shelf_t = 20;
back_h = 65;
holder_H = shelf_t + back_h; // 85
socket_R = 10;
socket_ro = 9.5;
socket_cz = sqrt(socket_R*socket_R - socket_ro*socket_ro); // 3.122
slot_w = 4; slot_h = 12;

assembly_top = ball_cz - socket_cz + holder_H;

module base_part() {
    union() {
        cylinder(r = base_r, h = base_t, $fn = 128);
        translate([0,0,base_t-1])
            cylinder(r1 = post_r_base, r2 = post_r_neck, h = (post_neck_z+1)-(base_t-1), $fn = 64);
        translate([0,0,post_neck_z])
            cylinder(r = post_r_top, h = (post_top_z+2)-post_neck_z, $fn = 64);
        translate([0,0,ball_cz])
            sphere(r = ball_r, $fn = 96);
    }
}

module holder_part() {
    difference() {
        union() {
            // shelf block
            translate([holder_x0, holder_y0, 0])
                cube([holder_W, holder_y1-holder_y0, shelf_t]);
            // back plate
            translate([holder_x0, holder_back_y0, 0])
                cube([holder_W, holder_back_y1-holder_back_y0, holder_H]);
            // front lip (overlap 1mm)
            translate([holder_x0, holder_front_y0, shelf_t-1])
                cube([holder_W, holder_front_y1-holder_front_y0, 16]);
            // side walls (overlap 1mm)
            translate([holder_x0, holder_y0, shelf_t-1])
                cube([3, holder_y1-holder_y0, 16]);
            translate([holder_x1-3, holder_y0, shelf_t-1])
                cube([3, holder_y1-holder_y0, 16]);
        }
        // socket sphere
        translate([0, 0, socket_cz])
            sphere(r = socket_R, $fn = 96);
        // X slot (full width, open bottom+sides)
        translate([-45, -slot_w/2, -1])
            cube([90, slot_w, slot_h+1]);
        // Y slot (full depth, open bottom+sides)
        translate([-slot_w/2, -12, -1])
            cube([slot_w, 25, slot_h+1]);
    }
}

// ---------- specs ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 48]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["foot", "-z", 5000]]],
        ["overhangs_allowed", [["ball underside short lip", [[-11, -11, 28], [11, 11, 39]]]]],
        ["copies", 1],
        ["details", [
            ["base_plate", "material", [[-45, -45, 0], [45, 45, 6]], 0.7],
            ["ball", "material", [[-10, -10, 28], [10, 10, 48]], 0.4],
            ["post_core", "material", [[-2, -2, 10], [2, 2, 20]], 0.9],
            ["base_thickness", "thickness", [30, 0, -1], [0, 0, 1], 6],
            ["ball_dia", "thickness", [20, 0, 38], [-1, 0, 0], 20]
        ]]
    ]);
    base_part();
} else if (part == "holder") {
    echo(cadverify_spec = [
        ["bounds", [[-44, -11, 0], [44, 12, 85]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bottom", "-z", 500]]],
        ["overhangs_allowed", [["socket and slots short bridges", [[-45, -12, -1], [45, 13, 14]]]]],
        ["copies", 1],
        ["details", [
            ["phone_slot", "void", [[-41, -5, 20], [41, 7, 35]], 0.9],
            ["socket_cavity", "void", [[-3, -3, 2], [3, 3, 8]], 0.9],
            ["snap_slot", "void", [[-30, -1, 1], [30, 1, 9]], 0.9],
            ["side_wall", "material", [[-43.5, -5, 25], [-41.5, 5, 30]], 0.9],
            ["back_wall", "thickness", [0, -12, 50], [0, 1, 0], 6],
            ["shelf_floor", "thickness", [30, 5, -1], [0, 0, 1], 20]
        ]]
    ]);
    holder_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 119.88]]],
        ["support_faces", [["desk", "-z", 5000]]],
        ["motions", [
            ["tilt", ["holder"], "rotate", [0, 0, 38], [0, 1, 0], [-30, 30]],
            ["turn", ["holder"], "rotate", [0, 0, 38], [0, 0, 1], [0, 360]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["holder"], [0, 0, -1], ["flex", [["holder", "base", 1.0, "snap over ball"]]]]
        ]],
        ["held", ["holder"]]
    ]);
    instance("base", "base") base_part();
    instance("holder", "holder") translate([0, 0, ball_cz - socket_cz]) holder_part();
}
