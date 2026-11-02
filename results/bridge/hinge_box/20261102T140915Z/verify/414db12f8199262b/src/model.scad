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
            // pyramid field (single closed polyhedron) + top slab
            polyhedron(
                points = concat(
                    [for (y=[0:ny], x=[0:nx]) [-ox/2+px*x, -oy/2+py*y, fld_z]],
                    [for (j=[0:ny-1], i=[0:nx-1]) [-ox/2+px*i+px/2, -oy/2+py*j+py/2, lid_bot]]
                ),
                faces = concat(
                    [for (j=[0:ny-1], x=[0:nx-1])
                        [j*(nx+1)+x, j*(nx+1)+x+1, (j+1)*(nx+1)+x+1, (j+1)*(nx+1)+x]],
                    [for (j=[0:ny-1], i=[0:nx-1]) let(
                        a=(nx+1)*(ny+1)+j*nx+i,
                        p0=j*(nx+1)+i, p1=j*(nx+1)+i+1,
                        p2=(j+1)*(nx+1)+i+1, p3=(j+1)*(nx+1)+i)
                        each [[a,p1,p0],[a,p2,p1],[a,p3,p2],[a,p0,p3]]]
                )
            );
            translate([-ox/2,-oy/2,fld_z]) cube([ox,oy,lid_top-fld_z]);
            // lid knuckles (merge into the slab)
            for (s=lid_segs) {
                translate([0,y0,z0]) knuckle_cyl(s[0],s[1],Rk);
            }
        }
        // holes through lid knuckles (extend 0.3 into gaps)
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,-23.9-0.3]) cylinder(h=(-8.3+0.3)-(-23.9-0.3), r=Rh, $fn=32);
        translate([0,y0,z0]) rotate([0,90,0]) translate([0,0,8.3-0.3]) cylinder(h=(23.9+0.3)-(8.3-0.3), r=Rh, $fn=32);
        // catch notch (void, open at the lid front edge)
        translate([-5.4,26.8,29.9]) cube([10.8,3.2,2.3]);
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
        ["bounds", [[-40,-33.5,0],[42,30,35.6]]],
        ["bodies", 1],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["hinge", [[-40.5,-34,27],[42.5,-27,36]]],
            ["catch", [[-5.5,26.5,29],[5.5,30.5,32]]]
        ]],
        ["copies", 1],
        ["details", [
            ["outer_wall","thickness",[50,0,15],[-1,0,0],2.4],
            ["bottom","thickness",[5,10,-5],[0,0,1],2.4],
            ["divider","material",[[-37.5,-17.7,2.5],[37.5,-16.4,29.7]],0.85],
            ["rib","material",[[-0.7,-27.5,2.5],[0.7,27.5,29.7]],0.85],
            ["pillar","material",[[-14.7,-9.7,2.5],[-13.3,-8.3,29.7]],0.9],
            ["bump","material",[[-5,27.1,30],[5,29.7,31.5]],0.85],
            ["pedestal","material",[[39.6,-32.4,0.1],[41.9,-28.6,29.7]],0.9],
            ["knuckle_box","material",[[-7.8,-33.5,29.6],[7.8,-27.5,35.6]],0.4],
            ["knuckle_gap","void",[[-8.3,-33.5,29.6],[-7.8,-27.5,35.6]],0.7],
            ["hole_box","hole",[-8.05,-30.5,32.6],[1,0,0],[[0,3.5],[15,3.5]]]
        ]]
    ]);
    box_part();
} else if (part=="lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40,-33.5,30.4],[40,30,40]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["hinge", [[-40,-34,29],[40,-27,37]]],
            ["notch", [[-5.4,26.8,29.9],[5.4,30,32.2]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_top","thickness",[2,3,45],[0,0,-1],9.6],
            ["knuckle_lid","material",[[-23.9,-33.5,29.6],[-8.3,-27.5,35.6]],0.4],
            ["notch_void","void",[[-5.4,26.8,31.6],[5.4,29.9,32.1]],0.7],
            ["hole_lid","hole",[-8.05,-30.5,32.6],[-1,0,0],[[0,3.5],[15,3.5]]],
            ["texture","view",[[-8,-12,30.4],[8,6,33.6]]]
        ]]
    ]);
    lid_part();
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
