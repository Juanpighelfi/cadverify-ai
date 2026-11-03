// Planetary gear set, printed in place (straight spur involute teeth).
// Design intent / measurable spec:
//  - Overall assembly: 60 mm diameter x 10 mm thick.
//  - Sun 15T, three planets 15T, ring 45T internal, module 1.1 mm, 20 deg PA.
//    Stub teeth (0.8m addendum, 1.15m dedendum) for a printable tip width.
//    Each tooth thinned by 0.28 mm of pitch arc -> ~0.26 mm normal flank
//    clearance between meshing gears, 0.385 mm tip-to-root clearance,
//    0.4 mm axial clearances: no PLA fusion on a 0.4 mm nozzle (A1).
//  - Captivity without supports: planets carry top/bottom flange discs
//    (r 8.85) axially outside the 1.6..8.4 mm gear band. The flanges overlap
//    the ring band and the sun tooth tips in plan, so the sun cannot pass
//    the planet flanges, the planets cannot pass the ring band, and the
//    ring cannot pass the planet flanges. All parts still rest flat on
//    the bed and no face needs support (declared undersides are short
//    bridges over material of the same / neighbouring part).
//  - Sun has a through hex hole, 6.7 mm across flats (for a 1/4 in /
//    6.35 mm bit, with printed-hole clearance), through a r6 hub.

part = "assembly"; // [assembly, sun, planet, ring]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* [Gear parameters] */
module_m   = 1.1;          // gear module (mm)
n_sun      = 15;
n_planet   = 15;
n_ring     = 45;           // = n_sun + 2*n_planet
pressure_deg = 20;
thin       = 0.28;         // tooth thinning, pitch arc (mm) -> backlash
add_k      = 0.8;          // addendum = add_k * module
ded_k      = 1.15;         // dedendum = ded_k * module

rp_sun    = module_m * n_sun / 2;        // 8.25
rp_planet = module_m * n_planet / 2;     // 8.25
rp_ring   = module_m * n_ring / 2;       // 24.75
tip_ext   = rp_sun + add_k * module_m;   // 9.13
root_ext  = rp_sun - ded_k * module_m;   // 6.985
tip_ring  = rp_ring - add_k * module_m;  // 23.87 (innermost)
root_ring = rp_ring + ded_k * module_m;  // 26.015
center_d  = rp_sun + rp_planet;          // 16.5

gear_z0 = 1.6;
gear_z1 = 8.4;
total_h = 10;
ring_r  = 30;
bore_r  = 26.02;
hub_r   = 6.0;
planet_core_r = 5.5;
flange_r = 8.85;
flange_t = 1.2;
neck_z   = 0.4;            // axial gap gear band -> flange (1.2..1.6)
hex_af   = 6.7;            // across flats
hex_r    = hex_af / (2 * cos(30));       // 3.868 circumradius

tooth_arc = PI * module_m - thin;        // not used for thickness below
s_ext  = PI * module_m / 1 - thin;       // tooth arc thickness at pitch... see below
// tooth thickness arc at pitch circle:
s_tooth = PI * module_m - thin;          // placeholder, corrected in profile fn

/* Involute helpers (angles in radians returned for half tooth angle) */
function inv_of(r, rb) =
    let(a = acos(min(1, rb / r))) (tan(a) - a * PI / 180);
function half_ext(r, rp, rb, s) =
    let(rr = max(r, rb))
    s / (2 * rp) + inv_of(rp, rb) - inv_of(rr, rb);
function half_int(r, rp, rb, s) =
    s / (2 * rp) - inv_of(rp, rb) + inv_of(r, rb);
function pol(r, a_deg) = [r * cos(a_deg), r * sin(a_deg)];

// External gear outline. s = tooth thickness arc at pitch (mm).
function ext_points(n, rp, tip, root, s, phase) =
    let(rb = rp * cos(pressure_deg),
        hb = half_ext(root, rp, rb, s) * 180 / PI,
        steps = [0, 0.33, 0.66, 1])
    [for (i = [0 : n - 1])
        let(a = phase + i * 360 / n)
        for (p = concat(
            [pol(root, a - hb)],
            [for (t = steps)
                let(r = rb + (tip - rb) * t,
                    h = half_ext(r, rp, rb, s) * 180 / PI)
                pol(r, a - h)],
            [pol(tip, a)],
            [for (t = [1, 0.66, 0.33, 0])
                let(r = rb + (tip - rb) * t,
                    h = half_ext(r, rp, rb, s) * 180 / PI)
                pol(r, a + h)],
            [pol(root, a + hb), pol(root, a + 180 / n)]
        )) p];

// Internal (ring) gear void outline: teeth point inwards.
// Tooth centres are offset by half a pitch so a gap faces +x.
function int_points(n, rp, tip, root, s, phase) =
    let(rb = rp * cos(pressure_deg),
        steps = [0, 0.33, 0.66, 1])
    [for (i = [0 : n - 1])
        let(a = phase + i * 360 / n,
            hr = half_int(root, rp, rb, s) * 180 / PI)
        for (p = concat(
            [pol(root, a - hr)],
            [for (t = steps)
                let(r = root + (tip - root) * t,
                    h = half_int(r, rp, rb, s) * 180 / PI)
                pol(r, a - h)],
            [pol(tip, a)],
            [for (t = [1, 0.66, 0.33, 0])
                let(r = root + (tip - root) * t,
                    h = half_int(r, rp, rb, s) * 180 / PI)
                pol(r, a + h)],
            [pol(root, a + hr), pol(root, a + 180 / n)]
        )) p];

module gear_ext_2d(n, rp, tip, root) {
    // tooth thickness at pitch: half the circular pitch, thinned
    s = PI * module_m - thin * 0 + (PI * module_m / 2 - thin) - PI * module_m / 2;
    // (written out: s = PI*module_m/2 - thin)
    polygon(points = ext_points(n, rp, tip, root, PI * module_m / 2 - thin, 0));
}

module sun_part() {
    difference() {
        union() {
            cylinder(h = total_h, r = hub_r, $fn = 96);
            translate([0, 0, gear_z0])
                linear_extrude(height = gear_z1 - gear_z0)
                    gear_ext_2d(n_sun, rp_sun, tip_ext, root_ext);
        }
        translate([0, 0, -1])
            cylinder(h = total_h + 2, r = hex_r, $fn = 6);
    }
}

module planet_part() {
    union() {
        cylinder(h = total_h, r = planet_core_r, $fn = 72);
        cylinder(h = flange_t, r = flange_r, $fn = 96);
        translate([0, 0, total_h - flange_t])
            cylinder(h = flange_t, r = flange_r, $fn = 96);
        translate([0, 0, gear_z0])
            linear_extrude(height = gear_z1 - gear_z0)
                gear_ext_2d(n_planet, rp_planet, tip_ext, root_ext);
    }
}

module ring_part() {
    difference() {
        cylinder(h = total_h, r = ring_r, $fn = 180);
        // smooth bore in the flange bands (below / above the gear band)
        translate([0, 0, -0.5])
            cylinder(h = gear_z0 + 0.55, r = bore_r, $fn = 180);
        translate([0, 0, gear_z1 - 0.05])
            cylinder(h = total_h - gear_z1 + 0.55, r = bore_r, $fn = 180);
        // internal teeth, middle band
        translate([0, 0, gear_z0 - 0.05])
            linear_extrude(height = gear_z1 - gear_z0 + 0.1)
                polygon(points = int_points(n_ring, rp_ring, tip_ring, root_ring,
                                             PI * module_m / 2 - thin,
                                             180 / n_ring));
    }
}

/* ---------------- Verified specification (per exported part) ---------------- */
if (part == "sun") {
    echo(cadverify_spec = [
        ["bounds", [[-tip_ext, -tip_ext, 0], [tip_ext, tip_ext, total_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bottom", "-z", 60]]],
        ["overhangs_allowed", [
            ["gear underside over hub, teeth tips within 3.2 mm of hub in plan",
             [[-tip_ext, -tip_ext, gear_z0 - 0.1], [tip_ext, tip_ext, gear_z0 + 0.1]]]
        ]],
        ["copies", 1],
        ["details", [
            ["hub", "material", [[-5, -5, 0.2], [5, 5, 9.8]], 0.40],
            ["hex_void", "void", [[-2.3, -2.3, 0], [2.3, 2.3, 10]], 1.0],
            ["hex_hole", "hole", [0, 0, 12], [0, 0, -1], [[0, 7.04], [5, 7.04], [9.9, 7.04]]],
            ["gear_tooth", "material", [[5.5, -1, 1.6], [9.13, 1, 8.4]], 0.18],
            ["teeth_view", "view", [[5, -5, 1.6], [9.2, 5, 8.4]]]
        ]]
    ]);
} else if (part == "planet") {
    echo(cadverify_spec = [
        ["bounds", [[-tip_ext, -tip_ext, 0], [tip_ext, tip_ext, total_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bottom", "-z", 200]]],
        ["overhangs_allowed", [
            ["gear underside over bottom flange in plan",
             [[-tip_ext, -tip_ext, gear_z0 - 0.1], [tip_ext, tip_ext, gear_z0 + 0.1]]],
            ["top flange underside over gear band in plan",
             [[-flange_r, -flange_r, total_h - flange_t - 0.1],
              [flange_r, flange_r, total_h - flange_t + 0.1]]]
        ]],
        ["copies", 3],
        ["details", [
            ["bottom_flange", "material", [[-8, -8, 0], [8, 8, 1.2]], 0.60],
            ["top_flange", "material", [[-8, -8, 8.8], [8, 8, 10]], 0.60],
            ["core", "material", [[-4, -4, 0], [4, 4, 10]], 0.55],
            ["gear_tooth", "material", [[5.5, -1, 1.6], [9.13, 1, 8.4]], 0.18],
            ["teeth_view", "view", [[5, -5, 1.6], [9.2, 5, 8.4]]]
        ]]
    ]);
} else if (part == "ring") {
    echo(cadverify_spec = [
        ["bounds", [[-ring_r, -ring_r, 0], [ring_r, ring_r, total_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bottom", "-z", 600]]],
        ["overhangs_allowed", [
            ["internal tooth undersides, 2.2 mm long from root in plan",
             [[-ring_r, -ring_r, gear_z0 - 0.1], [ring_r, ring_r, gear_z0 + 0.1]]]
        ]],
        ["copies", 1],
        ["details", [
            ["rim", "material", [[26, -4, 0], [30, 4, 10]], 0.70],
            ["bore", "void", [[-16, -16, 0], [16, 16, 10]], 1.0],
            ["rim_wall", "thickness", [35, 0, 5], [-1, 0, 0], 3.98],
            ["teeth_view", "view", [[23, -7, 1.6], [30, 7, 8.4]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-ring_r, -ring_r, 0], [ring_r, ring_r, total_h]]],
        ["support_faces", [["bed", "-z", 1000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["sun_turning",
             ["planet_1", "planet_2", "planet_3"], "rotate",
             [0, 0, 0], [0, 0, 1], [0, 90],
             ["drives", [
                 [["sun_gear"], "rotate", [0, 0, 0], [0, 0, 1], 4],
                 [["planet_1"], "rotate", [16.5, 0, 5], [0, 0, 1], -3],
                 [["planet_2"], "rotate", [-8.25, 14.2885, 5], [0, 0, 1], -3],
                 [["planet_3"], "rotate", [-8.25, -14.2885, 5], [0, 0, 1], -3]
             ]]]
        ]],
        ["assembly_order", [
            [["ring_gear"], [0, 0, 0]],
            [["planet_1"], [0, 0, 25]],
            [["planet_2"], [0, 0, 25]],
            [["planet_3"], [0, 0, 25]],
            [["sun_gear"], [0, 0, 25]]
        ]],
        ["overhangs_allowed", [
            ["gear band undersides bridge at most 6.3 mm over material below in plan",
             [[-26, -26, 1.5], [26, 26, 1.75]]],
            ["planet top flange undersides bridge 2.4 mm",
             [[-26, -26, 8.7], [26, 26, 8.9]]]
        ]],
        ["print_in_place", 0.22]
    ]);
}

/* ---------------- Output ---------------- */
if (part == "sun") {
    sun_part();
} else if (part == "planet") {
    planet_part();
} else if (part == "ring") {
    ring_part();
} else if (part == "assembly") {
    instance("ring_gear", "ring") ring_part();
    instance("sun_gear", "sun") sun_part();
    instance("planet_1", "planet")
        translate([center_d, 0, 0]) planet_part();
    instance("planet_2", "planet")
        rotate([0, 0, 120]) translate([center_d, 0, 0]) planet_part();
    instance("planet_3", "planet")
        rotate([0, 0, 240]) translate([center_d, 0, 0]) planet_part();
} else {
    assert(false, str("unknown part: ", part));
}
