// Desk jar with bayonet lid — PETG, 0.4mm nozzle, no supports.
// Jar prints upright (base on bed). Lid prints top-down (top face on bed).
// Assembly = closed (seated, flush) jar; twist_lock ends locked.

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
plugR = 34.2;         // lid plug outer (0.8 clearance to bore)
plugRi = 31.2;        // plug inner (3.0 wall)
plugBot = 5;          // plug base in lid print coords (disc top)
plugTipZ = 16.5;      // plug tip in print coords
lidTopH = 5;          // disc thickness

// bayonet track on jar inner wall
slotR0 = 34.5;        // inner edge (breaks into bore for clean cut)
slotR1 = 37.5;        // groove floor (2.5 wall left to outer)
slotFloor = 75;
slotTop = 79;         // rect top (4.0 tall)
roofApex = 81.5;      // 2.5 above rect top
entryHalf = 4.0;      // entry notch half width (tangential)
trackA0 = -7;
trackA1 = 75;
pocketA = 65;         // locked lug centre
bumpA = 50;           // detent bump centre
bumpH = 0.8;          // bump height above track floor

// wedge lugs on lid plug (lid print coords)
lugR0 = 34.0;         // embedded 0.2 into plug
lugR1 = 36.0;         // tip (1.5 clear to groove floor)
lugW = 6.0;           // tangential width
lugZLow = 11.5;       // print low (assembly top)
lugZHigh = 14.5;      // print high (assembly bottom)
lugZTip = 13.57;      // tip low (44deg slope)
asmTop = 90;          // assembly top (lid top), disc 85..90

$fn = 200;

// ---------- jar ----------
module jar_blank() {
    pts = [
        [0,0],[37,0],[40,3.5],[40,83],[38.5,85],[36.5,85],
        [35,83.5],[35,9],[31,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module jar_slot_once() {
    // entry notch open through rim
    translate([slotR0, -entryHalf, slotFloor])
        cube([slotR1 - slotR0, entryHalf*2, 86 - slotFloor]);
    // horizontal rect sector
    rotate([0,0,trackA0])
        rotate_extrude(angle=trackA1-trackA0, convexity=4)
            polygon([[slotR0,slotFloor],[slotR1,slotFloor],
                     [slotR1,slotTop],[slotR0,slotTop]]);
    // support-free roof (tent, slopes ~28deg from vertical)
    midr = (slotR0+slotR1)/2;
    rotate([0,0,trackA0])
        rotate_extrude(angle=trackA1-trackA0, convexity=4)
            polygon([[slotR0,slotTop],[slotR1,slotTop],[midr,roofApex]]);
}

module bump_once(a) {
    rotate([0,0,a]) hull() {
        translate([slotR0, -2.5, slotFloor-0.2]) cube([slotR1-slotR0, 5, 0.2]);
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
        [0,0],[37.5,0],[40,3],[40,3.5],[38.5,5],[plugR,5],
        [plugR,15],[33.2,16.5],[32.2,16.5],[plugRi,15],[plugRi,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module lug_once(ap) {
    rotate([0,0,ap]) hull() {
        translate([lugR0, -lugW/2, lugZLow]) cube([0.2, lugW, lugZHigh-lugZLow]);
        translate([lugR1-0.2, -lugW/2, lugZTip]) cube([0.2, lugW, lugZHigh-lugZTip]);
    }
}

module lid() {
    union() {
        lid_blank();
        lug_once(0);
        lug_once(180);
    }
}

// ---------- assembly (closed / seated, lugs in entries) ----------
module assembly() {
    instance("jar","jar") jar();
    instance("lid","lid")
        translate([0,0,asmTop]) rotate([180,0,0]) lid();
}

// ---------- specs ----------
jar_bounds = [[-40,-40,0],[40,40,85]];
lid_bounds = [[-40,-40,0],[40,40,16.5]];
asm_bounds = [[-40,-40,0],[40,40,90]];

jar_details = [
    ["cavity", "void", [[-24,-24,6],[24,24,82]], 0.9],
    ["wall", "thickness", [50,0,40], [-1,0,0], 5],
    ["floor", "thickness", [0,0,-10], [0,0,1], 5],
    ["slot_entry", "void", [[34.5,-4,75],[37.5,4,86]], 0.9],
    ["slot_track", "void", [[30.2,17,76],[32.2,19,78]], 0.85],
    ["bump", "material", [[21,25.5,74.5],[25.5,29.5,75.9]], 0.3],
    ["rim_soft", "view", [[36.5,-5,82.0],[40,5,85]]],
    ["bottom_soft", "view", [[37.0,-5,-0.5],[40.5,5,3.5]]]
];
lid_details = [
    ["top", "thickness", [0,0,-10], [0,0,1], 5],
    ["plug_wall", "thickness", [50,0,10], [-1,0,0], 3],
    ["lug", "material", [[34.2,-2,12.5],[35.8,2,14.2]], 0.5],
    ["top_soft", "view", [[36.5,-5,-0.5],[40.5,5,3.5]]],
    ["tip_lead", "view", [[31.0,-5,14.5],[35.0,5,17.0]]]
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
            ["lift_off", ["lid"], "slide", [0,0,1], [0,15]],
            ["twist_lock", ["lid"], "rotate", [0,0,0], [0,0,1], [0,65], ["flex", [["lid","jar",1.0,"detent bump cams over"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,-1]]
        ]],
        ["overhangs_allowed", []]
    ]);
    assembly();
} else {
    jar();
}
