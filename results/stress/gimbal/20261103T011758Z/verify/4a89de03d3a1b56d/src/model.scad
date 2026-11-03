// Print-in-place gimbal
// Vertical rings printed upright in place on a plinth stand.
// Outer ring fixed to stand; middle ring pivots about X inside outer;
// inner disc pivots about Z (perpendicular in the ring plane) inside middle.
// At rest all three are coplanar (XZ plane), centre at z=38 in assembly.

part = "assembly"; // [assembly, outer, middle, inner]
cadverify_only = "";

// ---------- parameters (mm) ----------
$fn = 96;
cz = 38;                 // gimbal centre height in assembly
outer_R = 35; outer_r = 28.5; ring_t = 6;
mid_R = 27.9; mid_r = 21.5;
disc_R = 20.9;
gap_ring = outer_r - mid_R;        // 0.6
pin_R = 1.8; socket_R = 2.2;       // 0.4 radial pivot clearance
pin_tip_gap = 0.6;
// A pivots (X): middle pins into outer sockets
a_pin_end = 30.9; a_sock_end = 31.5;
// B pivots (Z): inner pins into middle sockets
b_pin_end = 23.9; b_sock_end = 24.5;

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module cyl_y(r, h) rotate([90,0,0]) cylinder(r=r, h=h, center=true);
module cyl_x(r, h) rotate([0,90,0]) cylinder(r=r, h=h, center=true);

// ---------- outer: ring + plinth stand (local origin = gimbal centre) ----------
module outer_local() {
    difference() {
        union() {
            difference() { cyl_y(outer_R, ring_t); cyl_y(outer_r, ring_t+2); }
            // plinth
            translate([0,0,-cz]) linear_extrude(8) offset(r=4) square([56,28], center=true);
            // raised saddle boss the ring sinks into
            translate([0,0,-cz]) linear_extrude(9.5) offset(r=4) square([24,8], center=true);
        }
        // A sockets (blind, axis X, mouth at inner face x=+-28.5)
        for (s=[-1,1]) translate([s*29.25,0,0]) cyl_x(socket_R, 4.5);
    }
}

// ---------- middle ring (local origin = centre) ----------
module middle_local() {
    difference() {
        union() {
            difference() { cyl_y(mid_R, ring_t); cyl_y(mid_r, ring_t+2); }
            // A pins, axis X, root embedded in ring, tip into outer socket
            for (s=[-1,1]) translate([s*28.45,0,0]) cyl_x(pin_R, 4.9);
        }
        // B sockets (blind, axis Z, mouth at inner face z=+-21.5)
        for (s=[-1,1]) translate([0,0,s*22.75]) cylinder(r=socket_R, h=3.5, center=true);
    }
}

// ---------- inner disc (local origin = centre) ----------
module inner_local() {
    union() {
        cyl_y(disc_R, ring_t);
        // B pins, axis Z
        for (s=[-1,1]) translate([0,0,s*21.45]) cylinder(r=pin_R, h=4.9, center=true);
    }
}

// ---------- dispatch ----------
if (part == "outer") {
    echo(cadverify_spec = [
        ["bounds", [[-35,-18,0],[35,18,73]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["plinth_bottom", "-z", 2000]]],
        ["overhangs_allowed", [
            ["outer ring inner top arch", [[-20,-3,55],[20,3,67]]],
            ["outer ring lower left outer curve", [[-35,-3,3],[-18,3,20]]],
            ["outer ring lower right outer curve", [[18,-3,3],[35,3,20]]],
            ["A pivot sockets", [[-32,-3,34],[32,3,42]]]
        ]],
        ["copies", 1],
        ["details", [
            ["plinth", "material", [[-30,-16,0],[30,16,4]], 0.95],
            ["saddle_boss", "material", [[-14,-6,2],[14,6,8]], 0.95],
            ["ring_top", "material", [[-5,-3,68],[5,3,73]], 0.35],
            ["gimbal_window", "void", [[-15,-2.9,30],[15,2.9,55]], 0.95],
            ["a_socket_right", "hole", [24,0,38], [1,0,0], [[0,4.4],[2.5,4.4]]],
            ["ring_wall_top", "thickness", [0,0,74], [0,0,-1], 6.5],
            ["plinth_floor", "thickness", [25,0,-1], [0,0,1], 8]
        ]]
    ]);
    translate([0,0,cz]) outer_local();
} else if (part == "middle") {
    echo(cadverify_spec = [
        ["bounds", [[-30.9,-3,0],[30.9,3,55.8]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["middle ring inner top arch and B socket end", [[-16,-3,40],[16,3,53]]],
            ["middle ring lower outer curve", [[-20,-3,0],[20,3,14]]],
            ["A pivot pins underside", [[-31,-2,24],[31,2,31]]]
        ]],
        ["copies", 1],
        ["details", [
            ["ring_top", "material", [[-5,-3,50],[5,3,55.8]], 0.35],
            ["centre_window", "void", [[-12,-2.9,16],[12,2.9,40]], 0.95],
            ["a_pin_right", "material", [[27,-1.5,26.4],[30.5,1.5,29.4]], 0.6],
            ["b_socket_top", "hole", [0,0,44], [0,0,1], [[0,4.4],[2.5,4.4]]],
            ["ring_wall_side", "thickness", [10,0,56], [0,0,-1], 7.0]
        ]]
    ]);
    translate([0,0,mid_R]) middle_local();
} else if (part == "inner") {
    echo(cadverify_spec = [
        ["bounds", [[-20.9,-3,0],[20.9,3,47.8]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", []],
        ["overhangs_allowed", [
            ["inner disc lower rim", [[-17,-3,0],[17,3,12]]]
        ]],
        ["copies", 1],
        ["details", [
            ["disc_body", "material", [[-8,-2.9,19.9],[8,2.9,27.9]], 0.95],
            ["b_pin_top", "material", [[-1.5,-1.5,42],[1.5,1.5,47]], 0.6],
            ["disc_thickness", "thickness", [0,-5,23.9], [0,1,0], 6],
            ["disc_face", "thickness", [-5,5,23.9], [0,-1,0], 6]
        ]]
    ]);
    translate([0,0,b_pin_end]) inner_local();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-35,-18,0],[35,18,73]]],
        ["support_faces", [["stand_bottom", "-z", 2000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["middle_turn", ["middle","inner"], "rotate", [0,0,38], [1,0,0], [0,360]],
            ["inner_turn", ["inner"], "rotate", [0,0,38], [0,0,1], [0,360]]
        ]],
        ["assembly_order", [
            [["stand","middle","inner"], [0,0,0]]
        ]],
        ["print_in_place", 0.4],
        ["overhangs_allowed", [
            ["outer ring inner top arch", [[-20,-3,55],[20,3,67]]],
            ["outer ring lower outer curves", [[-35,-3,3],[35,3,20]]],
            ["A pivot sockets and pins", [[-32,-3,34],[32,3,42]]],
            ["middle ring inner top arch", [[-16,-3,52],[16,3,66]]],
            ["middle and inner lower rims in print pose", [[-28,-3,8],[28,3,24]]]
        ]],
        ["held", ["stand","middle","inner"]]
    ]);
    instance("stand", "outer") translate([0,0,cz]) outer_local();
    instance("middle", "middle") translate([0,0,cz]) middle_local();
    instance("inner", "inner") translate([0,0,cz]) inner_local();
}
