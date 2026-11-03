// Gridfinity bin 2x1 x 3U tall
// Outside 83.5 x 41.5, H=21, foot 0.8/1.8/2.15, stacking lip, label shelf, scoop
grid = 42;
clr = 0.5;
Lx = 2*grid - clr; // 83.5
Ly = 1*grid - clr; // 41.5
H = 3*7; // 21
h1 = 0.8;
h2 = 1.8;
h3 = 2.15;
Hfoot = h1+h2+h3; // 4.75
foot_bot = Ly - 2*(h1+h3); // 35.6
foot_mid = foot_bot + 2*h1; // 37.2
wt = 1.2;
lipExtra = 0.5;
floorTop = 6.0;
lipTrans0 = 17.5;
lipTop0 = 18.0;
frontTop = 10;
x0 = 15;
xr0 = 12;
rampTop = 9;
shelfLen = 40;
shelfCx = -15; // shelf x in [-35,5]
shelf_y_wall = -(Ly/2 - wt); // -19.55
shelf_y_tip = shelf_y_wall + 6; // -13.55
shelf_z_bot = 9;
shelf_z_top = 15;
x1f = -grid/2;
x2f = grid/2;

echo(cadverify_spec = [
    ["bounds", [[-Lx/2, -Ly/2, 0], [Lx/2, Ly/2, H]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["bed", "-z", 2000]]],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
        ["foot_left", "material", [[x1f-foot_bot/2, -foot_bot/2, 0.05], [x1f+foot_bot/2, foot_bot/2, 0.55]], 0.9],
        ["foot_right", "material", [[x2f-foot_bot/2, -foot_bot/2, 0.05], [x2f+foot_bot/2, foot_bot/2, 0.55]], 0.9],
        ["lip_back", "material", [[-30, Ly/2-wt-lipExtra, 19], [0, Ly/2, 21]], 0.9],
        ["label_shelf", "material", [[-30, -19, 14.5], [0, -14.5, 15]], 0.9],
        ["scoop_void", "void", [[30, -15, 10.5], [40.4, 15, 14]], 0.9],
        ["cavity", "void", [[-20, -10, 10], [10, 10, 16]], 0.9],
        ["wall", "thickness", [0, 25, 15], [0, -1, 0], 1.2],
        ["floor", "thickness", [-21, 0, -5], [0, 0, 1], 6.0]
    ]]
]);

module foot(cx) {
    hull() {
        translate([cx-foot_bot/2, -foot_bot/2, 0]) cube([foot_bot, foot_bot, 0.1]);
        translate([cx-foot_mid/2, -foot_mid/2, h1-0.05]) cube([foot_mid, foot_mid, 0.1]);
    }
    translate([cx-foot_mid/2, -foot_mid/2, h1-0.05]) cube([foot_mid, foot_mid, h2+0.1]);
    hull() {
        translate([cx-foot_mid/2, -foot_mid/2, h1+h2-0.05]) cube([foot_mid, foot_mid, 0.1]);
        translate([cx-Ly/2, -Ly/2, Hfoot]) cube([Ly, Ly, 0.1]);
    }
}

module body_outer() {
    foot(x1f);
    foot(x2f);
    translate([-Lx/2, -Ly/2, Hfoot-0.1]) cube([Lx, Ly, H-Hfoot+0.1]);
}

module cavity_solid() {
    intL_low = Lx-2*wt;
    intW_low = Ly-2*wt;
    intL_up = Lx-2*(wt+lipExtra);
    intW_up = Ly-2*(wt+lipExtra);
    translate([-intL_low/2, -intW_low/2, floorTop-0.02]) cube([intL_low, intW_low, (lipTrans0-floorTop)+0.02]);
    hull() {
        translate([-intL_low/2, -intW_low/2, lipTrans0-0.02]) cube([intL_low, intW_low, 0.04]);
        translate([-intL_up/2, -intW_up/2, lipTop0]) cube([intL_up, intW_up, 0.04]);
    }
    translate([-intL_up/2, -intW_up/2, lipTop0-0.02]) cube([intL_up, intW_up, (H+2-lipTop0)+0.02]);
}

module scoop_cut() {
    W = Ly+2;
    x1cut = Lx/2+1;
    hull() {
        translate([x0-0.1, -W/2, H]) cube([0.2, W, 2]);
        translate([x1cut-0.1, -W/2, frontTop]) cube([0.2, W, (H+2-frontTop)]);
    }
}

module scoop_ramp() {
    intW = Ly-2*wt;
    xr1 = Lx/2-wt;
    hull() {
        translate([xr0-0.1, -intW/2, floorTop-0.1]) cube([0.2, intW, 0.14]);
        translate([xr1-0.1, -intW/2, floorTop-0.1]) cube([0.2, intW, (rampTop-floorTop)+0.1]);
    }
}

module label_shelf_mod() {
    hull() {
        translate([shelfCx-shelfLen/2, shelf_y_wall-0.2, shelf_z_bot]) cube([shelfLen, 0.4, shelf_z_top-shelf_z_bot]);
        translate([shelfCx-shelfLen/2, shelf_y_tip-0.1, shelf_z_top-0.1]) cube([shelfLen, 0.2, 0.2]);
    }
}

module bin_part() {
    difference() {
        body_outer();
        cavity_solid();
        scoop_cut();
    }
}

union() {
    bin_part();
    scoop_ramp();
    label_shelf_mod();
}
