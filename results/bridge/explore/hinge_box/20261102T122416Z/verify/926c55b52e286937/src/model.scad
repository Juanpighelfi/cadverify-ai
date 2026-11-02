/* Box with a print-in-place hinge - FDM PLA, 0.4 mm nozzle, Bambu A1.
   Closed body 80x60x40 (hinge knuckles protrude ~6.5 behind, pin head 1 to
   the side), lid 10 of that height. Hinge along the back edge: 7 knuckles
   alternating box/lid around a pin printed in place (0.6 radial/axial gaps,
   0.5 end gaps, blind cap + flared head keep the pin captive). The lid's
   top-rear edge is a 45 deg bevel so the open lid prints support-free; a
   tongue-and-slot catch at the front keeps the lid shut.
   The product prints in one job in the print pose (lid open 90 deg, the
   lid_swing motion); the assembly shows the closed box.
*/

part = "assembly"; // [box, lid, pin, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters ----
wall_t = 2.4;
R_out = 3.0;
R_bore = 2.1;
R_pin = 1.5;
ax_y = -33.5;
ax_z = 30; // assembly hinge axis
// knuckle X intervals (0.6 axial gaps), symmetric about x=0
B1x0=-40;    B1x1=-27.275;
L1x0=-26.675; L1x1=-18.175;
B2x0=-17.575; B2x1=-4.85;
L2x0=-4.25;   L2x1=4.25;
B3x0=4.85;    B3x1=17.575;
L3x0=18.175;  L3x1=26.675;
B4x0=27.275;  B4x1=40;

// ---- printable parts (print orientation, min z = 0) ----
module box() {
    difference() {
        union() {
            // outer body
            translate([-40,-30,0]) cube([80,60,30]);
            // box knuckle barrels (r3 about axis)
            translate([B1x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=B1x1-B1x0, $fn=64);
            translate([B2x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=B2x1-B2x0, $fn=64);
            translate([B3x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=B3x1-B3x0, $fn=64);
            translate([B4x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_out, h=B4x1-B4x0, $fn=64);
            // box webs (barrel rear to body, embedded 0.5)
            translate([B1x0,-36.5,28]) cube([B1x1-B1x0,7,2]);
            translate([B2x0,-36.5,28]) cube([B2x1-B2x0,7,2]);
            translate([B3x0,-36.5,28]) cube([B3x1-B3x0,7,2]);
            translate([B4x0,-36.5,28]) cube([B4x1-B4x0,7,2]);
            // catch tongue (0.3 back/side clearances to slot, front flush)
            translate([-4,27.9,29.5]) cube([8,2.1,3.5]);
        }
        // interior cavity
        translate([-37.6,-27.6,2.4]) cube([75.2,55.2,27.6]);
        // bores: B1 blind (0.5 cap outside -> captive pin), B2/B3/B4 through
        translate([-39.5, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=12.725, $fn=48);
        translate([-18.075, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=13.725, $fn=48);
        translate([4.35, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=13.725, $fn=48);
        translate([26.775, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=R_bore, h=13.725, $fn=48);
    }
}

// lid in print orientation: opening up, top plate 0..6 on bed, walls 6..10,
// hinge axis y=-33.5 z=10
module lid() {
    difference() {
        union() {
            translate([-40,-30,0]) cube([80,60,10]);
            translate([L1x0, -33.5, 10]) rotate([0,90,0]) cylinder(r=R_out, h=L1x1-L1x0, $fn=64);
            translate([L2x0, -33.5, 10]) rotate([0,90,0]) cylinder(r=R_out, h=L2x1-L2x0, $fn=64);
            translate([L3x0, -33.5, 10]) rotate([0,90,0]) cylinder(r=R_out, h=L3x1-L3x0, $fn=64);
            translate([L1x0,-35,8]) cube([L1x1-L1x0,5.5,2]);
            translate([L2x0,-35,8]) cube([L2x1-L2x0,5.5,2]);
            translate([L3x0,-35,8]) cube([L3x1-L3x0,5.5,2]);
        }
        // pocket 6..10, open top
        translate([-37.6,-27.6,6]) cube([75.2,55.2,4]);
        // catch slot, open at rim top
        translate([-4.3,27.6,6.5]) cube([8.6,2.4,4]);
        // bores, through
        translate([-27.175, -33.5, 10]) rotate([0,90,0]) cylinder(r=R_bore, h=9.5, $fn=48);
        translate([-4.75, -33.5, 10]) rotate([0,90,0]) cylinder(r=R_bore, h=9.5, $fn=48);
        translate([17.675, -33.5, 10]) rotate([0,90,0]) cylinder(r=R_bore, h=9.5, $fn=48);
        // rear-bottom 4x6 chamfer (34deg slope, no overhang): closed top-rear edge
        hull() {
            translate([-41,-30.1,0]) cube([82,0.1,6]);
            translate([-41,-30,0]) cube([82,4,0.1]);
        }
    }
}

// pin prints in place lying in the hinge (vertical when exported alone)
module pin() {
    cylinder(r=R_pin, h=79, $fn=48);
    translate([0,0,79]) cylinder(r1=R_pin, r2=2.5, h=1, $fn=48);
}

// ---- output ----
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36.5, 0], [40, 30, 33]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bottom", "-z", 4000]]],
        ["overhangs_allowed", [["hinge barrels bores and webs print without supports - small diameters short bridges", [[-40, -37, 26], [40, -29, 33]]]]],
        ["copies", 1],
        ["details", [
            ["box_wall", "thickness", [41, 0, 15], [-1, 0, 0], 2.4],
            ["box_bottom", "thickness", [0, 0, -1], [0, 0, 1], 2.4],
            ["tongue", "material", [[-4, 27.9, 29.5], [4, 30, 33]], 0.9],
            ["box_cavity", "void", [[-37.6, -27.6, 2.4], [37.6, 27.6, 30]], 0.95],
            ["box_bore", "hole", [-18.7, -33.5, 30], [1, 0, 0], [[0, 4.2], [10, 4.2]]]
        ]]
    ]);
    box();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36.5, 0], [40, 30, 13]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["top", "-z", 4000]]],
        ["overhangs_allowed", [["hinge barrels bores and webs print without supports - small diameters short bridges", [[-40, -37, 6], [40, -29, 13]]]]],
        ["copies", 1],
        ["details", [
            ["lid_top", "thickness", [0, 0, -1], [0, 0, 1], 6],
            ["lid_wall", "thickness", [10, 31, 8], [0, -1, 0], 2.4],
            ["slot", "void", [[-4.3, 27.6, 6.5], [4.3, 30, 10]], 0.9],
            ["lid_pocket", "void", [[-37.6, -27.6, 6], [37.6, 27.6, 10]], 0.95],
            ["lid_bore", "hole", [-5.3, -33.5, 10], [1, 0, 0], [[0, 4.2], [8, 4.2]]]
        ]]
    ]);
    lid();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-2.5, -2.5, 0], [2.5, 2.5, 80]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base", "-z", 5]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["pin_body", "material", [[-1, -1, 1], [1, 1, 78]], 0.95],
            ["pin_thickness", "thickness", [2, 0, 40], [-1, 0, 0], 3.0]
        ]]
    ]);
    pin();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36.5, 0], [41, 30, 40]]],
        ["support_faces", [["bottom", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid_inst"], "rotate", [0, -33.5, 30], [1, 0, 0], [0, 110]]
        ]],
        ["assembly_order", [
            [["box_inst"], [0, 0, 0]],
            [["lid_inst"], [0, 0, -1]],
            [["pin_inst"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.4],
        ["print_pose", [["lid_swing", 100]]],
        ["overhangs_allowed", [
            ["knuckle barrels webs and pin print with half-mm gaps, short bridges", [[-40, -37, 26], [41.5, -30, 34]]],
            ["lid rear face and rim print tilted past horizontal, short cantilever", [[-40, -46, 30], [40, -31, 43]]],
            ["lid standing walls and top edge when open, short end bridges", [[-40, -46, 80], [40, -30, 96]]]
        ]]
    ]);
    instance("box_inst", "box", 1) box();
    instance("lid_inst", "lid", 1) translate([0,0,40]) rotate([0,180,0]) lid();
    instance("pin_inst", "pin", 1) translate([-39,-33.5,30]) rotate([0,90,0]) pin();
}
