// Bag clip with living hinge - PETG, 0.4mm nozzle, no supports
// One piece, printed open flat. Lower arm + upper arm meet at hinge mid-plane.
// Fold map (180 about pivot): F(x) = 216 - x, F(z) = 10.4 - z.

part = "arm_lower"; // [arm_lower, arm_upper, assembly]
cadverify_only = "";

Lbody = 100;
Wbody = 20;
Tbody = 3.2;
Hhalf = 8;
Thinge = 0.6;
Bgap = 2.0;
Xpiv = 108;
Zpiv = 5.2;

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module arm_lower() {
    cube([Lbody, Wbody, Tbody], false);
    translate([Lbody-0.1, 0, 0])
        cube([Hhalf+0.1, Wbody, Thinge], false);
    translate([10, 1, Tbody-0.1])
        cube([80, 1.5, Bgap+0.1], false);
    translate([10, 17.5, Tbody-0.1])
        cube([80, 1.5, Bgap+0.1], false);
    translate([2, 5, Tbody-0.1])
        cube([6, 10, Bgap+0.1], false);
    translate([7.9, 6, 4.7])
        cube([2.1, 8, 0.5], false);
}

module arm_upper() {
    cube([Hhalf+0.1, Wbody, Thinge], false);
    translate([Hhalf-0.1, 0, 0])
        cube([Lbody+0.1, Wbody, Tbody], false);
    translate([100, 5, Tbody-0.1])
        cube([6, 10, Bgap+0.1], false);
    translate([97.9, 6, 4.6])
        cube([2.5, 8, 0.5], false);
    translate([107.9, 6, 0])
        cube([8.1, 8, Tbody], false);
}

if (part == "arm_lower") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [108, 20, 5.2]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", [["latch lip", [[7.5, 5.5, 4.5], [10.5, 14.5, 5.5]]]]],
        ["copies", 1],
        ["details", [
            ["arm", "material", [[20, 6, 1.0], [80, 14, 2.2]], 1],
            ["arm_wall", "thickness", [50, 10, 10], [0, 0, -1], 3.2],
            ["hinge", "thickness", [104, 10, 5], [0, 0, -1], 0.6],
            ["rib", "material", [[20, 1.2, 3.5], [80, 2.3, 5.0]], 1],
            ["latch_tower", "material", [[3, 6, 3.5], [7, 14, 5.0]], 1],
            ["latch_lip", "material", [[8.2, 7, 4.8], [9.7, 13, 5.1]], 1],
            ["bag_slot", "void", [[20, 3, 3.5], [80, 17, 5.0]], 1]
        ]]
    ]);
    arm_lower();
} else if (part == "arm_upper") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [116, 20, 5.2]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", [["latch lip", [[97.5, 5.5, 4.5], [100.8, 14.5, 5.5]]]]],
        ["copies", 1],
        ["details", [
            ["arm", "material", [[15, 6, 1.0], [80, 14, 2.2]], 0.99],
            ["arm_wall", "thickness", [50, 10, 10], [0, 0, -1], 3.2],
            ["hinge", "thickness", [4, 10, 5], [0, 0, -1], 0.6],
            ["latch_tower", "material", [[100.5, 6, 3.5], [105.5, 14, 5.0]], 1],
            ["latch_lip", "material", [[98.2, 7, 4.8], [100.1, 13, 5.1]], 1],
            ["thumb_tab", "material", [[108.5, 7, 1.0], [115, 13, 2.2]], 1],
            ["field", "void", [[15, 3, 3.5], [80, 17, 5.0]], 1]
        ]]
    ]);
    arm_upper();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [224, 20, 5.2]]],
        ["support_faces", [["bed", "-z", 3000]]],
        ["motions", [
            ["close", ["upper"], "rotate", [108, 10, 5.2], [0, -1, 0], [0, 180],
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
    instance("upper", "arm_upper") translate([108, 0, 0]) arm_upper();
}
