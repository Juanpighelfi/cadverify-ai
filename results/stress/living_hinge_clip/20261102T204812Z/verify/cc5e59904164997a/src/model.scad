// Bag clip with living hinge - PETG, 0.4mm nozzle, no supports
// Printed open flat, closes on 2mm folded bag. Latch hooks shut, thumb tab opens.
// Units: mm. Print orientation: +Z up, rests on z=0.

/* [Parts] */
part = "clip"; // [clip, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters
La = 100;      // arm length
W = 20;        // arm width (Y)
Ta = 4;        // arm thickness (Z)
Gh = 12;       // hinge gap in X (-6..6)
Th = 0.8;      // hinge thickness (2x0.4 nozzle)
TabL = 10;     // thumb tab length beyond top arm free end

Xmin = -106 - TabL;  // -116 tab tip
Xmax = 6 + La;       // 106 bottom nose
Ymin = 0; Ymax = W;
Zmin = 0; Zmax = Ta + 2; // 6 latch top

module clip() {
    // bottom arm 6..106
    translate([6, 0, 0]) cube([La, W, Ta]);
    // top arm -106..-6
    translate([-106, 0, 0]) cube([La, W, Ta]);
    // living hinge -6.02..6.02 (overlap into arms), full width, thin
    translate([-Gh/2 - 0.02, 0, 0]) cube([Gh + 0.04, W, Th]);
    // thumb tab -116..-105.98 (overlap into top arm)
    translate([Xmin, 0, 0]) cube([TabL + 0.02, W, Ta]);

    // inner grip teeth 0.6 tall, 2 wide, on inner faces (tops, become inner when closed)
    for (i = [0:9]) translate([16 + i*8, 0, Ta - 0.02]) cube([2, W, 0.62]);
    for (i = [0:9]) translate([-18 - i*8, 0, Ta - 0.02]) cube([2, W, 0.62]);
    // thumb grip ridges on tab top
    translate([-114, 0, Ta - 0.02]) cube([2, W, 0.62]);
    translate([-111, 0, Ta - 0.02]) cube([2, W, 0.62]);
    translate([-108, 0, Ta - 0.02]) cube([2, W, 0.62]);

    // bottom catch block 96..102, 7..12, 3.98..6 with 45deg top-outer chamfer
    difference() {
        translate([96, 7, Ta - 0.02]) cube([6, 5, 2.02]);
        translate([95.99, 0, 11]) rotate([0, 90, 0])
            linear_extrude(height = 6.04)
                polygon(points = [[6.01, 11], [6.01, 12.01], [4.99, 12.01]]);
    }
    // top hook block -102..-96, 11..16, 3.98..6 with 45deg bottom-inner chamfer
    difference() {
        translate([-102, 11, Ta - 0.02]) cube([6, 5, 2.02]);
        translate([-102.02, 0, 9]) rotate([0, 90, 0])
            linear_extrude(height = 6.04)
                polygon(points = [[5.01, 10.99], [3.99, 10.99], [3.99, 12.01]]);
    }
}

module assembly() {
    instance("clip_inst", "clip", 1) clip();
}

if (part == "clip") {
    echo(cadverify_spec = [
        ["bounds", [[Xmin, Ymin, Zmin], [Xmax, Ymax, Zmax]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bottom_arm", "material", [[6, 0, 0], [106, 20, 4]], 0.9],
            ["top_arm", "material", [[-106, 0, 0], [-6, 20, 4]], 0.9],
            ["thumb_tab", "material", [[-116, 0, 0], [-106, 20, 4]], 0.9],
            ["latch_bottom", "material", [[96, 7, 4], [102, 12, 6]], 0.8],
            ["latch_top", "material", [[-102, 11, 4], [-96, 16, 6]], 0.8],
            ["hinge_gap", "void", [[-6, 0, 0.8], [6, 20, 4]], 0.9],
            ["hinge_thin", "thickness", [0, 10, 5], [0, 0, -1], 0.8],
            ["arm_thickness", "thickness", [56, 10, 10], [0, 0, -1], 4.0],
            ["teeth", "view", [[14, 0, 4], [92, 20, 4.8]]],
            ["latch_detail", "view", [[94, 5, 4], [104, 18, 6]]]
        ]]
    ]);
    clip();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[Xmin, Ymin, Zmin], [Xmax, Ymax, Zmax]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["closing", ["clip_inst"], "slide", [1, 0, 0], [0, 20]]
        ]],
        ["assembly_order", [
            [["clip_inst"], [0, 0, 0]]
        ]]
    ]);
    assembly();
}
