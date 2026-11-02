// Box with print-in-place hinge - PLA, 0.4mm nozzle, Bambu A1
// Closed box 80x60x40. Print orientation = assembly orientation (closed), +Z up.
part = "assembly"; // [assembly, base, lid, pin]
cadverify_only = "";

W = 80; D = 60;
effector_gap = 0.3;
rear_gap0 = 0.3; rear_gap1 = 0.35;
H_base_top = 29.25;
H_lid_bot = 30.0;
Notch_y0=0.35; Notch_y1=1.65;
H_total = 40.0;
T_wall = 2.0;
T_bot = 2.0;
T_top = 2.5;
Top_bot = 37.5;

Ax_y = 56; Ax_z = 29.8;
Pin_r = 2.0;
Hole_r = 2.3;
Knu_r = 4.0;
Knu_bot = 25.8;
Knu_top = 33.8;
K0x0=10; K0x1=21.6;
K1x0=22.1; K1x1=33.7;
K2x0=34.2; K2x1=45.8;
K3x0=46.3; K3x1=57.9;
K4x0=58.4; K4x1=70;
Pin_x0 = 11.5; Pin_x1 = 79.5;

Tab_x0=36; Tab_x1=44; Tab_y0=0.7; Tab_y1=1.3; Tab_z0=29.5; Tab_z1=33.5;
Notch_x0=35.5; Notch_x1=44.5; Notch_y0=0.45; Notch_y1=1.55; Notch_z1=34.4;

$fn = 64;

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
module knuckle_x(x0, x1) {
    translate([x0, Ax_y, Ax_z]) rotate([0,90,0]) cylinder(h=x1-x0, r=Knu_r);
}
module hole_x(x0, x1) {
    translate([x0, Ax_y, Ax_z]) rotate([0,90,0]) cylinder(h=x1-x0, r=Hole_r);
}

module base() {
    difference() {
        union() {
            cube([W, D, T_bot]);
            cube([W, T_wall, H_base_top]);
            translate([0,0,0]) cube([T_wall, D, H_base_top]);
            translate([W-T_wall,0,0]) cube([T_wall, D, H_base_top]);
            translate([0,D-T_wall,0]) cube([W, T_wall, H_base_top]);
            knuckle_x(K0x0,K0x1);
            knuckle_x(K2x0,K2x1);
            knuckle_x(K4x0,K4x1);
            translate([Tab_x0, Tab_y0, Tab_z0]) cube([Tab_x1-Tab_x0, Tab_y1-Tab_y0, Tab_z1-Tab_z0]);
        }
        translate([K1x0-0.4, D-T_wall-0.1, Knu_bot-0.3]) cube([(K1x1+0.4)-(K1x0-0.4), T_wall+0.2, H_base_top-(Knu_bot-0.3)+0.1]);
        translate([K3x0-0.4, D-T_wall-0.1, Knu_bot-0.3]) cube([(K3x1+0.4)-(K3x0-0.4), T_wall+0.2, H_base_top-(Knu_bot-0.3)+0.1]);
        hole_x(11, K0x1+0.1);
        hole_x(K2x0-0.1, K2x1+0.1);
        hole_x(K4x0-0.1, K4x1+0.1);
        hole_x(78, 80.1);
    }
}

module lid() {
    difference() {
        union() {
            translate([0,0,Top_bot]) cube([W, D, T_top]);
            translate([0,0,H_lid_bot]) cube([W, T_wall, H_total-H_lid_bot]);
            translate([0,0,H_lid_bot]) cube([T_wall, 53.5, H_total-H_lid_bot]);
            translate([W-T_wall,0,H_lid_bot]) cube([T_wall, 53.5, H_total-H_lid_bot]);
            knuckle_x(K1x0,K1x1);
            knuckle_x(K3x0,K3x1);
            translate([K1x0, 53.5, 32.5]) cube([K1x1-K1x0, 3.5, 5.5]);
            translate([K3x0, 53.5, 32.5]) cube([K3x1-K3x0, 3.5, 5.5]);
        }
        hole_x(K1x0-0.1, K1x1+0.1);
        hole_x(K3x0-0.1, K3x1+0.1);
        translate([Notch_x0, Notch_y0, H_lid_bot-0.1]) cube([Notch_x1-Notch_x0, Notch_y1-Notch_y0, Notch_z1-(H_lid_bot-0.1)]);
    }
}

module pin() {
    translate([Pin_x0, Ax_y, Ax_z]) rotate([0,90,0]) cylinder(h=Pin_x1-Pin_x0, r=Pin_r);
}

module assembly() {
    instance("base_inst", "base") base();
    instance("lid_inst", "lid") lid();
    instance("pin_inst", "pin") pin();
}

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [80, 60, 33.8]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge", [[9, 51, 25], [71, 61, 35]]],
            ["pin_entry", [[77, 53, 27], [81, 59, 33]]]
        ]],
        ["copies", 1],
        ["details", [
            ["front_wall", "material", [[0, 0, 2], [34, 2, 29.6]], 0.9],
            ["cavity", "void", [[2, 2, 2], [78, 55, 25.0]], 0.9],
            ["knuckles", "material", [[10, 52, 25.8], [70, 60, 33.8]], 0.25],
            ["wall_thick", "thickness", [-1, 30, 15], [1, 0, 0], 2],
            ["bottom_thick", "thickness", [40, 30, -1], [0, 0, 1], 2],
            ["hole_K2", "hole", [33.0, 56, 29.8], [1, 0, 0], [[0, 4.6], [10, 4.6]]],
            ["catch_tab", "material", [[36, 0.7, 29.6], [44, 1.3, 33.5]], 0.8],
            ["view_hinge", "view", [[10, 52, 25.8], [70, 60, 33.8]]]
        ]]
    ]);
    base();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 25.8], [80, 60, 40.0]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["overhangs_allowed", [
            ["hinge", [[9.5, 52, 25.5], [70.5, 60, 34]]],
            ["top_bridge", [[2, 2, 37], [78, 58, 38]]],
            ["rim_bridge", [[0, 0, 29.7], [80, 54, 30.3]]],
            ["catch", [[35, 0, 32.5], [45, 2, 35]]],
            ["rear_wall", [[0, 57.5, 33], [80, 60.5, 34.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top_plate", "material", [[0, 0, 37.5], [30, 60, 40.0]], 0.9],
            ["cavity", "void", [[2, 2, 30.5], [78, 53, 37.5]], 0.9],
            ["knuckles", "material", [[22.1, 52, 25.8], [57.9, 60, 33.8]], 0.25],
            ["wall_thick", "thickness", [-1, 30, 35], [1, 0, 0], 2],
            ["top_thick", "thickness", [40, 30, 41], [0, 0, -1], 2.5],
            ["hole_K1", "hole", [21.0, 56, 29.8], [1, 0, 0], [[0, 4.6], [10, 4.6]]],
            ["catch_pocket", "void", [[35.5, 0.45, 29.9], [44.5, 1.55, 34.4]], 0.9],
            ["view_hinge", "view", [[22, 52, 25.8], [58, 60, 34.5]]],
            ["view_catch", "view", [[35, 0, 29.5], [45, 2, 35]]]
        ]]
    ]);
    lid();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[11.5, 54, 27.8], [79.5, 58, 31.8]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["overhangs_allowed", [
            ["pin underside", [[11.5, 54, 27.8], [79.5, 58, 29.8]]]
        ]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[20, 54.5, 28.3], [60, 57.5, 31.3]], 0.7],
            ["diameter", "thickness", [40, 56, 32.5], [0, 0, -1], 4],
            ["view_end", "view", [[76, 54, 27.8], [79.5, 58, 31.8]]]
        ]]
    ]);
    pin();
} else {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [80, 60, 40.0]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid_inst"], "rotate", [0, 56, 29.8], [-1, 0, 0], [0, 105]]
        ]],
        ["assembly_order", [
            [["base_inst"], [0, 0, 0]],
            [["lid_inst"], [0, 0, -1]],
            [["pin_inst"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge", [[9, 51, 25], [71, 61, 35]]],
            ["top_bridge", [[2, 2, 36], [78, 58, 38.5]]],
            ["rim_bridge", [[0, 0, 29.0], [80, 56, 31.0]]],
            ["catch", [[33, 0, 30], [47, 2, 35]]],
            ["rear_wall", [[0, 57, 33], [80, 61, 35]]]
        ]]
    ]);
    assembly();
}
