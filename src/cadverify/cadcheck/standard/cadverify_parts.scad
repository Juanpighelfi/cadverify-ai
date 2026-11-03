// Standard parts, drawn from their datasheets, for an assembly to place what it holds or fits:
//
//     use <cadverify_parts.scad>
//     instance("board", "standard:pi4_board") translate([x, y, z]) pi4_board();
//
// The harness exports the module itself and checks that the instance is it, moved (the same
// volume, area and principal moments): the design then has to fit the real part, not a block of
// its own drawing. A part a standard sizes within limits is drawn at its largest.

// A Raspberry Pi 4 Model B, from the official mechanical drawing (RP-008343-DS-1): the board,
// 85 x 56 x 1.4 mm with 3 mm corners, its four 2.7 mm holes (3.5 mm in from the left and bottom
// edges, 58 x 49 mm apart) and the bodies of what stands on it, to the heights the drawing gives.
// Origin: the bottom left corner of the board's underside; the USB-C, the two micro-HDMI and the
// audio jack face -y, the USB and Ethernet face +x, components on +z. Not in it: the microSD slot
// and anything under the board (the drawing shows neither).
module pi4_board() {
    difference() {
        hull() for (x = [3, 82], y = [3, 53]) translate([x, y, 0]) cylinder(r = 3, h = 1.4, $fn = 48);
        for (x = [3.5, 61.5], y = [3.5, 52.5]) translate([x, y, -1]) cylinder(d = 2.7, h = 3.4, $fn = 32);
    }
    translate([0, 0, 1.4]) {
        // USB-C power, 3.2 mm tall, and the two micro-HDMI, 3.0 mm tall, over the bottom edge.
        translate([11.2 - 4.5, -1.3, 0]) cube([9, 7.5, 3.2]);
        for (x = [26, 39.5]) translate([x - 3.25, -1.4, 0]) cube([6.5, 7.6, 3.0]);
        // The audio jack, 6 mm tall, its barrel out past the edge.
        translate([54 - 3, 0, 0]) cube([6, 11.5, 6]);
        translate([54, 0, 3]) rotate([90, 0, 0]) cylinder(d = 6, h = 2.5, $fn = 32);
        // Ethernet (13.5 mm tall) and the two USB stacks (16 mm), 3.2 mm out past the right edge.
        translate([66.7, 45.75 - 7.8, 0]) cube([21.5, 15.6, 13.5]);
        for (y = [9, 27]) translate([70.6, y - 6.75, 0]) cube([17.6, 13.5, 16]);
        // The 40-pin header, 8.5 mm tall.
        translate([32.5 - 25.4, 52.5 - 2.54, 0]) cube([50.8, 5.08, 8.5]);
    }
}

// A 608 ball bearing (ISO 15 series, 8 x 22 x 7 mm). Origin: the center of one face; axis z.
module bearing_608() {
    difference() {
        cylinder(d = 22, h = 7, $fn = 96);
        translate([0, 0, -1]) cylinder(d = 8, h = 9, $fn = 48);
    }
}

// An AA cell (IEC LR6) at its largest: 14.5 mm across and 50.5 mm long over its positive
// terminal (5.5 mm across, 1 mm tall). Origin: the center of the negative end; + toward +z.
module aa_cell() {
    cylinder(d = 14.5, h = 49.5, $fn = 64);
    translate([0, 0, 49.5]) cylinder(d = 5.5, h = 1, $fn = 32);
}

// An M3 hex nut (ISO 4032) at its largest: 5.5 mm across flats, 2.4 mm thick, with a 3 mm hole.
// Origin: the center of one face; axis z, two flats parallel to x.
module m3_nut() {
    difference() {
        cylinder(d = 5.5 / cos(30), h = 2.4, $fn = 6);
        translate([0, 0, -1]) cylinder(d = 3, h = 4.4, $fn = 24);
    }
}
