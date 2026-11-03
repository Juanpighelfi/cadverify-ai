use <cadverify_parts.scad>

// Holder for two AA batteries with a sliding cover.
// Print orientation = exported orientation (+Z up, lowest face on bed, no supports).

part = "assembly"; // [base, cover, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------------- parameters ----------------
bay_w   = 15.4;   // battery bay width (cell 14.5 + clearance)
div_t   = 1.6;    // centre divider thickness
side_t  = 3.0;    // side wall thickness (1.4 web outside grooves)
endc_t  = 2.0;    // closed-end wall thickness
ende_t  = 5.0;    // entry-end wall thickness (holds catch pocket)
W_in    = 2*bay_w + div_t;        // 32.4 interior width
W_out   = W_in + 2*side_t;        // 38.4 outer width
L_in    = 60.0;                   // interior length (50.5 cell + 6 + 3 + 0.5)
L_out   = L_in + endc_t + ende_t; // 67.0 outer length
floor_t = 2.0;
wall_top = 22.0;  // side / closed-end wall top
gb      = 17.0;   // groove floor height (0.5 above cell top 16.5)
ce_in   = 19.4;   // groove ceiling height at inner edge
ce_out  = 21.0;   // groove ceiling height at outer edge (45 deg slope)
groove_d = 1.6;   // groove depth into side wall
groove_y0 = endc_t;
div_h0  = 2.0;
div_h1  = 12.0;   // divider top (above cell centre, below cover)

// catch pocket in entry-wall top (closed pocket, >=1.2 webs)
notch_x  = 2.2;
notch_y0 = 63.3;
notch_y1 = 65.3;
notch_z0 = 15.8;
notch_zt = 17.0;  // entry-wall top

// wire holes through floor at spring end
wire_d = 2.0;
wire_y = 5.0;

// cover, modelled in print orientation (plate on bed, tooth up)
W_cov   = W_in + 2*(groove_d - 0.2); // 35.2
L_cov   = 64.8;                      // front 2.2 .. rear 67.0 in assembly
plate_t = 2.0;
tooth_h = 1.0;
slot_x0 = 6.0;
slot_x1 = 8.5;
slot_y0 = 43.0;   // slot roots (slots open at rear edge)
finger_d = 6.0;
finger_y = 51.0;
tooth_y0 = 61.3;  // tooth base, print coords
tooth_y1 = 62.9;
tooth_x  = 2.0;   // half width in x

// batteries in assembly
batt_d   = 14.5;
batt_len = 50.5;
bx       = div_t/2 + bay_w/2;  // 8.5 bay centres
batt_y0  = endc_t + 6;         // 8.0 negative end (6 mm spring room)
batt_z   = floor_t + batt_d/2; // 9.25 axis height
asm_cov_y = 2.2;               // cover front in assembly
asm_cov_z = 19.2;              // cover top in assembly (plate top)

// ---------------- base ----------------
module groove_void_left() {
    x_in = -W_in/2;
    x_out = -W_in/2 - groove_d;
    y0 = groove_y0;
    y1 = L_out + 0.1;
    hull() {
        translate([x_out, y0, gb]) cube([x_in - x_out, y1 - y0, 0.01]);
        translate([x_in - 0.01, y0, ce_in]) cube([0.01, y1 - y0, 0.01]);
        translate([x_out, y0, ce_out]) cube([0.01, y1 - y0, 0.01]);
    }
}

module base() {
    difference() {
        union() {
            // floor
            translate([-W_out/2, 0, 0]) cube([W_out, L_out, floor_t]);
            // side walls
            translate([-W_out/2, 0, floor_t]) cube([side_t, L_out, wall_top - floor_t]);
            translate([W_in/2, 0, floor_t]) cube([side_t, L_out, wall_top - floor_t]);
            // closed end wall (full height, cover stop)
            translate([-W_in/2, 0, floor_t]) cube([W_in, endc_t, wall_top - floor_t]);
            // entry end wall (low so cover slides over it)
            translate([-W_in/2, L_in + endc_t, floor_t])
                cube([W_in, ende_t, notch_zt - floor_t]);
            // centre divider rib between cells
            translate([-div_t/2, endc_t, div_h0]) cube([div_t, L_in, div_h1 - div_h0]);
        }
        // sliding grooves with 45 deg self-supporting ceilings, open at entry end
        groove_void_left();
        mirror([1, 0, 0]) groove_void_left();
        // catch pocket (open to top only)
        translate([-notch_x, notch_y0, notch_z0])
            cube([2*notch_x, notch_y1 - notch_y0, notch_zt - notch_z0 + 0.1]);
        // two wire holes through floor
        translate([-bx, wire_y, -0.5]) cylinder(d = wire_d, h = floor_t + 1, $fn = 24);
        translate([bx, wire_y, -0.5]) cylinder(d = wire_d, h = floor_t + 1, $fn = 24);
    }
}

// ---------------- cover ----------------
module cover() {
    difference() {
        union() {
            // sliding plate (side strips ride in the grooves)
            translate([-W_cov/2, 0, 0]) cube([W_cov, L_cov, plate_t]);
            // catch tooth with 45 deg front/back ramps
            hull() {
                translate([-tooth_x, tooth_y0, plate_t]) cube([2*tooth_x, tooth_y1 - tooth_y0, 0.6]);
                translate([-tooth_x, tooth_y0 + 0.4, plate_t + tooth_h - 0.01])
                    cube([2*tooth_x, tooth_y1 - tooth_y0 - 0.8, 0.01]);
            }
        }
        // two slots forming the flexible end tab (open at rear edge)
        translate([-slot_x1, slot_y0, -0.5]) cube([slot_x1 - slot_x0, L_cov - slot_y0 + 0.6, plate_t + 1]);
        translate([slot_x0, slot_y0, -0.5]) cube([slot_x1 - slot_x0, L_cov - slot_y0 + 0.6, plate_t + 1]);
        // rounded slot roots
        translate([-(slot_x0 + slot_x1)/2, slot_y0, -0.5])
            cylinder(d = slot_x1 - slot_x0, h = plate_t + 1, $fn = 24);
        translate([(slot_x0 + slot_x1)/2, slot_y0, -0.5])
            cylinder(d = slot_x1 - slot_x0, h = plate_t + 1, $fn = 24);
        // finger pull hole in the tab
        translate([0, finger_y, -0.5]) cylinder(d = finger_d, h = plate_t + 1, $fn = 48);
    }
}

// ---------------- assembly (closed, cells fitted) ----------------
module assembly() {
    instance("base", "base") translate([0, 0, 0]) base();
    instance("batt_left", "standard:aa_cell")
        translate([-bx, batt_y0, batt_z]) rotate([-90, 0, 0]) aa_cell();
    instance("batt_right", "standard:aa_cell")
        translate([bx, batt_y0, batt_z]) rotate([-90, 0, 0]) aa_cell();
    instance("cover", "cover")
        translate([0, asm_cov_y, asm_cov_z]) rotate([0, 180, 0]) cover();
}

// ---------------- specs + dispatch ----------------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-W_out/2, 0, 0], [W_out/2, L_out, wall_top]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed", "-z", 2000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["bay_left", "void", [[-W_in/2, endc_t, floor_t], [-div_t/2, endc_t + L_in, floor_t + batt_d]], 0.9],
            ["bay_right", "void", [[div_t/2, endc_t, floor_t], [W_in/2, endc_t + L_in, floor_t + batt_d]], 0.9],
            ["contact_spring", "void", [[-W_in/2, endc_t, floor_t], [W_in/2, endc_t + 6, floor_t + batt_d]], 0.9],
            ["contact_pos", "void", [[-W_in/2, endc_t + L_in - 3.5, floor_t], [W_in/2, endc_t + L_in, floor_t + batt_d]], 0.9],
            ["groove_left", "void", [[-W_in/2 - groove_d, groove_y0, gb], [-W_in/2, L_out, ce_in]], 0.9],
            ["groove_right", "void", [[W_in/2, groove_y0, gb], [W_in/2 + groove_d, L_out, ce_in]], 0.9],
            ["catch_pocket", "void", [[-notch_x, notch_y0, notch_z0], [notch_x, notch_y1, notch_zt]], 0.9],
            ["wire_left", "hole", [-bx, wire_y, -1], [0, 0, 1], [[0, wire_d]]],
            ["wire_right", "hole", [bx, wire_y, -1], [0, 0, 1], [[0, wire_d]]],
            ["wall_side", "thickness", [W_out/2 + 1, 30, 10], [-1, 0, 0], side_t],
            ["wall_end", "thickness", [8.5, -1, 15], [0, 1, 0], endc_t],
            ["floor", "thickness", [8, 30, -1], [0, 0, 1], floor_t],
            ["divider", "material", [[-div_t/2, endc_t, div_h0], [div_t/2, endc_t + L_in, div_h1]], 0.9]
        ]]
    ]);
    base();
} else if (part == "cover") {
    echo(cadverify_spec = [
        ["bounds", [[-W_cov/2, 0, 0], [W_cov/2, L_cov, plate_t + tooth_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["bed", "-z", 1700]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["plate", "material", [[-W_cov/2, 0, 0], [W_cov/2, slot_y0, plate_t]], 0.9],
            ["tab", "material", [[-slot_x0, slot_y0, 0], [slot_x0, L_cov, plate_t]], 0.8],
            ["tooth", "material", [[-tooth_x, tooth_y0, plate_t], [tooth_x, tooth_y1, plate_t + tooth_h]], 0.7],
            ["slot_left", "void", [[-slot_x1, slot_y0, 0], [-slot_x0, L_cov, plate_t]], 0.9],
            ["slot_right", "void", [[slot_x0, slot_y0, 0], [slot_x1, L_cov, plate_t]], 0.9],
            ["finger", "hole", [0, finger_y, -1], [0, 0, 1], [[0, finger_d], [plate_t, finger_d]]],
            ["plate_thickness", "thickness", [10, 10, 5], [0, 0, -1], plate_t]
        ]]
    ]);
    cover();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-W_out/2, 0, 0], [W_out/2, L_out, wall_top]]],
        ["support_faces", [["bed", "-z", 2000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["slide_off", ["cover"], "slide", [0, 1, 0], [0, 45],
                ["flex", [["cover", "base", 1.0, "catch tooth rides over entry wall"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["batt_left"], [0, 0, -1]],
            [["batt_right"], [0, 0, -1]],
            [["cover"], [0, -1, 0],
                ["flex", [["cover", "base", 1.0, "catch tooth rides over entry wall"]]]]
        ]],
        ["held", ["batt_left", "batt_right"]]
    ]);
    assembly();
}
