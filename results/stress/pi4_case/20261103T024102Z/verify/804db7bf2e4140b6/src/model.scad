// Two-part case for a Raspberry Pi 4 Model B (PLA, Bambu Lab A1, 0.4 mm nozzle, no supports).
//
// Assembly coordinates: x east (USB/Ethernet end), y north (GPIO side), z up.
// The board sits at translate([3,3,4.4]): its underside is on four standoffs (floor 2 mm +
// standoff 2.4 mm).  Base outer 91 x 62 x 14 mm.  The lid is a cover whose skirt
// (outer 95 x 66 mm, walls 1.8 mm) slides over the base with 0.2 mm clearance per side;
// its underside ceiling is at z = 22.6 mm, clear of the 16 mm USB stacks (top z = 21.8 mm).
// Snap ribs on the base (y = +/- faces, z 10.2..11.0 mm) engage grooves inside the lid skirt.
//
// Ports (board coords + [3,3]): USB-C / 2x micro-HDMI / audio face -y (south wall of the
// base, windows open at the top of that wall so the board drops straight in); USB x2 and
// Ethernet face +x (east wall, likewise); microSD faces -x under the board (west wall,
// gable-roofed window: its 45 deg slopes are not overhangs, and the card passes the
// 14 mm wide lower part).  The lid skirt repeats the east windows and has notches over
// the south ports so plugs clear it while the case is closed.
//
// Print orientation: base as assembled (floor on the bed).  The lid is printed top-down
// (its top face on the bed, skirt pointing up, cavity open upward): no ceilings except
// the shallow snap-groove roofs.

use <cadverify_parts.scad>

part = "assembly"; // [base, lid, assembly]

$fn = 36;

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ================= base (print coords == assembly coords) ================= */

module base_part() {
    difference() {
        union() {
            // floor and four walls: outer 91 x 62 x 14, wall 2, floor 2
            difference() {
                cube([91, 62, 14]);
                translate([2, 2, 2]) cube([87, 58, 13]);
            }
            // standoffs: d6, floor top (z2) to board underside (z4.4), at the board holes
            for (x = [6.5, 64.5], y = [6.5, 55.5])
                translate([x, y, 2]) cylinder(d = 6, h = 2.4);
            // snap ribs, protrude 0.5, z 10.2..11.0
            translate([20, 62, 10.2]) cube([51, 0.5, 0.8]);      // north, clear of ports
            translate([21, -0.5, 10.2]) cube([3, 0.5, 0.8]);     // south, on wall pillars
            translate([34.5, -0.5, 10.2]) cube([3, 0.5, 0.8]);   // (between the port windows)
            translate([48, -0.5, 10.2]) cube([4, 0.5, 0.8]);
        }
        // M2.5 pilot holes, d2.2, from standoff top down to z1 (blind)
        for (x = [6.5, 64.5], y = [6.5, 55.5])
            translate([x, y, 1]) cylinder(d = 2.2, h = 4);
        // south port windows, open at the top of the wall (z5..15), board drops straight in
        translate([8.7, -1, 5]) cube([11, 4, 10]);     // USB-C   (port x 9.7..18.7)
        translate([24.75, -1, 5]) cube([8.5, 4, 10]);  // HDMI 1  (port x 25.75..32.25)
        translate([38.25, -1, 5]) cube([8.5, 4, 10]);  // HDMI 2  (port x 39.25..45.75)
        translate([53, -1, 5]) cube([8, 4, 10]);       // audio   (port x 54..60)
        // east port windows, open at the top of the wall
        translate([88, 4.5, 5]) cube([4, 15, 10]);     // USB 1   (port y 5.25..18.75)
        translate([88, 22.5, 5]) cube([4, 15, 10]);    // USB 2   (port y 23.25..36.75)
        translate([88, 40.2, 5]) cube([4, 17.1, 10]);  // Ethernet(port y 40.95..56.55)
        // microSD window in the west wall: 14 wide under the board, 45 deg gable roof
        translate([3, 0, 0]) rotate([0, -90, 0])
            linear_extrude(height = 4)
                polygon(points = [[2.2, 21], [2.2, 35], [4.6, 35], [11.6, 28], [4.6, 21]]);
    }
}

/* ================= lid, drawn in assembly coords, then flipped to print ================= */

module lid_asm() {
    difference() {
        union() {
            translate([-2, -2, 22.6]) cube([95, 66, 2]);       // top plate, ceiling z22.6
            difference() {                                     // skirt z8..22.6, wall 1.8
                translate([-2, -2, 8]) cube([95, 66, 14.6]);
                translate([-0.2, -0.2, 7]) cube([91.4, 62.4, 15.6]);
            }
        }
        // vents over the processor (board SoC area), 5 slots 22 x 1.8 through the top
        for (i = [0 : 4]) translate([36, 26 + i * 3.4, 22]) cube([22, 1.8, 3]);
        // east windows in the skirt, continuing the base windows (notches from skirt rim)
        translate([90, 4.5, 8]) cube([4, 15, 14.2]);    // USB 1, up to z22.2
        translate([90, 22.5, 8]) cube([4, 15, 14.2]);   // USB 2
        translate([90, 40.2, 8]) cube([4, 17.1, 11.9]); // Ethernet, up to z19.9
        // south notches in the skirt so plugs reach the south ports with the lid on
        translate([8.7, -3, 8]) cube([11, 4, 1.6]);     // USB-C, up to z9.6
        translate([24.75, -3, 8]) cube([8.5, 4, 1.4]);  // HDMI 1, up to z9.4
        translate([38.25, -3, 8]) cube([8.5, 4, 1.4]);  // HDMI 2
        translate([53, -3, 8]) cube([8, 4, 4.4]);       // audio, up to z12.4
        // snap grooves inside the skirt: z10..11.2, 0.7 deep, for the base ribs
        translate([18, 61.9, 10]) cube([55, 1.0, 1.2]);   // north (starts inside the cavity)
        translate([4, -0.9, 10]) cube([83, 1.0, 1.2]);    // south
    }
}

module lid_part() {
    // assembly -> print: (x, y, z) -> (x + 2, 64 - y, 24.6 - z); top face on the bed
    translate([2, 64, 24.6]) rotate([180, 0, 0]) lid_asm();
}

/* ================= output ================= */

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[0, -0.5, 0], [91, 62.5, 14]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 5600]]],
        ["overhangs_allowed", [
            ["north snap rib underside", [[19, 61.5, 9.6], [72, 63, 10.4]]],
            ["south snap rib undersides", [[19, -1, 9.6], [53, 0.5, 10.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["base floor", "thickness", [45, 31, -2], [0, 0, 1], 2],
            ["front wall", "thickness", [22, -2, 7], [0, 1, 0], 2],
            ["standoff", "material", [[3.5, 3.5, 2], [9.5, 9.5, 4.4]], 0.55],
            ["screw pilot", "hole", [6.5, 6.5, 8], [0, 0, -1], [[0, 2.2], [2, 2.2], [3, 2.2]]],
            ["usb-c opening", "void", [[8.7, 0, 5], [19.7, 2, 9.4]], 0.9],
            ["ethernet opening", "void", [[89, 40.2, 5], [91, 57.3, 14]], 0.9],
            ["microsd opening", "void", [[0, 21, 2.2], [2, 35, 4.6]], 0.9],
            ["north snap rib", "material", [[20, 62, 10.2], [71, 62.5, 11.0]], 0.85]
        ]]
    ]);
    base_part();
} else if (part == "lid") {
    // spec in print coordinates (top face on the bed, skirt up)
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [95, 66, 16.6]]],
        ["bodies", 1],
        ["through_holes", 5],
        ["support_faces", [["bed", "-z", 5900]]],
        ["overhangs_allowed", [
            ["north snap groove roof", [[19, 0.5, 13], [76, 2.5, 15]]],
            ["south snap groove roof", [[5, 63.5, 13], [89, 65.5, 15]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid top", "thickness", [12, 54, -2], [0, 0, 1], 2],
            ["processor vents", "void", [[38, 22.6, 0], [60, 38, 2]], 0.5],
            ["lid usb opening", "void", [[93.2, 44.5, 2.4], [95, 59.5, 16.6]], 0.9],
            ["north snap groove", "void", [[20, 1.1, 13.4], [75, 1.8, 14.6]], 0.85],
            ["skirt wall", "thickness", [20, 68, 8], [0, -1, 0], 1.8]
        ]]
    ]);
    lid_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-2, -2, 0], [93, 64, 24.6]]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["board"], [0, 0, -1]],
            [["lid"], [0, 0, -1],
                ["flex", [["lid", "base", 0.4, "snap ribs ride over the lid skirt into their grooves"]]]]
        ]],
        ["held", ["lid"]]
    ]);
    instance("base", "base") base_part();
    instance("board", "standard:pi4_board") translate([3, 3, 4.4]) pi4_board();
    // print -> assembly is the inverse of the flip in lid_part()
    instance("lid", "lid") translate([-2, 64, 24.6]) rotate([180, 0, 0]) lid_part();
}
