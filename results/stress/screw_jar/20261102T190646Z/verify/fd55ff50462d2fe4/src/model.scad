// Storage jar with screw-on lid. Units mm. Print orientation: +Z up, base on bed.
part = "jar"; // [jar, lid, assembly]

r_in = 30; depth_in = 70; wall = 2.4; floor_h = 3;
P = 4.5; th_h = 1.0; tip_w = 1.6; flank = 50; clr = 0.3;
band_turns = 1.5; bandH = P * band_turns;
male_top = 71; male_z0 = male_top - bandH;
cotf = 1 / tan(flank);
tipH = tip_w / 2; wBot = tip_w / 2 + th_h * cotf; wTop = tip_w / 2;

r_out = r_in + wall; Hj = floor_h + depth_in;
rMm = r_out; rMM = r_out + th_h;
rFm = rMm + clr; rFM = rMM + clr;
rSk = rFM + wall; ribR = rSk + 0.8;
lidH = 18; tzA = Hj + floor_h;
fem_z0 = (tzA - male_top - bandH) + 0.3;

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module helical_thread(Rbase, inward, z0, turns) {
    N = ceil(turns * 110);
    prof = inward
        ? [[0.3, -wBot], [-th_h, -tipH], [-th_h, tipH], [0.3, wTop]]
        : [[-0.3, -wBot], [th_h, -tipH], [th_h, tipH], [-0.3, wTop]];
    translate([0, 0, z0])
        linear_extrude(height = P * turns, twist = turns * 360, slices = N, convexity = 6)
            translate([Rbase, 0, 0]) polygon(prof);
}

module jar() {
    difference() {
        union() {
            cylinder(r = r_out, h = Hj, $fn = 180);
            cylinder(r1 = r_out - 0.5, r2 = r_out, h = 0.5, $fn = 180);
        }
        translate([0, 0, floor_h]) cylinder(r = r_in, h = depth_in + 1.5, $fn = 180);
    }
    helical_thread(rMm, false, male_z0, band_turns);
}

module lid() {
    difference() {
        cylinder(r = rSk, h = lidH, $fn = 180);
        translate([0, 0, floor_h]) cylinder(r = rFM, h = lidH, $fn = 180);
    }
    helical_thread(rFM, true, fem_z0, band_turns);
    for (k = [0:23]) rotate([0, 0, k * 15])
        translate([rSk - 0.4, -1.5, 0]) cube([1.2, 3, lidH]);
}

if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-rMM, -rMM, 0], [rMM, rMM, Hj]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", 3000]]],
        ["details", [
            ["cavity", "void", [[-21, -21, 3.5], [21, 21, 72.5]], 0.95],
            ["mouth", "hole", [0, 0, 80], [0, 0, -1], [[0, 60], [65, 60]]],
            ["wall", "thickness", [40, 0, 40], [-1, 0, 0], wall],
            ["floor", "thickness", [0, 0, -2], [0, 0, 1], floor_h],
            ["ext_thread", "view", [[30, -8, 63], [34.5, 8, 72]]]
        ]]
    ]);
    jar();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-ribR, -ribR, 0], [ribR, ribR, lidH]]],
        ["bodies", 1],
        ["support_faces", [["dome", "-z", 3800]]],
        ["details", [
            ["roof", "thickness", [0, 0, 25], [0, 0, -1], floor_h],
            ["skirt", "thickness", [45, 0, 3.6], [-1, 0, 0], 3.2],
            ["int_thread", "view", [[30, -8, 4], [34.5, 8, 13]]]
        ]]
    ]);
    lid();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-ribR, -ribR, 0], [ribR, ribR, tzA]]],
        ["support_faces", [["base", "-z", 3000]]],
        ["allowed_interferences", [["lid", "jar", "thread flanks kiss for feel and seal"]]],
        ["motions", [
            ["screw_on", ["lid"], "rotate", [0, 0, 73], [0, 0, 1], [-720, 0],
                ["flex", [["lid", "jar", 0.9, "thread flanks ride over each other"]]]],
            ["lift_off", ["lid"], "slide", [0, 0, 1], [0, 14],
                ["flex", [["lid", "jar", 0.9, "thread ridges pass each other"]]]]
        ]],
        ["assembly_order", [
            [[ "jar"], [0, 0, 0]],
            [[ "lid"], [0, 0, -1]]
        ]]
    ]);
    instance("jar", "jar") jar();
    instance("lid", "lid") rotate([180, 0, 0]) translate([0, 0, -tzA]) lid();
}
