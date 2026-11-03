/* Ratchet wheel with spring pawl - desk demo, PLA, no supports */
part = "assembly"; // [wheel:Wheel, base:Base, assembly:Assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
Rtip = 25;          // wheel outer radius (50mm across)
Rroot = 23;         // wheel root radius (tooth height 2mm)
wheel_t = 6;        // wheel thickness
hole_D = 12.6;      // wheel centre hole
post_D = 12;        // base post diameter
post_h = 8;         // post height above base top
base_t = 6;         // base plate thickness
base_x = 80;
base_y = 60;
wheel_cx = -10;     // wheel centre in base/assembly XY
wheel_cy = 0;
wheel_gap = 0.2;    // wheel bottom above base top
pawl_rad = 24.2;    // pawl tip radius from wheel centre (0.8 inside tip circle)
pawl_tip_x = wheel_cx + pawl_rad; // 14.2
pawl_tip_y = 0;
beam_x0 = 16.5; beam_x1 = 19.5;   // flexible arm (3mm wide)
beam_y0 = -22; beam_y1 = 3;       // arm length ~25mm
slot_w = 1.5;
wheel_lift_z = base_t + wheel_gap; // 6.2 wheel bottom in assembly
post_top_z = base_t + post_h;      // 14
pawl_h = 6;                        // pawl height 6..12

// tooth angles: shallow root->tip 20deg, tip 4deg, steep tip->root 6deg
function wheel_pts() = [
    for(k=[0:11]) for(j=[0:2])
        j==0 ? [Rroot*cos(k*30), Rroot*sin(k*30)]
      : j==1 ? [Rtip*cos(k*30+20), Rtip*sin(k*30+20)]
             : [Rtip*cos(k*30+24), Rtip*sin(k*30+24)]
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
            // post
            translate([wheel_cx, wheel_cy, base_t]) cylinder(d=post_D, h=post_h, $fn=64);
            // pawl tooth on top of arm free end (triangle prism)
            linear_extrude(height=pawl_h, convexity=2)
                polygon(points=[[pawl_tip_x, pawl_tip_y],[beam_x0, 1.5],[beam_x0, -1.5]]);
            // note: arm beam itself is the plate material between slots (0..base_t),
            // pawl sits with its base at z=base_t
            translate([0,0,base_t]) linear_extrude(height=0.01) square([0.01,0.01]); // keep union non-empty
        }
        // U-slot freeing the arm (through plate)
        // west slot
        translate([beam_x0-slot_w, beam_y0, -1]) cube([slot_w, beam_y1-beam_y0, base_t+2]);
        // east slot
        translate([beam_x1, beam_y0, -1]) cube([slot_w, beam_y1-beam_y0, base_t+2]);
        // north slot (connects west+east, frees north end)
        translate([beam_x0-slot_w, beam_y1, -1]) cube([(beam_x1+slot_w)-(beam_x0-slot_w), slot_w, base_t+2]);
    }
    // pawl tooth base is at z=base_t: move it up (it was built at 0..pawl_h in union above? fix)
}

// fix: rebuild base correctly with pawl at right z
module base_correct() {
    difference() {
        union() {
            translate([-base_x/2, -base_y/2, 0]) cube([base_x, base_y, base_t]);
            translate([wheel_cx, wheel_cy, base_t]) cylinder(d=post_D, h=post_h, $fn=64);
            translate([0,0,base_t]) linear_extrude(height=pawl_h, convexity=2)
                polygon(points=[[pawl_tip_x, pawl_tip_y],[beam_x0, 1.5],[beam_x0, -1.5]]);
        }
        translate([beam_x0-slot_w, beam_y0, -1]) cube([slot_w, beam_y1-beam_y0, base_t+2]);
        translate([beam_x1, beam_y0, -1]) cube([slot_w, beam_y1-beam_y0, base_t+2]);
        translate([beam_x0-slot_w, beam_y1, -1]) cube([(beam_x1+slot_w)-(beam_x0-slot_w), slot_w, base_t+2]);
    }
}

module assembly() {
    instance("base_inst", "base", 1) base_correct();
    // wheel rotated -4.2deg so gullet centre aligns with pawl tip (east)
    instance("wheel_inst", "wheel", 1)
        translate([wheel_cx, wheel_cy, wheel_lift_z]) rotate([0,0,-4.2]) wheel();
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
        ["tooth0", "material", [[22.5, 8.0, 0], [24.0, 10.0, wheel_t]], 0.5],
        ["tooth1", "material", [[-2.0, 23.0, 0], [2.0, 25.0, wheel_t]], 0.3],
        ["tooth2", "material", [[-24.0, 8.0, 0], [-22.0, 10.5, wheel_t]], 0.3]
    ]]
];

base_spec = [
    ["bounds", [[-base_x/2, -base_y/2, 0], [base_x/2, base_y/2, post_top_z]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed", "-z", 2000]]],
    ["overhangs_allowed", [["pawl bridges slot", [[13.5, -2, 5.8], [17.5, 2, 6.2]]]]],
    ["copies", 1],
    ["details", [
        ["plate_thick", "thickness", [0, -28, base_t+4], [0, 0, -1], base_t],
        ["post_dia", "thickness", [wheel_cx-10, wheel_cy, base_t+4], [1, 0, 0], post_D],
        ["post_height", "thickness", [wheel_cx, wheel_cy, post_top_z+4], [0, 0, -1], post_top_z],
        ["arm_width", "thickness", [beam_x0-0.8, -10, 3], [1, 0, 0], beam_x1-beam_x0],
        ["slot_gap", "void", [[beam_x0-slot_w, -20, 0], [beam_x0, -10, base_t]], 0.8],
        ["pawl_tip", "material", [[15, -0.5, base_t+1], [16, 0.5, base_t+5]], 0.8],
        ["pawl_height", "thickness", [15.5, 0, base_t+pawl_h+3], [0, 0, -1], pawl_h]
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
    base_correct();
} else {
    echo(cadverify_spec = assembly_spec);
    assembly();
}
