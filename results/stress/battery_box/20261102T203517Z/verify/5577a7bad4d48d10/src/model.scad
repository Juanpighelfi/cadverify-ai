/* Holder for two AA batteries with sliding cover.
   PLA, 0.4mm nozzle, no supports. Units mm.
   Print orientation: +Z up, parts rest on min z.
*/

// ---------- parameters ----------
battery_d = 14.5;
battery_l = 50.5;
side_gap = 0.6;      // battery side to wall
mid_gap = 0.8;       // between batteries
Wi = 2*battery_d + mid_gap + 2*side_gap; // 31.0 interior width
Li = battery_l + 3 + 6;                  // 59.5 interior length
floor_t = 2.0;
side_t = 3.0;
end_t = 2.5;
Wext = Wi + 2*side_t;   // 37
Lext = Li + 2*end_t;    // 64.5
wall_top = 20.9;
low_top = 17.0;
groove_bottom = 17.0;
groove_h = 2.4;
groove_top = groove_bottom + groove_h; // 19.4
groove_depth = 1.8;
engage = 1.5;
Wc = Wi + 2*engage;     // 34 cover width
Lc0 = Lext;             // 64.5 main length
lip_len = 5.0;
Lc = Lc0 + lip_len;     // 69.5 total cover length
y0b = -Lext/2;          // -32.25 base min y
y1b = Lext/2;           // 32.25 base max y
y0c = -Lext/2;          // -32.25 cover min y
y1c = Lext/2 + lip_len; // 37.25 cover max y
tc = 2.0;
finger_w = 12;
slot_w = 1.5;
finger_y0 = 12.25;
tooth_w = 11.8;
tooth_yl = 2.5;
tooth_y0 = 29.75;
tooth_y1 = tooth_y0 + tooth_yl; // 32.25
tooth_h = 1.0;
notch_hw = 7;
notch_y0 = 29.65;
notch_y1 = 32.35;
notch_bot = 16.0;
bx = battery_d/2 + mid_gap/2; // 7.65 battery center x
battery_y0 = -Li/2 + 6;       // -23.75 spring side
battery_y1 = battery_y0 + battery_l; // 26.75
battery_yc = (battery_y0 + battery_y1)/2; // 1.5
battery_zc = floor_t + battery_d/2 + 0.1; // 9.35 slight lift
wire_z = 5;
wire_r = 1.0;

part = "assembly"; // [base, cover, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module battery() {
    rotate([-90,0,0])
        cylinder(d=battery_d, h=battery_l, center=true, $fn=64);
}

module base() {
    difference() {
        // outer solid
        translate([-Wext/2, y0b, 0])
            cube([Wext, Lext, wall_top]);
        // interior cavity open at top
        translate([-Wi/2, -Li/2, floor_t])
            cube([Wi, Li, wall_top - floor_t + 1]);
        // low end wall cut (+Y end)
        translate([-Wext/2, Li/2, low_top])
            cube([Wext, Lext/2 - Li/2 + 0.5, wall_top - low_top + 1]);
        // left groove
        translate([Wi/2, -Li/2, groove_bottom])
            cube([groove_depth, Li/2 + Lext/2 + 0.5, groove_h]);
        // right groove
        translate([-Wi/2 - groove_depth, -Li/2, groove_bottom])
            cube([groove_depth, Li/2 + Lext/2 + 0.5, groove_h]);
        // wire holes through spring (-Y) wall
        translate([bx, y0b - 1, wire_z])
            rotate([-90,0,0])
                cylinder(r=wire_r, h=end_t + 2, $fn=24);
        translate([-bx, y0b - 1, wire_z])
            rotate([-90,0,0])
                cylinder(r=wire_r, h=end_t + 2, $fn=24);
        // latch notch in low wall top
        translate([-notch_hw, notch_y0, notch_bot])
            cube([2*notch_hw, notch_y1 - notch_y0, low_top - notch_bot + 0.02]);
    }
}

module cover() {
    // print orientation: plate 0..tc, tooth on top tc..tc+tooth_h
    difference() {
        union() {
            translate([-Wc/2, y0c, 0])
                cube([Wc, Lc, tc]);
            // latch tooth on top (becomes bottom after flip)
            translate([-tooth_w/2, tooth_y0, tc])
                cube([tooth_w, tooth_yl, tooth_h]);
        }
        // finger slots, open at +Y lip end
        translate([finger_w/2, finger_y0, -0.5])
            cube([slot_w, y1c - finger_y0 + 0.5, tc + 1.5]);
        translate([-finger_w/2 - slot_w, finger_y0, -0.5])
            cube([slot_w, y1c - finger_y0 + 0.5, tc + 1.5]);
    }
}

module assembly() {
    instance("base", "base", 1) base();
    instance("battery_left", "external", 1)
        translate([bx, battery_yc, battery_zc]) battery();
    instance("battery_right", "external", 1)
        translate([-bx, battery_yc, battery_zc]) battery();
    // cover printed upside-down: rotate 180 about Y then lift
    instance("cover", "cover", 1)
        translate([0, 0, 19.2]) rotate([0,180,0]) cover();
}

// ---------- specs ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-Wext/2, y0b, 0], [Wext/2, y1b, wall_top]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bottom", "-z", 2000]]],
        ["overhangs_allowed", [
            ["groove ceilings bridge 3.6mm", [[Wi/2 - 0.6, -Li/2 - 0.5, groove_bottom - 0.5], [Wi/2 + groove_depth + 0.5, y1b + 0.2, groove_top + 0.6]]],
            ["groove ceilings bridge 3.6mm", [[-Wi/2 - groove_depth - 0.5, -Li/2 - 0.5, groove_bottom - 0.5], [-Wi/2 + 0.6, y1b + 0.2, groove_top + 0.6]]],
            ["wire holes 2mm dia bridges", [[-10, y0b - 0.5, wire_z - 1.5], [10, -Li/2 + 0.5, wire_z + 1.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["cavity", "void", [[-Wi/2, -Li/2, floor_t], [Wi/2, Li/2, 17]], 0.9],
            ["spring_room", "void", [[-Wi/2, -Li/2, floor_t], [Wi/2, -Li/2 + 6, 16.6]], 0.9],
            ["pos_room", "void", [[-Wi/2, Li/2 - 3, floor_t], [Wi/2, Li/2, 16.6]], 0.9],
            ["groove_left", "void", [[Wi/2, -Li/2, groove_bottom], [Wi/2 + groove_depth, y1b, groove_top]], 0.85],
            ["groove_right", "void", [[-Wi/2 - groove_depth, -Li/2, groove_bottom], [-Wi/2, y1b, groove_top]], 0.85],
            ["notch", "void", [[-notch_hw, notch_y0, notch_bot], [notch_hw, notch_y1, low_top + 0.02]], 0.85],
            ["wire1", "hole", [bx, y0b - 1, wire_z], [0, 1, 0], [[0, 2], [2, 2]]],
            ["wire2", "hole", [-bx, y0b - 1, wire_z], [0, 1, 0], [[0, 2], [2, 2]]],
            ["floor", "thickness", [0, 0, -1], [0, 0, 1], 2.0],
            ["side_wall", "thickness", [Wext/2 + 1, 0, 18.2], [-1, 0, 0], 1.2],
            ["end_wall", "thickness", [0, y1b + 1, 10], [0, -1, 0], 2.5]
        ]]
    ]);
    base();
} else if (part == "cover") {
    echo(cadverify_spec = [
        ["bounds", [[-Wc/2, y0c, 0], [Wc/2, y1c, tc + tooth_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bottom", "-z", 1500]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["plate", "thickness", [0, -10, -1], [0, 0, 1], 2.0],
            ["finger", "material", [[-finger_w/2, finger_y0, 0], [finger_w/2, y1c, tc]], 0.85],
            ["slot_left", "void", [[finger_w/2, finger_y0, -0.5], [finger_w/2 + slot_w, y1c + 0.01, tc + 0.5]], 0.85],
            ["slot_right", "void", [[-finger_w/2 - slot_w, finger_y0, -0.5], [-finger_w/2, y1c + 0.01, tc + 0.5]], 0.85],
            ["tooth", "material", [[-tooth_w/2, tooth_y0, tc], [tooth_w/2, tooth_y1, tc + tooth_h]], 0.85],
            ["lip", "material", [[-Wc/2, y1b, 0], [Wc/2, y1c, tc]], 0.9]
        ]]
    ]);
    cover();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-Wext/2, y0b, 0], [Wext/2, y1c, wall_top]]],
        ["support_faces", [["bottom", "-z", 2000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["slide_cover", ["cover"], "slide", [0, 1, 0], [0, 50], ["flex", [["cover", "base", 1.0, "latch tooth rides over end wall"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["battery_left"], [0, 0, -1]],
            [["battery_right"], [0, 0, -1]],
            [["cover"], [0, -1, 0]]
        ]]
    ]);
    assembly();
}
