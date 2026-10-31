// ============================================================================
// L SHELF BRACKET FOR FDM PRINTING - PETG - NO SUPPORTS
// Units: millimetres (mm)
// Design load: 3 kg spread over a shelf 150 mm deep.
// Recommended print: PETG, 0.4 mm nozzle, 0.20 mm layers,
// 5 perimeters, 40-50 % gyroid infill and a 5 mm skirt/brim.
// A model-written bracket whose inner fillet sticks out 2 mm behind the wall
// face: the defect the spec check and the cut views must catch.
// ============================================================================

/* [Overall size] */
shelf_depth                = 150;  // Depth of the shelf it carries
front_margin               = 20;   // From the bracket's front to the shelf's edge
shelf_flange_length        = shelf_depth - front_margin; // 130 mm
wall_flange_height         = 120;  // Height of the flange screwed to the wall
bracket_width              = 50;   // Width of both flanges
flange_thickness           = 6;    // Thickness of both flanges

/* [Rib] */
rib_thickness              = 6;    // Thickness of the central gusset
rib_leg                    = 70;   // Length of each leg from the inner corner
inner_fillet_radius        = 8;    // Inner corner radius: lowers stress concentration

/* [4 mm screws] */
screw_diameter             = 4;
diametral_clearance        = 0.5;
hole_diameter              = screw_diameter + diametral_clearance; // 4.5 mm
countersink_head_diameter  = 9;    // Largest diameter of the flat head
// 90 degree countersink: a 45 degree slope, printable without supports.
countersink_depth          = (countersink_head_diameter - hole_diameter) / 2; // 2.25 mm
drill_overcut              = 1;    // Overcut of the cutting tools

/* [Screw positions] */
// The wall screws are offset in Y to stay clear of the central rib.
wall_screws_y              = 36;
lower_wall_screw_z         = 28;
upper_wall_screw_z         = 92;
// The shelf screw is centered in Y, in front of the rib's end.
shelf_screw_x              = 100;
shelf_screw_y              = bracket_width / 2;

$fn = 64;

// Basic interference and margin checks.
assert(shelf_screw_x > flange_thickness + rib_leg + countersink_head_diameter);
assert(upper_wall_screw_z < wall_flange_height - flange_thickness);

// ----------------------------------------------------------------------------
// Vertical flange against the wall: X = thickness, Y = width, Z = height.
// The back face (X=0) rests against the wall.
// ----------------------------------------------------------------------------
module wall_flange() {
    cube([flange_thickness, bracket_width, wall_flange_height]);
}

// ----------------------------------------------------------------------------
// Horizontal flange under the shelf. Its top face is at Z=wall_flange_height.
// ----------------------------------------------------------------------------
module shelf_flange() {
    translate([0, 0, wall_flange_height - flange_thickness])
        cube([shelf_flange_length, bracket_width, flange_thickness]);
}

// ----------------------------------------------------------------------------
// Inner fillet: a cylinder sitting in the corner; it only adds material in
// the inner quadrant, reinforcing the zone that bends the most.
// ----------------------------------------------------------------------------
module inner_fillet() {
    translate([flange_thickness, bracket_width, wall_flange_height - flange_thickness])
        rotate([90, 0, 0])
            cylinder(r = inner_fillet_radius, h = bracket_width);
}

// ----------------------------------------------------------------------------
// Triangular gusset centered in the width, between the front face of the wall
// flange and the bottom face of the shelf flange. Hypotenuse at 45 degrees.
// ----------------------------------------------------------------------------
module rib() {
    translate([flange_thickness,
               bracket_width / 2 + rib_thickness / 2,
               wall_flange_height - flange_thickness])
        rotate([90, 0, 0])
            linear_extrude(height = rib_thickness)
                polygon(points = [[0, 0], [0, -rib_leg], [rib_leg, 0]]);
}

// Solid body without holes.
module body() {
    union() {
        wall_flange();
        shelf_flange();
        inner_fillet();
        rib();
    }
}

// ----------------------------------------------------------------------------
// Countersunk hole along X for the wall flange.
// The screw head goes in from the front face (X=flange_thickness).
// ----------------------------------------------------------------------------
module wall_countersunk_hole(pos_y, pos_z) {
    cone_length = countersink_depth + drill_overcut;

    // Screw clearance.
    translate([-drill_overcut, pos_y, pos_z])
        rotate([0, 90, 0])
            cylinder(d = hole_diameter, h = flange_thickness + 2 * drill_overcut);

    // 90 degree countersink cone.
    translate([flange_thickness - countersink_depth, pos_y, pos_z])
        rotate([0, 90, 0])
            cylinder(h = cone_length,
                     r1 = hole_diameter / 2,
                     r2 = hole_diameter / 2 + cone_length);
}

// ----------------------------------------------------------------------------
// Countersunk hole along Z for the shelf flange.
// The head sits on the bottom face and the screw goes into the shelf.
// ----------------------------------------------------------------------------
module shelf_countersunk_hole(pos_x, pos_y) {
    bottom_z = wall_flange_height - flange_thickness;
    cone_length = countersink_depth + drill_overcut;

    // Screw clearance.
    translate([pos_x, pos_y, bottom_z - drill_overcut])
        cylinder(d = hole_diameter, h = flange_thickness + 2 * drill_overcut);

    // 90 degree countersink cone.
    translate([pos_x, pos_y, bottom_z - drill_overcut])
        cylinder(h = cone_length,
                 r1 = hole_diameter / 2 + cone_length,
                 r2 = hole_diameter / 2);
}

// The part in its position of use, before it is oriented for printing.
module bracket() {
    difference() {
        body();

        wall_countersunk_hole(wall_screws_y, lower_wall_screw_z);
        wall_countersunk_hole(wall_screws_y, upper_wall_screw_z);
        shelf_countersunk_hole(shelf_screw_x, shelf_screw_y);
    }
}

// ----------------------------------------------------------------------------
// PRINT ORIENTATION: one whole side face rests on the bed (Z=0), the L profile
// is printed in layers parallel to its bending plane and the print height is
// only the bracket's width (50 mm).
// ----------------------------------------------------------------------------
translate([0, wall_flange_height, 0])
    rotate([90, 0, 0])
        bracket();
