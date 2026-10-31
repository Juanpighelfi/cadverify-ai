// Desk jar with a bayonet lid — quarter-turn lock, no threads.
// Print: PETG, 0.4 mm nozzle, no supports. Jar upright, lid top-down on the bed.

/* [Part] */
part = "assembly"; // [jar, lid, assembly]

/* [Jar dimensions] */
jar_inner_d = 70;          // main cavity diameter
jar_depth   = 80;          // floor top to rim
wall        = 2.4;         // body wall / floor thickness (>= 1.6)
neck_inner_d = 61;         // opening at the neck
neck_z0     = 64;          // shoulder height where the lid skirt seats

/* [Lid / bayonet] */
clearance   = 0.4;         // radial PETG clearance, sliding faces
lug_count   = 3;
lock_turn_deg = 90;        // quarter turn

// ---- derived ----
inner_r  = jar_inner_d / 2;              // 35
outer_r  = inner_r + wall;               // 37.4
floor_t  = wall;                         // 2.4
jar_h    = floor_t + jar_depth;          // 82.4
neck_in_r  = neck_inner_d / 2;           // 30.5
neck_out_r = 34.2;                       // neck wall 3.7 thick
slot_bot_r = 32.6;                       // bayonet groove floor (2.1 wall behind)
lid_out_r  = outer_r;                    // 37.4  -> flush with jar body
lid_in_r   = neck_out_r + clearance;     // 34.6
lid_h      = 22;                         // skirt rim (seat) to lid top
lid_top_asm = neck_z0 + lid_h;           // 86  assembly z of lid top

// bayonet slot (jar, assembly z)
slot_z_bot  = 71.6;                      // groove bottom wall
slot_top_in = 74.0;                      // groove ceiling at slot_bot_r (45 deg out/up)
// lug (assembly z): bottom 72.0, top 75.2 at root sloping -45 deg to tip
lug_z_bot   = slot_z_bot + clearance;    // 72.0
lug_tip_r   = 33.0;                      // 0.4 clear of groove floor, 1.2 engagement
lug_w       = 6.6;                       // tangential lug width

detent_h    = 0.6;                       // bump on groove floor: top 72.2, 0.2 press on lug

$fn = 160;

function v3(p) = p;

// ============================== JAR ==============================
module jar_body() {
    rotate_extrude()
        polygon(points = [
            [0, 0], [35.4, 0], [outer_r, 2],                 // base, 45 deg foot chamfer
            [outer_r, 20], [36.7, 20.7], [outer_r, 21.4],    // shallow 45 deg decorative groove
            [outer_r, neck_z0], [neck_out_r, neck_z0],       // flat lid seat out to the neck wall
            [neck_out_r, 81.4], [33.2, jar_h],               // neck + rim chamfer
            [neck_in_r, jar_h], [neck_in_r, 70],             // rim, neck bore
            [inner_r, 65.5],                                 // 45 deg inner cone to full cavity
            [inner_r, floor_t], [0, floor_t]                 // cavity wall + floor
        ]);
}

module jar_slot_cutters() {
    for (i = [0 : lug_count - 1]) {
        a = i * 360 / lug_count;
        // horizontal (locking) groove: ceiling rises 45 deg radially outward so it prints clean
        rotate([0, 0, a - 8])
            rotate_extrude(angle = lock_turn_deg + 15.5)
                polygon(points = [[slot_bot_r, slot_z_bot], [38, slot_z_bot],
                                  [38, 79.4], [slot_bot_r, slot_top_in]]);
        // vertical entry groove, open at the rim
        rotate([0, 0, a - 8])
            rotate_extrude(angle = 16)
                polygon(points = [[slot_bot_r, slot_z_bot], [38, slot_z_bot],
                                  [38, jar_h + 2], [slot_bot_r, jar_h + 2]]);
    }
}

module jar_detents() {
    // small bump on the groove floor just behind the lug's locked position;
    // lug (0.4 above floor) rides over the 0.6 bump (0.2 press) then settles past it.
    // Added after the slot cut so the cutter cannot remove it.
    for (i = [0 : lug_count - 1]) {
        a = i * 360 / lug_count;
        rotate([0, 0, a + 71.5])
            rotate_extrude(angle = 6)
                polygon(points = [[slot_bot_r - 0.1, slot_z_bot], [34.0, slot_z_bot],
                                  [34.0, slot_z_bot + detent_h], [slot_bot_r - 0.1, slot_z_bot + detent_h]]);
    }
}

module jar() {
    union() {
        difference() {
            jar_body();
            jar_slot_cutters();
        }
        jar_detents();
    }
}

// ============================== LID (print orientation: top face on bed, skirt up) ==============================
module lid_body() {
    rotate_extrude()
        polygon(points = [
            [0, 0], [35.4, 0], [lid_out_r, 2],        // top face on bed + 45 deg edge chamfer
            [lid_out_r, 21.2], [36.6, lid_h],         // outer wall + rim chamfer
            [lid_in_r, lid_h], [lid_in_r, 2.4],       // skirt rim (seat) + inner wall
            [0, 2.4]                                  // cap underside
        ]);
}

module lid_lug_one() {
    // print z of lug: flat face up (assembly bottom), 45 deg face down toward cap (assembly top)
    // profile in (r, z_print): root z 10.8..14.0, tip z 12.4..14.0
    rotate([90, 0, 0])
        linear_extrude(height = lug_w, center = true)
            polygon(points = [[lug_tip_r, 12.4], [35.0, 10.8], [35.0, 14.0], [lug_tip_r, 14.0]]);
}

module lid_grip_cutters() {
    for (i = [0 : 23])
        rotate([0, 0, i * 15])
            translate([36.7, -1.1, 3]) cube([3.2, 2.2, lid_h - 2]);
}

module lid() {
    difference() {
        union() {
            lid_body();
            for (i = [0 : lug_count - 1]) rotate([0, 0, i * 360 / lug_count]) lid_lug_one();
        }
        lid_grip_cutters();
    }
}

// ============================== SPECS ==============================
module spec_jar() {
    echo(cadverify_spec = [
        ["bounds", [[-outer_r, -outer_r, 0], [outer_r, outer_r, jar_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base", "-z", 3000]]],
        ["overhangs_allowed", [
            ["bayonet_slot_45deg_ceiling_and_detent", [[-38, -38, 70], [38, 38, 83]]]
        ]],
        ["copies", 1],
        ["details", [
            ["cavity", "void", [[-30, -30, 5], [30, 30, 60]], 0.95],
            ["neck_opening", "void", [[-28, -28, 72], [28, 28, 80]], 0.95],
            ["slot_entry", "void", [[32.7, -4, 76], [34.1, 4, 81]], 0.85],
            ["body_wall", "thickness", [-40, 0, 40], [1, 0, 0], wall],
            ["floor", "thickness", [0, 0, -5], [0, 0, 1], floor_t],
            ["neck_wall", "thickness", [40, 0, 68], [-1, 0, 0], 3.7],
            ["detent_bump", "material", [[7.9, 31.4, 71.65], [9.8, 32.7, 72.15]], 0.5],
            ["decorative_groove", "view", [[28, -12, 18], [37.5, 12, 24]]]
        ]]
    ]);
}

module spec_lid() {
    echo(cadverify_spec = [
        ["bounds", [[-lid_out_r, -lid_out_r, 0], [lid_out_r, lid_out_r, lid_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["top_on_bed", "-z", 3000]]],
        ["overhangs_allowed", [
            ["lug_45deg_face", [[-38, -38, 9], [38, 38, 15]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_cavity", "void", [[-30, -30, 5], [30, 30, 18]], 0.95],
            ["lug", "material", [[33.1, -3, 11], [34.5, 3, 13.8]], 0.45],
            ["skirt_wall", "thickness", [38.17, 5.02, 12], [-0.991, -0.131, 0], 2.8],
            ["cap", "thickness", [0, 0, -5], [0, 0, 1], 2.4],
            ["grip_flutes", "view", [[28, -12, 8], [37.5, 12, 20]]]
        ]]
    ]);
}

// ============================== ASSEMBLY ==============================
cadverify_only = "";
module instance(name, part_name, unit = 1) {
    echo(cadverify_instance = [name, part_name, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module assembly() {
    echo(cadverify_spec = [
        ["bounds", [[-outer_r, -outer_r, 0], [outer_r, outer_r, lid_top_asm]]],
        ["support_faces", [["desk", "-z", 3000]]],
        ["allowed_interferences", [
            ["lid", "jar", "detent bump grazes lug path by up to 0.2 mm as a snap detent"]
        ]],
        ["motions", [
            ["lid_lock_turn", ["lid"], "rotate", [0, 0, 0], [0, 0, 1], [-90, 0]]
        ]],
        ["assembly_order", [
            [["jar"], [0, 0, 0]],
            [["lid"], [0, 0, -1], ["rotate", [0, 0, 0], [0, 0, 1], 90]]
        ]]
    ]);
    instance("jar", "jar") jar();
    // lid print pose flipped over onto the jar, rotated so lugs sit at the locked end of the slots
    instance("lid", "lid")
        translate([0, 0, lid_top_asm]) rotate([0, 0, 90]) rotate([180, 0, 0]) lid();
}

// ============================== OUTPUT ==============================
if (part == "jar") {
    spec_jar();
    jar();
} else if (part == "lid") {
    spec_lid();
    lid();
} else if (part == "assembly") {
    assembly();
} else {
    assert(false, str("unknown part: ", part));
}
