// Bag clip with living hinge - PETG, 0.4mm nozzle, no supports
// Printed open flat (two arms end-to-end), closes by folding 180deg about Y.
// Lower arm at origin, upper arm local origin at its hinge edge.

part = "arm_lower"; // [arm_lower, arm_upper, assembly]
cadverify_only = "";

/* Dimensions (mm) */
Lbody = 100;      // arm body length
Wbody = 20;       // arm width
Tbody = 3.2;      // arm thickness
Hhinge = 6;       // total hinge length (gap between bodies)
Hhalf = 3;        // hinge half length per arm
Thinge = 0.6;     // hinge thickness
Bgap = 2.0;       // bag thickness / closed gap
Ttot = Tbody + Bgap; // 5.2 closed inner top
Zpiv = Tbody + Bgap/2; // 4.2 pivot height
Xpiv = Lbody + Hhalf;  // 103 pivot X in assembly

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- lower arm geometry (print orientation, min at 0) ----------
module arm_lower() {
    // body
    cube([Lbody, Wbody, Tbody], false);
    // hinge half (thin, on bed), overlap 0.1 into body
    translate([Lbody-0.1, 0, 0])
        cube([Hhalf+0.1, Wbody, Thinge], false);
    // ribs (2mm tall standoff), overlap 0.1 into body
    translate([10, 1, Tbody-0.1])
        cube([80, 1.5, Bgap+0.1], false);
    translate([10, 17.5, Tbody-0.1])
        cube([80, 1.5, Bgap+0.1], false);
    // latch tower, overlap into body
    translate([2, 5, Tbody-0.1])
        cube([6, 10, Bgap+0.1], false);
    // latch lip (cantilever +X), overlap into tower
    translate([7.9, 6, 4.3])
        cube([2.1, 8, 0.9], false);
}

// ---------- upper arm geometry (print orientation, hinge at x=0) ----------
module arm_upper() {
    // hinge half on bed
    cube([Hhalf+0.1, Wbody, Thinge], false);
    // body, overlap into hinge
    translate([Hhalf-0.1, 0, 0])
        cube([Lbody+0.1, Wbody, Tbody], false);
    // latch tower (maps to closed x=12-18), overlap into body
    translate([85, 5, Tbody-0.1])
        cube([6, 10, Bgap+0.1], false);
    // latch lip (extends +X toward free end), overlap into tower
    translate([90.9, 6, 4.2])
        cube([3.1, 8, 1.0], false);
    // thumb tab beyond free end, same thickness as body, overlap
    translate([102.9, 6, 0])
        cube([8.1, 8, Tbody], false);
}

// ---------- part / assembly dispatch ----------
if (part == "arm_lower") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [103, 20, 5.2]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", [["latch lip", [[7.5, 5.5, 4.0], [10.5, 14.5, 5.5]]]]],
        ["copies", 1],
        ["details", [
            ["arm", "material", [[10, 5, 0.5], [90, 15, 2.7]], 1],
            ["arm_wall", "thickness", [50, 10, 10], [0, 0, -1], 3.2],
            ["hinge", "thickness", [101.5, 10, 5], [0, 0, -1], 0.6],
            ["rib", "material", [[20, 1.2, 3.5], [80, 2.3, 5.0]], 1],
            ["latch_tower", "material", [[3, 6, 3.5], [7, 14, 5.0]], 1],
            ["latch_lip", "material", [[8.5, 7, 4.5], [9.5, 13, 5.0]], 1],
            ["bag_slot", "void", [[20, 3, 3.5], [80, 17, 5.0]], 1]
        ]]
    ]);
    arm_lower();
} else if (part == "arm_upper") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [111, 20, 5.2]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", [["latch lip", [[90.5, 5.5, 4.0], [94.5, 14.5, 5.5]]]]],
        ["copies", 1],
        ["details", [
            ["arm", "material", [[10, 5, 0.5], [80, 15, 2.7]], 1],
            ["arm_wall", "thickness", [50, 10, 10], [0, 0, -1], 3.2],
            ["hinge", "thickness", [1.5, 10, 5], [0, 0, -1], 0.6],
            ["latch_tower", "material", [[86, 6, 3.5], [90, 14, 5.0]], 1],
            ["latch_lip", "material", [[91.5, 7, 4.4], [93.5, 13, 5.0]], 1],
            ["thumb_tab", "material", [[104, 7, 0.5], [110, 13, 2.7]], 1],
            ["field", "void", [[10, 3, 3.5], [80, 17, 5.0]], 1]
        ]]
    ]);
    arm_upper();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [214, 20, 5.2]]],
        ["support_faces", [["bed", "-z", 3000]]],
        ["motions", [
            ["close", ["upper"], "rotate", [103, 10, 4.2], [0, 1, 0], [0, 180],
                ["flex", [["upper", "lower", 1.0, "latch snap"]]],
                ["stops", [180]]
            ]
        ]],
        ["assembly_order", [
            [["lower"], [0, 0, 0]],
            [["upper"], [0, 0, -1]]
        ]]
    ]);
    instance("lower", "arm_lower") arm_lower();
    instance("upper", "arm_upper") translate([103, 0, 0]) arm_upper();
}
