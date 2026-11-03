// Knob for potentiometer 6mm D-shaft, M3 nut trap, set screw hole
// PLA, 0.4mm nozzle, no supports, print orientation +Z up, bottom on bed

part = "knob"; // [knob, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
R_out = 15;        // max radius incl ribs -> ~30 across
R_base = 14;       // base cylinder radius
R_bot = 13.5;      // bottom face radius (chamfer)
R_top = 12.5;      // top face radius (chamfer)
H = 18;            // total height
H_bot = 0.5;       // bottom chamfer height
H_topc = 1.5;      // top chamfer height
H_straight_bot = 0.5;
H_straight_top = 16.5;

hole_R = 3.15;     // D-hole radius (6.3 dia, +0.15 clearance)
hole_flat = 1.65;  // D-hole flat plane y (shaft 1.5 + 0.15)
hole_depth = 15;   // D-hole depth from bottom
hole_top = 15;

screw_r = 1.5;     // 3mm screw hole radius
screw_z = 6;       // screw axis height
screw_x = 0;

nut_AF = 5.5;
nut_T = 2.4;
pocket_AF = 5.8;   // +0.3 clearance
pocket_T = 2.7;    // +0.3 clearance
pocket_R = 5.8/1.7320508; // corner radius 3.348
nut_y = 8;
nut_z = 6;

n_ribs = 36;

module knob() {
    difference() {
        union() {
            // bottom chamfer
            translate([0,0,0]) cylinder(r1=R_bot, r2=R_base, h=H_bot, $fn=128);
            // straight section (overlap to avoid coincident faces)
            translate([0,0,H_straight_bot-0.01]) cylinder(r=R_base, h=(H_straight_top-H_straight_bot)+0.02, $fn=128);
            // top chamfer 45deg
            translate([0,0,H_straight_top]) cylinder(r1=R_base, r2=R_top, h=H_topc, $fn=128);
            // knurl ribs: vertical, 36x
            for (a=[0:10:350]) rotate([0,0,a]) translate([13.9,-0.6,0.5]) cube([1.1,1.2,16.0]);
        }
        // D-hole: cylinder r=hole_R clipped at y<=hole_flat, from bottom to hole_top
        intersection() {
            translate([0,0,-0.1]) cylinder(r=hole_R, h=hole_top+0.2, $fn=64);
            translate([-4,-4,-0.2]) cube([8, hole_flat+4, hole_top+0.4]);
        }
        // screw cross hole dia 3 along Y at (0,*,screw_z), from inside shaft to outside
        translate([screw_x, 6, screw_z]) rotate([90,0,0]) cylinder(r=screw_r, h=22, center=true, $fn=48);
        // hex nut pocket, axis Y, flats top/bottom, centered at (0,nut_y,nut_z)
        translate([0,nut_y,nut_z]) rotate([90,0,0])
            linear_extrude(height=pocket_T, center=true)
                polygon(points=[[pocket_R,0],[pocket_R/2,pocket_AF/2],[-pocket_R/2,pocket_AF/2],[-pocket_R,0],[-pocket_R/2,-pocket_AF/2],[pocket_R/2,-pocket_AF/2]]);
        // nut entry slot from +X side, rectangular, same cross-section as pocket thickness
        translate([0, nut_y-pocket_T/2, nut_z-pocket_AF/2]) cube([16, pocket_T, pocket_AF]);
        // pointer groove on top, along +Y, 1.2 wide, 1 deep, y 2..12
        translate([-0.6, 2, 17]) cube([1.2, 10, 1.2]);
    }
}

module shaft() {
    // 6mm D-shaft, 4.5 across flat (flat at y=1.5), length 20, tip at z=12, bottom at -8
    intersection() {
        translate([0,0,-8]) cylinder(r=3, h=20, $fn=64);
        translate([-4,-4,-9]) cube([8, 5.5, 22]);
    }
}

module nut_m3() {
    Rnut = 5.5/1.7320508;
    difference() {
        translate([0,nut_y,nut_z]) rotate([90,0,0])
            linear_extrude(height=nut_T, center=true)
                polygon(points=[[Rnut,0],[Rnut/2,2.75],[-Rnut/2,2.75],[-Rnut,0],[-Rnut/2,-2.75],[Rnut/2,-2.75]]);
        translate([0,nut_y,nut_z]) rotate([90,0,0]) cylinder(r=1.5, h=3.2, center=true, $fn=32);
    }
}

if (part == "knob") {
    knob();
    echo(cadverify_spec = [
        ["bounds", [[-R_out-0.1, -R_out-0.1, 0], [R_out+0.1, R_out+0.1, H]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bottom", "-z", 500]]],
        ["overhangs_allowed", [
            ["d_hole ceiling bridge dia 6.3", [[-3.5, -3.5, hole_top-0.5], [3.5, 2.0, hole_top+0.5]]],
            ["nut pocket and entry slot ceiling bridge 2.7mm", [[-3.6, nut_y-1.5, nut_z+2.2], [15.0, nut_y+1.5, nut_z+3.2]]],
            ["cross hole bridge dia 3", [[screw_x-1.6, -3.5, screw_z+0.8], [screw_x+1.6, 15.2, screw_z+1.7]]]
        ]],
        ["copies", 1],
        ["details", [
            ["knurl_rib", "material", [[14.0, -0.4, 5], [14.8, 0.4, 10]], 0.9],
            ["nut_pocket", "void", [[-3.3, nut_y-1.3, nut_z-2.7], [3.3, nut_y+1.3, nut_z+2.7]], 0.6],
            ["nut_entry", "void", [[4, nut_y-1.3, nut_z-2.7], [12, nut_y+1.3, nut_z+2.7]], 0.9],
            ["d_hole", "void", [[-2, -2, 1], [2, 1, 10]], 0.9],
            ["screw_hole", "hole", [[0, 16, screw_z]], [[0, -1, 0]], [[0, 3], [4, 3]]],
            ["side_wall", "thickness", [[20, 0, 8]], [[-1, 0, 0]], 8],
            ["top_floor", "thickness", [[0, 0, 25]], [[0, 0, -1]], 2.5],
            ["pointer", "view", [[-0.6, 2, 17], [0.6, 12, 18.2]]]
        ]]
    ]);
} else if (part == "assembly") {
    instance("knob1", "knob") knob();
    instance("shaft1", "external") shaft();
    instance("nut1", "external") nut_m3();
    echo(cadverify_spec = [
        ["bounds", [[-R_out-0.1, -R_out-0.1, -8], [R_out+0.1, R_out+0.1, H]]],
        ["allowed_interferences", []],
        ["assembly_order", [
            [["knob1"], [0, 0, 0]],
            [["shaft1"], [0, 0, 1]],
            [["nut1"], [-1, 0, 0]]
        ]]
    ]);
}
