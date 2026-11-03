use <cadverify_parts.scad>

// Knob for potentiometer with 6mm D-shaft, M3 nut + set screw.
// Print orientation: base at z=0, top at z=18 (+Z up), centered at (0,0).

/* [Basic] */
part = "knob"; // [knob, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
knob_d = 30;            // max diameter incl. ribs
knob_h = 18;            // total height
body_d = 28.8;          // turned body diameter (ribs add to 30)
body_r = body_d/2;      // 14.4
bot_r = 13.4;           // bottom face radius (1mm 45deg chamfer)
top_r = 12.9;           // top face radius (1.5mm 45deg chamfer)
bot_cham_h = 1.0;
top_cham_h = 1.5;
rib_n = 36;
rib_w = 1.2;            // tangential width
rib_x0 = 13.5;          // rib inner x (inside body)
rib_x1 = 15.0;          // rib outer x (max radius)
rib_z0 = 2.0;
rib_z1 = 15.5;
bore_d = 6.3;           // D-bore diameter (snug +0.3 on 6.0 shaft)
bore_r = bore_d/2;      // 3.15
bore_flat = 1.65;       // flat plane x (shaft flat 1.5 + 0.15 clearance)
bore_depth = 15;        // blind depth from base
floor_t = 3.0;          // 18-15
screw_d = 3.2;          // M3 clearance through plastic
screw_z = 8;            // screw axis height above base
pocket_af = 5.9;        // hex pocket across flats (nut 5.5 + clearance)
pocket_ac = pocket_af / cos(30); // across corners
pocket_inner = 5.05;    // hex channel inner end (x)
pocket_outer = 15.5;    // hex channel outer end (beyond surface)
nut_af = 5.5;
nut_t = 2.4;
nut_inner = 5.25;       // nut inner face x (knob local)
pointer_w = 1.2;
pointer_x0 = 1.0;
pointer_x1 = 12.5;
pointer_ztop = 18;
pointer_zbot = 16.8;
shaft_d = 6.0;
shaft_r = shaft_d/2;
shaft_flat = 1.5;       // flat plane x (4.5 across: 3+1.5)
shaft_len = 25;
assy_base = 10;         // knob base height in assembly (shaft bottom at 0)

// ---- knob solid (printing orientation) ----
module knob_body_revolved() {
    // profile (r,z): bottom face -> bottom chamfer -> straight -> top chamfer -> top face
    pts = [
        [0, 0],
        [bot_r, 0],
        [body_r, bot_cham_h],
        [body_r, knob_h - top_cham_h],
        [top_r, knob_h],
        [0, knob_h]
    ];
    rotate_extrude($fn=128) polygon(pts);
}

module knob_ribs() {
    for (a = [0 : 360/rib_n : 360 - 360/rib_n])
        rotate([0,0,a])
            translate([rib_x0, -rib_w/2, rib_z0])
                cube([rib_x1-rib_x0, rib_w, rib_z1-rib_z0]);
}

module bore_void() {
    intersection() {
        translate([0,0,-0.5]) cylinder(d=bore_d, h=bore_depth+0.5, $fn=64);
        translate([-5,-5,-0.5]) cube([(bore_flat+5), 10, bore_depth+0.5]);
    }
}

module pocket_void() {
    translate([pocket_inner, 0, screw_z])
        rotate([0,90,0])
            cylinder(d=pocket_ac, h=pocket_outer-pocket_inner, $fn=6);
}

module screw_void() {
    translate([0, 0, screw_z])
        rotate([0,90,0])
            cylinder(d=screw_d, h=5.5, $fn=32);
}

module pointer_void() {
    translate([pointer_x0, -pointer_w/2, pointer_zbot])
        cube([pointer_x1-pointer_x0, pointer_w, (pointer_ztop+0.2)-pointer_zbot]);
}

module knob() {
    difference() {
        union() {
            knob_body_revolved();
            knob_ribs();
        }
        bore_void();
        pocket_void();
        screw_void();
        pointer_void();
    }
}

// ---- shaft (external, pot D-shaft) ----
module shaft() {
    intersection() {
        cylinder(d=shaft_d, h=shaft_len, $fn=64);
        translate([-10,-10,0]) cube([(shaft_flat+10), 20, shaft_len]);
    }
}

// ---- assembly placement ----
module assembly() {
    // knob elevated so shaft bottom sits at z=0
    instance("knob", "knob") translate([0,0,assy_base]) knob();
    // shaft fully inserted: top flush with bore ceiling (assy_base+15=25)
    instance("shaft", "external") shaft();
    // nut in pocket, axis along +X, inner face at nut_inner
    instance("nut", "standard:m3_nut") translate([nut_inner, 0, assy_base+screw_z]) rotate([0,90,0]) m3_nut();
}

// ---- specs ----
if (part == "knob") {
    echo(cadverify_spec = [
        ["bounds", [[-knob_d/2, -knob_d/2, 0], [knob_d/2, knob_d/2, knob_h]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["base", "-z", 400]]],
        ["overhangs_allowed", [
            ["bore ceiling bridge 6.3mm", [[-bore_r-0.5, -bore_r-0.5, bore_depth-1], [bore_flat+0.5, bore_r+0.5, bore_depth+1]]],
            ["horizontal screw hole bridge 3.2mm", [[0, -2, screw_z-0.5], [pocket_inner+0.5, 2, screw_z+2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["knurl", "view", [[12, -5, rib_z0], [16, 5, rib_z1]]],
            ["pointer", "void", [[pointer_x0, -pointer_w/2, pointer_zbot], [pointer_x1, pointer_w/2, pointer_ztop+0.2]], 0.9],
            ["bore", "void", [[-2, -2, 0], [1.5, 2, bore_depth]], 0.9],
            ["floor", "thickness", [0, 0, 20], [0, 0, -1], floor_t],
            ["nut_pocket", "void", [[6, -1.5, screw_z-1.5], [10, 1.5, screw_z+1.5]], 0.9],
            ["screw_hole", "hole", [10, 0, screw_z], [-1, 0, 0], [[0, screw_d], [3.4, screw_d]]]
        ]]
    ]);
}

if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-knob_d/2, -knob_d/2, 0], [knob_d/2, knob_d/2, assy_base+knob_h]]],
        ["assembly_order", [
            [["knob"], [0, 0, 0]],
            [["nut"], [-1, 0, 0]],
            [["shaft"], [0, 0, 1]]
        ]]
    ]);
}

// ---- output ----
if (part == "assembly") {
    assembly();
} else {
    knob();
}
