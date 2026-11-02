/* Box with print-in-place hinge */
part = "assembly"; // [base, lid, pin, assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
Bx=80; By=60; Hb=30; Hl=10; Wt=2.4; Bt=3; Lt=3;
Ya=-35; Za=20;
Kr=3.5; Br=1.9; Pr=1.5; CapR=3.0; CapT=1.5;
Hxmin=-30; Hxmax=30;
Lk=11.6;
function seg(i) =
  i==0 ? [Hxmin, Hxmin+Lk] :
  i==1 ? [Hxmin+Lk+0.5, Hxmin+2*Lk+0.5] :
  i==2 ? [Hxmin+2*Lk+1.0, Hxmin+3*Lk+1.0] :
  i==3 ? [Hxmin+3*Lk+1.5, Hxmin+4*Lk+1.5] :
         [Hxmin+4*Lk+2.0, Hxmax];
module knuckle(x0,x1,y,z,r_out,r_in) {
  difference() {
    translate([0,y,z]) rotate([0,90,0]) translate([0,0,(x0+x1)/2]) cylinder(h=x1-x0, r=r_out, center=true, $fn=48);
    translate([0,y,z]) rotate([0,90,0]) translate([0,0,(x0+x1)/2-0.5]) cylinder(h=(x1-x0)+1.0, r=r_in, center=true, $fn=32);
  }
}
module base_geom() {
  difference() {
    translate([-Bx/2,-By/2,0]) cube([Bx,By,Hb]);
    translate([-Bx/2+Wt,-By/2+Wt,Bt]) cube([Bx-2*Wt,By-2*Wt,Hb]);
  }
  for (s=[0,2,4]) { a=seg(s); translate([(a[0]+a[1])/2,0,0]) {
    translate([-(a[1]-a[0])/2+0,0,0]) cube([(a[1]-a[0]),0,0]); }
    translate([a[0],-35,18]) cube([a[1]-a[0],6,4]);
    knuckle(a[0],a[1],Ya,Za,Kr,Br);
  }
  // catch nub on front wall (y=+30)
  translate([-3.5,30,27.5]) cube([7,0.01,2.0]);
  polyhedron(points=[[-3.5,30,27.5],[3.5,30,27.5],[3.5,30,29.5],[-3.5,30,29.5],[-3.5,31.2,28.7],[3.5,31.2,28.7],[3.5,31.2,29.5],[-3.5,31.2,29.5]], faces=[[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]);
}
module lid_geom() {
  // print pose: plate at z 0-3, y -100..-40
  translate([-Bx/2,-100,0]) cube([Bx,60,Lt]);
  difference() {
    translate([-Bx/2,-100,Lt]) cube([Bx,60,7]);
    translate([-Bx/2+Wt,-97.6,Lt]) cube([Bx-2*Wt,55.2,7]);
  }
  for (s=[1,3]) { a=seg(s);
    translate([a[0],-42,7]) cube([a[1]-a[0],11,15]);
    knuckle(a[0],a[1],Ya,Za,Kr,Br);
  }
  // front skirt outside far wall (y=-100 side)
  difference() {
    translate([-10,-101.6,8]) cube([20,2.6,6]);
    translate([-4,-102,9.8]) cube([8,3.2,2.5]);
  }
}
module pin_geom() {
  translate([0,Ya,Za]) rotate([0,90,0]) translate([0,0,0]) cylinder(h=64, r=Pr, center=true, $fn=32);
  for (sx=[-1,1]) translate([sx*31.25,Ya,Za]) rotate([0,90,0]) cylinder(h=CapT, r=CapR, center=true, $fn=32);
}
if (part=="base") base_geom();
else if (part=="lid") lid_geom();
else if (part=="pin") pin_geom();
else if (part=="assembly") {
  instance("base","base") base_geom();
  instance("lid","lid") translate([0,Ya,Za]) rotate([180,0,0]) translate([0,-Ya,-Za]) lid_geom();
  instance("pin","pin") pin_geom();
}
