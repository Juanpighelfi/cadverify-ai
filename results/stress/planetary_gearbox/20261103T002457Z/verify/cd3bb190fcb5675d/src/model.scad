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

// ---- parameters ----
m = 1.2;               // module
pa_deg = 20;           // pressure angle
Zs = 18;               // sun teeth
Zp = 12;               // planet teeth
Zr = 42;               // ring teeth
thick = 10;            // total thickness
half_h = 5;            // half thickness
dx_apex = 0.8;         // herringbone apex shift at pitch (mm over half_h)
backlash_t = 0.32;     // thinning per side (mm), flank clearance for 0.4 nozzle PLA
tip_cut = 0.35;        // tip shortening for radial clearance
flank_steps = 5;

p_circ = PI*m;
thick_tooth = p_circ/2 - 2*backlash_t;

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

Dcenter = Rp_sun + Rp_planet; // 18
Rhex = 6.8/sqrt(3);    // hex across flats 6.8 for 1/4 inch bit + clearance

// ---- involute helpers ----
function inv_rad(a_deg) = tan(a_deg) - a_deg*PI/180;
function half_at_rad(R, Rp, Rb, half0, inv_pa) = half0 + inv_pa - (R >= Rb ? inv_rad(acos(Rb/R)) : 0);

function gear_outline(Z, Rp, Rb, Rt, Rr, tooth_th, flank) =
  let(half0 = (tooth_th/Rp)/2,
      inv_pa = inv_rad(pa_deg),
      pitch = 360/Z)
  [for(i=[0:Z-1]) for(pt =
    concat(
      [for(j=[0:flank]) let(R = Rr+(Rt-Rr)*j/flank, hr = half_at_rad(R,Rp,Rb,half0,inv_pa), ang = i*pitch - hr*180/PI) [R*cos(ang), R*sin(ang)]],
      let(hrtip = half_at_rad(Rt,Rp,Rb,half0,inv_pa), ang2 = i*pitch + hrtip*180/PI) [[Rt*cos(ang2), Rt*sin(ang2)]],
      [for(j=[flank-1:-1:0]) let(R = Rr+(Rt-Rr)*j/flank, hr = half_at_rad(R,Rp,Rb,half0,inv_pa), ang = i*pitch + hr*180/PI) [R*cos(ang), R*sin(ang)]]
    )) pt
  ];

function hex_pts() = [for(k=[0:5]) let(a=k*60) [Rhex*cos(a), Rhex*sin(a)]];

// ---- gear modules (print orientation, rest on z=0) ----
module sun_gear() {
  difference() {
    union() {
      linear_extrude(height=half_h, twist=tw_sun, slices=10, convexity=10)
        polygon(gear_outline(Zs, Rp_sun, Rb_sun, Rt_sun, Rr_sun, thick_tooth, flank_steps));
      translate([0,0,half_h]) rotate([0,0,tw_sun])
        linear_extrude(height=half_h, twist=-tw_sun, slices=10, convexity=10)
          polygon(gear_outline(Zs, Rp_sun, Rb_sun, Rt_sun, Rr_sun, thick_tooth, flank_steps));
    }
    translate([0,0,-0.5]) linear_extrude(height=thick+1) polygon(hex_pts());
  }
}

module planet_gear() {
  union() {
    linear_extrude(height=half_h, twist=-tw_planet, slices=10, convexity=10)
      polygon(gear_outline(Zp, Rp_planet, Rb_planet, Rt_planet, Rr_planet, thick_tooth, flank_steps));
    translate([0,0,half_h]) rotate([0,0,-tw_planet])
      linear_extrude(height=half_h, twist=tw_planet, slices=10, convexity=10)
        polygon(gear_outline(Zp, Rp_planet, Rb_planet, Rt_planet, Rr_planet, thick_tooth, flank_steps));
  }
}

module ring_gear() {
  linear_extrude(height=half_h, twist=-tw_ring, slices=10, convexity=10)
    difference() {
      circle(r=30, $fn=128);
      polygon(gear_outline(Zr, Rp_ring, Rb_ring, Rt_ring, Rr_ring, thick_tooth, flank_steps));
    }
  translate([0,0,half_h]) rotate([0,0,-tw_ring])
    linear_extrude(height=half_h, twist=tw_ring, slices=10, convexity=10)
      difference() {
        circle(r=30, $fn=128);
        polygon(gear_outline(Zr, Rp_ring, Rb_ring, Rt_ring, Rr_ring, thick_tooth, flank_steps));
      }
}

// ---- part specs + geometry ----
if (part == "sun") {
  echo(cadverify_spec = [
    ["bounds", [[-11.65, -11.65, 0], [11.65, 11.65, 10]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["overhangs_allowed", [["herringbone apex valleys, bridges under 3 mm", [[-11.65, -11.65, 4.4], [11.65, 11.65, 5.6]]]]],
    ["copies", 1],
    ["details", [
      ["sun_body", "material", [[4.5, -1, 0], [8.5, 1, 10]], 0.95],
      ["hex_empty", "void", [[-2, -2, -1], [2, 2, 11]], 0.95],
      ["sun_thickness", "thickness", [6, 0, -1], [0, 0, 1], 10],
      ["herringbone", "view", [[-11.65, -11.65, 4], [11.65, 11.65, 6]]]
    ]]
  ]);
  sun_gear();
} else if (part == "planet") {
  echo(cadverify_spec = [
    ["bounds", [[-8.05, -8.05, 0], [8.05, 8.05, 10]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["overhangs_allowed", [["herringbone apex valleys, bridges under 3 mm", [[-8.05, -8.05, 4.4], [8.05, 8.05, 5.6]]]]],
    ["copies", 3],
    ["details", [
      ["planet_body", "material", [[2.5, -0.8, 0], [4.5, 0.8, 10]], 0.95],
      ["planet_thickness", "thickness", [3.5, 0, -1], [0, 0, 1], 10],
      ["herringbone", "view", [[-8.05, -8.05, 4], [8.05, 8.05, 6]]]
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
    ["print_in_place", 0.2],
    ["held", ["sun", "planet1", "planet2", "planet3", "ring"]]
  ]);
  instance("sun", "sun") sun_gear();
  instance("planet1", "planet") translate([18, 0, 0]) rotate([0, 0, 15]) planet_gear();
  instance("planet2", "planet") translate([-9, 15.5885, 0]) rotate([0, 0, 15]) planet_gear();
  instance("planet3", "planet") translate([-9, -15.5885, 0]) rotate([0, 0, 15]) planet_gear();
  instance("ring", "ring") ring_gear();
}
