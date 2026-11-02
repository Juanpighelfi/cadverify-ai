// Box with print-in-place hinge - PLA 0.4mm nozzle, no supports
// Closed outer body ~80x60x40 (hinge adds 6mm behind), lid 10mm.

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
// hinge axis (assembly coords)
ax_y = -D/2 - 3; // -33
ax_z = Hbox + 2; // 32
Rk = 3; Rp = 1.5; boreR = 1.85; // radial clearance 0.35
Lh = 60; Hx0 = -30; Hx1 = 30;
gap_ax = 0.5; nseg = 5;
Lk = (Lh - (nseg-1)*gap_ax)/nseg; // 11.6
// segment helper
function seg_x0(i) = Hx0 + i*(Lk+gap_ax);
function seg_x1(i) = seg_x0(i)+Lk;
// pin
pin_x0 = -30.8; pin_x1 = 30.8;
cap_t = 1.5; capR = 2.5;
cap_x0_out = pin_x0 - cap_t; // -32.3
cap_x1_out = pin_x1 + cap_t; // 32.3

$fn = 64;

cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module box_knuckle(i) {
    x0 = seg_x0(i);
    // cylinder along X
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
    // connects back wall to knuckle, top flush with box top
    translate([x0, ax_y-1.5, 28.5]) cube([Lk, 4.5, 1.5+0.01]);
    // y: -34.5 to -30? ax_y-1.5=-34.5, +4.5 => -30.0 ; z 28.5-30.0
}
module lid_lug(i) {
    x0 = seg_x0(i);
    // connects lid back wall to knuckle, bottom at lid bottom
    translate([x0, ax_y-1.5, Zlb]) cube([Lk, 4.5, 2.6+0.01]);
    // y -34.5 to -30, z 30.4-33.0
}

module box_part() {
    difference() {
        union() {
            // main body outer
            translate([-W/2, -D/2, 0]) cube([W, D, Hbox]);
            // box knuckles + lugs (segments 0,2,4)
            box_knuckle(0); box_knuckle(2); box_knuckle(4);
            box_lug(0); box_lug(2); box_lug(4);
            // catch block on top of front wall
            translate([-5, 28.5, Zbt]) cube([10, 1.0, 1.5]);
        }
        // interior cavity
        translate([-W/2+wall, -D/2+wall, bottom_t]) cube([W-2*wall, D-2*wall, Hbox]);
    }
}

module lid_part() {
    difference() {
        union() {
            // skirt outer
            translate([-W/2, -D/2, Zlb]) cube([W, D, skirt_h]);
            // top plate
            translate([-W/2, -D/2, Zsk_top]) cube([W, D, top_t]);
            // plug (alignment) 75.2 x 55.2, from 27.4 to 37.4
            translate([-37.6, -27.6, Zlb-3]) cube([75.2, 55.2, 10.0]);
            // lid knuckles + lugs (segments 1,3)
            lid_knuckle(1); lid_knuckle(3);
            lid_lug(1); lid_lug(3);
        }
        // skirt cavity (open bottom)
        translate([-W/2+wall, -D/2+wall, Zlb]) cube([W-2*wall, D-2*wall, skirt_h]);
        // catch slot in front skirt (open at bottom)
        translate([-5.3, 28.2, Zlb-0.01]) cube([10.6, 1.6, 2.01]);
    }
}

module pin_part() {
    union() {
        // shaft
        translate([pin_x0, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=Rp, h=pin_x1-pin_x0);
        // caps
        translate([cap_x0_out, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=capR, h=cap_t);
        translate([pin_x1, ax_y, ax_z]) rotate([0,90,0]) cylinder(r=capR, h=cap_t);
    }
}

// ---- specs ----
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 35]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["base", "-z", 4000]]],
        ["overhangs_allowed", [["hinge knuckles bridge, 6mm dia prints without supports", [[-30, -36, 29], [30, -30, 35]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [30, 32, 15], [0, -1, 0], 2],
            ["bottom", "thickness", [0, 0, -1], [0, 0, 1], 3],
            ["lug", "material", [[-5.5, -34.2, 28.6], [5.5, -30.2, 29.9]], 0.9],
            ["cavity", "void", [[-37.5, -27.5, 3.5], [37.5, 27.5, 28.5]], 0.9],
            ["bore", "hole", [-31, -33, 32], [1, 0, 0], [[0, 3.7], [11.6, 3.7]]],
            ["catch", "material", [[-4.5, 28.6, 30.1], [4.5, 29.4, 31.4]], 0.9],
            ["hinge_view", "view", [[-30, -36, 29], [30, -30, 35]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 27.4], [40, 30, 40.4]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["hinge knuckles bridge, 6mm dia prints without supports", [[-30, -36, 29], [30, -30, 35]]],
            ["catch slot bridges 1.6mm, no supports", [[-5.3, 28.2, 30.4], [5.3, 29.8, 32.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 0, 41.4], [0, 0, -1], 3],
            ["skirt", "thickness", [30, 32, 33.5], [0, -1, 0], 2],
            ["lug", "material", [[-17.5, -34.2, 30.5], [-6.7, -30.2, 32.8]], 0.9],
            ["slot", "void", [[-5.0, 28.4, 30.5], [5.0, 29.6, 32.2]], 0.9],
            ["bore", "hole", [-18.15, -33, 32], [1, 0, 0], [[0, 3.7], [11.6, 3.7]]],
            ["plug_gap", "void", [[37.7, -20, 31], [37.9, 20, 37]], 0.9],
            ["hinge_view", "view", [[-30, -36, 29], [30, -30, 35]]],
            ["catch_view", "view", [[-5.3, 28.2, 30.4], [5.3, 29.8, 32.5]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-32.3, -35.5, 29.5], [32.3, -30.5, 34.5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", []],
        ["overhangs_allowed", [["pin shaft bridges inside knuckles, no supports", [[-32.3, -35.5, 29.5], [32.3, -30.5, 31.5]]]]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-30, -34, 31], [30, -32, 33]], 0.9],
            ["diameter", "thickness", [0, -30, 32], [0, -1, 0], 3],
            ["cap_view", "view", [[30.8, -35.5, 29.5], [32.3, -30.5, 34.5]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 40.4]]],
        ["support_faces", [["base", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid_1"], "rotate", [0, -33, 32], [1, 0, 0], [0, 105]]
        ]],
        ["assembly_order", [
            [["box_1"], [0, 0, 0]],
            [["lid_1"], [0, 0, -1]],
            [["pin_1"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge knuckles and pin bridge, no supports", [[-32.5, -36, 29], [32.5, -29, 35.5]]],
            ["catch slot bridges 1.6mm, no supports", [[-6, 28, 30], [6, 30, 33]]]
        ]]
    ]);
    instance("box_1", "box") box_part();
    instance("lid_1", "lid") lid_part();
    instance("pin_1", "pin") pin_part();
}
