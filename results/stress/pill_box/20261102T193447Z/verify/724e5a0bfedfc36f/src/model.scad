/* Weekly pill box with turning lid.
   About 90 mm across, 25 mm tall. 7 compartments, lid with one opening.
   Base + lid. Print: PLA, 0.4 nozzle, no supports, walls >=1.2mm.
   Lid prints upside down (outer face on bed), base prints upright.
*/

part = "assembly"; // [base, lid, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
Rb_out = 43;
Rb_in = 41;
Hb = 22;
floor_t = 2;
divider_t = 1.6;
divider_top = 21.8;
post_r = 5;
post_top = 21.8;
base_tab_out = 43.8;
base_tab_z0 = 16;
base_tab_z1 = 18;
base_tab_ang = 30;
n_tabs = 7;
n_notches = 14;
notch_w = 3;
notch_d = 1.0;
Rl_out = 45.4;
Rl_in = 44.2;
lid_plate_t = 2.5;
lid_plate_bot = 22.6;
lid_plate_top = 25.1;
lid_skirt_bot = 13.6;
lid_tab_in = 43.4;
lid_tab_z0 = 13.6;
lid_tab_z1 = 15.6;
lid_tab_ang = 30;
opening_ang = 40;
opening_r0 = 8;
opening_r1 = 40;
bump_r = 1.0;
bump_rad = 42;
bump_ang = 25.7142857;
recess_r = 5.4;
recess_d = 1.0;
pitch = 360/7;            // 51.428571
half_pitch = 180/7;       // 25.7142857

lid_print_h = lid_plate_top - lid_skirt_bot; // 11.5

$fn = 180;

function arc_pts(r, a0, a1, n) = [for (i=[0:n]) [r*cos(a0+(a1-a0)*i/n), r*sin(a0+(a1-a0)*i/n)]];

module annular_sector(r0, r1, a0, a1, z0, z1, n=16) {
    outer = arc_pts(r1, a0, a1, n);
    inner = arc_pts(r0, a1, a0, n);
    pts = concat(outer, inner);
    linear_extrude(height = z1 - z0, convexity = 4)
        translate([0,0,z0])
            translate([0,0,-z0])
                polygon(pts);
    // NOTE: linear_extrude starts at 0; shift up:
    // rebuild correctly:
}

// fix annular_sector: build at 0 then translate
module annular_sector2(r0, r1, a0, a1, z0, z1, n=16) {
    outer = arc_pts(r1, a0, a1, n);
    inner = arc_pts(r0, a1, a0, n);
    pts = concat(outer, inner);
    translate([0,0,z0])
        linear_extrude(height = z1 - z0, convexity = 4)
            polygon(pts);
}

module base_geom() {
    difference() {
        union() {
            // floor + outer wall
            cylinder(r = Rb_out, h = Hb);
            // center post (overlaps floor)
            cylinder(r = post_r, h = post_top);
            // dividers (7), at half-pitch offset: 25.714 + k*51.428
            for (k=[0:6]) {
                rotate([0,0,half_pitch + k*pitch])
                    translate([4, -divider_t/2, 1.9])
                        cube([38, divider_t, divider_top-1.9]);
            }
            // snap tabs (7) at divider angles
            for (k=[0:6]) {
                a = half_pitch + k*pitch;
                annular_sector2(41, base_tab_out, a-base_tab_ang/2, a+base_tab_ang/2, base_tab_z0, base_tab_z1, 20);
            }
        }
        // inner cavity
        translate([0,0,floor_t])
            cylinder(r = Rb_in, h = Hb - floor_t + 0.1);
        // inner cavity must not remove post/dividers? post and dividers overlap cavity:
        // (they were unioned, then cavity subtracts around them -> they remain as islands)
        // notches (14) in top of outer wall
        for (k=[0:13]) {
            a = k*360/14;
            rotate([0,0,a])
                translate([41, -notch_w/2, Hb-notch_d])
                    cube([2, notch_w, notch_d+0.2]);
        }
    }
}

module lid_use_geom() {
    difference() {
        union() {
            // top plate
            cylinder(r = Rl_out, h = lid_plate_t);
            // skirt (tube) below plate: plate occupies 0..2.5 in local coords
            // local coords: plate 0..2.5, skirt -9..0 (will be positioned later)
            // Build skirt as tube from -9 to 0:
            translate([0,0,-9])
                difference() {
                    cylinder(r = Rl_out, h = 9);
                    translate([0,0,-0.1])
                        cylinder(r = Rl_in, h = 9.2);
                }
            // retention tabs (7) at divider angles, below skirt bottom region
            for (k=[0:6]) {
                a = half_pitch + k*pitch;
                annular_sector2(lid_tab_in, Rl_out, a-lid_tab_ang/2, a+lid_tab_ang/2, -9, -7, 20);
            }
            // detent bump: sphere centered at plate underside
            // plate underside is z=0 in local? plate 0..2.5, underside z=0.
            // bump below underside:
            translate([bump_rad*cos(bump_ang), bump_rad*sin(bump_ang), 0])
                sphere(r = bump_r);
        }
        // opening wedge through plate
        annular_sector2(opening_r0, opening_r1, -opening_ang/2, opening_ang/2, -0.1, lid_plate_t+0.1, 24);
        // center recess (blind) from underside up into plate
        translate([0,0,0.0])
            cylinder(r = recess_r, h = recess_d);
        // NOTE: recess cylinder from z=0..1.0 removes pit from underside? underside at 0,
        // plate 0..2.5, pit 0..1.0 open at underside. Good.
    }
}

// lid_use_geom is built in LOCAL coords: plate 0..2.5, skirt -9..0.
// Map to assembly coords: plate underside (z=0 local) -> lid_plate_bot (22.6).
module lid_use() {
    translate([0,0,lid_plate_bot])
        lid_use_geom();
}

// lid print: flip use 180deg about X and rest on bed.
// use z 13.6..25.1 -> print 0..11.5
module lid_print() {
    translate([0,0,lid_plate_top])
        rotate([180,0,0])
            lid_use();
}

// ---------- specs ----------
// base bounds (print = assembly for base)
base_xmin = -43.8; base_xmax = 43.8;
base_ymin = -43.8; base_ymax = 43.8;
base_zmin = 0; base_zmax = 22;

// lid print bounds
lid_xmin = -45.4; lid_xmax = 45.4;
lid_ymin = -45.4; lid_ymax = 45.4;
lid_zmin = 0; lid_zmax = 11.5;

// assembly bounds
asm_xmin = -45.4; asm_xmax = 45.4;
asm_ymin = -45.4; asm_ymax = 45.4;
asm_zmin = 0; asm_zmax = 25.1;

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[base_xmin, base_ymin, base_zmin], [base_xmax, base_ymax, base_zmax]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base bottom", "-z", 5000]]],
        ["overhangs_allowed", [["snap tabs underside", [[-44.3, -44.3, 15.5], [44.3, 44.3, 16.5]]]]],
        ["copies", 1],
        ["details", [
            ["floor", "thickness", [25, 0, -1], [0, 0, 1], 2],
            ["outer wall", "thickness", [50, 0, 10], [-1, 0, 0], 2],
            ["divider", "material", [[22.0, 10.3, 10], [23.0, 11.3, 14]], 0.8],
            ["compartment", "void", [[22, -4, 5], [28, 4, 15]], 0.9],
            ["snap lug", "material", [[38.8, 18.2, 16.5], [39.4, 19.0, 17.5]], 0.8],
            ["detent notch", "void", [[41.2, -1, 21.2], [42.8, 1, 21.9]], 0.9]
        ]]
    ]);
    base_geom();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[lid_xmin, lid_ymin, lid_zmin], [lid_xmax, lid_ymax, lid_zmax]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["lid top", "-z", 5000]]],
        ["overhangs_allowed", [["retention lugs underside", [[-46, -46, 9], [46, 46, 10]]]]],
        ["copies", 1],
        ["details", [
            ["top plate", "thickness", [-20, 0, -1], [0, 0, 1], 2.5],
            ["skirt wall", "thickness", [-50, 0, 6], [1, 0, 0], 1.2],
            ["window", "void", [[15, -4, 0], [35, 4, 2.5]], 0.9],
            ["retention lug", "material", [[39.3, -19.5, 10], [39.9, -18.6, 11]], 0.8],
            ["recess", "void", [[-3, -3, 1.6], [3, 3, 2.4]], 0.9],
            ["bump view", "view", [[36, -20, 2.5], [40, -16.5, 4.2]]]
        ]]
    ]);
    lid_print();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[asm_xmin, asm_ymin, asm_zmin], [asm_xmax, asm_ymax, asm_zmax]]],
        ["support_faces", [["bottom", "-z", 5000]]],
        ["motions", [["turn", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360], ["flex", [["lid", "base", 0.5, "detent bump rides over wall top between notches"]]]]]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["rotate", [0, 0, 0], [0, 0, 1], 25.7142857]]
        ]]
    ]);
    instance("base", "base") base_geom();
    instance("lid", "lid") lid_use();
}
