// Box 80x60x40 closed, lid 10 tall; hinge axis y=-30,z=30, 5 knuckles KL9/BR2.35
// Prints as 4 separate support-free parts (box,lid,pin,2x cap); pin+ caps assembled by hand.
// Assembly shown closed; lid_swing 0..110 deg about +X at (0,-30,30).
part = "box";
$fn = 48;
W=80; D=60; Hb=30; WT=2.4; FT=2.4;
KR=4; BR=2.35; KL=9;
BOXC=[-20,0,20]; LIDC=[-10,10];
PIN_R=2; PIN_L=55; CAP_R=3; CAP_HOLE=1.85; CAP_T=2;
cadverify_only = "";
module instance(name, part, unit = 1) {
  echo(cadverify_instance = [name, part, unit]);
  if (cadverify_only == "" || cadverify_only == name) children();
}
module knuckleX(cx,ay,az) {
  translate([cx-KL/2,ay,az]) rotate([0,90,0])
    difference() { cylinder(r=KR,h=KL); translate([0,0,-0.2]) cylinder(r=BR,h=KL+0.4); }
}
module box_part() {
  union() {
    difference() { cube([80,60,30]); translate([2.4,2.4,2.4]) cube([75.2,55.2,30]); }
    for (cx=BOXC) {
      translate([cx,-40,-30]) knuckleX(0,0,0);
      translate([cx-4.5,-34,0]) cube([9,5,28]);
    }
    translate([37.3,8,29.6]) cube([2,4,1]);
    translate([-39.3,8,29.6]) cube([2,4,1]);
  }
}
module lid_part() {
  union() {
    difference() {
      union() {
        translate([-40,-30,0]) cube([80,60,2.4]);
        translate([-37.2,-27.2,2.0]) cube([74.4,2,7.6]);
        translate([-37.2,25.2,2.0]) cube([74.4,2,7.6]);
        translate([-37.2,-25.2,2.0]) cube([2,50.4,7.6]);
        translate([35.2,-25.2,2.0]) cube([2,50.4,7.6]);
        for (cx=LIDC) {
          translate([cx,-30,10]) knuckleX(0,0,0);
          translate([cx-4.5,-34,0]) cube([9,8,12]);
        }
      }
      translate([36.8,7.8,8.4]) cube([0.5,4.4,1.3]);
      translate([-37.3,7.8,8.4]) cube([0.5,4.4,1.3]);
    }
  }
}
module pin_part() cylinder(r=2,h=55);
module cap_part() difference() { cylinder(r=3,h=2); translate([0,0,-0.2]) cylinder(r=1.85,h=2.4); }
if (part=="box") {
  echo(cadverify_spec=[
    ["bounds",[[-40,-34,0],[40,30,34]]],["bodies",1],["through_holes",3],
    ["support_faces",[["base","-z",4000]]],
    ["overhangs_allowed",[["knuckle curved undersides and bore roofs, bridges to 4.7",[[-31,-35,25],[31,-25,35]]]]],
    ["copies",1],
    ["details",[
      ["wall","thickness",[0,32,15],[0,-1,0],2.4],
      ["floor","thickness",[0,0,-1],[0,0,1],2.4],
      ["knuckle","material",[[-4.5,-34,26],[4.5,-26,34]],0.3],
      ["bore","hole",[8,-30,30],[-1,0,0],[[0,4.7],[9,4.7]]],
      ["nub","material",[[37.3,8,29.6],[39.3,12,30.6]],0.9]]]]);
  translate([40,30,0]) box_part();
}
if (part=="lid") {
  echo(cadverify_spec=[
    ["bounds",[[-40,-34,0],[40,30,14]]],["bodies",1],["through_holes",2],
    ["support_faces",[["plate","-z",4000]]],
    ["overhangs_allowed",[["knuckle curved undersides and bore roofs, bridges to 4.7",[[-16,-35,5],[16,-25,15]]]]],
    ["copies",1],
    ["details",[
      ["plate","thickness",[0,0,-1],[0,0,1],2.4],
      ["knuckle","material",[[5.5,-34,6],[14.5,-26,14]],0.3],
      ["bore","hole",[18,-30,10],[-1,0,0],[[0,4.7],[9,4.7]]],
      ["notch","void",[[36.8,7.8,8.4],[37.3,12.2,9.7]],0.8]]]]);
  lid_part();
}
if (part=="pin") {
  echo(cadverify_spec=[
    ["bounds",[[-2,-2,0],[2,2,55]]],["bodies",1],["through_holes",0],
    ["support_faces",[["base","-z",8]]],["copies",1],
    ["details",[["shaft","thickness",[3,0,30],[-1,0,0],4]]]]);
  pin_part();
}
if (part=="cap") {
  echo(cadverify_spec=[
    ["bounds",[[-3,-3,0],[3,3,2]]],["bodies",1],["through_holes",1],
    ["support_faces",[["base","-z",12]]],["copies",2],
    ["details",[["ring","thickness",[2.4,0,3],[0,0,-1],2]]]]);
  cap_part();
}
if (part=="assembly") {
  echo(cadverify_spec=[
    ["bounds",[[-40,-34,0],[40,30,40]]],
    ["support_faces",[["bed","-z",4000]]],
    ["allowed_interferences",[["cap_plus","pin","cap bore press fit 0.15"],["cap_minus","pin","cap bore press fit 0.15"]]],
    ["motions",[["lid_swing",["lid"],"rotate",[0,-30,30],[1,0,0],[0,110]]]],
    ["assembly_order",[[["box"]],[["lid"],[0,0,1]],[["pin"],[-1,0,0]],[["cap_plus"],[-1,0,0]],[["cap_minus"],[1,0,0]]]]]);
  instance("box","box") translate([-40,-30,0]) box_part();
  instance("lid","lid") translate([0,0,40]) rotate([0,180,0]) lid_part();
  instance("pin","pin") translate([-27.5,-30,30]) rotate([0,90,0]) pin_part();
  instance("cap_plus","cap") translate([27.5,-30,30]) rotate([0,90,0]) cap_part();
  instance("cap_minus","cap") translate([-27.5,-30,30]) rotate([0,-90,0]) cap_part();
}
