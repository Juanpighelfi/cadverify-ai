// Box with print-in-place hinge
// [box, lid, pin, assembly]
part = "box";
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
W = 80; D = 60; Hbox = 30; Hlid = 10;
t_wall = 2.4; t_floor = 2.4; t_top = 2.4;
gap_v = 0.4;              // vertical lid/box gap
clr_r = 0.3;              // radial pin/bore clearance
clr_a = 0.4;              // axial knuckle gap
Rkn = 3.2; rbore = 2.3; rpin = 2.0;
yh = -30.5;               // hinge axis Y (assembly coords, box centered X0 Y0)
zh_box = 30.2;            // hinge axis Z in box coords (= assembly)
lip_h = 3.0;              // plug depth below lid skirt bottom
plug_t = 2.0;             // plug wall thickness
// hinge segmentation: span -30..30, 5 knuckles len 11.68 gaps 0.4
k_len = 11.68;
k0x0=-30; k0x1=-18.32;
k1x0=-17.92; k1x1=-6.24;
k2x0=-5.84; k2x1=5.84;
k3x0=6.24; k3x1=17.92;
k4x0=18.32; k4x1=30;
// lid part coords: plug bottom Z0, skirt bottom Z3, top Z13
lid_zh = 2.8;             // hinge axis Z in lid part coords (30.2-27.4)
lid_lift = 27.4;          // translate lid part to assembly
pin_lift_z = 27.2; pin_shift_y = -30.5;

$fn = 64;

module teardrop_prism(x0,x1,yh,zh) {
    ya = yh-1.626; za = zh+1.626;
    yb = yh+1.626; zb = zh+1.626;
    yc = yh;       zc = zh+3.252;
    polyhedron(
        points=[[x0,ya,za],[x0,yb,zb],[x0,yc,zc],
                [x1,ya,za],[x1,yb,zb],[x1,yc,zc]],
        faces=[[0,2,1],[3,4,5],[0,1,4,3],[1,2,5,4],[0,3,5,2]]
    );
}

module knuckle_solid(x0,x1,yh,zh) {
    // outer cylinder along X
    translate([x0,yh,zh]) rotate([0,90,0]) cylinder(r=Rkn, h=x1-x0);
}

module knuckle_bore(x0,x1,yh,zh) {
    translate([x0-0.02,yh,zh]) rotate([0,90,0]) cylinder(r=rbore, h=(x1-x0)+0.04);
    teardrop_prism(x0-0.02,x1+0.02,yh,zh);
}

module box_knuckle(x0,x1) {
    difference() {
        union() {
            knuckle_solid(x0,x1,yh,zh_box);
            // lug to back wall: X x0..x1, Y -31..-27.6, Z 27..30.5
            translate([x0,-31,27]) cube([x1-x0, 3.4, 3.5]);
        }
        knuckle_bore(x0,x1,yh,zh_box);
    }
}

module lid_knuckle(x0,x1) {
    difference() {
        union() {
            knuckle_solid(x0,x1,yh,lid_zh);
            // lug to lid back: Y -31..-27.6, Z 1.5..4.5 (part coords)
            translate([x0,-31,1.5]) cube([x1-x0, 3.4, 3.0]);
        }
        knuckle_bore(x0,x1,yh,lid_zh);
    }
}

module box_part() {
    difference() {
        union() {
            // floor
            translate([-40,-30,0]) cube([80,60,t_floor]);
            // front wall
            translate([-40,27.6,t_floor]) cube([80,2.4,Hbox-t_floor]);
            // back wall
            translate([-40,-30,t_floor]) cube([80,2.4,Hbox-t_floor]);
            // left wall
            translate([-40,-27.6,t_floor]) cube([2.4,55.2,Hbox-t_floor]);
            // right wall
            translate([37.6,-27.6,t_floor]) cube([2.4,55.2,Hbox-t_floor]);
            // catch bump front inner: 6 x 0.6 x 1.5 at Z27.5..29
            translate([-3,27.0,27.5]) cube([6,0.6,1.5]);
            // knuckles
            box_knuckle(k0x0,k0x1);
            box_knuckle(k2x0,k2x1);
            box_knuckle(k4x0,k4x1);
        }
        // hollow interior already via walls? floor+walls leave interior void; no extra cut needed
        // (walls built as separate boxes, interior is void)
        dummy=0;
    }
}

module lid_part() {
    // lid part coords: plug bottom 0, skirt bottom 3, top 13
    difference() {
        union() {
            // top plate 80x60x2.4 at Z10.6..13
            translate([-40,-30,10.6]) cube([80,60,2.4]);
            // outer skirt walls Z3..10.6 (h7.6)
            // front
            translate([-40,27.6,3]) cube([80,2.4,7.6]);
            // back
            translate([-40,-30,3]) cube([80,2.4,7.6]);
            // left
            translate([-40,-27.6,3]) cube([2.4,55.2,7.6]);
            // right
            translate([37.6,-27.6,3]) cube([2.4,55.2,7.6]);
            // inner plug walls Z0..10.6 outer 74.4x54.4 t=2.0
            // front plug
            translate([-37.2,25.2,0]) cube([74.4,2.0,10.6]);
            // back plug
            translate([-37.2,-27.2,0]) cube([74.4,2.0,10.6]);
            // left plug
            translate([-37.2,-25.2,0]) cube([2.0,50.4,10.6]);
            // right plug
            translate([35.2,-25.2,0]) cube([2.0,50.4,10.6]);
            // lid knuckles
            lid_knuckle(k1x0,k1x1);
            lid_knuckle(k3x0,k3x1);
        }
        // catch notch in front plug: open at bottom Z0..1.8, X-3.2..3.2, Y26.4..27.2+0.05
        translate([-3.2,26.4,0-0.05]) cube([6.4,0.85,1.85]);
    }
}

module pin_part() {
    union() {
        // shaft r2 from -32.4..32.4 along X at Y0 Z3
        translate([-32.4,0,3]) rotate([0,90,0]) cylinder(r=rpin, h=64.8);
        // heads r3 thickness 2 at ends: inner 30.4 outer 32.4
        translate([30.4,0,3]) rotate([0,90,0]) cylinder(r=3, h=2);
        translate([-32.4,0,3]) rotate([0,90,0]) cylinder(r=3, h=2);
    }
}

// ---- specs ----
if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.7,0],[40,30,33.4]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [["hinge knuckles underside, prints bridged over bore gap", [[-30,-34,26],[30,-27,31]]]]],
        ["copies", 1],
        ["details", [
            ["floor","thickness",[0,0,-1],[0,0,1],2.4],
            ["front_wall","thickness",[0,31,15],[0,-1,0],2.4],
            ["cavity","void",[[-37.6,-27.6,2.4],[37.6,27.6,29.9]],0.9],
            ["hinge_bore","hole",[-31,-30.5,30.2],[1,0,0],[[0,4.6],[11.6,4.6]]],
            ["catch_bump","material",[[-3,27.0,27.5],[3,27.6,29.0]],0.9],
            ["hinge_view","view",[[-30,-34,26],[30,-27,34]]]
        ]]
    ]);
    box_part();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.7,0],[40,30,13]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed","-z",300]]],
        ["overhangs_allowed", [
            ["hinge knuckles underside", [[-18,-34,0],[18,-27,4]]],
            ["lid top bridging over cavity", [[-37.6,-27.6,9],[37.6,27.6,11]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top","thickness",[0,0,14],[0,0,-1],2.4],
            ["skirt","thickness",[0,31,6],[0,-1,0],2.4],
            ["plug_cavity","void",[[-35.2,-25.2,0],[35.2,25.2,10.5]],0.9],
            ["hinge_bore","hole",[-18.6,-30.5,2.8],[1,0,0],[[0,4.6],[11.6,4.6]]],
            ["catch_notch","void",[[-3.2,26.4,0],[3.2,27.25,1.8]],0.9],
            ["catch_view","view",[[-5,25,0],[5,28.5,3]]]
        ]]
    ]);
    lid_part();
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [[-32.4,-3,0],[32.4,3,6]]],
        ["bodies", 1],
        ["support_faces", []],
        ["overhangs_allowed", [["pin underside bridging, small radius breaks free", [[-32.4,-3,0],[32.4,3,2]]]]],
        ["copies", 1],
        ["details", [
            ["shaft","thickness",[0,3,3],[0,-1,0],4.0],
            ["head","material",[[30.4,-3,0],[32.4,3,6]],0.7],
            ["pin_view","view",[[-32.4,-3,0],[32.4,3,6]]]
        ]]
    ]);
    pin_part();
} else if (part=="assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.7,0],[40,30,40.4]]],
        ["support_faces", [["bed","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid"], "rotate", [0,-30.5,30.2], [1,0,0], [0,110]]
        ]],
        ["assembly_order", [
            [["box"], [0,0,0]],
            [["lid"], [0,0,1]],
            [["pin"], [1,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge undersides in place", [[-30,-34,26],[30,-26,34]]],
            ["lid bridging over box cavity", [[-37.6,-27.6,29.5],[37.6,27.6,31]]]
        ]]
    ]);
    instance("box","box") box_part();
    instance("lid","lid") translate([0,0,lid_lift]) lid_part();
    instance("pin","pin") translate([0,pin_shift_y,pin_lift_z]) pin_part();
}
