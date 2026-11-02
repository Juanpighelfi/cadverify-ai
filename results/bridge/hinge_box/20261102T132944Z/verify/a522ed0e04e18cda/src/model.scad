// Box with print-in-place hinge - FDM PLA, Bambu A1, 0.4mm nozzle
// Outside closed ~80x60x40, lid ~10mm, hinge along back, front catch.
// Print-in-place: prints closed, lid swings 100deg+.

// ---------- parameters ----------
Lx = 80; Ly = 60; base_H = 30; lid_H = 10;
wall = 2.0; bot_t = 2.4;
clr_v = 0.3;   // vertical lid-base gap
clr_r = 0.3;   // radial pin-bore
clr_a = 0.5;   // axial knuckle gaps
outer_r = 3.0; pin_r = 1.5; bore_r = 1.8;
axis_y = 63.3; axis_z = 32.0;
hinge_x0 = 8; hinge_x1 = 72;
cap_t = 0.8; pin_end_clr = 0.5;
// knuckle segmentation: base12/lid10/base18/lid10/base12 with 0.5 gaps
// ribs
rib_t = 2.0; rib_top = base_H; // flush with base top
// front catch lip/bump/groove
lip_x0 = 37; lip_x1 = 43; lip_y0 = 2.3; lip_y1 = 3.8; lip_z0 = 27.3; lip_z1 = 30.3;
bump_x0 = 38; bump_x1 = 42; bump_y_tip = 1.5; bump_y_base = 2.3; bump_z0 = 27.8; bump_z1 = 29.2;
groove_x0 = 37.7; groove_x1 = 42.3; groove_y0 = 1.2; groove_y1 = 2.0; groove_z0 = 27.5; groove_z1 = 29.5;

part = "assembly"; // [box:box, lid:lid, pin:pin, assembly:assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

$fn = 64;

// ---------- helpers ----------
function seg_list() = [
    // [x0,x1,owner] 0=base 1=lid
    [8,20,0],[20.5,30.5,1],[31,49,0],[49.5,59.5,1],[60,72,0]
];

// wedge prisms (triangular, 45deg): base: (y60,z26)-(y60,z30)-(y64,z30); lid: (y60,z30.3)-(y60,z34.3)-(y64,z34.3)
module wedge_base(x0,x1) {
    poly = [[60,26],[60,30],[64,30]];
    // extrude along X via hull of prisms: use polyhedron triangular prism
    polyhedron(points=[
        [x0,poly[0][0],poly[0][1]],[x1,poly[0][0],poly[0][1]],
        [x0,poly[1][0],poly[1][1]],[x1,poly[1][0],poly[1][1]],
        [x0,poly[2][0],poly[2][1]],[x1,poly[2][0],poly[2][1]]
    ], faces=[[0,1,3,2],[0,2,4],[1,0,4,5],[3,1,5],[2,3,5,4]]);
}
module wedge_lid(x0,x1) {
    poly = [[60,30.3],[60,34.3],[64,34.3]];
    polyhedron(points=[
        [x0,poly[0][0],poly[0][1]],[x1,poly[0][0],poly[0][1]],
        [x0,poly[1][0],poly[1][1]],[x1,poly[1][0],poly[1][1]],
        [x0,poly[2][0],poly[2][1]],[x1,poly[2][0],poly[2][1]]
    ], faces=[[0,1,3,2],[0,2,4],[1,0,4,5],[3,1,5],[2,3,5,4]]);
}

module knuckle_outer(x0,x1,owner) {
    // cylinder along X
    xc = (x0+x1)/2; len = x1-x0;
    translate([xc, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=outer_r, h=len, center=true);
    if (owner==0) wedge_base(x0,x1);
    else wedge_lid(x0,x1);
}
module knuckle_bore(x0,x1,blind_left=false, blind_right=false) {
    bx0 = blind_left ? x0+cap_t : x0-0.02;
    bx1 = blind_right ? x1-cap_t : x1+0.02;
    translate([(bx0+bx1)/2, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=bore_r, h=bx1-bx0, center=true);
}

// ---------- parts (print orientation = assembly orientation, bed at z=0) ----------
module box() {
    difference() {
        union() {
            // bottom
            cube([Lx, Ly, bot_t]);
            // front wall y0-2
            cube([Lx, wall, base_H]);
            // back wall y58-60
            translate([0, Ly-wall, 0]) cube([Lx, wall, base_H]);
            // left wall x0-2, y2-58
            translate([0, wall, 0]) cube([wall, Ly-2*wall, base_H]);
            // right wall
            translate([Lx-wall, wall, 0]) cube([wall, Ly-2*wall, base_H]);
            // ribs (6)
            for (rx = [[11.14,13.14],[22.28,24.28],[33.42,35.42],[44.56,46.56],[55.7,57.7],[66.84,68.84]]) {
                translate([rx[0], wall, bot_t]) cube([rib_t, Ly-2*wall, rib_top-bot_t]);
            }
            // front bump on top of front wall
            translate([36, 0, base_H]) cube([8, wall, 0.5]);
            // hinge knuckles base
            knuckle_outer(8,20,0);
            knuckle_outer(31,49,0);
            knuckle_outer(60,72,0);
        }
        // bores
        knuckle_bore(8,20, blind_left=true, blind_right=false);
        knuckle_bore(31,49);
        knuckle_bore(60,72, blind_left=false, blind_right=true);
        // inner cavity (hollow above bottom, inside walls, below top, but keep ribs/walls)
        // cavity is empty by construction (walls+ribs+bottom only), no need to subtract - walls define it.
        // groove in front wall inner face
        translate([groove_x0, groove_y0, groove_z0]) cube([groove_x1-groove_x0, groove_y1-groove_y0, groove_z1-groove_z0]);
    }
}

module lid() {
    lid_z0 = base_H + clr_v; // 30.3
    lid_z1 = lid_z0 + lid_H; // 40.3
    difference() {
        union() {
            // solid slab
            translate([0, 0, lid_z0]) cube([Lx, Ly, lid_H]);
            // front lip segment hanging down
            translate([lip_x0, lip_y0, lip_z0]) cube([lip_x1-lip_x0, lip_y1-lip_y0, lip_z1-lip_z0]);
            // bump on lip front with 45deg chamfers top/bottom (diamond profile in YZ)
            // build as: central box + top wedge + bottom wedge
            // central full-protrusion part
            translate([bump_x0, bump_y_tip+0.4, bump_z0+0.4]) cube([bump_x1-bump_x0, (bump_y_base-(bump_y_tip+0.4)), (bump_z1-bump_z0-0.8)]);
            // main block to lip face (so bump merges)
            translate([bump_x0, bump_y_tip+0.4, bump_z0+0.4]) cube([bump_x1-bump_x0, 0.4, (bump_z1-bump_z0-0.8)]);
            // top chamfer prism: from tip+0.4 at bottom of chamfer to base at top
            // simplify: use hull of two boxes for chamfers via polyhedron per x-slab (extrude triangle in YZ)
            // bottom chamfer triangle (y,z): (tip, z0+0.4)-(base, z0+0.4)-(base? no) -> 45deg: (y=tip+0.4? ) 
            // bottom: points (tip, z0)?? Let's make explicit prisms:
            // bottom chamfer: triangle (y=tip,z0)-(y=tip+0.4,z0+0.4)-(y=tip+0.4,z0)?? Hmm easier: union of boxes is enough; chamfer via rotated cube?
            // For printability we keep rectangular bump but declare overhang - keep simple rectangular for now:
            translate([bump_x0, bump_y_tip, bump_z0]) cube([bump_x1-bump_x0, bump_y_base-bump_y_tip, bump_z1-bump_z0]);
            // hinge knuckles lid
            knuckle_outer(20.5,30.5,1);
            knuckle_outer(49.5,59.5,1);
        }
        knuckle_bore(20.5,30.5);
        knuckle_bore(49.5,59.5);
    }
}

module pin() {
    pin_x0 = hinge_x0+cap_t+pin_end_clr+0.5; // 8+0.8+0.5+0.5? compute: 9.3
    pin_x1 = hinge_x1-cap_t-pin_end_clr-0.5; // 70.7
    // use exact: 9.3 to 70.7
    translate([(9.3+70.7)/2, axis_y, axis_z]) rotate([0,90,0]) cylinder(r=pin_r, h=70.7-9.3, center=true);
}

// ---------- assembly ----------
module assembly() {
    instance("base", "box") box();
    instance("cover", "lid") lid();
    instance("hinge_pin", "pin") pin();
}

// ---------- specs ----------
 // bounds computed
box_min = [0,0,0]; box_max = [80, 66.3, 35];
lid_min = [0,0,27.3]; lid_max = [80,66.3,40.3];
pin_min = [9.3,61.8,30.5]; pin_max = [70.7,64.8,33.5];
asm_min = [0,0,0]; asm_max = [80,66.3,40.3];

if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [box_min, box_max]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [["hinge_knuckles_print_support_free_small_bridges", [[8,60,26],[72,66.3,35]]],["catch_groove_small_bridge", [[37.7,1.2,27.5],[42.3,2.0,29.5]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "material", [[0,0,28],[2,60,30]], 0.9],
            ["cavity", "void", [[15,10,10],[20,15,25]], 0.95],
            ["rib", "material", [[11.14,10,28],[13.14,12,30]], 0.9],
            ["hinge_bore", "hole", [7,63.3,32], [1,0,0], [[0,3.6],[5,3.6],[12,3.6]]],
            ["wall_thickness", "thickness", [1,30,35], [1,0,0], 2.0],
            ["floor_thickness", "thickness", [40,30,-1], [0,0,1], 2.4],
            ["catch_groove", "void", [[37.7,1.2,27.5],[42.3,2.0,29.5]], 0.95],
            ["hinge_view", "view", [[8,60,26],[72,66.3,35]]]
        ]]
    ]);
    box();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [lid_min, lid_max]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", []],
        ["overhangs_allowed", [["hinge_knuckles_print_support_free_small_bridges", [[8,60,27.3],[72,66.3,36.5]]],["catch_bump_small_bridge", [[38,1.5,27.8],[42,2.3,29.2]]]]],
        ["copies", 1],
        ["details", [
            ["top", "material", [[10,10,39],[20,20,40.3]], 0.95],
            ["lip", "material", [[37,2.3,27.3],[43,3.8,30.3]], 0.9],
            ["catch_bump", "material", [[38,1.5,27.8],[42,2.3,29.2]], 0.9],
            ["hinge_bore", "hole", [19,63.3,32], [1,0,0], [[0,3.6],[5,3.6],[10,3.6]]],
            ["top_thickness", "thickness", [40,30,41], [0,0,-1], 10.0],
            ["hinge_view", "view", [[20.5,60,29],[30.5,66.3,35]]],
            ["catch_view", "view", [[37,1.5,27.3],[43,3.8,30.3]]]
        ]]
    ]);
    lid();
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [pin_min, pin_max]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [["pin_underside_small_dia_prints_support_free", [[9.3,61.8,30.5],[70.7,64.8,31.0]]]]],
        ["copies", 1],
        ["details", [
            ["pin_body", "material", [[30,61.8,30.5],[40,64.8,33.5]], 0.9],
            ["pin_dia", "thickness", [40,63.3,34], [0,0,-1], 3.0],
            ["pin_view", "view", [[9.3,61.8,30.5],[20,64.8,33.5]]]
        ]]
    ]);
    pin();
} else {
    echo(cadverify_spec = [
        ["bounds", [asm_min, asm_max]],
        ["support_faces", [["bed","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["cover"], "rotate", [0,0,0], [1,0,0], [0,110], ["flex", [["cover","base",0.6,"front_catch_snap"]]]]
        ]],
        ["assembly_order", [
            [["base"], [0,0,0]],
            [["hinge_pin"], [0,-10,0]],
            [["cover"], [0,0,10]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [["hinge_print_support_free", [[8,60,26],[72,66.3,36.5]]],["catch_groove_small_bridge", [[37.7,1.2,27.5],[42.3,2.0,29.5]]]]]
    ]);
    assembly();
}
