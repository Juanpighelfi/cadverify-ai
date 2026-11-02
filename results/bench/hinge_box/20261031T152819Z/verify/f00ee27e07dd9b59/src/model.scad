// Box with print-in-place hinge - PLA, 0.4mm nozzle, Bambu A1
// Closed box 80x~61.5x40 (hinge knuckles flush at rear y=60).
// Print orientation = assembly orientation (closed), +Z up.
part = "assembly";
cadverify_only = "";

W = 80; D = 60;
H_base_top = 29.6;
H_lid_bot = 30.0;
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
Pin_x0 = 11.5; Pin_x1 = 68.5;

Tab_x0=35; Tab_x1=45; Tab_y0=0.6; Tab_y1=1.4; Tab_z0=29.5; Tab_z1=34.0;
BumpL_x0=34.3; BumpL_x1=35.0;
BumpR_x0=45.0; BumpR_x1=45.7;
Bump_y0=0.7; Bump_y1=1.3; Bump_z0=31.5; Bump_z1=32.5;
Notch_x0=34.0; Notch_x1=46.0;
Notch_z1=34.4;
RecL_x0=33.7; RecL_x1=34.7;
RecR_x0=45.3; RecR_x1=46.3;
Rec_z0=31.1; Rec_z1=32.9;

LowTop = 25.5;   // lowered rear top for swing clearance
LidRearBot = 34.0; // raised lid rear bottom for swing clearance

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
            // side walls: front full height, rear lowered
            cube([T_wall, 55, H_base_top]);
            translate([0,55,0]) cube([T_wall, D-55, LowTop]);
            translate([W-T_wall,0,0]) cube([T_wall, 55, H_base_top]);
            translate([W-T_wall,55,0]) cube([T_wall, D-55, LowTop]);
            // rear wall: sides full, middle low
            cube([K0x0, D-T_wall, H_base_top]);
            translate([K0x0, D-T_wall, 0]) cube([K4x1-K0x0, T_wall, LowTop]);
            translate([K4x1,0,0]) cube([W-K4x1, D, H_base_top]);
            // base knuckles
            knuckle_x(K0x0,K0x1);
            knuckle_x(K2x0,K2x1);
            knuckle_x(K4x0,K4x1);
            // catch
            translate([Tab_x0, Tab_y0, Tab_z0]) cube([Tab_x1-Tab_x0, Tab_y1-Tab_y0, Tab_z1-Tab_z0]);
            translate([BumpL_x0, Bump_y0, Bump_z0]) cube([BumpL_x1-BumpL_x0, Bump_y1-Bump_y0, Bump_z1-Bump_z0]);
            translate([BumpR_x0, Bump_y0, Bump_z0]) cube([BumpR_x1-BumpR_x0, Bump_y1-Bump_y0, Bump_z1-Bump_z0]);
        }
        // lid-knuckle notches in rear wall (open top)
        translate([K1x0-0.4, D-T_wall-0.1, LowTop]) cube([(K1x1+0.4)-(K1x0-0.4), T_wall+0.2, H_base_top-LowTop+0.1]);
        translate([K3x0-0.4, D-T_wall-0.1, LowTop]) cube([(K3x1+0.4)-(K3x0-0.4), T_wall+0.2, H_base_top-LowTop+0.1]);
        // hinge holes: K0 blind left, K2 through, K4 open right for pin insertion
        hole_x(11, K0x1+0.1);
        hole_x(K2x0-0.1, K2x1+0.1);
        hole_x(K4x0-0.1, K4x1+0.1);
        // side insertion hole through right wall
        hole_x(78, 80.1);
    }
}

module lid() {
    difference() {
        union() {
            translate([0,0,Top_bot]) cube([W, D, T_top]);
            translate([0,0,H_lid_bot]) cube([W, T_wall, H_total-H_lid_bot]);
            // side walls: front full, rear raised
            translate([0,0,H_lid_bot]) cube([T_wall, 55, H_total-H_lid_bot]);
            translate([0,55,LidRearBot]) cube([T_wall, D-55, H_total-LidRearBot]);
            translate([W-T_wall,0,H_lid_bot]) cube([T_wall, 55, H_total-H_lid_bot]);
            translate([W-T_wall,55,LidRearBot]) cube([T_wall, D-55, H_total-LidRearBot]);
            // rear wall only sides (middle open for hinge)
            translate([0,D-T_wall,H_lid_bot]) cube([K0x0, T_wall, H_total-H_lid_bot]);
            translate([K4x1,D-T_wall,H_lid_bot]) cube([W-K4x1, T_wall, H_total-H_lid_bot]);
            // lid knuckles
            knuckle_x(K1x0,K1x1);
            knuckle_x(K3x0,K3x1);
        }
        // base-knuckle notches in lid sides (open bottom)
        translate([K0x0-0.4, D-T_wall-0.1, H_lid_bot-0.1]) cube([(K0x1+0.4)-(K0x0-0.4), T_wall+0.2, (Knu_top+0.3)-(H_lid_bot-0.1)]);
        translate([K2x0-0.4, D-T_wall-0.1, H_lid_bot-0.1]) cube([(K2x1+0.4)-(K2x0-0.4), T_wall+0.2, (Knu_top+0.3)-(H_lid_bot-0.1)]);
        translate([K4x0-0.4, D-T_wall-0.1, H_lid_bot-0.1]) cube([(K4x1+0.4)-(K4x0-0.4), T_wall+0.2, (Knu_top+0.3)-(H_lid_bot-0.1)]);
        hole_x(K1x0-0.1, K1x1+0.1);
        hole_x(K3x0-0.1, K3x1+0.1);
        translate([Notch_x0, -0.1, H_lid_bot-0.1]) cube([Notch_x1-Notch_x0, T_wall+0.2, Notch_z1-(H_lid_bot-0.1)]);
        translate([RecL_x0, -0.1, Rec_z0]) cube([RecL_x1-RecL_x0, T_wall+0.2, Rec_z1-Rec_z0]);
        translate([RecR_x0, -0.1, Rec_z0]) cube([RecR_x1-RecR_x0, T_wall+0.2, Rec_z1-Rec_z0]);
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
        ["bounds", [[0, 0, 0], [80, 60, 34.0]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge", [[9, 51, 25], [71, 61, 35]]],
            ["catch_bumps", [[33, 0, 30], [47, 2, 33.5]]],
            ["rear_gap", [[0, 54, 25], [80, 60, 30]]]
        ]],
        ["copies", 1],
        ["details", [
            ["front_wall", "material", [[0, 0, 2], [34, 2, 29.6]], 0.9],
            ["cavity", "void", [[2, 2, 2], [78, 55, 25.0]], 0.9],
            ["knuckles", "material", [[10, 52, 25.8], [70, 60, 33.8]], 0.25],
            ["wall_thick", "thickness", [-1, 30, 15], [1, 0, 0], 2],
            ["bottom_thick", "thickness", [40, 30, -1], [0, 0, 1], 2],
            ["hole_K2", "hole", [33.0, 56, 29.8], [1, 0, 0], [[0, 4.6], [10, 4.6]]],
            ["catch_tab", "material", [[35, 0.6, 29.6], [45, 1.4, 34.0]], 0.8],
            ["catch_bump", "material", [[34.3, 0.7, 31.5], [35.0, 1.3, 32.5]], 0.7],
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
            ["rim_bridge", [[0, 0, 29.7], [80, 55.5, 30.3]]],
            ["catch", [[33.5, -0.5, 32.5], [46.5, 2.5, 35]]],
            ["rear_step_L", [[0, 54.5, 33.5], [2.5, 58.5, 34.5]]],
            ["rear_step_R", [[77.5, 54.5, 33.5], [80, 58.5, 34.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top_plate", "material", [[0, 0, 37.5], [30, 60, 40.0]], 0.9],
            ["cavity", "void", [[2, 2, 30.5], [78, 55, 37.5]], 0.9],
            ["knuckles", "material", [[22.1, 52, 25.8], [57.9, 60, 33.8]], 0.25],
            ["wall_thick", "thickness", [-1, 30, 35], [1, 0, 0], 2],
            ["top_thick", "thickness", [40, 30, 41], [0, 0, -1], 2.5],
            ["hole_K1", "hole", [21.0, 56, 29.8], [1, 0, 0], [[0, 4.6], [10, 4.6]]],
            ["catch_notch", "void", [[34.4, 0, 30.0], [45.6, 2, 34.4]], 0.9],
            ["catch_recess", "void", [[33.7, 0, 31.1], [34.7, 2, 32.9]], 0.7],
            ["view_hinge", "view", [[22, 52, 25.8], [58, 60, 34.5]]],
            ["view_catch", "view", [[33, 0, 30], [47, 2, 35]]]
        ]]
    ]);
    lid();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[11.5, 54, 27.8], [68.5, 58, 31.8]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["overhangs_allowed", [
            ["pin underside", [[11.5, 54, 27.8], [68.5, 58, 29.8]]]
        ]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[20, 54.5, 28.3], [60, 57.5, 31.3]], 0.7],
            ["diameter", "thickness", [40, 56, 32.5], [0, 0, -1], 4],
            ["view_end", "view", [[11.5, 54, 27.8], [15, 58, 31.8]]]
        ]]
    ]);
    pin();
} else {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [80, 60, 40.0]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid_inst"], "rotate", [0, 56, 29.8], [-1, 0, 0], [0, 105], ["flex", [["lid_inst", "base_inst", 0.5, "catch snap"]]]]
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
            ["rear_step", [[0, 54, 25], [80, 60, 35]]]
        ]]
    ]);
    assembly();
}
