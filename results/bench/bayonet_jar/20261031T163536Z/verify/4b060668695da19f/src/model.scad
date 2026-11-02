// Desk jar with bayonet lid - PETG, Bambu Lab A1, 0.4 nozzle, no supports
// Dimensions in mm.

/* [Part] */
part = "assembly"; // ["jar", "lid", "assembly"]

/* [Dimensions] */
inner_r = 35;          // 70 mm main cavity across
inner_depth = 80;      // cavity depth
floor_t = 2.4;         // >= 1.6
body_r = 38.5;         // jar outside radius (77 mm across)
neck_r = 35.6;         // bayonet neck outside radius
neck_inner_r = 33;     // neck opening radius (66 mm clear opening)
neck_start = 67.4;     // z where body steps to neck
rim_z = 82.4;          // floor_t + inner_depth = 2.4 + 80
slot_z = 73.4;         // bayonet horizontal slot centre height
slot_w = 3.6;          // axial slot width
slot_floor_r = 34.2;   // groove floor radius (1.4 deep groove, 1.2 wall behind it)

lid_r = 38.5;          // flush with body_r
lid_inner_r = 36.1;    // 0.5 radial clearance over neck_r
lid_h = 16.8;          // lid height in print orientation
lid_top_t = 2.4;
lug_tip_r = 34.7;      // 0.5 clearance to slot_floor_r
lug_z_print = 12.0;    // lug centre in lid print coords

$fn = 96;

function arc2(cx, cy, r, a0, a1, n = 8) =
    [for (i = [0:n]) let (a = a0 + (a1 - a0) * i / n) [cx + r * cos(a), cy + r * sin(a)]];
// arc continuing from the previous profile point (no duplicate first point)
function arc2b(cx, cy, r, a0, a1, n = 8) =
    [for (i = [1:n]) let (a = a0 + (a1 - a0) * i / n) [cx + r * cos(a), cy + r * sin(a)]];

// ---------- Jar ----------
module jar_geo() {
    prof = concat(
        [[0, 0], [36.5, 0], [38.5, 2]],                    // base + 45deg bed chamfer
        [[38.5, 65.4]],
        arc2b(36.5, 65.4, 2, 0, 90),                       // shoulder outer fillet -> (36.5,67.4)
        [[37.6, 67.4]],
        arc2b(37.6, 69.4, 2, 270, 180),                    // shoulder/neck concave fillet -> (35.6,69.4)
        [[35.6, 80.9]],
        arc2b(34.1, 80.9, 1.5, 0, 90),                     // rim outer fillet -> (34.1,82.4)
        arc2b(34.1, 80.9, 1.5, 90, 180),                   // rim inner fillet -> (32.6,80.9)
        [[32.6, 72], [35, 69.6]],                         // 45deg inner neck expansion
        [[35, 5.4]],
        arc2b(32, 5.4, 3, 0, -90),                         // inner floor fillet -> (32,2.4)
        [[0, 2.4]]
    );
    difference() {
        rotate_extrude() polygon(prof);
        // bayonet L-slots: vertical entry + horizontal quarter-turn groove, x3
        for (k = [0, 120, 240]) rotate([0, 0, k]) {
            // horizontal annular-sector groove, -6 .. 96 deg
            translate([0, 0, slot_z - slot_w / 2])
                linear_extrude(height = slot_w)
                    polygon(concat(
                        arc2(0, 0, 37.5, -6, 96, 28),
                        arc2(0, 0, slot_floor_r, 96, -6, 28)));
            // vertical entry, open at rim
            translate([34.5, 0, 78]) cube([6, 7.4, 12], center = true);
        }
    }
    // detent bumps on groove floors, near locked end (81 deg in each slot):
    // flattened spheres protruding 0.6 mm inward, embedded 1.2 mm into the wall
    for (k = [0, 120, 240]) rotate([0, 0, k + 89])
        translate([34.6, 0, slot_z]) scale([0.4, 1, 1]) sphere(r = 1.5, $fn = 32);
}

// ---------- Lid (print orientation: closed top face on bed, skirt up) ----------
module lid_geo() {
    prof = concat(
        [[0, 0], [37, 0], [38.5, 1.5]],                    // top face + 45deg bed chamfer
        [[38.5, 15.8]],
        arc2(37.5, 15.8, 1, 0, 90),                        // skirt rim outer fillet -> (37.5,16.8)
        [[36.6, 16.8], [36.1, 16.3]],                     // skirt rim chamfer
        [[36.1, 2.4]],
        [[0, 2.4]]
    );
    difference() {
        rotate_extrude() polygon(prof);
        // shallow vertical grip flutes, within flush outer radius
        for (i = [0:47]) rotate([0, 0, i * 7.5])
            translate([38.0, 0, 9.3]) cube([2.0, 1.8, 15.0], center = true);
    }
    // bayonet lugs x3, curved tip, 45deg chamfer on print-down face
    for (k = [0, 120, 240]) rotate([0, 0, k - 4.75])
        rotate_extrude(angle = 9.5)
            polygon([[34.7, 12.3], [34.7, 13.2], [36.3, 13.2], [36.3, 10.8]]);
}

// ---------- Specs ----------
jar_bounds = [[-38.5, -38.5, 0], [38.5, 38.5, 82.4]];
lid_bounds = [[-38.5, -38.5, 0], [38.5, 38.5, 16.8]];

if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", jar_bounds],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bottom", "-z", 3500]]],
        ["overhangs_allowed", [
            ["bayonet groove upper wall: 3.6mm wide groove bridges without support in PETG", [[-37, -37, 71.6], [37, 37, 75.2]]],
            ["45deg shoulder ring at z=67.4 (angle exactly at 45deg print limit, facetted ring of the shoulder/neck fillet)", [[-37.6, -37.6, 67.2], [37.6, 37.6, 67.6]]],
            ["rounded rim underside creases next to the entry slots at z=82.38 (tiny faceting slivers of the rim fillet)", [[-34.5, -34.5, 82.3], [34.5, 34.5, 82.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["body_wall", "thickness", [-50, 0, 40], [1, 0, 0], 3.5],
            ["neck_wall", "thickness", [35.36, 35.36, 78], [-0.707, -0.707, 0], 3.0],
            ["floor", "thickness", [10, 0, -5], [0, 0, 1], 2.4],
            ["cavity", "void", [[-30, -30, 20], [30, 30, 70]], 0.95],
            ["bayonet_slot", "void", [[23.5, 23.5, 72.5], [26.5, 26.5, 74.3]], 0.85],
            ["entry_slot", "void", [[34, -3, 77], [38, 3, 82]], 0.85],
            ["detent_bump", "material", [[-0.9, 33.5, 72.5], [2.1, 35.4, 74.7]], 0.12],
            ["detent_bump_view", "view", [[-3, 31, 70], [4, 37, 77]]],
            ["rim_soft", "view", [[-37, -6, 79], [37, 6, 82.4]]]
        ]]
    ]);
    jar_geo();
}

if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", lid_bounds],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["top_face", "-z", 3500]]],
        ["overhangs_allowed", [
            ["lug print-down 45deg chamfer and small lug underside", [[34, -4, 10], [37, 4, 14]]],
            ["lug print-down 45deg chamfer and small lug underside", [[-22, 26, 10], [-13, 35, 14]]],
            ["lug print-down 45deg chamfer and small lug underside", [[-22, -35, 10], [-13, -26, 14]]]
        ]],
        ["copies", 1],
        ["details", [
            ["skirt_wall", "thickness", [49.9, 3.27, 8], [-0.998, -0.065, 0], 2.4],
            ["top_wall", "thickness", [0, 0, -5], [0, 0, 1], 2.4],
            ["lid_cavity", "void", [[-30, -30, 6], [30, 30, 15]], 0.95],
            ["lug", "material", [[35.2, -2, 11.0], [36.1, 2, 13.1]], 0.8],
            ["lug_view", "view", [[33, -5, 9.5], [37, 5, 14.5]]],
            ["grip_flutes", "view", [[30, -10, 4], [38.5, 10, 15]]]
        ]]
    ]);
    lid_geo();
}

// ---------- Assembly ----------
cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-38.5, -38.5, 0], [38.5, 38.5, 85.4]]],
        ["support_faces", [["desk", "-z", 3500]]],
        ["allowed_interferences", [["lid", "jar", "lug tips press 0.2mm (0.24 measured) against the detent bumps in the locked seat"]]],
        ["motions", [
            ["bayonet_lock_turn", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [0, -90],
                ["flex", [["lid", "jar", 0.7, "PETG skirt/lug flexes radially over 0.6mm detent bump at end of bayonet turn"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["rotate", [0, 0, 0], [0, 0, 1], 90]]
        ]]
    ]);
    instance("jar", "jar") jar_geo();
    // lid print geo flipped to use orientation; rotate z 90 puts lugs at locked angle
    instance("lid", "lid") translate([0, 0, 85.4]) rotate([0, 0, 90]) rotate([180, 0, 0]) lid_geo();
}
