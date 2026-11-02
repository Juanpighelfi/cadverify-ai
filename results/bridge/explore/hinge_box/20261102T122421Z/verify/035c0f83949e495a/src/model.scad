/* Box with print-in-place hinge
   Outside closed body ~80x60x40, lid 10mm.
   Hinge along back edge, alternating knuckles + separate pin, printed in place.
   Print pose: lid open 90deg (print_pose), assembly shows closed.
*/

// Select part to export / verify
part = "assembly"; // [assembly, base, lid, pin]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
outerW = 80; outerD = 60; baseH = 30; lidH = 10;
wallT = 2.4; floorT = 3.0;
pinD = 4; boreD = 5; knuckleOD = 7;
pinR = pinD/2; boreR = boreD/2; knuckleR = knuckleOD/2;
hingeY = -30; hingeZ_base = 30; // axis in base/assembly coords (base print == assembly)
radialClear = 0.5; // (boreD-pinD)/2
axialGapKnuckle = 1.5;
headClear = 0.5; headT = 2; headD = 6;
// knuckle X ranges (assembly)
bOL0=-28; bOL1=-18; bC0=-5; bC1=5; bOR0=18; bOR1=28;
lL0=-16.5; lL1=-6.5; lR0=6.5; lR1=16.5;
pinLen = 61; // total pin length (vertical print), heads included

$fn = 64;

// ---------- helpers ----------
module cylX(r, x0, x1, y, z) {
    // cylinder along X from x0 to x1, center (y,z)
    translate([x0, y, z]) rotate([0,90,0]) cylinder(r=r, h=x1-x0);
}
module cylZ(r, z0, z1, x, y) {
    translate([x, y, z0]) cylinder(r=r, h=z1-z0);
}

// teardrop bore along X: cylinder + roof prism (apex up)
module boreX(x0, x1, yc, zc) {
    // main cylinder
    cylX(boreR, x0, x1, yc, zc);
    // roof triangle prism: apex (yc, zc+boreR+1), base (yc-1, zc+boreR)-(yc+1, zc+boreR)
    // build as hull of apex line + base line
    hull() {
        // apex edge
        translate([x0, yc, zc+boreR+1]) cube([x1-x0, 0.01, 0.01], center=false);
        // base edge
        translate([x0, yc-1, zc+boreR-0.01]) cube([x1-x0, 2, 0.02], center=false);
    }
}
module knuckleX(x0, x1, yc, zc) {
    difference() {
        cylX(knuckleR, x0, x1, yc, zc);
        boreX(x0-0.15, x1+0.15, yc, zc);
    }
}

// ---------- BASE (print orientation == assembly: bottom Z=0) ----------
module base_print() {
    difference() {
        union() {
            // tray: outer minus interior
            difference() {
                cube([outerW, outerD, baseH], center=false); // placeholder, translated below
                // interior cavity
                translate([(outerW-75.2)/2 - 40 + 40, 0,0]) {}; // dummy
            }
        }
        // (real geometry built below)
        cube([0.01,0.01,0.01]);
    }
}

// Build base properly with translate to center X/Y
module base_geo() {
    // centered X -40..40, Y -30..30, Z 0..30 + knuckles
    translate([-40, -30, 0]) {
        difference() {
            union() {
                // solid outer block 80x60x30
                cube([80, 60, 30]);
                // knuckles (positions relative: X 0..80 maps to -40..40, so +40 offset)
                // base outer left: X -28..-18 => rel 12..22
                // base center: -5..5 => rel 35..45
                // base outer right: 18..28 => rel 58..68
                // knuckle centers Y rel: hingeY(-30)+30=0, Z=30
                translate([0,0,0]) {
                    knuckleX(12, 22, 0, 30);
                    knuckleX(35, 45, 0, 30);
                    knuckleX(58, 68, 0, 30);
                }
            }
            // interior cavity: X rel 2.4..77.6, Y rel 2.4..57.6, Z 3..30.5 (open top)
            translate([2.4, 2.4, 3.0]) cube([75.2, 55.2, 27.5]);
            // front catch notch: X rel 29.5..50.5 (=-10.5..10.5), Y rel 57.5..60.1, Z 27.5..30.5
            translate([29.5, 57.5, 27.5]) cube([21, 2.6, 3.0]);
            // catch pockets in notch sides
            // left pocket: X rel 28.5..29.5 (=-11.5..-10.5), Y 57.5..60.1, Z 28.75..30.01
            translate([28.5, 57.5, 28.75]) cube([1.0, 2.6, 1.26]);
            // right pocket
            translate([50.5, 57.5, 28.75]) cube([1.0, 2.6, 1.26]);
            // hinge clearance cutouts for lid knuckles+pin gaps:
            // cutout1 X rel 22..35 (=-18..-5), cutout2 45..58 (=5..18), Y rel -0.5..4? Y: hinge area
            // base wall Y rel 0..2.4 (Y -30..-27.6). Cut Y rel -3.5..4 (covers behind+forward clearance), Z 26..30.5
            translate([22, -3.5, 26]) cube([13, 7.5, 4.5]);
            translate([45, -3.5, 26]) cube([13, 7.5, 4.5]);
        }
    }
}

// ---------- LID (print orientation: upside-down flat, block Z 0..10) ----------
// lid_print: X -40..40, Y -30..30, Z 0..10 block + knuckles at Y=-30,Z=10 + tab at front
module lid_geo_print() {
    translate([-40, -30, 0]) {
        difference() {
            union() {
                // solid block 80x60x10
                cube([80, 60, 10]);
                // knuckles: lid left X rel 23.5..33.5 (=-16.5..-6.5), lid right 46.5..56.5 (=6.5..16.5)
                // centers Y rel 0 (Y=-30), Z=10
                knuckleX(23.5, 33.5, 0, 10);
                knuckleX(46.5, 56.5, 0, 10);
                // catch tab: X rel 30..50 (=-10..10), Y rel 57.6..60 (Y 27.6..30), Z 8..12
                translate([30, 57.6, 8]) cube([20, 2.4, 4]);
                // catch bumps on tab sides at Z 10..11 (sit on block top)
                // left bump X rel 29..30
                translate([29, 57.6, 10]) cube([1.0, 2.4, 1.0]);
                // right bump X rel 50..51
                translate([50, 57.6, 10]) cube([1.0, 2.4, 1.0]);
            }
            // cutouts for base knuckles: X rel 11.5..22.5, 34.5..45.5, 57.5..68.5
            // (base ranges expanded 0.5): -28.5..-17.5 etc.
            // Y rel -0.5..4 (Y -30.5..-26), Z 6..10.5
            translate([11.5, -0.5, 6]) cube([11, 4.5, 4.5]);
            translate([34.5, -0.5, 6]) cube([11, 4.5, 4.5]);
            translate([57.5, -0.5, 6]) cube([11, 4.5, 4.5]);
        }
    }
}

// lid in assembly coords (for reference): flip lid_print 180deg about Y + translate Z+40
module lid_geo_assembly() {
    translate([0, 0, 40]) rotate([0,180,0]) lid_geo_print();
}

// ---------- PIN (print orientation: vertical along Z, height 61) ----------
module pin_geo_print() {
    union() {
        // shaft dia 4 from 0..61
        cylZ(pinR, 0, 61, 0, 0);
        // bottom head dia 6, 0..2
        cylZ(headD/2, 0, 2, 0, 0);
        // top head dia 6, 59..61
        cylZ(headD/2, 59, 61, 0, 0);
    }
}
module pin_geo_assembly() {
    // vertical -> horizontal along X at hinge Y=-30,Z=30, X -30.5..30.5
    translate([-30.5, -30, 30]) rotate([0,90,0]) pin_geo_print();
}

// ---------- dispatch ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.5, 0], [40, 30, 33.5]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge knuckles and bores print without supports, small bridges", [[-28, -34, 26], [28, -26, 34]]],
            ["catch pockets tiny ceilings, depth 1mm bridges", [[-12, 27, 28], [12, 31, 30.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["base_floor_solid", "material", [[-30, -20, 0.5], [30, 20, 2.5]], 0.9],
            ["base_interior_void", "void", [[-37.6, -27.6, 3.2], [37.6, 27.6, 29.5]], 0.9],
            ["base_catch_notch_void", "void", [[-10.5, 27.5, 27.5], [10.5, 30.1, 30.1]], 0.9],
            ["base_front_wall", "thickness", [0, 32, 15], [0, -1, 0], 2.4],
            ["base_floor", "thickness", [0, 0, -2], [0, 0, 1], 3.0],
            ["hinge_bore", "hole", [-32, -30, 30], [1, 0, 0], [[0, 5], [10, 5]]]
        ]]
    ]);
    base_geo();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -33.5, 0], [40, 30, 13.5]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["hinge knuckles and bores print without supports, small bridges", [[-28, -34, 6], [28, -26, 14]]],
            ["catch bumps tiny ledges sit on block top, 1mm bridges", [[-12, 27, 9.5], [12, 31, 12]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_block_solid", "material", [[-30, -20, 2], [30, 20, 8]], 0.9],
            ["lid_hinge_cutout_void", "void", [[-28.5, -30.5, 6.2], [-17.5, -26.2, 10.3]], 0.9],
            ["lid_thickness", "thickness", [0, 0, 12], [0, 0, -1], 10],
            ["lid_tab_wall", "thickness", [0, 32, 9], [0, -1, 0], 2.4],
            ["hinge_bore", "hole", [-20, -30, 10], [1, 0, 0], [[0, 5], [10, 5]]]
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
            ["pin_shaft_solid", "material", [[-2, -2, 20], [2, 2, 30]], 0.7],
            ["pin_shaft_dia", "thickness", [5, 0, 30], [-1, 0, 0], 4.0],
            ["pin_head_dia", "thickness", [5, 0, 1], [-1, 0, 0], 6.0]
        ]]
    ]);
    pin_geo_print();
} else {
    // assembly: closed box
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
            ["hinge pin and knuckle clearances print without supports, bridges under 5mm", [[-31, -34, 26], [31, -26, 34]]]
        ]]
    ]);
    instance("base", "base") base_geo();
    instance("lid", "lid") lid_geo_assembly();
    instance("pin", "pin") pin_geo_assembly();
}
