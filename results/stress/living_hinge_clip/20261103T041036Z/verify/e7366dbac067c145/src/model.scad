/* Bag clip with living hinge - PETG, 0.4mm nozzle, no supports
   Printed open flat (single print, fuses into one piece), folds shut on 2mm folded bag.
   Two verification parts (lower + upper) that fuse at hinge when printed together.
   Assembly shows closed on bag, motion "closing" folds upper onto lower/bag.
*/
/* [Print] */
part = "lower"; // [lower, upper, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
arm_len = 100;
arm_w = 24;
arm_t = 3;
hinge_len = 6;
hinge_t = 0.6;
tab_len = 12;
heel_len = 8;
catch_w = 5;
lip = 0.8;
lip_t = 0.7;
bag_t = 2;

lower_xmax = 106;      // 0..106
upper_len_print = 112; // 0..112
closed_h = 8.2;
pivot_x = 103.05;
pivot_z = 4.1;

module lower_geo() {
    // base
    cube([100, arm_w, arm_t]);
    // catch block at free end (x 0..5), overlap into base
    translate([0, 0, 2.98]) cube([5, arm_w, 2.02]);
    // catch lip protruding +x, overlap into block
    translate([4.98, 0, 4.3]) cube([0.82, arm_w, 0.7]);
    // living hinge leaf, overlap into base
    translate([99.98, 0, 0]) cube([6.02, arm_w, hinge_t]);
}

module upper_geo() {
    // base 0..100
    cube([100, arm_w, arm_t]);
    // heel at hinge end on top
    translate([0, 0, 2.98]) cube([8, arm_w, 2.02]);
    // hook leg near free end on top
    translate([92.2, 0, 2.98]) cube([2, arm_w, 1.82]);
    // hook lip protruding +x from leg side
    translate([94.18, 0, 4.1]) cube([0.82, arm_w, 0.7]);
    // thumb tab extension beyond free end
    translate([99.98, 0, 0]) cube([12.02, arm_w, arm_t]);
}

module bag_geo() {
    translate([8, 0, 3]) cube([84, arm_w, bag_t]);
}

if (part == "lower") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [106, 24, 5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 500]]],
        ["overhangs_allowed", [["catch lip bridge", [[4.5, 0, 4.0], [6.2, 24, 5.1]]]]],
        ["copies", 1],
        ["details", [
            ["base", "material", [[10, 0, 0], [90, 24, 3]], 1],
            ["catch", "material", [[0, 0, 3], [5, 24, 5]], 1],
            ["catch_lip", "material", [[5.0, 0.1, 4.35], [5.75, 23.9, 4.95]], 0.9],
            ["hinge", "material", [[100.05, 0.1, 0.05], [105.95, 23.9, 0.55]], 0.9],
            ["hook_space", "void", [[5.8, 0, 3], [8.6, 24, 5.4]], 1],
            ["bag_space", "void", [[8, 0, 5.1], [92, 24, 7]], 1],
            ["wall", "thickness", [50, 12, 6], [0, 0, -1], 3],
            ["film", "thickness", [103, 12, 2], [0, 0, -1], 0.6],
            ["hinge_top", "view", [[99, 0, 0], [107, 24, 1]]]
        ]]
    ]);
    lower_geo();
} else if (part == "upper") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [112, 24, 5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 500]]],
        ["overhangs_allowed", [["hook lip bridge", [[91.5, 0, 2.8], [96, 24, 5]]]]],
        ["copies", 1],
        ["details", [
            ["heel", "material", [[0, 0, 3], [8, 24, 5]], 1],
            ["arm", "material", [[10, 0, 0], [80, 24, 3]], 1],
            ["hook_leg", "material", [[92.3, 0.1, 3.05], [94.1, 23.9, 4.75]], 0.9],
            ["hook_lip", "material", [[94.2, 0.1, 4.15], [94.95, 23.9, 4.75]], 0.9],
            ["tab", "material", [[100, 0, 0], [112, 24, 3]], 1],
            ["catch_space", "void", [[95, 0, 3], [99.9, 24, 5]], 1],
            ["wall", "thickness", [50, 12, 6], [0, 0, -1], 3],
            ["heel_wall", "thickness", [4, 12, 7], [0, 0, -1], 5],
            ["thumb", "view", [[99, 0, 0], [113, 24, 3.5]]]
        ]]
    ]);
    upper_geo();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [218, 24, 5]]],
        ["support_faces", [["bed", "-z", 1000]]],
        ["motions", [
            ["closing", ["upper"], "rotate", [103, 12, 4.1], [0, -1, 0], [0, 180],
                ["flex", [["upper", "lower", 1, "latch snap and heel clearance"]]], ["stops", [180]], ["rests", [180]]]
        ]],
        ["assembly_order", [
            [["lower"], [0, 0, 0]],
            [["bag"], [0, 0, -1]],
            [["upper"], [0, 0, -1], ["flex", [["upper", "lower", 1, "latch snap"]]]]
        ]]
    ]);
    instance("lower", "lower") lower_geo();
    instance("upper", "upper") translate([106, 0, 0]) upper_geo();
    instance("bag", "external") bag_geo();
}
