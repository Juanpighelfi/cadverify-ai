// Print-in-hand hinged box 80x60x40 (hinge knuckles protrude 9 at back).
// Parts print separately in one job, no supports; pin slides in, caps press on.
// Assembly shown closed; lid swings 0..110 deg about X axis at (y=-35,z=30).
part = "box";
$fn = 32;

W=80; D=60; Hb=30; GAP=0.4; HL=9.6;
WT=2.4; FT=2.4;
AXY=-35; AXZ=30; KR=4; BR=2.35; KL=12.6; PITCH=13.1;
BOXC=[-26.2,0,26.2]; LIDC=[-13.1,13.1];
SKT=26;                    // skirt/knuckle Bauteil-Unterkante (Druck)
PIN_R=2; PIN_L=67.5; CAP_R=3; CAP_HOLE=1.85; CAP_T=2;

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module knuckle(cx, ay, az) {
    translate([cx, ay, az]) rotate([0,90,0])
        difference() {
            cylinder(r=KR, h=KL, center=true);
            cylinder(r=BR, h=KL+0.4, center=true);
        }
}
module webbox(cx) translate([cx-KL/2, -36, 26]) cube([KL, 6, 4]);
module webblid(cx) translate([cx-KL/2, -36, 26]) cube([KL, 6, 4.4]);

module box_part() {
    difference() {
        union() {
            difference() {
                cube([W, D, Hb]);
                translate([WT, WT, FT]) cube([W-2*WT, D-2*WT, Hb]);
            }
            for (cx=BOXC) { knuckle(cx, AXY, AXZ); webbox(cx); }
            for (nx=[-20,20]) translate([nx-2, 28, 30]) cube([4, 2, 1]);
        }
    }
}

module lid_part() {
    // printed upside down: slab on bed, skirt up, notch pits open upward
    difference() {
        union() {
            translate([-40, -29.6, 0]) cube([80, 59.6, HL]);
            // skirt walls (outer 74.2 x 54.2, 2 thick), z 9.6..14
            translate([-37.1, -27.1, 9.6]) cube([74.2, 2, 4.4]);
            translate([-37.1, 25.1, 9.6]) cube([74.2, 2, 4.4]);
            translate([-37.1, -27.1, 9.6]) cube([2, 54.2, 4.4]);
            translate([35.1, -27.1, 9.6]) cube([2, 54.2, 4.4]);
            for (cx=LIDC) { knuckle(cx, AXY, 10); webblid(cx);
                translate([cx-KL/2, -30, 9.6]) cube([KL, 0.4, 0.8]); }
        }
        for (nx=[-20,20]) translate([nx-2.4, 27.6, 8.5]) cube([4.8, 2.4, 1.2]);
    }
}

module pin_part() cylinder(r=PIN_R, h=PIN_L);
module cap_part() difference() {
    cylinder(r=CAP_R, h=CAP_T);
    translate([0,0,-0.2]) cylinder(r=CAP_HOLE, h=CAP_T+0.4);
}

if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -39, 0], [40, 30, 34]]],
        ["bodies", 1], ["through_holes", 3],
        ["support_faces", [["base", "-z", 4000]]],
        ["overhangs_allowed", [["hinge knuckles and bores, bridges to 4.7",
            [[-33, -39, 25.5], [33, -31, 34.5]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [0, 32, 15], [0, -1, 0], 2.4],
            ["floor", "thickness", [0, 0, -1], [0, 0, 1], 2.4],
            ["knuckle", "material", [[-6.3, -39, 26], [6.3, -31, 34]], 0.3],
            ["bore", "hole", [8, -35, 30], [-1, 0, 0], [[0, 4.7], [12.6, 4.7]]],
            ["nub", "material", [[18, 28, 30], [22, 30, 31]], 0.9]
        ]]
    ]);
    translate([-40, -30, 0]) box_part();
}
if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -39, 0], [40, 30, 14]]],
        ["bodies", 1], ["through_holes", 2],
        ["support_faces", [["top", "-z", 4000]]],
        ["overhangs_allowed", [["hinge knuckle undersides and bore roofs, bridges to 4.7",
            [[-33, -39, 6], [33, -31, 14]]]]],
        ["copies", 1],
        ["details", [
            ["top", "thickness", [0, 0, 15], [0, 0, -1], 9.6],
            ["knuckle", "material", [[-19.4, -39, 6], [-6.8, -31, 14]], 0.3],
            ["bore", "hole", [-4, -35, 10], [-1, 0, 0], [[0, 4.7], [12.6, 4.7]]],
            ["notch", "void", [[17.6, 27.6, 8.4], [22.4, 30, 9.7]], 0.8]
        ]]
    ]);
    translate([0, 0, 0]) lid_part();
}
if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-2, -2, 0], [2, 2, 67.5]]],
        ["bodies", 1], ["through_holes", 0],
        ["support_faces", [["base", "-z", 8]]],
        ["copies", 1],
        ["details", [
            ["shaft", "thickness", [3, 0, 30], [-1, 0, 0], 4]
        ]]
    ]);
    pin_part();
}
if (part == "cap") {
    echo(cadverify_spec = [
        ["bounds", [[-3, -3, 0], [3, 3, 2]]],
        ["bodies", 1], ["through_holes", 1],
        ["support_faces", [["base", "-z", 12]]],
        ["copies", 2],
        ["details", [
            ["ring", "thickness", [2.4, 0, 3], [0, 0, -1], 2]
        ]]
    ]);
    cap_part();
}
if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -39, 0], [40, 30, 40]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", [["cap_plus", "pin", "cap bore press fit 0.15"],
            ["cap_minus", "pin", "cap bore press fit 0.15"]]],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0, -35, 30], [1, 0, 0], [0, 110]]
        ]],
        ["assembly_order", [
            [["box"]],
            [["lid"], [0, 0, -1]],
            [["pin"], [-1, 0, 0]],
            [["cap_plus"], [-1, 0, 0]],
            [["cap_minus"], [1, 0, 0]]
        ]]
    ]);
    instance("box", "box") translate([-40, -30, 0]) box_part();
    instance("lid", "lid") translate([0, 0, 40]) rotate([0, 0, 180]) rotate([180, 0, 0]) lid_part();
    instance("pin", "pin") translate([-33.75, -35, 30]) rotate([0, 90, 0]) pin_part();
    instance("cap_plus", "cap") translate([32.7, -35, 30]) rotate([0, 90, 0]) cap_part();
    instance("cap_minus", "cap") translate([-32.7, -35, 30]) rotate([0, -90, 0]) cap_part();
}
