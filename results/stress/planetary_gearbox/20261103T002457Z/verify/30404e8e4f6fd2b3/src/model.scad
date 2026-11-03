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
dx_apex = 1.0;         // herringbone apex shift at pitch (mm over half_h)
backlash_t = 0.1;      // thinning per side (mm), total flank clearance 4*t=0.4
Router = 30;           // ring outer radius (60 across)
hex_flat = 6.8;        // hex across flats for 1/4 inch bit (6.35 nominal + clearance)
flank_steps = 5;

p_circ = PI*m;
thick_tooth = p_circ/2 - 2*backlash_t;

Rp_sun = m*Zs/2;
Rb_sun = Rp_sun*cos(pa_deg);
Rt_sun = Rp_sun + m;
Rr_sun = Rp_sun - 1.25*m;

Rp_planet = m*Zp/2;
Rb_planet = Rp_planet*cos(pa_deg);
Rt_planet = Rp_planet + m;
Rr_planet = Rp_planet - 1.25*m;

Rp_ring = m*Zr/2;
Rb_ring = Rp_ring*cos(pa_deg);
Rt_ring = Rp_ring - m;
Rr_ring = Rp_ring + 1.25*m;

tw_sun = dx_apex/Rp_sun*180/PI;
tw_planet = dx_apex/Rp_planet*180/PI;
tw_ring = dx_apex/Rp_ring*180/PI;

Dcenter = Rp_sun + Rp_planet; // 18
Rhex = hex_flat/sqrt(3);

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
  // bottom half
  linear_extrude(height=half_h, twist=-tw_ring, slices=10, convexity=10)
    difference() {
      circle(r=Router, $fn=128);
      polygon(gear_outline(Zr, Rp_ring, Rb_ring, Rt_ring, Rr_ring, thick_tooth, flank_steps));
    }
  // top half, base rotated to meet apex
  translate([0,0,half_h]) rotate([0,0,-tw_ring])
    linear_extrude(height=half_h, twist=tw_ring, slices=10, convexity=10)
      difference() {
        circle(r=Router, $fn=128);
        polygon(gear_outline(Zr, Rp_ring, Rb_ring, Rt_ring, Rr_ring, thick_tooth, flank_steps));
      }
}

// ---- part specs + geometry ----
if (part == "sun") {
  echo(cadverify_spec = [
    ["bounds", [[-Rt_sun, -Rt_sun, 0], [Rt_sun, Rt_sun, thick]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
      ["sun_body", "material", [[4.5, -1, 0], [8.5, 1, thick]], 0.95],
      ["hex_empty", "void", [[-2, -2, -1], [2, 2, thick+1]], 0.95],
      ["sun_thickness", "thickness", [6, 0, -1], [0, 0, 1], thick],
      ["herringbone", "view", [[-Rt_sun, -Rt_sun, 4], [Rt_sun, Rt_sun, 6]]]
    ]]
  ]);
  sun_gear();
} else if (part == "planet") {
  echo(cadverify_spec = [
    ["bounds", [[-Rt_planet, -Rt_planet, 0], [Rt_planet, Rt_planet, thick]]],
    ["bodies", 1],
    ["through_holes", 0],
    ["overhangs_allowed", []],
    ["copies", 3],
    ["details", [
      ["planet_body", "material", [[2.5, -0.8, 0], [4.5, 0.8, thick]], 0.95],
      ["planet_thickness", "thickness", [3.5, 0, -1], [0, 0, 1], thick],
      ["herringbone", "view", [[-Rt_planet, -Rt_planet, 4], [Rt_planet, Rt_planet, 6]]]
    ]]
  ]);
  planet_gear();
} else if (part == "ring") {
  echo(cadverify_spec = [
    ["bounds", [[-Router, -Router, 0], [Router, Router, thick]]],
    ["bodies", 1],
    ["through_holes", 1],
    ["overhangs_allowed", []],
    ["copies", 1],
    ["details", [
      ["rim_body", "material", [[27, -1, 0], [29.5, 1, thick]], 0.95],
      ["center_empty", "void", [[-10, -10, -1], [10, 10, thick+1]], 0.95],
      ["rim_thickness", "thickness", [28, 0, -1], [0, 0, 1], thick],
      ["herringbone", "view", [[-26, -26, 4], [26, 26, 6]]]
    ]]
  ]);
  ring_gear();
} else if (part == "assembly") {
  echo(cadverify_spec = [
    ["overhangs_allowed", []],
    ["motions", [
      ["sun_turn", ["sun"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360],
        ["drives", [
          [[ "planet1" ], "rotate", [Dcenter, 0, 0], [0, 0, 1], -Zs/Zp],
          [[ "planet2" ], "rotate", [Dcenter*cos(120), Dcenter*sin(120), 0], [0, 0, 1], -Zs/Zp],
          [[ "planet3" ], "rotate", [Dcenter*cos(240), Dcenter*sin(240), 0], [0, 0, 1], -Zs/Zp],
          [[ "ring" ], "rotate", [0, 0, 0], [0, 0, 1], -Zs/Zr]
        ]]
      ]
    ]],
    ["assembly_order", [
      [["sun"], [0, 0, 0]],
      [["ring"], [0, 0, -1]],
      [["planet1"], [0, 0, -1], ["flex", [["planet1", "sun", 0.9, "herringbone teeth slide"], ["planet1", "ring", 0.9, "herringbone teeth slide"]]]],
      [["planet2"], [0, 0, -1], ["flex", [["planet2", "sun", 0.9, "herringbone teeth slide"], ["planet2", "ring", 0.9, "herringbone teeth slide"]]]],
      [["planet3"], [0, 0, -1], ["flex", [["planet3", "sun", 0.9, "herringbone teeth slide"], ["planet3", "ring", 0.9, "herringbone teeth slide"]]]]
    ]],
    ["print_in_place", 0.3],
    ["held", ["sun", "planet1", "planet2", "planet3", "ring"]]
  ]);
  instance("sun", "sun") sun_gear();
  instance("planet1", "planet") translate([Dcenter, 0, 0]) rotate([0, 0, 180/Zp]) planet_gear();
  instance("planet2", "planet") translate([Dcenter*cos(120), Dcenter*sin(120), 0]) rotate([0, 0, 180/Zp]) planet_gear();
  instance("planet3", "planet") translate([Dcenter*cos(240), Dcenter*sin(240), 0]) rotate([0, 0, 180/Zp]) planet_gear();
  instance("ring", "ring") ring_gear();
}
