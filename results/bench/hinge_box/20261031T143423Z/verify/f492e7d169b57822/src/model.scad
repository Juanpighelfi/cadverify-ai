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
Rkn = 3.4; rbore = 2.3; rpin = 2.0;
yh = -30.5;
zh_box = 30.8;            // hinge axis Z (box coords = assembly)
lid_zh = 3.4;             // hinge axis Z in lid part coords
lid_lift = 27.4;          // lid part -> assembly
pin_lift_z = 27.8; pin_shift_y = -30.5;
k0x0=-30; k0x1=-18.32;
k1x0=-17.92; k1x1=-6.24;
k2x0=-5.84; k2x1=5.84;
k3x0=6.24; k3x1=17.92;
k4x0=18.32; k4x1=30;

$fn = 64;

module knuckle_solid(x0,x1,yh,zh) {
    translate([x0,yh,zh]) rotate([0,90,0]) cylinder(r=Rkn, h=x1-x0);
}
module knuckle_bore(x0,x1,yh,zh) {
    translate([x0-0.06,yh,zh]) rotate([0,90,0]) cylinder(r=rbore, h=(x1-x0)+0.12);
}
module box_knuckle(x0,x1) {
    difference() {
        union() {
            knuckle_solid(x0,x1,yh,zh_box);
            translate([x0,-31,27.4]) cube([x1-x0, 3.4, 3.4]);
        }
        knuckle_bore(x0,x1,yh,zh_box);
    }
}
module lid_knuckle(x0,x1) {
    difference() {
        union() {
            knuckle_solid(x0,x1,yh,lid_zh);
            translate([x0,-31,0]) cube([x1-x0, 3.4, 5.0]);
        }
        knuckle_bore(x0,x1,yh,lid_zh);
    }
}
module box_part() {
    union() {
        translate([-40,-30,0]) cube([80,60,t_floor]);
        translate([-40,27.6,t_floor]) cube([80,2.4,Hbox-t_floor]);
        translate([-40,-30,t_floor]) cube([80,2.4,Hbox-t_floor]);
        translate([-40,-27.6,t_floor]) cube([2.4,55.2,Hbox-t_floor]);
        translate([37.6,-27.6,t_floor]) cube([2.4,55.2,Hbox-t_floor]);
        translate([-3,27.0,27.5]) cube([6,0.6,1.5]);
        box_knuckle(k0x0,k0x1);
        box_knuckle(k2x0,k2x1);
        box_knuckle(k4x0,k4x1);
    }
}
module lid_part() {
    difference() {
        union() {
            translate([-40,-30,10.6]) cube([80,60,2.4]);
            translate([-40,27.6,3]) cube([80,2.4,7.6]);
            translate([-40,-30,3]) cube([80,2.4,7.6]);
            translate([-40,-27.6,3]) cube([2.4,55.2,7.6]);
            translate([37.6,-27.6,3]) cube([2.4,55.2,7.6]);
            translate([-37.2,25.2,0]) cube([74.4,2.0,10.6]);
            translate([-37.2,-27.2,0]) cube([74.4,2.0,10.6]);
            translate([-37.2,-25.2,0]) cube([2.0,50.4,10.6]);
            translate([35.2,-25.2,0]) cube([2.0,50.4,10.6]);
            lid_knuckle(k1x0,k1x1);
            lid_knuckle(k3x0,k3x1);
        }
        translate([-3.2,26.4,-0.05]) cube([6.4,0.85,1.85]);
    }
}
module pin_part() {
    union() {
        translate([-32.4,0,3]) rotate([0,90,0]) cylinder(r=rpin, h=64.8);
        translate([30.4,0,3]) rotate([0,90,0]) cylinder(r=3, h=2);
        translate([-32.4,0,3]) rotate([0,90,0]) cylinder(r=3, h=2);
    }
}

if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.9,0],[40,30,34.2]]],
        ["bodies", 1],
        ["through_holes", 3],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [["hinge knuckle and bore undersides print in place", [[-30,-34.5,26],[30,-26.5,31.5]]]]],
        ["copies", 1],
        ["details", [
            ["floor","thickness",[0,0,-1],[0,0,1],2.4],
            ["front_wall","thickness",[0,31,15],[0,-1,0],2.4],
            ["cavity","void",[[-37.6,-27.6,2.4],[37.6,27.6,29.9]],0.9],
            ["hinge_bore","hole",[-31,-30.5,30.8],[1,0,0],[[0,4.6],[11.6,4.6]]],
            ["catch_bump","material",[[-3,27.0,27.5],[3,27.6,29.0]],0.9],
            ["hinge_view","view",[[-30,-34.5,26],[30,-26.5,35]]]
        ]]
    ]);
    box_part();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.9,0],[40,30,13]]],
        ["bodies", 1],
        ["through_holes", 2],
        ["support_faces", [["bed","-z",300]]],
        ["overhangs_allowed", [
            ["hinge knuckle and bore undersides print in place", [[-18,-34.5,0],[18,-26.5,4]]],
            ["lid top bridging over plug cavity", [[-37.2,-25.2,9],[37.2,25.2,11]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top","thickness",[0,0,14],[0,0,-1],2.4],
            ["skirt","thickness",[0,31,6],[0,-1,0],2.4],
            ["plug_cavity","void",[[-35.2,-25.2,0],[35.2,25.2,10.5]],0.9],
            ["hinge_bore","hole",[-18.6,-30.5,3.4],[1,0,0],[[0,4.6],[11.6,4.6]]],
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
        ["overhangs_allowed", [["pin shaft underside bridges inside bore with 0.3 gap", [[-32.4,-3,0],[32.4,3,2.5]]]]],
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
        ["bounds", [[-40,-33.9,0],[40,30,40.4]]],
        ["support_faces", [["bed","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_open", ["lid"], "rotate", [0,-30.5,30.8], [1,0,0], [0,110], ["flex", [["lid","box",0.8,"snap catch bump passes over plug"]]]]
        ]],
        ["assembly_order", [
            [["box"], [0,0,0]],
            [["lid"], [0,0,-1]],
            [["pin"], [1,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge undersides and pin bridge in place", [[-33,-34.5,26],[33,-26.5,35]]],
            ["lid top bridging over box cavity", [[-37.6,-27.6,29.5],[37.6,27.6,38.5]]]
        ]]
    ]);
    instance("box","box") box_part();
    instance("lid","lid") translate([0,0,lid_lift]) lid_part();
    instance("pin","pin") translate([0,pin_shift_y,pin_lift_z]) pin_part();
}
