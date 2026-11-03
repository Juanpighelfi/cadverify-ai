// Planetary gear set printed in place - herringbone with center groove, 60mm x 10mm
// Sun 18T, Planets 18T x3, Ring 54T, module 1.0
part = "assembly"; // [sun, planet, ring, assembly]

m = 1.0;
Zs = 18;
Zp = 18;
Zr = 54;
pa = 20;
H = 10;
groove = 1.2;
Hb = (H-groove)/2; // 4.4 half height
backlash = 0.60; // tooth thinning per gear (mm arc)
tipC = 0.20;
shift = 0.8; // herringbone shift at pitch radius over Hb
AF = 6.7;
outerR = 30;

rp_s = m*Zs/2;
rb_s = rp_s*cos(pa);
ra_s = rp_s + m - tipC;
rd_s = rp_s - 1.25*m;

rp_p = m*Zp/2;
rb_p = rp_p*cos(pa);
ra_p = rp_p + m - tipC;
rd_p = rp_p - 1.25*m;

rp_r = m*Zr/2;
rb_r = rp_r*cos(pa);
rt_r = rp_r - m + tipC;
rr_r = rp_r + 1.25*m;

Ts = shift / rp_s * 180/PI;
Tp = shift / rp_p * 180/PI;
Tr = shift / rp_r * 180/PI;

Dorbit = (Zs+Zp)*m/2;

function inv_deg(phi) = (tan(phi) - phi*PI/180)*180/PI;
function inv_pa_val(pa_) = (tan(pa_) - pa_*PI/180)*180/PI;
function half_deg(z, rp) = 90/z - (backlash/(2*rp))*180/PI;
function phi_of(rb, r) = acos(rb/r);
function ext_a(r, half, invpa, rb) = half + invpa - inv_deg(phi_of(rb, r));
function int_a(r, half, invpa, rb) = half - invpa + inv_deg(phi_of(rb, r));
function polar(r, a) = [r*cos(a), r*sin(a)];

function ext_left_mid(z, rp, rb, ra, rd, half, invpa, k, j, Nf) =
  let(base=k*360/z, rj = rb + (ra-rb)*j/Nf, aj = ext_a(rj, half, invpa, rb))
    polar(rj, base - aj);
function ext_right_mid(z, rp, rb, ra, rd, half, invpa, k, j, Nf) =
  let(base=k*360/z, rj = rb + (ra-rb)*j/Nf, aj = ext_a(rj, half, invpa, rb))
    polar(rj, base + aj);
function int_left_mid(z, rp, rb, rt, rr, half, invpa, k, j, Nf) =
  let(base=k*360/z, rj = rt + (rr-rt)*j/Nf, aj = int_a(rj, half, invpa, rb))
    polar(rj, base - aj);
function int_right_mid(z, rp, rb, rt, rr, half, invpa, k, j, Nf) =
  let(base=k*360/z, rj = rt + (rr-rt)*j/Nf, aj = int_a(rj, half, invpa, rb))
    polar(rj, base + aj);

module sun_2d(Nf=4) {
  half = half_deg(Zs, rp_s);
  invpa = inv_pa_val(pa);
  a_tip = ext_a(ra_s, half, invpa, rb_s);
  a_base = half + invpa;
  pitch = 360/Zs;
  pts = [
    for (k=[0:Zs-1])
      let(base=k*pitch)
      for (s=[0:2*Nf+5])
        s==0 ? polar(rd_s, base - a_base) :
        s==1 ? polar(rb_s, base - a_base) :
        s>=2 && s<=Nf ? ext_left_mid(Zs, rp_s, rb_s, ra_s, rd_s, half, invpa, k, s-1, Nf) :
        s==Nf+1 ? polar(ra_s, base - a_tip) :
        s==Nf+2 ? polar(ra_s, base) :
        s==Nf+3 ? polar(ra_s, base + a_tip) :
        s>=Nf+4 && s<=2*Nf+2 ? ext_right_mid(Zs, rp_s, rb_s, ra_s, rd_s, half, invpa, k, 2*Nf+3-s, Nf) :
        s==2*Nf+3 ? polar(rb_s, base + a_base) :
        s==2*Nf+4 ? polar(rd_s, base + a_base) :
        polar(rd_s, base + pitch/2)
  ];
  polygon(pts);
}
module planet_2d(Nf=4) {
  half = half_deg(Zp, rp_p);
  invpa = inv_pa_val(pa);
  a_tip = ext_a(ra_p, half, invpa, rb_p);
  a_base = half + invpa;
  pitch = 360/Zp;
  pts = [
    for (k=[0:Zp-1])
      let(base=k*pitch)
      for (s=[0:2*Nf+5])
        s==0 ? polar(rd_p, base - a_base) :
        s==1 ? polar(rb_p, base - a_base) :
        s>=2 && s<=Nf ? ext_left_mid(Zp, rp_p, rb_p, ra_p, rd_p, half, invpa, k, s-1, Nf) :
        s==Nf+1 ? polar(ra_p, base - a_tip) :
        s==Nf+2 ? polar(ra_p, base) :
        s==Nf+3 ? polar(ra_p, base + a_tip) :
        s>=Nf+4 && s<=2*Nf+2 ? ext_right_mid(Zp, rp_p, rb_p, ra_p, rd_p, half, invpa, k, 2*Nf+3-s, Nf) :
        s==2*Nf+3 ? polar(rb_p, base + a_base) :
        s==2*Nf+4 ? polar(rd_p, base + a_base) :
        polar(rd_p, base + pitch/2)
  ];
  polygon(pts);
}
module ring_void_2d(Nf=4) {
  half = 90/Zr - (backlash/(2*rp_r))*180/PI;
  invpa = inv_pa_val(pa);
  a_tip = int_a(rt_r, half, invpa, rb_r);
  a_root = int_a(rr_r, half, invpa, rb_r);
  pitch = 360/Zr;
  pts = [
    for (k=[0:Zr-1])
      let(base=k*pitch)
      for (s=[0:2*Nf+5])
        s==0 ? polar(rr_r, base - a_root) :
        s>=1 && s<=Nf-1 ? int_left_mid(Zr, rp_r, rb_r, rt_r, rr_r, half, invpa, k, Nf-s, Nf) :
        s==Nf ? polar(rt_r, base - a_tip) :
        s==Nf+1 ? polar(rt_r, base) :
        s==Nf+2 ? polar(rt_r, base + a_tip) :
        s>=Nf+3 && s<=2*Nf+1 ? int_right_mid(Zr, rp_r, rb_r, rt_r, rr_r, half, invpa, k, s-(Nf+2), Nf) :
        s==2*Nf+2 ? polar(rr_r, base + a_root) :
        polar(rr_r, base + pitch/2)
  ];
  polygon(pts);
}

Rhex = AF/sqrt(3);
module hex_2d() {
  polygon([for (i=[0:5]) let(a=30+i*60) polar(Rhex, a)]);
}

module sun_half_bot() {
  rotate([0,0,-Ts]) linear_extrude(height=Hb, twist=Ts, slices=8) sun_2d();
}
module sun_half_top() {
  translate([0,0,H-Hb]) linear_extrude(height=Hb, twist=-Ts, slices=8) sun_2d();
}
module planet_half_bot() {
  rotate([0,0,Tp]) linear_extrude(height=Hb, twist=-Tp, slices=8) planet_2d();
}
module planet_half_top() {
  translate([0,0,H-Hb]) linear_extrude(height=Hb, twist=Tp, slices=8) planet_2d();
}
module ring_void_bot() {
  translate([0,0,-0.6]) rotate([0,0,Tr]) linear_extrude(height=Hb+0.7, twist=-Tr, slices=8) ring_void_2d();
}
module ring_void_top() {
  translate([0,0,H-Hb-0.1]) linear_extrude(height=Hb+0.7, twist=Tr, slices=8) ring_void_2d();
}

module sun_gear() {
  difference() {
    union() {
      cylinder(r=rd_s, h=H, $fn=96);
      sun_half_bot();
      sun_half_top();
    }
    translate([0,0,-0.6]) linear_extrude(height=H+1.2) hex_2d();
  }
}
module planet_gear() {
  union() {
    cylinder(r=rd_p, h=H, $fn=96);
    planet_half_bot();
    planet_half_top();
  }
}
module ring_gear() {
  difference() {
    cylinder(r=outerR, h=H, $fn=180);
    ring_void_bot();
    ring_void_top();
    // center groove bore at root radius
    translate([0,0,Hb]) cylinder(r=rr_r, h=groove+0.2, $fn=180);
  }
}

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

if (part == "sun") {
  echo(cadverify_spec = [
    ["bounds", [[-ra_s, -ra_s, 0], [ra_s, ra_s, H]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed", "-z", 50]]],
    ["overhangs_allowed", [["herringbone groove bridges", [[-ra_s, -ra_s, Hb-0.2], [ra_s, ra_s, H-Hb+0.2]]]]],
    ["copies", 1],
    ["details", [
      ["hex", "hole", [0, 0, H+2], [0, 0, -1], [[0, 7.04], [9, 7.04]]],
      ["body", "thickness", [5, 0, H+2], [0, 0, -1], H],
      ["groove", "void", [[-ra_s, -2, Hb], [ra_s, 2, H-Hb]], 0.5],
      ["apex", "view", [[7, -2, Hb-1], [ra_s+0.5, 2, H-Hb+1]]]
    ]]
  ]);
  sun_gear();
} else if (part == "planet") {
  echo(cadverify_spec = [
    ["bounds", [[-ra_p, -ra_p, 0], [ra_p, ra_p, H]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["support_faces", [["bed", "-z", 50]]],
    ["overhangs_allowed", [["herringbone groove bridges", [[-ra_p, -ra_p, Hb-0.2], [ra_p, ra_p, H-Hb+0.2]]]]],
    ["copies", 3],
    ["details", [
      ["body", "thickness", [5, 0, H+2], [0, 0, -1], H],
      ["apex", "view", [[7, -2, Hb-1], [ra_p+0.5, 2, H-Hb+1]]]
    ]]
  ]);
  planet_gear();
} else if (part == "ring") {
  echo(cadverify_spec = [
    ["bounds", [[-outerR, -outerR, 0], [outerR, outerR, H]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["support_faces", [["bed", "-z", 200]]],
    ["overhangs_allowed", [["herringbone groove bridges", [[-rr_r, -rr_r, Hb-0.2], [rr_r, rr_r, H-Hb+0.2]]]]],
    ["copies", 1],
    ["details", [
      ["rim", "thickness", [29, 0, H+2], [0, 0, -1], H],
      ["teeth", "view", [[24, -4, Hb-1], [29, 4, H-Hb+1]]]
    ]]
  ]);
  ring_gear();
} else if (part == "assembly") {
  echo(cadverify_spec = [
    ["bounds", [[-outerR, -outerR, 0], [outerR, outerR, H]]],
    ["support_faces", [["bed", "-z", 500]]],
    ["overhangs_allowed", [["herringbone apex bridges", [[-28.5, -28.5, Hb-0.2], [28.5, 28.5, H-Hb+0.2]]]]],
    ["assembly_order", [
      [[ "ring", "sun", "planet1", "planet2", "planet3"], [0, 0, 0]]
    ]],
    ["motions", [
      ["sun", ["sun", "planet1", "planet2", "planet3"], "rotate", [0, 0, 0], [0, 0, 1], [0, 120],
        ["drives", [
          [["sun"], "rotate", [0, 0, 0], [0, 0, 1], 3],
          [["planet1"], "rotate", [Dorbit, 0, 0], [0, 0, 1], -3],
          [["planet2"], "rotate", [Dorbit*cos(120), Dorbit*sin(120), 0], [0, 0, 1], -3],
          [["planet3"], "rotate", [Dorbit*cos(240), Dorbit*sin(240), 0], [0, 0, 1], -3]
        ]]
      ]
    ]],
    ["print_in_place", 0.3],
    ["held", ["ring", "sun", "planet1", "planet2", "planet3"]]
  ]);
  instance("ring", "ring") ring_gear();
  instance("sun", "sun") sun_gear();
  instance("planet1", "planet") translate([Dorbit, 0, 0]) rotate([0,0,10]) planet_gear();
  instance("planet2", "planet") translate([Dorbit*cos(120), Dorbit*sin(120), 0]) rotate([0,0,10]) planet_gear();
  instance("planet3", "planet") translate([Dorbit*cos(240), Dorbit*sin(240), 0]) rotate([0,0,10]) planet_gear();
}
