// Print-in-place hinged box, 80 x 60 x 40 mm closed.
// Printed closed in PLA (Bambu A1, 0.4 nozzle): base, lid and a captive
// hinge pin are separate bodies with 0.35-0.6 mm clearances, so the hinge
// breaks free by hand.  No supports: the lid underside bridges the cavity,
// the hinge barrels/pin use faceted (octagonal) lower surfaces, and all
// other downward faces are short bridges or rest on the body below.

/* [Part] */
part = "assembly"; // [assembly, box, lid, pin]

/* [Dimensions] */
box_w = 80;          // X, outside
box_d = 60;          // Y, outside (front y=0, back y=60)
box_h = 29.6;        // base height to its rim
lid_h = 10;          // lid height; lid bottom at z=30 (0.4 gap)
lid_z = 30;
wall = 3;
floor_t = 3;
total_h = 40;

hinge_y = 55.8;      // hinge axis, assembly coords
hinge_z = 35;
barrel_r = 4.0;
pin_r = 2.4;         // octagon circumradius
bore_r = 2.75;       // pin_r + 0.35 radial clearance
relief_r = 4.6;      // barrel_r + 0.6

// Alternating knuckles along the back edge (x intervals), 0.6 mm end gaps.
box_segs  = [[6.3, 19.3], [33.5, 46.5], [60.7, 73.7]];
lid_segs  = [[19.9, 32.9], [47.1, 60.1]];

cadverify_only = "";
module instance(name, part_name, unit = 1) {
    echo(cadverify_instance = [name, part_name, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------------------------------------------------------------- base (box)
module box_main() {
    difference() {
        union() {
            // shell: outer block minus open-top cavity
            difference() {
                cube([box_w, box_d, box_h]);
                translate([wall, wall, floor_t]) cube([box_w - 2 * wall, box_d - 2 * wall, box_h]);
            }
            // hinge knuckles (base) + support posts down to the back wall
            for (s = box_segs) {
                translate([s[0], hinge_y, hinge_z]) rotate([0, 90, 0])
                    cylinder(h = s[1] - s[0], r = barrel_r, $fn = 48);
                translate([s[0], 53.8, 24]) cube([s[1] - s[0], 6.2, 11.5]);
            }
            // front catch tooth (enters the socket in the lid)
            translate([35, 0, box_h]) cube([10, wall, 2.6]);
        }
        // pin bore through the base knuckles
        translate([-1, hinge_y, hinge_z]) rotate([0, 90, 0])
            cylinder(h = box_w + 2, r = bore_r, $fn = 48);
    }
}

// ---------------------------------------------------------------- lid (local: z 0..10, hinge axis at z=5)
module lid_main() {
    union() {
        difference() {
            union() {
                // main slab, side profile (Y-Z) extruded along X.
                // Rear lower edge chamfered 50,0 -> 60,8 so the slab
                // swings clear of the base back wall.
                rotate([0, 90, 0])
                    linear_extrude(height = box_w)
                        polygon(points = [[0, 0], [0, 50], [-8, 60], [-10, 60], [-10, 0]]);
                // hinge knuckles (lid)
                for (s = lid_segs)
                    translate([s[0], hinge_y, 5]) rotate([0, 90, 0])
                        cylinder(h = s[1] - s[0], r = barrel_r, $fn = 48);
            }
            // recessed panel in the top face
            translate([6, 6, 6.5]) cube([68, 48, 4]);
            // front catch socket (tooth: x35..45, z assy 29.6..32.2)
            translate([34.4, -1, -0.5]) cube([11.2, 4.6, 3.2]);
            // clearance tunnel for the base knuckles / pin
            translate([-1, hinge_y, 5]) rotate([0, 90, 0])
                cylinder(h = box_w + 2, r = relief_r, $fn = 48);
            // pin bore through the lid knuckles
            translate([-1, hinge_y, 5]) rotate([0, 90, 0])
                cylinder(h = box_w + 2, r = bore_r, $fn = 48);
        }
        // webs joining lid knuckles to the slab: upper half-discs r=4.9
        // (stay above z=30.1 in assembly, clear of the base rim at 29.6)
        for (s = lid_segs)
            intersection() {
                translate([s[0], hinge_y, 5]) rotate([0, 90, 0])
                    cylinder(h = s[1] - s[0], r = 4.9, $fn = 48);
                translate([s[0], hinge_y - 10, 5]) cube([s[1] - s[0], 20, 5]);
                translate([s[0], 0, 0]) cube([s[1] - s[0], box_d, lid_h]);
            }
    }
}

// ---------------------------------------------------------------- pin
// Centred on its axis, local +Z from head (z=0) to tip (z=71.2).
module pin_geom() {
    union() {
        cylinder(h = 1.3, r = 3.3, $fn = 32);                    // head
        translate([0, 0, 1.0]) rotate([0, 0, 22.5])
            cylinder(h = 69.5, r = pin_r, $fn = 8);              // octagonal shaft
        translate([0, 0, 70.4]) rotate([0, 0, 22.5])
            cylinder(h = 0.8, r1 = pin_r, r2 = 1.2, $fn = 8);    // lead-in tip
    }
}
module pin_part() { translate([3.3, 3.3, 0]) pin_geom(); }

// ---------------------------------------------------------------- output
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [box_w, box_d, hinge_z + barrel_r]]],
        ["bodies", 1],
        ["copies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [["hinge knuckles and pin bore print in place; faceted bore ceiling is a short internal bridge", [[5, 51, 30], [75, 60, 39.5]]]]],
        ["details", [
            ["cavity", "void", [[4, 4, 10], [76, 53, 29]], 0.95],
            ["front_wall", "thickness", [40, -1, 15], [0, 1, 0], 3],
            ["floor", "thickness", [40, 30, -1], [0, 0, 1], 3],
            ["box_knuckle", "material", [[7, 52, 33.5], [18, 53.8, 36.5]], 0.85],
            ["pin_bore", "void", [[8, 54.9, 34.1], [17, 56.7, 35.9]], 0.9],
            ["catch_tooth", "material", [[36, 0.5, 30], [44, 2.5, 32]], 0.85],
            ["hinge_knuckles", "view", [[4, 50, 28], [76, 60, 39.5]]]
        ]]
    ]);
    box_main();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [box_w, box_d, lid_h]]],
        ["bodies", 1],
        ["copies", 1],
        ["support_faces", [["print_face", "-z", 3000]]],
        ["overhangs_allowed", [["lid knuckle bores print in place around the pin; bore ceilings are short internal bridges", [[5, 51, 0], [75, 60, 10]]]]],
        ["details", [
            ["top_pocket", "void", [[7, 7, 6.6], [73, 53, 9.9]], 0.95],
            ["lid_slab", "thickness", [40, 30, 9], [0, 0, -1], 6.5],
            ["lid_knuckle", "material", [[21, 52, 3.5], [32, 53.8, 6.5]], 0.85],
            ["pin_bore", "void", [[22, 55, 4.2], [31, 56.6, 5.8]], 0.9],
            ["catch_socket", "void", [[35, 0.5, 0.2], [45, 2.5, 2.5]], 0.9],
            ["hinge_knuckles", "view", [[4, 50, 0], [76, 60, 10]]]
        ]]
    ]);
    lid_main();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [6.6, 6.6, 71.2]]],
        ["bodies", 1],
        ["copies", 1],
        ["support_faces", [["head_base", "-z", 30]]],
        ["overhangs_allowed", []],
        ["details", [
            ["pin_shaft", "material", [[2, 2, 10], [4.6, 4.6, 20]], 0.9],
            ["pin_head", "material", [[1, 1, 0.1], [5.6, 5.6, 1.2]], 0.75],
            ["pin_length", "thickness", [1.2, 3.3, 72], [0, 0, -1], 71.2],
            ["pin_head_view", "view", [[0, 0, 0], [6.6, 6.6, 2]]]
        ]]
    ]);
    pin_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [box_w, box_d, total_h]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0, hinge_y, hinge_z], [-1, 0, 0], [0, 110]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["lid"], [0, 0, -1]],
            [["pin"], [-1, 0, 0]]
        ]]
    ]);
    instance("base", "box") box_main();
    instance("lid", "lid") translate([0, 0, lid_z]) lid_main();
    instance("pin", "pin") translate([75.2, hinge_y, hinge_z]) rotate([0, -90, 0]) pin_geom();
}
