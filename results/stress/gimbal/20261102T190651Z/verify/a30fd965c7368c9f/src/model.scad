// Print-in-place gimbal: outer ring on stand, middle ring, inner disc.
// Print orientation: flat on bed, +Z up, bottom at z=0.
// Pivots are U-grooves open at the top: pins drop in from +Z, no supports.

part = "assembly"; // [stand_outer, middle, inner, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

/* ---------- parameters (mm) ---------- */
R_o_out = 35;
R_o_in  = 29;
T       = 6;
Gap     = 0.8;
R_m_out = R_o_in - Gap;       // 28.2
W_m     = 6;
R_m_in  = R_m_out - W_m;      // 22.2
R_i     = R_m_in - Gap;       // 21.4
d_pin   = 3;
groove_w = 4;                 // pin + 2*0.5 clearance
pin_overlap = 1.0;
tip_clear = 0.5;

// stand foot
stand_w = 24;
stand_d = 12;
stand_y0 = -R_o_out + 2 - stand_d; // -45

// pins: base embedded in ring, tip inside groove with tip_clear to groove end
groove_o_end = 32.0;             // groove bottom in outer ring
pin_m_base = R_m_out - pin_overlap;   // 27.2
pin_m_tip  = groove_o_end - tip_clear; // 31.5
groove_m_end = 25.2;             // groove bottom in middle ring
pin_i_base = R_i - pin_overlap;       // 20.4
pin_i_tip  = groove_m_end - tip_clear; // 24.7
// groove floors leave 0.5 under pin: floor z = 1, pin bottom z = 1.5
groove_z0 = 1.0;

$fn = 128;

/* ---------- parts ---------- */
module m_stand_outer() {
    difference() {
        union() {
            difference() {
                cylinder(h=T, r=R_o_out);
                translate([0,0,-1]) cylinder(h=T+2, r=R_o_in);
            }
            translate([-stand_w/2, stand_y0, 0]) cube([stand_w, stand_d, T]);
        }
        // U-grooves open at top for middle pins (along X)
        // +X groove: from bore (x=28) out to groove_o_end, width groove_w, z 1..top
        translate([28.0, -groove_w/2, groove_z0])
            cube([groove_o_end-28.0, groove_w, T+1-groove_z0]);
        translate([-groove_o_end, -groove_w/2, groove_z0])
            cube([groove_o_end-28.0, groove_w, T+1-groove_z0]);
    }
}

module m_middle() {
    difference() {
        union() {
            difference() {
                cylinder(h=T, r=R_m_out);
                translate([0,0,-1]) cylinder(h=T+2, r=R_m_in);
            }
            translate([pin_m_base, 0, T/2])
                rotate([0,90,0]) cylinder(h=pin_m_tip-pin_m_base, r=d_pin/2);
            translate([-pin_m_base, 0, T/2])
                rotate([0,-90,0]) cylinder(h=pin_m_tip-pin_m_base, r=d_pin/2);
        }
        // U-grooves open at top for inner pins (along Y)
        translate([-groove_w/2, 21.2, groove_z0])
            cube([groove_w, groove_m_end-21.2, T+1-groove_z0]);
        translate([-groove_w/2, -groove_m_end, groove_z0])
            cube([groove_w, groove_m_end-21.2, T+1-groove_z0]);
    }
}

module m_inner() {
    union() {
        cylinder(h=T, r=R_i);
        translate([0, pin_i_base, T/2])
            rotate([-90,0,0]) cylinder(h=pin_i_tip-pin_i_base, r=d_pin/2);
        translate([0, -pin_i_base, T/2])
            rotate([90,0,0]) cylinder(h=pin_i_tip-pin_i_base, r=d_pin/2);
    }
}

/* ---------- specs ---------- */
if (part == "stand_outer") {
    echo(cadverify_spec = [
        ["bounds", [[-35, -45, 0], [35, 35, 6]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 1000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["stand_base", "material", [[-10, -44, 0], [10, -34, 6]], 0.9],
            ["outer_wall", "thickness", [33, 0, 10], [0, 0, -1], 6.0],
            ["groove_plus_x", "void", [[28.2, -1.8, 1.2], [31.8, 1.8, 5.8]], 0.5],
            ["groove_minus_x", "void", [[-31.8, -1.8, 1.2], [-28.2, 1.8, 5.8]], 0.5]
        ]]
    ]);
    m_stand_outer();
} else if (part == "middle") {
    echo(cadverify_spec = [
        ["bounds", [[-31.5, -28.2, 0], [31.5, 28.2, 6]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 700]]],
        ["overhangs_allowed", [
            ["pin_plus_x bridge", [[27, -2, 1], [32, 2, 5]]],
            ["pin_minus_x bridge", [[-32, -2, 1], [-27, 2, 5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_plus_x", "material", [[29, -1, 2], [31, 1, 4]], 0.9],
            ["middle_wall", "thickness", [25, 0, 10], [0, 0, -1], 6.0],
            ["groove_plus_y", "void", [[-1.8, 21.4, 1.2], [1.8, 25.0, 5.8]], 0.5],
            ["groove_minus_y", "void", [[-1.8, -25.0, 1.2], [1.8, -21.4, 5.8]], 0.5]
        ]]
    ]);
    m_middle();
} else if (part == "inner") {
    echo(cadverify_spec = [
        ["bounds", [[-21.4, -24.7, 0], [21.4, 24.7, 6]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 1000]]],
        ["overhangs_allowed", [
            ["pin_plus_y bridge", [[-2, 20, 1], [2, 25.2, 5]]],
            ["pin_minus_y bridge", [[-2, -25.2, 1], [2, -20, 5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["disc_floor", "thickness", [0, 0, 10], [0, 0, -1], 6.0],
            ["pin_plus_y", "material", [[-1, 22.5, 2], [1, 24.5, 4]], 0.9],
            ["disc_side", "thickness", [30, 0, 3], [-1, 0, 0], 42.8]
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
            [["middle"], [0, 0, -30]],
            [["inner"], [0, 0, -30]]
        ]],
        ["print_in_place", 0.5],
        ["overhangs_allowed", [
            ["pins_middle bridge", [[-32, -2, 1], [32, 2, 5]]],
            ["pins_inner bridge", [[-2, -25.2, 1], [2, 25.2, 5]]]
        ]]
    ]);
    instance("stand_outer", "stand_outer") m_stand_outer();
    instance("middle", "middle") m_middle();
    instance("inner", "inner") m_inner();
}
