use <cadverify_parts.scad>

part = "base"; // [base, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
base_W = 93; base_D = 62; base_H = 26;
wall_t = 2; floor_t = 2;
board_X = 3; board_Y = 3; board_Z = 6;
lid_W = 98; lid_D = 67; lid_T = 3;
lid_X0 = -2.5; lid_Y0 = -2.5; lid_Z0 = 26;
hook_top_print = 11;

so_x = [6.5, 64.5];
so_y = [6.5, 55.5];

module standoff(x, y) {
    translate([x, y, 1.5]) cylinder(r = 3, h = 4.5, $fn = 48);
}

module base() {
    difference() {
        union() {
            cube([base_W, base_D, floor_t]);
            cube([base_W, wall_t, base_H]);
            translate([0, base_D - wall_t, 0]) cube([base_W, wall_t, base_H]);
            translate([0, wall_t, 0]) cube([wall_t, base_D - 2*wall_t, base_H]);
            translate([base_W - wall_t, wall_t, 0]) cube([wall_t, base_D - 2*wall_t, base_H]);
            for (x = so_x, y = so_y) standoff(x, y);
        }
        // south wall port notches (open top, through wall, sill z=5)
        translate([8.9, -1, 5]) cube([10.6, 4, 22]);    // USB-C
        translate([24.95, -1, 5]) cube([8.1, 4, 22]);  // HDMI0
        translate([38.45, -1, 5]) cube([8.1, 4, 22]);  // HDMI1
        translate([53.2, -1, 5]) cube([7.6, 4, 22]);    // audio
        // east wall port notches (sill z=5)
        translate([88, 4.45, 5]) cube([6, 15.1, 22]);   // USB lower
        translate([88, 22.75, 5]) cube([6, 14.1, 22]); // USB upper
        translate([88, 40.9, 5]) cube([6, 16.15, 22]); // Ethernet
        // west wall microSD notch (sill z=3)
        translate([-1, 23, 3]) cube([4, 16, 24]);
        // snap pockets, 1 deep into outer face, z 18..21, clear of ports
        translate([66.5, -0.5, 18]) cube([10, 1.5, 3]); // south
        translate([66.5, 61, 18]) cube([10, 1.5, 3]);   // north
        // M2.5 pilot holes, d2.2, blind
        for (x = so_x, y = so_y) translate([x, y, 2.5]) cylinder(d = 2.2, h = 3.7, $fn = 24);
    }
}

module hook_south() {
    translate([70, 0, 2.5]) cube([8, 2, 8.5]);
    translate([70, 2, 8]) cube([8, 0.8, 2]);
    hull() {
        translate([70, 2, 10]) cube([8, 0.8, 0.2]);
        translate([70, 1.9, 10.8]) cube([8, 0.2, 0.2]);
    }
}
module hook_north() {
    translate([70, 65, 2.5]) cube([8, 2, 8.5]);
    translate([70, 64.2, 8]) cube([8, 0.8, 2]);
    hull() {
        translate([70, 64.2, 10]) cube([8, 0.8, 0.2]);
        translate([70, 64.9, 10.8]) cube([8, 0.2, 0.2]);
    }
}

module lid() {
    difference() {
        union() {
            cube([lid_W, lid_D, lid_T]);
            hook_south(); hook_north();
        }
        for (i = [0:5])
            translate([30, 21.5 + i*4, -0.5]) cube([20, 2, 4]);
    }
}

if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[lid_X0, lid_Y0, 0], [lid_X0 + lid_W, lid_Y0 + lid_D, lid_Z0 + lid_T]]],
        ["support_faces", [["table", "-z", 5000]]],
        ["assembly_order", [
            [[ "base" ], [0, 0, 0]],
            [[ "board" ], [0, 0, -1]],
            [[ "lid" ], [0, 0, -1], ["flex", [["lid", "base", 0.6, "snap barbs ride over base walls"]]]]
        ]],
        ["held", ["lid"]]
    ]);
    instance("base", "base") base();
    instance("board", "standard:pi4_board") translate([board_X, board_Y, board_Z]) pi4_board();
    instance("lid", "lid") translate([-2.5, 64.5, 29]) rotate([180, 0, 0]) lid();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [lid_W, lid_D, hook_top_print]]],
        ["bodies", 1],
        ["through_holes", 6],
        ["support_faces", [["plate", "-z", 5500]]],
        ["overhangs_allowed", [
            ["barb catch south", [[69.8, 1.8, 7.8], [78.2, 3.0, 8.2]]],
            ["barb catch north", [[69.8, 64.0, 7.8], [78.2, 65.2, 8.2]]]
        ]],
        ["details", [
            ["plate", "thickness", [48, 10, -1], [0, 0, 1], lid_T],
            ["vents", "void", [[30.1, 21.6, -0.2], [49.9, 43.4, 3.2]], 0.4],
            ["hook south", "material", [[70, 0, 3], [78, 2, 10]], 0.7],
            ["hook north", "material", [[70, 65, 3], [78, 67, 10]], 0.7]
        ]]
    ]);
    lid();
} else {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [base_W, base_D, base_H]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", 5000]]],
        ["overhangs_allowed", [
            ["pocket roof south", [[66.3, -0.1, 17.8], [76.7, 1.2, 21.2]]],
            ["pocket roof north", [[66.3, 60.8, 17.8], [76.7, 62.1, 21.2]]]
        ]],
        ["details", [
            ["floor", "thickness", [46.5, 31, -1], [0, 0, 1], floor_t],
            ["wall south", "thickness", [30, -1, 13], [0, 1, 0], wall_t],
            ["usb-c opening", "void", [[9.0, 0.1, 5.1], [19.4, 1.9, 25.9]], 0.9],
            ["hdmi0 opening", "void", [[25.05, 0.1, 5.1], [32.95, 1.9, 25.9]], 0.9],
            ["hdmi1 opening", "void", [[38.55, 0.1, 5.1], [46.45, 1.9, 25.9]], 0.9],
            ["audio opening", "void", [[53.3, 0.1, 5.1], [60.7, 1.9, 25.9]], 0.9],
            ["usb lower opening", "void", [[91.1, 4.55, 5.1], [92.9, 19.45, 25.9]], 0.9],
            ["usb upper opening", "void", [[91.1, 22.85, 5.1], [92.9, 36.75, 25.9]], 0.9],
            ["ethernet opening", "void", [[91.1, 41.0, 5.1], [92.9, 56.95, 25.9]], 0.9],
            ["microsd opening", "void", [[0.1, 23.1, 3.1], [1.9, 38.9, 25.9]], 0.9],
            ["standoff", "material", [[3.5, 3.5, 2], [9.5, 9.5, 6]], 0.5],
            ["standoff pilot", "hole", [6.5, 6.5, 8], [0, 0, -1], [[0, 2.2], [2, 2.2]]],
            ["snap pocket south", "void", [[66.6, 0.05, 18.1], [76.4, 0.95, 20.9]], 0.9],
            ["snap pocket north", "void", [[66.6, 61.05, 18.1], [76.4, 61.95, 20.9]], 0.9]
        ]]
    ]);
    base();
}
