// Box with print-in-place hinge - FDM PLA, 0.4mm nozzle, Bambu Lab A1
// Units mm. Print orientation +Z up. Assembly = closed box as printed.

/* [Part] */
part = "assembly"; // ["base","lid","pin","assembly"]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
W = 80; D = 60;
baseH = 30; lidH = 10; gapV = 0.4;
wallT = 2.4; botT = 2.4; lidTopT = 2.4;
pinD = 3.2; boreD = 4.0; knOD = 7.0;
knR = knOD/2; boreR = boreD/2;
hingeY = -32.5; hingeZasm = 31.5;
hingeHalf = 35; gapA = 0.6;
knL = (2*hingeHalf - 4*gapA)/5; // 13.52
// knuckle x intervals (5 segments)
x0a=-35; x0b=-35+knL;
x1a=x0b+gapA; x1b=x1a+knL;
x2a=x1b+gapA; x2b=x2a+knL;
x3a=x2b+gapA; x3b=x3a+knL;
x4a=x3b+gapA; x4b=35;
lidZoff = baseH + gapV; // 30.4, lid skirt bottom in assembly
lidAxisZ = hingeZasm - lidZoff; // 1.1
pinGapAx = 0.6; headT = 2.0; headD = 6.0;

$fn = 64;

// ---------- helpers ----------
module knSeg(xa, xb, y, z, od) {
    translate([(xa+xb)/2, y, z]) rotate([0,90,0])
        cylinder(d=od, h=xb-xa, center=true);
}
module boreSeg(xa, xb, y, z, id) {
    translate([(xa+xb)/2, y, z]) rotate([0,90,0])
        cylinder(d=id, h=(xb-xa)+0.4, center=true);
}

// ---------- base ----------
module base() {
    difference() {
        union() {
            // outer tub solid
            translate([-W/2, -D/2, 0]) cube([W, D, baseH]);
            // base knuckles (3)
            knSeg(x0a,x0b, hingeY, hingeZasm, knOD);
            knSeg(x2a,x2b, hingeY, hingeZasm, knOD);
            knSeg(x4a,x4b, hingeY, hingeZasm, knOD);
            // base webs below bores
            translate([x0a, -33.5, 28.0]) cube([x0b-x0a, 4.5, 1.5]);
            translate([x2a, -33.5, 28.0]) cube([x2b-x2a, 4.5, 1.5]);
            translate([x4a, -33.5, 28.0]) cube([x4b-x4a, 4.5, 1.5]);
        }
        // inner cavity
        translate([-(W/2-wallT), -(D/2-wallT), botT]) cube([W-2*wallT, D-2*wallT, baseH-botT+0.5]);
        // catch recess front (open top)
        translate([-10.5, 28.8, 23.5]) cube([21, 2.0, 7.0]);
        // catch groove in recess back wall
        translate([-8.5, 28.2, 26.5]) cube([17, 0.61, 1.8]);
        // knuckle bores
        boreSeg(x0a,x0b, hingeY, hingeZasm, boreD);
        boreSeg(x2a,x2b, hingeY, hingeZasm, boreD);
        boreSeg(x4a,x4b, hingeY, hingeZasm, boreD);
    }
}

// ---------- lid (part coords: skirt bottom Z=0, top Z=10) ----------
module lid() {
    difference() {
        union() {
            translate([-W/2, -D/2, 0]) cube([W, D, lidH]);
            // lid knuckles (2)
            knSeg(x1a,x1b, hingeY, lidAxisZ, knOD);
            knSeg(x3a,x3b, hingeY, lidAxisZ, knOD);
            // lid webs
            translate([x1a, -33.5, -2.4]) cube([x1b-x1a, 4.5, 1.5]);
            translate([x3a, -33.5, -2.4]) cube([x3b-x3a, 4.5, 1.5]);
            // catch tab hanging below skirt
            translate([-10, 29.2, -6]) cube([20, 0.8, 8]);
            // catch bump (trapezoid ridge, 45deg ramps)
            hull() {
                translate([-8, 29.0, -4.0]) cube([16, 0.3, 2.0]);
                translate([-8, 28.6, -3.4]) cube([16, 0.1, 0.8]);
            }
        }
        // lid inner pocket (open bottom)
        translate([-(W/2-wallT), -(D/2-wallT), -0.5]) cube([W-2*wallT, D-2*wallT, (lidH-lidTopT)+0.5+0.5]);
        // knuckle bores
        boreSeg(x1a,x1b, hingeY, lidAxisZ, boreD);
        boreSeg(x3a,x3b, hingeY, lidAxisZ, boreD);
    }
}

// ---------- pin (part coords: axis at origin along X) ----------
module pin() {
    union() {
        translate([0,0,0]) rotate([0,90,0]) cylinder(d=pinD, h=72, center=true);
        translate([36.6,0,0]) rotate([0,90,0]) cylinder(d=headD, h=headT, center=true);
        translate([-36.6,0,0]) rotate([0,90,0]) cylinder(d=headD, h=headT, center=true);
    }
}

// ---------- output ----------
if (part == "base") base();
else if (part == "lid") lid();
else if (part == "pin") pin();
else if (part == "assembly") {
    instance("base_1", "base", 1) base();
    instance("lid_1", "lid", 1) translate([0,0,lidZoff]) lid();
    instance("pin_1", "pin", 1) translate([0,hingeY,hingeZasm]) pin();
}

// ---------- specs ----------
if (part == "base") echo(cadverify_spec = [
    ["bounds", [[-W/2, hingeY-knR, 0], [W/2, D/2, hingeZasm+knR]]],
    ["bodies", 1],
    ["through_holes", 3],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [
        ["hinge", [[-35.5, -36.5, 27.5], [35.5, -28.5, 35.5]]],
        ["catch", [[-8.5, 28.0, 26.5], [8.5, 28.9, 28.4]]]
    ]],
    ["copies", 1],
    ["details", [
        ["sidewall", "thickness", [45, 0, 15], [-1, 0, 0], 2.4],
        ["bottom", "thickness", [0, 0, -1], [0, 0, 1], 2.4],
        ["cavity", "void", [[-37.6, -27.6, 2.4], [37.6, 27.6, 30]], 0.9],
        ["recess", "void", [[-10.5, 28.8, 23.5], [10.5, 30.5, 30.5]], 0.9],
        ["groove", "void", [[-8.5, 28.2, 26.5], [8.5, 28.81, 28.3]], 0.8],
        ["gap01", "void", [[x0b, -34.5, 29.5], [x1a, -30.5, 33.5]], 0.9],
        ["bore", "hole", [x0a-1, hingeY, hingeZasm], [1, 0, 0], [[0, 4.0], [knL, 4.0]]],
        ["knuckle_top", "material", [[-30, -33, 33.6], [-25, -32, 34.4]], 0.8],
        ["hinge_view", "view", [[-35, -36.5, 27.5], [35, -28.5, 35.5]]],
        ["catch_view", "view", [[-10.5, 28.2, 23.5], [10.5, 30.5, 30.5]]]
    ]]
]);
else if (part == "lid") echo(cadverify_spec = [
    ["bounds", [[-W/2, hingeY-knR, -6], [W/2, D/2, lidH]]],
    ["bodies", 1],
    ["through_holes", 2],
    ["support_faces", []],
    ["overhangs_allowed", [
        ["hinge", [[-35.5, -36.5, -2.5], [35.5, -28.5, 5]]],
        ["roof", [[-37.6, -27.6, 7.0], [37.6, 27.6, 7.7]]]
    ]],
    ["copies", 1],
    ["details", [
        ["top", "thickness", [0, 0, 11], [0, 0, -1], 2.4],
        ["sidewall", "thickness", [45, 0, 5], [-1, 0, 0], 2.4],
        ["pocket", "void", [[-37.6, -27.6, -0.5], [37.6, 27.6, 7.6]], 0.9],
        ["bore", "hole", [x1a-1, hingeY, lidAxisZ], [1, 0, 0], [[0, 4.0], [knL, 4.0]]],
        ["tab", "material", [[-5, 29.3, -4], [5, 29.9, 0]], 0.8],
        ["knuckle_top", "material", [[9, -33, 3.1], [14, -32, 3.9]], 0.8],
        ["hinge_view", "view", [[-35, -36.5, -2.5], [35, -28.5, 5]]],
        ["catch_view", "view", [[-10, 28.6, -6], [10, 30, 2]]]
    ]]
]);
else if (part == "pin") echo(cadverify_spec = [
    ["bounds", [[-37.6, -3, -3], [37.6, 3, 3]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", []],
    ["overhangs_allowed", [
        ["shaft", [[-36, -1.3, -1.7], [36, 1.3, -0.8]]]
    ]],
    ["copies", 1],
    ["details", [
        ["shaft", "thickness", [0, 5, 0], [0, -1, 0], 3.2],
        ["head", "material", [[36.0, -1, -1], [37.2, 1, 1]], 0.8],
        ["pin_view", "view", [[-36, -3, -3], [36, 3, 3]]]
    ]]
]);
else if (part == "assembly") echo(cadverify_spec = [
    ["bounds", [[-W/2, hingeY-knR, 0], [W/2, D/2, lidZoff+lidH]]],
    ["support_faces", [["bed", "-z", 4000]]],
    ["allowed_interferences", []],
    ["motions", [
        ["lid_open", ["lid_1"], "rotate", [0, hingeY, hingeZasm], [1, 0, 0], [0, 110], ["flex", [["lid_1", "base_1", 0.8, "catch detent passes"]]]]
    ]],
    ["assembly_order", [
        [["base_1"], [0, 0, 0]],
        [["lid_1"], [0, 0, -1]],
        [["pin_1"], [-1, 0, 0]]
    ]],
    ["print_in_place", 0.4],
    ["overhangs_allowed", [
        ["hinge", [[-35.5, -36.5, 27.5], [35.5, -28.5, 35.5]]],
        ["roof", [[-37.6, -27.6, 37.4], [37.6, 27.6, 38.1]]],
        ["catch", [[-8.5, 28.0, 26.5], [8.5, 28.9, 28.4]]]
    ]]
]);
