/* Weekly pill box with turning lid - PLA, no supports, 0.4 nozzle */
part = "assembly"; // [base, lid, assembly]

/* parameters */
base_wall_outer = 41.5;
base_wall_inner = 39.5;
base_h = 22;
base_bottom_t = 2;
flange_outer = 42.6;
flange_top = 19;
flange_mid = 18.4;
flange_bot = 17;
hub_r = 8;
divider_t = 1.6;
divider_r0 = 7;
divider_r1 = 40;
notch_r = 40.5;
notch_rad = 1.3;
bump_rad = 1.0;
lid_outer = 45;
lid_skirt_inner = 43;
lid_disc_t = 2.8;
lid_skirt_h = 7.0; // 2.8 to 9.8 in print
lid_print_h = 9.8;
lid_lip_tip_r = 42.2;
lid_lip_low_z_print = 8.3; // sloped side at wall
lid_lip_top_z_print = 9.8; // flat top
center_hole_r = 8.4;
opening_inner = 10;
opening_outer = 38;
opening_half_ang = 20;
assembly_lid_top = 25;
align_ang = 360/14; // 25.7142857

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module base_geometry() {
    // bottom disc
    cylinder(r = base_wall_outer, h = base_bottom_t, $fn = 180);
    // outer wall tube
    difference() {
        cylinder(r = base_wall_outer, h = base_h, $fn = 180);
        translate([0,0,base_bottom_t - 0.5])
            cylinder(r = base_wall_inner, h = base_h, $fn = 180);
    }
    // flange ring with 45deg-chamfered underside
    rotate_extrude($fn = 180)
        polygon(points = [
            [base_wall_outer, flange_bot],
            [flange_outer, flange_mid],
            [flange_outer, flange_top],
            [base_wall_outer, flange_top]
        ]);
    // hub (kept solid: added after cavity so it survives)
    cylinder(r = hub_r, h = base_h, $fn = 96);
    // 7 dividers at k*360/7 (added after cavity so they survive)
    for (k = [0:6]) {
        rotate([0,0,k*360/7])
            translate([divider_r0, -divider_t/2, base_bottom_t])
                cube([divider_r1 - divider_r0, divider_t, base_h - base_bottom_t]);
    }
    // 7 notch pits (hemispherical) at compartment centres
    for (k = [0:6]) {
        ang = (k+0.5)*360/7;
        translate([notch_r*cos(ang), notch_r*sin(ang), base_h])
            sphere(r = notch_rad, $fn = 32);
    }
}

module lid_geometry() {
    // print orientation: use-top at z=0, skirt up to 9.8
    difference() {
        union() {
            // disc
            cylinder(r = lid_outer, h = lid_disc_t, $fn = 180);
            // skirt tube
            translate([0,0,lid_disc_t])
                difference() {
                    cylinder(r = lid_outer, h = lid_skirt_h, $fn = 180);
                    translate([0,0,-0.5])
                        cylinder(r = lid_skirt_inner, h = lid_skirt_h+1, $fn = 180);
                }
            // lip ring (triangle section)
            rotate_extrude($fn = 180)
                polygon(points = [
                    [lid_skirt_inner, lid_lip_low_z_print],
                    [lid_skirt_inner, lid_lip_top_z_print],
                    [lid_lip_tip_r, lid_lip_top_z_print]
                ]);
            // detent bump (hemisphere up): full sphere centred on surface
            translate([notch_r, 0, lid_disc_t])
                sphere(r = bump_rad, $fn = 32);
        }
        // center hole
        translate([0,0,-1])
            cylinder(r = center_hole_r, h = lid_disc_t+2, $fn = 96);
        // sector opening: wedge ^ outer minus inner, through disc
        translate([0,0,-1])
            difference() {
                intersection() {
                    linear_extrude(height = lid_disc_t+2)
                        polygon(points = [
                            [0,0],
                            [50*cos(-opening_half_ang), 50*sin(-opening_half_ang)],
                            [50*cos(opening_half_ang), 50*sin(opening_half_ang)]
                        ]);
                    cylinder(r = opening_outer, h = lid_disc_t+2, $fn = 128);
                }
                cylinder(r = opening_inner, h = lid_disc_t+4, $fn = 96);
            }
    }
}

// specs
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-42.6, -42.6, 0], [42.6, 42.6, 22]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["outer_wall", "thickness", [42.5, 0, 10], [-1, 0, 0], 2.0],
            ["floor", "thickness", [20, 5, -1], [0, 0, 1], 2.0],
            ["divider", "material", [[15, -0.7, 10], [25, 0.7, 14]], 0.9],
            ["hub", "material", [[-2, -2, 5], [2, 2, 10]], 0.9],
            ["compartment", "void", [[21, 9, 5], [26, 13, 15]], 0.9],
            ["notch", "void", [[35.989, 17.072, 21.5], [36.989, 18.072, 22.0]], 0.9]
        ]]
    ]);
    base_geometry();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 9.8]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 20, -1], [0, 0, 1], 2.8],
            ["skirt", "thickness", [46, 0, 6], [-1, 0, 0], 2.0],
            ["center_hole", "hole", [0, 0, -1], [0, 0, 1], [[0, 16.8], [2.0, 16.8]]],
            ["opening", "void", [[15, -2, 0.5], [30, 2, 2.5]], 0.9],
            ["bump", "material", [[40.0, -0.5, 2.8], [41.0, 0.5, 3.3]], 0.9],
            ["lip", "material", [[42.5, -0.3, 9.5], [42.9, 0.3, 9.7]], 0.9]
        ]]
    ]);
    lid_geometry();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 25]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_turn", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360],
                ["flex", [["lid", "base", 1.0, "detent bump rides over rim"]]],
                ["rests", [0, 51.428571, 102.857142, 154.285714, 205.714285, 257.142857, 308.571428, 360]]
            ]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["flex", [["lid", "base", 1.0, "lip snaps over flange"]]]]
        ]],
        ["held", ["lid"]]
    ]);
    instance("base", "base") base_geometry();
    instance("lid", "lid") translate([0,0,assembly_lid_top]) rotate([0,0,align_ang]) rotate([180,0,0]) lid_geometry();
}
