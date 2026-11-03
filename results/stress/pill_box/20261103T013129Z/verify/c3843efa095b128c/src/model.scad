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
bead_zA = 14;
bead_zB = 15;
bead_zC = 17;
bead_zD = 18;
post_R = 5;
post_top = 23;
divider_t = 1.6;
divider_top = 20.5;
divider_bot = 2.5;
notch_r = 1.3;
notch_depth = 1.0;
notch_rad = 39.5;
wall_top = 21;
lid_R = 45;
plate_t = 3.4;
skirt_inner = 42.4;
lip_R = 41.4;
lid_H = 14.0;
taper_z0 = 12.0;
taper_z1 = 13.0;
lip_z0 = 13.0;
lip_z1 = 14.0;
bump_r = 1.0;
bump_h = 1.2;
bump_rad = 39.5;
bore_R = 5.4;
open_Rin = 12;
open_Rout = 36;
open_half = 20;
pitch = 360/7;

module base_geo() {
    difference() {
        union() {
            // bottom disc
            cylinder(r = base_R_out, h = bottom_t, $fn = 180);
            // outer wall tube 2.5..21
            difference() {
                cylinder(r = base_R_out, h = base_H, $fn = 180);
                translate([0,0,bottom_t-0.1])
                    cylinder(r = base_R_in, h = base_H, $fn = 180);
            }
            // retention bead: bottom chamfer 14-15, straight 15-17, top chamfer 17-18
            translate([0,0,bead_zA])
                cylinder(r1 = base_R_out, r2 = bead_R, h = bead_zB-bead_zA, $fn = 180);
            translate([0,0,bead_zB])
                cylinder(r = bead_R, h = bead_zC-bead_zB, $fn = 180);
            translate([0,0,bead_zC])
                cylinder(r1 = bead_R, r2 = base_R_out, h = bead_zD-bead_zC, $fn = 180);
            // center post 2.5..23 with top lead chamfer 22..23
            translate([0,0,divider_bot])
                cylinder(r = post_R, h = 22-divider_bot, $fn = 96);
            translate([0,0,22])
                cylinder(r1 = post_R, r2 = post_R-1, h = 1, $fn = 96);
            // 7 dividers
            for (k = [0:6]) {
                rotate([0,0,(k+0.5)*pitch])
                    translate([4, -divider_t/2, divider_bot])
                        cube([38.5-4, divider_t, divider_top-divider_bot]);
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
            // plate + outer shell up to taper start
            cylinder(r = lid_R, h = taper_z0, $fn = 180);
            // taper outer continues, inner tapers 42.4 -> 41.4 over 12..13
            difference() {
                cylinder(r = lid_R, h = lip_z1, $fn = 180);
                // bore straight part
                translate([0,0,plate_t-0.1])
                    cylinder(r = skirt_inner, h = (taper_z0-plate_t)+0.2, $fn = 180);
                // taper void (cone) 12..13 : inner void narrows downward? we subtract cone that leaves material taper
                // To make inner wall taper inward going up, subtract a cone r 42.4 at bottom to 41.4 at top
                translate([0,0,taper_z0])
                    cylinder(r1 = skirt_inner, r2 = lip_R, h = taper_z1-taper_z0, $fn = 180);
                // lip straight bore
                translate([0,0,lip_z0])
                    cylinder(r = lip_R, h = lip_z1-lip_z0+0.1, $fn = 180);
            }
            // detent bump on plate top (print) at radius 39.5 angle 0
            translate([bump_rad, 0, plate_t-0.1])
                cylinder(r = bump_r, h = bump_h+0.1, $fn = 32);
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
            cylinder(r = bore_R, h = plate_t+1.0, $fn = 64);
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
            ["bottom", "thickness", [0, 0, -1], [0, 0, 1], 2.5],
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
            ["plate", "thickness", [0, 0, 5], [0, 0, -1], 3.4],
            ["skirt", "thickness", [46, 0, 8], [-1, 0, 0], 2.6],
            ["bump", "material", [[38.5, -1, 3.4], [40.5, 1, 4.6]], 0.5],
            ["opening_void", "void", [[15, -5, -1], [30, 5, 4]], 0.9],
            ["center_bore", "hole", [0, 0, -1], [0, 0, 1], [[0, 10.8], [3.4, 10.8]]],
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
                ["flex", [["lid", "base", 0.8, "detent bump rides over top face"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, 1], ["flex", [["lid", "base", 0.8, "lip snaps over bead"]]]]
        ]],
        ["held", ["lid"]]
    ]);
    instance("base", "base") base_geo();
    instance("lid", "lid") lid_in_assembly();
}
