part = "assembly"; // [assembly, base, lid]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
base_R_out = 41;
base_R_in = 38;
base_H = 21;
bottom_t = 2.5;
bead_R = 42;
post_R = 5;
post_top = 23;
divider_t = 1.6;
divider_top = 20.5;
notch_r = 1.3;
notch_depth = 1.0;
notch_rad = 39.5;
wall_top = 21;
lid_R = 45;
plate_t = 3.4;
skirt_inner = 42.4;
lip_R = 41.4;
lid_H = 14.0;
open_Rin = 12;
open_Rout = 36;
open_half = 20;
pitch = 360/7;

module base_geo() {
    difference() {
        union() {
            // one-piece cup via revolved profile (bottom + wall + bead)
            rotate_extrude($fn = 180, convexity = 4)
                polygon(points = [
                    [0, 0],
                    [base_R_out, 0],
                    [base_R_out, 14],
                    [bead_R, 15],
                    [bead_R, 17],
                    [base_R_out, 18],
                    [base_R_out, wall_top],
                    [base_R_in, wall_top],
                    [base_R_in, bottom_t],
                    [0, bottom_t]
                ]);
            // center post embedded into bottom, with top lead chamfer
            translate([0,0,2.0])
                cylinder(r = post_R, h = 20.0, $fn = 96);
            translate([0,0,22])
                cylinder(r1 = post_R, r2 = post_R-1, h = 1, $fn = 96);
            // 7 dividers embedded into bottom, post and wall
            for (k = [0:6]) {
                rotate([0,0,(k+0.5)*pitch])
                    translate([3.0, -divider_t/2, 2.0])
                        cube([38.5-3.0, divider_t, divider_top-2.0]);
            }
        }
        // 7 detent notches on wall top
        for (k = [0:6]) {
            translate([notch_rad*cos(k*pitch), notch_rad*sin(k*pitch), wall_top-notch_depth-0.1])
                cylinder(r = notch_r, h = notch_depth+0.2, $fn = 32);
        }
    }
}

module lid_geo() {
    difference() {
        union() {
            // one-piece lid cup via revolved profile (lip 1.2 tall, 45 deg lead taper)
            rotate_extrude($fn = 180, convexity = 4)
                polygon(points = [
                    [0, 0],
                    [lid_R, 0],
                    [lid_R, lid_H],
                    [lip_R, lid_H],
                    [lip_R, 12.8],
                    [skirt_inner, 11.8],
                    [skirt_inner, plate_t],
                    [0, plate_t]
                ]);
            // detent bump on plate top (print) at radius 39.5 angle 0
            translate([39.5, 0, plate_t-0.1])
                cylinder(r = 1.0, h = 1.3, $fn = 32);
        }
        // wedge opening through plate (0..plate_t)
        translate([0,0,-0.5])
            linear_extrude(height = plate_t+1.0, convexity = 4)
                polygon(points = concat(
                    [ for (a = [-open_half : 2 : open_half]) [open_Rin*cos(a), open_Rin*sin(a)] ],
                    [ for (a = [open_half : -2 : -open_half]) [open_Rout*cos(a), open_Rout*sin(a)] ]
                ));
        // center bore through plate
        translate([0,0,-0.5])
            cylinder(r = 5.4, h = plate_t+1.0, $fn = 64);
    }
}

module base_part() { base_geo(); }
module lid_part() { lid_geo(); }

// print pose lid assembly transform: print z0 -> assembly 25, print 14 -> assembly 11
module lid_in_assembly() {
    translate([0,0,25]) rotate([180,0,0]) lid_geo();
}

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-42, -42, 0], [42, 42, 23]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base_bottom", "-z", 4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["outer_wall", "thickness", [42, 0, 10], [-1, 0, 0], 3],
            ["bottom", "thickness", [20, 0, -1], [0, 0, 1], 2.5],
            ["divider", "thickness", [18.15, 11.85, 12], [0.434, -0.901, 0], 1.6],
            ["bead", "material", [[-41.9, -0.5, 15.5], [-41, 0.5, 16.5]], 0.9],
            ["compartment_void", "void", [[20, -5, 5], [30, 5, 15]], 0.9],
            ["detent_notch_0", "hole", [39.5, 0, 22], [0, 0, -1], [[0, 2.6], [1.0, 2.6]]],
            ["bead_profile", "view", [[-42.5, -2, 13], [-40, 2, 15.5]]]
        ]]
    ]);
    base_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 14]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["lid_top", "-z", 4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["plate", "thickness", [0, 25, 5], [0, 0, -1], 3.4],
            ["skirt", "thickness", [46, 0, 8], [-1, 0, 0], 2.6],
            ["bump", "material", [[38.5, -1, 3.4], [40.5, 1, 4.6]], 0.5],
            ["opening_void", "void", [[15, -5, -1], [30, 5, 4]], 0.9],
            ["center_bore", "hole", [0, 0, -1], [0, 0, 1], [[0, 10.8]]],
            ["lip_ring", "material", [[-45, -1, 12], [-41.4, 1, 14]], 0.7],
            ["opening_edge", "view", [[34, -2, 0], [37, 2, 3.4]]]
        ]]
    ]);
    lid_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 25]]],
        ["motions", [
            ["lid_turn", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360],
                ["flex", [["lid", "base", 1.0, "detent bump rides over top face"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["flex", [["lid", "base", 1.0, "lip snaps over bead"]]]]
        ]],
        ["held", ["lid"]]
    ]);
    instance("base", "base") base_geo();
    instance("lid", "lid") lid_in_assembly();
}
