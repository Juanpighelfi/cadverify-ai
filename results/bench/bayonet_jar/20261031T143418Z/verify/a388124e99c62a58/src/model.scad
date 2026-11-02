// Desk jar with bayonet lid - PETG, Bambu Lab A1, 0.4 mm nozzle, no supports.
// Print orientation: +Z up, parts rest on min z. Jar upright, lid top-plate on bed (cavity up).
// Closed jar (lid placed, lugs in entries) is the assembly;
// motion lid_lock turns the lid 30 deg to lock.

R_out = 42; R_neck = 39; R_in = 35; R_lidin = 39.3;
Hj = 86; Lid_H = 25;
slot_bot = 71; slot_Rf = 37; slot_Ro = 39.1;
slot_o_top = 74; slot_i_top = 76.5;
entry_half = 5;
bump_ang = 20; lock_ang = 30;
Zlid = 90.5;

part = "jar"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

$fn = 180;

module jar_body() {
    p = concat(
        [[0,0],[40,0],[42,2.5],[42,61],[39,65],[39,85],[38,86],[36,86],[35,85],[35,9]],
        [ for (a=[-22.5,-45,-67.5]) [32+3*cos(a), 9+3*sin(a)] ],
        [[32,6],[0,6]]
    );
    rotate_extrude(convexity=6) polygon(p);
}

module slot_cutter_one(slot_ang) {
    rotate([0,0,slot_ang]) {
        translate([slot_Rf, -entry_half, slot_bot]) cube([slot_Ro-slot_Rf, entry_half*2, 87-slot_bot]);
        rotate([0,0,-7.5]) rotate_extrude(angle=45.5, convexity=6)
            polygon([[slot_Rf,slot_bot],[slot_Ro,slot_bot],[slot_Ro,slot_o_top],[slot_Rf,slot_i_top]]);
    }
}

module bump_one(slot_ang) {
    rotate([0,0,slot_ang+bump_ang]) hull() {
        translate([slot_Rf, -2, 70.5]) cube([2.1, 4, 0.6]);
        translate([slot_Rf, -0.5, 72.0]) cube([2.1, 1, 0.1]);
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
        [[0,0],[40,0],[42,2.5],[42,24],[41,25],[R_lidin,25],[R_lidin,6]],
        [ for (a=[-22.5,-45,-67.5]) [37.3+2*cos(a), 6+2*sin(a)] ],
        [[37.3,4],[0,4]]
    );
    rotate_extrude(convexity=6) polygon(p);
}

module lug_one(ang) {
    rotate([0,0,ang]) hull() {
        translate([37.5,-4,17.2]) cube([0.5,8,2]);
        translate([39.0,-4,17.2]) cube([0.5,8,2]);
    }
}

module lid() {
    lid_body();
    lug_one(0);
    lug_one(120);
    lug_one(240);
}

module assembly() {
    // lid seated in entries (unlocked); lock is +30 deg turn (motion lid_lock)
    instance("jar","jar",1) jar();
    instance("lid","lid",1) translate([0,0,Zlid]) rotate([180,0,0]) lid();
}

if (part=="jar") {
    echo(cadverify_spec = [
        ["bounds", [[-42,-42,0],[42,42,86]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",3000]]],
        ["overhangs_allowed", [
            ["detent bump underside, tiny ledge prints without supports", [[33.5,10.2,69.5],[38,15.8,71.5]]],
            ["detent bump underside, tiny ledge prints without supports", [[-31.8,21.7,69.5],[-26.5,27.2,71.5]]],
            ["detent bump underside, tiny ledge prints without supports", [[-9.3,-39.4,69.5],[-3.9,-37.5,71.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["interior","void",[[-24,-24,10],[24,24,80]],0.7],
            ["wall","thickness",[50,0,35],[-1,0,0],7],
            ["floor","thickness",[0,0,-5],[0,0,1],6],
            ["slot_entry","void",[[37.2,-4,72],[38.9,4,85]],0.9],
            ["slot_lock","void",[[32.4,18.5,72],[33.4,19.5,73.5]],0.9],
            ["bump","material",[[35.2,12.5,71.2],[36.2,13.5,72]],0.4],
            ["soft_outer","view",[[40,-2,0],[42,2,2.5]]],
            ["rim","view",[[17.5,31,85],[20,33,86]]]
        ]]
    ]);
    jar();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-42,-42,0],[42,42,25]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",3000]]],
        ["overhangs_allowed", [
            ["lug underside, 1.4 mm narrow ledge bridges without supports", [[37,-5,16.5],[39.4,5,17.7]]],
            ["lug underside, 1.4 mm narrow ledge bridges without supports", [[-23.4,30,16.5],[-14.8,36.2,17.7]]],
            ["lug underside, 1.4 mm narrow ledge bridges without supports", [[-23.4,-36.2,16.5],[-14.8,-30,17.7]]]
        ]],
        ["copies", 1],
        ["details", [
            ["cavity","void",[[-26,-26,6],[26,26,23]],0.8],
            ["lug","material",[[37.5,-3,17.5],[38.9,3,18.9]],0.6],
            ["skirt_wall","thickness",[0,50,15],[0,-1,0],2.7],
            ["top","thickness",[0,0,-5],[0,0,1],4],
            ["soft_outer","view",[[40,-2,0],[42,2,2.5]]],
            ["rim_lead","view",[[39,-2,24],[42,2,25]]]
        ]]
    ]);
    lid();
} else if (part=="assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-42,-42,0],[42,42,90.5]]],
        ["support_faces", [["desk","-z",3000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_lock", ["lid"], "rotate", [0,0,0], [0,0,1], [0,30], ["flex", [["lid","jar",0.9,"detent bump"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,-1]]
        ]]
    ]);
    assembly();
}
