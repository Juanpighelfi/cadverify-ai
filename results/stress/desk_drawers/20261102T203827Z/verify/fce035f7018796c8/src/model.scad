cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

part = "assembly";

// ---------- parameters (mm) ----------
W = 120; Df = 140; H = 90; t = 4;
DW = 108; DDbox = 126; frontT = 4; pullP = 10; DH = 32;

// frame assembly geometry (assembly coords: x 0..120, y 0..140 back->front, z 0..90)
module frame_asm() {
    union() {
        // bottom
        cube([120, 140, 4]);
        // top
        translate([0, 0, 86]) cube([120, 140, 4]);
        // left wall
        cube([4, 140, 90]);
        // right wall
        translate([116, 0, 0]) cube([4, 140, 90]);
        // back wall
        cube([120, 4, 90]);
        // middle shelf (between side walls, from back to front)
        translate([4, 0, 43]) cube([112, 140, 4]);
        // stop blocks: overlap into walls/floors by 0.1 for manifold union
        // lower left
        translate([3.9, 130, 3.9]) cube([1.6, 10, 6.1]);
        // lower right
        translate([114.5, 130, 3.9]) cube([1.6, 10, 6.1]);
        // upper left (on middle shelf)
        translate([3.9, 130, 46.9]) cube([1.6, 10, 6.1]);
        // upper right
        translate([114.5, 130, 46.9]) cube([1.6, 10, 6.1]);
    }
}

// drawer local geometry (local coords: box min at 0,0,0; x 0..108, y 0..130 box+front, pull to 140, z 0..32, tabs to x -1.5..109.5)
module drawer_local() {
    union() {
        // bottom
        cube([108, 126, 3]);
        // left wall
        translate([0, 0, 3]) cube([3, 126, 26]);
        // right wall
        translate([105, 0, 3]) cube([3, 126, 26]);
        // back wall
        translate([0, 0, 3]) cube([108, 3, 26]);
        // front panel (full height)
        translate([0, 126, 0]) cube([108, 4, 32]);
        // stop tabs (overlap 0.5 into side walls)
        translate([-1.5, 5, 4]) cube([2.0, 10, 4]);
        translate([107.5, 5, 4]) cube([2.0, 10, 4]);
        // pull wedge: convex hull of 4 bars along X at YZ corners
        hull() {
            translate([34, 129.9, 14]) cube([40, 0.1, 0.1]);
            translate([34, 129.9, 28]) cube([40, 0.1, 0.1]);
            translate([34, 140, 24]) cube([40, 0.1, 0.1]);
            translate([34, 140, 28]) cube([40, 0.1, 0.1]);
        }
    }
}

module frame_print() {
    translate([0, 90, 0]) rotate([90, 0, 0]) frame_asm();
}
module drawer_print() {
    drawer_local();
}

if (part == "frame") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [120, 90, 140]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 5000]]],
        ["overhangs_allowed", [
            ["lower_left_block", [[3.5, 79, 129], [6, 87, 141]]],
            ["lower_right_block", [[114, 79, 129], [117, 87, 141]]],
            ["upper_left_block", [[3.5, 36, 129], [6, 44, 141]]],
            ["upper_right_block", [[114, 36, 129], [117, 44, 141]]]
        ]],
        ["copies", 1],
        ["details", [
            ["side_wall", "thickness", [-1, 45, 70], [1, 0, 0], 4],
            ["back_plate", "thickness", [60, 45, -1], [0, 0, 1], 4],
            ["block_ll", "material", [[4, 80, 130], [5.5, 86, 140]], 0.9],
            ["block_lr", "material", [[114.5, 80, 130], [116, 86, 140]], 0.9],
            ["block_ul", "material", [[4, 37, 130], [5.5, 43, 140]], 0.9],
            ["block_ur", "material", [[114.5, 37, 130], [116, 43, 140]], 0.9],
            ["cavity_lower", "void", [[6, 47, 4], [114, 86, 129]], 0.9],
            ["cavity_upper", "void", [[6, 4, 4], [114, 43, 129]], 0.9]
        ]]
    ]);
    frame_print();
} else if (part == "drawer") {
    echo(cadverify_spec = [
        ["bounds", [[-1.5, 0, 0], [109.5, 140, 32]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 5000]]],
        ["overhangs_allowed", [
            ["tab_left", [[-2, 4, 3], [1, 16, 9]]],
            ["tab_right", [[107, 4, 3], [111, 16, 9]]],
            ["pull_underside", [[33, 129, 13], [75, 141, 29]]]
        ]],
        ["copies", 2],
        ["details", [
            ["bottom", "thickness", [54, 60, -1], [0, 0, 1], 3],
            ["side_wall", "thickness", [-1, 60, 15], [1, 0, 0], 3],
            ["tab_left", "material", [[-1.5, 5, 4], [0.5, 15, 8]], 0.9],
            ["tab_right", "material", [[107.5, 5, 4], [109.5, 15, 8]], 0.9],
            ["interior", "void", [[4, 4, 4], [104, 125, 28]], 0.9],
            ["pull", "view", [[34, 129, 14], [74, 140, 28]]]
        ]]
    ]);
    drawer_print();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [120, 150, 90]]],
        ["support_faces", [["desk", "-z", 5000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lower_slide", ["drawer_lower"], "slide", [0, 1, 0], [0, 104]],
            ["upper_slide", ["drawer_upper"], "slide", [0, 1, 0], [0, 104]]
        ]],
        ["assembly_order", [
            [["frame"], [0, 0, 0]],
            [["drawer_lower"], [0, -1, -0.03]],
            [["drawer_upper"], [0, -1, -0.03]]
        ]]
    ]);
    instance("frame", "frame") frame_asm();
    instance("drawer_lower", "drawer", 1) translate([6, 10, 5]) drawer_local();
    instance("drawer_upper", "drawer", 1) translate([6, 10, 48]) drawer_local();
}
