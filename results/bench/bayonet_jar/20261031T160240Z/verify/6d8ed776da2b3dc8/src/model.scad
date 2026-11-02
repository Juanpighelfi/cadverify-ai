/* Desk jar with bayonet lid
   Print: PETG, Bambu A1, 0.4 nozzle, no supports.
   Jar prints base-down. Lid prints top-face-down (skirt up).
   All dimensions mm.
*/
part = "jar"; // [jar, lid, assembly]
$fn = 128;

// ---- Parameters ----
R_out   = 37.5;   // jar / lid outside radius (75 dia, flush)
R_in    = 35.0;   // jar main bore radius (70 dia)
wall    = R_out - R_in; // 2.5
floor_t = 2.5;
jar_h   = 82.5;   // rim height; bore depth = jar_h - floor_t = 80
neck_ro = 35.0;   // stepped neck outside
neck_ri = 32.0;   // neck bore (3.0 neck wall)
shoulder_z = 60.0;

slot_floor_r = 33.6; // groove floor radius: leaves 1.6 wall to neck bore
slot_z  = 71.0;      // centre of horizontal bayonet run
slot_h  = 5.2;       // horizontal slot height
entry_w = 7.2;       // vertical entry width

lid_h   = 20.5;      // lid total height in print orientation
lid_ro  = 37.5;
skirt_ri = 35.6;     // 0.6 radial clearance over neck_ro=35.0
lid_t   = 2.5;       // lid top disc thickness
lug_w   = 6.0;       // tangential
lug_h   = 4.0;       // axial, 0.6 clearance top/bottom in slot
lug_tip_r = 33.9;    // 0.3 clearance to slot floor 33.6
lug_cz_print = 14.0; // lid print z of lug centre -> 71 in assembly
asm_top = 85.0;      // jar rim 82.5 + lid disc 2.5

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- Jar ----
module jar_body() {
    rotate_extrude()
    polygon(points=[
        [0,0],[33.5,0],[37.5,4],[37.5,shoulder_z],
        [neck_ro,62.5],[neck_ro,81.3],[33.8,jar_h],[neck_ri,jar_h],
        [neck_ri,64.0],[R_in,61.0],[R_in,6.5],[31.0,floor_t],[0,floor_t]
    ]);
}

module wedge_sector(z0,h) {
    translate([0,0,z0])
    linear_extrude(height=h)
    polygon(points=concat([[0,0]],
        [for(a=[-6:3:97]) 40*[cos(a),sin(a)]]));
}

module slot_cut_one() {
    union() {
        // vertical entry, open through rim
        translate([35.05,0,75.7]) cube([2.9,entry_w,14.6],center=true);
        // horizontal circumferential run
        intersection() {
            difference() {
                translate([0,0,slot_z-slot_h/2]) cylinder(h=slot_h,r=36.5);
                translate([0,0,slot_z-slot_h/2-0.1]) cylinder(h=slot_h+0.2,r=slot_floor_r);
            }
            wedge_sector(slot_z-slot_h/2, slot_h);
        }
    }
}

module bump_one() {
    // Detent bump: vertical pin segment standing out of groove floor.
    // At 78 deg, centred radially on the groove floor.
    translate([slot_floor_r*cos(78), slot_floor_r*sin(78), slot_z])
        cylinder(h=slot_h, r=1.0, center=true);
}

module jar() {
    union() {
        difference() {
            jar_body();
            slot_cut_one();
            rotate([0,0,180]) slot_cut_one();
        }
        bump_one();
        rotate([0,0,180]) bump_one();
    }
}

// ---- Lid ----
module lid_body() {
    rotate_extrude()
    polygon(points=[
        [0,0],[34.5,0],[37.5,3],[37.5,19.3],[36.3,lid_h],
        [skirt_ri,lid_h],[skirt_ri,2.9],[32.6,lid_t],[0,lid_t]
    ]);
}

module lug_one() {
    // along +Y, in lid print coordinates
    translate([0,34.75,lug_cz_print]) cube([lug_w,2.0,lug_h],center=true);
}

module lid() {
    union() {
        lid_body();
        lug_one();
        rotate([0,0,180]) lug_one();
    }
}

// ---- Specs and output ----
if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-R_out,-R_out,0],[R_out,R_out,jar_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base", "-z", 3000]]],
        ["overhangs_allowed", [
            ["bayonet slot ceiling, 1.4mm radial groove, PETG bridges this short span",
             [[-36,-36,68],[36,36,74]]]
        ]],
        ["copies", 1],
        ["details", [
            ["main_bore", "void", [[-24,-24,10],[24,24,58]], 0.99],
            ["entry_slot", "void", [[33.7,-3,75],[36.5,3,82.4]], 0.95],
            ["horizontal_slot", "void", [[22,22,69],[26.5,26.5,73]], 0.65],
            ["detent_bump", "material", [[5.5,31.5,69.5],[8.5,34.5,72.5]], 0.35],
            ["side_wall", "thickness", [40,0,30], [-1,0,0], wall],
            ["floor", "thickness", [0,0,-5], [0,0,1], floor_t],
            ["groove_floor_wall", "thickness",
                [40*cos(45),40*sin(45),slot_z], [-cos(45),-sin(45),0], 1.6],
            ["bayonet_slots", "view", [[20,-36,64],[38,36,82.5]]]
        ]]
    ]);
    jar();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-lid_ro,-lid_ro,0],[lid_ro,lid_ro,lid_h]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["top_on_bed", "-z", 3000]]],
        ["overhangs_allowed", [
            ["lug underside, 1.7mm radial lug, PETG bridges this short span",
             [[-4,33,11],[4,36.5,17]]],
            ["lug underside opposite, 1.7mm radial lug, PETG bridges this short span",
             [[-4,-36.5,11],[4,-33,17]]]
        ]],
        ["copies", 1],
        ["details", [
            ["lid_cavity", "void", [[-24,-24,8],[24,24,19]], 0.99],
            ["lug", "material", [[-3,33.5,12],[3,36,16]], 0.65],
            ["lug_opposite", "material", [[-3,-36,12],[3,-33.5,16]], 0.65],
            ["top_disc", "thickness", [0,0,-5], [0,0,1], lid_t],
            ["skirt_wall", "thickness", [40,0,15], [-1,0,0], 1.9],
            ["lug_shape", "view", [[-5,32,10],[5,37,18]]]
        ]]
    ]);
    lid();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-R_out,-R_out,0],[R_out,R_out,asm_top]]],
        ["support_faces", [["desk", "-z", 3000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["lock_turn", ["lid"], "rotate", [0,0,0], [0,0,1], [-90,0],
                ["flex", [["lid","jar",1.0,
                    "PETG skirt/lug flexes out over 0.8mm detent bump in slot"]]]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,1], ["rotate", [0,0,slot_z], [0,0,1], 90]]
        ]]
    ]);
    instance("jar", "jar") jar();
    instance("lid", "lid")
        translate([0,0,asm_top]) rotate([180,0,0]) lid();
}
