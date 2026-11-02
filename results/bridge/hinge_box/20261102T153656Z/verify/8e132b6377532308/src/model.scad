// Print-in-place hinged box, 80 x ~65 x 40 mm closed (80 x 56 body + hinge/catch)
// Parts: base, lid, pin.  Assembly = closed box.  Print pose = lid open 180 deg,
// lying flat behind the base, both trays opening up, pin captive in the knuckles.
part = "assembly"; // [assembly, base, lid]
cadverify_only = "";
module instance(name, p, unit = 1) {
    echo(cadverify_instance = [name, p, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
$fn = 48;
// ---- dimensions (assembly / closed coordinates) ----
W = 80; D = 56; base_h = 30; lid_top = 40; wall = 3;
ax_y = 32.5; ax_z = 20;            // hinge axis, 0.8 mm behind rear wall (y=28)
r_out = 3.7; r_bore = 2.6; r_stub = 2.15; // lid pin stubs, 0.45 radial clearance in base bores
base_segs = [[-34, -20], [-6, 8], [22, 34]];
lid_segs  = [[-19, -7], [9, 21]];
module cylx(x0, len, r) translate([x0, 0, 0]) rotate([0, 90, 0]) cylinder(h = len, r = r);
module base_closed() {
    difference() {
        union() {
            difference() {
                translate([-40, -28, 0]) cube([80, 56, 30]);
                translate([-37, -25, 3]) cube([74, 50, 30]);
            }
            for (s = base_segs) {
                translate([s[0], 27, 0]) cube([s[1] - s[0], 8.5, 20]); // pillar to bed, supports knuckle
                intersection() { // open-top cradle (lower knuckle): lid stub drops in, no enclosed bore
                    translate([0, ax_y, ax_z]) cylx(s[0], s[1] - s[0], r_out);
                    translate([s[0], ax_y - 4, ax_z - 4]) cube([s[1] - s[0], 8, 4.5]);
                }
            }
        }
        for (s = base_segs) translate([0, ax_y, ax_z]) cylx(s[0] - 1, s[1] - s[0] + 2, r_bore);
        translate([-5.5, -29, 24]) cube([11, 1.9, 3.5]); // catch pocket, front wall
    }
}
module lid_closed() {
    union() {
            translate([-40, -28, 37]) cube([80, 56, 3]);               // top panel
            difference() {                                              // skirt
                translate([-40, -28, 30.4]) cube([80, 56, 6.6]);
                translate([-37, -25, 29]) cube([74, 50, 8]);
            }
            for (s = lid_segs) {
                translate([s[0], 28, 20]) cube([s[1] - s[0], 4, 17]);  // hinge strap
                translate([0, ax_y, ax_z]) cylx(s[0], s[1] - s[0], r_out);
                translate([0, ax_y, ax_z]) cylx(s[0] - 4, s[1] - s[0] + 8, r_stub); // integral pin stubs into base cradles
            }
            translate([-7, -30.4, 30.4]) cube([14, 2.4, 6.6]);          // catch spacer
            translate([-7, -30.4, 21]) cube([14, 1.8, 12]);             // catch tab
            translate([-5, -28.6, 25.0]) cube([10, 1.0, 1.5]);          // catch bump (smaller, less snap penetration)
    }
}
module lid_print() translate([0, -28.8, 0]) translate([0, ax_y, ax_z])
    rotate([180, 0, 0]) translate([0, -ax_y, -ax_z]) lid_closed();
// ---- specs (exported-part coordinates) ----
if (part == "base") echo(cadverify_spec = [
    ["bounds", [[-40, -28, 0], [40, 36.2, 30]]], ["bodies", 1], ["through_holes", 0],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [["hinge cradle groove, pillars rise to the knuckles from the bed", [[-40, 26, 14], [40, 37, 24]]],
                            ["catch pocket ceiling", [[-8, -29, 23], [8, -26, 29]]]]],
    ["copies", 1],
    ["details", [
        ["floor", "material", [[-37, -25, 0], [37, 25, 3]], 0.95],
        ["cavity", "void", [[-36, -24, 10], [36, 24, 29]], 0.98],
        ["base_knuckle", "material", [[-30, 34.8, 19], [-24, 35.8, 20]], 0.7],
        ["cradle_groove", "void", [[-30, 31.8, 19.3], [-24, 33.2, 20.7]], 0.95],
        ["front_wall", "thickness", [0, -35, 15], [0, 1, 0], 3]
    ]]]);
if (part == "lid") echo(cadverify_spec = [
    ["bounds", [[-40, 0, 0], [40, 66.6, 23.7]]], ["bodies", 1], ["through_holes", 1],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [["strap and hinge knuckle undersides, within 5 mm of the panel edge and straps", [[-40, 0, 2], [40, 10, 24]]],
                            ["catch tab and bump undersides", [[-8, 62, 2], [8, 67, 20]]]]],
    ["copies", 1],
    ["details", [
        ["panel", "material", [[-37, 10, 0], [37, 60, 3]], 0.95],
        ["tray_cavity", "void", [[-35, 14, 3.5], [35, 57, 9]], 0.95],
        ["strap", "material", [[10, 5, 10], [20, 7.5, 18]], 0.85],
        ["panel_thickness", "thickness", [0, 35, -5], [0, 0, 1], 3],
        ["catch_tab", "view", [[-8, 64, 6], [8, 67, 20]]]
    ]]]);
if (part == "assembly") echo(cadverify_spec = [
    ["bounds", [[-40, -30.4, 0], [40, 36.2, 40]]],
    ["support_faces", [["bed", "-z", 4000]]],
    ["allowed_interferences", []],
    ["motions", [["lid_open", ["lid"], "rotate", [0, 32.5, 20], [-1, 0, 0], [0, 180],
        ["flex", [["lid", "base", 1.0, "catch bump snaps out of its pocket and tab flexes"]]]]]],
    ["assembly_order", [
        [["base"], [0, 0, 0]],
        [["lid"], [0, 0, -1], ["rotate", [0, 32.5, 20], [-1, 0, 0], 180]]
    ]],
    ["print_in_place", 0.4],
    ["print_pose", [["lid_open", 180]]],
    ["overhangs_allowed", [["hinge cradles, knuckles, straps and pin stubs, supported by pillars, panel edge and straps within 5 mm", [[-40, 27, 2], [40, 38, 26]]],
                            ["catch tab, spacer and bump in print pose", [[-8, 88, 2], [8, 96, 20]]],
                            ["catch pocket ceiling", [[-8, -31, 20], [8, -26, 29]]]]]
]);
// ---- output ----
if (part == "base") base_closed();
else if (part == "lid") lid_print();
else if (part == "assembly") {
    instance("base", "base") base_closed();
    instance("lid", "lid") lid_closed();
}
