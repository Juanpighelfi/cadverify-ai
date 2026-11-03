// Storage jar with screw-on lid - FDM / PETG, Bambu Lab A1, 0.4 mm nozzle
// Jar printed upright (base on bed). Lid printed top-face on bed, opening up,
// then flipped over in the assembly. Assembly pose = fully closed.

part = "assembly"; // ["jar", "lid", "assembly"]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------------- parameters ---------------- */
inner_r        = 30;     // 60 mm inside diameter
wall_t         = 2.0;    // >= 1.6 mm required
floor_t        = 2.4;    // >= 1.6 mm required
cavity_depth   = 70;     // inside depth, inner floor to rim
rim_z          = floor_t + cavity_depth;   // 72.4

jar_root_r     = inner_r + wall_t;         // 32
jar_crest_r    = jar_root_r + 1.0;         // 33, thread height 1.0

thread_pitch   = 4.0;
thread_turns_jar = 2.0;
jar_thread_zref  = 62.5; // helix centre z at angle 0

lid_inner_r    = jar_crest_r + 0.4;        // 33.4 radial PETG clearance
lid_tip_r      = jar_root_r + 0.4;         // 32.4 radial PETG clearance
lid_wall_t     = 2.0;
lid_outer_r    = lid_inner_r + lid_wall_t; // 35.4
rib_out_r      = 35.9;                     // grip ribs protrude 0.5
lid_top_t      = 2.0;
lid_skirt_len  = 10.4;                     // ceiling face to open edge, in use
lid_h          = lid_top_t + lid_skirt_len;// 12.4 (print height)
// Lid thread in print coords: helix z = 9.9 + pitch*angle/360,
// angle from -540 to 0 deg (1.5 turns).  After the 180 deg flip in the
// assembly this sits at z = 64.5 .. 70.5, exactly half a pitch (2 mm)
// offset from the jar helix at the same angle, so the ridges interleave.
lid_thread_zref = 9.9;

assembly_top_z = rim_z + lid_top_t;        // 74.4, also flip translation

assert(wall_t >= 1.6 && floor_t >= 1.6 && lid_wall_t >= 1.6 && lid_top_t >= 1.6);

/* ---------------- verifiable specs ---------------- */
if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-jar_crest_r, -jar_crest_r, 0], [jar_crest_r, jar_crest_r, rim_z]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bottom", "-z", 3000]]],
        ["overhangs_allowed", [
            ["external thread 45-degree flanks, helical ridge",
             [[-33.5, -33.5, 60.5], [33.5, 33.5, 72.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["interior", "void", [[-20, -20, 5], [20, 20, 70]], 0.99],
            ["external_thread_ridge", "material", [[-33.1, -0.4, 64.1], [-31.9, 0.4, 64.9]], 0.75],
            ["rim_land", "material", [[-0.5, 30.2, 71.0], [0.5, 31.8, 72.3]], 0.95],
            ["floor", "thickness", [0, 0, -5], [0, 0, 1], floor_t],
            ["side_wall", "thickness", [40, 0, 30], [-1, 0, 0], wall_t],
            ["external_thread", "view", [[28, -8, 61], [33.5, 8, 72]]]
        ]]
    ]);
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-rib_out_r, -rib_out_r, 0], [rib_out_r, rib_out_r, lid_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["top_face", "-z", 3500]]],
        ["overhangs_allowed", [
            ["internal thread 45-degree flanks, helical ridge",
             [[-33.5, -33.5, 2.2], [33.5, 33.5, 11.6]]]
        ]],
        ["copies", 1],
        ["details", [
            ["interior", "void", [[-20, -20, 3], [20, 20, 11]], 0.99],
            ["internal_thread_ridge", "material", [[-33.5, -0.4, 7.5], [-32.3, 0.4, 8.3]], 0.70],
            ["grip_rib", "material", [[35.0, -0.8, 4], [36.0, 0.8, 8]], 0.80],
            ["ceiling", "thickness", [0, 0, -5], [0, 0, 1], lid_top_t],
            ["skirt_wall", "thickness", [39.8, 3.49, 6], [-0.996, -0.087, 0], lid_wall_t],
            ["internal_thread", "view", [[24, -10, 3], [33.6, 10, 11.5]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-rib_out_r, -rib_out_r, 0], [rib_out_r, rib_out_r, assembly_top_z]]],
        ["support_faces", [["bed", "-z", 3000]]],
        ["motions", [
            ["lid_screw", ["lid"], "screw", [0, 0, 0], [0, 0, 1], thread_pitch, [0, 540],
                ["stops", [0]]]
        ]],
        ["assembly_order", [
            [["jar"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["screw", [0, 0, 0], [0, 0, 1], thread_pitch, -540]]
        ]],
        ["held", ["lid"]]
    ]);
}

/* ---------------- helical thread ---------------- */
// Profile points are [radius, dz] forming a closed trapezoid, CCW in r-z.
// The ridge crest is tapered radially to the root over the first and last
// half turn, giving a lead-in at both ends.  mode "out": crest beyond root_r;
// mode "in": crest inside root_r (embedded part of the profile is kept).
function tapered_r(r, f, mode, root_r) =
    mode == "out"
        ? (r > root_r ? root_r + (r - root_r) * f : r)
        : (r < root_r ? root_r - (root_r - r) * f : r);

module helical_thread(profile, z_ref, pitch, start_angle, turns, mode, root_r) {
    step_deg = 6;
    n = ceil(abs(turns) * 360 / step_deg);
    p = len(profile);
    pts = [
        for (i = [0 : n])
            let(frac = i / n,
                ang = start_angle + 360 * turns * frac,
                zc = z_ref + pitch * ang / 360,
                d_end = min(frac, 1 - frac) * abs(turns),
                f = min(1, d_end / 0.5))
            for (j = [0 : p - 1])
                let(rr = tapered_r(profile[j][0], f, mode, root_r))
                [rr * cos(ang), rr * sin(ang), zc + profile[j][1]]
    ];
    side = [
        for (i = [0 : n - 1])
            for (j = [0 : p - 1])
                let(j1 = (j + 1) % p,
                    a = i * p + j, b = (i + 1) * p + j,
                    c = (i + 1) * p + j1, d = i * p + j1)
                [a, b, c, d]
    ];
    base = n * p;
    faces = concat(side,
        [[0, 1, 2], [0, 2, 3]],
        [[base + 0, base + 2, base + 1], [base + 0, base + 3, base + 2]]);
    polyhedron(points = pts, faces = faces, convexity = 10);
}

// Jar: embedded root 31.5, crest 33, base half-width 1.5, tip half-width 0.5.
// Flanks move 1.0 radially and 1.0 axially: 45 degrees, support-free.
jar_profile = [[31.5, -1.5], [33.0, -0.5], [33.0, 0.5], [31.5, 1.5]];
// Lid: embedded 33.9, tip 32.4, same widths / 45-degree flanks, CCW in r-z.
lid_profile = [[33.9, -1.5], [33.9, 1.5], [32.4, 0.5], [32.4, -0.5]];

/* ---------------- jar ---------------- */
module jar_part() {
    union() {
        difference() {
            cylinder(h = rim_z, r = jar_root_r, $fn = 180);
            translate([0, 0, floor_t])
                cylinder(h = cavity_depth + 2, r = inner_r, $fn = 180);
        }
        helical_thread(jar_profile, jar_thread_zref, thread_pitch,
                       0, thread_turns_jar, "out", jar_root_r);
    }
}

/* ---------------- lid (print orientation: top on bed, opening up) ------- */
module lid_part() {
    union() {
        difference() {
            cylinder(h = lid_h, r = lid_outer_r, $fn = 180);
            translate([0, 0, lid_top_t])
                cylinder(h = lid_h - lid_top_t + 2, r = lid_inner_r, $fn = 180);
        }
        helical_thread(lid_profile, lid_thread_zref, thread_pitch,
                       -540, 1.5, "in", lid_inner_r);
        // vertical grip ribs around the skirt
        for (i = [0 : 35])
            rotate([0, 0, i * 10])
                translate([35.35, 0, 7.2])
                    cube([1.1, 2.0, 10.4], center = true);
    }
}

/* ---------------- output ---------------- */
if (part == "jar") {
    jar_part();
} else if (part == "lid") {
    lid_part();
} else if (part == "assembly") {
    instance("jar", "jar") jar_part();
    instance("lid", "lid")
        translate([0, 0, assembly_top_z]) rotate([180, 0, 0]) lid_part();
}
