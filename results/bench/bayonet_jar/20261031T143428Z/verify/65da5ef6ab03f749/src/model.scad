// Desk jar with bayonet lid — PETG, 0.4 mm nozzle, no supports.
// Jar prints upright (base on bed). Lid prints top-down (top face on bed).
// Closed jar is the assembly. Motion twist_lock = turn to lock (flex over bump).

part = "jar"; // [jar:Jar, lid:Lid, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
outerR = 40;          // flush outside radius jar + lid
boreR = 35;           // interior radius (70 across)
floorT = 5;
jarH = 85;            // rim at 85, interior depth 80 (5..85)
plugR = 34.4;         // lid plug outer (0.6 clearance to bore)
plugRi = 31.4;        // plug inner (3.0 wall)
plugBot = 5;          // plug base in lid print coords (disc top)
plugTipZ = 16.5;      // plug tip in print coords
lidTopH = 5;          // disc thickness

// bayonet track on jar inner wall
slotR0 = 34.8;        // inner edge (breaks into bore for clean cut)
slotR1 = 37.2;        // groove floor (2.8 wall left to outer)
slotFloor = 74.8;
slotTop = 79.8;       // rect top (5.0 tall)
roofApex = 81.5;      // 1.7 above rect top, slopes ~35 deg
entryHalf = 4.0;      // entry notch half width (tangential)
trackA0 = -6;
trackA1 = 40;
pocketA = 32;         // locked lug centre
bumpA = 22;           // detent bump centre
bumpH = 0.3;          // graze bump (holds by friction, no press overlap)

// wedge lugs on lid plug (lid print coords)
lugR0 = 34.2;         // embedded 0.2 into plug
lugR1 = 36.8;         // tip (0.4 clear to groove floor)
lugW = 6.0;           // tangential width
lugZLow = 11.6;       // print low (assembly top, sloped face)
lugZHigh = 15.2;      // print high (assembly bottom, flat face)
lugZTip = 14.2;       // tip low (45 deg slope: run 2.6 rise 2.6)
asmTop = 90.3;        // assembly top (lid top), gap disc-to-rim 0.3

$fn = 200;

// ---------- jar ----------
module jar_blank() {
    pts = [
        [0,0],[37.5,0],[40,2.5],[40,83.5],[38.5,85],[36.5,85],
        [35,83.5],[35,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module jar_slot_once() {
    // entry notch open through rim
    translate([slotR0, -entryHalf, slotFloor])
        cube([slotR1 - slotR0, entryHalf*2, 85.5 - slotFloor]);
    // horizontal rect sector
    rotate([0,0,trackA0])
        rotate_extrude(angle=trackA1-trackA0, convexity=4)
            polygon([[slotR0,slotFloor],[slotR1,slotFloor],
                     [slotR1,slotTop],[slotR0,slotTop]]);
    // support-free roof (triangle, slopes ~35 deg from vertical)
    midr = (slotR0+slotR1)/2;
    rotate([0,0,trackA0])
        rotate_extrude(angle=trackA1-trackA0, convexity=4)
            polygon([[slotR0,slotTop],[slotR1,slotTop],[midr,roofApex]]);
}

module bump_once(a) {
    rotate([0,0,a]) hull() {
        translate([slotR0, -2.5, slotFloor]) cube([slotR1-slotR0, 5, 0.1]);
        translate([slotR0, -0.2, slotFloor+bumpH-0.1]) cube([slotR1-slotR0, 0.4, 0.1]);
    }
}

module jar() {
    union() {
        difference() {
            jar_blank();
            jar_slot_once();
            rotate([0,0,180]) jar_slot_once();
        }
        bump_once(bumpA);
        bump_once(bumpA+180);
    }
}

// ---------- lid (print orientation: top face on bed) ----------
module lid_blank() {
    pts = [
        [0,0],[38,0],[40,2],[40,3.5],[38.5,5],[plugR,5],
        [plugR,15.5],[33.4,16.5],[32.4,16.5],[plugRi,15.5],[plugRi,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module lug_once(ap) {
    rotate([0,0,ap]) hull() {
        translate([lugR0, -lugW/2, lugZLow]) cube([0.1, lugW, lugZHigh-lugZLow]);
        translate([lugR0, -lugW/2, lugZHigh-0.1]) cube([lugR1-lugR0, lugW, 0.1]);
        translate([lugR1-0.1, -lugW/2, lugZTip]) cube([0.1, lugW, lugZHigh-lugZTip]);
    }
}

module lid() {
    union() {
        lid_blank();
        lug_once(0);
        lug_once(180);
    }
}

// ---------- assembly (closed / locked) ----------
module assembly() {
    instance("jar","jar") jar();
    instance("lid","lid")
        rotate([0,0,pocketA]) translate([0,0,asmTop]) rotate([180,0,0]) lid();
}

// ---------- specs ----------
jar_bounds = [[-40,-40,0],[40,40,85]];
lid_bounds = [[-40,-40,0],[40,40,16.5]];
asm_bounds = [[-40,-40,0],[40,40,90.3]];

jar_details = [
    ["cavity", "void", [[-24,-24,6],[24,24,84]], 0.9],
    ["wall", "thickness", [50,0,40], [-1,0,0], 5],
    ["floor", "thickness", [0,0,-10], [0,0,1], 5],
    ["slot_entry", "void", [[34.9,-3.5,76],[37.1,3.5,84]], 0.9],
    ["slot_track", "void", [[29.8,17.8,75.5],[31.2,19.2,78.5]], 0.85],
    ["bump", "material", [[32.8,12.9,74.8],[33.9,14.0,75.05]], 0.4],
    ["rim_soft", "view", [[36.5,-5,82.0],[40,5,85]]],
    ["bottom_soft", "view", [[37.0,-5,-0.5],[40.5,5,3.0]]]
];
lid_details = [
    ["top", "thickness", [0,0,-10], [0,0,1], 5],
    ["plug_wall", "thickness", [50,0,10], [-1,0,0], 3],
    ["lug", "material", [[34.5,-2.0,13.5],[35.5,2.0,14.5]], 0.8],
    ["top_soft", "view", [[36.5,-5,-0.5],[40.5,5,3.0]]],
    ["tip_lead", "view", [[31.0,-5,14.5],[35.0,5,16.8]]]
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
