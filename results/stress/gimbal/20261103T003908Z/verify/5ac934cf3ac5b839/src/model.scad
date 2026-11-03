/* Print-in-place gimbal: flat print, no supports.
   Outer ring OD70 (R30/35) on two stand tabs, middle ring (R25.5/29.45) on two
   X pins, inner disc (R24.95) on two Y pins. Concentric, 6 mm thick, bed z=0.
   Blind bores open into centre holes; 0.55 radial PLA clearance, short pins.
   Full 360 deg about X (middle+disc) and about Y (disc).
*/
part = "assembly"; // [frame:Frame, middle:Middle, disc:Disc, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
Roi=30; Roo=35; Rmi=25.5; Rmo=29.45; Rd=24.95; T=6; Zc=3;
pinR=1.95; sockR=2.5;
$fn=128;
module frame0() {
    difference(){
        union(){
            difference(){
                cylinder(h=T, r=Roo);
                translate([0,0,-0.1]) cylinder(h=T+0.2, r=Roi);
            }
            translate([-4,33,0]) cube([8,8,T]);
            translate([-4,-41,0]) cube([8,8,T]);
        }
        translate([30.5,0,Zc]) rotate([0,90,0]) cylinder(h=3, r=sockR, center=true, $fn=48);
        translate([-30.5,0,Zc]) rotate([0,90,0]) cylinder(h=3, r=sockR, center=true, $fn=48);
    }
}
module middle0() {
    difference(){
        union(){
            difference(){
                cylinder(h=T, r=Rmo);
                translate([0,0,-0.1]) cylinder(h=T+0.2, r=Rmi);
            }
            translate([29,0,Zc]) rotate([0,90,0]) cylinder(h=3, r=pinR, center=true, $fn=48);
            translate([-29,0,Zc]) rotate([0,90,0]) cylinder(h=3, r=pinR, center=true, $fn=48);
        }
        translate([0,26,Zc]) rotate([90,0,0]) cylinder(h=2, r=sockR, center=true, $fn=48);
        translate([0,-26,Zc]) rotate([90,0,0]) cylinder(h=2, r=sockR, center=true, $fn=48);
    }
}
module disc0() {
    union(){
        cylinder(h=T, r=Rd);
        translate([0,24.5,Zc]) rotate([90,0,0]) cylinder(h=3, r=pinR, center=true, $fn=48);
        translate([0,-24.5,Zc]) rotate([90,0,0]) cylinder(h=3, r=pinR, center=true, $fn=48);
    }
}
if (part=="frame") {
    echo(cadverify_spec=[
      ["bounds",[[-35,-41,0],[35,41,6]]],
      ["bodies",1],
      ["through_holes",1],
      ["support_faces",[["bed","-z",800]]],
      ["overhangs_allowed",[
        ["bore+X",[[28.8,-2.6,0.4],[32.2,2.6,5.6]]],
        ["bore-X",[[-32.2,-2.6,0.4],[-28.8,2.6,5.6]]]
      ]],
      ["copies",1],
      ["details",[
        ["stand+","material",[[-4,33,0],[4,41,6]],0.9],
        ["stand-","material",[[-4,-41,0],[4,-33,6]],0.9],
        ["gapRing","void",[[-1,29.4,0],[1,30.05,6]],0.8],
        ["sock+X","void",[[29.2,-1,2],[31.8,1,4]],0.7],
        ["floorTab","thickness",[0,37,-1],[0,0,1],6],
        ["wallOut","thickness",[36,0,3],[-1,0,0],5]
      ]]
    ]);
    frame0();
} else if (part=="middle") {
    echo(cadverify_spec=[
      ["bounds",[[-30.5,-29.45,0],[30.5,29.45,6]]],
      ["bodies",1],
      ["through_holes",1],
      ["overhangs_allowed",[
        ["pin+X",[[27.2,-2,0.8],[30.6,2,3.2]]],
        ["pin-X",[[-30.6,-2,0.8],[-27.2,2,3.2]]],
        ["bore+Y",[[-2.6,25,0.4],[2.6,27.2,5.6]]],
        ["bore-Y",[[-2.6,-27.2,0.4],[2.6,-25,5.6]]]
      ]],
      ["copies",1],
      ["details",[
        ["pin+X","material",[[28,-1,2],[30.4,1,4]],0.7],
        ["sock+Y","void",[[-1,25.2,2], [1,26.8,4]],0.7],
        ["gapDisc","void",[[-1,24.9,0],[1,25.55,6]],0.7],
        ["floorRing","thickness",[27,0,-1],[0,0,1],6]
      ]]
    ]);
    middle0();
} else if (part=="disc") {
    echo(cadverify_spec=[
      ["bounds",[[-24.95,-26,0],[24.95,26,6]]],
      ["bodies",1],
      ["overhangs_allowed",[
        ["pin+Y",[[-2,22.8,0.8],[2,26.2,3.2]]],
        ["pin-Y",[[-2,-26.2,0.8],[2,-22.8,3.2]]]
      ]],
      ["copies",1],
      ["details",[
        ["pin+Y","material",[[-1,23,2],[1,26,4]],0.7],
        ["floorDisc","thickness",[0,0,-1],[0,0,1],6],
        ["edgeX","thickness",[25.5,0,3],[-1,0,0],49.9]
      ]]
    ]);
    disc0();
} else if (part=="assembly") {
    echo(cadverify_spec=[
      ["bounds",[[-35,-41,0],[35,41,6]]],
      ["overhangs_allowed",[
        ["boreX",[[-32.2,-2.6,0.4],[32.2,2.6,5.6]]],
        ["boreY",[[-2.6,-27.2,0.4],[2.6,27.2,5.6]]],
        ["pinsX",[[-30.6,-2,0.8],[30.6,2,3.2]]],
        ["pinsY",[[-2,-26.2,0.8],[2,26.2,3.2]]]
      ]],
      ["motions",[
        ["swing_middle",["middle","disc"],"rotate",[0,0,3],[1,0,0],[0,360]],
        ["spin_disc",["disc"],"rotate",[0,0,3],[0,1,0],[0,360]]
      ]],
      ["assembly_order",[
        [[["frame"],[0,0,0]]],
        [[["middle"],[0,0,-1]],["flex",[["middle","frame",1,"pin snap"]]]],
        [[["disc"],[0,0,-1]],["flex",[["disc","middle",1,"pin snap"]]]]
      ]],
      ["print_in_place",0.5],
      ["held",["middle","disc"]]
    ]);
    instance("frame","frame") frame0();
    instance("middle","middle") middle0();
    instance("disc","disc") disc0();
}
