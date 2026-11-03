// Gridfinity bin, 2x1 x 3U tall
// Outside 83.5 x 41.5 mm, height 21 mm (3x7mm), PLA, 0.4mm nozzle, no supports
// Print orientation: +Z up, bottom (foot bottoms) on bed at z=0

Lx = 83.5;
Ly = 41.5;
H = 21;
foot_z0 = 0;
foot_z1 = 0.8;
foot_z2 = 2.6;   // 0.8+1.8
foot_z3 = 4.75;  // 0.8+1.8+2.15
foot_btm = 35.6; // 41.5-5.9
foot_mid = 37.2; // 35.6+1.6
foot_top = 41.5;
wall_t = 1.6;
floor_z = 6.0;
lip_z = 19.5;
lip_inset = 0.6;

echo(cadverify_spec = [
    ["bounds", [[-41.75, -20.75, 0], [41.75, 20.75, 21]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["bed", "-z", 2000]]],
    ["overhangs_allowed", [
        ["standard Gridfinity foot lower 45-degree chamfer left", [[-40, -19, -0.1], [-2, 19, 0.8]]],
        ["standard Gridfinity foot lower 45-degree chamfer right", [[2, -19, -0.1], [40, 19, 0.8]]],
        ["standard Gridfinity foot upper 45-degree taper", [[-42, -21, 2.5], [42, 21, 4.75]]]
    ]],
    ["copies", 1],
    ["details", [
        ["foot_left", "material", [[-30, -10, 0.1], [-12, 10, 0.7]], 0.9],
        ["foot_right", "material", [[12, -10, 0.1], [30, 10, 0.7]], 0.9],
        ["stack_lip", "material", [[-20, 19.3, 19.6], [20, 20.0, 20.9]], 0.9],
        ["label_shelf", "material", [[-30, 16, 6.5], [30, 18.5, 8]], 0.9],
        ["scoop_void", "void", [[40.5, -10, 14], [42.5, 10, 20]], 0.9],
        ["wall_side", "thickness", [38, 22, 16], [0, -1, 0], 1.6],
        ["floor", "thickness", [-21, 0, -5], [0, 0, 1], 6.0],
        ["foot_profile", "view", [[-39, -18, 0], [-3, 18, 5]]],
        ["scoop_view", "view", [[35, -15, 10], [43, 15, 22]]],
        ["label_view", "view", [[-10, 12, 6], [10, 20, 13]]],
        ["lip_view", "view", [[-15, 18.5, 18.5], [15, 21, 21.5]]]
    ]]
]);

module foot(cx) {
    translate([cx, 0, 0]) {
        // bottom 45deg frustum: 35.6 -> 37.2 over 0.8
        hull() {
            translate([-foot_btm/2, -foot_btm/2, 0]) cube([foot_btm, foot_btm, 0.1]);
            translate([-foot_mid/2, -foot_mid/2, foot_z1-0.1]) cube([foot_mid, foot_mid, 0.1]);
        }
        // vertical 1.8
        translate([-foot_mid/2, -foot_mid/2, foot_z1]) cube([foot_mid, foot_mid, foot_z2-foot_z1]);
        // top 45deg frustum: 37.2 -> 41.5 over 2.15
        hull() {
            translate([-foot_mid/2, -foot_mid/2, foot_z2]) cube([foot_mid, foot_mid, 0.1]);
            translate([-foot_top/2, -foot_top/2, foot_z3-0.1]) cube([foot_top, foot_top, 0.1]);
        }
    }
}

module bin_solid() {
    foot(-21);
    foot(21);
    // main outer body, overlap feet top by 0.1
    translate([-Lx/2, -Ly/2, foot_z3-0.1]) cube([Lx, Ly, lip_z-(foot_z3-0.1)]);
    // stacking lip: stepped inward 0.6 per side, no overhang
    translate([-(Lx-2*lip_inset)/2, -(Ly-2*lip_inset)/2, lip_z]) cube([Lx-2*lip_inset, Ly-2*lip_inset, H-lip_z]);
    // label shelf wedge along +Y inside, sits on floor against wall
    // y_in=19.15, bottom from 13.15 to 19.35, top from 17.65 to 19.35
    hull() {
        translate([-35, 13.15, 5.9]) cube([70, 19.35-13.15, 0.2]);
        translate([-35, 17.65, 11.9]) cube([70, 19.35-17.65, 0.2]);
    }
}

module bin() {
    x_in = (Lx-2*wall_t)/2;
    y_in0 = -(Ly-2*wall_t)/2;
    y_in1 = (Ly-2*wall_t)/2;
    shelf_y0 = 13.15;
    shelf_y1 = 17.65;
    shelf_z0 = 6.0;
    shelf_z1 = 12.0;
    difference() {
        bin_solid();
        // lower cavity, fronted by label shelf slope on +Y
        hull() {
            translate([-x_in, y_in0, shelf_z0]) cube([2*x_in, shelf_y0-y_in0, 0.2]);
            translate([-x_in, y_in0, shelf_z1-0.2]) cube([2*x_in, shelf_y1-y_in0, 0.2]);
        }
        // upper cavity full width
        translate([-x_in, y_in0, shelf_z1]) cube([2*x_in, y_in1-y_in0, H-shelf_z1+1]);
        // scoop at +X front: cylinder axis X, R30 center z42 -> bottom 12 at center
        translate([41.0, 0, 42]) rotate([0, 90, 0]) cylinder(r=30, h=12, center=true, $fn=128);
    }
}

bin();
