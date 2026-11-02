// Box with print-in-place hinge
part = "assembly"; // [assembly, box, lid, pin]
W = 80; D = 60; Hb = 30; Hl = 10;
wall = 2; floor_t = 2;
pin_r = 2; bore_r = 2.4; kn_r = 4;
axisY = -33; axisZ = 20.2; lift = 0.4;
hinge_half = 30;
notch_half = 6; notch_bottom = 25;
clear_rad = 1.1; bore_end = 1.1;
cadverify_only = "";
module instance(name, partname, unit = 1) {
    echo(cadverify_instance = [name, partname, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
box1_x0 = -30; box1_x1 = -17;
lid1_x0 = -16.5; lid1_x1 = -5.5;
box2_x0 = -5; box2_x1 = 5;
lid2_x0 = 5.5; lid2_x1 = 16.5;
box3_x0 = 17; box3_x1 = 30;
gap = 0.5;
box2a_x0 = -5; box2a_x1 = 0; box2b_x0 = 0; box2b_x1 = 5;
module knuckle_x(x0, x1, r) {
    len = x1 - x0;
    translate([x0, axisY, axisZ]) rotate([0,90,0]) cylinder(r=r, h=len, $fn=48);
}
module bore_x(x0, x1, r) {
    len = (x1 - x0) + 0.4;
    translate([x0-0.2, axisY, axisZ]) rotate([0,90,0]) cylinder(r=r, h=len, $fn=48);
}
module clear_x(x0, x1, r) {
    len = (x1 - x0);
    translate([x0, axisY, axisZ]) rotate([0,90,0]) cylinder(r=r, h=len, $fn=48);
}
module box_part() {
    difference() {
        union() {
            translate([-W/2, -D/2, 0]) cube([W, D, Hb]);
            knuckle_x(box1_x0, box1_x1, kn_r);
            knuckle_x(box2a_x0, box2a_x1, kn_r);
            knuckle_x(box2b_x0, box2b_x1, kn_r);
            knuckle_x(box3_x0, box3_x1, kn_r);
        }
        translate([-(W/2-wall), -(D/2-wall), floor_t]) cube([W-2*wall, D-2*wall, Hb]);
        translate([-notch_half, D/2-wall-0.1, notch_bottom]) cube([2*notch_half, wall+1.1, Hb-notch_bottom+1]);
        bore_x(box1_x0, box1_x1, bore_r);
        bore_x(box2a_x0, box2a_x1, bore_r);
        bore_x(box2b_x0, box2b_x1, bore_r);
        bore_x(box3_x0, box3_x1, bore_r);
        clear_x(lid1_x0-gap, lid1_x1+gap, kn_r+clear_rad);
        clear_x(lid2_x0-gap, lid2_x1+gap, kn_r+clear_rad);
        // clearance under pin head travel: slot along x 0..29.5 at pin z
        translate([0, axisY, axisZ]) rotate([0,90,0]) cylinder(r=bore_end, h=29.5, $fn=32);
        translate([0, axisY, axisZ]) rotate([0,90,0]) cylinder(r=bore_end, h=29.5, $fn=32);
    }
}
module lid_closed() {
    difference() {
        union() {
            translate([-W/2, -D/2, Hb+lift]) cube([W, D, Hl]);
            translate([-(notch_half-0.2), D/2-1.4, Hb+lift-3]) cube([2*(notch_half-0.2), 1.0, 3]);
            translate([lid1_x0, -35, axisZ]) cube([(lid1_x1-lid1_x0), 4.6, (Hb+lift-axisZ)]);
            translate([lid1_x0, -35, Hb+lift]) cube([(lid1_x1-lid1_x0), 5.6, 5]);
            translate([lid2_x0, -35, axisZ]) cube([(lid1_x1-lid1_x0), 4.6, (Hb+lift-axisZ)]);
            translate([lid2_x0, -35, Hb+lift]) cube([(lid2_x1-lid2_x0), 5.6, 5]);
            knuckle_x(lid1_x0, lid1_x1, kn_r);
            knuckle_x(lid2_x0, lid2_x1, kn_r);
        }
        bore_x(lid1_x0, lid1_x1, bore_r);
        bore_x(lid2_x0, lid2_x1, bore_r);
    }
}
pin_len = 59;
module pin_canonical() {
    translate([0,0,pin_len/2]) cylinder(r=pin_r, h=pin_len, center=true, $fn=48);
}
module pin_horizontal() {
    translate([-pin_len/2, axisY, axisZ]) rotate([0,90,0]) pin_canonical();
}
module lid_open() {
    translate([0, axisY, axisZ]) rotate([180,0,0]) translate([0, -axisY, -axisZ]) lid_closed();
}
box_xmin = -W/2; box_xmax = W/2;
box_ymin = axisY - kn_r; box_ymax = D/2;
box_zmin = 0; box_zmax = Hb;
lid_xmin = -W/2; lid_xmax = W/2;
lid_ymin = 2*axisY - D/2; lid_ymax = axisY + kn_r;
lid_zmin = 0; lid_zmax = axisZ + kn_r;
pin_xmin = -pin_r; pin_xmax = pin_r;
pin_ymin = -pin_r; pin_ymax = pin_r;
pin_zmin = 0; pin_zmax = pin_len;
asm_xmin = -W/2; asm_xmax = W/2;
asm_ymin = axisY - (kn_r+clear_rad); asm_ymax = D/2;
asm_zmin = 0; asm_zmax = Hb + lift + Hl;
ox0 = -(hinge_half+4); ox1 = (hinge_half+4);
oy0 = axisY-(kn_r+clear_rad)-1; oy1 = axisY+kn_r+1;
oz0 = axisZ-(kn_r+clear_rad)-1; oz1 = axisZ+(kn_r+clear_rad)+1;
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
            ["knuckle_bore", "hole", [-31, axisY, axisZ], [1, 0, 0], [[0, 2*bore_r], [10, 2*bore_r]]]
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
            ["catch_tab", "material", [[-(notch_half-0.2), 2*axisY-(D/2-1.4)-1.0, Hl], [(notch_half-0.2), 2*axisY-(D/2-1.4), Hl+3]], 0.9],
            ["knuckle_bore", "hole", [-16.75, axisY, axisZ], [1, 0, 0], [[0, 2*bore_r], [8, 2*bore_r]]]
        ]]
    ]);
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[pin_xmin, pin_ymin, pin_zmin], [pin_xmax, pin_ymax, pin_zmax]]],
        ["bodies", 1],
        ["support_faces", [["base", "-z", 10]]],
        ["copies", 1],
        ["details", [
            ["shaft_thickness", "thickness", [pin_r+0.3, 0, pin_len/2], [-1, 0, 0], 2*pin_r]
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
            [["pin_body"], [0, 0, 0]],
            [["box_body", "lid_body"], [1, 0, 0]]
        ]],
        ["print_in_place", 0.3],
        ["print_pose", [["lid_swing", 180]]],
        ["overhangs_allowed", [
            ["hinge_clearance", [[ox0, oy0, oz0], [ox1, oy1, oz1]]],
            ["lid_bridges", [[-17, -36, 4], [17, -30, 6]]]
        ]]
    ]);
}
if (part == "box") {
    box_part();
} else if (part == "lid") {
    lid_open();
} else if (part == "pin") {
    pin_canonical();
} else if (part == "assembly") {
    instance("box_body", "box") box_part();
    instance("lid_body", "lid") lid_closed();
    instance("pin_body", "pin") pin_horizontal();
}
