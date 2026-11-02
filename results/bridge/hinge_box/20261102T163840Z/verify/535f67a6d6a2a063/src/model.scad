part = "assembly"; // [base, lid, pin, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
  echo(cadverify_instance = [name, part, unit]);
  if (cadverify_only == "" || cadverify_only == name) children();
}
Ya = -33.5; Za = 20; Kr = 3.0; Br = 1.9; Pr = 1.5;
BX = [[-30,-18],[-6,6],[18,30]];
LX = [[-17.5,-6.5],[6.5,17.5]];
module barrelX(x0, x1) {
  difference() {
    translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,(x0+x1)/2])
      cylinder(h=x1-x0, r=Kr, center=true, $fn=48);
    translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,(x0+x1)/2])
      cylinder(h=(x1-x0)+1.0, r=Br, center=true, $fn=24);
  }
}
module base_geom() {
  difference() {
  union() {
    difference() {
      translate([-40,-30,0]) cube([80,60,30]);
      translate([-37.6,-27.6,3]) cube([75.2,55.2,27.01]);
    }
    for (b=BX) {
      translate([b[0],-36.5,0]) cube([b[1]-b[0],6.5,17.5]);
      barrelX(b[0], b[1]);
    }
    translate([5,0,0]) rotate([0,-90,0]) linear_extrude(height=10)
      polygon([[29.5,26.5],[31,28.5],[31,30.65],[29.5,30.65]]);
  }
  translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,0])
    cylinder(h=62, r=Br, center=true, $fn=24);
  }
}
module lid_open() {
  difference() {
    union() {
      translate([-40,-97,0]) cube([80,60,3]);
      translate([-40,-97,3]) cube([80,2.4,6.85]);
      translate([-40,-39.4,3]) cube([80,2.4,6.85]);
      translate([-40,-97,3]) cube([2.4,60,6.85]);
      translate([37.6,-97,3]) cube([2.4,60,6.85]);
      for (b=LX) {
        translate([b[0],-39,0]) cube([b[1]-b[0],8.5,6]);
        translate([b[0],-35.5,3]) cube([b[1]-b[0],4,17.5]);
        barrelX(b[0], b[1]);
      }
    }
    translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,0])
      cylinder(h=62, r=Br, center=true, $fn=24);
    translate([-5.6,-98.6,9.25]) cube([11.2,3,0.76]);
  }
}
module pin_geom() {
  union() {
    translate([-29.2,0,1.5]) rotate([0,90,0])
      cylinder(h=58.4, r=Pr, center=false, $fn=32);
    translate([-29.2,-0.9,0]) cube([58.4,1.8,0.6]);
  }
}
module lid_closed() {
  translate([0,Ya,Za]) rotate([180,0,0]) translate([0,-Ya,-Za]) lid_open();
}
module pin_placed() {
  translate([0,Ya,Za-1.5]) pin_geom();
}
if (part=="base") {
  base_geom();
  echo(cadverify_spec=[
    ["bounds", [[-40,-36.5,0],[40,30.65,31]]],
    ["bodies", 1],
    ["support_faces", [["base","-z",4000]]],
    ["overhangs_allowed", [["hinge", [[-30,-37,16],[30,-30,24]]]]],
    ["copies", 1],
    ["details", [
      ["bottom","thickness",[0,0,-1],[0,0,1],3],
      ["cavity","void",[[-37.6,-27.6,3],[37.6,27.6,30]],0.9],
      ["knuckle","material",[[-30,-36.5,17],[-18,-30.5,23]],0.5],
      ["bore","hole",[-31,-33.5,20],[1,0,0],[[0,3.8],[10,3.8]]],
      ["catch","material",[[-5,30,26.5],[5,31,30.65]],0.15]
    ]]
  ]);
} else if (part=="lid") {
  lid_open();
  echo(cadverify_spec=[
    ["bounds", [[-40,-97,0],[40,-30.5,23]]],
    ["bodies", 1],
    ["support_faces", [["lid","-z",4000]]],
    ["overhangs_allowed", [["hinge", [[-30,-37,16],[30,-30,24]]]]],
    ["copies", 1],
    ["details", [
      ["plate","thickness",[0,-67,-1],[0,0,1],3],
      ["pocket","void",[[-37.6,-94.6,3],[37.6,-39.4,9.85]],0.9],
      ["knuckle","material",[[-17.5,-36.5,17],[-6.5,-30.5,23]],0.6],
      ["bore","hole",[-18,-33.5,20],[1,0,0],[[0,3.8],[9,3.8]]],
      ["notch","void",[[-5.6,-97,9.25],[5.6,-95.6,9.85]],0.9]
    ]]
  ]);
} else if (part=="pin") {
  pin_geom();
  echo(cadverify_spec=[
    ["bounds", [[-29.2,-1.5,0],[29.2,1.5,3]]],
    ["bodies", 1],
    ["support_faces", [["pin","-z",50]]],
    ["overhangs_allowed", [["flanks", [[-29.2,-1.5,0],[29.2,1.5,3]]]]],
    ["copies", 1],
    ["details", [
      ["shaft","thickness",[0,5,1.5],[0,-1,0],3]
    ]]
  ]);
} else {
  instance("base","base") base_geom();
  instance("lid","lid") lid_closed();
  instance("pin","pin") pin_placed();
  echo(cadverify_spec=[
    ["bounds", [[-40,-36.5,0],[40,30.65,40]]],
    ["support_faces", [["bed","-z",4000]]],
    ["motions", [["swing",["lid"],"rotate",[0,-33.5,20],[1,0,0],[0,180],["flex",[["lid","base",0.5,"catch entry"]]]]]],
    ["assembly_order", [[["base"],[0,0,0]],[["lid"],[0,0,1]],[["pin"],[-1,0,0]]]],
    ["print_in_place", 0.4],
    ["print_pose", [["swing",180]]],
    ["overhangs_allowed", [["hinge", [[-30,-37,16],[30,-30,24]]]]]
  ]);
}
