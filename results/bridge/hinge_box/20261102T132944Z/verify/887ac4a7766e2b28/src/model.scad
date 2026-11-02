// Box with print-in-place hinge - PLA, Bambu A1, 0.4mm nozzle.
// Body 80x60x30, lid 10mm, closed 80x60x40 (66.3 deep incl hinge).
// Prints in place CLOSED: lid 0.3 above walls/ribs grid, bridges <=10mm.
part = "assembly"; // [box, lid, pin, assembly]
Lx = 80; Ly = 60; base_H = 30; lid_H = 10;
wall = 2.0; bot_t = 2.4; clr_v = 0.3;
outer_r = 3.0; pin_r = 1.5; bore_r = 1.8;
axis_y = 63.3; axis_z = 32.0; cap_t = 0.8;
PX = 0; PY = 63.3; PZ = 32.0;
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
            // cross ribs make ~9x10mm support grid for lid
            for (ry = [12,24,36,48])
                translate([wall, ry, bot_t-0.5]) cube([Lx-2*wall, 2.0, base_H-(bot_t-0.5)]);
            translate([36, 0, base_H-0.5]) cube([8, wall, 1.0]);
            knuckle_outer(8,20,27.5,30.0);
            knuckle_outer(31,49,27.5,30.0);
            knuckle_outer(60,72,27.5,30.0);
            translate([37, 1.8, 28.5]) cube([6, 2.0, 0.7]);
        }
        knuckle_bore(8,20, blind_left=true, blind_right=false);
        knuckle_bore(31,49);
        knuckle_bore(60,72, blind_left=false, blind_right=false);
        translate([37.7, 1.2, 29.5]) cube([4.6, 0.85, 0.9]);
    }
}
module lid_closed() {
    difference() {
        union() {
            translate([0, 0, base_H+clr_v]) cube([Lx, Ly, lid_H]);
            translate([37, 2.3, 29.5]) cube([6, 1.5, 1.0]);
            translate([38, 1.5, 29.8]) cube([4, 0.8, 0.3]);
            knuckle_outer(20.5,30.5,30.3,35.0);
            knuckle_outer(49.5,59.5,30.3,35.0);
        }
        knuckle_bore(20.5,30.5);
        knuckle_bore(49.5,59.5);
    }
}
// lid exported in print pose: rotated open 90deg about hinge, resting on bed
module lid() {
    translate([0, 0, -29.3])
        translate([PX,PY,PZ]) rotate([-90,0,0]) translate([-PX,-PY,-PZ])
            lid_closed();
}
module pin() {
    translate([40, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=pin_r, h=61.4, center=true);
}
module assembly() {
    instance("base", "box") box();
    // cover: lid part moved back to closed pose (inverse of print rotation)
    instance("cover", "lid")
        translate([PX,PY,PZ]) rotate([90,0,0]) translate([-PX,-PY,-PZ]) translate([0,0,29.3])
            lid();
    instance("hinge_pin", "pin") pin();
}
box_min = [0,0,0]; box_max = [80, 66.3, 35];
lid_min = [0,60.8,0]; lid_max = [80,71.6,66.3];
pin_min = [9.3,61.8,30.5]; pin_max = [70.7,64.8,33.5];
asm_min = [0,0,0]; asm_max = [80,66.3,40.3];
if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [box_min, box_max]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [["hinge_knuckles", [[8,58.5,27.5],[72,66.3,35]]],["catch_groove", [[37.7,1.2,29.5],[42.3,2.05,30.4]]],["catch_shelf", [[37,1.8,28.5],[43,3.8,29.2]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "material", [[0,0,25],[2,2,29]], 0.9],
            ["cavity", "void", [[25,15,10],[30,20,25]], 0.95],
            ["rib", "material", [[11.14,28,28],[13.14,32,30]], 0.85],
            ["hinge_bore", "hole", [20.3,63.3,32], [-1,0,0], [[0,3.6],[5,3.6],[10,3.6]]],
            ["wall_thickness", "thickness", [-1,30,29], [1,0,0], 2.0],
            ["floor_thickness", "thickness", [40,30,-1], [0,0,1], 2.4],
            ["catch_groove", "void", [[37.7,1.2,29.5],[42.3,2.05,30.4]], 0.85],
            ["catch_shelf", "material", [[37,1.8,28.5],[43,3.8,29.2]], 0.9],
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
        ["overhangs_allowed", [["hinge_knuckles", [[20.5,60.8,29.3],[30.5,71.6,66.0]]],["lid_edges", [[0,60.8,0],[80,71.6,66.3]]]]],
        ["copies", 1],
        ["details", [
            ["top", "material", [[10,62.0,20.0],[20,64.0,30.0]], 0.9],
            ["lip", "material", [[37,62.5,64.0],[43,64.0,65.5]], 0.7],
            ["catch_bump", "material", [[38,63.0,64.5],[42,64.0,65.0]], 0.5],
            ["hinge_bore", "hole", [[20.2,63.3,32]], [1,0,0], [[0,3.6],[5,3.6],[9,3.6]]],
            ["top_thickness", "thickness", [[40,63.0,50.0]], [0,-1,0], 10.0],
            ["hinge_view", "view", [[20.5,60.8,29.3],[30.5,71.6,40.0]]],
            ["catch_view", "view", [[37,60.8,60.0],[43,66.0,66.3]]]
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
            ["lid_swing", ["cover"], "rotate", [0,63.3,32], [-1,0,0], [0,110], ["flex", [["cover","base",1.0,"front_catch_snap"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0,0,0]],
            [["cover"], [0,0,10]],
            [["hinge_pin"], [-10,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [["hinge", [[8,58.5,27.5],[72,66.3,36.5]]],["base_catch", [[37,1.2,28.5],[43,3.8,30.4]]]]]
    ]);
    assembly();
}
