/* Ratchet wheel with spring pawl - desk demo, PLA, 0.4 mm nozzle, no supports.
   Wheel (~50 mm, 12 teeth) turns on a post; the pawl is part of the base on a
   flexible arm cut from the plate. Free way is clockwise seen from above
   (negative rotation about +Z). */
part = "assembly"; // [wheel:Wheel, base:Base, assembly:Assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
Rtip = 25;          // wheel outer radius (50 mm across)
Rroot = 23;         // wheel root radius (tooth height 2 mm)
wheel_t = 6;        // wheel thickness
hole_D = 12.6;      // wheel centre hole diameter
post_D = 12;        // base post diameter (0.6 mm play on diameter)
post_h = 8;         // post height above base top
base_t = 6;         // base plate thickness
base_x = 80;
base_y = 60;
wheel_cx = -10;     // wheel centre in base/assembly XY
wheel_cy = 0;
wheel_gap = 0.2;    // wheel bottom above base top
wheel_lift_z = base_t + wheel_gap;   // 6.2 wheel bottom in assembly
post_top_z = base_t + post_h;        // 14
pawl_tip_x = 14.2;  // pawl tip: 0.8 inside tip circle, 1.2 off root
beam_x0 = 16.5; beam_x1 = 19.5;      // flexible arm: 3 mm wide ...
beam_y0 = -22; beam_y1 = 3;          // ... 25 mm long, fixed south, free north
slot_w = 1.5;       // slot width (clears a 0.4 mm nozzle)
pawl_h = 6;         // pawl height above plate (meets wheel band 6.2..12.2)
rest_angle = 0;     // gullet bottom centred on pawl tip

// tooth k: root at 30k, shallow rise to tip at 30k+24, tip land to +27,
// steep drop to root at +30. Shallow face cams the pawl out (free way),
// steep face pushes along the arm (locks reverse).
function wheel_pts() = [
    for(k=[0:11]) for(j=[0:2])
        j==0 ? [Rroot*cos(k*30), Rroot*sin(k*30)]
      : j==1 ? [Rtip*cos(k*30+24), Rtip*sin(k*30+24)]
             : [Rtip*cos(k*30+27), Rtip*sin(k*30+27)]
];

module wheel() {
    difference() {
        linear_extrude(height=wheel_t, convexity=4)
            polygon(points=wheel_pts());
        translate([0,0,-1]) cylinder(d=hole_D, h=wheel_t+2, $fn=64);
    }
}

module base() {
    difference() {
        union() {
            // plate
            translate([-base_x/2, -base_y/2, 0]) cube([base_x, base_y, base_t]);
            // post the wheel turns on
            translate([wheel_cx, wheel_cy, base_t]) cylinder(d=post_D, h=post_h, $fn=64);
            // pawl wedge: tip near the wheel, root fused onto the free end of the arm
            translate([0,0,base_t]) linear_extrude(height=pawl_h, convexity=2)
                polygon(points=[[pawl_tip_x, 0],[beam_x1, 2.2],[beam_x1, -2.2]]);
        }
        // U-slot freeing the arm (one connected through opening) + window under pawl tip
        translate([beam_x0-slot_w, beam_y0, -1]) cube([slot_w, 19, base_t+2]); // west x15..16.5 y-22..-3
        translate([beam_x1, beam_y0, -1]) cube([slot_w, 26.5, base_t+2]);      // east x19.5..21 y-22..4.5
        translate([beam_x0-slot_w, beam_y1, -1]) cube([6, slot_w, base_t+2]);  // north x15..21 y3..4.5
        translate([12, -3, -1]) cube([4.5, 6, base_t+2]);                       // window x12..16.5 y-3..3
    }
}

module assembly() {
    instance("base_inst", "base", 1) base();
    instance("wheel_inst", "wheel", 1)
        translate([wheel_cx, wheel_cy, wheel_lift_z]) rotate([0,0,rest_angle]) wheel();
}

// ---------- specs (computed from parameters) ----------
wheel_spec = [
    ["bounds", [[-Rtip, -Rtip, 0], [Rtip, Rtip, wheel_t]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed", "-z", 800]]],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
        ["axle_hole", "hole", [0, 0, wheel_t+4], [0, 0, -1], [[0, hole_D], [wheel_t, hole_D]]],
        ["rim_thick", "thickness", [15, 0, wheel_t+4], [0, 0, -1], wheel_t],
        ["tooth0", "material", [[22.05, 7.71, 0], [23.05, 8.71, wheel_t]], 0.5],
        ["tooth4", "material", [[-18.89, 14.93, 0], [-17.89, 15.93, wheel_t]], 0.5],
        ["tooth8", "material", [[-4.67, -24.14, 0], [-3.67, -23.14, wheel_t]], 0.5]
    ]]
];

base_spec = [
    ["bounds", [[-base_x/2, -base_y/2, 0], [base_x/2, base_y/2, post_top_z]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed", "-z", 2000]]],
    ["overhangs_allowed", [["pawl bridges slot", [[14, -1.5, 5.9], [17, 1.5, 6.1]]]]],
    ["copies", 1],
    ["details", [
        ["plate_thick", "thickness", [0, -28, base_t+4], [0, 0, -1], base_t],
        ["post_dia", "thickness", [wheel_cx-10, wheel_cy, base_t+post_h-1], [1, 0, 0], post_D],
        ["post_core", "material", [[wheel_cx-2, -2, 8], [wheel_cx+2, 2, 13]], 0.8],
        ["arm_width", "thickness", [beam_x0-0.75, -16, 3], [1, 0, 0], beam_x1-beam_x0],
        ["arm_full", "material", [[17, -20, 0], [19, -12, base_t]], 0.8],
        ["slot_gap", "void", [[beam_x0-slot_w, -20, 0], [beam_x0, -10, base_t]], 0.8],
        ["window_void", "void", [[12.5, -2.5, 0], [16, 2.5, base_t]], 0.8],
        ["pawl_tip", "material", [[14.9, -0.2, 8], [15.7, 0.2, 11]], 0.5],
        ["pawl_height", "thickness", [14.5, 0, base_t+pawl_h+3], [0, 0, -1], pawl_h]
    ]]
];

assembly_spec = [
    ["bounds", [[-base_x/2, -base_y/2, 0], [base_x/2, base_y/2, post_top_z]]],
    ["support_faces", [["desk", "-z", 2000]]],
    ["allowed_interferences", []],
    ["motions", [
        ["spin_free", ["wheel_inst"], "rotate", [wheel_cx, wheel_cy, wheel_lift_z], [0, 0, 1], [0, -360],
            ["flex", [["wheel_inst", "base_inst", 0.9, "pawl clicks over teeth"]]]]
    ]],
    ["assembly_order", [
        [["base_inst"], [0, 0, 0]],
        [["wheel_inst"], [0, 0, -1]]
    ]]
];

if (part == "wheel") {
    echo(cadverify_spec = wheel_spec);
    wheel();
} else if (part == "base") {
    echo(cadverify_spec = base_spec);
    base();
} else {
    echo(cadverify_spec = assembly_spec);
    assembly();
}
