// Print-in-place gimbal: outer ring on stand, middle ring, inner disc.
// Print orientation: flat on bed, +Z up, bottom at z=0.

part = "assembly"; // [stand_outer, middle, inner, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- parameters (mm) ---------- */
R_o_out = 35;
R_o_in  = 29;
T       = 6;          // thickness of all rings/disc
Gap     = 0.6;        // radial gap between rings
R_m_out = R_o_in - Gap;       // 28.4
W_m     = 6;
R_m_in  = R_m_out - W_m;      // 22.4
R_i     = R_m_in - Gap;       // 21.8
d_pin   = 3;
d_sock  = 4;
sock_depth = 3.5;
tip_clear  = 0.5;
pin_overlap = 1.0;

// stand foot
stand_w = 24;
stand_d = 12;
stand_y0 = -R_o_out + 2 - stand_d; // -45, 2mm overlap into ring

// derived pin tips
tip_outer = R_o_in + sock_depth - tip_clear; // 32.0
base_m_outer = R_m_out - pin_overlap;        // 27.4
tip_inner = R_m_in + sock_depth - tip_clear; // 25.4  (socket bottom in middle)
base_inner = R_i - pin_overlap;              // 20.8

$fn = 128;

/* ---------- parts ---------- */
module m_stand_outer() {
    difference() {
        union() {
            // outer ring
            difference() {
                cylinder(h=T, r=R_o_out);
                translate([0,0,-1]) cylinder(h=T+2, r=R_o_in);
            }
            // stand foot
            translate([-stand_w/2, stand_y0, 0]) cube([stand_w, stand_d, T]);
        }
        // sockets along X (mouth extends 0.5 into gap)
        // +X
        translate([(R_o_in-0.5 + R_o_in+sock_depth)/2, 0, T/2])
            rotate([0,90,0]) cylinder(h=sock_depth+0.5, r=d_sock/2);
        // -X
        translate([-(R_o_in-0.5 + R_o_in+sock_depth)/2, 0, T/2])
            rotate([0,90,0]) cylinder(h=sock_depth+0.5, r=d_sock/2);
    }
}

module m_middle() {
    difference() {
        union() {
            difference() {
                cylinder(h=T, r=R_m_out);
                translate([0,0,-1]) cylinder(h=T+2, r=R_m_in);
            }
            // pins outward along +-X
            // +X pin from base_m_outer to tip_outer
            translate([(base_m_outer+tip_outer)/2, 0, T/2])
                rotate([0,90,0]) cylinder(h=tip_outer-base_m_outer, r=d_pin/2);
            // -X
            translate([-(base_m_outer+tip_outer)/2, 0, T/2])
                rotate([0,90,0]) cylinder(h=tip_outer-base_m_outer, r=d_pin/2);
        }
        // sockets along Y for inner pins (mouth extends 0.5 into gap)
        // +Y: from R_m_in-0.5 to R_m_in+sock_depth
        translate([0, (R_m_in-0.5 + R_m_in+sock_depth)/2, T/2])
            rotate([90,0,0]) cylinder(h=sock_depth+0.5, r=d_sock/2);
        // -Y
        translate([0, -(R_m_in-0.5 + R_m_in+sock_depth)/2, T/2])
            rotate([90,0,0]) cylinder(h=sock_depth+0.5, r=d_sock/2);
    }
}

module m_inner() {
    union() {
        cylinder(h=T, r=R_i);
        // pins along +-Y from base_inner to tip_inner
        translate([0, (base_inner+tip_inner)/2, T/2])
            rotate([90,0,0]) cylinder(h=tip_inner-base_inner, r=d_pin/2);
        translate([0, -(base_inner+tip_inner)/2, T/2])
            rotate([90,0,0]) cylinder(h=tip_inner-base_inner, r=d_pin/2);
    }
}

/* ---------- specs ---------- */
// stand_outer spec
// bounds: X +-35, Y -45..35, Z 0..6
// middle bounds: X +-32, Y +-28.4, Z 0..6
// inner bounds: X +-21.8, Y +-25.4, Z 0..6

if (part == "stand_outer") {
    echo(cadverify_spec = [
        ["bounds", [[-35, -45, 0], [35, 35, 6]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 1000]]],
        ["overhangs_allowed", [
            ["socket_plus_x bridge", [[29, -2.5, 1], [32.5, 2.5, 5]]],
            ["socket_minus_x bridge", [[-32.5, -2.5, 1], [-29, 2.5, 5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["stand_base", "material", [[-10, -44, 0], [10, -34, 6]], 0.9],
            ["outer_wall", "thickness", [40, 0, 3], [-1, 0, 0], 5.5],
            ["socket_plus_x", "hole", [28, 0, 3], [1, 0, 0], [[0, 4], [3, 4]]],
            ["socket_minus_x", "hole", [-28, 0, 3], [-1, 0, 0], [[0, 4], [3, 4]]]
        ]]
    ]);
    m_stand_outer();
} else if (part == "middle") {
    echo(cadverify_spec = [
        ["bounds", [[-32, -28.4, 0], [32, 28.4, 6]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 700]]],
        ["overhangs_allowed", [
            ["pin_plus_x bridge", [[27.4, -2, 1], [32, 2, 4.5]]],
            ["pin_minus_x bridge", [[-32, -2, 1], [-27.4, 2, 4.5]]],
            ["socket_plus_y bridge", [[-2.5, 21.9, 1], [2.5, 25.9, 5]]],
            ["socket_minus_y bridge", [[-2.5, -25.9, 1], [2.5, -21.9, 5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_plus_x", "material", [[29, -1, 2], [31, 1, 4]], 0.9],
            ["middle_wall", "thickness", [5, 35, 3], [0, -1, 0], 5.5],
            ["socket_plus_y", "hole", [0, 21, 3], [0, 1, 0], [[0, 4], [3, 4]]],
            ["socket_minus_y", "hole", [0, -21, 3], [0, -1, 0], [[0, 4], [3, 4]]]
        ]]
    ]);
    m_middle();
} else if (part == "inner") {
    echo(cadverify_spec = [
        ["bounds", [[-21.8, -25.4, 0], [21.8, 25.4, 6]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1000]]],
        ["overhangs_allowed", [
            ["pin_plus_y bridge", [[-2, 20.8, 1], [2, 25.4, 4.5]]],
            ["pin_minus_y bridge", [[-2, -25.4, 1], [2, -20.8, 4.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["disc_floor", "thickness", [0, 0, 10], [0, 0, -1], 5.5],
            ["pin_plus_y", "material", [[-1, 22.5, 2], [1, 24.5, 4]], 0.9],
            ["disc_side", "thickness", [30, 0, 3], [-1, 0, 0], 40]
        ]]
    ]);
    m_inner();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-35, -45, 0], [35, 35, 6]]],
        ["motions", [
            ["swing_middle", ["middle", "inner"], "rotate", [0, 0, 3], [1, 0, 0], [0, 360]],
            ["spin_inner", ["inner"], "rotate", [0, 0, 3], [0, 1, 0], [0, 360]]
        ]],
        ["assembly_order", [
            [["stand_outer"], [0, 0, 0]],
            [["middle"], [0, 0, 30]],
            [["inner"], [0, 30, 0]]
        ]],
        ["print_in_place", 0.5],
        ["overhangs_allowed", [
            ["sockets_outer bridge", [[-32.5, -2.5, 1], [32.5, 2.5, 5]]],
            ["pins_middle bridge", [[-32, -2, 1], [32, 2, 4.5]]],
            ["sockets_middle bridge", [[-2.5, -25.9, 1], [2.5, 25.9, 5]]],
            ["pins_inner bridge", [[-2, -25.4, 1], [2, 25.4, 4.5]]]
        ]]
    ]);
    instance("stand_outer", "stand_outer") m_stand_outer();
    instance("middle", "middle") m_middle();
    instance("inner", "inner") m_inner();
}
