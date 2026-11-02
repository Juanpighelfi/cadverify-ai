// Print-in-place hinged box, 80 x ~65 x 40 mm closed (80 x 56 body + hinge/catch)
// Parts: base, lid, pin.  Assembly = closed box.  Print pose = lid open 180 deg,
// lying flat behind the base, both trays opening up, pin captive in the knuckles.
part = "assembly"; // [assembly, base, lid, pin]
cadverify_only = "";
module instance(name, p, unit = 1) {
    echo(cadverify_instance = [name, p, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
$fn = 48;
// ---- dimensions (assembly / closed coordinates) ----
W = 80; D = 56; base_h = 30; lid_top = 40; wall = 3;
ax_y = 31; ax_z = 20;              // hinge axis
r_out = 3.7; r_bore = 2.6; r_pin = 2.2; // 0.4 radial clearance pin/bore
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
                translate([s[0], 27, 17]) cube([s[1] - s[0], 7.5, 6]);
                translate([0, ax_y, ax_z]) cylx(s[0], s[1] - s[0], r_out);
            }
        }
        for (s = base_segs) translate([0, ax_y, ax_z]) cylx(s[0] - 1, s[1] - s[0] + 2, r_bore);
        translate([-5.5, -29, 24]) cube([11, 1.9, 3.5]); // catch pocket, front wall
    }
}
module lid_closed() {
    difference() {
        union() {
            translate([-40, -28, 37]) cube([80, 56, 3]);               // top panel
            difference() {                                              // skirt
                translate([-40, -28, 30.4]) cube([80, 56, 6.6]);
                translate([-37, -25, 29]) cube([74, 50, 8]);
            }
            for (s = lid_segs) {
                translate([s[0], 28, 20]) cube([s[1] - s[0], 4, 17]);  // hinge strap
                translate([0, ax_y, ax_z]) cylx(s[0], s[1] - s[0], r_out);
            }
            translate([-7, -30.4, 30.4]) cube([14, 2.4, 6.6]);          // catch spacer
            translate([-7, -30.4, 21]) cube([14, 1.8, 12]);             // catch tab
            translate([-5, -28.6, 24.5]) cube([10, 1.2, 2.5]);          // catch bump
        }
        for (s = lid_segs) translate([0, ax_y, ax_z]) cylx(s[0] - 1, s[1] - s[0] + 2, r_bore);
    }
}
module pin_local() { // axis = X axis through origin, head at +X
    cylx(-36.5, 71.5, r_pin);
    cylx(35, 2.5, 3.3);
}
module lid_print() translate([0, -27.3, 0]) translate([0, ax_y, ax_z])
    rotate([180, 0, 0]) translate([0, -ax_y, -ax_z]) lid_closed();
module pin_print() translate([0, 0, 3.3]) pin_local();
// ---- specs (exported-part coordinates) ----
if (part == "base") echo(cadverify_spec = [
    ["bounds", [[-40, -28, 0], [40, 34.7, 30]]], ["bodies", 1], ["through_holes", 0],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [["hinge knuckle undersides, webs support them", [[-40, 26, 14], [40, 35, 26]]],
                            ["catch pocket ceiling", [[-8, -29, 23], [8, -26, 29]]]]],
    ["copies", 1],
    ["details", [
        ["floor", "material", [[-37, -25, 0], [37, 25, 3]], 0.95],
        ["cavity", "void", [[-36, -24, 10], [36, 24, 29]], 0.98],
        ["base_knuckle", "material", [[-30, 29.5, 18.5], [-24, 32, 21.5]], 0.9],
        ["hinge_bore", "void", [[-33, 29.5, 18.5], [-21, 32.5, 21.5]], 0.95],
        ["front_wall", "thickness", [0, -35, 15], [0, 1, 0], 3]
    ]]]);
if (part == "lid") echo(cadverify_spec = [
    ["bounds", [[-40, 0, 0], [40, 65.1, 23.7]]], ["bodies", 1], ["through_holes", 0],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [["hinge knuckle undersides, straps support them", [[-40, 0, 15], [40, 8, 24]]],
                            ["catch bump underside", [[-8, 62, 9], [8, 66, 19]]]]],
    ["copies", 1],
    ["details", [
        ["panel", "material", [[-37, 9, 0], [37, 60, 3]], 0.95],
        ["tray_cavity", "void", [[-35, 12, 3.5], [35, 57, 9]], 0.95],
        ["strap", "material", [[10, 3, 10], [20, 6.5, 18]], 0.85],
        ["panel_thickness", "thickness", [0, 35, -5], [0, 0, 1], 3],
        ["catch_tab", "view", [[-8, 62, 9], [8, 66, 19]]]
    ]]]);
if (part == "pin") echo(cadverify_spec = [
    ["bounds", [[-36.5, -3.3, 0], [37.5, 3.3, 6.6]]], ["bodies", 1], ["through_holes", 0],
    ["overhangs_allowed", [["round pin shaft and head underside", [[-37, -3.4, 0], [38, 3.4, 3.3]]]]],
    ["copies", 1],
    ["details", [
        ["shaft", "material", [[-20, -1.5, 1.8], [0, 1.5, 4.8]], 0.95],
        ["head", "view", [[34, -3.3, 0], [38, 3.3, 6.6]]]
    ]]]);
if (part == "assembly") echo(cadverify_spec = [
    ["bounds", [[-40, -30.4, 0], [40, 34.7, 40]]],
    ["support_faces", [["bed", "-z", 4000]]],
    ["allowed_interferences", []],
    ["motions", [["lid_open", ["lid"], "rotate", [0, 31, 20], [-1, 0, 0], [0, 180],
        ["flex", [["lid", "base", 1.0, "catch bump snaps out of its pocket and tab flexes"]]]]]],
    ["assembly_order", [
        [["base"], [0, 0, 0]],
        [["lid"], [0, 0, -1]],
        [["pin"], [-1, 0, 0]]
    ]],
    ["print_in_place", 0.4],
    ["print_pose", [["lid_open", 180]]],
    ["overhangs_allowed", [["hinge knuckles and in-place pin undersides, supported by knuckle webs and straps within 5 mm", [[-40, 26, 14], [40, 36, 26]]],
                            ["catch pocket and bump", [[-8, -31, 20], [8, -26, 29]]]]]
]);
// ---- output ----
if (part == "base") base_closed();
else if (part == "lid") lid_print();
else if (part == "pin") pin_print();
else if (part == "assembly") {
    instance("base", "base") base_closed();
    instance("lid", "lid") lid_closed();
    instance("pin", "pin") translate([0, ax_y, ax_z]) pin_local();
}
