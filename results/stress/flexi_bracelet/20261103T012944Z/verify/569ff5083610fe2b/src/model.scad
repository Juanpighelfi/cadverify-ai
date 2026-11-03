part = "link"; // [link, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
pitch = 18;          // pin-to-bore distance (10 links = 180mm)
link_w = 12;         // width (Y)
link_t = 5;          // thickness (Z)
pin_d = 4;           // pin shaft diameter
bore_d = 4.6;        // bore diameter (0.3 radial clearance)
cap_d = 6;           // cap diameter
cap_h = 1;           // cap thickness
kn_out_d = 7.6;      // knuckle outer diameter (1.5 wall)
cap_cav_d = 6.6;     // cap clearance diameter (0.3 radial)
neck_w = 2;          // neck width
neck_t = 0.8;        // neck thickness (central only)
slot_half = 65;      // slot half-angle (deg), allows +-30 deg swing
yoke_west = 6;       // yoke west edge (local X)
yoke_east = 19;      // yoke east extent (local X)
$fn = 64;

module link_geom() {
    bore_x = pitch;
    pin_r = pin_d/2;
    bore_r = bore_d/2;
    kn_out_r = kn_out_d/2;
    cav_r = cap_cav_d/2;
    cap_r = cap_d/2;
    wedge_far = 30;
    dy_far = wedge_far * tan(slot_half);
    // Z stack
    z0=0; z1=cap_h;              // 0..1 bottom
    z2=z1+0.3;                   // 1..1.3 lower cap clearance
    z3=z2+0.5;                   // 1.3..1.8 lower lip (closed)
    z4=z3+0.3;                   // 1.8..2.1 lower neck gap (slotted)
    z5=z4+neck_t;                // 2.1..2.9 central (slotted, neck lives)
    z6=z5+0.3;                   // 2.9..3.2 upper neck gap (slotted)
    z7=z6+0.5;                   // 3.2..3.7 upper lip (closed)
    z8=z7+0.3;                   // 3.7..4.0 upper cap clearance
    z9=z8+cap_h;                 // 4..5 top
    // 2D helpers (modules can't take shapes, so inline each layer)
    // bottom (0..1)
    translate([0,0,z0]) linear_extrude(height=z1-z0, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
            }
            translate([bore_x,0]) circle(r=cav_r);
        }
    }
    // lower cap clearance (1..1.3)
    translate([0,0,z1]) linear_extrude(height=z2-z1, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
            }
            translate([bore_x,0]) circle(r=cav_r);
        }
    }
    // lower lip (1.3..1.8) closed bore
    translate([0,0,z2]) linear_extrude(height=z3-z2, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
                translate([bore_x,0]) circle(r=kn_out_r);
            }
            translate([bore_x,0]) circle(r=bore_r);
        }
    }
    // lower neck gap (1.8..2.1) slotted
    translate([0,0,z3]) linear_extrude(height=z4-z3, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
                translate([bore_x,0]) circle(r=kn_out_r);
            }
            translate([bore_x,0]) circle(r=bore_r);
            polygon(points=[[bore_x,0],[bore_x+wedge_far,dy_far],[bore_x+wedge_far,-dy_far]]);
        }
    }
    // central (2.1..2.9) slotted + neck
    translate([0,0,z4]) linear_extrude(height=z5-z4, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([0,-neck_w/2]) square([yoke_west+1, neck_w]);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
                translate([bore_x,0]) circle(r=kn_out_r);
            }
            translate([bore_x,0]) circle(r=bore_r);
            polygon(points=[[bore_x,0],[bore_x+wedge_far,dy_far],[bore_x+wedge_far,-dy_far]]);
        }
    }
    // upper neck gap (2.9..3.2) slotted
    translate([0,0,z5]) linear_extrude(height=z6-z5, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
                translate([bore_x,0]) circle(r=kn_out_r);
            }
            translate([bore_x,0]) circle(r=bore_r);
            polygon(points=[[bore_x,0],[bore_x+wedge_far,dy_far],[bore_x+wedge_far,-dy_far]]);
        }
    }
    // upper lip (3.2..3.7) closed
    translate([0,0,z6]) linear_extrude(height=z7-z6, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
                translate([bore_x,0]) circle(r=kn_out_r);
            }
            translate([bore_x,0]) circle(r=bore_r);
        }
    }
    // upper cap clearance (3.7..4)
    translate([0,0,z7]) linear_extrude(height=z8-z7, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
            }
            translate([bore_x,0]) circle(r=cav_r);
        }
    }
    // top (4..5)
    translate([0,0,z8]) linear_extrude(height=z9-z8, convexity=8) {
        difference() {
            union() {
                circle(r=pin_r);
                translate([yoke_west,-link_w/2]) square([yoke_east-yoke_west, link_w]);
            }
            translate([bore_x,0]) circle(r=cav_r);
        }
    }
    // caps (pin ends)
    translate([0,0,0]) cylinder(h=cap_h, r=cap_r);
    translate([0,0,link_t-cap_h]) cylinder(h=cap_h, r=cap_r);
}

if (part == "assembly") {
    instance("link1", "link", 1) translate([0,0,0]) link_geom();
    instance("link2", "link", 1) translate([18,0,0]) link_geom();
    instance("link3", "link", 1) translate([36,0,0]) link_geom();
    echo(cadverify_spec = [
        ["bounds", [[-3, -6, 0], [55.7, 6, 5]]],
        ["support_faces", [["bed", "-z", 200]]],
        ["motions", [
            ["bend", ["link3"], "rotate", [36, 0, 0], [0, 0, 1], [-30, 30]]
        ]],
        ["assembly_order", [
            [["link1", "link2", "link3"], [0, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["pin cap link1", [[-3, -3, 3.8], [3, 3, 4.2]]],
            ["knuckle joint1", [[14, -4, 1.0], [22, 4, 1.6]]],
            ["pin cap link2", [[15, -3, 3.8], [21, 3, 4.2]]],
            ["knuckle joint2", [[32, -4, 1.0], [40, 4, 1.6]]],
            ["pin cap link3", [[33, -3, 3.8], [39, 3, 4.2]]],
            ["knuckle end", [[50, -4, 1.0], [58, 4, 1.6]]]
        ]],
        ["held", ["link1", "link2", "link3"]]
    ]);
} else {
    link_geom();
    echo(cadverify_spec = [
        ["bounds", [[-3, -6, 0], [21.9, 6, 5]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 100]]],
        ["overhangs_allowed", [
            ["pin cap", [[-3, -3, 3.8], [3, 3, 4.2]]],
            ["knuckle ceiling", [[14, -4, 1.0], [22, 4, 1.6]]]
        ]],
        ["copies", 3],
        ["details", [
            ["body", "material", [[6, -6, 0], [14, 6, 5]], 0.85],
            ["neck", "material", [[0, -1, 2.1], [7, 1, 2.9]], 0.8],
            ["knuckle", "material", [[14.2, -3.8, 1.3], [21.8, 3.8, 3.7]], 0.25],
            ["slot", "void", [[19, -1, 2.1], [21, 1, 2.9]], 0.8],
            ["cap_cavity", "void", [[14.7, -3.3, 0], [21.3, 3.3, 1]], 0.5],
            ["wall", "thickness", [18, 7, 2.5], [0, -1, 0], 3.7],
            ["floor", "thickness", [9, 0, -1], [0, 0, 1], 5]
        ]]
    ]);
}
