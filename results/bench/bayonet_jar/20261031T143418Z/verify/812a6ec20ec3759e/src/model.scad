// Desk jar with bayonet lid - PETG, Bambu A1, 0.4mm nozzle, no supports
// Print orientation: +Z up, parts rest on min z. Jar upright, lid opening up (top plate on bed).

R_out = 42; R_neck = 39; R_in = 35; R_lidin = 39.3;
Hj = 86; floor_t = 6; Lid_H = 25; top_t = 4;
slot_bot = 71; slot_Rf = 37; slot_Ro = 39.1;
entry_half = 5;
Zlid = 91;

part = "jar"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

$fn = 180;

module jar_body() {
    pts = [
        [0,0],[40,0],[42,2],[42,63],[39,66],[39,85],[38,86],[36,86],[35,85],[35,9],
        [34.12,7.76],[32.76,6.88],[31.12,6.12],[32-3+3*cos(-22.5),6+3+3*sin(-22.5)]
    ];
    // rebuild cleanly with fillet arc
    p = concat(
        [[0,0],[40,0],[42,2],[42,63],[39,66],[39,85],[38,86],[36,86],[35,85],[35,9]],
        [ for (a=[-22.5,-45,-67.5]) [32+3*cos(a), 9+3*sin(a)] ],
        [[32,6],[0,6]]
    );
    rotate_extrude(convexity=6) polygon(p);
}

module slot_cutter_one(slot_ang) {
    rotate([0,0,slot_ang]) {
        translate([slot_Rf, -entry_half, slot_bot]) cube([slot_Ro-slot_Rf, entry_half*2, 87-slot_bot]);
        rotate([0,0,-7.5]) rotate_extrude(angle=45.5, convexity=6)
            polygon([[slot_Rf,slot_bot],[slot_Ro,slot_bot],[slot_Ro,78],[slot_Rf,76]]);
    }
}

module bump_one(slot_ang) {
    rotate([0,0,slot_ang+20]) hull() {
        translate([37, -1.5, 70.9]) cube([2, 3, 0.1]);
        translate([37, -0.5, 72.3]) cube([2, 1, 0.1]);
    }
}

module jar() {
    difference() {
        jar_body();
        slot_cutter_one(0);
        slot_cutter_one(120);
        slot_cutter_one(240);
    }
    bump_one(0);
    bump_one(120);
    bump_one(240);
}

module lid_body() {
    p = concat(
        [[0,0],[40,0],[42,2],[42,24],[41,25],[39.3,25],[39.3,6]],
        [ for (a=[-22.5,-45,-67.5]) [37.3+2*cos(a), 6+2*sin(a)] ],
        [[37.3,4],[0,4]]
    );
    rotate_extrude(convexity=6) polygon(p);
}

module lug_one(ang) {
    rotate([0,0,ang]) hull() {
        translate([37.2,-4,19.4]) cube([2.3,8,0.1]);
        translate([39.4,-4,13.4]) cube([0.1,8,0.1]);
        translate([37.2,-4,15.4]) cube([0.1,8,0.1]);
    }
}

module lid() {
    lid_body();
    lug_one(0);
    lug_one(120);
    lug_one(240);
}

module assembly() {
    instance("jar","jar",1) jar();
    instance("lid","lid",1) translate([0,0,Zlid]) rotate([0,0,30]) rotate([180,0,0]) lid();
}

if (part=="jar") {
    echo(cadverify_spec = [
        ["bounds", [[-42,-42,0],[42,42,86]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["interior","void",[[-35,-35,6],[35,35,86]],0.7],
            ["wall","thickness",[50,0,35],[-1,0,0],5],
            ["floor","thickness",[0,0,-5],[0,0,1],6],
            ["slot_entry","void",[[37,-5,71],[39.1,5,87]],0.9],
            ["slot_lock","void",[[31.9,18,72],[33.9,20,74]],0.9],
            ["bump","material",[[34.5,12,71],[36.5,14,72.3]],0.4],
            ["soft_outer","view",[[40,-2,0],[42,2,2]]],
            ["rim","view",[[37,0,85],[39,2,86]]]
        ]]
    ]);
    jar();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-42,-42,0],[42,42,25]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["cavity","void",[[-39,-39,4],[39,39,25]],0.5],
            ["lug","material",[[37.2,-4,13.4],[39.5,4,19.5]],0.4],
            ["skirt_wall","thickness",[0,50,15],[0,-1,0],2.5],
            ["top","thickness",[0,0,-5],[0,0,1],4],
            ["soft_outer","view",[[40,-2,0],[42,2,2]]],
            ["rim_lead","view",[[39,-2,24],[42,2,25]]]
        ]]
    ]);
    lid();
} else if (part=="assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-42,-42,0],[42,42,91]]],
        ["support_faces", [["desk","-z",3000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_lock", ["lid"], "rotate", [0,0,0], [0,0,1], [-30,0], ["flex", [["lid","jar",0.9,"detent bump"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,100], ["rotate", [0,0,0], [0,0,1], 30]]
        ]]
    ]);
    assembly();
}
