// Box with print-in-place hinge - closed assembly is +Z up
part = "assembly";
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
Rk = 3.0; Rh = 1.7; Rp = 1.4;
y0 = -oy/2 - 3.3; // -30.3
z0 = lid_bot + Rk; // 33.4

// knuckle intervals along X
box_segs = [[-40,-24.4],[-7.8,7.8],[24.4,40]];
lid_segs = [[-23.9,-8.3],[8.3,23.9]];

// interior divider Y positions: 4 dividers, 5 slots of 8.56
div_t = 1.6;
slot = 8.56;
div_ys = [for (i=[0:3]) -iy/2 + slot + i*(slot+div_t)]; // -16.04, -5.88, 4.28, 14.44

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
            // dividers running along X (support lid first layer as 8.56 mm bridges)
            for (y_start=div_ys) {
                translate([-ix/2-0.2, y_start, 2.0]) cube([ix+0.4, div_t, box_h-2.0]);
            }
            // catch bump on front wall top
            translate([-5, oy/2-wall-0.5, 29.5]) cube([10, wall+0.5, 2.0]);
            // box knuckles
            for (s=box_segs) {
                translate([0,y0,z0]) knuckle_cyl(s[0],s[1],Rk);
            }
            // blind cap at left outer end (0.8 thick)
            translate([-40,y0,z0]) rotate([0,90,0]) cylinder(h=0.8, r=Rk, $fn=48);
            // box lugs (8 wide, Y -28.5..-26, Z 29..31.5)
            for (cx=[-32.2,0,32.2]) {
                translate([cx-4,-28.5,29]) cube([8,2.5,2.5]);
            }
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
            // lid lugs
            for (cx=[-16.1,16.1]) {
                translate([cx-4,-28.5,31.5]) cube([8,2.5,2.5]);
            }
        }
        // holes through lid knuckles (extend 0.3 into gaps)
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,-23.9-0.3]) cylinder(h=(-8.3+0.3)-(-23.9-0.3), r=Rh, $fn=32);
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,8.3-0.3]) cylinder(h=(23.9+0.3)-(8.3-0.3), r=Rh, $fn=32);
        // catch notch (void): X -5.4..5.4, Y 23.8..27.3, Z 29.9..32.2
        translate([-5.4,23.8,29.9]) cube([10.8,3.5,2.3]);
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
        ["bounds", [[-40,-33.3,0],[40,27,36.4]]],
        ["bodies", 1],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["hinge", [[-40,-33.5,29],[40,-26,36.6]]],
            ["catch", [[-5,24.1,29.5],[5,27,31.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["outer_wall","thickness",[50,0,15],[-1,0,0],2.4],
            ["bottom","thickness",[0,0,-5],[0,0,1],2.4],
            ["divider","material",[[-37.4,-16.04,2.4],[37.4,-14.44,29.8]],0.85],
            ["bump","material",[[-5,24.6,30],[5,27,31.5]],0.85],
            ["knuckle_box","material",[[-7.8,-33.3,30.4],[7.8,-27.3,36.4]],0.4],
            ["knuckle_gap","void",[[-8.3,-33.3,30.4],[-7.8,-27.3,36.4]],0.7],
            ["hole_box","hole",[-8.05,-30.3,33.4],[1,0,0],[[0,3.4],[15.6,3.4]]]
        ]]
    ]);
    box_part();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.3,30.4],[40,27,40]]],
        ["bodies", 1],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["hinge", [[-40,-33.5,29],[40,-26,37]]],
            ["notch", [[-5.4,23.8,29.9],[5.4,27.3,32.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_top","thickness",[0,0,45],[0,0,-1],9.6],
            ["knuckle_lid","material",[[-23.9,-33.3,30.4],[-8.3,-27.3,36.4]],0.4],
            ["notch_void","void",[[-5.4,23.8,30.4],[5.4,27,32.2]],0.7],
            ["hole_lid","hole",[-8.05,-30.3,33.4],[-1,0,0],[[0,3.4],[15.6,3.4]]]
        ]]
    ]);
    lid_part();
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [[-38.7,-32.8,30.9],[42.0,-27.8,35.9]]],
        ["bodies", 1],
        ["overhangs_allowed", [["pin_below", [[-38.7,-32.8,30.9],[42.0,-27.8,33.4]]]]],
        ["copies", 1],
        ["details", [
            ["pin_dia","thickness",[0,-28.5,33.4],[0,-1,0],2.8]
        ]]
    ]);
    pin_part();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.3,0],[42,27,40]]],
        ["support_faces", [["bed","-z",4000]]],
        ["motions", [
            ["lid_swing", ["lid_inst"], "rotate", [0,-30.3,33.4], [1,0,0], [0,110]]
        ]],
        ["assembly_order", [
            [["box_inst"], [0,0,0]],
            [["lid_inst"], [0,0,-1]],
            [["pin_inst"], [-1,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge", [[-40,-33.5,29.5],[42,-26,37]]],
            ["lid_interface", [[-40,-27,29.5],[40,27,32.5]]]
        ]]
    ]);
    assembly_mod();
}
