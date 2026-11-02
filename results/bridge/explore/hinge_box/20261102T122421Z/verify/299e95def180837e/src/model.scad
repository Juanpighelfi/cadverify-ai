/* Box with print-in-place hinge
   Outside closed ~80x60x40, lid 10mm. Hinge on back edge, alternating
   knuckles around a pin printed in place. Print pose: lid open 90deg.
   Axis at back top corner (Y=-30, Z=30), 0.5mm radial/axial clearances.
*/

part = "assembly"; // [assembly, base, lid, pin]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
wallT = 2.4; floorT = 3.0;
shaftR = 1.8; boreR = 2.3; knuckleR = 3.5;   // 0.5 radial clearance
headR = 3.0; headT = 2.0;
axY = -30; axZ = 30;                          // hinge axis (assembly coords)
// knuckle X ranges (assembly)
bOL0=-28; bOL1=-18; bC0=-5; bC1=5; bOR0=18; bOR1=28;
lL0=-16.5; lL1=-6.5; lR0=6.5; lR1=16.5;
headX0=28.5; headX1=30.5;                      // pin heads (mirrored)

$fn = 64;

// ---------- helpers ----------
module cylX(r, x0, x1, y, z) {
    translate([x0, y, z]) rotate([0,90,0]) cylinder(r=r, h=x1-x0);
}
module cylZ(r, z0, z1, x, y) {
    translate([x, y, z0]) cylinder(r=r, h=z1-z0);
}
// bore along X with contained teardrop roof (apex stays inside knuckle)
module boreX(x0, x1, yc, zc) {
    cylX(boreR, x0, x1, yc, zc);
    hull() {
        translate([x0, yc-0.95, zc+2.19]) cube([x1-x0, 1.9, 0.02]);
        translate([x0, yc-0.005, zc+2.8]) cube([x1-x0, 0.01, 0.02]);
    }
}
module knuckleX(x0, x1, yc, zc) {
    difference() {
        cylX(knuckleR, x0, x1, yc, zc);
        boreX(x0-0.15, x1+0.15, yc, zc);
    }
}
// 45deg corner chamfer wedge along X (legs 3.5), corner at (yc,zc)
module wedgeX(x0, x1, yc, zc, ysign, zsign) {
    hull() {
        translate([x0, yc-0.1*ysign - (ysign<0?0.2:0), zc + (zsign<0?-4.1:0)])
            cube([x1-x0, 0.2, 4.1]);
        translate([x0, yc + (ysign<0?-3.7:0), zc-0.1*zsign - (zsign<0?0.2:0)+ (zsign>0?0:0)])
            cube([x1-x0, 3.7, 0.2]);
    }
}

// ---------- BASE (print == assembly coords, bottom Z=0) ----------
module base_geo() {
    translate([-40, -30, 0]) {
        difference() {
            union() {
                cube([80, 60, 30]);
                knuckleX(12, 22, 0, 30);
                knuckleX(35, 45, 0, 30);
                knuckleX(58, 68, 0, 30);
            }
            // interior (back wall 5.0 thick)
            translate([2.4, 5.0, 3.0]) cube([75.2, 52.6, 27.5]);
            // catch notch + detent pockets
            translate([29.5, 57.5, 27.5]) cube([21, 2.6, 3.0]);
            translate([28.8, 57.5, 28.8]) cube([1.4, 2.6, 1.4]);
            translate([49.8, 57.5, 28.8]) cube([1.4, 2.6, 1.4]);
            // lid-knuckle swing cutouts
            translate([21.5, -4, 25.8]) cube([14, 8.2, 4.9]);
            translate([44.5, -4, 25.8]) cube([14, 8.2, 4.9]);
            // pin head + shaft-end channels
            translate([68, -4, 26.5]) cube([3.1, 8, 4.2]);
            translate([8.9, -4, 26.5]) cube([3.1, 8, 4.2]);
            // back-top 45deg bevel
            hull() {
                translate([0, -0.1, 26.5]) cube([80, 0.2, 4.1]);
                translate([0, -0.1, 30.4]) cube([80, 3.7, 0.2]);
            }
        }
    }
}

// ---------- LID (print: flat block Z 0..10, knuckles at Z=10) ----------
module lid_geo_print() {
    translate([-40, -30, 0]) {
        difference() {
            union() {
                cube([80, 60, 10]);
                knuckleX(23.5, 33.5, 0, 10);
                knuckleX(46.5, 56.5, 0, 10);
                translate([30, 57.6, 8]) cube([20, 2.4, 4]);   // catch tab
                translate([29, 57.6, 10]) cube([1, 2.4, 1]);   // detent bump L
                translate([50, 57.6, 10]) cube([1, 2.4, 1]);   // detent bump R
            }
            // base-knuckle cutouts
            translate([11.5, -4, 5.8]) cube([11, 8, 5.2]);
            translate([34.5, -4, 5.8]) cube([11, 8, 5.2]);
            translate([57.5, -4, 5.8]) cube([11, 8, 5.2]);
            // shaft/head grooves between lid knuckles
            translate([8.9, -4, 5.8]) cube([14.6, 8, 5.2]);
            translate([33.5, -4, 5.8]) cube([13, 8, 5.2]);
            translate([56.5, -4, 5.8]) cube([14.6, 8, 5.2]);
            // back-face 45deg bevels (top and bottom long edges)
            hull() {
                translate([0, -0.1, 6.5]) cube([80, 0.2, 4.1]);
                translate([0, -0.1, 10.4]) cube([80, 3.7, 0.2]);
            }
            hull() {
                translate([0, -0.1, -0.6]) cube([80, 0.2, 4.1]);
                translate([0, -0.1, -0.5]) cube([80, 3.7, 0.2]);
            }
        }
    }
}
module lid_geo_assembly() {
    translate([0, 0, 40]) rotate([0,180,0]) lid_geo_print();
}

// ---------- PIN (print: vertical, Z 0..61) ----------
module pin_geo_print() {
    union() {
        cylZ(shaftR, 0, 61, 0, 0);
        cylZ(headR, 0, 2, 0, 0);
        cylZ(headR, 59, 61, 0, 0);
    }
}
module pin_geo_assembly() {
    translate([-30.5, -30, 30]) rotate([0,90,0]) pin_geo_print();
}

// ---------- dispatch ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.5, 0], [40, 30, 33.5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge bores channels and cutouts print support-free, bridges under 8mm", [[-32, -35, 25], [32, -25, 34]]],
            ["catch pockets and notch small ceilings bridge under 3mm", [[-12, 27, 28], [12, 31, 31]]]
        ]],
        ["copies", 1],
        ["details", [
            ["base_floor_solid", "material", [[-30, -20, 0.5], [30, 20, 2.5]], 0.9],
            ["base_interior_void", "void", [[-37.6, -25, 3.2], [37.6, 27.6, 29.5]], 0.9],
            ["base_catch_notch_void", "void", [[-10.5, 27.5, 27.5], [10.5, 30.1, 30.1]], 0.9],
            ["hinge_bore_empty", "void", [[-4.5, -31.8, 28.2], [4.5, -28.2, 31.8]], 0.85],
            ["base_front_wall", "thickness", [0, 32, 15], [0, -1, 0], 2.4],
            ["base_floor", "thickness", [0, 0, -2], [0, 0, 1], 3.0],
            ["catch_notch", "view", [[-12, 27, 27], [12, 31, 31]]]
        ]]
    ]);
    base_geo();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.5, 0], [40, 30, 13.5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge bores grooves cutouts support-free bridges under 8mm", [[-32, -35, 5], [32, -25, 14]]],
            ["catch tab and bumps small ledges", [[-12, 27, 8], [12, 31, 12]]],
            ["back bevels 45deg self-supporting", [[-40, -34, -1], [40, -26, 14]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_block_solid", "material", [[-30, -20, 2], [30, 20, 8]], 0.9],
            ["lid_cutout_void", "void", [[-28, -33, 6], [-18, -27, 10.5]], 0.9],
            ["lid_groove_void", "void", [[-6, -33, 6], [6, -27, 10.5]], 0.9],
            ["catch_tab", "material", [[-9, 27.7, 8.5], [9, 29.9, 11]], 0.9],
            ["lid_thickness", "thickness", [0, 0, 12], [0, 0, -1], 10],
            ["catch_tab_detail", "view", [[-12, 27.5, 8], [12, 30.5, 12]]]
        ]]
    ]);
    lid_geo_print();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-3, -3, 0], [3, 3, 61]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 20]]],
        ["overhangs_allowed", [
            ["top head annulus underside 1mm ring bridges to shaft", [[-3, -3, 58], [3, 3, 60]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_shaft_solid", "material", [[-2, -2, 20], [2, 2, 30]], 0.6],
            ["pin_shaft_dia", "thickness", [5, 0, 30], [-1, 0, 0], 3.6],
            ["pin_head_dia", "thickness", [5, 0, 1], [-1, 0, 0], 6.0]
        ]]
    ]);
    pin_geo_print();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.5, 0], [40, 30, 40]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0, -30, 30], [1, 0, 0], [0, 110],
                ["flex", [["lid", "base", 0.6, "catch detent bumps ride over notch sides"]]]
            ]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, -1]],
            [["pin"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.4],
        ["print_pose", [["lid_swing", 90]]],
        ["overhangs_allowed", [
            ["hinge pin knuckles and lid back bevels print support-free, bridges under 8mm", [[-32, -37, 25], [32, -25, 35]]],
            ["lid catch tab underside short 4mm bridge", [[-11, -30, 87], [11, -28, 88]]]
        ]]
    ]);
    instance("base", "base") base_geo();
    instance("lid", "lid") lid_geo_assembly();
    instance("pin", "pin") pin_geo_assembly();
}
