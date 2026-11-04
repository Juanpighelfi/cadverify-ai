// Crank gear train, printed in place. PLA, Bambu Lab A1, 0.4 mm nozzle.
// Four meshing spur gears on capped fixed pins, on a 100 x 60 mm base.
// Gear 1 carries a crank peg and a notched detent flange; a flexible leaf
// on the base clicks into the flange notches every quarter turn.
//
// Print-in-place clearances used throughout (mm):
//   gear bore / pin        0.4 radial
//   gear underside / plate 0.6 vertical
//   cap underside / gear   0.6 vertical
//   detent wall / gear tip 0.6
//   gear mesh              extra centre distance 0.4 + tooth thinning 0.4
part = "assembly"; // ["assembly", "base", "gear1", "gear2", "gear3", "gear4"]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* [Gear geometry] */
mod = 1.5;                    // gear module
press_deg = 20;               // pressure angle
gear_h = 5;                   // gear thickness
backlash = 0.4;               // circumferential tooth thinning
extra_centre = 0.4;           // extra centre distance per mesh
z1 = 18; z2 = 12; z3 = 16; z4 = 10;
function pitch_r(z) = mod * z / 2;
r1 = pitch_r(z1); r2 = pitch_r(z2); r3 = pitch_r(z3); r4 = pitch_r(z4);

// centres, in assembly coordinates
y_c = 30;
x1 = 21;
x2 = x1 + r1 + r2 + extra_centre;          // 43.9
x3 = x2 + r2 + r3 + extra_centre;          // 65.3
x4 = x3 + r3 + r4 + extra_centre;          // 85.2
centres = [[x1, y_c], [x2, y_c], [x3, y_c], [x4, y_c]];

base_w = 100; base_d = 60; plate_h = 3;
gear_z = plate_h + 0.6;                    // underside of every gear: 3.6
pin_r = 3; bore_r = 3.4;                   // 0.4 radial clearance
cap_r = 5; cap_h = 2;
// cap underside is 0.6 above the top of the thing it retains
cap1_bot = gear_z + gear_h + 3.2 + 0.6;    // gear1 flange top + 0.6 = 12.4
cap_bot  = gear_z + gear_h + 0.6;          // plain gears: 9.2

/* ---------- involute gear outline ---------- */
function inv(a) = tan(a * 180 / PI) - a;   // a in radians
function pol(r, a) = [r * cos(a * 180 / PI), r * sin(a * 180 / PI)];
function rot2(p, a_deg) = [p[0] * cos(a_deg) - p[1] * sin(a_deg),
                           p[0] * sin(a_deg) + p[1] * cos(a_deg)];

function half_ang(z, r, rb, rp) =
    let(pa = press_deg * PI / 180,
        ar = acos(rb / r) * PI / 180,
        hp = PI / (2 * z) - backlash / (2 * rp))
    hp + inv(pa) - inv(ar);

function tooth_pts(z) =
    let(rp = pitch_r(z), rb = rp * cos(press_deg), rt = rp + mod,
        rr = rp - 1.25 * mod, pitch_a = 2 * PI / z,
        rs = max(rb, rr), steps = 4,
        ha_root = half_ang(z, rs, rb, rp))
    concat(
        // root arc to involute start, flank up, tip point, flank down
        [pol(rr, -pitch_a / 2), pol(rr, -ha_root)],
        [for (i = [1 : steps]) let(r = rs + (rt - rs) * i / steps)
             pol(r, -half_ang(z, r, rb, rp))],
        [for (i = [steps - 1 : -1 : 0]) let(r = rs + (rt - rs) * i / steps)
             pol(r, half_ang(z, r, rb, rp))],
        [pol(rr, ha_root)]);

function gear_pts(z) =
    [for (i = [0 : z - 1]) for (p = tooth_pts(z)) rot2(p, i * 360 / z)];

module gear_solid(z) {
    linear_extrude(height = gear_h) polygon(points = gear_pts(z));
}
module gear_plain(z) {
    difference() {
        gear_solid(z);
        translate([0, 0, -1]) cylinder(r = bore_r, h = gear_h + 2, $fn = 48);
    }
}

/* ---------- the parts, each in its own print orientation ---------- */
// base: plate on the bed, pins standing up. Origin at a plate corner.
module base() {
    // rounded plate
    hull() for (cx = [6, base_w - 6], cy = [6, base_d - 6])
        translate([cx, cy, 0]) cylinder(r = 6, h = plate_h, $fn = 36);
    // fixed pins with retaining caps (caps 45 deg conical: no support needed)
    for (i = [0 : 3]) {
        c = centres[i];
        bot = (i == 0) ? cap1_bot : cap_bot;
        translate([c[0], c[1], 0]) cylinder(r = pin_r, h = bot + cap_h, $fn = 36);
        translate([c[0], c[1], bot]) cylinder(r1 = cap_r, r2 = pin_r, h = cap_h, $fn = 36);
    }
    // Flexible detent: an arc wall south-east of gear 1, inner radius
    // 15.6 (0.6 clear of the gear-1 tip circle), standing on the plate
    // up to flange height. A short arm at its south end reaches north
    // at flange height and carries the bump. The wall flexes radially.
    intersection() {
        difference() {
            translate([x1, y_c, plate_h]) cylinder(r = 17.4, h = 6.9, $fn = 72);
            translate([x1, y_c, plate_h - 1]) cylinder(r = 15.6, h = 8.9, $fn = 72);
        }
        translate([0, 0, plate_h]) linear_extrude(height = 6.9)
            polygon(points = [[x1, y_c],
                              [x1 + 20 * cos(-90), y_c + 20 * sin(-90)],
                              [x1 + 20 * cos(-32), y_c + 20 * sin(-32)]]);
    }
    // arm at flange height, from the wall (y 14) north to the rim (y 19.4)
    translate([x1 - 0.7, 14, 9.4]) cube([1.4, 5.4, 1.5]);
    // bump: half-round knob centred on the flange rim (radius 11 south),
    // protruding north of the rim line into a notch when one aligns
    translate([x1, y_c - 11, 9.4]) cylinder(r = 0.65, h = 1.5, $fn = 24);
}

// gear 1: gear + detent flange (with 4 notches) + crank peg. Centre origin.
module gear1() {
    difference() {
        union() {
            gear_solid(z1);
            // detent flange (r 11, clear of gear 2) on the gear top,
            // with a 45 deg conical lead-in from the gear OD
            translate([0, 0, gear_h]) cylinder(r = 11, h = 2.5, $fn = 72);
            translate([0, 0, gear_h - 1]) cylinder(r1 = 12, r2 = 11, h = 1, $fn = 72);
            // crank peg at radius 8.5, at 45 deg between detent slots,
            // clear of the pin cap (radius 5) by 0.9
            translate([6, 6, gear_h]) cylinder(r = 2.6, h = 11.5, $fn = 36);
        }
        translate([0, 0, -1]) cylinder(r = bore_r, h = 20, $fn = 48);
        // four radial detent slots through the full flange height:
        // the base bump clicks in every quarter turn
        for (a = [0, 90, 180, 270])
            rotate([0, 0, a]) translate([-1.3, -12.3, gear_h - 0.1])
                cube([2.6, 4.5, 2.7]);
    }
}
module gear2() { gear_plain(z2); }
module gear3() { gear_plain(z3); }
module gear4() { gear_plain(z4); }

/* ---------- specification echoes ---------- */
tip1 = r1 + mod; tip2 = r2 + mod; tip3 = r3 + mod; tip4 = r4 + mod;

if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [base_w, base_d, cap1_bot + cap_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["pin cap underside gear1", [[x1 - 5, y_c - 5, cap1_bot - 0.4], [x1 + 5, y_c + 5, cap1_bot + 0.4]]],
            ["pin cap underside gear2", [[x2 - 5, y_c - 5, cap_bot - 0.4], [x2 + 5, y_c + 5, cap_bot + 0.4]]],
            ["pin cap underside gear3", [[x3 - 5, y_c - 5, cap_bot - 0.4], [x3 + 5, y_c + 5, cap_bot + 0.4]]],
            ["pin cap underside gear4", [[x4 - 5, y_c - 5, cap_bot - 0.4], [x4 + 5, y_c + 5, cap_bot + 0.4]]],
            ["detent arm underside", [[x1 - 2, 13.5, 9.0], [x1 + 2, 20, 9.8]]]
        ]],
        ["copies", 1],
        ["details", [
            ["base_plate", "material", [[10, 10, 0.5], [90, 50, 2.5]], 0.95],
            ["plate_thickness", "thickness", [50, 20, -2], [0, 0, 1], 3],
            ["pin_gear2", "material", [[x2 - 1.5, y_c - 1.5, 4], [x2 + 1.5, y_c + 1.5, 8]], 0.7],
            ["cap_gear2", "material", [[x2 - 2, y_c - 2, cap_bot + 0.3], [x2 + 2, y_c + 2, cap_bot + cap_h - 0.3]], 0.9],
            ["detent_leaf", "material", [[x1 - 0.8, 13.2, 4], [x1 + 0.8, 14.6, 8]], 0.4],
            ["detent_arm", "view", [[x1 - 3, 12, 2.5], [x1 + 3, 19.5, 11.5]]],
            ["pin_caps", "view", [[x1 - 6, y_c - 6, 8.5], [x4 + 6, y_c + 6, cap1_bot + cap_h + 0.5]]]
        ]]
    ]);
}
if (part == "gear1") {
    echo(cadverify_spec = [
        ["bounds", [[-tip1, -tip1, 0], [tip1, tip1, gear_h + 11.5]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 150]]],
        ["overhangs_allowed", [
            ["detent flange cone underside", [[-12.5, -12.5, 3.8], [12.5, 12.5, 5.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["bore", "hole", [0, 0, -2], [0, 0, 1], [[0, 6.8], [4, 6.8]]],
            ["gear_web", "thickness", [5, -5, -2], [0, 0, 1], 7.5],
            ["tooth_east", "material", [[r1 - 1, -1, 1], [tip1 - 0.2, 1, 4]], 0.45],
            ["detent_flange", "material", [[3, 3, 6.5], [7, 7, 7.2]], 0.9],
            ["detent_notch_south", "void", [[-1.4, -11.3, 5.2], [1.4, -8.2, 7.3]], 0.5],
            ["crank_peg", "material", [[5, 5, 10], [7, 7, 15.5]], 0.9],
            ["crank", "view", [[3, 3, 4.5], [9.5, 9.5, gear_h + 11.5]]],
            ["teeth", "view", [[tip1 - 8, -tip1, 0], [tip1, tip1, gear_h]]]
        ]]
    ]);
}
if (part == "gear2") {
    echo(cadverify_spec = [
        ["bounds", [[-tip2, -tip2, 0], [tip2, tip2, gear_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 100]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bore", "hole", [0, 0, -2], [0, 0, 1], [[0, 6.8], [4, 6.8]]],
            ["gear_web", "thickness", [0, 7, -2], [0, 0, 1], 5],
            ["tooth_east", "material", [[r2 - 1, -1, 1], [tip2 - 0.2, 1, 4]], 0.45],
            ["teeth", "view", [[tip2 - 7, -tip2, 0], [tip2, tip2, gear_h]]]
        ]]
    ]);
}
if (part == "gear3") {
    echo(cadverify_spec = [
        ["bounds", [[-tip3, -tip3, 0], [tip3, tip3, gear_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 150]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bore", "hole", [0, 0, -2], [0, 0, 1], [[0, 6.8], [4, 6.8]]],
            ["gear_web", "thickness", [0, 8, -2], [0, 0, 1], 5],
            ["tooth_east", "material", [[r3 - 1, -1, 1], [tip3 - 0.2, 1, 4]], 0.45],
            ["teeth", "view", [[tip3 - 7, -tip3, 0], [tip3, tip3, gear_h]]]
        ]]
    ]);
}
if (part == "gear4") {
    echo(cadverify_spec = [
        ["bounds", [[-9.0, -8.619, 0], [9.0, 8.619, gear_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 60]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bore", "hole", [0, 0, -2], [0, 0, 1], [[0, 6.8], [4, 6.8]]],
            ["gear_web", "thickness", [0, 5.5, -2], [0, 0, 1], 5],
            ["tooth_east", "material", [[r4 - 1, -1, 1], [tip4 - 0.2, 1, 4]], 0.45],
            ["teeth", "view", [[tip4 - 7, -tip4, 0], [tip4, tip4, gear_h]]]
        ]]
    ]);
}
if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [base_w, base_d, gear_z + gear_h + 11.5]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["crank_turn", ["gear1"], "rotate", [x1, y_c, 0], [0, 0, 1], [0, 360],
                ["drives", [
                    [["gear2"], "rotate", [x2, y_c, 0], [0, 0, 1], -z1 / z2],
                    [["gear3"], "rotate", [x3, y_c, 0], [0, 0, 1], z1 / z3],
                    [["gear4"], "rotate", [x4, y_c, 0], [0, 0, 1], -z1 / z4]
                ]],
                ["flex", [["gear1", "base", 0.9,
                    "detent bump on the flexible base leaf rides over the gear-1 flange between its quarter-turn notches"]]],
                ["rests", [0, 90, 180, 270, 360]]]
        ]],
        ["assembly_order", [
            [["base", "gear1", "gear2", "gear3", "gear4"], [0, 0, 0]]
        ]],
        ["print_in_place", 0.2],
        ["overhangs_allowed", [
            ["gear1 detent flange cone underside", [[x1 - 13, y_c - 13, 7.2], [x1 + 13, y_c + 13, 8.8]]],
            ["gear1 underside 0.6 above the plate", [[x1 - tip1, y_c - tip1, gear_z - 0.4], [x1 + tip1, y_c + tip1, gear_z + 0.4]]],
            ["gear2 underside 0.6 above the plate", [[x2 - tip2, y_c - tip2, gear_z - 0.4], [x2 + tip2, y_c + tip2, gear_z + 0.4]]],
            ["gear3 underside 0.6 above the plate", [[x3 - tip3, y_c - tip3, gear_z - 0.4], [x3 + tip3, y_c + tip3, gear_z + 0.4]]],
            ["gear4 underside 0.6 above the plate", [[x4 - tip4, y_c - tip4, gear_z - 0.4], [x4 + tip4, y_c + tip4, gear_z + 0.4]]],
            ["pin cap underside gear1", [[x1 - 5, y_c - 5, cap1_bot - 0.4], [x1 + 5, y_c + 5, cap1_bot + 0.4]]],
            ["pin cap underside gear2", [[x2 - 5, y_c - 5, cap_bot - 0.4], [x2 + 5, y_c + 5, cap_bot + 0.4]]],
            ["pin cap underside gear3", [[x3 - 5, y_c - 5, cap_bot - 0.4], [x3 + 5, y_c + 5, cap_bot + 0.4]]],
            ["pin cap underside gear4", [[x4 - 5, y_c - 5, cap_bot - 0.4], [x4 + 5, y_c + 5, cap_bot + 0.4]]],
            ["detent arm underside", [[x1 - 2, 13.5, 9.0], [x1 + 2, 20, 9.8]]]
        ]],
        ["held", ["gear1", "gear2", "gear3", "gear4"]]
    ]);
}

/* ---------- output ---------- */
if (part == "base") base();
else if (part == "gear1") gear1();
else if (part == "gear2") gear2();
else if (part == "gear3") gear3();
else if (part == "gear4") gear4();
else if (part == "assembly") {
    instance("base", "base") base();
    instance("gear1", "gear1") translate([x1, y_c, gear_z]) gear1();
    instance("gear2", "gear2") translate([x2, y_c, gear_z]) rotate([0, 0, 180 - 180 / z2]) gear2();
    instance("gear3", "gear3") translate([x3, y_c, gear_z]) gear3();
    instance("gear4", "gear4") translate([x4, y_c, gear_z]) rotate([0, 0, 180 - 180 / z4]) gear4();
}
