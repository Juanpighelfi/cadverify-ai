// Desk jar with bayonet lid - PETG, Bambu A1, 0.4mm nozzle, no supports
// Print orientation: +Z up, parts rest on min z. Jar upright, lid opening up.

Do = 80; Di = 70;
outer_R = Do/2; // 40
inner_R = Di/2; // 35
Hj = 86;
floor_t = 6;
shoulder_z = 70;
neck_D = 74; neck_R = neck_D/2; // 37
lid_H = 22; lid_top_t = 4;
radial_clear = 0.3;
lid_in_R = neck_R + radial_clear; // 37.3
slot_bot = 71.6;
slot_top_outer = 76.4;
slot_top_inner = 73.9;
slot_floor_R = 34.5;
slot_outer_R = 38;
entry_half = 5.4; // tangential half width
bump_ang = 20;
lock_ang = 30;

part = "jar"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

$fn = 128;

module jar_body() {
    // profile r,z with chamfers + floor fillet
    // fillet arc points
    pts = concat(
        [[0,0],[38,0],[40,2],[40,69],[39,70],[37,70],[37,85.2],[36.2,86],[35.8,86],[35,85.2],[35,9]],
        [ for (a=[-22.5,-45,-67.5]) [32+3*cos(a), 9+3*sin(a)] ],
        [[32,6],[0,6]]
    );
    rotate_extrude(convexity=4) polygon(pts);
}

module slot_cutter_one(slot_ang) {
    // vertical entry
    // horizontal arc from -8.5 to +38 deg relative to slot center
    rotate([0,0,slot_ang]) {
        // vertical box: x radial 34.5..38, y +-5.4, z 71.6..87
        translate([slot_floor_R, -entry_half, slot_bot]) cube([slot_outer_R-slot_floor_R, entry_half*2, 87-slot_bot]);
        // horizontal curved slot
        rotate([0,0,-8.5]) rotate_extrude(angle=46.5, convexity=4)
            polygon([[slot_floor_R,slot_bot],[slot_outer_R,slot_bot],[slot_outer_R,slot_top_outer],[slot_floor_R,slot_top_inner]]);
    }
}

module bump_one(slot_ang) {
    rotate([0,0,slot_ang+bump_ang]) hull() {
        translate([slot_floor_R, -2, slot_bot]) cube([2.5, 4, 0.1]);
        translate([slot_floor_R, -1.2, 72.3]) cube([2.5, 2.4, 0.1]);
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
    pts = concat(
        [[0,0],[38,0],[40,2],[40,21],[39,22],[38.3,22],[lid_in_R,21],[lid_in_R,6]],
        [ for (a=[-22.5,-45,-67.5]) [35.3+2*cos(a), 6+2*sin(a)] ],
        [[35.3,4],[0,4]]
    );
    rotate_extrude(convexity=4) polygon(pts);
}

module lug_one(ang) {
    rotate([0,0,ang]) hull() {
        translate([37.4,-5,16]) cube([0.1,10,4]);
        translate([35.3,-5,18]) cube([0.1,10,2]);
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
    instance("lid","lid",1) translate([0,0,92]) rotate([0,0,30]) rotate([180,0,0]) lid();
}

// ---- specs ----
if (part=="jar") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-40,0],[40,40,86]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["interior","void",[[-35,-35,6],[35,35,86]],0.7],
            ["wall","thickness",[50,0,35],[-1,0,0],5],
            ["floor","thickness",[0,0,-5],[0,0,1],6],
            ["slot_entry","void",[[34.5,-5.4,71.6],[38,5.4,87]],0.9],
            ["slot_lock","void",[[30.18,17,72],[32.18,19,74]],0.9],
            ["bump","material",[[33.09,11.73,71.8],[34.09,12.73,72.3]],0.8],
            ["soft_outer","view",[[36,-4,0],[40,4,2]]],
            ["rim","view",[[35,0,85],[37,4,86]]]
        ]]
    ]);
    jar();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-40,0],[40,40,22]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["cavity","void",[[-35,-35,4],[35,35,22]],0.7],
            ["lug","material",[[35.3,-5,16],[37.5,5,20]],0.6],
            ["skirt_wall","thickness",[0,50,10],[0,-1,0],2.7],
            ["top","thickness",[0,0,-5],[0,0,1],4],
            ["soft_outer","view",[[36,-4,0],[40,4,2]]],
            ["rim_lead","view",[[37,-4,21],[40,4,22]]]
        ]]
    ]);
    lid();
} else if (part=="assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-40,0],[40,40,92]]],
        ["support_faces", [["desk","-z",3000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_lock", ["lid"], "rotate", [0,0,0], [0,0,1], [-30,0], ["flex", [["lid","jar",0.8,"detent bump"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,120], ["rotate", [0,0,0], [0,0,1], 30]]
        ]]
    ]);
    assembly();
}
