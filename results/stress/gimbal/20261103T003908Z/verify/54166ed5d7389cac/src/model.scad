/* Print-in-place gimbal: outer ring on stand, middle ring, inner disc.
   Print orientation: flat (XY), +Z up, all bottoms on bed (Z=0).
   Outer OD 70mm. Clearances 0.5mm for PLA 0.4mm nozzle.
   Pivots: outer-middle about X (side pins), middle-disc about Y (front/back pins).
   Full 360 deg each, no supports (pin/socket bridges <=5mm declared).
*/
part = "assembly"; // [frame:Frame, middle:Middle, disc:Disc, assembly:Assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters ----
R_out_out = 35;      // outer ring outer radius (70 across)
R_out_in  = 30;      // outer ring inner radius
T         = 5;       // ring/disc thickness in Z
Zc        = 2.5;     // pivot axis height (T/2)
R_mid_out = 29.5;    // middle outer (0.5 gap to outer)
R_mid_in  = 25.5;    // middle inner (4 wall)
R_disc    = 25.0;    // disc radius (0.5 gap to middle)
pin_r  = 2.0;        // pin radius (d=4)
sock_r = 2.5;        // socket radius (d=5, 0.5 clearance)
foot_x = 4;          // half width of stand feet in X
foot_y0 = 33; foot_y1 = 41; // feet Y extents (+ side), mirrored for -
pin_mid_x0 = 27.5; pin_mid_x1 = 32;   // middle->outer pin X span (+ side)
sock_out_x0 = 29.9; sock_out_x1 = 33.9; // outer socket X span (+ side)
sock_mid_y0 = 25.4; sock_mid_y1 = 29.4; // middle socket Y span (+ side)
pin_disc_y0 = 23; pin_disc_y1 = 27;     // disc->middle pin Y span (+ side)

$fn = 128;

module frame() {
    difference() {
        union() {
            // outer ring
            difference() {
                cylinder(h=T, r=R_out_out);
                translate([0,0,-0.1]) cylinder(h=T+0.2, r=R_out_in);
            }
            // small stand: two feet at +-Y
            translate([-foot_x, foot_y0, 0]) cube([foot_x*2, foot_y1-foot_y0, T]);
            translate([-foot_x, -foot_y1, 0]) cube([foot_x*2, foot_y1-foot_y0, T]);
        }
        // pivot sockets about X (side bores, blind)
        translate([(sock_out_x0+sock_out_x1)/2, 0, Zc]) rotate([0,90,0]) cylinder(h=sock_out_x1-sock_out_x0, r=sock_r, center=true, $fn=48);
        translate([-(sock_out_x0+sock_out_x1)/2, 0, Zc]) rotate([0,90,0]) cylinder(h=sock_out_x1-sock_out_x0, r=sock_r, center=true, $fn=48);
    }
}

module middle() {
    difference() {
        union() {
            difference() {
                cylinder(h=T, r=R_mid_out);
                translate([0,0,-0.1]) cylinder(h=T+0.2, r=R_mid_in);
            }
            // pivot pins about X (protrude into outer sockets)
            translate([(pin_mid_x0+pin_mid_x1)/2, 0, Zc]) rotate([0,90,0]) cylinder(h=pin_mid_x1-pin_mid_x0, r=pin_r, center=true, $fn=48);
            translate([-(pin_mid_x0+pin_mid_x1)/2, 0, Zc]) rotate([0,90,0]) cylinder(h=pin_mid_x1-pin_mid_x0, r=pin_r, center=true, $fn=48);
        }
        // pivot sockets about Y (for disc pins, blind)
        translate([0, (sock_mid_y0+sock_mid_y1)/2, Zc]) rotate([90,0,0]) cylinder(h=sock_mid_y1-sock_mid_y0, r=sock_r, center=true, $fn=48);
        translate([0, -(sock_mid_y0+sock_mid_y1)/2, Zc]) rotate([90,0,0]) cylinder(h=sock_mid_y1-sock_mid_y0, r=sock_r, center=true, $fn=48);
    }
}

module disc() {
    union() {
        cylinder(h=T, r=R_disc);
        // pivot pins about Y
        translate([0, (pin_disc_y0+pin_disc_y1)/2, Zc]) rotate([90,0,0]) cylinder(h=pin_disc_y1-pin_disc_y0, r=pin_r, center=true, $fn=48);
        translate([0, -(pin_disc_y0+pin_disc_y1)/2, Zc]) rotate([90,0,0]) cylinder(h=pin_disc_y1-pin_disc_y0, r=pin_r, center=true, $fn=48);
    }
}

if (part == "frame") {
    echo(cadverify_spec = [
        ["bounds", [[-R_out_out, -foot_y1, 0], [R_out_out, foot_y1, T]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 800]]],
        ["overhangs_allowed", [
            ["pin bridge +X", [[29, -3, 0], [34, 3, T]]],
            ["pin bridge -X", [[-34, -3, 0], [-29, 3, T]]]
        ]],
        ["copies", 1],
        ["details", [
            ["stand+", "material", [[-foot_x, foot_y0, 0], [foot_x, foot_y1, T]], 0.9],
            ["stand-", "material", [[-foot_x, -foot_y1, 0], [foot_x, -foot_y0, T]], 0.9],
            ["gap1+", "void", [[-1, 29.55, 0], [1, 29.95, T]], 0.8],
            ["wall", "thickness", [36, 0, Zc], [-1, 0, 0], 5],
            ["floor", "thickness", [0, 32.5, -1], [0, 0, 1], 5],
            ["socket+X", "hole", [29.7, 0, Zc], [1, 0, 0], [[0, 5], [3, 5]]],
            ["socket-X", "hole", [-29.7, 0, Zc], [-1, 0, 0], [[0, 5], [3, 5]]]
        ]]
    ]);
    frame();
} else if (part == "middle") {
    echo(cadverify_spec = [
        ["bounds", [[-pin_mid_x1, -R_mid_out, 0], [pin_mid_x1, R_mid_out, T]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 400]]],
        ["overhangs_allowed", [
            ["pin+X", [[27, -2.5, 0], [32, 2.5, T]]],
            ["pin-X", [[-32, -2.5, 0], [-27, 2.5, T]]],
            ["socket+Y", [[-3, 25, 0], [3, 29.5, T]]],
            ["socket-Y", [[-3, -29.5, 0], [3, -25, T]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin+X", "material", [[29.5, -1.5, 1], [32, 1.5, 4]], 0.5],
            ["pin-X", "material", [[-32, -1.5, 1], [-29.5, 1.5, 4]], 0.5],
            ["gap2", "void", [[25.05, -1, 0], [25.45, 1, T]], 0.8],
            ["wall", "thickness", [30, 0, Zc], [-1, 0, 0], 4],
            ["floor", "thickness", [0, 27.5, -1], [0, 0, 1], 5],
            ["socket+Y", "hole", [0, 25.2, Zc], [0, 1, 0], [[0, 5], [3, 5]]],
            ["socket-Y", "hole", [0, -25.2, Zc], [0, -1, 0], [[0, 5], [3, 5]]]
        ]]
    ]);
    middle();
} else if (part == "disc") {
    echo(cadverify_spec = [
        ["bounds", [[-R_disc, -pin_disc_y1, 0], [R_disc, pin_disc_y1, T]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 1000]]],
        ["overhangs_allowed", [
            ["pin+Y", [[-2.5, 23, 0], [2.5, 27, T]]],
            ["pin-Y", [[-2.5, -27, 0], [2.5, -23, T]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin+Y", "material", [[-1.5, 23, 1], [1.5, 27, 4]], 0.5],
            ["pin-Y", "material", [[-1.5, -27, 1], [1.5, -23, 4]], 0.5],
            ["gap2x", "void", [[25.05, -1, 0], [25.45, 1, T]], 0.8],
            ["floor", "thickness", [0, 0, -1], [0, 0, 1], 5],
            ["edge", "thickness", [26, 0, Zc], [-1, 0, 0], 50]
        ]]
    ]);
    disc();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-R_out_out, -foot_y1, 0], [R_out_out, foot_y1, T]]],
        ["motions", [
            ["swing_middle", ["middle", "disc"], "rotate", [0, 0, Zc], [1, 0, 0], [0, 360]],
            ["spin_disc", ["disc"], "rotate", [0, 0, Zc], [0, 1, 0], [0, 360]]
        ]],
        ["print_in_place", 0.5],
        ["overhangs_allowed", [
            ["pin bridge X", [[-34, -3, 0], [34, 3, T]]],
            ["pin bridge Y", [[-3, -29.5, 0], [3, 29.5, T]]]
        ]],
        ["held", ["middle", "disc"]]
    ]);
    instance("frame", "frame") frame();
    instance("middle", "middle") middle();
    instance("disc", "disc") disc();
}
