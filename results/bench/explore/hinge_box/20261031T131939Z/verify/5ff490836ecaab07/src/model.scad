/* Box with print-in-place hinge - PLA, 0.4mm nozzle, Bambu Lab A1, no supports
   Outside body ~80x60x40, lid ~10mm, hinge along back edge, pin printed in place.
   Print orientation = assembly orientation (+Z up). Assembly = closed box.
*/

// Customizer part selector
part = "assembly"; // [box:Box, lid:Lid, pin:Pin, assembly:Assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters (mm) ----------
W = 80; D = 60; boxH = 30; lidH = 10; gapV = 0.4;
wall = 2.4; floorT = 2.4; lidTopT = 2.4;
plugW = 74.4; plugD = 54.4; plugH = 3.0; // plug protrudes below lid
plugZ0 = 30.4 - plugH; // 27.4
lidZ0 = 30.4; lidZ1 = 40.4;
yAxis = -32; zAxis = 30.4;
knOD = 8; boreD = 4.8; pinD = 4.0; pinHeadD = 6; pinHeadT = 2;
hingeLen = 60; hingeX0 = -30; axGap = 0.5;
knL = (hingeLen - 4*axGap)/5; // 11.6

bumpW = 10; bumpP = 0.8; bumpZ0 = 28.2; bumpZ1 = 29.7;
notchW = 12; notchD = 1.0; notchZ0 = 28.0;

module box_part() {
    difference() {
        union() {
            // outer body
            translate([-W/2, -D/2, 0]) cube([W, D, boxH]);
            // box knuckles (3): idx 0,2,4
            for (i=[0,2,4]) {
                x0 = hingeX0 + i*(knL+axGap);
                translate([x0, yAxis, zAxis]) rotate([0,90,0]) cylinder(d=knOD, h=knL, $fn=64);
            }
        }
        // cavity
        translate([-W/2+wall, -D/2+wall, floorT]) cube([W-2*wall, D-2*wall, boxH - floorT + 1]);
        // knuckle bores
        for (i=[0,2,4]) {
            x0 = hingeX0 + i*(knL+axGap);
            translate([x0-0.1, yAxis, zAxis]) rotate([0,90,0]) cylinder(d=boreD, h=knL+0.2, $fn=48);
        }
        // front catch notch (open to top), centered x=0
        // inner face y = D/2-wall = 27.6
        translate([-notchW/2, D/2-wall, notchZ0]) cube([notchW, notchD, boxH - notchZ0 + 1]);
    }
}

module lid_part() {
    difference() {
        union() {
            // solid lid slab
            translate([-W/2, -D/2, lidZ0]) cube([W, D, lidH]);
            // inner plug
            translate([-plugW/2, -plugD/2, plugZ0]) cube([plugW, plugD, plugH]);
            // catch bump (wedge, 45deg underside, no horizontal overhang)
            polyhedron(points=[
                [-bumpW/2, 27.2, 28.2],
                [ bumpW/2, 27.2, 28.2],
                [ bumpW/2, 27.2, 29.7],
                [-bumpW/2, 27.2, 29.7],
                [-bumpW/2, 28.0, 29.0],
                [ bumpW/2, 28.0, 29.0],
                [ bumpW/2, 28.0, 29.7],
                [-bumpW/2, 28.0, 29.7]
            ], faces=[
                [0,1,2,3], [4,5,6,7], [0,4,7,3], [1,5,6,2], [3,2,6,7], [0,1,5,4]
            ]);
            // lid knuckles (2): idx 1,3
            for (i=[1,3]) {
                x0 = hingeX0 + i*(knL+axGap);
                translate([x0, yAxis, zAxis]) rotate([0,90,0]) cylinder(d=knOD, h=knL, $fn=64);
            }
        }
        // knuckle bores
        for (i=[1,3]) {
            x0 = hingeX0 + i*(knL+axGap);
            translate([x0-0.1, yAxis, zAxis]) rotate([0,90,0]) cylinder(d=boreD, h=knL+0.2, $fn=48);
        }
    }
}

module pin_part() {
    union() {
        // tip cone (lead-in) -30..-29.5
        translate([-30, yAxis, zAxis]) rotate([0,90,0]) cylinder(d1=3.0, d2=pinD, h=0.5, $fn=48);
        // shaft -29.5..30.6
        translate([-29.5, yAxis, zAxis]) rotate([0,90,0]) cylinder(d=pinD, h=60.1, $fn=48);
        // head 30.6..32.6
        translate([30.6, yAxis, zAxis]) rotate([0,90,0]) cylinder(d=pinHeadD, h=pinHeadT, $fn=48);
    }
}

// ---------- specs (in exported part coordinates = assembly coordinates) ----------
if (part == "box") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 34.4]]],
        ["bodies", 1],
        ["support_faces", [["bed", "-z", 4000]]],
        ["overhangs_allowed", [
            ["knuckle_curve", [[-30, -36, 26.4], [30, -28, 34.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["wall", "material", [[-40, -30, 0], [-37.6, 30, 30]], 0.9],
            ["floor", "material", [[-40, -30, 0], [40, 30, 2.4]], 0.9],
            ["knuckle", "material", [[-30, -36, 26.4], [-18.4, -28, 34.4]], 0.5],
            ["notch", "void", [[-6, 27.6, 28.0], [6, 28.6, 30.5]], 0.9],
            ["knuckle_gap", "void", [[-18.4, -36, 26.4], [-17.9, -28, 34.4]], 0.9],
            ["bore", [-31, -32, 30.4], [1, 0, 0], [[0, 4.8], [11.6, 4.8]]],
            ["wall_thick", [41, 0, 15], [-1, 0, 0], 2.4],
            ["floor_thick", [0, 0, -1], [0, 0, 1], 2.4],
            ["notch_view", "view", [[-6, 27.0, 28.0], [6, 29.0, 30.2]]]
        ]]
    ]);
    box_part();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 26.4], [40, 30, 40.4]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["knuckle_curve", [[-30, -36, 26.4], [30, -28, 34.4]]],
            ["lid_bridge", [[-40, -30, 27.4], [40, 30, 30.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_slab", "material", [[-40, -30, 38.0], [40, 30, 40.4]], 0.9],
            ["plug", "material", [[-37.2, -27.2, 27.4], [37.2, 27.2, 30.4]], 0.9],
            ["bump", "material", [[-5, 27.2, 28.2], [5, 28.0, 29.7]], 0.5],
            ["knuckle", "material", [[-17.9, -36, 26.4], [-6.3, -28, 34.4]], 0.5],
            ["knuckle_gap", "void", [[-6.3, -36, 26.4], [-5.8, -28, 34.4]], 0.9],
            ["bore", [-18.0, -32, 30.4], [1, 0, 0], [[0, 4.8], [11.6, 4.8]]],
            ["lid_top_thick", [0, 0, 41.4], [0, 0, -1], 2.4],
            ["bump_view", "view", [[-5, 26.5, 27.5], [5, 28.5, 30.0]]]
        ]]
    ]);
    lid_part();
} else if (part == "pin") {
    echo(cadverify_spec = [
        ["bounds", [[-30, -35, 27.4], [32.6, -29, 33.4]]],
        ["bodies", 1],
        ["overhangs_allowed", [
            ["pin_curve", [[-30, -35, 27.4], [32.6, -29, 33.4]]]
        ]],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-29.5, -34, 28.4], [30.6, -30, 32.4]], 0.5],
            ["head", "material", [[30.6, -35, 27.4], [32.6, -29, 33.4]], 0.5],
            ["shaft_dia", [0, -35, 30.4], [0, 1, 0], 4.0],
            ["head_view", "view", [[30.0, -35, 27.4], [33.0, -29, 33.4]]]
        ]]
    ]);
    pin_part();
} else {
    // assembly = closed box
    echo(cadverify_spec = [
        ["bounds", [[-40, -36, 0], [40, 30, 40.4]]],
        ["support_faces", [["bed", "-z", 4000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lid_swing", ["lid"], "rotate", [-32, 30.4, 0], [1, 0, 0], [0, 110]]
        ]],
        ["assembly_order", [
            [["box"], [0, 0, 0]],
            [["lid"], [0, 0, 30]],
            [["pin"], [30, 0, 0]]
        ]]
    ]);
    instance("box", "box") box_part();
    instance("lid", "lid") lid_part();
    instance("pin", "pin") pin_part();
}
