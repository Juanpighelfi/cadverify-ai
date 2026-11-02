// Box with print-in-place hinge - PLA, Bambu Lab A1, 0.4 mm nozzle, no supports.
// Closed body 80 x 60 x 40.4 (lid 10 mm of that height). Hinge axis along X at
// (y=-31, z=32): 7 knuckles R3 alternate box/lid around a pin R1.5 printed in
// place (bores/channel R1.9: 0.4 radial clearance, 0.5 axial gaps, 0.4+ gaps at
// walls). Knuckle shells dip 1 mm into the wall tops so they bond. Mortise and
// notch cutouts clear the mating knuckles (0.5 side, 0.6 top/bottom clearance).
// The lid prints closed, bridging over the box (0.4 vertical gap). The pin's head
// sits outside the body (x 40.5..42) so it never touches box or lid.

part = "assembly"; // [box, lid, pin, assembly]

W = 80; D = 60;
Hbox = 30; wall = 2; bottom_t = 3; top_t = 3;
mate_gap = 0.4;
Zbt = Hbox;            // 30   box top
Zlb = Hbox + mate_gap; // 30.4 lid skirt bottom
skirt_h = 7;
Zsk = Zlb + skirt_h;   // 37.4 skirt top
Zceil = 35.4;          // lid cavity ceiling (plate underside)
Zlt = Zsk + top_t;     // 40.4 lid top

// hinge axis and sizes
CY = -31; CZ = 32;
Rk = 3; boreR = 1.9; Rp = 1.5; capR = 2.5;
nseg = 7; gap_ax = 0.5;
Hx0 = -36;
Lk = (72 - (nseg-1)*gap_ax)/nseg; // 9.857
function seg_x0(i) = Hx0 + i*(Lk+gap_ax);
// pin: shaft -36..40.5, head 40.5..42 (slides in tail-first from +x)
pin_x0 = -36.0; pin_x1 = 40.5; head_x0 = 40.5; head_x1 = 42;

$fn = 64;

cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module knuckle(x0) {
    difference() {
        translate([x0, CY, CZ]) rotate([0,90,0]) cylinder(r=Rk, h=Lk);
        translate([x0-0.1, CY, CZ]) rotate([0,90,0]) cylinder(r=boreR, h=Lk+0.2);
    }
}

module box_part() {
    difference() {
        union() {
            translate([-W/2, -D/2, 0]) cube([W, D, Hbox]);
            for (i = [0,2,4,6]) knuckle(seg_x0(i));
            // friction catch tongue on top of front wall
            translate([-4.9, 28.4, Zbt]) cube([9.8, 1.2, 1.5]);
        }
        translate([-W/2+wall, -D/2+wall, bottom_t]) cube([W-2*wall, D-2*wall, Hbox]);
        // notches in back wall top clearing the lid knuckles (0.5 side, 0.6 below)
        for (i = [1,3,5])
            translate([seg_x0(i)-0.5, -30, 28.4]) cube([Lk+1.0, 2, 1.6]);
    }
}

module lid_part() {
    difference() {
        union() {
            // skirt ring
            translate([-W/2, -D/2, Zlb]) cube([W, D, skirt_h]);
            // solid top (plate + filler down to cavity ceiling)
            translate([-W/2, -D/2, Zceil]) cube([W, D, Zlt-Zceil]);
            for (i = [1,3,5]) knuckle(seg_x0(i));
        }
        // lid cavity open at bottom
        translate([-W/2+wall, -D/2+wall, Zlb]) cube([W-2*wall, D-2*wall, Zceil-Zlb]);
        // mortises clearing box knuckles, open at skirt bottom (0.5 side, 0.6 top)
        for (i = [0,2,4,6])
            translate([seg_x0(i)-0.5, -30, Zlb-0.01]) cube([Lk+1.0, 2, 35.6-Zlb+0.01]);
        // continuous pin channel through the back wall (0.4 radial clearance)
        translate([-36.6, CY, CZ]) rotate([0,90,0]) cylinder(r=boreR, h=77.2);
        // catch window through front skirt, open at bottom
        translate([-5.45, 28, Zlb-0.01]) cube([10.9, 2, 1.61]);
    }
}

module pin_part() {
    union() {
        translate([pin_x0, CY, CZ]) rotate([0,90,0]) cylinder(r=Rp, h=pin_x1-pin_x0);
        translate([head_x0, CY, CZ]) rotate([0,90,0]) cylinder(r=capR, h=head_x1-head_x0);
    }
}

if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -34, 0], [40, 30, 35]]],
        ["bodies", 1],
        ["through_holes", 4],
        ["support_faces", [["base", "-z", 4000]]],
        ["overhangs_allowed", [["knuckle shells and bores bridge, no supports", [[-36, -34, 28], [36, -28, 35]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [30, 32, 15], [0, -1, 0], 2],
            ["bottom", "thickness", [0, 0, -1], [0, 0, 1], 3],
            ["bond", "material", [[6, -30, 29.6], [14, -28.5, 30.4]], 0.9],
            ["cavity", "void", [[-37.5, -27.5, 3.5], [37.5, 27.5, 28.5]], 0.9],
            ["bore", "hole", [-36.6, -31, 32], [1, 0, 0], [[0, 3.8], [8, 3.8]]],
            ["catch", "material", [[-4.5, 28.5, 30.2], [4.5, 29.5, 31.4]], 0.9],
            ["hinge_view", "view", [[-36, -34, 28], [36, -28, 35]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -34, 29], [40, 30, 40.4]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["knuckle shells, bores, channel and mortise ceilings bridge, no supports", [[-36.6, -34, 28], [36, -28, 35.7]]],
            ["lid plate underside bridges the box in place, no supports", [[-38, -28, 35.3], [38, 28, 35.5]]],
            ["skirt bottom ring bridges a 0.4 gap over the box walls, no supports", [[-40, -30, 30.3], [40, 30, 30.5]]],
            ["catch window bridges 2mm in y, no supports", [[-5.45, 28, 30.4], [5.45, 30, 32]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 0, 41.4], [0, 0, -1], 5],
            ["skirt", "thickness", [20, 32, 33.5], [0, -1, 0], 2],
            ["bond", "material", [[-4, -29, 33], [4, -28.2, 34]], 0.9],
            ["slot", "void", [[-5, 28.1, 30.5], [5, 29.9, 31.9]], 0.9],
            ["mortise", "void", [[-35.5, -29.9, 34], [-26.6, -28.1, 35.5]], 0.9],
            ["bore", "hole", [-26, -31, 32], [1, 0, 0], [[0, 3.8], [8, 3.8]]],
            ["hinge_view", "view", [[-36, -34, 28], [36, -28, 35.7]]],
            ["catch_view", "view", [[-8, 27.5, 29.5], [8, 30.5, 33]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-36, -33.5, 29.5], [42, -28.5, 34.5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["shaft underside prints suspended in bores, gap-limited droop, no supports", [[-36, -32.1, 30.4], [40.5, -29.9, 31]]],
            ["head underside prints suspended, no supports", [[40.5, -32.8, 29.4], [42, -29.2, 30.3]]]
        ]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-30, -32, 31], [30, -30, 33]], 0.9],
            ["diameter", "thickness", [0, -28, 32], [0, -1, 0], 3],
            ["cap_view", "view", [[40.5, -33.5, 29.5], [42, -28.5, 34.5]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -34, 0], [42, 30, 40.4]]],
        ["support_faces", [["base", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid_1"], "rotate", [0, -31, 32], [1, 0, 0], [0, 105]]
        ]],
        ["assembly_order", [
            [["box_1"], [0, 0, 0]],
            [["lid_1"], [0, 0, -1]],
            [["pin_1"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.4],
        ["overhangs_allowed", [
            ["hinge knuckles, pin, channel, grooves and mortise ceilings bridge in place, no supports", [[-37, -34, 28.5], [42, -28, 35.7]]],
            ["lid plate underside bridges the box in place, no supports", [[-38, -28, 35.3], [38, 28, 35.5]]],
            ["skirt bottom ring bridges a 0.4 gap over the box walls, no supports", [[-40, -30, 30.3], [40, 30, 30.5]]],
            ["catch tongue/window bridges 2mm in y, no supports", [[-5.45, 28, 30], [5.45, 30, 32]]]
        ]]
    ]);
    instance("box_1", "box") box_part();
    instance("lid_1", "lid") lid_part();
    instance("pin_1", "pin") pin_part();
}
