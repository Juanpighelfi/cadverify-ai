// Bag clip living hinge, PETG, 0.4 nozzle, no supports.
// Two halves contacting at hinge, open flat print pose.
// Fold: rotate upper 180 about [108,10,5.2] -Y. F(x)=216-x, F(z)=10.4-z.

part = "arm_lower"; // [arm_lower, arm_upper, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module arm_lower() {
    cube([100, 20, 3.2], false);
    translate([99.9, 0, 0]) cube([8.2, 20, 0.6], false);
    translate([10, 1, 3.1]) cube([80, 1.5, 2.1], false);
    translate([10, 17.5, 3.1]) cube([80, 1.5, 2.1], false);
    // stop tower (central)
    translate([2, 9, 3.1]) cube([6, 6, 2.1], false);
    // lower hook base region uses body; hook lip + bridge
    translate([6, 5, 4.7]) cube([3, 2, 0.5], false);
    translate([6, 6.9, 4.7]) cube([2, 2.2, 0.5], false);
}

module arm_upper() {
    cube([8.2, 20, 0.6], false);
    translate([7.9, 0, 0]) cube([100.1, 20, 3.2], false);
    // stop tower (central) local x 102-106 -> folded 2-6
    translate([102, 9, 3.1]) cube([4, 6, 2.1], false);
    // upper hook post (Y 13-15) tall
    translate([102, 13, 3.1]) cube([4, 2, 3.3], false);
    // Y bridge 7-13
    translate([99, 6.9, 5.8]) cube([3.1, 6.2, 0.6], false);
    // upper hook lip (Y 5-7)
    translate([99, 5, 5.8]) cube([3.1, 2, 0.6], false);
    // thumb tab
    translate([107.9, 6, 0]) cube([8.1, 8, 3.2], false);
}

if (part == "arm_lower") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [108.1, 20, 5.2]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", [["latch lip", [[5.5, 4.5, 4.5], [9.5, 9.5, 5.5]]]]],
        ["copies", 1],
        ["details", [
            ["arm", "material", [[30, 10, 1.2], [70, 12, 2.0]], 1],
            ["arm_wall", "thickness", [50, 10, 10], [0, 0, -1], 3.2],
            ["hinge", "thickness", [104, 10, 5], [0, 0, -1], 0.6],
            ["rib", "material", [[30, 1.3, 3.8], [70, 2.2, 4.8]], 1],
            ["rib2", "material", [[30, 17.8, 3.8], [70, 18.7, 4.8]], 1],
            ["latch_tower", "material", [[3, 10, 3.8], [7, 14, 5.0]], 1],
            ["latch_lip", "material", [[6.5, 5.5, 4.8], [8.5, 6.5, 5.1]], 1],
            ["bag_slot", "void", [[30, 4, 3.8], [70, 16, 5.0]], 1]
        ]]
    ]);
    arm_lower();
} else if (part == "arm_upper") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [116, 20, 6.4]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", [["latch lip", [[98.5, 4.5, 5.6], [102.5, 13.5, 6.6]]]]],
        ["copies", 1],
        ["details", [
            ["arm", "material", [[30, 10, 1.2], [70, 12, 2.0]], 1],
            ["arm_wall", "thickness", [50, 10, 10], [0, 0, -1], 3.2],
            ["hinge", "thickness", [4, 10, 5], [0, 0, -1], 0.6],
            ["latch_tower", "material", [[102.5, 10, 3.8], [105.5, 14, 5.0]], 1],
            ["latch_lip", "material", [[99.5, 5.5, 5.9], [101.5, 6.5, 6.3]], 0.99],
            ["thumb_tab", "material", [[109, 7, 1.2], [114, 13, 2.0]], 0.99],
            ["field", "void", [[30, 4, 3.8], [70, 16, 5.0]], 1]
        ]]
    ]);
    arm_upper();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [224.1, 20, 6.4]]],
        ["support_faces", [["bed", "-z", 3000]]],
        ["allowed_interferences", [["lower", "upper", "hinge fused"]]],
        ["motions", [
            ["close", ["upper"], "rotate", [108, 10, 5.2], [0, -1, 0], [0, 180],
                ["flex", [["upper", "lower", 1.0, "latch snap"]]],
                ["stops", [180]],
                ["rests", [0, 180]]
            ]
        ]],
        ["assembly_order", [
            [["lower"], [0, 0, 0]],
            [["upper"], [0, 0, -1]]
        ]],
        ["print_in_place", 0.3]
    ]);
    instance("lower", "arm_lower") arm_lower();
    instance("upper", "arm_upper") translate([108, 0, 0]) arm_upper();
}
