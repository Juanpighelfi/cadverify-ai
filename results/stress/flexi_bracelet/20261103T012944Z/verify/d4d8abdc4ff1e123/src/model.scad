part = "link"; // [link, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
pitch = 18;          // pin-to-bore distance
link_w = 12;         // width (Y)
link_t = 5;          // thickness (Z)
pin_d = 4;           // pin shaft diameter
bore_d = 4.6;        // bore diameter (0.3 radial clearance)
cap_d = 6;           // cap diameter
cap_h = 1;           // cap thickness
gap_z = 0.3;         // vertical clearance cap<->knuckle
kn_h = 2.4;          // knuckle height = 5-2*1-2*0.3
kn_out_d = 7.6;      // knuckle outer diameter (1.5 wall)
cap_cav_d = 6.6;     // cap cavity diameter (0.3 radial clearance)
neck_w = 2;          // neck width
slot_half = 50;      // slot half-angle (deg), allows +-30 deg swing
yoke_east = 20.5;    // full-height yoke east extent (local X)
$fn = 64;

module link_geom() {
    bore_x = pitch;
    cap_r = cap_d/2;
    cav_r = cap_cav_d/2;
    pin_r = pin_d/2;
    bore_r = bore_d/2;
    kn_out_r = kn_out_d/2;
    // far points for slot wedge (full height + middle)
    // wedge from bore center to the east, half-angle slot_half
    wedge_far = 30;
    dy_far = wedge_far * tan(slot_half);
    // ---- full height (0..5): yoke + neck + pin shaft ----
    linear_extrude(height = link_t, convexity = 8) {
        difference() {
            union() {
                // pin shaft disc
                translate([0,0]) circle(r = pin_r);
                // neck rect X[0,5] Y[-1,1]
                translate([0,-neck_w/2]) square([5, neck_w]);
                // yoke base rect X[4,yoke_east] Y[-6,6]
                translate([4,-link_w/2]) square([yoke_east-4, link_w]);
            }
            // cap cavity (for next link caps)
            translate([bore_x,0]) circle(r = cav_r);
            // slot wedge for next-link neck swing (full height)
            polygon(points = [[bore_x,0],[bore_x+wedge_far, dy_far],[bore_x+wedge_far, -dy_far]]);
        }
    }
    // ---- middle knuckle ring (1.3..3.7) ----
    kn_bot = cap_h + gap_z; // 1.3
    translate([0,0,kn_bot])
    linear_extrude(height = kn_h, convexity = 8) {
        difference() {
            translate([bore_x,0]) circle(r = kn_out_r);
            translate([bore_x,0]) circle(r = bore_r);
            polygon(points = [[bore_x,0],[bore_x+wedge_far, dy_far],[bore_x+wedge_far, -dy_far]]);
        }
    }
    // ---- caps ----
    translate([0,0,0]) cylinder(h = cap_h, r = cap_r);
    translate([0,0,link_t-cap_h]) cylinder(h = cap_h, r = cap_r);
}

if (part == "assembly") {
    instance("link1", "link", 1) translate([0,0,0]) link_geom();
    instance("link2", "link", 1) translate([18,0,0]) link_geom();
    instance("link3", "link", 1) translate([36,0,0]) link_geom();
    echo(cadverify_spec = [
        ["bounds", [[-3, -6, 0], [56.5, 6, 5]]],
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
            ["knuckle joint1", [[14.5, -3.5, 1.0], [21, 3.5, 1.5]]],
            ["pin cap link2", [[15, -3, 3.8], [21, 3, 4.2]]],
            ["knuckle joint2", [[32.5, -3.5, 1.0], [39, 3.5, 1.5]]],
            ["pin cap link3", [[33, -3, 3.8], [39, 3, 4.2]]],
            ["knuckle end", [[50.5, -3.5, 1.0], [57, 3.5, 1.5]]]
        ]],
        ["held", ["link1", "link2", "link3"]]
    ]);
} else {
    link_geom();
    echo(cadverify_spec = [
        ["bounds", [[-3, -6, 0], [20.5, 6, 5]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 100]]],
        ["overhangs_allowed", [
            ["pin cap", [[-3, -3, 3.8], [3, 3, 4.2]]],
            ["knuckle ceiling", [[14.5, -3.5, 1.0], [21, 3.5, 1.5]]]
        ]],
        ["copies", 3],
        ["details", [
            ["body", "material", [[4, -6, 0], [14, 6, 5]], 0.85],
            ["neck", "material", [[0, -1, 0], [5, 1, 5]], 0.8],
            ["knuckle", "material", [[14.2, -3.8, 1.3], [21.8, 3.8, 3.7]], 0.25],
            ["slot", "void", [[19, -1, 0], [21, 1, 5]], 0.8],
            ["cap_cavity", "void", [[14.7, -3.3, 0], [21.3, 3.3, 1]], 0.5],
            ["wall", "thickness", [18, 7, 2.5], [0, -1, 0], 1.5],
            ["floor", "thickness", [9, 0, -1], [0, 0, 1], 5]
        ]]
    ]);
}
