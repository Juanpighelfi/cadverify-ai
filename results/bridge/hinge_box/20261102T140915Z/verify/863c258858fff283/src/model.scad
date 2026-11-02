// Box with print-in-place hinge - closed assembly is +Z up
part = "assembly"; // [box, lid, pin, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
ox = 80; oy = 54;
box_h = 30; gap = 0.4;
lid_bot = box_h + gap; // 30.4
lid_top = 40;
wall = 2.4; bot_t = 2.4;
ix = ox - 2*wall; // 75.2
iy = oy - 2*wall; // 49.2
Rk = 3.0; Rh = 1.75; Rp = 1.4;
y0 = -oy/2 - 3.4; // -30.4
z0 = lid_bot + Rk; // 33.4

// knuckle intervals along X
box_segs = [[-40,-24.4],[-7.8,7.8],[24.4,40]];
lid_segs = [[-23.9,-8.3],[8.3,23.9]];
box_cx = [-32.2, 0, 32.2];
lid_cx = [-16.1, 16.1];

// interior support grid: 4 dividers along X, 7 ribs along Y,
// plus full-perimeter inner ledges; tops at 30.0 (0.4 under the lid)
div_t = 1.6;
slot = 8.56;
div_ys = [for (i=[0:3]) -iy/2 + slot + i*(slot+div_t)]; // -16.04, -5.88, 4.28, 14.44
ribyt0 = -oy/2 + wall; // -24.6
ribxs = [-29.6,-20.0,-10.4,-0.8,8.8,18.4,28.0];
// wall-ledges along X on the full inner perimeter (front/back band)
band_t = 8.56;
band_ys = [-iy/2, iy/2-band_t]; // -24.6, 16.04
// cross ledges along Y at left/right ends
cross_xs = [-ix/2, ix/2-div_t]; // -37.6, 36.0

module knuckle_cyl(x1,x2,r) {
    rotate([0,90,0]) translate([0,0,x1]) cylinder(h=x2-x1, r=r, $fn=48);
}

module box_part() {
    difference() {
        union() {
            // bottom slab
            translate([-ox/2,-oy/2,0]) cube([ox,oy,bot_t]);
            // 4 walls
            translate([-ox/2,-oy/2,0]) cube([ox,wall,box_h]);
            translate([-ox/2,oy/2-wall,0]) cube([ox,wall,box_h]);
            translate([-ox/2,-oy/2+wall,0]) cube([wall,iy,box_h]);
            translate([ox/2-wall,-oy/2+wall,0]) cube([wall,iy,box_h]);
            // dividers along X
            for (y_start=div_ys) {
                translate([-ix/2-0.2, y_start, 2.0]) cube([ix+0.4, div_t, box_h-2.0]);
            }
            // ribs along Y
            for (x_start=ribxs) {
                translate([x_start, ribyt0, 2.0]) cube([div_t, iy, box_h-2.0]);
            }
            // support bands along X (front/back), floor of the lid bays
            for (y_start=band_ys) {
                translate([-ix/2, y_start, 28.0]) cube([ix, band_t, 2.0]);
            }
            // cross ledges along Y (left/right ends)
            for (x_start=cross_xs) {
                translate([x_start, -iy/2, 28.0]) cube([div_t, iy, 2.0]);
            }
            // catch bump on front wall top
            translate([-5, oy/2-wall-0.5, 29.5]) cube([10, wall+0.5, 2.0]);
            // box knuckles
            for (s=box_segs) {
                translate([0,y0,z0]) knuckle_cyl(s[0],s[1],Rk);
            }
            // blind cap at left outer end (0.8 thick)
            translate([-40,y0,z0]) rotate([0,90,0]) cylinder(h=0.8, r=Rk, $fn=48);
            // box webs: sit on back-wall top, merge into knuckles
            for (cx=box_cx) {
                translate([cx-4,-28,30]) cube([8,1.5,3.4]);
            }
            // pin-head pedestal: stands on bed, 0.3 under the pin head
            translate([39.5,-32.3,0]) cube([2.5,4.0,30.6]);
        }
        // holes
        // left blind hole: -39.2..-24.4 +0.3 ext into gap
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,-39.2]) cylinder(h=(-24.4+0.3)-(-39.2), r=Rh, $fn=32);
        // center through: -7.8-0.3 .. 7.8+0.3
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,-7.8-0.3]) cylinder(h=(7.8+0.3)-(-7.8-0.3), r=Rh, $fn=32);
        // right through: 24.4-0.3 .. 40+0.3
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,24.4-0.3]) cylinder(h=(40+0.3)-(24.4-0.3), r=Rh, $fn=32);
    }
}

module lid_part() {
    difference() {
        union() {
            // solid lid slab
            translate([-ox/2,-oy/2,lid_bot]) cube([ox,oy,lid_top-lid_bot]);
            // lid knuckles
            for (s=lid_segs) {
                translate([0,y0,z0]) knuckle_cyl(s[0],s[1],Rk);
            }
            // lid webs: merge lid slab into lid knuckles
            for (cx=lid_cx) {
                translate([cx-4,-28,30.4]) cube([8,2.0,3.0]);
            }
        }
        // holes through lid knuckles (extend 0.3 into gaps)
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,-23.9-0.3]) cylinder(h=(-8.3+0.3)-(-23.9-0.3), r=Rh, $fn=32);
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,8.3-0.3]) cylinder(h=(23.9+0.3)-(8.3-0.3), r=Rh, $fn=32);
        // catch notch (void): X -5.4..5.4, Y 23.8..27.3, Z 29.9..32.2
        translate([-5.4,23.8,29.9]) cube([10.8,3.5,2.3]);
        // hinge pockets where box webs pass (0.3 clearance each side/top/front)
        for (cx=box_cx) {
            translate([cx-4.3,-27.7,lid_bot]) cube([8.6,1.5,3.3]);
        }
        // end pockets over the cross ledges (0.3 clearance, 2.0 deep)
        for (x_start=cross_xs) {
            translate([x_start-0.3,-iy/2-0.3,lid_bot]) cube([2.2,iy+0.6,2.0]);
        }
    }
}

module pin_part() {
    // shaft -38.7..40.5, head 40.5..42.0 dia 5
    translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,-38.7]) cylinder(h=40.5-(-38.7), r=Rp, $fn=32);
    translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,40.5]) cylinder(h=1.5, r=2.5, $fn=32);
}

module assembly_mod() {
    instance("box_inst","box") box_part();
    instance("lid_inst","lid") lid_part();
    instance("pin_inst","pin") pin_part();
}

// specs
if (part=="box") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.4,0],[42,27,36.4]]],
        ["bodies", 1],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["hinge", [[-40,-33.6,27],[42,-25.5,36.6]]],
            ["catch", [[-5,24.1,29.5],[5,27,31.5]]],
            ["bands", [[-38,-25,27.5],[38,25,30.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["outer_wall","thickness",[50,0,15],[-1,0,0],2.4],
            ["bottom","thickness",[5,10,-5],[0,0,1],2.4],
            ["divider","material",[[-37.4,-16.04,2.4],[37.4,-14.44,29.8]],0.85],
            ["rib","material",[[-0.8,-24.6,2.4],[0.8,24.6,29.8]],0.85],
            ["band","material",[[-37.5,16.1,28.1],[37.5,24.5,29.9]],0.9],
            ["cross_ledge","material",[[36.1,-24.5,28.1],[37.5,24.5,29.9]],0.9],
            ["bump","material",[[-5,24.6,30],[5,27,31.5]],0.85],
            ["web_box","material",[[-4,-27.5,30],[4,-26.5,31]],0.9],
            ["pedestal","material",[[39.5,-32.3,0],[42,-28.3,30.6]],0.9],
            ["knuckle_box","material",[[-7.8,-33.4,30.4],[7.8,-27.4,36.4]],0.4],
            ["knuckle_gap","void",[[-8.3,-33.4,30.4],[-7.8,-27.4,36.4]],0.7],
            ["hole_box","hole",[-8.05,-30.4,33.4],[1,0,0],[[0,3.5],[15,3.5]]]
        ]]
    ]);
    box_part();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.4,30.4],[40,27,40]]],
        ["bodies", 1],
        ["support_faces", [["bed","-z",1200]]],
        ["overhangs_allowed", [
            ["hinge", [[-40,-33.6,29],[40,-25.5,37]]],
            ["notch", [[-5.4,23.8,29.9],[5.4,27.3,32.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_top","thickness",[0,0,45],[0,0,-1],9.6],
            ["knuckle_lid","material",[[-23.9,-33.4,30.4],[-8.3,-27.4,36.4]],0.4],
            ["web_lid","material",[[12.1,-27,30.4],[20.1,-26,32]],0.9],
            ["end_pocket","void",[[35.7,-24.9,30.4],[38.2,24.9,32.4]],0.6],
            ["notch_void","void",[[-5.4,23.8,30.4],[5.4,27,32.2]],0.7],
            ["pocket_void2","void",[[-4.3,-27.7,30.4],[4.3,-26.2,33.7]],0.7],
            ["hole_lid","hole",[-8.05,-30.4,33.4],[-1,0,0],[[0,3.5],[15,3.5]]]
        ]]
    ]);
    lid_part();
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [[-38.7,-32.9,30.9],[42.0,-27.9,35.9]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["shaft_low", [[-38.9,-31.6,31.8],[40.7,-29.2,32.6]]],
            ["head_low", [[40.3,-32.4,30.7],[42.2,-28.4,31.8]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_dia","thickness",[0,-28.5,33.4],[0,-1,0],2.8]
        ]]
    ]);
    pin_part();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.4,0],[42,27,40]]],
        ["support_faces", [["bed","-z",4000]]],
        ["motions", [
            ["lid_swing", ["lid_inst"], "rotate", [0,-30.4,33.4], [1,0,0], [0,110]]
        ]],
        ["assembly_order", [
            [["box_inst"], [0,0,0]],
            [["lid_inst"], [0,0,-1]],
            [["pin_inst"], [-1,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge", [[-40,-33.6,27],[42,-25.5,37]]],
            ["lid_interface", [[-40,-27,29],[40,27,32.9]]]
        ]]
    ]);
    assembly_mod();
}
