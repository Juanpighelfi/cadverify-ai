// Bracelet of hinged links, printed in place
// Print orientation: flat on bed, +Z up, min z = 0
// Link: pitch 18 (X), width 12 (Y), thickness 5 (Z incl. snap stud)
// Hinge: horizontal pin along Y, teardrop pin in round hole, 0.5mm clearance

part = "link"; // [link, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters ----
P = 18;            // pitch (hinge to hinge)
W = 12;            // width (Y)
Hb = 4;            // body thickness (Z 0-4)
Hs = 1;            // stud height (Z 4-5)
Zc = 2.0;          // hinge axis height
Rp = 1.5;          // pin radius (teardrop, tip dist 1.5)
Rh = 2.0;          // hole radius
Ytong = 3.5;       // tongue half width
Yin = 4.0;         // leaves inner face
Yout = 6.0;        // outer半 width
Xrear = -1.5;      // rear face (pin rear)
Xsr = 3.5;         // spine rear (overlap)
Xsf = 14.5;       // spine front (overlap)
Xlr = 13.5;        // leaves rear
Xfront = 20;       // front face
XpinR = 0;         // rear pin x
XpinF = 18;        // front hole x
studX = 7; studR = 1.75;
holeX = 11; holeR = 1.6;

module teardrop2D() {
    RpL = 1.5; ZcL = 2.0;
    pts = concat(
        [for (a=[0:180/16:180]) [RpL*cos(a), ZcL+RpL*sin(a)]],
        [[0, ZcL-RpL]]
    );
    polygon(pts);
}

module pin_stub(len) {
    linear_extrude(height=len)
        teardrop2D();
}

module stud_solid() {
    // base shaft r1.75, 3.9-4.5 + 45deg chamfer frustum to r1.25, 4.5-5.0
    translate([studX, 0, 3.9]) cylinder(r=studR, h=0.6, $fn=32);
    translate([studX, 0, 4.5]) cylinder(r1=studR, r2=1.25, h=0.5, $fn=32);
}

module link() {
    difference() {
        union() {
            // spine
            translate([Xsr, -6, 0]) cube([Xsf-Xsr, 12, 4]);
            // tongue (middle, thin in Y)
            translate([Xrear, -Ytong, 0]) cube([(4.5-Xrear), 7, 4]);
            // leaves (outer in Y)
            translate([Xlr, -6, 0]) cube([Xfront-Xlr, 2, 4]);
            translate([Xlr, 4, 0]) cube([Xfront-Xlr, 2, 4]);
            // pin stubs (teardrop, axis Y)
            translate([0, -3.0, 0]) rotate([90,0,0]) pin_stub(2.5);
            translate([0, 5.5, 0]) rotate([90,0,0]) pin_stub(2.5);
            // snap stud on top
            stud_solid();
        }
        // leaf holes (round, axis Y)
        translate([XpinF, -6.1, Zc]) rotate([-90,0,0]) cylinder(r=Rh, h=2.2, $fn=40);
        translate([XpinF, 3.9, Zc]) rotate([-90,0,0]) cylinder(r=Rh, h=2.2, $fn=40);
        // snap hole through (axis Z) + entry chamfers
        translate([holeX, 0, -0.1]) cylinder(r=holeR, h=4.2, $fn=32);
        translate([holeX, 0, 3.5]) cylinder(r1=holeR, r2=2.1, h=0.5, $fn=32);
        translate([holeX, 0, 0]) cylinder(r1=2.1, r2=holeR, h=0.5, $fn=32);
    }
}

if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-1.5, -6, 0], [56, 6, 5]]],
        ["support_faces", [["bed", "-z", 300]]],
        ["allowed_interferences", []],
        ["motions", [
            ["joint_bend", ["link3"], "rotate", [36, 0, 2], [0, 1, 0], [-30, 30]]
        ]],
        ["assembly_order", [
            [["link1"], [0, 0, 0]],
            [["link2"], [0, 0, -1]],
            [["link3"], [0, 0, -1]]
        ]],
        ["print_in_place", 0.5],
        ["overhangs_allowed", [
            ["hole top bridge span 2mm", [[16, 4, 3.4], [20, 6, 4]]],
            ["hole top bridge span 2mm", [[16, -6, 3.4], [20, -4, 4]]],
            ["hole top bridge span 2mm", [[34, 4, 3.4], [38, 6, 4]]],
            ["hole top bridge span 2mm", [[34, -6, 3.4], [38, -4, 4]]],
            ["hole top bridge span 2mm", [[52, 4, 3.4], [56, 6, 4]]],
            ["hole top bridge span 2mm", [[52, -6, 3.4], [56, -4, 4]]]
        ]]
    ]);
    instance("link1", "link", 1) translate([0, 0, 0]) link();
    instance("link2", "link", 1) translate([18, 0, 0]) link();
    instance("link3", "link", 1) translate([36, 0, 0]) link();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-1.5, -6, 0], [20, 6, 5]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed", "-z", 100]]],
        ["overhangs_allowed", [
            ["hole top bridge span 2mm", [[16, 4, 3.4], [20, 6, 4]]],
            ["hole top bridge span 2mm", [[16, -6, 3.4], [20, -4, 4]]]
        ]],
        ["copies", 3],
        ["details", [
            ["spine", "material", [[5, -5, 0], [9, 5, 4]], 0.9],
            ["slot", "void", [[14.5, -4, 0], [20, 4, 4]], 0.9],
            ["pin_hole", "hole", [18, -8, 2], [0, 1, 0], [[0, 4], [2, 4]]],
            ["snap_hole", "hole", [11, 0, 6], [0, 0, -1], [[0, 4.2], [0.5, 3.2], [3.5, 3.2], [4, 4.2]]],
            ["floor", "thickness", [9, 3, -1], [0, 0, 1], 4],
            ["snap", "view", [[5, -2, 4], [9, 2, 5]]]
        ]]
    ]);
    link();
}
