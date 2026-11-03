// Weekly pill box with a turning lid
// Two printable parts: base (7 compartments) and lid (1 dispensing opening).
// PLA, Bambu Lab A1, 0.4 mm nozzle, no supports. All walls >= 1.2 mm.
//
// Assembled size: 90 mm diameter x 25 mm tall.
// Base is printed as used (floor on the bed).
// Lid is printed upside-down (its outer top face on the bed, skirt up);
// in the assembly it is flipped over the base.
//
// Retention: an inward annular lip under the lid skirt snaps into an
// annular groove in the base neck (0.4 mm radial snap over the neck land,
// 0.5 mm running clearance in the groove). The lid can turn freely but
// cannot lift off: lip travel is trapped in the groove.
//
// Detent: one smooth dome on the base rim clicks into any of seven
// notches under the lid plate. Axial play of the lip in its groove
// (about +/-1.0 mm) lets the lid ride up 0.6 mm over the dome and drop
// into the next notch, so it holds its step in a bag.

part = "assembly"; // [assembly, base, lid]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* [Dimensions] */
steps         = 7;
step_angle    = 360 / steps;
outer_R       = 45;      // overall radius (90 mm across)
total_H       = 25;      // assembled height
base_H        = 22.8;    // base rim top (assembly z)
floor_t       = 2.0;     // base floor
cavity_R      = 40.0;    // compartment cavity radius
neck_R        = 42.6;    // base neck land radius
groove_R      = 41.7;    // snap groove bottom radius (wall at groove = 1.7)
divider_t     = 1.6;
divider_top   = 22.4;
hub_R         = 8;
plate_t       = 2.2;     // lid top plate
skirt_Ro      = 45;
skirt_Ri      = 43.2;    // 0.6 radial clearance over neck land
lip_R         = 42.2;    // snap lip tip: 0.4 snap over neck, 0.5 clear in groove
lid_print_H   = 10.6;    // lid height in print orientation
open_R1       = 10.5;    // dispensing opening, inner radius
open_R2       = 38.5;    // dispensing opening, outer radius
open_half_a   = 19;      // dispensing opening half-angle (38 deg sector)
dome_Rr       = 1.0;     // detent dome radial half-size
dome_Rt       = 3.2;     // detent dome tangential half-size
dome_h        = 0.7;     // detent dome height above rim

$fn = 180;

// ---------- helpers ----------
// annular sector polygon points (2D, in XY), r1..r2, a1..a2 degrees
function sector_pts(r1, r2, a1, a2, n = 12) =
    concat([for (i = [0:n]) let (a = a1 + (a2 - a1) * i / n)
                [r2 * cos(a), r2 * sin(a)]],
           [for (i = [n:-1:0]) let (a = a1 + (a2 - a1) * i / n)
                [r1 * cos(a), r1 * sin(a)]]);

module sector_prism(r1, r2, a1, a2, z1, z2) {
    linear_extrude(height = z2 - z1)
        translate([0, 0, 0]) polygon(sector_pts(r1, r2, a1, a2));
    // note: extrude starts at z=0, caller translates in z
}

// ---------- base ----------
module base_part() {
    // main body of revolution: floor, cavity, stepped shoulder, neck,
    // snap groove (trapezoid slopes ~37 deg from vertical, printable).
    rotate_extrude()
        polygon([
            [0, 0], [outer_R, 0], [outer_R, 12], [neck_R, 12],
            [neck_R, 14.2], [groove_R, 15.4], [groove_R, 17.6],
            [neck_R, 18.8], [neck_R, base_H],
            [cavity_R, base_H], [cavity_R, floor_t], [0, floor_t]
        ]);
    // central hub
    translate([0, 0, floor_t - 0.5])
        cylinder(h = divider_top - floor_t + 0.5, r = hub_R);
    // seven radial dividers; compartment i is centred between dividers.
    // Divider angles are offset half a step so one compartment is
    // centred on +X (angle 0), where the lid opening sits when closed
    // on that day. One divider lies exactly on -X for easy measuring.
    for (i = [0:steps - 1])
        rotate([0, 0, step_angle / 2 + i * step_angle])
            translate([6, -divider_t / 2, floor_t - 0.5])
                cube([cavity_R - 5.5, divider_t, divider_top - floor_t + 0.5]);
    // single detent dome on the rim at angle 0 (rim annulus r40..42.6)
    translate([41.3, 0, base_H])
        scale([dome_Rr, dome_Rt, dome_h]) sphere(r = 1, $fn = 48);
}

// ---------- lid ----------
// Designed in print orientation: outer top face at z=0 (on the bed),
// plate 0..2.2, skirt rising to z=10.6, snap lip on the skirt bore.
module lid_part() {
    difference() {
        rotate_extrude()
            polygon([
                [0, 0], [skirt_Ro, 0], [skirt_Ro, lid_print_H],
                [skirt_Ri, lid_print_H], [skirt_Ri, 10.4],
                [lip_R, 9.2], [lip_R, 7.8], [skirt_Ri, 6.6],
                [skirt_Ri, plate_t], [0, plate_t]
            ]);
        // dispensing opening: one sector through the plate, centred on +X
        translate([0, 0, -0.1])
            sector_prism(open_R1, open_R2, -open_half_a, open_half_a, 0, plate_t + 0.2);
        // seven detent notches in the underside of the plate (rim radius),
        // one at the opening centre angle, the rest one step apart.
        // 0.9 deep, leaving 1.3 mm of plate above (still >= 1.2 wall).
        for (i = [0:steps - 1])
            rotate([0, 0, i * step_angle])
                translate([0, 0, plate_t - 0.9])
                    sector_prism(40.1, 42.5, -6, 6, 0, 1.0);
        // grip flutes around the skirt outside (turning grip)
        for (i = [0:23])
            rotate([0, 0, i * 15])
                translate([44.4, -1.1, 3.2]) cube([1.4, 2.2, 6.6]);
    }
}

// ---------- specs & output ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-outer_R, -outer_R, 0], [outer_R, outer_R, base_H + dome_h]]],
        ["bodies", 1],
        ["support_faces", [["bed_bottom", "-z", 6000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["hub", "material", [[-3, -3, 5], [3, 3, 18]], 0.95],
            ["floor", "material", [[-20, -20, 0.1], [20, 20, 1.9]], 0.95],
            ["divider_on_minus_x", "material", [[-30, -0.8, 5], [-20, 0.8, 18]], 0.95],
            ["compartment", "void", [[18, -6, 5], [30, 6, 18]], 0.95],
            ["snap_groove", "void", [[41.9, -2, 15.7], [42.5, 2, 17.5]], 0.95],
            ["detent_dome", "material", [[40.8, -1, 22.9], [41.8, 1, 23.35]], 0.3],
            ["outer_wall", "thickness", [44, 0, 20], [-1, 0, 0], neck_R - cavity_R],
            ["floor_thickness", "thickness", [20, 0, -1], [0, 0, 1], floor_t],
            ["divider", "thickness", [-24, 3, 10], [0, -1, 0], divider_t],
            ["seven_compartments", "view", [[-41, -41, 2], [41, 41, 22.8]]]
        ]]
    ]);
    base_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-skirt_Ro, -skirt_Ro, 0], [skirt_Ro, skirt_Ro, lid_print_H]]],
        ["bodies", 1],
        ["support_faces", [["bed_top_face", "-z", 5000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["snap_lip", "material", [[-43.0, -1, 7.9], [-42.3, 1, 9.0]], 0.9],
            ["opening", "void", [[15, -5, 0.1], [35, 5, 2.1]], 0.95],
            ["detent_notch", "void", [[40.5, -2, 1.4], [42.1, 2, 2.6]], 0.95],
            ["grip_flute", "void", [[44.5, -1, 4], [45.6, 1, 9]], 0.95],
            ["plate", "thickness", [0, 20, -1], [0, 0, 1], plate_t],
            ["skirt_wall", "thickness",
                [46 * cos(7.5), 46 * sin(7.5), 5],
                [-cos(7.5), -sin(7.5), 0], skirt_Ro - skirt_Ri],
            ["dispensing_opening", "view", [[9, -40, 0], [40, 40, 2.2]]]
        ]]
    ]);
    lid_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-outer_R, -outer_R, 0], [outer_R, outer_R, total_H]]],
        ["support_faces", [["base_bottom", "-z", 6000]]],
        ["motions", [
            ["full_turn", ["lid_1"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360],
                ["flex", [["lid_1", "base_1", 0.8,
                    "detent dome rides under the lid plate between notches; the lid lifts 0.6 mm on the dome against the axial play of its snap lip in the base groove, then drops into the next notch"]]]]
        ]],
        ["assembly_order", [
            [["base_1"], [0, 0, 0]],
            [["lid_1"], [0, 0, -1],
                ["flex", [["lid_1", "base_1", 0.5,
                    "inward snap lip of the lid skirt expands 0.4 mm radially over the base neck land, then drops into the annular groove"]]]]
        ]],
        ["held", ["lid_1"]]
    ]);
    instance("base_1", "base") base_part();
    // lid flipped from print orientation: print z=0 (outer top) -> z=25
    instance("lid_1", "lid") translate([0, 0, total_H]) rotate([180, 0, 0]) lid_part();
}
