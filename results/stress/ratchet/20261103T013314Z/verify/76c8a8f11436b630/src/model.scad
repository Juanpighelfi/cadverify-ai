/* Ratchet wheel with spring pawl - PLA, 0.4 nozzle, no supports */
// Wheel ~50mm dia, 12 teeth. Free clockwise (from above), locks CCW.
// Print orientation: both parts flat, +Z up, bottom on bed.

/* [Part] */
part = "assembly"; // [wheel, base, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
Ro = 25;            // wheel tip radius (dia 50)
Rr = 23.5;          // wheel root radius (tooth height 1.5)
Nteeth = 12;
pitch = 360/Nteeth; // 30
gentle_span = 26;   // valley->tip CCW (gentle ramp)
wheel_t = 8;        // wheel thickness
bore_d = 12.6;      // wheel bore
post_d = 12;        // post diameter
post_h = 10;        // post height above base top
base_x = 90;
base_y = 70;
base_t = 6;
wheel_cx = -10;     // post/wheel centre in base coords
wheel_cy = 0;
base_top = base_t;  // 6
// pawl / arm
beam_x0 = 15.5; beam_x1 = 17.5;   // beam 2mm thick in X
beam_y0 = -30; beam_y1 = 3;       // beam length
beam_z0 = 6; beam_z1 = 14;        // beam height 8
tip_x = 14.0;       // pawl tip westmost (1.0 inside tip circle: 25-24=1.0)

$fn = 128;

// ---- wheel: centred at (0,0), bottom z=0 ----
module wheel() {
    difference() {
        linear_extrude(height = wheel_t, convexity = 4)
            polygon(points = [ for (i = [0:Nteeth-1]) each [
                [Rr*cos(i*pitch), Rr*sin(i*pitch)],
                [Ro*cos(i*pitch+gentle_span), Ro*sin(i*pitch+gentle_span)],
                [Rr*cos(i*pitch+gentle_span), Rr*sin(i*pitch+gentle_span)]
            ]]);
        translate([0,0,-1]) cylinder(d = bore_d, h = wheel_t+2);
    }
}

// ---- base: plate centred at origin, bottom z=0, post at (wheel_cx,wheel_cy) ----
module base() {
    union() {
        // plate
        translate([-base_x/2, -base_y/2, 0]) cube([base_x, base_y, base_t]);
        // post
        translate([wheel_cx, wheel_cy, base_top]) cylinder(d = post_d, h = post_h);
        // anchor block
        translate([10, -35, 6]) cube([14, 11, 8]);
        // flexible beam (2mm thick, ~33mm long, 8mm tall)
        translate([beam_x0, beam_y0, beam_z0]) cube([beam_x1-beam_x0, beam_y1-beam_y0, beam_z1-beam_z0]);
        // pawl tip wedge: tip (tip_x,0), overlap 0.5 into beam; north ramp, south flat
        linear_extrude(height = 8, convexity = 2)
            polygon(points = [[tip_x,0],[16,0],[16,3]]);
        // shift pawl wedge up to beam height (extrude from 0 -> translate)
    }
}

// pawl wedge is extruded 0..8, need to lift to 6..14: wrap
module base_fixed() {
    union() {
        translate([-base_x/2, -base_y/2, 0]) cube([base_x, base_y, base_t]);
        translate([wheel_cx, wheel_cy, base_top]) cylinder(d = post_d, h = post_h);
        translate([10, -35, 6]) cube([14, 11, 8]);
        translate([beam_x0, beam_y0, beam_z0]) cube([beam_x1-beam_x0, beam_y1-beam_y0, beam_z1-beam_z0]);
        translate([0,0,6]) linear_extrude(height = 8, convexity = 2)
            polygon(points = [[tip_x,0],[16,0],[16,3]]);
    }
}

// ---- specs ----
if (part == "wheel") echo(cadverify_spec = [
    ["bounds", [[-Ro, -Ro, 0], [Ro, Ro, wheel_t]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed", "-z", 1000]]],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
        ["bore", "hole", [0, 0, 10], [0, 0, -1], [[0, bore_d], [wheel_t-0.5, bore_d]]],
        ["rim", "thickness", [0, 15, 10], [0, 0, -1], wheel_t],
        ["tooth", "material", [[21.5, 9.5, 0], [23.5, 11.5, wheel_t]], 0.4],
        ["teeth", "view", [[20, -25, 0], [Ro, 25, wheel_t]]]
    ]]
]);

if (part == "base") echo(cadverify_spec = [
    ["bounds", [[-base_x/2, -base_y/2, 0], [base_x/2, base_y/2, base_top+post_h]]],
    ["bodies", 1],
    ["support_faces", [["bed", "-z", 4000]]],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
        ["plate", "thickness", [-30, 20, 10], [0, 0, -1], base_t],
        ["post", "material", [[wheel_cx-6, wheel_cy-6, base_top], [wheel_cx+6, wheel_cy+6, base_top+post_h]], 0.5],
        ["arm", "material", [[beam_x0, beam_y0, beam_z0], [beam_x1, beam_y1, beam_z1]], 0.9],
        ["pawl_tip", "view", [[14.0, -1, 6], [16, 3.5, 14]]]
    ]]
]);

if (part == "assembly") echo(cadverify_spec = [
    ["bounds", [[-base_x/2, -base_y/2, 0], [base_x/2, base_y/2, base_top+post_h]]],
    ["motions", [
        ["click", ["wheel1"], "rotate", [wheel_cx, wheel_cy, base_top], [0, 0, 1], [0, -360],
            ["flex", [["wheel1", "base1", 1.0, "pawl flexes over teeth"]]]]
    ]],
    ["assembly_order", [
        [["base1"], [0, 0, 0]],
        [["wheel1"], [0, 0, -30], ["flex", [["wheel1", "base1", 1.0, "pawl snaps aside as rim passes"]]]]
    ]]
]);

// ---- geometry dispatch ----
if (part == "wheel") wheel();
else if (part == "base") base_fixed();
else if (part == "assembly") {
    instance("base1", "base") base_fixed();
    instance("wheel1", "wheel") translate([wheel_cx, wheel_cy, base_top]) wheel();
}
