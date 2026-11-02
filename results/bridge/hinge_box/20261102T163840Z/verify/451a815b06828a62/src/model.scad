part = "assembly"; // [base, lid, pin, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
  echo(cadverify_instance = [name, part, unit]);
  if (cadverify_only == "" || cadverify_only == name) children();
}
Bx=80; By=60; Hb=30; Lt=3; Sk=7; Wt=2.4; Bt=3;
Ya=-32; Za=20; Kr=3.5; Br=1.9; Pr=1.5; CapR=3.0; CapT=1.5;
module barrel(x0,x1) {
  difference() {
    translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,(x0+x1)/2])
      cylinder(h=x1-x0, r=Kr, center=true, $fn=48);
    translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,(x0+x1)/2])
      cylinder(h=(x1-x0)+0.8, r=Br, center=true, $fn=24);
  }
}
module base_geom() {
  difference() {
    union() {
      difference() {
        translate([-40,-30,0]) cube([80,60,30]);
        translate([-37.6,-27.6,3]) cube([75.2,55.2,27.01]);
      }
      for (b=[[-30,-18],[-6,6],[18,30]]) {
        translate([b[0],-34,16.5]) cube([b[1]-b[0],5.5,7.0]);
        barrel(b[0],b[1]);
      }
      translate([-5,29.0,29.0]) cube([10,1.5,1.0]);
    }
    for (b=[[-30,-18],[-6,6],[18,30]])
      translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,(b[0]+b[1])/2])
        cylinder(h=(b[1]-b[0])+0.8, r=Br, center=true, $fn=24);
  }
}
module lid_open() {
  difference() {
    union() {
      translate([-40,-94,0]) cube([80,60,3]);
      difference() {
        translate([-40,-94,3]) cube([80,60,7]);
        translate([-37.6,-91.6,3]) cube([75.2,55.2,7.01]);
      }
      for (b=[[-17.5,-6.5],[6.5,17.5]]) {
        translate([b[0],-34,3]) cube([b[1]-b[0],5.5,17.0]);
        barrel(b[0],b[1]);
      }
    }
    translate([-5.2,-94.1,8.8]) cube([10.4,2.6,1.3]);
    for (b=[[-17.5,-6.5],[6.5,17.5]])
      translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,(b[0]+b[1])/2])
        cylinder(h=(b[1]-b[0])+0.8, r=Br, center=true, $fn=24);
  }
}
module pin_vert() {
  translate([0,0,0.8]) cylinder(h=58.4, r=Pr, center=false, $fn=24);
}
module lid_closed() {
  translate([0,Ya,Za]) rotate([180,0,0]) translate([0,-Ya,-Za]) lid_open();
}
module pin_placed() {
  translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,-32.5]) pin_vert();
}
if (part=="base") {
  base_geom();
  echo(cadverify_spec=[["bounds",[[-40,-35.5,0],[40,30,30]]],["bodies",1],["support_faces",[["base","-z",4000]]],["overhangs_allowed",[["hinge",[[-30,-35.5,14],[30,-28.5,24]]]]],["copies",1],["details":[["bottom","thickness",[0,0,-1],[0,0,1],3],["cavity","void",[[-37.6,-27.6,3],[37.6,27.6,30]],0.9],["knuckle","material",[[-30,-35.5,16.5],[-18,-28.5,23.5]],0.5],["bore","hole",[-31,-32,20],[1,0,0],[[0,3.8],[12,3.8]]],["catch","material",[[-5,29,29],[5,30.5,30]],0.8]]]);
} else if (part=="lid") {
  lid_open();
  echo(cadverify_spec=[["bounds",[[-40,-94,0],[40,-28.5,23.5]]],["bodies",1],["support_faces",[["lid","-z",4000]]],["overhangs_allowed",[["hinge",[[-17.5,-35.5,14],[17.5,-28.5,24]]]]],["copies",1],["details":[["plate","thickness",[0,-64,-1],[0,0,1],3],["pocket","void",[[-37.6,-91.6,3],[37.6,-36.4,10]],0.9],["knuckle","material",[[-17.5,-35.5,16.5],[-6.5,-28.5,23.5]],0.5],["bore","hole",[-18,-32,20],[1,0,0],[[0,3.8],[11,3.8]]],["notch","void",[[-5.2,-94.1,8.8],[5.2,-91.5,10.1]],0.9]]]);
} else if (part=="pin") {
  pin_vert();
  echo(cadverify_spec=[["bounds",[[-3,-3,0],[3,3,65]]],["bodies",1],["support_faces",[["pin","-z",20]]],["overhangs_allowed",[["cap",[[-3,-3,63.5],[3,3,65]]]]],["copies",1],["details":[["shaft","thickness",[5,0,32],[-1,0,0],3]]]);
} else {
  instance("base","base") base_geom();
  instance("lid","lid") lid_closed();
  instance("pin","pin") pin_placed();
  echo(cadverify_spec=[["bounds",[[-40,-35.5,0],[40,30.5,40]]],["support_faces",[["bed","-z",4000]]],["motions",[["swing",["lid"],"rotate",[0,-32,20],[1,0,0],[0,180]]]],["assembly_order",[[["base"],[0,0,0]],[["lid"],[0,0,1]],[["pin"],[-1,0,0]]]],["print_in_place",0.4],["print_pose",[["swing",180]]],["overhangs_allowed",[["hinge",[[-30,-35.5,14],[30,-28.5,24]]]]]]);
}
