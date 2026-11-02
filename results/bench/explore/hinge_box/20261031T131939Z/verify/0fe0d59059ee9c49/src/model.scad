/* Box with print-in-place hinge - PLA, 0.4 mm nozzle, Bambu Lab A1, no supports.
   Closed outside ~80 x 60 x 40.5 (lid 10). Hinge on back edge: 5 alternating
   knuckles (3 box / 2 lid) around a pin printed in place. Vertical gap 0.5,
   radial pin clearance 0.5, axial knuckle gaps 0.5: breaks free by hand.
   Print orientation = assembly orientation (+Z up). Assembly = closed box. */

part = "assembly"; // [box:Box, lid:Lid, pin:Pin, assembly:Assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
yA = -32; zA = 30.5;      // hinge axis (y, z), along X
knOD = 8; boreD = 5; pinD = 4; headD = 5; headL = 2.5;

module box_part() {
    difference() {
        union() {
            translate([-40, -30, 0]) cube([80, 60, 30]);
            for (x0 = [-30, -5.8, 18.4])
                translate([x0, yA, zA]) rotate([0, 90, 0])
                    cylinder(d = knOD, h = 11.6, $fn = 64);
            for (x = [-4, 4])
                translate([x, 28.8, 30]) cylinder(d = 2, h = 1.5, $fn = 32);
        }
        translate([-37.6, -27.6, 2.4]) cube([75.2, 55.2, 27.6]);
        for (x0 = [-30, -5.8, 18.4])
            translate([x0 - 0.1, yA, zA]) rotate([0, 90, 0])
                cylinder(d = boreD, h = 11.8, $fn = 48);
        // hinge slots where lid knuckles descend (disc path + channel)
        for (xs = [[-18.4, -5.8], [5.8, 18.4]]) {
            translate([xs[0] - 0.5, -36.3, 26]) cube([(xs[1] + 0.5) - (xs[0] - 0.5), 8.6, 4.5]);
            translate([xs[0] - 0.5, yA, zA]) rotate([0, 90, 0])
                cylinder(r = 4.5, h = (xs[1] + 0.5) - (xs[0] - 0.5), $fn = 64);
        }
        // pin head notch in back wall top
        translate([30.6, -31, 27.4]) cube([9.4, 2.1, 3.1]);
    }
}

module lid_part() {
    difference() {
        union() {
            translate([-40, -30, 30.5]) cube([80, 60, 10]);
            for (x0 = [-17.9, 6.3])
                translate([x0, yA, zA]) rotate([0, 90, 0])
                    cylinder(d = knOD, h = 11.6, $fn = 64);
        }
        for (x0 = [-17.9, 6.3])
            translate([x0 - 0.1, yA, zA]) rotate([0, 90, 0])
                cylinder(d = boreD, h = 11.8, $fn = 48);
        // channels clearing box knuckles through full swing (coaxial)
        for (xs = [[-30, -18.4], [-5.8, 5.8], [18.4, 30]])
            translate([xs[0] - 0.5, yA, zA]) rotate([0, 90, 0])
                cylinder(r = 4.5, h = (xs[1] + 0.5) - (xs[0] - 0.5), $fn = 64);
        // pin head guide channel, open at right face
        translate([30.3, yA, zA]) rotate([0, 90, 0])
            cylinder(r = 3.3, h = 9.8, $fn = 48);
        // catch peg holes
        for (x = [-4, 4])
            translate([x, 28.8, 30.5]) cylinder(d = 2.8, h = 1.9, $fn = 32);
    }
}

module pin_part() {
    union() {
        translate([-30, yA, zA]) rotate([0, 90, 0])
            cylinder(d1 = 3, d2 = pinD, h = 0.5, $fn = 48);
        translate([-29.5, yA, zA]) rotate([0, 90, 0])
            cylinder(d = pinD, h = 60.1, $fn = 48);
        translate([30.6, yA, zA]) rotate([0, 90, 0])
            cylinder(d = headD, h = headL, $fn = 48);
    }
}

if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 34.5]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 600]]],
        ["overhangs_allowed", [
            ["hinge_curves", [[-31, -37, 26], [31, -27, 35]]]
        ]],
        ["copies", 1],
        ["details", [
            ["wall", "material", [[-40, -30, 0], [-37.6, 30, 30]], 0.9],
            ["floor", "material", [[-30, -20, 0], [30, 20, 2.4]], 0.9],
            ["knuckle", "material", [[-30, -36, 26.5], [-18.4, -28, 34.5]], 0.45],
            ["peg", "material", [[-5, 27.8, 30], [-3, 29.8, 31.5]], 0.6],
            ["slot", "void", [[-18.4, -30.5, 26], [-5.8, -27.5, 30.5]], 0.85],
            ["head_notch", "void", [[30.6, -31, 27.4], [40, -28.9, 30.5]], 0.9],
            ["bore", "hole", [-31, -32, 30.5], [1, 0, 0], [[0, 5], [10, 5]]],
            ["wall_thick", "thickness", [41, 0, 15], [-1, 0, 0], 2.4],
            ["floor_thick", "thickness", [0, 0, -1], [0, 0, 1], 2.4],
            ["slot_view", "view", [[-18.4, -31, 26], [-5.8, -27, 31]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 26.5], [40, 30, 40.5]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["hinge_curves", [[-31, -37, 26], [40.5, -27, 35]]],
            ["lid_bridge", [[-40, -30, 30.49], [40, 30, 30.51]]],
            ["peg_holes", [[-5.5, 27.5, 30.5], [5.5, 30.1, 32.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["slab_top", "material", [[-30, 0, 38], [30, 20, 40.5]], 0.9],
            ["knuckle", "material", [[-17.9, -36, 26.5], [-6.3, -28, 34.5]], 0.45],
            ["channel", "void", [[-30.5, -36.5, 26], [-17.9, -27.5, 35]], 0.9],
            ["head_channel", "void", [[30.3, -35.3, 27.2], [40, -28.7, 33.8]], 0.9],
            ["bore", "hole", [-18.15, -32, 30.5], [1, 0, 0], [[0, 5], [10, 5]]],
            ["peg_hole", "void", [[-5.4, 27.4, 30.5], [-2.6, 30.2, 32.4]], 0.5],
            ["lid_thick", "thickness", [0, 20, 41.5], [0, 0, -1], 10],
            ["channel_view", "view", [[-30, -37, 26], [-18, -27, 35]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-30, -34.5, 28], [33.1, -29.5, 33]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["shaft_under", [[-29.6, -33.5, 28.4], [30.7, -30.5, 29.2]]],
            ["head_under", [[30.5, -33.9, 27.9], [33.2, -30.1, 28.9]]]
        ]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-29.5, -34, 28.5], [30.6, -30, 32.5]], 0.6],
            ["head", "material", [[30.6, -34.5, 28], [33.1, -29.5, 33]], 0.6],
            ["shaft_dia", "thickness", [10, -32, 34], [0, 0, -1], 4],
            ["head_view", "view", [[30, -35, 27.5], [33.5, -29, 33.5]]]
        ]]
    ]);
    pin_part();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 40.5]]],
        ["support_faces", [["bed", "-z", 600]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0, -32, 30.5], [1, 0, 0], [0, 110]]
        ]],
        ["assembly_order", [
            [["box"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["rotate", [0, -32, 30.5], [1, 0, 0], -110]],
            [["pin"], [-1, 0, 0]]
        ]]
    ]);
    instance("box", "box") box_part();
    instance("lid", "lid") lid_part();
    instance("pin", "pin") pin_part();
}
