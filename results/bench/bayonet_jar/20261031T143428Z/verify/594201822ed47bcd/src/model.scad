// Desk jar with bayonet lid - PETG, no supports, flush, soft edges
// Print orientations: jar upright (bottom on bed), lid upside-down (top on bed)

part = "jar"; // [jar:Jar, lid:Lid, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
inner_d = 70;          // interior diameter
inner_depth = 80;      // interior depth
outer_d = 80;          // flush outside diameter jar + lid
floor_t = 5;           // jar floor thickness
jar_h = 85;            // 5 + 80
lid_top_t = 5;         // lid top plate thickness
skirt_h = 11;          // skirt length below lid underside
skirt_outer_d = 68.8;  // skirt outer dia (bore 70, 0.6 radial clearance)
skirt_wall = 3.0;      // skirt wall thickness
skirt_inner_d = skirt_outer_d - 2*skirt_wall;

slot_floor_z = 75;     // horizontal track floor (10 below rim 85)
slot_rect_h = 4.5;     // rect part height 75..79.5
slot_roof_h = 1.7;     // triangular roof apex 79.5..81.2 (faces ~38deg)
slot_outer_r = 37.5;   // slot depth outward from axis
slot_inner_r = 34.8;   // slightly inside bore (35) to cut through
entry_half_w = 4.0;    // entry width 8
travel_deg = 32;       // entry centre -> pocket centre
bump_h = 1.0;          // detent bump height
bump_half_len = 2.4;   // tangential half length
bump_ang = 25;         // bump centre angle deg (pocket at 32)

lug_w = 6.5;
lug_H = 3.4;
lug_P = 2.2;           // radial length from embedded base
lug_rise = 2.44;       // bottom slope rise (42deg from vertical)
lug_bottom_z_print = 11.0; // lug bottom in print coords (top at 14.4)
lug_embed = 0.2;

$fn = 160;

// ---------- jar blank profile (r,z) ----------
module jar_blank() {
    // points: (0,0)->(38,0)->(40,2.4)->(40,82.6)->(38,85)->(36.5,85)->(35,83.2)->(35,5)->(0,5)
    pts = [
        [0,0],[38,0],[40,2.4],[40,82.6],[38,85],[36.5,85],[35,83.2],[35,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

// entry box at angle 0
module entry_void() {
    translate([slot_inner_r, -entry_half_w, slot_floor_z])
        cube([slot_outer_r - slot_inner_r, entry_half_w*2, 85.5 - slot_floor_z]);
}

// horizontal rect + roof sectors from -6 to 38 deg
module track_voids() {
    // rect
    rotate([0,0,-6])
        rotate_extrude(angle=44, convexity=4)
            polygon([[slot_inner_r,slot_floor_z],[slot_outer_r,slot_floor_z],[slot_outer_r,slot_floor_z+slot_rect_h],[slot_inner_r,slot_floor_z+slot_rect_h]]);
    // roof triangle
    midr = (slot_inner_r+slot_outer_r)/2;
    rotate([0,0,-6])
        rotate_extrude(angle=44, convexity=4)
            polygon([[slot_inner_r,slot_floor_z+slot_rect_h],[slot_outer_r,slot_floor_z+slot_rect_h],[midr,slot_floor_z+slot_rect_h+slot_roof_h]]);
}

module jar_slots() {
    entry_void();
    track_voids();
    rotate([0,0,180]) entry_void();
    rotate([0,0,180]) track_voids();
}

// detent bump prism (tangential triangle, radial depth full slot)
module bump_at(a) {
    midr = (slot_inner_r+slot_outer_r)/2;
    // prism built as extruded triangle (Xt=tangential, Yv=vertical) then mapped
    rotate([0,0,a])
        translate([midr-1.35, 0, slot_floor_z])
            rotate([0,0,90]) rotate([90,0,0])
                translate([0,0,-bump_half_len])
                    linear_extrude(height=bump_half_len*2, convexity=2)
                        polygon([[-bump_half_len,0],[bump_half_len,0],[0,bump_h]]);
    // Note: above mapping gives X=radial thickness 2.7? check: extrude height 4.8 becomes radial? Let's use direct polyhedron instead for exactness
}

 // Simpler robust bump: use polyhedron wedge explicitly in local (X radial,Y tang,Z vert)
module bump_wedge(a) {
    r0 = slot_inner_r;
    r1 = slot_outer_r;
    rotate([0,0,a])
        translate([(r0+r1)/2, 0, slot_floor_z])
            polyhedron(
                points=[
                    [-1.35,-2.4,0],[1.35,-2.4,0],[1.35,2.4,0],[-1.35,2.4,0],
                    [-1.35,0,1.0],[1.35,0,1.0]
                ],
                faces=[
                    [0,1,2,3],[0,4,5,1],[1,5,2],[2,5,4,3],[3,4,0]
                ], convexity=4);
}

module jar() {
    union() {
        difference() {
            jar_blank();
            jar_slots();
        }
        bump_wedge(bump_ang);
        bump_wedge(bump_ang+180);
    }
}

// ---------- lid ----------
module lid_blank() {
    // profile (r,z) print orientation, axis at 0
    // (0,0)->(38,0)->(40,2.4)->(40,3.8)->(39,5)->(34.4,5)->(34.4,14.5)->(33.2,16)->(32.6,16)->(31.4,14.5)->(31.4,5)->(0,5)
    pts = [
        [0,0],[38,0],[40,2.4],[40,3.8],[39,5],[34.4,5],[34.4,14.5],[33.2,16],[32.6,16],[31.4,14.5],[31.4,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module lug_at(ap) {
    Rsk = skirt_outer_d/2;
    rotate([0,0,ap])
        translate([Rsk-lug_embed, 0, lug_bottom_z_print])
            rotate([90,0,0])
                translate([0,0,-lug_w/2])
                    linear_extrude(height=lug_w, convexity=3)
                        polygon([[0,0],[lug_P,lug_rise],[lug_P,lug_H],[0,lug_H]]);
}

module lid() {
    union() {
        lid_blank();
        // print angles: assembly pockets at 32,212 -> print at -32,148 (mirror y->-y on flip)
        lug_at(-32);
        lug_at(-32+180);
    }
}

// ---------- assembly ----------
module assembly() {
    instance("jar","jar") jar();
    // lid print (top down 0..16) flipped to assembly (74..90): rotate 180 about X then +90
    instance("lid","lid") translate([0,0,90]) rotate([180,0,0]) lid();
}

// ---------- specs ----------
jar_bounds = [[-outer_d/2,-outer_d/2,0],[outer_d/2,outer_d/2,jar_h]];
lid_h = lid_top_t + skirt_h; // 16
lid_bounds = [[-outer_d/2,-outer_d/2,0],[outer_d/2,outer_d/2,lid_h]];
asm_bounds = [[-outer_d/2,-outer_d/2,0],[outer_d/2,outer_d/2,90]];

jar_spec_details = [
    ["cavity", "void", [[-24,-24,6],[24,24,84]], 0.9],
    ["wall", "thickness", [50,0,40], [-1,0,0], 5],
    ["floor", "thickness", [0,0,-10], [0,0,1], 5],
    ["slot_entry", "void", [[34.9,-3.5,76],[37.4,3.5,84]], 0.9],
    ["slot_track", "void", [[34.3,9.4,76.5],[35.3,10.6,78.5]], 0.85],
    ["bump", "material", [[35.5,-1.2,75],[37.0,1.2,75.6]], 0.5],
    ["rim_soft", "view", [[36.5,-5,82.0],[40,5,85]]],
    ["bottom_soft", "view", [[37.0,-5,-0.5],[40.5,5,3.0]]]
];
lid_spec_details = [
    ["top", "thickness", [0,0,-10], [0,0,1], 5],
    ["skirt_wall", "thickness", [50,0,10], [-1,0,0], 3],
    ["lug", "material", [[35.0,-0.6,12.0],[36.2,0.6,14.0]], 0.8],
    ["top_soft", "view", [[36.5,-5,-0.5],[40.5,5,3.0]]],
    ["tip_lead", "view", [[30.5,-5,14.0],[35.0,5,16.5]]]
];

if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", jar_bounds],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base","-z",4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", jar_spec_details]
    ]);
    jar();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", lid_bounds],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["top","-z",4000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", lid_spec_details]
    ]);
    lid();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", asm_bounds],
        ["support_faces", [["desk","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["twist_lock", ["lid"], "rotate", [0,0,0], [0,0,1], [0,-32], ["flex", [["lid","jar",1.0,"detent bump cams over"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,-1], ["rotate", [0,0,0], [0,0,1], 32]]
        ]],
        ["overhangs_allowed", []]
    ]);
    assembly();
} else {
    jar();
}
