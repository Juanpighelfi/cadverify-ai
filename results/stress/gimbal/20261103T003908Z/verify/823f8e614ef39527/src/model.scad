/* Print-in-place gimbal, vertical rings, no supports.
   Outer OD70 on small foot, middle + disc concentric, full 360 both axes.
   Each part exported resting on bed (min z=0); assembly centers all at Zc=35.
   Clearance 0.5mm for PLA 0.4mm nozzle. T=6mm wall thickness.
*/
part = "assembly"; // [frame:Frame, middle:Middle, disc:Disc, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
Roo=35; Roi=30; Rmo=29.5; Rmi=25.5; Rd=25; T=6; Zc=35;
pin_r=2; sock_r=2.5;
$fn=128;
// pivot at origin
module frame0() {
    difference(){
        union(){
            translate([0,0,0]) rotate([90,0,0])
              difference(){
                cylinder(h=T,r=Roo,center=true);
                cylinder(h=T+0.4,r=Roi,center=true);
              }
            translate([-25,-11,-35]) cube([50,22,4]);
        }
        translate([31.5,0,0]) rotate([0,90,0]) cylinder(h=5,r=sock_r,center=true,$fn=48);
        translate([-31.5,0,0]) rotate([0,90,0]) cylinder(h=5,r=sock_r,center=true,$fn=48);
    }
}
module middle0() {
    difference(){
        union(){
            translate([0,0,0]) rotate([90,0,0])
              difference(){
                cylinder(h=T,r=Rmo,center=true);
                cylinder(h=T+0.4,r=Rmi,center=true);
              }
            translate([30.75,0,0]) rotate([0,90,0]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
            translate([-30.75,0,0]) rotate([0,90,0]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
        }
        translate([0,0,-27]) cylinder(h=4,r=sock_r,center=true,$fn=48);
        translate([0,0,27]) cylinder(h=4,r=sock_r,center=true,$fn=48);
    }
}
module disc0() {
    union(){
        translate([0,0,0]) rotate([90,0,0]) cylinder(h=T,r=Rd,center=true);
        translate([0,0,-25.75]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
        translate([0,0,25.75]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
    }
}
if (part=="frame") {
    echo(cadverify_spec=[
      ["bounds",[[-35,-11,0],[35,11,70]]],
      ["bodies",1],
      ["through_holes",1],
      ["support_faces",[["bed","-z",150]]],
      ["overhangs_allowed",[
        ["sock+X",[[28.5,-3,32],[34.5,3,38]]],
        ["sock-X",[[-34.5,-3,32],[-28.5,3,38]]],
        ["archLow",[[-25,-3,0],[25,3,11]]],
        ["archTop",[[-22,-3,56],[22,3,65]]]
      ]],
      ["copies",1],
      ["details",[
        ["stand","material",[[-5,-11,0],[5,11,4]],0.9],
        ["gapTop","void",[[-1,-1,64.55],[1,1,64.95]],0.8],
        ["wallY","thickness",[28,10,50],[0,-1,0],6],
        ["floorFoot","thickness",[0,8,-1],[0,0,1],4]
      ]]
    ]);
    translate([0,0,Zc]) frame0();
} else if (part=="middle") {
    echo(cadverify_spec=[
      ["bounds",[[-33.5,-3,0],[33.5,3,59]]],
      ["bodies",1],
      ["through_holes",1],
      ["overhangs_allowed",[
        ["pin+X",[[27.5,-2.5,27],[34,2.5,32]]],
        ["pin-X",[[-34,-2.5,27],[-27.5,2.5,32]]],
        ["archLow",[[-21,-3,0],[21,3,15]]],
        ["archTop",[[-18,-3,44],[18,3,59]]]
      ]],
      ["copies",1],
      ["details",[
        ["pinX","material",[[31,-1,28.5],[33,1,30.5]],0.8],
        ["gapTop","void",[[-1,-1,59.05],[1,1,59.45]],0.8],
        ["wallY","thickness",[27,10,29.5],[0,-1,0],6]
      ]]
    ]);
    translate([0,0,29.5]) middle0();
} else if (part=="disc") {
    echo(cadverify_spec=[
      ["bounds",[[-25,-3,0],[25,3,57]]],
      ["bodies",1],
      ["overhangs_allowed",[
        ["archLow",[[-18,-3,0],[18,3,18]]],
        ["archTop",[[-18,-3,39],[18,3,57]]]
      ]],
      ["copies",1],
      ["details",[
        ["pinBot","material",[[-1,-1,1],[1,1,3]],0.8],
        ["gapAir","void",[[2.05,-0.4,54.5],[2.45,0.4,56.5]],0.8],
        ["edgeX","thickness",[26,0,28.5],[-1,0,0],50]
      ]]
    ]);
    translate([0,0,28.5]) disc0();
} else if (part=="assembly") {
    echo(cadverify_spec=[
      ["bounds",[[-35,-11,0],[35,11,70]]],
      ["overhangs_allowed",[
        ["pinX",[[-34.5,-3,32],[34.5,3,38]]],
        ["pinZ",[[-3,-3,5],[3,3,64.5]]],
        ["archLow",[[-25,-3,0],[25,3,18]]],
        ["archTop",[[-22,-3,53],[22,3,65]]]
      ]],
      ["motions",[
        ["swing_middle",["middle","disc"],"rotate",[0,0,35],[1,0,0],[0,360]],
        ["spin_disc",["disc"],"rotate",[0,0,35],[0,0,1],[0,360]]
      ]],
      ["assembly_order",[
        [[["frame"],[0,0,0]]],
        [[["middle"],[0,-1,0]],[ "flex",[["middle","frame",1,"pin snap"]]]],
        [[["disc"],[0,-1,0]],[ "flex",[["disc","middle",1,"pin snap"]]]]
      ]],
      ["print_in_place",0.4],
      ["held",["middle","disc"]]
    ]);
    instance("frame","frame") translate([0,0,Zc]) frame0();
    instance("middle","middle") translate([0,0,Zc]) middle0();
    instance("disc","disc") translate([0,0,Zc]) disc0();
}
