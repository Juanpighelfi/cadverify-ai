// Box with print-in-place hinge: box + lid + captive pin, one print.
// Print orientation / assembly coordinates: X 0..80, Y 0(front)..60(back), Z 0..40.
// Lid swing axis: Y=56.2, Z=34, along X.  Clearances 0.4-0.6 mm for PLA / 0.4 nozzle.

part = "assembly"; // [assembly, box, lid, pin]

W = 80; D = 60; H = 40;
baseH = 30;          // top rim of box
lidGap = 0.4;        // print-in-place gap between lid skirt and box rim
wall = 2.4;
ay = 56.2; az = 34;  // hinge axis (assembly coords)
kR = 3.8;            // knuckle outer radius
boreR = 2.4;         // knuckle bore radius (pin max radius 2.0 -> >=0.4 clearance)
lidClearR = 4.3;     // lid clearance around knuckles (0.5 over kR)
recessR = 7.6;       // hinge recess swept clearance in box

// knuckle segments along X
baseSegs = [[8,22],[34,48],[60,72]];
lidSegs  = [[22.6,33.4],[48.6,59.4]];

$fn = 64;
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- helpers ----------
module axis_cyl(r, x1, x2) {
    translate([x1, ay, az]) rotate([0,90,0]) cylinder(h = x2-x1, r = r);
}
// profile given as [y,z] absolute points, extruded along X from x1
module extrude_yz_abs(profile, x1, len) {
    translate([x1,0,0])
      multmatrix([[0,0,1,0],[1,0,0,0],[0,1,0,0],[0,0,0,1]])
        linear_extrude(height = len) polygon(points = profile);
}
// teardrop pin profile in [dy,dz] rel. axis: round top, pointed bottom (self-supporting 45+deg)
function teardrop(r, drop) =
    concat([[0,-drop],[r,0]],
           [for(a=[15:15:165]) [r*cos(a), r*sin(a)]],
           [[-r,0]]);

// ---------- box ----------
module box_body() {
    difference() {
        cube([W,D,baseH]);
        translate([wall,wall,wall]) cube([W-2*wall, D-2*wall, baseH]); // interior
        axis_cyl(recessR, -1, W+1);                                     // hinge recess trough
        // front catch recess (tab pocket), open at top/front
        translate([27.4,-1,24.2]) cube([25.2, 3.4, 7]);
    }
}
module catch_boss() {
    difference() {
        translate([25,wall,19]) cube([30, 2.8, 11]); // interior boss, front face y=2.4
        // groove for lid bump (assembly coords)
        translate([36.4,2.4,25.5]) cube([7.2, 0.9, 5.5]);
    }
}
module catch_bead() {
    // bar across the groove, 45deg underside
    extrude_yz_abs([[1.9,29.7],[3.3,29.7],[3.3,27.5],[1.9,28.9]], 34, 12);
}
module box_geom() {
    union() {
        box_body();
        catch_boss();
        catch_bead();
        // knuckles + support ribs (rib top z=31 overlaps knuckle bottom 30.2, clear of pin tip 32.1)
        for(s = baseSegs) {
            difference() {
                axis_cyl(kR, s[0], s[1]);
                axis_cyl(boreR, s[0]-1, s[1]+1);
            }
            translate([(s[0]+s[1])/2-3, 54.9, 0]) cube([6, 2.9, 31]);
        }
    }
}

// ---------- lid (built in assembly coords) ----------
module lid_cap() {
    difference() {
        union() {
            translate([0,0,37.6]) cube([W,D,2.4]);                    // top plate -> z 40
            translate([0,0,baseH+lidGap]) cube([W,wall,37.6-(baseH+lidGap)]); // front skirt
            translate([0,0,baseH+lidGap]) cube([wall,D,37.6-(baseH+lidGap)]); // left skirt
            translate([W-wall,0,baseH+lidGap]) cube([wall,D,37.6-(baseH+lidGap)]); // right skirt
            translate([28,0,25]) cube([24,1.6,7]);                    // front catch tab
        }
        axis_cyl(lidClearR, -1, W+1);                                 // clearance to base knuckles/pin
        translate([-1,53,-1]) cube([W+2, 8, 34.9]);                   // back/lower hinge notch (to z=33.9)
    }
}
module catch_bump() {
    extrude_yz_abs([[0.8,25.8],[2.55,26.6],[2.7,27.0],[2.05,27.8],[0.8,27.8]], 37, 6);
}
module lid_geom() {
    union() {
        lid_cap();
        catch_bump();
        for(s = lidSegs) {
            difference() {
                axis_cyl(kR, s[0], s[1]);
                axis_cyl(boreR, s[0]-1, s[1]+1);
            }
            // neck from knuckle up into top plate (bottom z=36, clear of pin top 35.7)
            translate([(s[0]+s[1])/2-3, 54.9, 36]) cube([6, 2.9, 3.6]);
        }
    }
}

// ---------- pin (assembly coords) ----------
module pin_geom() {
    union() {
        // shaft x 6..74
        translate([6,ay,az])
          multmatrix([[0,0,1,0],[1,0,0,0],[0,1,0,0],[0,0,0,1]])
            linear_extrude(height = 68) polygon(points = teardrop(1.7, 1.9));
        // head x 74..77
        translate([74,ay,az])
          multmatrix([[0,0,1,0],[1,0,0,0],[0,1,0,0],[0,0,0,1]])
            linear_extrude(height = 3) polygon(points = teardrop(3.0, 3.3));
    }
}

// ---------- specs + output ----------
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[0,0,0],[W,D,az+kR]]],
        ["bodies", 1],
        ["support_faces", [["bed","-z",4000]]],
        ["overhangs_allowed", [
            ["hinge knuckle and pin-space undersides, recess trough at back", [[4,48,25],[76,60,38.5]]],
            ["catch bead 45deg underside at front", [[33,0,27],[47,4,30.2]]],
            ["catch boss flat top inside front wall", [[24,2,18.5],[56,5.5,19.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["floor", "material", [[2,2,0],[78,58,2.2]], 0.9],
            ["interior", "void", [[5,6,5],[75,50,25]], 0.95],
            ["hinge_knuckle", "material", [[9,53,30],[21,60,37.5]], 0.35],
            ["catch_bead", "material", [[35,1.9,27.8],[45,3.2,29.6]], 0.35],
            ["catch_groove", "void", [[36.6,2.5,25.7],[43.4,3.2,27.6]], 0.9],
            ["front_wall", "thickness", [20,-1,15], [0,1,0], wall],
            ["floor_thickness", "thickness", [20,20,-1], [0,0,1], wall],
            ["hinge_view", "view", [[5,48,25],[76,60,38.5]]],
            ["catch_view", "view", [[25,0,19],[55,6,30.5]]]
        ]]
    ]);
    box_geom();
} else if (part == "lid") {
    // exported shifted down by 25mm so its lowest face (catch tab) is z=0
    echo(cadverify_spec = [
        ["bounds", [[0,0,0],[W,D,15]]],
        ["bodies", 1],
        ["support_faces", [["catch_tab_bottom","-z",30]]],
        ["overhangs_allowed", [
            ["lid top underside bridges across the box interior (55mm bridge)", [[0,2,11.5],[80,60,13.5]]],
            ["hinge knuckle bores and undersides at back", [[18,49,4],[64,60,13.2]]],
            ["skirt rim faces sit on box rim in print-in-place", [[0,0,4.9],[80,53,5.9]]],
            ["catch bump underside at front", [[33,0,0],[47,4,4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top_plate", "material", [[2,2,12.8],[78,58,15]], 0.75],
            ["cavity", "void", [[5,5,6],[75,50,12]], 0.95],
            ["catch_tab", "material", [[29,0,0.3],[51,1.5,6]], 0.8],
            ["knuckle_bore", "hole", [21,ay,9], [1,0,0], [[0,4.7],[5,4.7],[10,4.7]]],
            ["top_thickness", "thickness", [40,30,16], [0,0,-1], 2.4],
            ["front_skirt", "thickness", [20,-1,10], [0,1,0], wall],
            ["hinge_view", "view", [[18,49,4],[64,60,13.5]]],
            ["catch_view", "view", [[27,0,0],[53,4,8]]]
        ]]
    ]);
    translate([0,0,-25]) lid_geom();
} else if (part == "pin") {
    // exported shifted down by 30.7mm (tip of head is z=0)
    echo(cadverify_spec = [
        ["bounds", [[6,53.2,0],[77,59.2,6.3]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", []],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[20,54.9,2.2],[40,57.5,4.9]], 0.5],
            ["head", "material", [[74.4,54.0,1.2],[76.6,58.4,6.0]], 0.45],
            ["point_clearance", "void", [[20,54.5,0.2],[30,57.9,1.2]], 0.95],
            ["shaft_thickness", "thickness", [30,56.2,7], [0,0,-1], 3.6],
            ["head_view", "view", [[73,53,0],[77.5,59.5,6.5]]]
        ]]
    ]);
    translate([0,0,-30.7]) pin_geom();
} else { // assembly, closed, in print pose
    echo(cadverify_spec = [
        ["bounds", [[0,0,0],[W,D,H]]],
        ["support_faces", [["bed","-z",4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [0,ay,az], [-1,0,0], [0,110],
                ["flex", [["lid","box",0.9,"catch bump rides past the bead; front tab flexes forward"]]]]
        ]],
        ["assembly_order", [
            [["box"], [0,0,0]],
            [["lid"], [0,-1,0]],
            [["pin"], [-1,0,0]]
        ]],
        ["print_in_place", 0.3],
        ["overhangs_allowed", [
            ["hinge knuckle bores, pin and recess undersides at back (small self-supported spans)", [[4,48,25],[76,60,38.5]]],
            ["lid top underside bridges across the box interior (55mm bridge)", [[0,2.4,36.5],[80,60,38.6]]],
            ["catch bead/bump undersides at front", [[27,0,24],[53,5,30.5]]],
            ["catch boss flat top inside front wall", [[24,2,18.5],[56,5.5,19.5]]],
            ["lid skirt rim faces rest 0.4mm above box rim, printed in place", [[0,0,29.5],[80,60,31]]]
        ]]
    ]);
    instance("box", "box") box_geom();
    instance("lid", "lid") lid_geom();
    instance("pin", "pin") pin_geom();
}
