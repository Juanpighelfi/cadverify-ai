part="assembly";
W=80; D=60; Hb=30; Hl=10; T=2.4; Fl=2.4;
HR=4; PIN_D=4; BORE_D=4.8; HLEN=60; GAP=0.5; ENDCAP=1; PINCL=0.5;
LIPW=20; LIPG=0.3;
$fn=48;
module instance(name, p, unit=1){ echo(cadverify_instance=[name,p,unit]); if(cadverify_only==""||cadverify_only==name) children(); }
cadverify_only="";
// segments: B1 L1 B2 L2 B3
function seglist()= [[-30,-18],[-17.5,-6.5],[-6,6],[6.5,17.5],[18,30]];
module barrelX(x1,x2,yc,zc,r){ translate([(x1+x2)/2,yc,zc]) rotate([0,90,0]) cylinder(h=x2-x1,r=r,center=true); }
module boreX(x1,x2,yc,zc,r){ translate([(x1+x2)/2,yc,zc]) rotate([0,90,0]) cylinder(h=x2-x1+0.3,r=r,center=true); }
module base(){
 difference(){
  union(){
   difference(){ cube([W,D,Hb],center=false); translate([0,0,0]){} }
   // outer shell via difference below; knuckles added
  }
  // placeholder
 }
}
// real base geometry
module base_geo(){
 difference(){
  union(){
   // shell
   difference(){
    translate([-W/2,-D/2,0]) cube([W,D,Hb]);
    translate([-W/2+T,-D/2+T,Fl]) cube([W-2*T,D-2*T,Hb-Fl+1]);
   }
   // base knuckles B1 B2 B3
   barrelX(-30,-18,-D/2,Hb,HR); barrelX(-6,6,-D/2,Hb,HR); barrelX(18,30,-D/2,Hb,HR);
   // catch bump on front top inner
   translate([-5,D/2-T-1,Hb-3]) cube([10,1,3]);
  }
  // lid notches in back wall
  translate([-18,-D/2-5,Hb-HR-0.4]) cube([12,5+T+0.5,HR+0.5]);
  translate([6,-D/2-5,Hb-HR-0.4]) cube([12,5+T+0.5,HR+0.5]);
  // bores: B1 blind outer cap, B2 thru, B3 blind
  translate([0,0,0]){
   // B1 bore from inner end, leaves 1mm cap at x=-30
   translate([-23.5,-D/2,Hb]) rotate([0,90,0]) cylinder(h=11,r=BORE_D/2,center=true);
   barrelX(-6-0.2,6+0.2,-D/2,Hb,BORE_D/2);
   translate([23.5,-D/2,Hb]) rotate([0,90,0]) cylinder(h=11,r=BORE_D/2,center=true);
  }
  // front catch slot? none
 }
}
module lid_part_geo(){
 // printed top-down: top plate z0..2.4, skirt up to 10, hinge axis at z=10,y=-D/2
 difference(){
  union(){
   difference(){
    translate([-W/2,-D/2,0]) cube([W,D,Hl]);
    translate([-W/2+T,-D/2+T,0-1]) cube([W-2*T,D-2*T,Hl-2.4+1]);
    // top plate is at bottom: cavity from top down to 2.4
   }
   // lid knuckles L1 L2
   barrelX(-17.5,-6.5,-D/2,10,HR); barrelX(6.5,17.5,-D/2,10,HR);
   // catch lip: top bridge + lower leg
   translate([-LIPW/2,D/2-0.01-2.4,8]) cube([LIPW,2.4+2.4,2]);
   translate([-LIPW/2,D/2+LIPG,8-7+2]) cube([LIPW,2.4,7]);
  }
  // base notches in back wall (upper near opening)
  translate([-12.5,-D/2-5,5.6]) cube([13,5+T+0.5,4.5]);
  translate([-0.5+6,-D/2-5,5.6]) cube([13,5+T+0.5,4.5]);
  // bores thru
  barrelX(-17.5-0.2,-6.5+0.2,-D/2,10,BORE_D/2);
  barrelX(6.5-0.2,17.5+0.2,-D/2,10,BORE_D/2);
 }
}
module pin_geo(){ translate([0,0,0]) cylinder(h=57,r=PIN_D/2); }
if(part=="box"){
 echo(cadverify_spec=[["bounds",[[-40,-34,0],[40,30,34]]],["bodies",1],["support_faces",[["bottom","-z",4000]]],["overhangs_allowed",[["hinge barrels and bores",[[-30,-34,26],[30,-26,34]]]]],["copies",1],["details",[["floor","thickness",[0,0,-1],[0,0,1],2.4],["wall","thickness",[41,0,15],[-1,0,0],2.4],["bore","hole",[-17.5,-30,30],[-1,0,0],[[0,4.8],[11,4.8]]],["cap","material",[[-30,-32,28],[-29,-28,32]],1],["notch","void",[[-18,-34,25.6],[-6,-27.6,30.1]],1],["hingeview","view",[[-30,-34,26],[30,-26,34]]]]]]);
 base_geo();
} else if(part=="lid"){
 echo(cadverify_spec=[["bounds",[[-40,-34,0],[40,32.7,15]]],["bodies",1],["support_faces",[["top","-z",4000]]],["overhangs_allowed",[["hinge barrels and bores",[[-30,-34,6],[30,-26,14]]],["catch lip bridge",[[-10,30,8],[10,32.7,15]]]]],["copies",1],["details",[["top","thickness",[0,0,-1],[0,0,1],2.4],["wall","thickness",[41,0,5],[-1,0,0],2.4],["bore","hole",[-17.7,-30,10],[1,0,0],[[0,4.8],[10,4.8]]],["caplink","material",[[-17.5,-29,12],[ -6.5,-27,13.5]],0.5],["notch","void",[[-12.5,-34,5.6],[0.5,-27.6,10.1]],1],["lip","material",[[-10,30.3,3],[10,32.7,8]],0.9],["hingeview","view",[[-30,-34,6],[30,-26,14]]]]]]);
 lid_part_geo();
} else if(part=="pin"){
 echo(cadverify_spec=[["bounds",[[-2,-2,0],[2,2,57]]],["bodies",1],["support_faces",[["bottom","-z",10]]],["copies",1],["details",[["dia","thickness",[3,0,28],[-1,0,0],4],["pinview","view",[[-2,-2,25],[2,2,32]]]]]]);
 pin_geo();
} else if(part=="assembly"){
 echo(cadverify_spec=[["bounds",[[-40,-34,0],[40,32.7,40]]],["support_faces",[["bottom","-z",4000]]],["allowed_interferences",[]],["motions",[["lid_open",["lid"],"rotate",[0,-30,30],[1,0,0],[0,110]]]],["assembly_order",[[["base"],[0,0,0]],[["lid"],[0,0,30]],[["pin"],[80,0,0]]]],["print_in_place",0.3],["print_pose",[["lid_open",90]]],["overhangs_allowed",[["hinge barrels and bores as printed",[[-30,-36,24],[30,-24,36]]],["catch lip as printed",[[-10,-40,85],[10,-22,92]]]]]]);
 instance("base","box") base_geo();
 instance("lid","lid") translate([0,0,40]) rotate([0,180,0]) lid_part_geo();
 instance("pin","pin") translate([-28.5,-30,30]) rotate([0,90,0]) pin_geo();
}
