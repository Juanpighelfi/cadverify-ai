// Box with print-in-place hinge
// Closed body 80 (x) x 54 (y body, 61.5 incl. hinge) x 40 (z) mm.
// Lid occupies the top 10 mm. Hinge pin axis: y=58, z=20 (mid-height at the
// back), so swinging the lid -180 deg about that axis lays the lid flat on
// the bed behind the box: that is the print-in-place pose.
// Clearances (PLA, 0.4 nozzle): pin/bore 0.40 radial, knuckle axial gaps
// 0.6, lid lip to box walls 0.4, lid barrels to box back wall 0.5.

part = "assembly"; // [assembly, box, lid, pin]
cadverify_only = "";

W = 80; D = 54; H = 40; box_h = 30;
wall = 2.4; floor_t = 3; plate_t = 3;
hinge_y = 58; hinge_z = 20;
barrel_r = 3.5; bore_r = 2.0; pin_r = 1.55; cap_r = 2.9;
hinge_ymax = hinge_y + barrel_r;          // 61.5
box_segs  = [[9, 11], [32.2, 11], [55.4, 11]];   // [x0, len]
lid_segs  = [[20.6, 11], [43.8, 11]];
pin_x0 = 10; pin_len = 55;

module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Extrude a (y,z) profile along +x starting at x0, offset by (oy,oz).
module extrude_yz(profile, x0, len, oy = 0, oz = 0) {
    multmatrix([[0,0,1,x0],[1,0,0,oy],[0,1,0,oz],[0,0,0,1]])
        linear_extrude(height = len) polygon(points = profile);
}

module barrel(x0, len) {
    translate([x0, hinge_y, hinge_z]) rotate([0, 90, 0])
        cylinder(h = len, r = barrel_r, $fn = 48);
}

bore_fr = pin_r * cos(22.5) + 0.45;   // bore facet distance: uniform 0.45 gap around the pin
bore_oct_r = bore_fr / cos(22.5);
module bore_cut() {
    // octagonal bore, same diamond orientation as the pin: facet gap 0.45 everywhere
    extrude_yz(oct_pts(bore_oct_r, 0), 4, 72, hinge_y, hinge_z);
}

module box_closed() {
    difference() {
        union() {
            // floor and walls up to z=30
            translate([0, 0, 0]) cube([W, D, floor_t]);
            translate([0, 0, floor_t]) cube([W, wall, box_h - floor_t]);              // front
            translate([0, D - wall, floor_t]) cube([W, wall, box_h - floor_t]);       // back
            translate([0, wall, floor_t]) cube([wall, D - 2*wall, box_h - floor_t]);  // left
            translate([W - wall, wall, floor_t]) cube([wall, D - 2*wall, box_h - floor_t]); // right
            // front catch detent bump on the inner front wall (wedged ridge)
            extrude_yz([[2.4,25.3],[3.4,26.5],[3.4,27.5],[2.4,28.7]], 36, 8);
            // hinge knuckles + arms to the back wall
            for (s = box_segs) {
                barrel(s[0], s[1]);
                translate([s[0], 53.5, hinge_z - 1.8]) cube([s[1], 5, 3.6]);
            }
        }
        bore_cut();
    }
}

module lid_closed() {
    difference() {
        union() {
            // top plate + back hinge tabs
            translate([0, 0, H - plate_t]) cube([W, D, plate_t]);
            for (s = lid_segs) translate([s[0], 53, H - plate_t]) cube([s[1], 6, plate_t]);
            // external skirt (down to z=30, flush with box walls outside)
            translate([0, 0, box_h]) cube([W, wall, H - plate_t - box_h]);                  // front
            translate([0, D - wall, box_h]) cube([W, wall, H - plate_t - box_h]);           // back
            translate([0, wall, box_h]) cube([wall, D - 2*wall, H - plate_t - box_h]);      // left
            translate([W - wall, wall, box_h]) cube([wall, D - 2*wall, H - plate_t - box_h]); // right
            // inner sealing lip (0.4 clear of box inner walls)
            translate([2.8, 2.8, 31]) cube([74.4, 2, 6]);        // front lip
            translate([2.8, 49.2, 31]) cube([74.4, 2, 6]);       // back lip
            translate([2.8, 4.8, 31]) cube([2, 44.4, 6]);        // left lip
            translate([75.2, 4.8, 31]) cube([2, 44.4, 6]);       // right lip
            // central catch tongue on the front lip, reaching down to z=23
            translate([33, 2.8, 23]) cube([14, 2, 8]);
            // hinge knuckles + diagonal straps up to the plate tabs
            for (s = lid_segs) {
                barrel(s[0], s[1]);
                extrude_yz([[54.5,39],[58.5,39],[60.2,27],[58,18.5],[54.5,21]], s[0], s[1]);
            }
        }
        bore_cut();
        // catch notch in the tongue: open at the bottom, receives the box detent bump when shut
        translate([34.5, 2.7, 22.5]) cube([11, 1.25, 7]);
        // fingernail scoop in the front skirt bottom edge
        translate([40, -1, box_h]) rotate([90, 0, 0]) cylinder(h = 4, r = 4.5, $fn = 32);
    }
}

function oct_pts(r, off = 22.5) = [for (i = [0:7]) let (a = off + 45*i) [r*cos(a), r*sin(a)]];

module pin_closed() {
    // octagonal axle with a vertex up/down (45 deg facets, no flat ceiling),
    // ends protrude past the outer knuckles
    extrude_yz(oct_pts(pin_r, 0), pin_x0, pin_len, hinge_y, hinge_z);
}

// --- printed (as-exported) orientations ---
module lid_printed() {
    // closed lid rotated 180 deg about the hinge axis, then dropped to y=0
    translate([0, hinge_ymax, H]) rotate([180, 0, 0]) lid_closed();
}
pin_off = pin_r; // 1.55 half-height of the diamond-oriented shaft
module pin_printed() {
    translate([-pin_x0, -(hinge_y - pin_off), -(hinge_z - pin_off)]) pin_closed();
}

box_spec = [
    ["bounds", [[0, 0, 0], [W, hinge_ymax, box_h]]],
    ["bodies", 1],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [
        ["hinge barrels and arms: horizontal print-in-place axle housings, bore is self-supported inside the tube", [[8, 53, 16], [67.5, 62, 24]]]
    ]],
    ["copies", 1],
    ["details", [
        ["floor", "material", [[10, 10, 0.5], [70, 44, 2.5]], 0.98],
        ["interior", "void", [[6, 6, 8], [74, 48, 24]], 0.98],
        ["front_wall", "thickness", [40, -1, 15], [0, 1, 0], 2.4],
        ["knuckle_arm", "material", [[10, 53.8, 18.8], [19, 55.8, 21.2]], 0.9],
        ["hinge_bore", "void", [[10, 57.1, 19.1], [19, 58.9, 20.9]], 1.0],
        ["catch_bump", "material", [[37, 2.6, 26.6], [43, 3.3, 27.4]], 0.85],
        ["catch_bump_view", "view", [[35, 2, 24], [45, 4.5, 29.5]]],
        ["hinge_view", "view", [[8, 53, 15], [67, 62, 25]]]
    ]]
];

lid_spec = [
    ["bounds", [[0, 0, 0], [W, hinge_ymax, 23.5]]],
    ["bodies", 1],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", [
        ["hinge barrels and straps: horizontal print-in-place axle housings", [[20, 0, 0], [55.5, 8, 24]]],
        ["catch groove underside in print pose", [[34, 56, 11], [46, 59, 15]]]
    ]],
    ["copies", 1],
    ["details", [
        ["top_plate", "material", [[10, 17.5, 0.5], [70, 51.5, 2.5]], 0.98],
        ["front_skirt", "material", [[10, 59.3, 4.5], [70, 61.3, 7.5]], 0.9],
        ["plate_thickness", "thickness", [40, 30, -1], [0, 0, 1], 3],
        ["tongue", "material", [[38, 57, 9.2], [42, 58.5, 10.3]], 0.85],
        ["catch_groove", "void", [[37, 57.7, 12], [43, 58.5, 14]], 1.0],
        ["hinge_bore", "void", [[23, 2.6, 19.1], [29, 4.4, 20.9]], 1.0],
        ["strap", "material", [[23, 3.5, 8], [29, 6.5, 12]], 0.8],
        ["catch_groove_view", "view", [[33, 56.5, 9], [47, 59, 17]]],
        ["lid_knuckle_view", "view", [[20, 0, 16], [32, 8, 24]]]
    ]]
];

pin_spec = [
    ["bounds", [[0, 0, 0], [pin_len, 2*pin_off, 2*pin_off]]],
    ["bodies", 1],
    ["overhangs_allowed", [
        ["45 degree lower facets of the diamond print-in-place axle, 0.45 above the bore", [[-0.1, -0.1, -0.1], [55.1, 3.2, 1.6]]]
    ]],
    ["copies", 1],
    ["details", [
        ["shaft", "material", [[10, 0.9, 0.9], [50, 2.2, 2.2]], 0.9],
        ["shaft_thickness", "thickness", [30, pin_off, -1], [0, 0, 1], 3.1],
        ["pin_end_view", "view", [[0, 0, 0], [3, 3.1, 3.1]]]
    ]]
];

assembly_spec = [
    ["bounds", [[0, 0, 0], [W, hinge_ymax, H]]],
    ["support_faces", [["table", "-z", 4000]]],
    ["motions", [
        ["lid_swing", ["lid"], "rotate", [0, hinge_y, hinge_z], [1, 0, 0], [-180, 0],
            ["flex", [["lid", "box", 1.0, "front catch tongue snaps 0.6 mm over the detent bump while closing"]]]]
    ]],
    ["assembly_order", [
        [["box"], [0, 0, 0]],
        [["lid"], [0, 0, -1], ["rotate", [0, hinge_y, hinge_z], [1, 0, 0], 180]],
        [["pin"], [1, 0, 0]]
    ]],
    ["print_in_place", 0.4],
    ["print_pose", [["lid_swing", -180]]],
    ["overhangs_allowed", [
        ["box hinge barrels in print pose", [[8, 53, 16], [67.5, 62, 24]]],
        ["lid hinge barrels and straps in print pose", [[20, 53, 0], [56, 62, 24]]],
        ["horizontal pin inside its bore, 0.4 above the bore surface", [[5, 55, 16.5], [70.5, 61, 20]]],
        ["lid catch groove in print pose", [[33, 110, 2], [47, 114, 18]]]
    ]]
];

if (part == "box") {
    echo(cadverify_spec = box_spec);
    box_closed();
} else if (part == "lid") {
    echo(cadverify_spec = lid_spec);
    lid_printed();
} else if (part == "pin") {
    echo(cadverify_spec = pin_spec);
    pin_printed();
} else {
    echo(cadverify_spec = assembly_spec);
    instance("box", "box") box_closed();
    instance("lid", "lid")
        translate([0, hinge_ymax, H]) rotate([180, 0, 0]) lid_printed();
    instance("pin", "pin")
        translate([pin_x0, hinge_y - pin_off, hinge_z - pin_off]) pin_printed();
}
