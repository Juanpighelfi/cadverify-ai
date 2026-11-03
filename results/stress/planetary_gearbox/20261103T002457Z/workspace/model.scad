// Planetary gear set printed in place - herringbone, captive, no supports
// About 60mm across, 10mm thick. Sun + 3 planets + ring.
// Hex hole in sun for 1/4 inch bit.
/* [Parts] */
part = "assembly"; // [assembly,sun,planet,ring]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

m = 1.2;
pa_deg = 20;
Zs = 18;
Zp = 12;
Zr = 42;
thick = 10;
half_h = 5;
dx_apex = 1.0;
backlash_t = 0.4;
tip_cut = 0.6;
flank_steps = 5;

p_circ = PI*m;
thick_ext = p_circ/2 - 2*backlash_t;
thick_ring = p_circ/2 + 2*backlash_t;

Rp_sun = m*Zs/2;
Rb_sun = Rp_sun*cos(pa_deg);
Rt_sun = Rp_sun + m - tip_cut;
Rr_sun = Rp_sun - 1.25*m;

Rp_planet = m*Zp/2;
Rb_planet = Rp_planet*cos(pa_deg);
Rt_planet = Rp_planet + m - tip_cut;
Rr_planet = Rp_planet - 1.25*m;

Rp_ring = m*Zr/2;
Rb_ring = Rp_ring*cos(pa_deg);
Rt_ring = Rp_ring - m + tip_cut;
Rr_ring = Rp_ring + 1.25*m;

tw_sun = dx_apex/Rp_sun*180/PI;
tw_planet = dx_apex/Rp_planet*180/PI;
tw_ring = dx_apex/Rp_ring*180/PI;

Dcenter = Rp_sun + Rp_planet;
Rhex = 6.8/sqrt(3);

function inv_rad(a_deg) = tan(a_deg) - a_deg*PI/180;
function half_at_rad(R, Rp, Rb, half0, inv_pa) = half0 + inv_pa - (R >= Rb ? inv_rad(acos(Rb/R)) : 0);

function gear_outline2(Z, Rp, Rb, Rt, Rr, tooth_th, flank) =
  let(half0 = (tooth_th/Rp)/2,
      inv_pa = inv_rad(pa_deg),
      pitch = 360/Z)
  [for(i=[0:Z-1]) for(pt =
    concat(
      [for(j=[0:flank]) let(R = Rr+(Rt-Rr)*j/flank, hr = half_at_rad(R,Rp,Rb,half0,inv_pa), ang = i*pitch - hr*180/PI) [R*cos(ang), R*sin(ang)]],
      let(hrtip = half_at_rad(Rt,Rp,Rb,half0,inv_pa)) [[Rt*cos(i*pitch + hrtip*180/PI), Rt*sin(i*pitch + hrtip*180/PI)]],
      [for(j=[flank-1:-1:0]) let(R = Rr+(Rt-Rr)*j/flank, hr = half_at_rad(R,Rp,Rb,half0,inv_pa), ang = i*pitch + hr*180/PI) [R*cos(ang), R*sin(ang)]]
    )) pt
  ];

function hex_pts() = [for(k=[0:5]) let(a=k*60) [Rhex*cos(a), Rhex*sin(a)]];

module sun_gear() {
  difference() {
    union() {
      linear_extrude(height=half_h, twist=tw_sun, slices=10, convexity=10)
        polygon(gear_outline2(Zs, Rp_sun, Rb_sun, Rt_sun, Rr_sun, thick_ext, flank_steps));
      translate([0,0,half_h]) rotate([0,0,tw_sun])
        linear_extrude(height=half_h, twist=-tw_sun, slices=10, convexity=10)
          polygon(gear_outline2(Zs, Rp_sun, Rb_sun, Rt_sun, Rr_sun, thick_ext, flank_steps));
    }
    translate([0,0,-0.5]) linear_extrude(height=thick+1) polygon(hex_pts());
  }
}

module planet_gear() {
  union() {
    linear_extrude(height=half_h, twist=-tw_planet, slices=10, convexity=10)
      polygon(gear_outline2(Zp, Rp_planet, Rb_planet, Rt_planet, Rr_planet, thick_ext, flank_steps));
    translate([0,0,half_h]) rotate([0,0,-tw_planet])
      linear_extrude(height=half_h, twist=tw_planet, slices=10, convexity=10)
        polygon(gear_outline2(Zp, Rp_planet, Rb_planet, Rt_planet, Rr_planet, thick_ext, flank_steps));
  }
}

module ring_gear() {
  linear_extrude(height=half_h, twist=-tw_ring, slices=10, convexity=10)
    difference() {
      circle(r=30, $fn=128);
      polygon(gear_outline2(Zr, Rp_ring, Rb_ring, Rt_ring, Rr_ring, thick_ring, flank_steps));
    }
  translate([0,0,half_h]) rotate([0,0,-tw_ring])
    linear_extrude(height=half_h, twist=tw_ring, slices=10, convexity=10)
      difference() {
        circle(r=30, $fn=128);
        polygon(gear_outline2(Zr, Rp_ring, Rb_ring, Rt_ring, Rr_ring, thick_ring, flank_steps));
      }
}

if (part == "sun") {
  echo(cadverify_spec = [
    ["bounds", [[-11.4, -11.4, 0], [11.4, 11.4, 10]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["overhangs_allowed", [["herringbone apex valleys, bridges under 3 mm", [[-11.4, -11.4, 4.4], [11.4, 11.4, 5.6]]]]],
    ["copies", 1],
    ["details", [
      ["sun_body", "material", [[4.5, -1, 0], [8.5, 1, 10]], 0.95],
      ["hex_empty", "void", [[-2, -2, -1], [2, 2, 11]], 0.95],
      ["sun_thickness", "thickness", [6, 0, -1], [0, 0, 1], 10],
      ["herringbone", "view", [[-11.4, -11.4, 4], [11.4, 11.4, 6]]]
    ]]
  ]);
  sun_gear();
} else if (part == "planet") {
  echo(cadverify_spec = [
    ["bounds", [[-7.8, -7.8, 0], [7.8, 7.8, 10]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["overhangs_allowed", [["herringbone apex valleys, bridges under 3 mm", [[-7.8, -7.8, 4.4], [7.8, 7.8, 5.6]]]]],
    ["copies", 3],
    ["details", [
      ["planet_body", "material", [[2.5, -0.8, 0], [4.5, 0.8, 10]], 0.95],
      ["planet_thickness", "thickness", [3.5, 0, -1], [0, 0, 1], 10],
      ["herringbone", "view", [[-7.8, -7.8, 4], [7.8, 7.8, 6]]]
    ]]
  ]);
  planet_gear();
} else if (part == "ring") {
  echo(cadverify_spec = [
    ["bounds", [[-30, -30, 0], [30, 30, 10]]],
    ["bodies", 1],
    ["overhangs_allowed", [["herringbone apex valleys, bridges under 3 mm", [[-30, -30, 4.4], [30, 30, 5.6]]]]],
    ["copies", 1],
    ["details", [
      ["rim_body", "material", [[27, -1, 0], [29.5, 1, 10]], 0.95],
      ["center_empty", "void", [[-10, -10, -1], [10, 10, 11]], 0.95],
      ["rim_thickness", "thickness", [28, 0, -1], [0, 0, 1], 10],
      ["herringbone", "view", [[-26, -26, 4], [26, 26, 6]]]
    ]]
  ]);
  ring_gear();
} else if (part == "assembly") {
  echo(cadverify_spec = [
    ["bounds", [[-30, -30, 0], [30, 30, 10]]],
    ["overhangs_allowed", [["herringbone apex valleys, bridges under 3 mm", [[-30, -30, 4.4], [30, 30, 5.6]]]]],
    ["motions", [
      ["sun_turn", ["sun"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360],
        ["drives", [
          [[ "planet1" ], "rotate", [18, 0, 0], [0, 0, 1], -1.5],
          [[ "planet2" ], "rotate", [-9, 15.5885, 0], [0, 0, 1], -1.5],
          [[ "planet3" ], "rotate", [-9, -15.5885, 0], [0, 0, 1], -1.5],
          [[ "ring" ], "rotate", [0, 0, 0], [0, 0, 1], -0.428571]
        ]]
      ]
    ]],
    ["assembly_order", [
      [["sun", "planet1", "planet2", "planet3", "ring"], [0, 0, 0]]
    ]],
    ["print_in_place", 0.2],
    ["held", ["sun", "planet1", "planet2", "planet3", "ring"]]
  ]);
  instance("sun", "sun") sun_gear();
  instance("planet1", "planet") translate([18, 0, 0]) rotate([0, 0, 15]) planet_gear();
  instance("planet2", "planet") translate([-9, 15.5885, 0]) rotate([0, 0, 15]) planet_gear();
  instance("planet3", "planet") translate([-9, -15.5885, 0]) rotate([0, 0, 15]) planet_gear();
  instance("ring", "ring") ring_gear();
}
