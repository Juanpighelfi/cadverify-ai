// Box with print-in-place hinge - closed assembly is +Z up
// Hinge knuckles sit behind the box and merge straight into the back wall (box)
// and the lid slab (lid): no webs. The lid underside is a field of 45-degree
// pyramids (tips 0.4 mm over the box grid) so the closed lid has no flat
// ceiling; four pillars under four pyramid tips steady the lid in the print.
part = "assembly"; // [box, lid, pin, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// Parameters (mm)
ox = 80; oy = 60;
box_h = 30; gap = 0.4;
lid_bot = box_h + gap; // 30.4
lid_top = 40;
wall = 2.4; bot_t = 2.4;
ix = ox - 2*wall; // 75.2
iy = oy - 2*wall; // 55.2
Rk = 3.0; Rh = 1.75; Rp = 1.4;
y0 = -oy/2 - 0.5; // -30.5
z0 = 32.6;

// knuckle intervals along X
box_segs = [[-40,-24.4],[-7.8,7.8],[24.4,40]];
lid_segs = [[-23.9,-8.3],[8.3,23.9]];

// interior compartment grid (full height walls, tops at 30.0)
div_t = 1.6;
div_ys = [-17.84,-6.48,4.88,16.24];
ribxs = [-29.6,-20.0,-10.4,-0.8,8.8,18.4,28.0];
// support pillars (1.6 x 1.6, tops at 30.0) under four pyramid tips
pillars = [[-14,-9],[14,-9],[-14,3],[14,3]];

// lid pyramid field: 20 x 10 pyramids, 4 x 6 base, 3.2 tall (faces <= 45 deg)
fld_z = 33.6; // pyramid bases / slab bottom
nx = 20; ny = 10; px = 4; py = 6;

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
                translate([x_start, -iy/2-0.2, 2.0]) cube([div_t, iy+0.4, box_h-2.0]);
            }
            // support pillars
            for (p=pillars) {
                translate([p[0]-0.8, p[1]-0.8, 2.0]) cube([1.6, 1.6, box_h-2.0]);
            }
            // catch bump on front wall top (flush with the front face)
            translate([-5, oy/2-wall, 29.5]) cube([10, wall, 2.0]);
            // box knuckles (merge into the back wall top)
            for (s=box_segs) {
                translate([0,y0,z0]) knuckle_cyl(s[0],s[1],Rk);
            }
            // blind cap at left outer end (0.8 thick)
            translate([-40,y0,z0]) rotate([0,90,0]) cylinder(h=0.8, r=Rk, $fn=48);
            // pin-head pedestal: stands on bed, 0.3 under the pin head
            translate([39.5,y0-2,0]) cube([2.5,4.0,29.8]);
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
            // lid knuckles (merge into the slab)
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
        // catch notch (void, open at the lid front edge)
        translate([-5.4,26.8,29.9]) cube([10.8,3.2,2.3]);
        // hinge pockets where box knuckles pass (0.3 clearance each side, open at back)
        for (cx=[-32.2,0,32.2]) {
            translate([cx-4.3,-33.5,lid_bot]) cube([8.6,6.5,3.3]);
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
effect = "none";
} else if (part=="pin") {
    echo(cadverify_spec = [
        ["bounds", [[-38.7,-33,30.1],[42.0,-28,35.1]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["shaft_low", [[-38.9,-32.1,31.0],[40.7,-29.9,32.2]]],
            ["head_low", [[40.3,-33.2,29.9],[42.2,-28.8,31.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["pin_dia","thickness",[0,-28.5,32.6],[0,-1,0],2.8]
        ]]
    ]);
    pin_part();
} else {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.5,0],[42,30,40]]],
        ["support_faces", [["bed","-z",4000]]],
        ["motions", [
            ["lid_swing", ["lid_inst"], "rotate", [0,-30.5,32.6], [1,0,0], [0,110]]
        ]],
        ["assembly_order", [
            [["box_inst"], [0,0,0]],
            [["lid_inst"], [0,0,-1]],
            [["pin_inst"], [-1,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge", [[-40.5,-34,29],[42.5,-27,37]]],
            ["lid_interface", [[-40,-27,29],[40,30,33]]]
        ]]
    ]);
    assembly_mod();
}
