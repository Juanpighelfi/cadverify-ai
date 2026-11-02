// Headphone stand in three printable parts: base, post, hanger.
// No glue, no screws. Rectangular (non-round) blade tenons prevent spinning.
// All dimensions in mm. Print orientation is the exported orientation (+Z up).
//
// Assembly heights (assembly coordinates, desk at z=0):
//   base plate/boss top        0 .. 32
//   post                       14.5 .. 250  (17.5 mm of it inside the base socket)
//   hanger tenon               228.5 .. 250 (21.5 mm inside the post socket)
//   hanger saddle top centre   270
// Socket clearances: 0.3 mm per side (socket is tenon + 0.6 in each dimension),
// tenon tips stop 0.5 mm above socket floors; shoulders/faces give the depth stop
// for the hanger, and the post bottoms in its socket.

part = "base"; // [base, post, hanger, assembly]
cadverify_only = "";

$fn = 96;

/* [Base] */
base_w = 188;          // desk footprint, X
base_d = 160;          // desk footprint, Y
base_plate_top = 9;    // straight plate wall up to here, then 45 deg chamfer to 12
base_top_plate = 12;
boss_w = 66;
boss_d = 74;
boss_straight_top = 29; // then 45 deg chamfer to boss_top
boss_top = 32;
base_socket_w = 38.6;  // post 38 + 0.6
base_socket_d = 46.6;  // post 46 + 0.6
base_socket_floor = 14;

/* [Post] */
post_w = 38;
post_d = 46;
post_len = 235.5;      // tip (local z=0) to top (assembly 250)
post_top_socket_w = 24.6; // hanger tenon 24 + 0.6
post_top_socket_d = 34.6; // hanger tenon 34 + 0.6
post_top_socket_floor_local = 213.5; // assembly 228

/* [Hanger, modelled in print coordinates] */
// Print coordinates: X = saddle length, Y = height above tenon tip,
// Z = saddle width direction (part lies on its Z=0 side face on the bed).
hang_len_half = 69;    // overall saddle half length incl. rounded end point
hang_width = 34;       // >= 30 mm headband support width
hang_top_rel = 41.5;   // tenon tip to saddle crown; assembly 228.5 + 41.5 = 270
hang_arc_r = 170;      // crown radius of the headband contact surface
hang_plate_t = 10;     // saddle plate thickness (vertical, in profile)
hang_tenon_half_w = 12;  // tenon is 24 (X) x 34 (width)
hang_shoulder_rel = 21.5; // assembly 250, post top
hang_neck_half_w = 17;

function hang_top_z(x) = hang_top_rel - (hang_arc_r - sqrt(hang_arc_r*hang_arc_r - x*x));
function hang_bot_z(x) = hang_top_z(x) - hang_plate_t;

module rounded_rect(w, d, r) {
    offset(r = r) square([w - 2*r, d - 2*r], center = true);
}

module instance(name, part_name, unit = 1) {
    echo(cadverify_instance = [name, part_name, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- BASE (print = assembly orientation) ---------- */
module base_part() {
    difference() {
        union() {
            // desk plate with 45 deg top edge chamfer
            linear_extrude(base_plate_top) rounded_rect(base_w, base_d, 30);
            hull() {
                translate([0, 0, base_plate_top]) linear_extrude(0.2)
                    rounded_rect(base_w, base_d, 30);
                translate([0, 0, base_top_plate - 0.2]) linear_extrude(0.2)
                    rounded_rect(base_w - 6, base_d - 6, 27);
            }
            // raised boss / collar around the post socket, 45 deg top chamfer
            translate([0, 0, base_top_plate])
                linear_extrude(boss_straight_top - base_top_plate)
                    rounded_rect(boss_w, boss_d, 14);
            hull() {
                translate([0, 0, boss_straight_top]) linear_extrude(0.2)
                    rounded_rect(boss_w, boss_d, 14);
                translate([0, 0, boss_top - 0.2]) linear_extrude(0.2)
                    rounded_rect(boss_w - 6, boss_d - 6, 11);
            }
        }
        // blind rectangular socket for the post (stops post spinning)
        translate([0, 0, base_socket_floor])
            linear_extrude(boss_top - base_socket_floor + 2)
                rounded_rect(base_socket_w, base_socket_d, 5);
    }
}

/* ---------- POST (printed upright, local z=0 is tenon tip) ---------- */
module post_part() {
    difference() {
        linear_extrude(post_len) rounded_rect(post_w, post_d, 8);
        // blind rectangular socket in the top for the hanger blade tenon
        translate([0, 0, post_top_socket_floor_local])
            linear_extrude(post_len - post_top_socket_floor_local + 2)
                rounded_rect(post_top_socket_w, post_top_socket_d, 5);
    }
}

/* ---------- HANGER (printed on its side) ---------- */
module hanger_part() {
    top_pts    = [for (x = [56 : -8 : -56]) [x, hang_top_z(x)]];
    bot_r_pts  = [for (x = [40 : 8 : 64]) [x, hang_bot_z(x)]];
    bot_l_pts  = [for (x = [-64 : 8 : -40]) [x, hang_bot_z(x)]];
    mid64 = (hang_top_z(64) + hang_bot_z(64)) / 2;
    // Saddle/neck profile above the shoulder plane (print y = hang_shoulder_rel).
    profile = concat(
        [[-hang_neck_half_w, hang_shoulder_rel], [hang_neck_half_w, hang_shoulder_rel],
         [30, hang_bot_z(30)]],
        bot_r_pts,
        [[hang_len_half - 0.5, mid64], [64, hang_top_z(64)]],
        top_pts,
        [[-64, hang_top_z(64)], [-(hang_len_half - 0.5), mid64], [-64, hang_bot_z(64)]],
        bot_l_pts,
        [[-30, hang_bot_z(30)]]
    );
    difference() {
        union() {
            linear_extrude(hang_width) polygon(profile);
            // Blade tenon below the shoulder: 24 x 34 with 4 mm corner radii,
            // so it clears the post socket's 5 mm rounded corners. It reaches
            // 2 mm up into the neck so the union is volumetric, not face-only.
            translate([0, 0, hang_width/2]) rotate([-90, 0, 0])
                linear_extrude(hang_shoulder_rel + 2)
                    rounded_rect(2*hang_tenon_half_w, hang_width, 4);
        }
        // 45 deg chamfers on the two crown side edges, centre contact zone only.
        // Plane (print coords): Z + Y = 38.5 + 34 on the far side ...
        translate([0, 38.5, hang_width]) rotate([-45, 0, 0])
            translate([-85, -40, 0]) cube([170, 80, 40]);
        // ... and Z - Y = -38.5 on the bed side.
        translate([0, 38.5, 0]) rotate([45, 0, 0])
            translate([-85, -40, -40]) cube([170, 80, 40]);
    }
}

/* ---------- Spec echoes ---------- */
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-base_w/2, -base_d/2, 0], [base_w/2, base_d/2, boss_top]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["desk", "-z", 25000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["plate", "material", [[-80, -60, 2], [80, 60, 10]], 0.99],
            ["boss_wall", "material", [[22, -30, 16], [31, 30, 28]], 0.99],
            ["post_socket", "void", [[-17, -21, 16], [17, 21, 30]], 0.99],
            ["socket_floor", "thickness", [0, 0, 42], [0, 0, -1], base_socket_floor],
            ["boss_socket_top", "view", [[-34, -38, 27], [34, 38, boss_top]]]
        ]]
    ]);
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-post_w/2, -post_d/2, 0], [post_w/2, post_d/2, post_len]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1500]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["column", "material", [[-16, -20, 30], [16, 20, 200]], 0.99],
            ["hanger_socket", "void", [[-10, -15, 216], [10, 15, 234]], 0.99],
            ["column_width", "thickness", [32, 0, 100], [-1, 0, 0], post_w],
            ["top_socket", "view", [[-19, -23, 210], [19, 23, post_len]]]
        ]]
    ]);
} else if (part == "hanger") {
    // actual extreme points are the saddle end tips at +-(hang_len_half - 0.5)
    echo(cadverify_spec = [
        ["bounds", [[-(hang_len_half - 0.5), 0, 0], [hang_len_half - 0.5, hang_top_rel, hang_width]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1200]]],
        ["overhangs_allowed", [
            ["45deg crown chamfer on bed side", [[-36, 37, 0], [36, hang_top_rel, 5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["saddle_plate", "material", [[-25, 32, 5], [25, 38, 29]], 0.99],
            ["tenon", "material", [[-10, 2, 5], [10, 20, 29]], 0.99],
            ["saddle_thickness", "thickness", [50, 52, 17], [0, -1, 0], hang_plate_t],
            ["rounded_crown", "view", [[-40, 27, 0], [40, hang_top_rel, hang_width]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-base_w/2, -base_d/2, 0], [base_w/2, base_d/2, 270]]],
        ["support_faces", [["desk", "-z", 25000]]],
        ["allowed_interferences", []],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["post"], [0, 0, -1]],
            [["hanger"], [0, 0, -1]]
        ]]
    ]);
}

/* ---------- Output ---------- */
if (part == "base") {
    base_part();
} else if (part == "post") {
    post_part();
} else if (part == "hanger") {
    hanger_part();
} else if (part == "assembly") {
    instance("base", "base") base_part();
    instance("post", "post") translate([0, 0, 14.5]) post_part();
    // hanger print coords (x, y=height rel. tenon tip, z=width)
    //   -> assembly (x, 17-z, 228.5+y): tenon tip at 228.5, crown at 270
    instance("hanger", "hanger")
        translate([0, hang_width/2, 228.5]) rotate([90, 0, 0]) hanger_part();
} else {
    assert(false, str("unknown part: ", part));
}
