cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Part selector: base, wheel, assembly
part = "assembly"; // [base, wheel, assembly]

$fn = 96;

// Parameters
Rt = 25;        // wheel tip radius (50mm across)
Rr = 22;        // wheel root radius
Nteeth = 12;
wheel_t = 6;    // wheel thickness
bore_r = 5.3;   // wheel bore radius (post 5.0 + 0.3 clearance)
post_r = 5;
post_h = 14;    // base bottom to post top
base_t = 4;     // base plate thickness
plate_x = 80;
plate_y = 60;
gap_angle = 37.3333333; // gap center for nominal assembly

module wheel() {
    pts = [ for (k=[0:2*Nteeth-1])
        let(i=floor(k/2),
            a = (k%2==0) ? i*360/Nteeth : i*360/Nteeth+5,
            r = (k%2==0) ? Rr : Rt)
        [r*cos(a), r*sin(a)] ];
    difference() {
        linear_extrude(height=wheel_t, convexity=4)
            polygon(pts);
        translate([0,0,-0.1])
            cylinder(h=wheel_t+0.2, r=bore_r);
    }
}

module base() {
    difference() {
        union() {
            // plate
            translate([-plate_x/2, -plate_y/2, 0])
                cube([plate_x, plate_y, base_t]);
            // post
            cylinder(h=post_h, r=post_r);
            // pawl backbone (tall)
            translate([27, -20, 0])
                cube([1.5, 20.75, 10]);
            // pawl finger (tall, radial)
            translate([24.2, -0.75, 0])
                cube([4.3, 1.5, 10]);
            // anchor block (full height fixation)
            translate([26, -26, 0])
                cube([10, 6, 10]);
        }
        // slot voids through plate (z -0.1..4.1)
        translate([26, -20, -0.1]) cube([1, 19.25, 4.2]);      // west of backbone
        translate([28.5, -20, -0.1]) cube([1, 20.75, 4.2]);    // east of backbone
        translate([23.2, 0.75, -0.1]) cube([6.3, 1, 4.2]);      // north
        translate([23.2, -1.75, -0.1]) cube([3.8, 1, 4.2]);     // south of finger tip
        translate([23.2, -1.75, -0.1]) cube([1, 3.5, 4.2]);     // west of tip
    }
}

if (part == "wheel") {
    echo(cadverify_spec = [
        ["bounds", [[-25, -25, 0], [25, 25, 6]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bottom", "-z", 1000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["hub", "material", [[5, 5, 0.5], [10, 10, 5.5]], 0.9],
            ["bore", "hole", [0, 0, 7], [0, 0, -1], [[0, 10.6], [5, 10.6]]],
            ["rim", "thickness", [15, 0, 7], [0, 0, -1], 6],
            ["teeth", "view", [[20, -15, 0], [25, 15, 6]]]
        ]]
    ]);
    wheel();
} else if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -30, 0], [40, 30, 14]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bottom", "-z", 4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["pawl_arm", "material", [[27.1, -10, 4.1], [28.4, -5, 9.9]], 0.9],
            ["slot", "void", [[26.1, -15, 0.5], [26.9, -5, 3.5]], 0.9],
            ["base_floor", "thickness", [-20, 20, -1], [0, 0, 1], 4],
            ["pawl_tip", "view", [[23, -2, 4], [26, 2, 10]]]
        ]]
    ]);
    base();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -30, 0], [40, 30, 14]]],
        ["support_faces", [["table", "-z", 4000]]],
        ["motions", [
            ["free", ["wheel1"], "rotate", [0, 0, 4], [0, 0, 1], [0, -30]],
            ["locked", ["wheel1"], "rotate", [0, 0, 4], [0, 0, 1], [0, 5]]
        ]],
        ["assembly_order", [
            [["base1"], [0, 0, 0]],
            [["wheel1"], [0, 0, -1]]
        ]]
    ]);
    instance("base1", "base") base();
    instance("wheel1", "wheel") translate([0, 0, 4]) rotate([0, 0, -gap_angle]) wheel();
}
