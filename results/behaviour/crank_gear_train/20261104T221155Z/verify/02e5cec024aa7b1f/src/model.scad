// Crank gear train, printed in place. PLA, Bambu Lab A1, 0.4 mm nozzle.
// Four meshing spur gears on capped fixed pins, on a 100 x 60 mm base.
// Gear 1 carries a crank peg (base on flange top, 0.2 over the detent)
// and a 4-notch detent flange; a diagonal leaf on the base clicks
// into the flange notches every quarter turn (2-10 N at the bump).
//
// Print-in-place clearances used throughout (mm):
//   gear bore / pin        0.4 radial
//   gear underside / plate 0.6 vertical
//   cap underside / gear   0.6 vertical (1.3 over gear1 flange)
//   crank peg bottom / detent top 0.2 vertical
//   detent finger / gear tip 0.8 vertical
//   gear mesh              extra centre distance 0.4 + tooth thinning 0.4
part = "assembly"; // ["assembly", "base", "gear1", "gear2", "gear3", "gear4", "test_detent"]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* [Detent tuning] */
detent_t = 1.68;     // leaf thickness across (mm, 4 lines) - soften: 1.26
detent_b = 5.04;     // leaf width along x (mm, 12 lines) - stiffen: 6.30
detent_o = 0.4;      // bump centre offset outside flange rim (mm)
detent_run = 8;      // leaf plan run, base to finger (mm)

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
cap1_bot = gear_z + gear_h + 3.2 + 0.6;    // gear1 flange top + 1.3 = 12.4
cap_bot  = gear_z + gear_h + 0.6;          // plain gears: 9.2

// detent geometry, shared by base and test coupon (formulas of detent_*)
flange_r = 11;
bump_r = 0.65;
bump_y = y_c - flange_r - detent_o;        // 18.6: 0.4 outside rim
finger_y0 = bump_y - 4.5;                  // 14.1: finger south face
finger_z0 = 9.4; finger_z1 = 10.9;         // flange height
leaf_base_y = finger_y0 - detent_run;      // 6.1
leaf_base_z = 2.5;                          // 0.5 embedded in plate
leaf_top_y = finger_y0 + 0.9;              // embedded in finger
leaf_top_z = 10.2;                          // mid finger
leaf_run = leaf_top_y - leaf_base_y;
leaf_rise = leaf_top_z - leaf_base_z;
leaf_L = sqrt(leaf_run*leaf_run + leaf_rise*leaf_rise);
leaf_ang = atan(leaf_run/leaf_rise);

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
    // Detent: diagonal leaf from the plate up-north to a short horizontal
    // finger at flange height; the finger carries the bump. The leaf bends
    // in-plane, the root has a fillet. Finger underside 0.8 above the gear,
    // 4.5 long (bridge).
    translate([x1, leaf_base_y, leaf_base_z]) rotate([-leaf_ang, 0, 0])
        translate([-detent_b/2, -detent_t/2, 0]) cube([detent_b, detent_t, leaf_L]);
    // root fillet along x
    translate([x1 - detent_b/2, leaf_base_y + 0.3, 3.0]) rotate([0, 90, 0])
        cylinder(r = 1.5, h = detent_b, $fn = 24);
    // finger at flange height, from outside the gear tip to the rim
    translate([x1 - detent_b/2, finger_y0, finger_z0])
        cube([detent_b, 4.5, finger_z1 - finger_z0]);
    // bump: knob centred on the finger tip face (half in the finger),
    // tip 0.25 inside the flange rim, 0.2 below the crank peg
    translate([x1, bump_y, finger_z0]) cylinder(r = bump_r, h = finger_z1 - finger_z0, $fn = 24);
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
            // crank peg at radius 8.5, at 45 deg between detent slots;
            // base sits on the flange top (0.2 over the detent), same
            // handle size as before, with a small base fillet
            translate([6, 6, 7.5]) cylinder(r = 2.6, h = 11.5, $fn = 36);
            translate([6, 6, 7.5]) cylinder(r1 = 3.2, r2 = 2.6, h = 1, $fn = 36);
        }
        translate([0, 0, -1]) cylinder(r = bore_r, h = 22, $fn = 48);
        // four radial detent slots through the full flange height:
        // the base bump clicks in every quarter turn
        for (a = [0, 90, 180, 270])
            rotate([0, 0, a]) translate([-1.3, -11.8, gear_h - 0.1])
                cube([2.6, 4, 2.7]);
    }
}
module gear2() { gear_plain(z2); }
module gear3() { gear_plain(z3); }
module gear4() { gear_plain(z4); }

// test coupon for the click: same leaf/finger/bump on a small chip
module test_detent() {
    cube([30, 25, 3]);
    translate([15, leaf_base_y, leaf_base_z]) rotate([-leaf_ang, 0, 0])
        translate([-detent_b/2, -detent_t/2, 0]) cube([detent_b, detent_t, leaf_L]);
    translate([15 - detent_b/2, leaf_base_y + 0.3, 3.0]) rotate([0, 90, 0])
        cylinder(r = 1.5, h = detent_b, $fn = 24);
    translate([15 - detent_b/2, finger_y0, finger_z0]) cube([detent_b, 4.5, finger_z1 - finger_z0]);
    translate([15, bump_y, finger_z0]) cylinder(r = bump_r, h = finger_z1 - finger_z0, $fn = 24);
}

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
            ["detent finger underside 4.5 bridge", [[x1 - detent_b/2 - 0.5, finger_y0 - 0.2, 9.0], [x1 + detent_b/2 + 0.5, bump_y + 0.7, 9.8]]],
            ["detent leaf underside 49deg", [[x1 - detent_b/2 - 0.5, 5.5, 2.0], [x1 + detent_b/2 + 0.5, finger_y0 + 1.0, 10.5]]]
        ]],
        ["copies", 1],
        ["material", "PLA"],
        ["details", [
            ["base_plate", "material", [[10, 10, 0.5], [90, 50, 2.5]], 0.95],
            ["plate_thickness", "thickness", [50, 20, -2], [0, 0, 1], 3],
            ["pin_gear2", "material", [[x2 - 1.5, y_c - 1.5, 4], [x2 + 1.5, y_c + 1.5, 8]], 0.7],
            ["cap_gear2", "material", [[x2 - 2, y_c - 2, cap_bot + 0.3], [x2 + 2, y_c + 2, cap_bot + cap_h - 0.3]], 0.9],
            ["detent_leaf", "material", [[x1 - 2.0, 9.5, 5.5], [x1 + 2.0, 11.5, 7.5]], 0.4],
            ["detent_leaf_thickness", "thickness", [x1, 12.41, 4.20], [0, -0.654, 0.756], 1.68],
            ["detent_bump", "material", [[x1 - 0.5, bump_y - 0.5, 9.6], [x1 + 0.5, bump_y + 0.5, 10.7]], 0.5],
            ["detent_finger", "view", [[x1 - 3, finger_y0 - 0.5, 9.0], [x1 + 3, bump_y + 0.7, 11.2]]],
            ["pin_caps", "view", [[x1 - 6, y_c - 6, 8.5], [x4 + 6, y_c + 6, cap1_bot + cap_h + 0.5]]]
        ]]
    ]);
}
if (part == "gear1") {
    echo(cadverify_spec = [
        ["bounds", [[-tip1, -tip1, 0], [tip1, tip1, 19.0]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 150]]],
        ["overhangs_allowed", [
            ["detent flange cone underside", [[-12.5, -12.5, 3.8], [12.5, 12.5, 5.2]]],
            ["crank peg base fillet lip", [[2.5, 2.5, 7.1], [9.5, 9.5, 8.6]]]
        ]],
        ["copies", 1],
        ["material", "PLA"],
        ["details", [
            ["bore", "hole", [0, 0, -2], [0, 0, 1], [[0, 6.8], [4, 6.8]]],
            ["gear_web", "thickness", [5, -5, -2], [0, 0, 1], 7.5],
            ["tooth_east", "material", [[r1 - 1, -1, 1], [tip1 - 0.2, 1, 4]], 0.45],
            ["detent_flange", "material", [[3, 3, 6.5], [7, 7, 7.2]], 0.9],
            ["detent_notch_south", "void", [[-1.4, -11.3, 5.2], [1.4, -8.2, 7.3]], 0.5],
            ["crank_peg", "material", [[5, 5, 10], [7, 7, 15.5]], 0.9],
            ["crank", "view", [[3, 3, 7.0], [9.5, 9.5, 19.0]]],
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
        ["material", "PLA"],
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
        ["material", "PLA"],
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
        ["bounds", [[-9.0, -8.619, 0], [9.0, 8.619, 0 + gear_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 60]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["material", "PLA"],
        ["details", [
            ["bore", "hole", [0, 0, -2], [0, 0, 1], [[0, 6.8], [4, 6.8]]],
            ["gear_web", "thickness", [0, 5.5, -2], [0, 0, 1], 5],
            ["tooth_east", "material", [[r4 - 1, -1, 1], [tip4 - 0.2, 1, 4]], 0.45],
            ["teeth", "view", [[tip4 - 7, -tip4, 0], [tip4, tip4, gear_h]]]
        ]]
    ]);
}
if (part == "test_detent") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [30, 25, 10.9]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 500]]],
        ["overhangs_allowed", [
            ["finger underside 4.5 bridge", [[12, 15.8, 9.0], [18, 21.2, 9.8]]],
            ["leaf underside 49deg", [[12, 3.5, 2.0], [18, 17, 10.5]]]
        ]],
        ["copies", 1],
        ["material", "PLA"],
        ["loads", [["click_push", [[14.35, 20.5, 9.4], [15.65, 21.15, 10.9]], [0, -2.5, 0],
                    [[0, 0, 0], [30, 5, 3]], 1.0]]],
        ["tune", [["test click too stiff, thin the leaf", "detent_t", 1.26, "load click_push"]]],
        ["probe_of", "flex gear1/base"],
        ["details", [
            ["chip_base", "material", [[5, 5, 0.5], [25, 20, 2.5]], 0.9],
            ["chip_thickness", "thickness", [15, 10, -2], [0, 0, 1], 3],
            ["test_leaf", "material", [[13, 9.5, 5.5], [17, 11.5, 7.5]], 0.4],
            ["test_leaf_thickness", "thickness", [15, 12.31, 4.2], [0, -0.654, 0.756], 1.68],
            ["test_finger", "view", [[12, 15.5, 9.0], [18, 21.5, 11.0]]]
        ]]
    ]);
}
if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [base_w, base_d, gear_z + 19.0]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["crank_turn", ["gear1"], "rotate", [x1, y_c, 0], [0, 0, 1], [0, 360],
                ["drives", [
                    [["gear2"], "rotate", [x2, y_c, 0], [0, 0, 1], -z1 / z2],
                    [["gear3"], "rotate", [x3, y_c, 0], [0, 0, 1], z1 / z3],
                    [["gear4"], "rotate", [x4, y_c, 0], [0, 0, 1], -z1 / z4]
                ]],
                ["flex", [["gear1", "base", 0.5,
                    "detent bump on the diagonal base leaf rides over the gear-1 flange between its quarter-turn notches", [2, 10]]]],
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
            ["detent finger underside 4.5 bridge", [[x1 - detent_b/2 - 0.5, finger_y0 - 0.2, 9.0], [x1 + detent_b/2 + 0.5, bump_y + 0.7, 9.8]]],
            ["detent leaf underside 49deg", [[x1 - detent_b/2 - 0.5, 5.5, 2.0], [x1 + detent_b/2 + 0.5, finger_y0 + 1.0, 10.5]]]
        ]],
        ["held", ["gear1", "gear2", "gear3", "gear4"]],
        ["material", "PLA"],
        ["tune", [
            ["click too stiff, thin the leaf", "detent_t", 1.26, "flex gear1/base"],
            ["click too soft, widen the leaf", "detent_b", 6.3, "flex gear1/base"]
        ]]
    ]);
}

/* ---------- output ---------- */
if (part == "base") base();
else if (part == "gear1") gear1();
else if (part == "gear2") gear2();
else if (part == "gear3") gear3();
else if (part == "gear4") gear4();
else if (part == "test_detent") test_detent();
else if (part == "assembly") {
    instance("base", "base") base();
    instance("gear1", "gear1") translate([x1, y_c, gear_z]) gear1();
    instance("gear2", "gear2") translate([x2, y_c, gear_z]) rotate([0, 0, 180 - 180 / z2]) gear2();
    instance("gear3", "gear3") translate([x3, y_c, gear_z]) gear3();
    instance("gear4", "gear4") translate([x4, y_c, gear_z]) rotate([0, 0, 180 - 180 / z4]) gear4();
}
