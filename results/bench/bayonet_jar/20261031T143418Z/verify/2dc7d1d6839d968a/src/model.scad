// Desk jar with bayonet lid - PETG, Bambu Lab A1, 0.4 mm nozzle, no supports.
// Print orientation: +Z up, parts rest on min z. Jar upright, lid top-plate on bed (cavity up).

R_out = 42; R_neck = 39; R_in = 35; R_lidin = 39.3;
Hj = 86; floor_t = 6; Lid_H = 25; top_t = 4;
slot_bot = 71; slot_Rf = 37; slot_Ro = 39.1;
slot_o_top = 73.5; slot_i_top = 76;
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
        translate([slot_Rf, -0.5, 72.9]) cube([2.1, 1, 0.1]);
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
        translate([39.0,-4,17.5]) cube([0.5,8,0.7]);
        translate([37.5,-4,15.7]) cube([0.5,8,2.5]);
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
    instance("lid","lid",1) translate([0,0,Zlid]) rotate([0,0,lock_ang]) rotate([180,0,0]) lid();
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
            ["interior","void",[[-24,-24,10],[24,24,80]],0.7],
            ["wall","thickness",[50,0,35],[-1,0,0],7],
            ["floor","thickness",[0,0,-5],[0,0,1],6],
            ["slot_entry","void",[[37.2,-4,72],[38.9,4,85]],0.9],
            ["slot_lock","void",[[32.6,18.6,71.8],[33.4,19.4,73]],0.9],
            ["bump","material",[[35.3,12.6,71.5],[36.3,13.6,72.5]],0.4],
            ["soft_outer","view",[[40,-2,0],[42,2,2.5]]],
            ["rim","view",[[36,-1,85],[38.5,1,86]]]
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
            ["cavity","void",[[-26,-26,6],[26,26,23]],0.8],
            ["lug","material",[[37.7,-3,16.5],[38.8,3,17.9]],0.5],
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
            ["lid_lock", ["lid"], "rotate", [0,0,0], [0,0,1], [-30,0], ["flex", [["lid","jar",0.9,"detent bump"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,-1], ["rotate", [0,0,0], [0,0,1], 30]]
        ]]
    ]);
    assembly();
}
