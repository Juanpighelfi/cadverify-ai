// Box with print-in-place hinge - PLA, Bambu A1, 0.4mm nozzle.
// Body 80x60x30, lid 10mm, closed 80x66.3x40.3 incl hinge.
// Prints in place CLOSED; lid bridges a 5.5mm rib grid; swing 0-110deg.
part = "assembly"; // [box, lid, pin, assembly]
Lx = 80; Ly = 60; base_H = 30; lid_H = 10;
wall = 2.0; bot_t = 2.4; clr_v = 0.3;
outer_r = 3.0; pin_r = 1.5; bore_r = 1.8;
axis_y = 63.3; axis_z = 32.0; cap_t = 0.8;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
$fn = 64;
module knuckle_outer(x0,x1,web_z0,web_z1) {
    xc = (x0+x1)/2; len = x1-x0;
    translate([xc, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=outer_r, h=len, center=true);
    translate([x0, 58.5, web_z0]) cube([x1-x0, 5.2, web_z1-web_z0]);
}
module knuckle_bore(x0,x1,blind_left=false, blind_right=false) {
    bx0 = blind_left ? x0+cap_t : x0-0.05;
    bx1 = blind_right ? x1-cap_t : x1+0.05;
    translate([(bx0+bx1)/2, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=bore_r, h=bx1-bx0, center=true);
}
module box() {
    difference() {
        union() {
            cube([Lx, Ly, bot_t]);
            translate([0, 0, bot_t-0.5]) cube([Lx, wall, base_H-(bot_t-0.5)]);
            translate([0, Ly-wall, bot_t-0.5]) cube([Lx, wall, base_H-(bot_t-0.5)]);
            translate([0, wall-0.1, bot_t-0.5]) cube([wall, Ly-2*wall+0.2, base_H-(bot_t-0.5)]);
            translate([Lx-wall, wall-0.1, bot_t-0.5]) cube([wall, Ly-2*wall+0.2, base_H-(bot_t-0.5)]);
            // lid support grid: 1.5 ribs, 5.5 gaps (bridge 7.8mm)
            for (rx = [4,11,18,25,32,39,46,53,60,67,74])
                translate([rx, wall, bot_t-0.5]) cube([1.5, Ly-2*wall, base_H-(bot_t-0.5)]);
            for (ry = [6,13,20,27,34,41,48,55])
                translate([wall, ry, bot_t-0.5]) cube([Lx-2*wall, 1.5, base_H-(bot_t-0.5)]);
            knuckle_outer(8,20,27.5,30.0);
            knuckle_outer(31,49,27.5,30.0);
            knuckle_outer(60,72,27.5,30.0);
        }
        knuckle_bore(8,20, blind_left=true, blind_right=false);
        knuckle_bore(31,49);
        knuckle_bore(60,72, blind_left=false, blind_right=false);
        // catch notch in front wall inner face, open at top
        translate([37.7, 1.3, 29.0]) cube([4.6, 0.7, 1.0]);
    }
}
module lid_closed() {
    difference() {
        union() {
            translate([0, 0, base_H+clr_v]) cube([Lx, Ly, lid_H]);
            // hanging lip inside front wall (0.3 off the wall face)
            translate([37, 2.3, 29.4]) cube([6, 0.6, 1.1]);
            // catch bump into the notch (0.3+ clear all around)
            translate([38, 1.65, 29.35]) cube([4, 0.7, 0.3]);
            knuckle_outer(20.5,30.5,30.3,35.0);
            knuckle_outer(49.5,59.5,30.3,35.0);
        }
        knuckle_bore(20.5,30.5);
        knuckle_bore(49.5,59.5);
    }
}
// lid prints standing on its front face (tall 66.3, stable 80-wide base)
module lid() {
    translate([0,63.3,63.3]) rotate([90,0,0]) translate([0,-63.3,-32]) lid_closed();
}
module pin() {
    translate([40, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=pin_r, h=61.4, center=true);
}
module assembly() {
    instance("base", "box") box();
    instance("cover", "lid")
        translate([0,63.3,32]) rotate([-90,0,0]) translate([0,-63.3,-63.3]) lid();
    instance("hinge_pin", "pin") pin();
}
box_min = [0,0,0]; box_max = [80, 66.3, 35];
lid_min = [0,55.0,0]; lid_max = [80,65.95,66.3];
pin_min = [9.3,61.8,30.5]; pin_max = [70.7,64.8,33.5];
asm_min = [0,0,0]; asm_max = [80,66.3,40.3];
if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [box_min, box_max]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [["hinge_knuckles", [[8,58.5,27.5],[72,66.3,35]]],["catch_notch", [[37.7,1.3,29.0],[42.3,2.0,30.0]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "material", [[0,0,25],[2,2,29]], 0.9],
            ["cavity", "void", [[6,8,10],[10,12,25]], 0.95],
            ["rib", "material", [[4,22,28],[5.5,26,30]], 0.85],
            ["hinge_bore", "hole", [20.3,63.3,32], [-1,0,0], [[0,3.6],[5,3.6],[10,3.6]]],
            ["wall_thickness", "thickness", [-1,30,29], [1,0,0], 2.0],
            ["floor_thickness", "thickness", [40,30,-1], [0,0,1], 2.4],
            ["catch_notch", "void", [[37.7,1.3,29.0],[42.3,2.0,30.0]], 0.85],
            ["hinge_view", "view", [[8,58.5,27.5],[72,66.3,35]]]
        ]]
    ]);
    box();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [lid_min, lid_max]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed","-z",700]]],
        ["overhangs_allowed", [["lid_knuckles", [[20.5,60.3,58],[30.5,66.3,64]]],["lid_knuckles2", [[49.5,60.3,58],[59.5,66.3,64]]],["lid_catch", [[37,64.8,1.8],[43,65.95,2.8]]]]],
        ["copies", 1],
        ["details", [
            ["top", "material", [[10,57.3,10],[20,63.3,30]], 0.9],
            ["lip", "material", [[37,64.8,2.3],[43,65.9,2.9]], 0.7],
            ["catch_bump", "material", [[38,65.65,1.65],[42,65.95,2.35]], 0.5],
            ["hinge_bore", "hole", [20.2,63.3,63.3], [1,0,0], [[0,3.6],[5,3.6],[9,3.6]]],
            ["top_thickness", "thickness", [40,54,30], [0,1,0], 10.0],
            ["hinge_view", "view", [[20.5,60.3,58],[30.5,66.3,68]]],
            ["catch_view", "view", [[37,64.8,1.5],[43,65.95,3.0]]]
        ]]
    ]);
    lid();
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [pin_min, pin_max]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [["pin_underside", [[9.3,61.8,30.5],[70.7,64.8,31.2]]]]],
        ["copies", 1],
        ["details", [
            ["pin_body", "material", [[30,62.3,31.0],[40,64.3,33.0]], 0.7],
            ["pin_dia", "thickness", [40,63.3,34], [0,0,-1], 3.0],
            ["pin_view", "view", [[9.3,61.8,30.5],[20,64.8,33.5]]]
        ]]
    ]);
    pin();
} else {
    echo(cadverify_spec = [
        ["bounds", [asm_min, asm_max]],
        ["support_faces", [["bed","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["cover"], "rotate", [0,63.3,32], [-1,0,0], [0,110], ["flex", [["cover","base",0.5,"front_catch_snap"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0,0,0]],
            [["cover"], [0,0,-10]],
            [["hinge_pin"], [-10,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [["hinge", [[8,58.5,27.5],[72,66.3,36.5]]],["in_place_catch", [[37.7,1.3,28.9],[43,2.9,29.8]]],["lid_bottom_bridge", [[2,2,30.0],[78,58,30.6]]]]]
    ]);
    assembly();
}
