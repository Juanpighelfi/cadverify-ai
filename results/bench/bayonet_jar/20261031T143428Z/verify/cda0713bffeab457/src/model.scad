// Desk jar with bayonet lid — PETG, 0.4 mm nozzle, no supports.
// Print: jar upright (base on bed), lid top-down (top dome on bed).
// Assembly: closed (locked) jar.

part = "jar"; // [jar:Jar, lid:Lid, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
outer_d = 80;          // flush outside diameter, jar + lid
inner_d = 70;          // interior diameter
inner_depth = 80;      // interior depth (floor top 5 -> rim 85)
floor_t = 5;
jar_h = 85;
lid_top_t = 5;
skirt_h = 11;
skirt_outer_d = 68.4;  // 0.8 radial clearance into 70 bore
skirt_wall = 3.0;
lift_clear = 0.8;      // lug bottom above track floor (print fit)

// bayonet track (jar), angles in degrees
slot_floor_z = 75;
slot_rect_h = 4.5;     // 75 .. 79.5
slot_roof_h = 1.7;     // apex 81.2, faces ~38 deg from vertical
slot_r0 = 34.8;        // cuts into bore (r 35)
slot_r1 = 37.5;        // stays 2.5 inside outer wall (r 40)
entry_half_w = 4.5;    // entry notch half width (tangential)
track_a0 = -6;         // track start angle
track_a1 = 40;         // track end angle
pocket_ang = 32;       // locked lug centre angle
bump_ang = 22;         // detent bump centre angle
bump_hd = 2.7;         // bump radial width (34.8..37.5)
bump_tan = 2.4;        // bump tangential half length
bump_h = 1.0;          // bump height above track floor

// lugs (lid, print coordinates, lugs at 0 and 180 deg)
lug_w = 6.5;           // tangential width
lug_H = 3.4;           // vertical height
lug_P = 2.2;           // radial length past skirt surface
lug_rise = 2.44;       // tip ramp rise (42 deg from vertical)
lug_z0 = 10.8;         // lug bottom in print coords (-> 79.2..75.8 assy)

$fn = 200;

// ---------- jar ----------
module jar_blank() {
    pts = [
        [0,0],[38,0],[40,2.4],[40,82.6],[38,85],[36.5,85],[35,83.2],
        [35,9],[31,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module jar_slot_pair() {
    // entry notch (open through rim top)
    translate([slot_r0, -entry_half_w, slot_floor_z])
        cube([slot_r1 - slot_r0, entry_half_w*2, 85.5 - slot_floor_z]);
    // horizontal rect sector
    rotate([0,0,track_a0])
        rotate_extrude(angle=track_a1-track_a0, convexity=4)
            polygon([[slot_r0,slot_floor_z],[slot_r1,slot_floor_z],
                     [slot_r1,slot_floor_z+slot_rect_h],[slot_r0,slot_floor_z+slot_rect_h]]);
    // 45-ish roof sector (support-free ceiling)
    midr = (slot_r0+slot_r1)/2;
    rotate([0,0,track_a0])
        rotate_extrude(angle=track_a1-track_a0, convexity=4)
            polygon([[slot_r0,slot_floor_z+slot_rect_h],[slot_r1,slot_floor_z+slot_rect_h],
                     [midr,slot_floor_z+slot_rect_h+slot_roof_h]]);
}

module bump_wedge(a) {
    w = bump_hd; mid = (slot_r0+slot_r1)/2;
    rotate([0,0,a]) translate([mid, 0, slot_floor_z])
        hull() {
            translate([-w/2, -bump_tan, 0]) cube([w, bump_tan*2, 0.1]);
            translate([-w/2, -0.2, bump_h-0.1]) cube([w, 0.4, 0.1]);
        }
}

module jar() {
    union() {
        difference() {
            jar_blank();
            jar_slot_pair();
            rotate([0,0,180]) jar_slot_pair();
        }
        bump_wedge(bump_ang);
        bump_wedge(bump_ang+180);
    }
}

// ---------- lid (print orientation: top dome on bed) ----------
module lid_blank() {
    Ro = skirt_outer_d/2;      // 34.2
    Ri = Ro - skirt_wall;      // 31.2
    pts = [
        [0,0],[38,0],[40,2.4],[40,3.8],[39,5],[Ro,5],[Ro,14.5],
        [Ro-1.2,16],[Ri+1.2,16],[Ri,14.5],[Ri,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module lug_at(ap) {
    Rsk = skirt_outer_d/2;
    rotate([0,0,ap])
        translate([Rsk-0.2, 0, lug_z0])
            rotate([90,0,0])
                translate([0,0,-lug_w/2])
                    linear_extrude(height=lug_w, convexity=3)
                        polygon([[0,0],[lug_P,lug_rise],[lug_P,lug_H],[0,lug_H]]);
}

module lid() {
    union() {
        lid_blank();
        lug_at(0);
        lug_at(180);
    }
}

// ---------- assembly (closed / locked) ----------
module assembly() {
    instance("jar","jar") jar();
    instance("lid","lid")
        rotate([0,0,pocket_ang]) translate([0,0,90]) rotate([180,0,0]) lid();
}

// ---------- specs ----------
jar_bounds = [[-40,-40,0],[40,40,85]];
lid_bounds = [[-40,-40,0],[40,40,16]];
asm_bounds = [[-40,-40,0],[40,40,90]];

jar_details = [
    ["cavity", "void", [[-24,-24,6],[24,24,84]], 0.9],
    ["wall", "thickness", [50,0,40], [-1,0,0], 5],
    ["floor", "thickness", [0,0,-10], [0,0,1], 5],
    ["slot_entry", "void", [[34.9,-4.0,76],[37.4,4.0,84]], 0.9],
    ["slot_track", "void", [[34.3,9.4,76.5],[35.3,10.6,78.5]], 0.85],
    ["bump", "material", [[31.8,11.7,75],[35.3,15.4,75.5]], 0.4],
    ["rim_soft", "view", [[36.5,-5,82.0],[40,5,85]]],
    ["bottom_soft", "view", [[37.0,-5,-0.5],[40.5,5,3.0]]]
];
lid_details = [
    ["top", "thickness", [0,0,-10], [0,0,1], 5],
    ["skirt_wall", "thickness", [50,0,10], [-1,0,0], 3],
    ["lug", "material", [[34.1,-2.5,13.3],[36.1,2.5,14.1]], 0.8],
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
        ["details", jar_details]
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
        ["details", lid_details]
    ]);
    lid();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", asm_bounds],
        ["support_faces", [["desk","-z",4000]]],
        ["allowed_interferences", [["lid","jar","detent bump snap, 0.2 mm"]]],
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
