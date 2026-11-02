/* Box with print-in-place hinge - FDM PLA, 0.4mm nozzle, Bambu A1
   Outside closed body 80x60x40 (hinge protrudes ~6 behind), lid 10 of height.
   Hinge along back edge, 5 knuckles + pin printed in place.
   Print pose is lid open 90deg (motion), assembly shows closed.
*/

part = "assembly"; // [box, lid, pin, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters ----
wall_t = 2.4;
boxW = 80; boxD = 60; boxH = 30;
lidH = 10;
R_out = 3.0;
R_bore = 1.9;
R_pin = 1.5;
ax_y = -33;
ax_z = 30; // assembly axis
// knuckle X intervals (assembly X), 5 knuckles, gaps 0.5
b1x0=-40; b1x1=-24.4;
l1x0=-23.9; l1x1=-8.3;
b2x0=-7.8; b2x1=7.8;
l2x0=8.3; l2x1=23.9;
b3x0=24.4; b3x1=40;
kn_len = 15.6;

// ---- printable parts (print orientation, min z = 0) ----
module box() {
    difference() {
        union() {
            // outer body
            translate([-40,-30,0]) cube([80,60,30]);
            // box knuckle barrels
            translate([b1x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=kn_len, $fn=64);
            translate([b2x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=kn_len, $fn=64);
            translate([b3x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=kn_len, $fn=64);
            // box webs y -35..-29.5, z 28..30
            translate([b1x0,-35,28]) cube([kn_len,5.5,2]);
            translate([b2x0,-35,28]) cube([kn_len,5.5,2]);
            translate([b3x0,-35,28]) cube([kn_len,5.5,2]);
            // catch tongue (embedded 0.5)
            translate([-4,27.6,29.5]) cube([8,2.4,3.5]);
        }
        // interior cavity
        translate([-37.6,-27.6,2.4]) cube([75.2,55.2,28.6]);
        // bores (through, extend 0.5 each side)
        translate([b1x0-0.5, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=kn_len+1, $fn=48);
        translate([b2x0-0.5, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=kn_len+1, $fn=48);
        translate([b3x0-0.5, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=kn_len+1, $fn=48);
    }
}

// lid in print orientation: opening up, top plate 0..6 on bed, walls 6..10, hinge axis y=-33 z=10
module lid() {
    difference() {
        union() {
            translate([-40,-30,0]) cube([80,60,10]);
            translate([l1x0, -33, 10]) rotate([0,90,0]) cylinder(r=R_out, h=kn_len, $fn=64);
            translate([l2x0, -33, 10]) rotate([0,90,0]) cylinder(r=R_out, h=kn_len, $fn=64);
            translate([l1x0,-35,8]) cube([kn_len,5.5,2]);
            translate([l2x0,-35,8]) cube([kn_len,5.5,2]);
        }
        // pocket 6..10 open top
        translate([-37.6,-27.6,6]) cube([75.2,55.2,5]);
        // catch slot x -4.3..4.3, y full, z 6.5..11 open top
        translate([-4.3,27.6,6.5]) cube([8.6,2.4,4.5]);
        // bores
        translate([l1x0-0.5, -33, 10]) rotate([0,90,0]) cylinder(r=R_bore, h=kn_len+1, $fn=48);
        translate([l2x0-0.5, -33, 10]) rotate([0,90,0]) cylinder(r=R_bore, h=kn_len+1, $fn=48);
    }
}

// pin vertical, z 0..80
module pin() {
    cylinder(r=R_pin, h=80, $fn=48);
}

// ---- output ----
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 33]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bottom", "-z", 4000]]],
        ["overhangs_allowed", [["hinge barrels bores and webs print without supports - small diameters short bridges", [[-40, -36, 27], [40, -29, 32]]]]],
        ["copies", 1],
        ["details", [
            ["box_wall", "thickness", [41, 0, 15], [-1, 0, 0], 2.4],
            ["box_bottom", "thickness", [0, 0, -1], [0, 0, 1], 2.4],
            ["tongue", "material", [[-4, 27.6, 30], [4, 30, 33]], 0.9],
            ["box_cavity", "void", [[-37.6, -27.6, 2.4], [37.6, 27.6, 30]], 0.95],
            ["box_bore", "hole", [-42, -33, 30], [1, 0, 0], [[0, 3.8], [15, 3.8]]]
        ]]
    ]);
    box();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 13]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["top", "-z", 4000]]],
        ["overhangs_allowed", [["hinge barrels bores and webs print without supports - small diameters short bridges", [[-40, -36, 7], [40, -29, 12]]]]],
        ["copies", 1],
        ["details", [
            ["lid_top", "thickness", [0, 0, -1], [0, 0, 1], 6],
            ["lid_wall", "thickness", [10, 31, 8], [0, -1, 0], 2.4],
            ["slot", "void", [[-4.3, 27.6, 6.5], [4.3, 30, 10]], 0.9],
            ["lid_pocket", "void", [[-37.6, -27.6, 6], [37.6, 27.6, 10]], 0.95],
            ["lid_bore", "hole", [-25, -33, 10], [1, 0, 0], [[0, 3.8], [15.6, 3.8]]]
        ]]
    ]);
    lid();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-1.5, -1.5, 0], [1.5, 1.5, 80]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base", "-z", 5]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["pin_body", "material", [[-1, -1, 1], [1, 1, 79]], 0.95],
            ["pin_thickness", "thickness", [2, 0, 40], [-1, 0, 0], 3.0]
        ]]
    ]);
    pin();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 40]]],
        ["support_faces", [["bottom", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid_inst"], "rotate", [0, -33, 30], [1, 0, 0], [0, 110]]
        ]],
        ["assembly_order", [
            [["box_inst"], [0, 0, 0]],
            [["lid_inst"], [0, 0, -1]],
            [["pin_inst"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.4],
        ["print_pose", [["lid_swing", 90]]],
        ["overhangs_allowed", [
            ["hinge barrels webs and pin gaps print without supports - short self-supporting curves", [[-40, -36, 27], [40, -30, 34]]],
            ["lid rear wall as short 4mm cantilever when printing open", [[-40, -37, 32.5], [40, -33, 36]]],
            ["lid front wall as short 4mm cantilever when printing open", [[-40, -37, 90], [40, -33, 94]]]
        ]]
    ]);
    instance("box_inst", "box", 1) box();
    instance("lid_inst", "lid", 1) translate([0,0,40]) rotate([0,180,0]) lid();
    instance("pin_inst", "pin", 1) translate([-40,-33,30]) rotate([0,90,0]) pin();
}
