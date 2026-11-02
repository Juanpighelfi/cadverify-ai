// Box with print-in-place hinge — Bambu Lab A1, PLA, 0.4 mm nozzle.
// One print, printed open flat (lid swung 180 deg), comes off the bed assembled.
// Closed outside: 80 (x) x ~70 incl. hinge (y) x 40 (z) mm; body alone 80x60x40.
// Hinge: alternating knuckles on a separate pin printed in place.
//   pin r=1.9, bore r=2.4 (0.5 radial clearance), knuckle axial gaps 0.75,
//   lid cheek to base back wall 1.0 in closed pose, 0.5 is the declared
//   print-in-place minimum clearance (pin/bore and pin head).
part = "assembly"; // [assembly, base, lid, pin]
cadverify_only = "";

$fn = 64;

W = 80;          // outside width  (x)
D = 60;          // outside depth of body (y), front y=0, back y=60
base_h = 30;     // base height
lid_h = 10;      // lid height
total_h = base_h + lid_h; // 40
wall = 3;
floor_t = 3;
plate_t = 3;

pivot_y = 65.5;  // hinge axis, behind back wall (y=60)
pivot_z = 20;    // hinge axis height: midway between closed lid plate
                 // (z 37..40) and open-flat lid plate (z 0..3)
knuckle_r = 4.5;
bore_r = 2.45;
pin_r = 1.9;

lid_segs  = [[6, 13], [33.5, 13], [61, 13]];   // [x_start, len]
base_segs = [[19.75, 13], [47.25, 13]];

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- shared hinge bore cutter (axis along x) ----------
// Bore starts at x=8: west end knuckle (lid, x 6..19) keeps a 2 mm blind cap,
// so the pin is captured west by that cap and east by its head.
module bore_cutter() {
    translate([8, pivot_y, pivot_z]) rotate([0, 90, 0])
        cylinder(h = 68, r = bore_r);
}

// ---------- base (print = assembly orientation) ----------
module base_part() {
    difference() {
        union() {
            // floor and four walls: hollow tray, interior 74 x 54 x 27
            cube([W, D, floor_t]);
            cube([W, wall, base_h]);                    // front
            translate([0, D - wall, 0]) cube([W, wall, base_h]); // back
            cube([wall, D, base_h]);                    // left
            translate([W - wall, 0, 0]) cube([wall, D, base_h]); // right
            // base hinge knuckles + webs tying them to the back wall
            for (s = base_segs) {
                translate([s[0], pivot_y, pivot_z]) rotate([0, 90, 0])
                    cylinder(h = s[1], r = knuckle_r);
                translate([s[0], 59.5, pivot_z - 3.2])
                    cube([s[1], 6.5, 6.4]);
            }
            // front catch nub, centred in the lid tab window
            translate([37.5, -0.5, 25.2]) cube([5, 0.5, 2.0]);
            // pin-head support post: foot from the floor edge, post top
            // 0.5 mm under the pin head so the pin starts over material
            translate([75, 57, 0]) cube([1.5, 9.8, 1]);
            translate([75, 64.2, 1]) cube([1.5, 2.6, 15.2]);
        }
        bore_cutter();
    }
}

// ---------- lid, built in closed (assembly) coordinates ----------
module lid_closed() {
    difference() {
        union() {
            // top plate
            translate([0, 0, total_h - plate_t]) cube([W, D, plate_t]);
            // perimeter skirt down to the base rim (z=30)
            translate([0, 0, base_h]) cube([W, wall, lid_h - plate_t]);
            translate([0, D - wall, base_h]) cube([W, wall, lid_h - plate_t]);
            translate([0, 0, base_h]) cube([wall, D, lid_h - plate_t]);
            translate([W - wall, 0, base_h]) cube([wall, D, lid_h - plate_t]);
            // hinge arms: knuckle + cheek down behind the back wall
            // (cheek front face y=61, 1.0 clear of back wall y=60) +
            // bridge over the back skirt
            for (s = lid_segs) {
                translate([s[0], pivot_y, pivot_z]) rotate([0, 90, 0])
                    cylinder(h = s[1], r = knuckle_r);
                translate([s[0], 61, pivot_z]) cube([s[1], 5.5, 10]);
                translate([s[0], 57, base_h]) cube([s[1], 5.5, 7]);
            }
            // front catch tab: two rails either side of the base nub,
            // top connector to the front skirt, bottom hook bar.
            // Window between rails x 37..43, z 24.8..34 houses the nub.
            translate([35, -2, 34]) cube([10, 2.5, 3]);       // connector
            translate([35, -2, 24]) cube([2, 1.6, 10]);       // rail L
            translate([43, -2, 24]) cube([2, 1.6, 10]);       // rail R
            translate([35, -2, 22.3]) cube([10, 1.6, 2.5]);   // hook bar
            translate([37, -0.4, 22.3]) cube([6, 0.08, 2.5]); // hook bump
        }
        bore_cutter();
    }
}

// lid in print orientation: top face on the bed, skirt up, hinge knuckles
// above the hinge-side edge. Rigid transform of lid_closed():
// rotate 180 about the hinge axis, then shift so the tray is y 0..60.
module lid_part() {
    translate([0, -71, 0])
        translate([0, pivot_y, pivot_z]) rotate([180, 0, 0])
            translate([0, -pivot_y, -pivot_z])
                lid_closed();
}

// ---------- pin, in assembly coordinates ----------
module pin_asm() {
    // shaft x 9..74.5 (1.0 clear of the west blind cap at x=8,
    // head face 0.5 clear of east knuckle end at x=74)
    translate([9, pivot_y, pivot_z]) rotate([0, 90, 0])
        cylinder(h = 65.5, r = pin_r);
    translate([74.5, pivot_y, pivot_z]) rotate([0, 90, 0])
        cylinder(h = 1.5, r = 3.3);
}

// pin in print orientation (standalone): standing on its shaft end.
module pin_part() {
    translate([3.3, 3.3, 0]) rotate([0, -90, 0])
        translate([-9, -pivot_y, -pivot_z]) pin_asm();
}

// ---------- specs (computed from the parameters above) ----------
hinge_zone_asm = [[5, 59, 2], [77, 71, 26]];

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[0, -0.5, 0], [W, pivot_y + knuckle_r, base_h]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge knuckles, webs and bore around the horizontal pin axis", hinge_zone_asm],
            ["underside of the small front catch nub", [[36, -1, 24], [44, 1, 28]]]
        ]],
        ["copies", 1],
        ["details", [
            ["floor", "material", [[2, 2, 0], [78, 58, 2.9]], 0.95],
            ["interior_cavity", "void", [[10, 10, 10], [70, 50, 29]], 0.95],
            ["base_knuckle_bore", "hole", [16, pivot_y, pivot_z], [1, 0, 0], [[0, 4.9], [12, 4.9]]],
            ["floor_thickness", "thickness", [40, 30, -5], [0, 0, 1], 3]
        ]]
    ]);
    base_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, -10, 0], [W, 62, pivot_z + knuckle_r]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge knuckles, arms and bore around the horizontal pin axis", [[5, -11, 2], [77, 5, 26]]],
            ["catch tab and hook, standing at the far edge in print orientation", [[34, 59, 2], [46, 63, 19]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_plate", "material", [[2, 2, 0], [78, 58, 2.9]], 0.95],
            ["lid_recess", "void", [[10, 10, 4], [70, 50, 9]], 0.95],
            ["lid_knuckle_bore", "hole", [30, -5.5, pivot_z], [1, 0, 0], [[0, 4.9], [12, 4.9]]],
            ["plate_thickness", "thickness", [40, 30, -5], [0, 0, 1], 3],
            ["catch_hook", "material", [[36, 60.5, 15.4], [44, 61.9, 17.5]], 0.9]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [6.6, 6.6, 67]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 10]]],
        ["overhangs_allowed", [
            ["underside of the pin head flange", [[0, 0, 64], [6.6, 6.6, 67.1]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_shaft", "material", [[2.4, 2.4, 10], [4.2, 4.2, 50]], 0.95],
            ["pin_diameter", "thickness", [-2, 3.3, 30], [1, 0, 0], 3.8]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, -2, 0], [W, pivot_y + knuckle_r, total_h]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0, pivot_y, pivot_z], [-1, 0, 0], [0, 180],
                ["flex", [["lid", "base", 1.0, "front catch hook flexes outward over the base nub while the lid opens and closes"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["rotate", [0, pivot_y, pivot_z], [-1, 0, 0], -20]],
            [["pin"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.5],
        ["print_pose", [["lid_swing", 180]]],
        ["overhangs_allowed", [
            ["hinge knuckles, webs, arms, bores and the in-place pin around the horizontal hinge axis (print pose)", hinge_zone_asm],
            ["underside of the small front catch nub (print pose)", [[36, -1, 24], [44, 1, 28]]],
            ["catch tab and hook at the far edge of the open lid (print pose)", [[34, 129, 2], [46, 134, 19]]]
        ]]
    ]);
    instance("base", "base") base_part();
    instance("lid", "lid") lid_closed();
    instance("pin", "pin") pin_asm();
}
