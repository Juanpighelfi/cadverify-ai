/*
Desk jar with bayonet lid - quarter turn, no threads.
Print: PETG, 0.4 nozzle, no supports.
  jar: upright on its floor.
  lid: flat top face on the bed, skirt pointing up (inverted cup).
Assembly (default view): closed, locked jar, lid flush with jar body.
*/

// ---------- selector ----------
part = "assembly"; // [assembly, jar, lid]

// ---------- parameters (mm) ----------
inner_r      = 35;    // chamber radius -> 70 mm inside across
wall         = 3.0;   // jar side wall (>=1.6)
floor_t      = 3.0;   // jar floor (>=1.6)
outer_r      = inner_r + wall;          // 38
inner_depth  = 80;                      // rim to inner floor
rim_z        = floor_t + inner_depth;   // 83
neck_r       = 34;    // reduced neck under the lid skirt
neck_inner_r = 30;    // jar mouth radius (60 mm opening)
shoulder_z0  = 62;    // main body top / shoulder start
shoulder_z1  = 70;    // neck start

// bayonet
n_lugs       = 3;
slot_angles  = [0, 120, 240];
groove_r     = 32.3;  // bottom of bayonet groove in neck
slot_z       = 76;    // horizontal groove bottom (jar/use coords)
slot_h       = 4.0;
slot_cz      = slot_z + slot_h/2;       // 78
entry_half   = 6.5;   // deg, vertical entry half-width
locked_angle = 90;    // deg, entry centre -> locked centre (quarter turn)
lock_extra   = 6.5;   // deg of groove past locked centre
bump_angle   = 82;    // deg, detent bump centre (just before locked)
bump_r       = 31.2;  // sphere centre radius
bump_sphere  = 1.6;   // -> crest at r=32.8, flush with the lug tip radius

// lid (use coords; lid sits over neck, top at lid_top_z)
lid_top_z    = 86.5;
lid_ceiling_z= 83.5;  // 0.5 above jar rim (83)
skirt_inner_r= 34.5;  // 0.5 radial clearance over neck (34)
skirt_bottom_z = 70.5;// 0.5 above shoulder start (70)
lug_tip_r    = 32.8;  // 0.5 clearance to groove bottom (32.3)
lug_z        = 76.5;  // 0.5 clearance top/bottom in 76..80 groove
lug_h        = 3.0;
lug_half     = 4.3;   // deg (~5 mm wide lug)

// clearances summary: skirt/neck 0.5, lug/groove-bottom 0.5,
// lug/slot height 0.5 per side, entry sides ~1.3 mm tangential.

// spec helper coordinates (boxes/rays derived from the parameters above)
rim_axis_y    = 40;   // outside the rim (r=34 max) above the chamber mouth
chamber_axis_y= 95;   // below the floor (bounds z>=0), up the central axis
slot_rib_pt   = [30, 30, slot_cz]; // on the groove diagonal (45deg)
rib1_x = groove_r * cos(slot_angles[0] + locked_angle) - 3;
rib1_y = groove_r * sin(slot_angles[0] + locked_angle) - 3;
rib2_x = groove_r * cos(slot_angles[1] + locked_angle) - 3;
rib2_y = groove_r * sin(slot_angles[1] + locked_angle) - 3;
lug2_x = lug_tip_r * cos(slot_angles[1]) - 3;
lug2_y = lug_tip_r * sin(slot_angles[1]) - 3;
lug3_x = lug_tip_r * cos(slot_angles[2]) - 3;
lug3_y = lug_tip_r * sin(slot_angles[2]) - 3;

// ---------- verifiable spec ----------
cadverify_only = "";
module instance(name, p, unit = 1) {
    echo(cadverify_instance = [name, p, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-outer_r, -outer_r, 0], [outer_r, outer_r, rim_z]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 3000]]],
        ["overhangs_allowed", [
            ["bayonet groove ceilings: short 1.7mm deep horizontal grooves, self-bridging in PETG", [[-outer_r, -outer_r, slot_z], [outer_r, outer_r, slot_z + slot_h + 1]]],
            ["inner shoulder funnel narrowing to the mouth, sloped under 45deg", [[-outer_r, -outer_r, shoulder_z0 - 1], [outer_r, outer_r, shoulder_z1 + 1]]]
        ]],
        ["copies", 1],
        ["details", [
            ["side_wall", "thickness", [outer_r + 12, 0, 40], [-1, 0, 0], wall],
            ["floor", "thickness", [0, 0, -5], [0, 0, 1], floor_t],
            ["min_wall", "thickness", [outer_r + 12, 0, 60], [-1, 0, 0], wall],
            ["chamber_opening", "hole", [0, 0, rim_axis_y], [0, 0, -1], [[0, 70], [1.5, 60], [12, 60], [13.5, 70]]],
            ["chamber", "void", [[-24, -24, 10], [24, 24, 58]], 0.95],
            ["mouth", "void", [[-21, -21, 73], [21, 21, 82]], 0.95],
            ["bayonet_slot", "void", [[21, 21, slot_z + 0.4], [26.5, 26.5, slot_z + slot_h - 0.4]], 0.70],
            ["wall_behind_slot", "thickness", slot_rib_pt, [-0.7071, -0.7071, 0], 2.3],
            ["bump_proud", "thickness", [bump_r * cos(slot_angles[0] + bump_angle), bump_r * sin(slot_angles[0] + bump_angle), slot_cz], [cos(slot_angles[0] + bump_angle), sin(slot_angles[0] + bump_angle), 0], bump_sphere * 2],
            ["neck_rib", "material", [[rib1_x, rib1_y, slot_z + 0.3], [rib1_x + 6, rib1_y + 6, slot_z + slot_h - 0.3]], 0.30],
            ["neck_rib_2", "material", [[rib2_x, rib2_y, slot_z + 0.3], [rib2_x + 6, rib2_y + 6, slot_z + slot_h - 0.3]], 0.30],
            ["detent_bump", "view", [[2, 29, slot_z - 0.5], [8.5, 35, slot_z + slot_h + 0.5]]]
        ]]
    ]);
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-outer_r, -outer_r, 0], [outer_r, outer_r, lid_top_z - skirt_bottom_z]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 3000]]],
        ["overhangs_allowed", [
            ["bayonet lug undersides: 1.7mm inward tabs, self-bridging in PETG", [[-36, -36, 6], [36, 36, 11]]]
        ]],
        ["copies", 1],
        ["details", [
            ["skirt_wall", "thickness", [25, 43.3, 8], [-0.5, -0.866, 0], 3.5],
            ["top_disk", "thickness", [0, 0, -5], [0, 0, 1], 3.0],
            ["lid_cavity", "void", [[-24, -24, 6], [24, 24, 15]], 0.95],
            ["lug", "material", [[31.8, -2.5, 7], [35, 2.5, 10]], 0.55],
            ["lug_2", "material", [[lug2_x, lug2_y, 7], [lug2_x + 6, lug2_y + 6, 10]], 0.30],
            ["lug_3", "material", [[lug3_x, lug3_y, 7], [lug3_x + 6, lug3_y + 6, 10]], 0.30],
            ["lug_view", "view", [[29, -6, 4.5], [39, 6, 12.5]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-outer_r, -outer_r, 0], [outer_r, outer_r, lid_top_z]]],
        ["support_faces", [["desk", "-z", 3000]]],
        ["motions", [
            ["lock_turn", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [-90, 0]]
        ]],
        ["assembly_order", [
            [["jar"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["rotate", [0, 0, 0], [0, 0, 1], 90]]
        ]]
    ]);
}

// ---------- helpers ----------
function sector_pts(r1, r2, a1, a2) =
    let(n = max(3, ceil((a2 - a1) / 3)))
    concat(
        [for (i = [0:n]) let(a = a1 + (a2 - a1) * i / n) [r2 * cos(a), r2 * sin(a)]],
        [for (i = [n:-1:0]) let(a = a1 + (a2 - a1) * i / n) [r1 * cos(a), r1 * sin(a)]]
    );

module sector_block(r1, r2, a1, a2, z, h) {
    translate([0, 0, z])
        linear_extrude(height = h)
            polygon(sector_pts(r1, r2, a1, a2));
}

function smooth(t) = 0.5 - 0.5 * cos(t * 180);

// jar profile: [radius, z], centre-bottom -> outside up -> rim -> inside down -> floor
jar_profile = concat(
    [[0, 0], [35, 0], [38, 3], [38, shoulder_z0]],
    [for (i = [1:8]) let(t = i / 8, s = smooth(t))
        [outer_r - (outer_r - neck_r) * s, shoulder_z0 + (shoulder_z1 - shoulder_z0) * t]],
    [[neck_r, 82], [33, rim_z], [31, rim_z], [neck_inner_r, 82], [neck_inner_r, shoulder_z1]],
    [for (i = [1:8]) let(t = i / 8, s = smooth(t))
        [neck_inner_r + (inner_r - neck_inner_r) * s, shoulder_z1 - (shoulder_z1 - shoulder_z0) * t]],
    [[inner_r, floor_t], [0, floor_t]]
);

// lid profile in use coords: [radius, z]
lid_profile = [
    [0, lid_top_z], [35, lid_top_z], [outer_r, lid_ceiling_z],
    [outer_r, skirt_bottom_z + 1], [37, skirt_bottom_z],
    [skirt_inner_r, skirt_bottom_z], [skirt_inner_r, lid_ceiling_z],
    [0, lid_ceiling_z]
];

// ---------- jar ----------
module jar_shape() {
    union() {
        difference() {
            rotate_extrude($fn = 160) polygon(jar_profile);
            for (a = slot_angles) {
                // horizontal groove: entry centre round a quarter turn to locked
                sector_block(groove_r, outer_r + 2, a - entry_half,
                             a + locked_angle + lock_extra, slot_z, slot_h);
                // vertical entry from the rim down to the horizontal groove
                sector_block(groove_r, outer_r + 2, a - entry_half,
                             a + entry_half, slot_z, rim_z - slot_z + 2);
            }
        }
        // detent bumps on the groove floor, just before the locked pocket
        for (a = slot_angles)
            translate([(bump_r) * cos(a + bump_angle),
                       (bump_r) * sin(a + bump_angle), slot_cz])
                sphere(r = bump_sphere, $fn = 32);
    }
}

// ---------- lid ----------
module lid_shape_use() {
    union() {
        rotate_extrude($fn = 160) polygon(lid_profile);
        for (a = slot_angles)
            sector_block(lug_tip_r, skirt_inner_r + 0.2, a - lug_half,
                         a + lug_half, lug_z, lug_h);
    }
}

// lid in print orientation: top face on bed, skirt up
module lid_shape_print() {
    translate([0, 0, lid_top_z]) rotate([180, 0, 0]) lid_shape_use();
}

// ---------- output ----------
if (part == "jar") {
    jar_shape();
} else if (part == "lid") {
    lid_shape_print();
} else if (part == "assembly") {
    instance("jar", "jar") jar_shape();
    // closed & locked: lugs turned 90deg from their entries, flush outside
    instance("lid", "lid") rotate([0, 0, locked_angle]) lid_shape_use();
}
