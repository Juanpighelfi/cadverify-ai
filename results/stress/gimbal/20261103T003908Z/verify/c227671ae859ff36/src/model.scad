/* Print-in-place gimbal, vertical rings, no supports.
   Outer OD70 on small foot, middle + disc concentric, full 360 both axes.
   Print orientation: +Z up, all minima as modeled (frame 0, middle 5.5, disc 6.5).
   Clearance 0.5mm for PLA 0.4mm nozzle. T=6mm wall thickness.
*/
part = "assembly";
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
Roo=35; Roi=30; Rmo=29.5; Rmi=25.5; Rd=25; T=6; H=T/2; Zc=35;
pin_r=2; sock_r=2.5;
$fn=128;
module ring(Ro,Ri) {
    translate([0,0,Zc]) rotate([90,0,0])
      difference(){
        cylinder(h=T,r=Ro,center=true);
        translate([0,0,0]) cylinder(h=T+0.4,r=Ri,center=true);
      }
}
module frame() {
    union(){
        ring(Roo,Roi);
        translate([-5,-11,0]) cube([10,22,4]);
    }
    // placeholder for diff below via difference wrapper
}
module frame_solid() {
    difference(){
        union(){
            ring(Roo,Roi);
            translate([-5,-11,0]) cube([10,22,4]);
        }
        // X sockets (outer-middle pivots)
        translate([31.5,0,Zc]) rotate([0,90,0]) cylinder(h=5,r=sock_r,center=true,$fn=48);
        translate([-31.5,0,Zc]) rotate([0,90,0]) cylinder(h=5,r=sock_r,center=true,$fn=48);
    }
}
module middle_solid() {
    difference(){
        union(){
            ring(Rmo,Rmi);
            // X pins
            translate([30.75,0,Zc]) rotate([0,90,0]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
            translate([-30.75,0,Zc]) rotate([0,90,0]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
        }
        // Z sockets top/bottom (middle-disc pivots)
        translate([0,0,8]) cylinder(h=4,r=sock_r,center=true,$fn=48);
        translate([0,0,62]) cylinder(h=4,r=sock_r,center=true,$fn=48);
    }
}
module disc_solid() {
    union(){
        translate([0,0,Zc]) rotate([90,0,0]) cylinder(h=T,r=Rd,center=true);
        // Z pins
        translate([0,0,9.25]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
        translate([0,0,60.75]) cylinder(h=5.5,r=pin_r,center=true,$fn=48);
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
        ["sock-X",[[-34.5,-3,32],[-28.5,3,38]]]
      ]],
      ["copies",1],
      ["details",[
        ["stand","material",[[-5,-11,0],[5,11,4]],0.9],
        ["gapTop","void",[[-1,-1,64.55],[1,1,64.95]],0.8],
        ["wallY","thickness",[28,10,50],[0,-1,0],6],
        ["floorFoot","thickness",[0,8,-1],[0,0,1],4]
      ]]
    ]);
    frame_solid();
} else if (part=="middle") {
    echo(cadverify_spec=[
      ["bounds",[[-33.5,-3,5.5],[33.5,3,64.5]]],
      ["bodies",1],
      ["through_holes",1],
      ["overhangs_allowed",[
        ["pin+X",[[27.5,-2.5,32.5],[34,2.5,37.5]]],
        ["pin-X",[[-34,-2.5,32.5],[-27.5,2.5,37.5]]],
        ["sockBot",[[-3,-3,5],[3,3,11]]],
        ["sockTop",[[-3,-3,59],[3,3,64.5]]]
      ]],
      ["copies",1],
      ["details",[
        ["pinX","material",[[31,-1,34],[33,1,36]],0.8],
        ["gapTop","void",[[-1,-1,64.55],[1,1,64.95]],0.8],
        ["webX10","thickness",[10,0,6],[0,0,1],4.3]
      ]]
    ]);
    middle_solid();
} else if (part=="disc") {
    echo(cadverify_spec=[
      ["bounds",[[-25,-3,6.5],[25,3,63.5]]],
      ["bodies",1],
      ["overhangs_allowed",[
        ["pinBot",[[-2.5,-2.5,6],[2.5,2.5,12]]],
        ["pinTop",[[-2.5,-2.5,58],[2.5,2.5,64]]]
      ]],
      ["copies",1],
      ["details",[
        ["pinBot","material",[[-1,-1,7],[1,1,9]],0.8],
        ["gapTop","void",[[-1,-1,60.55],[1,1,60.95]],0.8],
        ["edgeX","thickness",[26,0,35],[-1,0,0],50]
      ]]
    ]);
    disc_solid();
} else if (part=="assembly") {
    echo(cadverify_spec=[
      ["bounds",[[-35,-11,0],[35,11,70]]],
      ["overhangs_allowed",[
        ["pinX",[[-34.5,-3,32],[34.5,3,38]]],
        ["pinZ",[[-3,-3,5],[3,3,64.5]]]
      ]],
      ["motions",[
        ["swing_middle",["middle","disc"],"rotate",[0,0,35],[1,0,0],[0,360]],
        ["spin_disc",["disc"],"rotate",[0,0,35],[0,0,1],[0,360]]
      ]],
      ["print_in_place",0.5],
      ["held",["middle","disc"]]
    ]);
    instance("frame","frame") frame_solid();
    instance("middle","middle") middle_solid();
    instance("disc","disc") disc_solid();
}
