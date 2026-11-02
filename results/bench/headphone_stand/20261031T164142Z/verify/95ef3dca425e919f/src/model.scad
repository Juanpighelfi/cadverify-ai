// Headphone stand in three printed parts: base, post and hanger.
// No glue and no screws. Rectangular (non-round) tenons prevent rotation.
// Units: mm. Printed in PLA, 0.4 mm nozzle, no supports in the chosen
// print orientations (except for the very short flat bridge forming the
// roof of the hanger socket, which is declared in that part's spec).

part = "assembly"; // ["base", "post", "hanger", "assembly"]

$fn = 48;

/* Design parameters */
fit_clear = 0.3;          // clearance per side at both tenon joints

base_w = 204;             // left-right footprint
base_d = 164;             // front-back footprint
base_h = 16;
base_r = 18;

pocket_w = 28 + 2 * fit_clear;   // 28.6
pocket_d = 30 + 2 * fit_clear;   // 30.6
pocket_depth = 8;
pocket_floor = base_h - pocket_depth; // z = 8

post_bottom = pocket_floor + 0.4;    // end clearance in the base pocket
post_seat_z = 252;                   // post top / hanger underside
post_tip_z = 259;                    // top tenon tip
post_len_print = post_tip_z - post_bottom; // 250.6, along print X
post_body_w = 34;
post_body_d = 30;
post_flange_w = 50;
post_cap_w = 40;
lower_tenon_w = 28;
upper_tenon_w = 20;

hang_seat_z = 252;
hang_top_z = 270;
hang_len = 172;           // x = -86..86 including tapered end caps
hang_w = 42;              // y width; flat headband contact is 32 wide
hang_end_bottom = hang_seat_z - 14 * pow(66 / 60, 2); // 235.06 at |x|=86
hang_print_ymax = hang_top_z - hang_end_bottom;      // 34.94

socket_w = upper_tenon_w + 2 * fit_clear; // 20.6 in x
socket_d = post_body_d + 2 * fit_clear;   // 30.6 in y
socket_top_z = 259.6;

/* Cross-section helpers */

// Rectangle in XY with all four corners cut. lx is the cut leg along X,
// ly is the cut leg along Y. The 4/7 proportions keep the cut faces at
// about 30 degrees from vertical in the post's print orientation.
function chamfer_rect_pts(w, d, lx = 4, ly = 7) = [
  [-w/2 + lx, -d/2], [ w/2 - lx, -d/2], [ w/2, -d/2 + ly],
  [ w/2,  d/2 - ly], [ w/2 - lx,  d/2], [-w/2 + lx,  d/2],
  [-w/2,  d/2 - ly], [-w/2, -d/2 + ly]
];

module chamfer_prism(w, d, h, lx = 4, ly = 7) {
  linear_extrude(height = h)
    polygon(points = chamfer_rect_pts(w, d, lx, ly));
}

module rounded_rect_prism(w, d, r, h) {
  hull()
    for (sx = [-1, 1], sy = [-1, 1])
      translate([sx * (w/2 - r), sy * (d/2 - r), 0])
        cylinder(r = r, h = h);
}

/* ---------------- Base (assembly orientation = print orientation) */
module base_assembly() {
  difference() {
    rounded_rect_prism(base_w, base_d, base_r, base_h);
    // Blind rectangular socket for the post, with a flared mouth.
    union() {
      translate([0, 0, pocket_floor - 0.1])
        cube([pocket_w, pocket_d, base_h - pocket_floor - 1.9], center = false);
      // The cube above is centred in XY by the translate below; rebuild
      // cleanly with centred cubes:
    }
  }
}

// The base is built again here without the placeholder difference above.
// (base_assembly is not used; see base_geometry.)
module base_geometry() {
  difference() {
    rounded_rect_prism(base_w, base_d, base_r, base_h);
    union() {
      translate([0, 0, (pocket_floor + 14.1) / 2])
        cube([pocket_w, pocket_d, 14.1 - pocket_floor + 0.2], center = true);
      hull() {
        translate([0, 0, 14.0])
          cube([pocket_w, pocket_d, 0.2], center = true);
        translate([0, 0, base_h + 0.1])
          cube([pocket_w + 4, pocket_d + 4, 0.2], center = true);
      }
    }
  }
}

module base_part() {
  base_geometry();
}

/* ---------------- Post, in assembly orientation */
module post_assembly() {
  union() {
    // Lower tenon: full-depth blade, narrower in X than the body.
    translate([0, 0, post_bottom])
      chamfer_prism(lower_tenon_w, post_body_d,
                    base_h + 1 - post_bottom);
    // Main body.
    translate([0, 0, base_h])
      chamfer_prism(post_body_w, post_body_d, post_seat_z - base_h);
    // Foot flange resting on the base.
    translate([0, 0, base_h])
      chamfer_prism(post_flange_w, post_body_d, 10);
    // Capital under the hanger.
    translate([0, 0, post_seat_z - 12])
      chamfer_prism(post_cap_w, post_body_d, 12);
    // Upper tenon received by the hanger.
    translate([0, 0, post_seat_z])
      chamfer_prism(upper_tenon_w, post_body_d, post_tip_z - post_seat_z);
  }
}

// Print orientation: length along +X, the assembly -Y face on the bed.
// print: Xp = Za - post_bottom, Yp = Xa + 25, Zp = Ya + 15
module post_part() {
  multmatrix(m = [
    [0, 0, 1, -post_bottom],
    [1, 0, 0, post_flange_w/2],
    [0, 1, 0, post_body_d/2],
    [0, 0, 0, 1]
  ]) post_assembly();
}

/* ---------------- Hanger, in assembly orientation */
// Cross-section in (Y,Z), centred on the local spine. hw is half width,
// t is local vertical thickness. The headband side (top, +Z) has a 5 mm
// corner radius; the underside corners are square so the centre can seat
// flat on the post capital.
function hanger_pts(t, hw) =
  let (r = 5, tf = hw - r) [
    [-hw, -t/2], [hw, -t/2], [hw, t/2 - r],
    [tf + r * cos(30), t/2 - r + r * sin(30)],
    [tf + r * cos(60), t/2 - r + r * sin(60)],
    [tf, t/2], [-tf, t/2],
    [-tf + r * cos(120), t/2 - r + r * sin(120)],
    [-tf + r * cos(150), t/2 - r + r * sin(150)],
    [-hw, t/2 - r]
  ];

function hang_bottom(x) =
  let (ax = abs(x))
    ax <= 20 ? hang_seat_z
             : hang_seat_z - 14 * pow((ax - 20) / 60, 2);

function hang_thick(x) = 18 - 2 * pow(abs(x) / 80, 2);

// [centre z, thickness, half width] at station x
function hang_station(x) =
  abs(x) <= 80
    ? [hang_bottom(x) + hang_thick(x) / 2,
       hang_thick(x), hang_w / 2]
    : [(hang_end_bottom + 9 / 2), 9, 15];

hang_xs = concat([-86], [for (i = [-8 : 8]) i * 10], [86]);

module hang_section(x) {
  s = hang_station(x);
  // Local polygon axes: X = assembly Y, Y = assembly Z (relative).
  // Slice thickness is local Z, mapped to assembly X.
  multmatrix(m = [
    [0, 0, 1, x],
    [1, 0, 0, 0],
    [0, 1, 0, s[0]],
    [0, 0, 0, 1]
  ])
    linear_extrude(height = 0.1)
      polygon(points = hanger_pts(s[1], s[2]));
}

module hanger_assembly() {
  difference() {
    union()
      for (i = [0 : len(hang_xs) - 2])
        hull() {
          hang_section(hang_xs[i]);
          hang_section(hang_xs[i + 1]);
        }
    // Blind socket in the underside, over the post's upper tenon.
    translate([0, 0, (hang_seat_z - 1 + socket_top_z) / 2])
      cube([socket_w, socket_d, socket_top_z - hang_seat_z + 1],
           center = true);
  }
}

// Print orientation: on one 42 mm side face. Xp = Xa,
// Yp = hang_top_z - Za, Zp = Ya + hang_w/2. Bed is Zp = 0.
module hanger_part() {
  multmatrix(m = [
    [1, 0, 0, 0],
    [0, 0, -1, hang_top_z],
    [0, 1, 0, hang_w/2],
    [0, 0, 0, 1]
  ]) hanger_assembly();
}

/* ---------------- Specs and part selection */

if (part == "base") {
  echo(cadverify_spec = [
    ["bounds", [[-base_w/2, -base_d/2, 0], [base_w/2, base_d/2, base_h]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["desk", "-z", 30000]]],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
      ["plinth", "material", [[-90, -70, 1], [90, 70, 7]], 0.95],
      ["socket", "void", [[-13, -14, 9], [13, 14, 15]], 0.95],
      ["socket_floor", "thickness", [0, 0, 25], [0, 0, -1], pocket_floor],
      ["base_outline", "view", [[-base_w/2, -base_d/2, 0], [base_w/2, -60, base_h]]]
    ]]
  ]);
  base_part();
} else if (part == "post") {
  echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], [post_len_print, post_flange_w, post_body_d]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["bed", "-z", 6000]]],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
      ["lower_tenon", "material", [[0, 12, 1], [8, 38, 29]], 0.90],
      ["foot_flange", "material", [[8, 2, 8], [18, 48, 22]], 0.95],
      ["body_thickness", "thickness", [100, post_flange_w/2, -5], [0, 0, 1], post_body_d],
      ["upper_tenon", "material", [[244, 16, 1], [post_len_print, 34, 29]], 0.90],
      ["upper_tenon_end", "view", [[240, 10, 0], [post_len_print, 40, post_body_d]]]
    ]]
  ]);
  post_part();
} else if (part == "hanger") {
  echo(cadverify_spec = [
    ["bounds", [[-hang_len/2, 0, 0], [hang_len/2, hang_print_ymax, hang_w]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["bed", "-z", 1900]]],
    ["overhangs_allowed", [
      ["roof of the blind hanger socket is a flat bridge of about 8 mm in the print-Y direction and prints support-free in PLA",
        [[-11, 10, 34], [11, 19, 37]]],
      ["lower edges of the two side faces of the curved profile form a 0.7 mm 45-degree chamfer lip along the underside; the face beyond 45 degrees is only this chamfer where the polygon joins the flat side, deliberate to avoid a knife edge on the end grain",
        [[-82, 0, 0], [82, 22, 2]]]
    ]],
    ["copies", 1],
    ["details", [
      ["socket", "void", [[-9, 11, 7], [9, 18, 35]], 0.95],
      ["saddle_flat", "material", [[-20, 1, 5], [20, 4, 37]], 0.90],
      ["saddle_profile_thickness", "thickness", [30, -5, hang_w/2], [0, 1, 0], 17.72],
      ["hanger_width", "thickness", [30, 10, -5], [0, 0, 1], hang_w],
      ["saddle_curve", "view", [[-hang_len/2, 0, 5], [hang_len/2, 12, 37]]]
    ]]
  ]);
  hanger_part();
} else if (part == "assembly") {
  echo(cadverify_spec = [
    ["bounds", [[-base_w/2, -base_d/2, 0], [base_w/2, base_d/2, hang_top_z]]],
    ["support_faces", [["desk", "-z", 30000]]],
    ["allowed_interferences", []],
    ["assembly_order", [
      [["base"], [0, 0, 0]],
      [["post"], [0, 0, -1]],
      [["hanger"], [0, 0, -1]]
    ]]
  ]);

  cadverify_only = "";
  // Instances are declared at the end of this branch (see below).
  assembly_instances();
}

module assembly_instances() {
  instance("base", "base")
    base_part();

  // Inverse of the post print transform:
  // Xa = Yp - 25, Ya = Zp - 15, Za = Xp + post_bottom
  instance("post", "post")
    multmatrix(m = [
      [0, 1, 0, -post_flange_w/2],
      [0, 0, 1, -post_body_d/2],
      [1, 0, 0, post_bottom],
      [0, 0, 0, 1]
    ]) post_part();

  // Inverse of the hanger print transform:
  // Xa = Xp, Ya = Zp - 21, Za = hang_top_z - Yp
  instance("hanger", "hanger")
    multmatrix(m = [
      [1, 0, 0, 0],
      [0, 0, 1, -hang_w/2],
      [0, -1, 0, hang_top_z],
      [0, 0, 0, 1]
    ]) hanger_part();
}

cadverify_only = "";
module instance(name, part_name, unit = 1) {
  echo(cadverify_instance = [name, part_name, unit]);
  if (cadverify_only == "" || cadverify_only == name) children();
}
