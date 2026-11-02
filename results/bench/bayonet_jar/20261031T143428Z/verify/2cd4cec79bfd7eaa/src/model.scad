// Desk jar with bayonet lid — PETG, 0.4 mm nozzle, no supports.
// Jar prints upright (base on bed). Lid prints top face down (plug up).
// Assembly = closed + locked jar. Motion twist_lock = turn to unlock (lock path).

part = "jar"; // [jar:Jar, lid:Lid, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
outerR = 40;          // flush outside radius, jar + lid
boreR = 35;           // interior radius (70 across)
floorT = 5;           // jar floor thickness
jarH = 85;            // rim height; interior depth 80 (5..85)
plugR = 34.2;         // lid plug outer (0.8 clearance to bore)
plugRi = 31.2;        // plug inner (3.0 wall)
plugTipPrint = 16.5;  // plug tip in lid print coords
lidDiscT = 5;         // lid disc thickness
asmTop = 90;          // assembly lid top (disc 85..90)

// bayonet track (jar)
slotR0 = 34.5;        // groove inner edge (breaks into bore)
slotR1 = 37.5;        // groove floor (2.5 wall left)
slotFloor = 75;
slotRectTop = 79.5;   // rect roof base (4.5 tall track)
slotApex = 81.5;      // tent apex (slopes ~34 deg from vertical)
entryHalf = 4.0;      // entry notch half width
trackA0 = -7;
trackA1 = 39;
pocketA = 32;         // locked lug centre
bumpA = 22;           // detent bump centre
bumpH = 0.8;          // bump height (0.3 graze with 0.5 lug gap)
bumpTan = 2.5;        // bump tangential half length

// wedge lugs (lid print coords)
lugR0 = 34.0;         // embedded 0.2 into plug
lugR1 = 36.3;         // tip (1.2 clear to groove floor)
lugHalfW = 3.0;       // half width (6 wide)
lugRampLow = 11.7;    // ramp low (print bottom = use top)
lugRampTip = 14.1;    // ramp at tip
lugFlat = 14.5;       // flat face (print top = use bottom, 75.5 in use)

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
        cube([slotR1 - slotR0, entryHalf*2, jarH + 1 - slotFloor]);
    // horizontal rect sector
    rotate([0,0,trackA0])
        rotate_extrude(angle=trackA1-trackA0, convexity=4)
            polygon([[slotR0,slotFloor],[slotR1,slotFloor],
                     [slotR1,slotRectTop],[slotR0,slotRectTop]]);
    // support-free tent roof
    midr = (slotR0+slotR1)/2;
    rotate([0,0,trackA0])
        rotate_extrude(angle=trackA1-trackA0, convexity=4)
            polygon([[slotR0,slotRectTop],[slotR1,slotRectTop],[midr,slotApex]]);
}

module bump_once(a) {
    rotate([0,0,a]) hull() {
        translate([slotR0, -bumpTan, slotFloor-0.2])
            cube([slotR1-slotR0, bumpTan*2, 0.2]);
        translate([slotR0, -0.2, slotFloor+bumpH-0.1])
            cube([slotR1-slotR0, 0.4, 0.1]);
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

// ---------- lid (print: top face on bed) ----------
module lid_blank() {
    pts = [
        [0,0],[37.5,0],[40,2.5],[40,4],[38.5,5],[plugR,5],
        [plugR,15],[33.2,16.5],[32.2,16.5],[plugRi,15],[plugRi,5],[0,5]
    ];
    rotate_extrude(angle=360, convexity=4) polygon(pts);
}

module lug_once(ap) {
    rotate([0,0,ap]) hull() {
        translate([lugR0, -lugHalfW, lugRampLow]) cube([0.2, lugHalfW*2, lugFlat-lugRampLow]);
        translate([lugR1-0.2, -lugHalfW, lugRampTip]) cube([0.2, lugHalfW*2, lugFlat-lugRampTip]);
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

// ---------- specs (in exported part coords) ----------
jar_bounds = [[-outerR,-outerR,0],[outerR,outerR,jarH]];
lid_bounds = [[-outerR,-outerR,0],[outerR,outerR,plugTipPrint]];
asm_bounds = [[-outerR,-outerR,0],[outerR,outerR,asmTop]];

jar_details = [
    ["cavity", "void", [[-24,-24,floorT+1],[24,24,jarH-3]], 0.9],
    ["wall", "thickness", [outerR+10,0,40], [-1,0,0], outerR-boreR],
    ["floor", "thickness", [0,0,-10], [0,0,1], floorT],
    ["slot_entry", "void", [[slotR0,-entryHalf,slotFloor],[slotR1,entryHalf,jarH+0.5]], 0.9],
    ["slot_track", "void", [[29.5,18.1,slotFloor+1],[31.5,20.1,slotRectTop-1.5]], 0.85],
    ["bump", "material", [[32.4,12.5,slotFloor],[34.4,14.5,slotFloor+0.5]], 0.3],
    ["rim_soft", "view", [[36.5,-5,82.0],[40,5,jarH]]],
    ["bottom_soft", "view", [[37.0,-5,-0.5],[40.5,5,3.5]]]
];
lid_details = [
    ["top", "thickness", [0,0,-10], [0,0,1], lidDiscT],
    ["plug_wall", "thickness", [50,0,10], [-1,0,0], plugR-plugRi],
    ["lug", "material", [[34.3,-1.5,13.8],[35.8,1.5,14.3]], 0.8],
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
