// Box with print-in-place hinge - FDM PLA, Bambu A1, 0.4mm nozzle
// Outside closed ~80x60x40, lid ~10mm, hinge along back, front catch.
// Prints closed, lid swings 100deg+.
Lx = 80; Ly = 60; base_H = 30; lid_H = 10;
wall = 2.0; bot_t = 2.4; clr_v = 0.3;
outer_r = 3.0; pin_r = 1.5; bore_r = 1.8;
axis_y = 63.3; axis_z = 32.0; cap_t = 0.8;
part = "assembly";
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
            for (rx = [11.14,22.28,33.42,44.56,55.7,66.84])
                translate([rx, wall, bot_t-0.5]) cube([2.0, Ly-2*wall, base_H-(bot_t-0.5)]);
            translate([36, 0, base_H-0.5]) cube([8, wall, 1.0]);
            knuckle_outer(8,20,27.5,32.5);
            knuckle_outer(31,49,27.5,32.5);
            knuckle_outer(60,72,27.5,32.5);
        }
        knuckle_bore(8,20, blind_left=true, blind_right=false);
        knuckle_bore(31,49);
        knuckle_bore(60,72, blind_left=false, blind_right=true);
        translate([37.7, 1.2, 27.5]) cube([4.6, 0.8, 2.0]);
    }
}
module lid() {
    lid_z0 = base_H + clr_v;
    difference() {
        union() {
            translate([0, 0, lid_z0]) cube([Lx, Ly, lid_H]);
            translate([37, 2.3, 27.3]) cube([6, 1.5, 3.2]);
            translate([38, 1.4, 28.0]) cube([4, 0.9, 1.0]);
            translate([38, 1.8, 28.2]) cube([4, 0.5, 0.6]);
            knuckle_outer(20.5,30.5,30.0,35.0);
            knuckle_outer(49.5,59.5,30.0,35.0);
        }
        knuckle_bore(20.5,30.5);
        knuckle_bore(49.5,59.5);
    }
}
module pin() {
    translate([40, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=pin_r, h=61.4, center=true);
}
module assembly() {
    instance("base", "box") box();
    instance("cover", "lid") lid();
    instance("hinge_pin", "pin") pin();
}
box_min = [0,0,0]; box_max = [80, 66.3, 35];
lid_min = [0,0,27.3]; lid_max = [80,66.3,40.3];
pin_min = [8.6,61.8,30.5]; pin_max = [71.4,64.8,33.5];
asm_min = [0,0,0]; asm_max = [80,66.3,40.3];
if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [box_min, box_max]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [["hinge_knuckles", [[8,58.5,27.5],[72,66.3,35]]],["catch_groove", [[37.7,1.2,27.5],[42.3,2.0,29.5]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "material", [[0,0,25],[2,2,29]], 0.9],
            ["cavity", "void", [[15,10,10],[20,15,25]], 0.95],
            ["rib", "material", [[11.14,28,28],[13.14,32,30]], 0.85],
            ["hinge_bore", "hole", [20.3,63.3,32], [-1,0,0], [[0,3.6],[5,3.6],[10,3.6]]],
            ["wall_thickness", "thickness", [-1,30,29], [1,0,0], 2.0],
            ["floor_thickness", "thickness", [40,30,-1], [0,0,1], 2.4],
            ["catch_groove", "void", [[37.7,1.2,27.5],[42.3,2.0,29.5]], 0.9],
            ["hinge_view", "view", [[8,58.5,27.5],[72,66.3,35]]]
        ]]
    ]);
    box();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [lid_min, lid_max]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", []],
        ["overhangs_allowed", [["hinge_knuckles", [[20.5,58.5,29],[59.5,66.3,36.5]]],["catch_bump", [[38,1.4,28.0],[42,2.3,29.0]]],["lid_bottom_bridge", [[2,2,30.0],[78,58,30.6]]]]],
        ["copies", 1],
        ["details", [
            ["top", "material", [[10,10,39],[20,20,40.3]], 0.95],
            ["lip", "material", [[37,2.3,27.3],[43,3.8,30.3]], 0.85],
            ["catch_bump", "material", [[38,1.4,28.0],[42,2.3,29.0]], 0.7],
            ["hinge_bore", "hole", [20.2,63.3,32], [1,0,0], [[0,3.6],[5,3.6],[9,3.6]]],
            ["top_thickness", "thickness", [40,30,41], [0,0,-1], 10.0],
            ["hinge_view", "view", [[20.5,58.5,29],[30.5,66.3,35]]],
            ["catch_view", "view", [[37,1.4,27.3],[43,3.8,30.3]]]
        ]]
    ]);
    lid();
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [pin_min, pin_max]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [["pin_underside", [[8.6,61.8,30.5],[71.4,64.8,31.2]]]]],
        ["copies", 1],
        ["details", [
            ["pin_body", "material", [[30,62.3,31.0],[40,64.3,33.0]], 0.7],
            ["pin_dia", "thickness", [40,63.3,34], [0,0,-1], 3.0],
            ["pin_view", "view", [[8.6,61.8,30.5],[20,64.8,33.5]]]
        ]]
    ]);
    pin();
} else {
    echo(cadverify_spec = [
        ["bounds", [asm_min, asm_max]],
        ["support_faces", [["bed","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["cover"], "rotate", [0,63.3,32], [-1,0,0], [0,110], ["flex", [["cover","base",0.6,"front_catch_snap"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0,0,0]],
            [["hinge_pin"], [-10,0,0]],
            [["cover"], [0,0,10]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [["hinge", [[8,58.5,27.5],[72,66.3,36.5]]],["catch_groove", [[37.7,1.2,27.5],[42.3,2.0,29.5]]],["lid_bottom_bridge", [[2,2,30.0],[78,58,30.6]]]]]
    ]);
    assembly();
}
