// Bracelet of hinged links, printed in place (3-link sample of a 10-link chain)
part = "link"; // [link, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
// link: pitch 18 (X), width 12 (Y), body 4 thick + 1 snap stud = 5
// hinge: teardrop pin (r1.1) in U-cradle (r1.8, open at top), 0.7 radial, 0.6 side clearance
P = 18; W = 12; Zc = 2.0;
Rp = 1.1; Rh = 1.8; SlotH = 1.8;
Ytong = 3.4;
Xrear = -1.5; Xsr = 3.5; Xsf = 14.5; Xlr = 13.5; Xfront = 20;
XpinF = 18;
studX = 7; studR = 1.75;
holeX = 11; holeR = 1.6;
module teardrop2D() {
    pts = concat([for (a=[0:180/16:180]) [Rp*cos(a), Zc+Rp*sin(a)]], [[0, Zc-Rp]]);
    polygon(pts);
}
module pin_stub(len) { linear_extrude(height=len) teardrop2D(); }
module stud_solid() {
    translate([studX, 0, 3.9]) cylinder(r=studR, h=0.6, $fn=32);
    translate([studX, 0, 4.5]) cylinder(r1=studR, r2=1.25, h=0.5, $fn=32);
}
module link() {
    difference() {
        union() {
            translate([Xsr, -6, 0]) cube([Xsf-Xsr, 12, 4]);
            translate([Xrear, -Ytong, 0]) cube([(4.5-Xrear), 2*Ytong, 4]);
            translate([Xlr, -6, 0]) cube([Xfront-Xlr, 2, 4]);
            translate([Xlr, 4, 0]) cube([Xfront-Xlr, 2, 4]);
            translate([0, -2.5, 0]) rotate([90,0,0]) pin_stub(3.0);
            translate([0, 5.5, 0]) rotate([90,0,0]) pin_stub(3.0);
            stud_solid();
        }
        translate([XpinF, -6.1, Zc]) rotate([-90,0,0]) cylinder(r=Rh, h=2.2, $fn=40);
        translate([XpinF, 3.9, Zc]) rotate([-90,0,0]) cylinder(r=Rh, h=2.2, $fn=40);
        translate([XpinF-SlotH, 3.9, 1.9]) cube([2*SlotH, 2.2, 2.2]);
        translate([XpinF-SlotH, -6.1, 1.9]) cube([2*SlotH, 2.2, 2.2]);
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
        ["motions", [["joint_bend", ["link3"], "rotate", [36, 0, 2], [0, 1, 0], [-30, 30]]]],
        ["assembly_order", [[["link1"], [0, 0, 0]], [["link2"], [0, 0, -1]], [["link3"], [0, 0, -1]]]],
        ["print_in_place", 0.5],
        ["overhangs_allowed", []]
    ]);
    instance("link1", "link", 1) translate([0, 0, 0]) link();
    instance("link2", "link", 1) translate([18, 0, 0]) link();
    instance("link3", "link", 1) translate([36, 0, 0]) link();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-1.5, -6, 0], [20, 6, 5]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 100]]],
        ["overhangs_allowed", []],
        ["copies", 3],
        ["details", [
            ["spine", "material", [[5, -5, 0], [9, 5, 4]], 0.9],
            ["slot", "void", [[14.5, -4, 0], [20, 4, 4]], 0.9],
            ["cradle", "void", [[16.2, 4, 1.9], [19.8, 6.1, 4.1]], 0.9],
            ["snap_hole", "hole", [11, 0, 6], [0, 0, -1], [[0, 4.2], [0.5, 3.2], [3.5, 3.2]]],
            ["floor", "thickness", [9, 3, -1], [0, 0, 1], 4],
            ["snap", "view", [[5, -2, 4], [9, 2, 5]]]
        ]]
    ]);
    link();
}
