// Desk jar with bayonet lid - PETG, Bambu A1, 0.4 nozzle
// Units mm. Print orientation: +Z up, parts rest on min z.

part = "assembly"; // [jar, lid, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters ----
Rin = 35;          // inner radius (dia 70)
Rout = 39;         // outer radius (dia 78)
Hjar = 86;         // jar height (floor 6 + depth 80)
floor_t = 6;
Wv = 8;            // vertical slot width (tangential)
groove_r1 = 34.4;  // slot cut inner (inside bore to ensure cut)
groove_r2 = 37.2;  // slot cut outer (depth 2 into wall, leaves 1.8)
ZF = 74;           // horizontal slot floor
ZRI = 78.8;        // horizontal slot roof at mouth (slot height 4.8)
ZRO = 82.3;        // horizontal slot roof at back (chamfer rise 3.5, angle ~38deg)
hstart0 = -7; hspan = 97; // horizontal arc start/sweep (covers -7..90)
hstart1 = 173;

Rplug = 33.8;
lidR = 39;
lidT = 6;
plug_bot = 5.8; plug_mid = 16.5; plug_tip = 18.0;
lug_x0 = 33.3; lug_w = 7; lug_len = 3.3; lug_z0 = 13.6; lug_h = 4; // tip at 36.6
bump_h = 1.2; bump_base = 73.8; bump_top = 75.0; // exposed 1.0 above floor 74

$fn = 128;

// ---- jar ----
module jar_outer() {
    rotate_extrude($fn=128)
        polygon(points=[[0,0],[37.5,0],[39,1.5],[39,84.5],[37.5,86],[0,86]]);
}
module jar_inner() {
    rotate_extrude($fn=128)
        polygon(points=[[0,6],[30,6],[35,11],[35,86],[0,86]]);
}
module vertical_slot(a) {
    rotate([0,0,a]) translate([34.4,-4,74]) cube([3.0,8,12.6]);
}
module horizontal_slot(start, sweep) {
    rotate([0,0,start]) rotate_extrude(angle=sweep, $fn=128)
        polygon(points=[[34.4,74],[37.2,74],[37.2,82.3],[34.4,78.8]]);
}
module bump(a) {
    rotate([0,0,a]) translate([36,0,73.8])
        polyhedron(points=[
            [-1.1,-2.5,0],[1.1,-2.5,0],[1.1,2.5,0],[-1.1,2.5,0],
            [-1.1,-1,1.2],[1.1,-1,1.2],[1.1,1,1.2],[-1.1,1,1.2]
        ], faces=[
            [0,3,2,1],[4,5,6,7],[0,1,5,4],[2,3,7,6],[3,0,4,7],[1,2,6,5]
        ]);
}
module jar() {
    union() {
        difference() {
            jar_outer();
            jar_inner();
            vertical_slot(0);
            vertical_slot(180);
            horizontal_slot(hstart0, hspan);
            horizontal_slot(hstart1, hspan);
        }
        bump(80);
        bump(260);
    }
}

// ---- lid (print orientation: outer top on bed z=0, plug up) ----
module lid_disc() {
    rotate_extrude($fn=128)
        polygon(points=[[0,0],[37.5,0],[39,1.5],[39,4.5],[37.5,6],[0,6]]);
}
module lid_plug() {
    union() {
        translate([0,0,5.8]) cylinder(r=33.8, h=10.7, $fn=128);
        translate([0,0,16.5]) cylinder(r1=33.8, r2=32.3, h=1.5, $fn=128);
    }
}
module lug(a) {
    rotate([0,0,a]) translate([33.3,-3.5,13.6]) cube([3.3,7,4]);
}
module lid() {
    union() {
        lid_disc();
        lid_plug();
        lug(0);
        lug(180);
    }
}

module assembly() {
    instance("jar","jar") jar();
    instance("lid","lid") translate([0,0,92]) rotate([0,0,90]) rotate([180,0,0]) lid();
}

if (part == "jar") jar();
else if (part == "lid") lid();
else if (part == "assembly") assembly();

// ---- specs ----
if (part == "jar") echo(cadverify_spec = [
    ["bounds", [[-39,-39,0],[39,39,86]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["base","-z",4000]]],
    ["overhangs_allowed", [
        ["bayonet slot chamfered roofs support-free", [[0,-5,73],[38,38,83]]],
        ["bayonet slot chamfered roofs support-free", [[-38,-38,73],[0,5,83]]]
    ]],
    ["copies", 1],
    ["details", [
        ["cavity","void",[[-34,-34,7],[34,34,85]],0.7],
        ["wall","thickness",[50,0,40],[-1,0,0],3],
        ["floor","thickness",[0,0,-5],[0,0,1],5],
        ["slot_entry_0","void",[[33,-4,74],[38,4,87]],0.5],
        ["slot_entry_1","void",[[-38,-4,74],[-33,4,87]],0.5],
        ["slot_horiz_0","void",[[0,0,74],[37,37,79]],0.3],
        ["slot_horiz_1","void",[[-37,-37,74],[0,0,79]],0.3],
        ["detent_0","material",[[3,33,73.8],[9,38,75.2]],0.2],
        ["detent_1","material",[[-9,-38,73.8],[-3,-33,75.2]],0.2],
        ["outer_finish","view",[[-39,-5,20],[39,5,30]]],
        ["flush_rim","view",[[-39,-39,82],[39,39,86]]]
    ]]
]);
if (part == "lid") echo(cadverify_spec = [
    ["bounds", [[-39,-39,0],[39,39,18]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["top","-z",4000]]],
    ["overhangs_allowed", [
        ["lug undersides short 3mm bridges support-free in PETG", [[32,-5,13],[38,5,18]]],
        ["lug undersides short 3mm bridges support-free in PETG", [[-38,-5,13],[-32,5,18]]]
    ]],
    ["copies", 1],
    ["details", [
        ["plug_body","material",[[-30,-30,6],[30,30,16]],0.8],
        ["lug_0","material",[[32,-4,13],[37,4,18]],0.3],
        ["lug_1","material",[[-37,-4,13],[-32,4,18]],0.3],
        ["lid_top","thickness",[0,0,25],[0,0,-1],15],
        ["disc_floor","thickness",[20,0,-5],[0,0,1],5],
        ["soft_top","view",[[-39,-39,-1],[39,39,2]]],
        ["grip_side","view",[[-39,-39,1],[39,39,5]]]
    ]]
]);
if (part == "assembly") echo(cadverify_spec = [
    ["bounds", [[-39,-39,0],[39,39,92]]],
    ["support_faces", [["desk","-z",4000]]],
    ["allowed_interferences", []],
    ["motions", [
        ["twist_lock",["lid"],"rotate",[0,0,86],[0,0,1],[-90,0],["flex",[["lid","jar",0.7,"detent bump ride-over"]]]]
    ]],
    ["assembly_order", [
        [[ "jar" ], [0,0,0]],
        [[ "lid" ], [0,0,1], ["rotate", [0,0,86],[0,0,1],90]]
    ]],
    ["overhangs_allowed", []]
]);
