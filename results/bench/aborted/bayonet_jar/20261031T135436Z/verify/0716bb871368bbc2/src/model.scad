/* Desk jar with bayonet lid - PETG, Bambu A1, 0.4 nozzle, no supports */
// Print orientation: jar upright (opening up), lid flat-top down (opening up)

part = "assembly"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
innerD = 70; innerR = 35;
innerDepth = 80;
floorT = 4;
rimZ = floorT + innerDepth; // 84
Rbody = 41;       // D 82
Rneck = 38.5;     // D 77
Rin = 35;
RskirtIn = 38.9;  // neck + 0.4 clearance
Rtip = 37.0;      // lug tip
Rgroove = 36.7;   // groove bottom radius (depth 1.8)
slotFloorZ = 71.0;
slotTopInnerZ = 75.8;
slotTopOuterZ = 77.3;
slotEntryW = 9;
lugWbase = 8; lugWtip = 7;
lugHbase = 4; lugHtip = 2;
lugBotZ = 12; lugTopZ = 16; // print coords
lidH = 19;
lidDiscT = 3;
shoulderZ = 68;
nLugs = 3;
lockAngle = 90; // degrees clockwise to lock

$fn = 180;

module jar_outer() {
    pts = [
        [0,0],[39,0],[41,2],[41,67],[40,68],[38.5,68],
        [38.5,83],[37.5,84],[36,84],[35,83],[35,7],
        [34.12,4.88],[32,4],[0,4]
    ];
    rotate_extrude(angle=360) polygon(pts);
}

module vslot(th) {
    rotate([0,0,th]) translate([38.6,0,78]) cube([3.8,9,14],center=true);
}

module hslot(th0) {
    start = th0-96; span = 102.7;
    rotate([0,0,start]) rotate_extrude(angle=span)
        polygon([[36.7,71],[40.5,71],[40.5,77.3],[36.7,75.8]]);
}

module bump(thb) {
    // trapezoidal bump on slot floor, base embedded 0.2
    rotate([0,0,thb]) translate([37.6,0,0])
        hull() {
            translate([0,0,70.85]) cube([1.8,6,0.1],center=true);
            translate([0,0,71.8]) cube([1.8,2,0.1],center=true);
        }
}

module jar() {
    union() {
        difference() {
            jar_outer();
            for (i=[0:2]) {
                th0 = i*120;
                vslot(th0);
                hslot(th0);
            }
        }
        for (i=[0:2]) {
            th0 = i*120;
            thb = th0-84;
            bump(thb);
        }
    }
}

module lid_outer() {
    pts = [
        [0,0],[39,0],[41,2],[41,18],[40,19],[39.4,19],
        [38.9,18.5],[38.9,5],[38.314,3.586],[36.9,3],[0,3]
    ];
    rotate_extrude(angle=360) polygon(pts);
}

module lug(th) {
    rotate([0,0,th]) translate([0,0,0])
    {
        // local: X radial, build via hull of base and tip boxes
        rotate([0,0,0]) {}
    }
}

module lug_at(th) {
    rotate([0,0,th])
        hull() {
            // base box (embedded 0.2 into skirt): X 38.0..39.1
            translate([38.55,0,14]) cube([1.1,8,4],center=true);
            // tip box: X ~37.0
            translate([37.0,0,14]) cube([0.1,7,2],center=true);
        }
}

module lid() {
    union() {
        lid_outer();
        for (i=[0:2]) {
            th0 = i*120;
            thlug = th0-90;
            lug_at(thlug);
        }
    }
}

module assembly() {
    instance("jar_body","jar",1) jar();
    // lid print (top down) flipped to use: rotate 180 about X then lift
    instance("lid_top","lid",1)
        translate([0,0,87.4]) rotate([180,0,0]) lid();
}

// specs
if (part=="jar") {
    echo(cadverify_spec = [
        ["bounds", [[-41,-41,0],[41,41,84]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base","-z",2000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["cavity","void",[[-24,-24,10],[24,24,78]],0.9],
            ["slot_void","void",[[36.8,-30,71.5],[38.4,-20,75.0]],0.9],
            ["detent","material",[[2,-39,71],[6,-36,72]],0.3],
            ["body_wall","thickness",[45,0,40],[-1,0,0],6],
            ["floor","thickness",[0,0,-5],[0,0,1],4],
            ["groove_wall","thickness",[38,0,73.4],[-1,0,0],1.7],
            ["soft_edge","view",[[38,-5,0],[42,5,3]]]
        ]]
    ]);
    jar();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-41,-41,0],[41,41,19]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base","-z",2000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["lug","material",[[-4,-39.5,12],[4,-36.5,16]],0.25],
            ["skirt","thickness",[45,0,10],[-1,0,0],2.1],
            ["top","thickness",[0,0,-5],[0,0,1],3],
            ["pocket","void",[[-20,-20,5],[20,20,15]],0.9],
            ["soft_edge","view",[[38,-5,0],[42,5,3]]]
        ]]
    ]);
    lid();
} else if (part=="assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-41,-41,0],[41,41,87.4]]],
        ["support_faces", [["desk","-z",2000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["twist_lock", ["lid_top"], "rotate", [0,0,0], [0,0,1], [0,90],
                ["flex", [["lid_top","jar_body",0.9,"detent bump ride-over"]]]]
        ]],
        ["assembly_order", [
            [[ "jar_body"], [0,0,0]],
            [[ "lid_top"], [0,0,-1], ["rotate", [0,0,0], [0,0,1], -90]]
        ]]
    ]);
    assembly();
}
