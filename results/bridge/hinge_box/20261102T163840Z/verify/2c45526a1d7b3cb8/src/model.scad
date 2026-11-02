part = "assembly"; // [base, lid, pin, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
Bx=80; By=60; Hb=30; Hl=10; Wt=2.4; Bt=3; Lt=3; Sk=7;
Ya=-32; Za=3.2; Kr=3.5; Br=1.9; Pr=1.5; CapR=3.0; CapT=1.5;
Hp=36.8; Lift=40;
B0x0=-30; B0x1=-18; L0x0=-17.5; L0x1=-6.5; B1x0=-6; B1x1=6;
L1x0=6.5; L1x1=17.5; B2x0=18; B2x1=30;
module barrel(x0,x1,y,z,ro,ri) {
  difference() {
    translate([0,y,z]) rotate([0,90,0])
      translate([0,0,(x0+x1)/2]) cylinder(h=x1-x0, r=ro, center=true, $fn=48);
    translate([0,y,z]) rotate([0,90,0])
      translate([0,0,(x0+x1)/2]) cylinder(h=(x1-x0)+0.6, r=ri, center=true, $fn=32);
  }
}
module base_raw() {
  difference() {
    translate([-Bx/2,-By/2,0]) cube([Bx,By,Hb]);
    translate([-Bx/2+Wt,-By/2+Wt,Bt]) cube([Bx-2*Wt,By-2*Wt,Hb-Bt+0.01]);
  }
  for (b=[[B0x0,B0x1],[B1x0,B1x1],[B2x0,B2x1]]) {
    translate([b[0],-35,0]) cube([b[1]-b[0],5,Za]);
    barrel(b[0],b[1],Ya,Za,Kr,Br);
  }
  translate([-5,27.8,Hb]) cube([10,2.0,1.0]);
}
module base_geom() {
  intersection() {
    base_raw();
    translate([-100,-100,0]) cube([200,200,120]);
  }
}
module lid_raw_print() {
  difference() {
    translate([-Bx/2,-By/2,0]) cube([Bx,By,Lt]);
    translate([0,0,0]) cube([0.01,0.01,0.01]);
  }
  difference() {
    translate([-Bx/2,-By/2,Lt]) cube([Bx,By,Sk]);
    translate([-Bx/2+Wt,-By/2+Wt,Lt]) cube([Bx-2*Wt,By-2*Wt,Sk+0.01]);
  }
  for (b=[[L0x0,L0x1],[L1x0,L1x1]]) {
    translate([b[0],-35,0]) cube([b[1]-b[0],7.4,38]);
    barrel(b[0],b[1],Ya,Hp,Kr,Br);
  }
  translate([-Bx/2,-By/2,0]) cube([Bx,By,Lt]);
}
module lid_notch() {
  translate([-5.2,27.6,Lt]) cube([10.4,2.4,1.2]);
}
module lid_geom() {
  difference() {
    lid_raw_print();
    lid_notch();
    for (b=[[L0x0,L0x1],[L1x0,L1x1]])
      translate([0,Ya,Hp]) rotate([0,90,0]) translate([0,0,(b[0]+b[1])/2])
        cylinder(h=(b[1]-b[0])+0.6, r=Br, center=true, $fn=32);
  }
}
module pin_raw_vert() {
  translate([0,0,CapT]) cylinder(h=62, r=Pr, center=false, $fn=32);
  translate([0,0,CapT/2]) cylinder(h=CapT, r=CapR, center=true, $fn=32);
  translate([0,0,CapT+62+CapT/2]) cylinder(h=CapT, r=CapR, center=true, $fn=32);
}
module pin_geom() { pin_raw_vert(); }
module lid_closed() {
  translate([0,0,Lift]) rotate([0,180,0]) lid_geom();
}
module pin_placed() {
  translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,0])
    rotate([0,-90,0]) translate([0,0,0]) pin_geom_place();
}
module pin_geom_place() {
  translate([0,0,0]) children();
}
if (part=="base") { base_geom();
  echo(cadverify_spec=[["bounds",[[-40,-35.5,0],[40,30,31]]],["bodies",1],["support_faces",[["base","-z",4000]]],["overhangs_allowed",[["hinge bores",[[-30,-35.5,0],[30,-28.5,6.7]]]]],["copies",1],["details":[["bottom","thickness",[0,0,-1],[0,0,1],3],["cavity","void",[[-37.6,-27.6,3],[37.6,27.6,30]],0.95],["knuckle","material",[[-30,-35.5,0],[-18,-28.5,6.7]],0.8],["bore","hole",[-32,-32,3.2],[1,0,0],[[0,3.8],[12,3.8]]],["catch_bump","material",[[-5,27.8,30],[5,29.8,31]],0.9]]]);
} else if (part=="lid") { lid_geom();
  echo(cadverify_spec=[["bounds",[[-40,-35.5,0],[40,30,40.3]]],["bodies",1],["support_faces",[["lid","-z",4000]]],["overhangs_allowed",[["hinge bores",[[-30,-35.5,33],[30,-28.5,40.5]]]]],["copies",1],["details":[["top","thickness",[0,0,-1],[0,0,1],3],["pocket","void",[[-37.6,-27.6,3],[37.6,27.6,10]],0.95],["knuckle","material",[[-17.5,-35.5,33],[-6.5,-28.5,40.3]],0.6],["bore","hole",[-17.8,-32,36.8],[1,0,0],[[0,3.8],[11,3.8]]],["notch","void",[[-5.2,27.6,3],[5.2,30.0,4.2]],0.9]]]);
} else if (part=="pin") { pin_geom();
  echo(cadverify_spec=[["bounds",[[-3,-3,0],[3,3,65]]],["bodies",1],["support_faces",[["pin","-z",20]]],["overhangs_allowed",[["top cap",[[-3,-3,62.5],[3,3,65]]]]],["copies",1],["details":[["shaft","thickness",[5,0,32],[ -1,0,0],3]]]);
} else if (part=="assembly") {
  instance("base","base") base_geom();
  instance("lid","lid") lid_closed();
  instance("pin","pin") translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,-(CapT+31)]) pin_geom();
  echo(cadverify_spec=[["bounds",[[-40,-35.5,0],[40,30,40]]],["support_faces",[["bed","-z",4000]]],["motions",[["swing",["lid"],"rotate",[0,-32,3.2],[1,0,0],[0,110]]]],["assembly_order",[[["base"],[0,0,0]], [["lid"],[0,0,-1]], [["pin"],[-1,0,0]]]],["print_in_place",0.2],["print_pose",[["swing",40]]],["overhangs_allowed",[["hinge",[[-30,-35.5,0],[30,-28.5,6.7]]]]]]);
}
