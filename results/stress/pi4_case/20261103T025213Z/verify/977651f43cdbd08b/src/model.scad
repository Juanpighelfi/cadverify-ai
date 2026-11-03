use <cadverify_parts.scad>

part = "base"; // [base, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
base_W = 91; base_D = 62; base_H = 26;
wall_t = 2; floor_t = 2;
board_X = 3; board_Y = 3; board_Z = 6;   // underside corner of the board in assembly
rim_Z = 26;                              // base rim = lid underside
lid_W = 96; lid_D = 67; lid_T = 3;
lid_X0 = -2.5; lid_Y0 = -2.5; lid_Z0 = 26; // lid plate corner in assembly
hook_top_print = 11;

// standoff centres (board holes: 3.5 in from edges, 58 x 49 apart)
so_x = [6.5, 64.5];
so_y = [6.5, 55.5];

module standoff(x, y) {
    translate([x, y, 1.5]) cylinder(r = 3, h = 4.5, $fn = 48);
}

module base() {
    difference() {
        union() {
            // floor
            cube([base_W, base_D, floor_t]);
            // walls
            cube([base_W, wall_t, base_H]);                          // south
            translate([0, base_D - wall_t, 0]) cube([base_W, wall_t, base_H]); // north
            translate([0, wall_t, 0]) cube([wall_t, base_D - 2*wall_t, base_H]); // west
            translate([base_W - wall_t, wall_t, 0]) cube([wall_t, base_D - 2*wall_t, base_H]); // east
            // standoffs (embedded 0.5 into the floor)
            for (x = so_x, y = so_y) standoff(x, y);
        }
        // south wall port notches (open top, through wall, sill at z=5)
        translate([8.9, -1, 5]) cube([10.6, 4, 22]);    // USB-C
        translate([24.95, -1, 5]) cube([8.1, 4, 22]);  // HDMI0
        translate([38.45, -1, 5]) cube([8.1, 4, 22]);  // HDMI1
        translate([53.2, -1, 5]) cube([7.6, 4, 22]);    // audio
        // east wall port notches (sill at z=5)
        translate([88, 4.45, 5]) cube([4, 15.1, 22]);   // USB lower
        translate([88, 22.75, 5]) cube([4, 14.1, 22]); // USB upper
        translate([88, 40.9, 5]) cube([4, 16.15, 22]); // Ethernet
        // west wall microSD notch (sill at z=3, under-board slot)
        translate([-1, 23, 3]) cube([4, 16, 24]);
        // snap pockets, 1 deep, z 18..21
        translate([40.5, -0.5, 18]) cube([10, 1.5, 3]); // south
        translate([40.5, 61, 18]) cube([10, 1.5, 3]);   // north
        translate([90, 26, 18]) cube([1.5, 10, 3]);    // east
        translate([-0.5, 26, 18]) cube([1.5, 10, 3]);  // west
        // M2.5 pilot holes, d2.2, blind (leave 1 above floor top... keep 1 web)
        for (x = so_x, y = so_y) translate([x, y, 2.5]) cylinder(d = 2.2, h = 3.7, $fn = 24);
    }
}

module hook_south() {
    translate([44, 0, 2.5]) cube([8, 2, 8.5]);
    translate([44, 2, 8]) cube([8, 0.8, 2]);
    hull() {
        translate([44, 2, 10]) cube([8, 0.8, 0.2]);
        translate([44, 1.9, 10.8]) cube([8, 0.2, 0.2]);
    }
}
module hook_north() {
    translate([44, 65, 2.5]) cube([8, 2, 8.5]);
    translate([44, 64.2, 8]) cube([8, 0.8, 2]);
    hull() {
        translate([44, 64.2, 10]) cube([8, 0.8, 0.2]);
        translate([44, 64.9, 10.8]) cube([8, 0.2, 0.2]);
    }
}
module hook_east() {
    translate([94, 29.5, 2.5]) cube([2, 8, 8.5]);
    translate([93.2, 29.5, 8]) cube([0.8, 8, 2]);
    hull() {
        translate([93.2, 29.5, 10]) cube([0.8, 8, 0.2]);
        translate([93.9, 29.5, 10.8]) cube([0.2, 8, 0.2]);
    }
}
module hook_west() {
    translate([0, 29.5, 2.5]) cube([2, 8, 8.5]);
    translate([2, 29.5, 8]) cube([0.8, 8, 2]);
    hull() {
        translate([2, 29.5, 10]) cube([0.8, 8, 0.2]);
        translate([1.9, 29.5, 10.8]) cube([0.2, 8, 0.2]);
    }
}

module lid() {
    difference() {
        union() {
            cube([lid_W, lid_D, lid_T]);
            hook_south(); hook_north(); hook_east(); hook_west();
        }
        // 6 vent slots over the processor, through the plate
        for (i = [0:5])
            translate([38, 22.5 + i*4, -0.5]) cube([20, 2, 4]);
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
            ["barb catch south", [[43.8, 1.8, 7.8], [52.2, 3.0, 8.2]]],
            ["barb catch north", [[43.8, 64.0, 7.8], [52.2, 65.2, 8.2]]],
            ["barb catch east", [[93.0, 29.3, 7.8], [94.2, 37.7, 8.2]]],
            ["barb catch west", [[1.8, 29.3, 7.8], [3.0, 37.7, 8.2]]]
        ]],
        ["details", [
            ["plate", "thickness", [48, 10, -1], [0, 0, 1], lid_T],
            ["vents", "void", [[38.1, 22.6, -0.2], [57.9, 44.4, 3.2]], 0.4],
            ["hook south", "material", [[44, 0, 3], [52, 2, 10]], 0.7],
            ["hook north", "material", [[44, 65, 3], [52, 67, 10]], 0.7],
            ["hook east", "material", [[94, 29.5, 3], [96, 37.5, 10]], 0.7],
            ["hook west", "material", [[0, 29.5, 3], [2, 37.5, 10]], 0.7]
        ]]
    ]);
    lid();
} else {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [base_W, base_D, base_H]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", 5000]]],
        ["overhangs_allowed", [
            ["pocket roof south", [[40.3, -0.1, 17.8], [50.7, 1.2, 21.2]]],
            ["pocket roof north", [[40.3, 60.8, 17.8], [50.7, 62.1, 21.2]]],
            ["pocket roof east", [[89.8, 25.8, 17.8], [91.2, 36.2, 21.2]]],
            ["pocket roof west", [[-0.2, 25.8, 17.8], [1.2, 36.2, 21.2]]]
        ]],
        ["details", [
            ["floor", "thickness", [45.5, 31, -1], [0, 0, 1], floor_t],
            ["wall south", "thickness", [70, -1, 13], [0, 1, 0], wall_t],
            ["usb-c opening", "void", [[9.0, 0.1, 5.1], [19.4, 1.9, 25.9]], 0.9],
            ["hdmi0 opening", "void", [[25.05, 0.1, 5.1], [32.95, 1.9, 25.9]], 0.9],
            ["hdmi1 opening", "void", [[38.55, 0.1, 5.1], [46.45, 1.9, 25.9]], 0.9],
            ["audio opening", "void", [[53.3, 0.1, 5.1], [60.7, 1.9, 25.9]], 0.9],
            ["usb lower opening", "void", [[89.1, 4.55, 5.1], [90.9, 19.45, 25.9]], 0.9],
            ["usb upper opening", "void", [[89.1, 22.55, 5.1], [90.9, 37.45, 25.9]], 0.9],
            ["ethernet opening", "void", [[89.1, 40.25, 5.1], [90.9, 57.25, 25.9]], 0.9],
            ["microsd opening", "void", [[0.1, 23.1, 3.1], [1.9, 38.9, 25.9]], 0.9],
            ["standoff", "material", [[3.5, 3.5, 2], [9.5, 9.5, 6]], 0.5],
            ["standoff pilot", "hole", [6.5, 6.5, 8], [0, 0, -1], [[0, 2.2], [2, 2.2]]],
            ["snap pocket south", "void", [[40.6, 0.05, 18.1], [50.4, 0.95, 20.9]], 0.9],
            ["snap pocket north", "void", [[40.6, 61.05, 18.1], [50.4, 61.95, 20.9]], 0.9],
            ["snap pocket east", "void", [[90.05, 26.1, 18.1], [90.95, 35.9, 20.9]], 0.9],
            ["snap pocket west", "void", [[0.05, 26.1, 18.1], [0.95, 35.9, 20.9]], 0.9]
        ]]
    ]);
    base();
}
