// Box with print-in-place hinge
// Outside closed ~80x60x40, lid ~10mm, hinge along back, pin in place, no supports.

part = "assembly"; // [assembly, box, lid, pin]

W = 80; D = 60; Hb = 30; Hl = 10;
wall = 2; floor_t = 2;
pin_r = 2; bore_r = 2.3; kn_r = 4;
axisY = -33; axisZ = 20;
hinge_len = 60; hinge_half = 30;
head_r = 3; head_t = 2; head_gap = 0.4;
notch_half = 6; notch_bottom = 25; // Hb-5
tab_clear = 0.2;
gap_axial = 0.5;

cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- knuckle X intervals (assembly coordinates) ----
box1_x0 = -30; box1_x1 = -17;
lid1_x0 = -16.5; lid1_x1 = -5.5;
box2_x0 = -5; box2_x1 = 5;
lid2_x0 = 5.5; lid2_x1 = 16.5;
box3_x0 = 17; box3_x1 = 30;

module knuckle_x(x0, x1, r) {
    len = x1 - x0;
    translate([x0, axisY, axisZ]) rotate([0,90,0]) cylinder(r=r, h=len, $fn=48);
}
module bore_x(x0, x1, r) {
    // slightly longer to open through, 0.2 each side
    len = (x1 - x0) + 0.4;
    translate([x0-0.2, axisY, axisZ]) rotate([0,90,0]) cylinder(r=r, h=len, $fn=48);
}

module box_part() {
    difference() {
        union() {
            // outer solid
            translate([-W/2, -D/2, 0]) cube([W, D, Hb]);
            // box knuckles
            knuckle_x(box1_x0, box1_x1, kn_r);
            knuckle_x(box2_x0, box2_x1, kn_r);
            knuckle_x(box3_x0, box3_x1, kn_r);
        }
        // interior cavity
        translate([-(W/2-wall), -(D/2-wall), floor_t]) cube([W-2*wall, D-2*wall, Hb]);
        // catch notch in front wall (through wall, open to top)
        translate([-notch_half, D/2-wall-0.1, notch_bottom]) cube([2*notch_half, wall+1.1, Hb-notch_bottom+1]);
        // knuckle bores
        bore_x(box1_x0, box1_x1, bore_r);
        bore_x(box2_x0, box2_x1, bore_r);
        bore_x(box3_x0, box3_x1, bore_r);
    }
}

// lid in CLOSED coordinates (slab Z 30..40)
module lid_closed() {
    difference() {
        union() {
            // slab
            translate([-W/2, -D/2, Hb]) cube([W, D, Hl]);
            // catch tab hanging down into notch
            translate([-(notch_half-tab_clear), D/2-wall+tab_clear, Hb-3]) cube([2*(notch_half-tab_clear), wall-2*tab_clear, 3]);
            // arms: lower behind wall + upper into lid back
            // lid1
            translate([lid1_x0, -35, axisZ]) cube([(lid1_x1-lid1_x0), 4.7, 10.5]);
            translate([lid1_x0, -35, 29.5]) cube([(lid1_x1-lid1_x0), 5.5, 5.5]);
            // lid2
            translate([lid2_x0, -35, axisZ]) cube([(lid2_x1-lid2_x0), 4.7, 10.5]);
            translate([lid2_x0, -35, 29.5]) cube([(lid2_x1-lid2_x0), 5.5, 5.5]);
            // lid knuckles
            knuckle_x(lid1_x0, lid1_x1, kn_r);
            knuckle_x(lid2_x0, lid2_x1, kn_r);
        }
        bore_x(lid1_x0, lid1_x1, bore_r);
        bore_x(lid2_x0, lid2_x1, bore_r);
    }
}

// pin canonical along Z centered at origin
module pin_canonical() {
    union() {
        // shaft -31..31
        cylinder(r=pin_r, h=62, center=true, $fn=48);
        // heads
        translate([0,0,hinge_half+head_gap+head_t/2]) cylinder(r=head_r, h=head_t, center=true, $fn=48);
        translate([0,0,-(hinge_half+head_gap+head_t/2)]) cylinder(r=head_r, h=head_t, center=true, $fn=48);
    }
}
module pin_horizontal() {
    translate([0, axisY, axisZ]) rotate([0,90,0]) pin_canonical();
}
module lid_open() {
    // 180 deg about hinge axis -> print pose / export orientation
    translate([0, axisY, axisZ]) rotate([180,0,0]) translate([0, -axisY, -axisZ]) lid_closed();
}

// ---- specs ----
box_xmin = -W/2; box_xmax = W/2;
box_ymin = axisY - kn_r; box_ymax = D/2;
box_zmin = 0; box_zmax = Hb;

lid_xmin = -W/2; lid_xmax = W/2;
lid_ymin = 2*axisY - D/2; lid_ymax = axisY + kn_r;
lid_zmin = 0; lid_zmax = 2*axisZ - 16;

pin_xmin = -head_r; pin_xmax = head_r;
pin_ymin = -head_r; pin_ymax = head_r;
pin_zmin = 0; pin_zmax = 2*(hinge_half+head_gap+head_t);

asm_xmin = -W/2; asm_xmax = W/2;
asm_ymin = axisY - kn_r; asm_ymax = D/2;
asm_zmin = 0; asm_zmax = Hb + Hl;

ox0 = -(hinge_half+3); ox1 = (hinge_half+3);
oy0 = axisY-kn_r-1; oy1 = axisY+kn_r+1;
oz0 = axisZ-kn_r-1; oz1 = axisZ+kn_r+1;

if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[box_xmin, box_ymin, box_zmin], [box_xmax, box_ymax, box_zmax]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", W*D-800]]],
        ["overhangs_allowed", [["hinge", [[ox0, oy0, oz0], [ox1, oy1, oz1]]]]],
        ["copies", 1],
        ["details", [
            ["wall_thickness", "thickness", [W/2+1, 0, Hb/2], [-1, 0, 0], wall],
            ["floor_thickness", "thickness", [0, 0, -1], [0, 0, 1], floor_t],
            ["catch_notch", "void", [[-notch_half, D/2-wall-0.1, notch_bottom], [notch_half, D/2+1, Hb+1]], 0.9],
            ["knuckle_bore", "hole", [-31, axisY, axisZ], [1, 0, 0], [[0, 2*bore_r], [13, 2*bore_r]]]
        ]]
    ]);
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[lid_xmin, lid_ymin, lid_zmin], [lid_xmax, lid_ymax, lid_zmax]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", W*D-800]]],
        ["overhangs_allowed", [["hinge", [[ox0, oy0, oz0], [ox1, oy1, oz1]]]]],
        ["copies", 1],
        ["details", [
            ["lid_thickness", "thickness", [0, 2*axisY, Hl+1], [0, 0, -1], Hl],
            ["catch_tab", "material", [[-(notch_half-tab_clear), 2*axisY-(D/2-wall+tab_clear)-(wall-2*tab_clear), Hl], [(notch_half-tab_clear), 2*axisY-(D/2-wall+tab_clear), Hl+3]], 0.9],
            ["knuckle_bore", "hole", [-16.75, axisY, axisZ], [1, 0, 0], [[0, 2*bore_r], [11, 2*bore_r]]]
        ]]
    ]);
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[pin_xmin, pin_ymin, pin_zmin], [pin_xmax, pin_ymax, pin_zmax]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", 20]]],
        ["copies", 1],
        ["details", [
            ["shaft_thickness", "thickness", [head_r, 0, (hinge_half+head_gap+head_t)], [-1, 0, 0], 2*pin_r],
            ["head", "material", [[-head_r, -head_r, 0], [head_r, head_r, head_t]], 0.7]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[asm_xmin, asm_ymin, asm_zmin], [asm_xmax, asm_ymax, asm_zmax]]],
        ["support_faces", [["base", "-z", W*D-800]]],
        ["motions", [
            ["lid_swing", ["lid_body"], "rotate", [0, axisY, axisZ], [1, 0, 0], [0, 180]]
        ]],
        ["assembly_order", [
            [["box_body"], [0, 0, 0]],
            [["lid_body"], [0, 0, -1]],
            [["pin_body"], [-1, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["print_pose", [["lid_swing", 180]]],
        ["overhangs_allowed", [["hinge_clearance", [[ox0, oy0, oz0], [ox1, oy1, oz1]]]]]
    ]);
}

// ---- geometry output ----
if (part == "box") {
    box_part();
} else if (part == "lid") {
    lid_open();
} else if (part == "pin") {
    translate([0,0,(hinge_half+head_gap+head_t)]) pin_canonical();
} else if (part == "assembly") {
    instance("box_body", "box") box_part();
    instance("lid_body", "lid") lid_closed();
    instance("pin_body", "pin") pin_horizontal();
}
