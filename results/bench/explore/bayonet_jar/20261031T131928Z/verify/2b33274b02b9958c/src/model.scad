// Desk jar with bayonet lid - PETG, 0.4mm nozzle, support-free
// Print orientations: jar upright (bottom on bed), lid top-face down (plug up)
// Units: mm

part = "jar"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
R_in = 35;          // interior radius (70 across)
R_out = 40;         // exterior radius (80 OD)
floor_t = 5;        // jar floor thickness
H_jar = 85;         // jar total height (5 floor + 80 depth)
lid_disk_t = 5;     // lid disk thickness
plug_len = 14;      // plug length below lid underside (use)
plug_R_out = 34.5;  // plug outer radius (0.5 clearance to 35)
plug_R_in = 31.5;   // plug inner radius (3mm wall)
H_lid_print = 19;   // lid print height = 5 disk + 14 plug
lug_H = 3.0;        // lug axial height
lug_W = 7.0;        // lug tangential width
lug_P = 2.4;        // lug radial protrusion from plug surface
lug_outer_R = plug_R_out + lug_P; // 36.9
slot_R_in = 34.5;   // slot inner radius (opened to interior)
slot_R_out = 38.3;  // slot outer radius (depth 3.8, leaves 1.7 wall)
slot_z0 = 72;       // slot floor
slot_z_in_top = 76; // slot inner top (height 4)
slot_z_out_top = 79.7; // slot outer top (45 deg slope: 76+3.7)
entry_half = 4.0;   // entry half-width tangential
bump_h = 0.5;
bump_R_mid = 36.4;

// ---------- jar profile (r,z) for rotate_extrude ----------
function jar_profile() =
    let(
        arc = [for(a=[0:-15:-90]) [32+3*cos(a), 8+3*sin(a)]]
    )
    concat(
        [[0,0],[38,0],[40,2],[40,83.5],[38.5,85],[36.5,85],[35,83.5],[35,8]],
        [for(i=[1:len(arc)-1]) arc[i]],
        [[32,5],[0,5]]
    );

module jar_base() {
    rotate_extrude($fn=160)
        polygon(points=jar_profile());
}

module jar_slots_sub() {
    // entry boxes
    translate([34.5, -entry_half, slot_z0])
        cube([slot_R_out-34.5, entry_half*2, 86-slot_z0]);
    translate([-slot_R_out, -entry_half, slot_z0])
        cube([slot_R_out-34.5, entry_half*2, 86-slot_z0]);
    // horizontal sectors with 45deg sloped top (radial slope)
    slot_prof = [[slot_R_in,slot_z0],[slot_R_out,slot_z0],[slot_R_out,slot_z_out_top],[slot_R_in,slot_z_in_top]];
    rotate([0,0,-7])
        rotate_extrude(angle=104, $fn=120)
            polygon(points=slot_prof);
    rotate([0,0,173])
        rotate_extrude(angle=104, $fn=120)
            polygon(points=slot_prof);
}

module jar_bump_one(ang) {
    // ang degrees, on slot floor
    r = bump_R_mid;
    x = r*cos(ang);
    y = r*sin(ang);
    translate([x,y,slot_z0])
        scale([1.85, 2.0, bump_h])
            sphere(r=1, $fn=24);
}

module jar_print() {
    difference() {
        jar_base();
        jar_slots_sub();
    }
    // detent bumps (added after slots)
    jar_bump_one(80);
    jar_bump_one(260);
}

// ---------- lid profile (r,z) in PRINT orientation (top down, plug up) ----------
function lid_profile() =
    let(
        arc2 = [for(a=[0:-15:-90]) [29.5+2*cos(a), 7+2*sin(a)]]
    )
    concat(
        [[0,0],[38,0],[40,2],[40,3.5],[38.5,5],[34.5,5],[34.5,18],[33.5,19],[32.5,19],[31.5,18],[31.5,7]],
        [for(i=[1:len(arc2)-1]) arc2[i]],
        [[29.5,5],[0,5]]
    );

module lid_base() {
    rotate_extrude($fn=160)
        polygon(points=lid_profile());
}

module lug_at_0() {
    // box lug, print coords: x radial 34.4..36.9, y +-3.5, z 14.5..17.5
    translate([34.4, -lug_W/2, 16-lug_H/2])
        cube([lug_outer_R-34.4, lug_W, lug_H]);
}

module lid_print() {
    union() {
        lid_base();
        lug_at_0();
        rotate([0,0,180]) lug_at_0();
    }
}

// lid in USE orientation (plug down), positioned for assembly (locked at 90deg)
module lid_use_locked() {
    // print lid has lugs at 0/180 along X; rotate 90 then flip
    translate([0,0,90])
        rotate([180,0,0])
            rotate([0,0,90])
                lid_print();
}

// ---------- assembly ----------
module assembly() {
    instance("jar","jar",1) jar_print();
    instance("lid","lid",1) lid_use_locked();
}

// ---------- specs ----------
if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-40,0],[40,40,85]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["slot1 ceiling, 45deg roof + short bridge", [[-5,-5,70],[39,39,79]]],
            ["slot2 ceiling, 45deg roof + short bridge", [[-39,-39,70],[5,5,79]]]
        ]],
        ["copies", 1],
        ["details", [
            ["cavity","void",[[-24,-24,10],[24,24,80]],0.95],
            ["wall","thickness",[50,0,40],[-1,0,0],5],
            ["floor","thickness",[0,0,-5],[0,0,1],5],
            ["slot_entry","void",[[34.5,-4,72],[38.2,4,84]],0.9],
            ["slot_entry2","void",[[-38.2,-4,72],[-34.5,4,84]],0.9],
            ["detent","material",[[5,34,70.5],[7.7,37.7,71.6]],0.4],
            ["detent2","material",[[-7.7,-37.7,70.5],[-5,-34,71.6]],0.4],
            ["mouth_chamfer","hole",[0,0,95],[0,0,-1],[[0,73],[1.5,70]]],
            ["soft_edge","view",[[35,-5,0],[41,5,3]]]
        ]]
    ]);
    jar_print();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-40,0],[40,40,19]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["lug underside cantilever, PETG short bridge", [[34,-4,14],[37.5,4,18]]],
            ["lug2 underside cantilever, PETG short bridge", [[-37.5,-4,14],[-34,4,18]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lug_a","material",[[34.4,-3.5,14.5],[36.9,3.5,17.5]],0.9],
            ["lug_b","material",[[-36.9,-3.5,14.5],[-34.4,3.5,17.5]],0.9],
            ["top","thickness",[0,0,-5],[0,0,1],5],
            ["plug_wall","thickness",[50,0,12],[-1,0,0],3],
            ["lid_edge","view",[[35,-5,0],[41,5,3]]]
        ]]
    ]);
    lid_print();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-40,0],[40,40,90]]],
        ["support_faces", [["desk","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lock", ["lid"], "rotate", [0,0,0], [0,0,1], [-90,0]]
        ]],
        ["assembly_order", [
            [[ "jar" ], [0,0,0]],
            [[ "lid" ], [0,0,-1], ["rotate", [0,0,0], [0,0,1], 90]]
        ]]
    ]);
    assembly();
}
