// Box with print-in-place hinge - FDM PLA, 0.4mm nozzle, Bambu A1
// Print orientation = assembly orientation (closed box), +Z up, lowest face on bed.
// Body 80x60x40 (W x D x H), lid 10mm, hinge embedded flush (no protrusion).

part = "assembly"; // [assembly, base, lid, pin]
cadverify_only = "";

// ---------- parameters ----------
W = 80; D = 60;
H_base_top = 29.6;      // base walls top
H_lid_bot = 30.0;       // lid walls bottom (0.4 vertical clearance)
H_total = 40.0;
T_wall = 2.0;
T_bot = 2.0;
T_top = 2.5;            // lid top 37.5-40
Top_bot = H_total - T_top; // 37.5

// hinge
Ax_y = 56; Ax_z = 29.8;    // hinge axis (y,z), x along width
Pin_d = 4.0; Pin_r = 2.0;
Clr_rad = 0.3;
Hole_d = 4.6; Hole_r = 2.3;
Knu_od = 8.0; Knu_r = 4.0;
Knu_bot = Ax_z - Knu_r; // 25.8
Knu_top = Ax_z + Knu_r; // 33.8
Hx0 = 10; Hx1 = 70;
Ax_gap = 0.5;
// knuckles: 3 base, 2 lid, each 11.6 long
K0x0=10;   K0x1=21.6;
K1x0=22.1; K1x1=33.7;
K2x0=34.2; K2x1=45.8;
K3x0=46.3; K3x1=57.9;
K4x0=58.4; K4x1=70;
// pin shaft with 0.5 clearance to end caps
Pin_x0 = 11.5; Pin_x1 = 68.5;

// catch: base tab up into lid notch (front, center)
Tab_x0=35; Tab_x1=45; Tab_y0=0.6; Tab_y1=1.4; Tab_z0=29.5; Tab_z1=34.0;
BumpL_x0=34.3; BumpL_x1=35.0;
BumpR_x0=45.0; BumpR_x1=45.7;
Bump_y0=0.7; Bump_y1=1.3; Bump_z0=31.5; Bump_z1=32.5;
Notch_x0=34.6; Notch_x1=45.4; // lid front notch (full thickness Y, open bottom)
Notch_z1=34.4;
RecL_x0=33.9; RecL_x1=34.7;
RecR_x0=45.3; RecR_x1=46.1;
Rec_z0=31.1; Rec_z1=32.9;

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
            // bottom
            cube([W, D, T_bot]);
            // front wall
            cube([W, T_wall, H_base_top]);
            // left / right walls (full depth, overlap)
            cube([T_wall, D, H_base_top]);
            cube([W-T_wall, 0, 0] + [0,0,0] + [0,0,0]); // placeholder
            translate([W-T_wall,0,0]) cube([T_wall, D, H_base_top]);
            // rear wall (full, notches subtracted later)
            translate([0, D-T_wall, 0]) cube([W, T_wall, H_base_top]);
            // base knuckles
            knuckle_x(K0x0,K0x1);
            knuckle_x(K2x0,K2x1);
            knuckle_x(K4x0,K4x1);
            // catch tab + side bumps (overlap 0.1 into wall top)
            cube([Tab_x1-Tab_x0, Tab_y1-Tab_y0, Tab_z1-Tab_z0] , false);
            translate([Tab_x0, Tab_y0, Tab_z0]) cube([Tab_x1-Tab_x0, Tab_y1-Tab_y0, Tab_z1-Tab_z0]);
            translate([BumpL_x0, Bump_y0, Bump_z0]) cube([BumpL_x1-BumpL_x0, Bump_y1-Bump_y0, Bump_z1-Bump_z0]);
            translate([BumpR_x0, Bump_y0, Bump_z0]) cube([BumpR_x1-BumpR_x0, Bump_y1-Bump_y0, Bump_z1-Bump_z0]);
        }
        // rear notches for lid knuckles (open top, 0.3 below knuckle bottom)
        translate([K1x0-0.4, D-T_wall-0.1, Knu_bot-0.3]) cube([ (K1x1+0.4)-(K1x0-0.4), T_wall+0.2, H_base_top-(Knu_bot-0.3)+0.1 ]);
        translate([K3x0-0.4, D-T_wall-0.1, Knu_bot-0.3]) cube([ (K3x1+0.4)-(K3x0-0.4), T_wall+0.2, H_base_top-(Knu_bot-0.3)+0.1 ]);
        // hinge holes: K0 blind (cap 1mm at outer end), K2 through, K4 blind
        hole_x(11, K0x1+0.1);
        hole_x(K2x0-0.1, K2x1+0.1);
        hole_x(K4x0-0.1, 69);
    }
}

module lid() {
    difference() {
        union() {
            // top plate
            translate([0,0,Top_bot]) cube([W, D, T_top]);
            // front wall
            translate([0,0,H_lid_bot]) cube([W, T_wall, H_total-H_lid_bot]);
            // rear wall
            translate([0,D-T_wall,H_lid_bot]) cube([W, T_wall, H_total-H_lid_bot]);
            // side walls with rear relief (raised 2mm at back Y55-60)
            translate([0,0,H_lid_bot]) cube([T_wall, 55.1, H_total-H_lid_bot]);
            translate([0,55,32]) cube([T_wall, 5, H_total-32]);
            translate([W-T_wall,0,H_lid_bot]) cube([T_wall, 55.1, H_total-H_lid_bot]);
            translate([W-T_wall,55,32]) cube([T_wall, 5, H_total-32]);
            // lid knuckles
            knuckle_x(K1x0,K1x1);
            knuckle_x(K3x0,K3x1);
        }
        // rear notches for base knuckles (open bottom, 0.3 above knuckle top)
        translate([K0x0-0.4, D-T_wall-0.1, H_lid_bot-0.1]) cube([(K0x1+0.4)-(K0x0-0.4), T_wall+0.2, (Knu_top+0.3)-(H_lid_bot-0.1)]);
        translate([K2x0-0.4, D-T_wall-0.1, H_lid_bot-0.1]) cube([(K2x1+0.4)-(K2x0-0.4), T_wall+0.2, (Knu_top+0.3)-(H_lid_bot-0.1)]);
        translate([K4x0-0.4, D-T_wall-0.1, H_lid_bot-0.1]) cube([(K4x1+0.4)-(K4x0-0.4), T_wall+0.2, (Knu_top+0.3)-(H_lid_bot-0.1)]);
        // hinge holes through lid knuckles
        hole_x(K1x0-0.1, K1x1+0.1);
        hole_x(K3x0-0.1, K3x1+0.1);
        // front catch notch (full thickness, open bottom)
        translate([Notch_x0, -0.1, H_lid_bot-0.1]) cube([Notch_x1-Notch_x0, T_wall+0.2, Notch_z1-(H_lid_bot-0.1)]);
        // side recesses for tab bumps (full thickness Y, open to notch)
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
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge", [[9, 51, 25], [71, 61, 35]]],
            ["catch_bumps", [[33, 0, 30], [47, 2, 33.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["front_wall", "material", [[0, 0, 2], [34, 2, 29.6]], 0.9],
            ["cavity", "void", [[2, 2, 2], [78, 56, 25.0]], 0.9],
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
            ["hinge", [[9, 51, 25], [71, 61, 35]]],
            ["top_bridge", [[2, 2, 36], [78, 58, 38.5]]],
            ["rim_bridge", [[0, 0, 29.5], [80, 60, 30.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top_plate", "material", [[0, 0, 37.5], [30, 60, 40.0]], 0.9],
            ["cavity", "void", [[2, 2, 30.5], [78, 56, 37.5]], 0.9],
            ["knuckles", "material", [[22.1, 52, 25.8], [57.9, 60, 33.8]], 0.25],
            ["wall_thick", "thickness", [-1, 30, 35], [1, 0, 0], 2],
            ["top_thick", "thickness", [40, 30, 41], [0, 0, -1], 2.5],
            ["hole_K1", "hole", [21.0, 56, 29.8], [1, 0, 0], [[0, 4.6], [11.6, 4.6]]],
            ["catch_notch", "void", [[34.6, 0, 30.0], [45.4, 2, 34.4]], 0.9],
            ["catch_recess", "void", [[33.9, 0, 31.1], [34.7, 2, 32.9]], 0.7],
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
            ["lid_open", ["lid_inst"], "rotate", [0, 56, 29.8], [-1, 0, 0], [0, 110], ["flex", [["lid_inst", "base_inst", 0.5, "catch snap"]]]]
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
            ["rim_bridge", [[0, 0, 29.0], [80, 60, 31.0]]],
            ["catch", [[33, 0, 30], [47, 2, 35]]]
        ]]
    ]);
    assembly();
}
