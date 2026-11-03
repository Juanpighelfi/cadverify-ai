// Planetary gear set, print-in-place, herringbone, ~60mm x 10mm
// Units mm, print orientation +Z up, parts rest on z=0

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

part = "assembly"; // [sun, planet, ring, assembly]

// ---- parameters ----
m = 1.2;
Zs = 18;
Zp = 12;
Zr = 42;
pa = 20;
add = 0.7*m;
ded = 1.0*m;
thick = 10;
half = thick/2;
psi = 25;
clear = 0.45;   // per-side erosion for print-in-place backlash
K = 4;
Rout = 30;
orbit = m*(Zs+Zp)/2; // 18
hexAF = 6.8;

r_sun = m*Zs/2;
r_planet = m*Zp/2;
R_ring = m*Zr/2;

twist_sun = half*tan(psi)/r_sun*180/PI;
twist_planet = -half*tan(psi)/r_planet*180/PI;
twist_ring = -half*tan(psi)/R_ring*180/PI;
planet_rot = 165;

function half_ext(Z,pa_deg,rk,rb) =
  let(inv_pa = tan(pa_deg)-pa_deg*PI/180,
      ak = (rk>=rb) ? acos(rb/rk) : 0,
      inv_ak = (rk>=rb) ? (tan(ak)-ak*PI/180) : 0)
  90/Z + (inv_pa - inv_ak)*180/PI;

function half_int(Z,pa_deg,rk,rb) =
  let(inv_pa = tan(pa_deg)-pa_deg*PI/180,
      ak = (rk>=rb) ? acos(rb/rk) : 0,
      inv_ak = (rk>=rb) ? (tan(ak)-ak*PI/180) : 0)
  90/Z - (inv_pa - inv_ak)*180/PI;

function ext_tooth_pts(phi,Z,pa_deg,r,rb,ra,rf,K) =
  concat(
    [for(k=[0:K]) let(rk=rf+(ra-rf)*k/K, h=half_ext(Z,pa_deg,rk,rb)) [rk*cos(phi-h), rk*sin(phi-h)]],
    [for(k=[K:-1:0]) let(rk=rf+(ra-rf)*k/K, h=half_ext(Z,pa_deg,rk,rb)) [rk*cos(phi+h), rk*sin(phi+h)]]
  );

function int_tooth_pts(phi,Z,pa_deg,R,rb,Rt,Rr,K) =
  concat(
    [for(k=[0:K]) let(rk=Rt+(Rr-Rt)*k/K, h=half_int(Z,pa_deg,rk,rb)) [rk*cos(phi-h), rk*sin(phi-h)]],
    [for(k=[K:-1:0]) let(rk=Rt+(Rr-Rt)*k/K, h=half_int(Z,pa_deg,rk,rb)) [rk*cos(phi+h), rk*sin(phi+h)]]
  );

function ext_gear_poly(m,Z,pa_deg,add,ded,K) =
  let(r=m*Z/2, rb=r*cos(pa_deg), ra=r+add, rf=r-ded)
  [for(i=[0:Z-1]) for(p=ext_tooth_pts(i*360/Z,Z,pa_deg,r,rb,ra,rf,K)) p];

function int_void_poly(m,Z,pa_deg,add,ded,K) =
  let(R=m*Z/2, rb=R*cos(pa_deg), Rt=R-add, Rr=R+ded)
  [for(i=[0:Z-1]) for(p=int_tooth_pts(i*360/Z,Z,pa_deg,R,rb,Rt,Rr,K)) p];

module sun_2d() {
  offset(delta=-clear) polygon(points=ext_gear_poly(m,Zs,pa,add,ded,K));
}
module planet_2d() {
  offset(delta=-clear) polygon(points=ext_gear_poly(m,Zp,pa,add,ded,K));
}
module ring_2d() {
  difference() {
    circle(r=Rout, $fn=128);
    offset(delta=clear) polygon(points=int_void_poly(m,Zr,pa,add,ded,K));
  }
}
module hex_2d() {
  circle(r=hexAF/sqrt(3), $fn=6);
}

module sun_solid() {
  difference() {
    union() {
      linear_extrude(height=half, twist=twist_sun, slices=10) sun_2d();
      translate([0,0,half]) rotate([0,0,twist_sun]) linear_extrude(height=half, twist=-twist_sun, slices=10) sun_2d();
    }
    translate([0,0,-0.5]) linear_extrude(height=thick+1) hex_2d();
  }
}
module planet_solid() {
  union() {
    linear_extrude(height=half, twist=twist_planet, slices=10) planet_2d();
    translate([0,0,half]) rotate([0,0,twist_planet]) linear_extrude(height=half, twist=-twist_planet, slices=10) planet_2d();
  }
}
module ring_solid() {
  union() {
    linear_extrude(height=half, twist=twist_ring, slices=10) ring_2d();
    translate([0,0,half]) rotate([0,0,twist_ring]) linear_extrude(height=half, twist=-twist_ring, slices=10) ring_2d();
  }
}

module sun_part() { sun_solid(); }
module planet_part() { planet_solid(); }
module ring_part() { ring_solid(); }

module assembly() {
  instance("sun", "sun", 1) sun_part();
  instance("planet_1", "planet", 1) translate([orbit,0,0]) rotate([0,0,planet_rot]) planet_solid();
  instance("planet_2", "planet", 1) translate([orbit*cos(120), orbit*sin(120),0]) rotate([0,0,planet_rot]) planet_solid();
  instance("planet_3", "planet", 1) translate([orbit*cos(240), orbit*sin(240),0]) rotate([0,0,planet_rot]) planet_solid();
  instance("ring", "ring", 1) ring_part();
}

if (part == "sun") {
  echo(cadverify_spec = [
    ["bounds", [[-11.6,-11.6,0],[11.6,11.6,10]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed","-z",100]]],
    ["overhangs_allowed", [["apex", [[-12,-12,4],[12,12,6]]]]],
    ["copies", 1],
    ["details", [
      ["hex_void", "void", [[-2,-2,-1],[2,2,11]], 0.95],
      ["wall", "thickness", [8,0,11], [0,0,-1], 10],
      ["herringbone", "view", [[9,-4,3],[12,4,7]]]
    ]]
  ]);
  sun_part();
} else if (part == "planet") {
  echo(cadverify_spec = [
    ["bounds", [[-8,-8,0],[8,8,10]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["bed","-z",50]]],
    ["overhangs_allowed", [["apex", [[-8,-8,4],[8,8,6]]]]],
    ["copies", 3],
    ["details", [
      ["wall", "thickness", [0,0,11], [0,0,-1], 10],
      ["herringbone", "view", [[6,-3,3],[9,3,7]]]
    ]]
  ]);
  planet_part();
} else if (part == "ring") {
  echo(cadverify_spec = [
    ["bounds", [[-30,-30,0],[30,30,10]]],
    ["bodies", 1],
    ["through_holes", 43],
    ["support_faces", [["bed","-z",500]]],
    ["overhangs_allowed", [["apex", [[-30,-30,4],[30,30,6]]]]],
    ["copies", 1],
    ["details", [
      ["wall", "thickness", [28,0,11], [0,0,-1], 10],
      ["herringbone", "view", [[22,-6,3],[27,6,7]]]
    ]]
  ]);
  ring_part();
} else if (part == "assembly") {
  echo(cadverify_spec = [
    ["bounds", [[-30,-30,0],[30,30,10]]],
    ["support_faces", [["bed","-z",800]]],
    ["allowed_interferences", []],
    ["motions", [
      ["sun_turn", ["sun","planet_1","planet_2","planet_3","ring"], "rotate", [0,0,0], [0,0,1], [0,360]]
    ]],
    ["assembly_order", [
      [["sun","planet_1","planet_2","planet_3","ring"], [0,0,0]]
    ]],
    ["print_in_place", 0.3],
    ["overhangs_allowed", [["apex", [[-30,-30,4],[30,30,6]]]]]
  ]);
  assembly();
}
