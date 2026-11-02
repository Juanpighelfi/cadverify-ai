// Box with print-in-place hinge - PLA, Bambu Lab A1, 0.4 mm nozzle, no supports.
// Closed body 80 x 60 x 40.4 (lid 10 mm of height). Hinge axis along X at (y=-31, z=34),
// knuckles R3 alternate box/lid around a captive-in-place pin (R1.5 in R1.85 bores).
// Connectors are 45 deg flares sitting on wall stock (no floating flat ledges).
// Lid back wall has mortise cutouts clearing the box knuckles; lid plug aligns it.

part = "assembly"; // [box, lid, pin, assembly]

W = 80; D = 60;
Hbox = 30; wall = 2; bottom_t = 3; top_t = 3;
mate_gap = 0.4;
Zbt = Hbox;            // 30   box top
Zlb = Hbox + mate_gap; // 30.4 lid skirt bottom
skirt_h = 7;
Zsk = Zlb + skirt_h;   // 37.4 skirt top / plate bottom
Zlt = Zsk + top_t;     // 40.4 lid top

// hinge axis and sizes
CY = -31; CZ = 34;
Rk = 3; boreR = 1.85; Rp = 1.5; capR = 2.5;
nseg = 7; gap_ax = 0.5;
Hx0 = -40;
Lk = (80 - (nseg-1)*gap_ax)/nseg; // 11
function seg_x0(i) = Hx0 + i*(Lk+gap_ax);
// pin: shaft -40.5..40.5, single head 40.3..42 (inserts from +x)
pin_x0 = -40.5; pin_x1 = 40.5; head_x0 = 40.3; head_x1 = 42;

$fn = 64;

cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// box hinge segment: knuckle with bore + 45 deg flare lug onto wall top
module box_seg(x0) {
    difference() {
        union() {
            translate([x0, CY, CZ]) rotate([0,90,0]) cylinder(r=Rk, h=Lk);
            translate([x0+Lk, 0, 0]) rotate([0,-90,0])
                linear_extrude(height=Lk)
                polygon([[-30,30],[-28,30],[-28,31.8],[-31.8,31.8]]);
        }
        translate([x0-0.1, CY, CZ]) rotate([0,90,0]) cylinder(r=boreR, h=Lk+0.2);
    }
}
// lid hinge segment: knuckle with bore + tapered lug up into skirt/plate
module lid_seg(x0) {
    difference() {
        union() {
            translate([x0, CY, CZ]) rotate([0,90,0]) cylinder(r=Rk, h=Lk);
            translate([x0+Lk, 0, 0]) rotate([0,-90,0])
                linear_extrude(height=Lk)
                polygon([[-32,37.6],[-28,37.6],[-28,34],[-30,34]]);
        }
        translate([x0-0.1, CY, CZ]) rotate([0,90,0]) cylinder(r=boreR, h=Lk+0.2);
    }
}

module box_part() {
    difference() {
        union() {
            translate([-W/2, -D/2, 0]) cube([W, D, Hbox]);
            for (i = [0,2,4,6]) box_seg(seg_x0(i));
            // catch tongue on top of front wall
            translate([-5, 28.4, Zbt]) cube([10, 1.0, 1.5]);
        }
        translate([-W/2+wall, -D/2+wall, bottom_t]) cube([W-2*wall, D-2*wall, Hbox]);
    }
}

module lid_part() {
    difference() {
        union() {
            // skirt walls (back wall full here, mortised below)
            translate([-W/2, -D/2, Zlb]) cube([W, D, skirt_h]);
            // top plate
            translate([-W/2, -D/2, Zsk]) cube([W, D, top_t]);
            // alignment plug (overlaps plate 0.2)
            translate([-37.4, -27.2, 28]) cube([74.8, 54.4, 9.6]);
            for (i = [1,3,5]) lid_seg(seg_x0(i));
        }
        // skirt cavity open at bottom
        translate([-W/2+wall, -D/2+wall, Zlb]) cube([W-2*wall, D-2*wall, skirt_h]);
        // mortises clearing box knuckles (box segs +-0.5), full skirt height
        for (i = [0,2,4,6])
            translate([seg_x0(i)-0.5, -30, Zlb-0.01]) cube([Lk+1, 2, skirt_h+0.01]);
        // catch window through front skirt, open at bottom
        translate([-5.45, -D/2, Zlb-0.01]) cube([10.9, 2, 1.61]);
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
        ["bounds", [[-40, -34, 0], [40, 30, 37]]],
        ["bodies", 1],
        ["through_holes", 4],
        ["support_faces", [["base", "-z", 4000]]],
        ["overhangs_allowed", [["knuckles, bores and lug flares bridge, no supports", [[-40, -34, 28], [40, -28, 37]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [30, 32, 15], [0, -1, 0], 2],
            ["bottom", "thickness", [0, 0, -1], [0, 0, 1], 3],
            ["lug", "material", [[-16, -29.9, 30.2], [-7, -28.1, 30.8]], 0.9],
            ["cavity", "void", [[-37.5, -27.5, 3.5], [37.5, 27.5, 28.5]], 0.9],
            ["bore", "hole", [-40.6, -31, 34], [1, 0, 0], [[0, 3.7], [9, 3.7]]],
            ["catch", "material", [[-4.5, 28.5, 30.1], [4.5, 29.3, 31.4]], 0.9],
            ["hinge_view", "view", [[-40, -34, 28], [40, -28, 37]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -34, 28], [40, 30, 40.4]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["knuckles, bores, lug flares and mortise ceilings bridge, no supports", [[-40, -34, 28], [40, -28, 37.6]]],
            ["catch window bridges 2mm in y, no supports", [[-5.45, 28, 30.4], [5.45, 30, 32]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 0, 41.4], [0, 0, -1], 3],
            ["skirt", "thickness", [0, 32, 33.5], [0, -1, 0], 2],
            ["lug", "material", [[-27, -28.9, 34.5], [-18, -28.2, 36]], 0.9],
            ["slot", "void", [[-5.0, 28.1, 30.5], [5.0, 29.9, 31.9]], 0.9],
            ["bore", "hole", [-28.75, -31, 34], [1, 0, 0], [[0, 3.7], [9, 3.7]]],
            ["plug_gap", "void", [[37.5, -20, 31], [37.9, 20, 37]], 0.9],
            ["hinge_view", "view", [[-40, -34, 28], [40, -28, 37.6]]],
            ["catch_view", "view", [[-5.45, 28, 30.4], [5.45, 30, 32.2]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-40.5, -33.5, 31.5], [42, -28.5, 36.5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", []],
        ["overhangs_allowed", [["shaft prints suspended in bores, gap-limited droop, no supports", [[-40.5, -33.6, 30.9], [42, -28.4, 32.6]]]]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-30, -32, 33], [30, -30, 35]], 0.9],
            ["diameter", "thickness", [0, -28, 34], [0, -1, 0], 3],
            ["cap_view", "view", [[40.3, -33.5, 31.5], [42, -28.5, 36.5]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40.5, -34, 0], [42, 30, 40.4]]],
        ["support_faces", [["base", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid_1"], "rotate", [0, -31, 34], [1, 0, 0], [0, 105]]
        ]],
        ["assembly_order", [
            [["box_1"], [0, 0, 0]],
            [["lid_1"], [0, 0, -1]],
            [["pin_1"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.35],
        ["overhangs_allowed", [
            ["hinge knuckles, pin and lugs bridge in place, no supports", [[-40.5, -34, 28], [42, -28, 37.6]]],
            ["catch window bridges 2mm in y, no supports", [[-5.45, 28, 30.4], [5.45, 30, 32]]]
        ]]
    ]);
    instance("box_1", "box") box_part();
    instance("lid_1", "lid") lid_part();
    instance("pin_1", "pin") pin_part();
}
