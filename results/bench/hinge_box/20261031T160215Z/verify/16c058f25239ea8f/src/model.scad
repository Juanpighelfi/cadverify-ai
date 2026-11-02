// Box with print-in-place hinge - PLA 0.4mm nozzle, no supports
// Closed outer body 80x60x40.4 (hinge adds ~6.5mm behind), lid 10mm of height.

part = "assembly"; // [box, lid, pin, assembly]

W = 80; D = 60;
Hbox = 30; Hlid = 10;
wall = 2; bottom_t = 3; top_t = 3;
mate_gap = 0.4; // lid bottom above box top (anti-fuse)
Zbt = Hbox; // 30 box top
Zlb = Hbox + mate_gap; // 30.4 lid bottom
Zlt = Zlb + Hlid; // 40.4 lid top
skirt_h = 7;
Zsk_top = Zlb + skirt_h; // 37.4
// hinge axis (assembly coords), set back so knuckles clear the walls
ax_y = -33.5;
ax_z = 32;
Rk = 3; Rp = 1.5; boreR = 1.85; // radial clearance 0.35
Lh = 60; Hx0 = -30; Hx1 = 30;
gap_ax = 0.5; nseg = 5;
Lk = (Lh - (nseg-1)*gap_ax)/nseg; // 11.6
// segment helper
function seg_x0(i) = Hx0 + i*(Lk+gap_ax);
function seg_x1(i) = seg_x0(i)+Lk;
// pin: shaft + single head at +x (assemblable, printed in place)
pin_x0 = -30.5; pin_x1 = 30.8;
cap_t = 1.5; capR = 2.5;
cap_x1_out = pin_x1 + cap_t; // 32.3

$fn = 64;

cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module box_knuckle(i) {
    x0 = seg_x0(i);
    translate([x0, ax_y, ax_z]) rotate([0,90,0])
        difference() {
            cylinder(r=Rk, h=Lk);
            translate([0,0,-0.1]) cylinder(r=boreR, h=Lk+0.2);
        }
}
module lid_knuckle(i) {
    x0 = seg_x0(i);
    translate([x0, ax_y, ax_z]) rotate([0,90,0])
        difference() {
            cylinder(r=Rk, h=Lk);
            translate([0,0,-0.1]) cylinder(r=boreR, h=Lk+0.2);
        }
}
module box_lug(i) {
    x0 = seg_x0(i);
    // below the bore mouth (mouth bottom z=30.15, lug top z=30)
    translate([x0, ax_y-1.5, 28.5]) cube([Lk, 4.5, 1.5+0.01]);
}
module lid_lug(i) {
    x0 = seg_x0(i);
    // narrow strap beside the bore mouth, clears the bore disc
    translate([x0, -31, Zlb]) cube([Lk, 1, 1.5+0.01]);
}

module box_part() {
    difference() {
        union() {
            translate([-W/2, -D/2, 0]) cube([W, D, Hbox]);
            box_knuckle(0); box_knuckle(2); box_knuckle(4);
            box_lug(0); box_lug(2); box_lug(4);
            // catch block on top of front wall
            translate([-5, 28.5, Zbt]) cube([10, 1.0, 1.5]);
        }
        translate([-W/2+wall, -D/2+wall, bottom_t]) cube([W-2*wall, D-2*wall, Hbox]);
    }
}

module lid_part() {
    difference() {
        union() {
            translate([-W/2, -D/2, Zlb]) cube([W, D, skirt_h]);
            translate([-W/2, -D/2, Zsk_top]) cube([W, D, top_t]);
            // plug overlaps the top plate so it is one body
            translate([-37.6, -27.6, Zlb-3]) cube([75.2, 55.2, 10.2]);
            lid_knuckle(1); lid_knuckle(3);
            lid_lug(1); lid_lug(3);
        }
        translate([-W/2+wall, -D/2+wall, Zlb]) cube([W-2*wall, D-2*wall, skirt_h]);
        // catch slot in front skirt (open at bottom)
        translate([-5.3, 28.2, Zlb-0.01]) cube([10.6, 1.6, 2.01]);
    }
}

module pin_part() {
    union() {
        translate([pin_x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=Rp, h=pin_x1-pin_x0);
        translate([pin_x1, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=capR, h=cap_t);
    }
}

// ---- specs ----
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36.5, 0], [40, 30, 35]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["base", "-z", 4000]]],
        ["overhangs_allowed", [["hinge knuckles bridge, 6mm dia prints without supports", [[-30, -36.5, 29], [30, -30, 35]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [30, 32, 15], [0, -1, 0], 2],
            ["bottom", "thickness", [0, 0, -1], [0, 0, 1], 3],
            ["lug", "material", [[-5.5, -35, 28.6], [5.5, -30.2, 29.9]], 0.9],
            ["cavity", "void", [[-37.5, -27.5, 3.5], [37.5, 27.5, 28.5]], 0.9],
            ["bore", "hole", [-31, -33.5, 32], [1, 0, 0], [[0, 3.7], [10, 3.7]]],
            ["catch", "material", [[-4.5, 28.6, 30.1], [4.5, 29.4, 31.4]], 0.9],
            ["hinge_view", "view", [[-30, -36.5, 29], [30, -30, 35]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36.5, 27.4], [40, 30, 40.4]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["hinge knuckles bridge, 6mm dia prints without supports", [[-30, -36.5, 29], [30, -30, 35]]],
            ["catch slot bridges 1.6mm, no supports", [[-5.3, 28.2, 30.4], [5.3, 29.8, 32.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 0, 41.4], [0, 0, -1], 3],
            ["skirt", "thickness", [30, 32, 33.5], [0, -1, 0], 2],
            ["lug", "material", [[-17.6, -30.9, 30.5], [-6.6, -30.1, 31.8]], 0.9],
            ["slot", "void", [[-5.0, 28.4, 30.5], [5.0, 29.6, 32.2]], 0.9],
            ["bore", "hole", [-18.15, -33.5, 32], [1, 0, 0], [[0, 3.7], [10, 3.7]]],
            ["plug_gap", "void", [[37.7, -20, 31], [37.9, 20, 37]], 0.9],
            ["hinge_view", "view", [[-30, -36.5, 29], [30, -30, 35]]],
            ["catch_view", "view", [[-5.3, 28.2, 30.4], [5.3, 29.8, 32.5]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-30.5, -36, 29.5], [32.3, -31, 34.5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", []],
        ["overhangs_allowed", [["pin shaft bridges inside knuckles, no supports", [[-30.5, -36, 29.5], [32.3, -31, 31.5]]]]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-30, -34.5, 31], [30, -32.5, 33]], 0.9],
            ["diameter", "thickness", [0, -30, 32], [0, -1, 0], 3],
            ["cap_view", "view", [[30.8, -36, 29.5], [32.3, -31, 34.5]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36.5, 0], [40, 30, 40.4]]],
        ["support_faces", [["base", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid_1"], "rotate", [0, -33.5, 32], [1, 0, 0], [0, 105]]
        ]],
        ["assembly_order", [
            [["box_1"], [0, 0, 0]],
            [["lid_1"], [0, 0, -1]],
            [["pin_1"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge knuckles and pin bridge, no supports", [[-31, -36.5, 29], [32.5, -29, 35.5]]],
            ["catch slot bridges 1.6mm, no supports", [[-6, 28, 30], [6, 30, 33]]]
        ]]
    ]);
    instance("box_1", "box") box_part();
    instance("lid_1", "lid") lid_part();
    instance("pin_1", "pin") pin_part();
}
