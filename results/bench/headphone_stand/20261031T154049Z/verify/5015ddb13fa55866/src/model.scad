// Headphone stand: base, post, hanger. Units mm. Print orientation = export orientation (+Z up).
part = "base"; // [base, post, hanger, assembly]
cadverify_only = "";

/* Parameters */
base_L = 180; base_W = 140; base_H = 14;
base_sock_L = 24.4; base_sock_W = 20.4; base_sock_D = 10; // depth from top
base_floor = base_H - base_sock_D; // 4
base_cham_H = 2; base_cham_extra = 1.5; // per side funnel

post_low_L = 24; post_low_W = 20; post_low_H = 10;
post_shaft_L = 34; post_shaft_W = 28; post_shaft_H = 220;
post_up_L = 20; post_up_W = 16; post_up_H = 12;
post_up_cham_H = 1.5; post_up_cham_extra = 1.5; // per side taper at top
post_H = post_low_H + post_shaft_H + post_up_H; // 242

hanger_L = 120; hanger_W = 36; hanger_base_H = 14; hanger_R = 18; // half-cyl radius = W/2
hanger_cyl_H = 18; // peak 14+18=32
lip_L = 10; lip_W = 36; lip_bot = 24; lip_top = 36; // lips 24..36, protrude 4 above peak
hanger_H = 36;
hanger_sock_L = 20.4; hanger_sock_W = 16.4; hanger_sock_D = 12; // straight depth from bottom
hanger_roof_H = 10; // triangular roof above straight, ridge along X
hanger_cham_H = 2; hanger_cham_extra = 1.5;

asm_post_Z = base_floor; // 4, post bottom in assembly
asm_hanger_Z = 234; // hanger bottom in assembly (shaft top)
// checks: shaft top = asm_post_Z+post_low_H+post_shaft_H = 4+10+220=234 ok
// post top = 4+242=246 = hanger straight top (234+12) ok
// hanger top = 234+36=270 ok

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module base_part() {
    difference() {
        // plate
        translate([-base_L/2, -base_W/2, 0]) cube([base_L, base_W, base_H]);
        // straight socket
        translate([-base_sock_L/2, -base_sock_W/2, base_floor])
            cube([base_sock_L, base_sock_W, base_sock_D+0.01]);
        // entry funnel (frustum): bottom rect sock, top rect enlarged
        hull() {
            translate([-base_sock_L/2, -base_sock_W/2, base_H-base_cham_H])
                cube([base_sock_L, base_sock_W, 0.01]);
            translate([-(base_sock_L/2+base_cham_extra), -(base_sock_W/2+base_cham_extra), base_H-0.01])
                cube([base_sock_L+2*base_cham_extra, base_sock_W+2*base_cham_extra, 0.01]);
        }
    }
}

module post_part() {
    // lower tenon
    translate([-post_low_L/2, -post_low_W/2, 0]) cube([post_low_L, post_low_W, post_low_H]);
    // shaft
    translate([-post_shaft_L/2, -post_shaft_W/2, post_low_H])
        cube([post_shaft_L, post_shaft_W, post_shaft_H]);
    // upper tenon straight
    translate([-post_up_L/2, -post_up_W/2, post_low_H+post_shaft_H])
        cube([post_up_L, post_up_W, post_up_H-post_up_cham_H]);
    // upper tenon top chamfer frustum
    hull() {
        translate([-post_up_L/2, -post_up_W/2, post_low_H+post_shaft_H+post_up_H-post_up_cham_H-0.01])
            cube([post_up_L, post_up_W, 0.01]);
        translate([-(post_up_L/2-post_up_cham_extra), -(post_up_W/2-post_up_cham_extra), post_H-0.01])
            cube([post_up_L-2*post_up_cham_extra, post_up_W-2*post_up_cham_extra, 0.01]);
    }
}

module hanger_part() {
    difference() {
        union() {
            // base box
            translate([-hanger_L/2, -hanger_W/2, 0]) cube([hanger_L, hanger_W, hanger_base_H]);
            // top half-cylinder (only z>=base_H part)
            intersection() {
                translate([0, 0, hanger_base_H]) rotate([0, 90, 0])
                    cylinder(r=hanger_R, h=hanger_L, center=true, $fn=96);
                translate([-hanger_L/2, -hanger_W/2, hanger_base_H]) cube([hanger_L, hanger_W, hanger_cyl_H]);
            }
            // end lips
            for (sx=[-1,1])
                translate([sx*(hanger_L/2-lip_L), -lip_W/2, lip_bot])
                    cube([lip_L, lip_W, lip_top-lip_bot]);
        }
        // straight socket
        translate([-hanger_sock_L/2, -hanger_sock_W/2, 0])
            cube([hanger_sock_L, hanger_sock_W, hanger_sock_D]);
        // entry funnel at mouth (bottom)
        hull() {
            translate([-hanger_sock_L/2, -hanger_sock_W/2, hanger_cham_H])
                cube([hanger_sock_L, hanger_sock_W, 0.01]);
            translate([-(hanger_sock_L/2+hanger_cham_extra), -(hanger_sock_W/2+hanger_cham_extra), -0.01])
                cube([hanger_sock_L+2*hanger_cham_extra, hanger_sock_W+2*hanger_cham_extra, 0.01]);
        }
        // roof (triangular prism, ridge along X, apex up)
        // cross-section in YZ: base width sock_W at z=sock_D, apex at z=sock_D+roof_H, y=0
        hull() {
            // base edge left/right? Use two thin boxes to form prism via hull of apex line + base rect
            translate([-hanger_sock_L/2, -hanger_sock_W/2, hanger_sock_D-0.01])
                cube([hanger_sock_L, hanger_sock_W, 0.01]);
            translate([-hanger_sock_L/2, -0.01, hanger_sock_D+hanger_roof_H-0.01])
                cube([hanger_sock_L, 0.02, 0.01]);
        }
        // lip top chamfers (bevel top edges 1.5x1.5 at 45deg approx, upward facing only)
        // chamfer by cutting wedges? Instead skip - lips have flat tops, no cut needed.
    }
}

// --- specs (print coords) ---
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-base_L/2, -base_W/2, 0], [base_L/2, base_W/2, base_H]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base_bottom", "-z", 20000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["base_plate", "material", [[50, 40, 0], [80, 60, base_H]], 0.9],
            ["socket", "void", [[-base_sock_L/2, -base_sock_W/2, base_floor], [base_sock_L/2, base_sock_W/2, base_H]], 0.9],
            ["socket_entry", "hole", [0, 0, base_H+6], [0, 0, -1], [[0, base_sock_W+2*base_cham_extra], [base_cham_H, base_sock_W], [base_sock_D, base_sock_W]]],
            ["floor", "thickness", [0, 0, -1], [0, 0, 1], base_floor],
            ["top_face", "view", [[-60, -50, base_H-1], [60, 50, base_H+1]]]
        ]]
    ]);
    base_part();
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-post_shaft_L/2, -post_shaft_W/2, 0], [post_shaft_L/2, post_shaft_W/2, post_H]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["post_bottom", "-z", 400]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-10, -8, post_low_H+50], [10, 8, post_low_H+150]], 0.9],
            ["lower_tenon", "material", [[-post_low_L/2, -post_low_W/2, 0], [post_low_L/2, post_low_W/2, post_low_H]], 0.9],
            ["upper_tenon", "material", [[-post_up_L/2, -post_up_W/2, post_low_H+post_shaft_H], [post_up_L/2, post_up_W/2, post_H]], 0.9],
            ["shaft_wall", "thickness", [30, 0, post_low_H+100], [-1, 0, 0], post_shaft_L],
            ["tenon_tip", "view", [[-post_up_L/2, -post_up_W/2, post_H-4], [post_up_L/2, post_up_W/2, post_H+1]]]
        ]]
    ]);
    post_part();
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-hanger_L/2, -hanger_W/2, 0], [hanger_L/2, hanger_W/2, hanger_H]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["hanger_bottom", "-z", 3000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["saddle", "material", [[-40, -10, 10], [40, 10, 30]], 0.9],
            ["end_stop", "material", [[hanger_L/2-lip_L, -lip_W/2, lip_bot], [hanger_L/2, lip_W/2, lip_top]], 0.9],
            ["socket", "void", [[-hanger_sock_L/2, -hanger_sock_W/2, 0], [hanger_sock_L/2, hanger_sock_W/2, hanger_sock_D]], 0.9],
            ["socket_entry", "hole", [0, 0, -6], [0, 0, 1], [[0, hanger_sock_W+2*hanger_cham_extra], [hanger_cham_H, hanger_sock_W], [hanger_sock_D, hanger_sock_W]]],
            ["top_skin", "thickness", [0, 0, hanger_H+4], [0, 0, -1], hanger_H-(hanger_sock_D+hanger_roof_H)]],
            ["round_top", "view", [[-40, -hanger_W/2, hanger_base_H], [40, hanger_W/2, hanger_base_H+hanger_cyl_H+1]]]
        ]]
    ]);
    hanger_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-base_L/2, -base_W/2, 0], [base_L/2, base_W/2, asm_hanger_Z+hanger_H]]],
        ["support_faces", [["desk", "-z", 20000]]],
        ["allowed_interferences", []],
        ["motions", []],
        ["assembly_order", [
            [[ "base_inst" ], [0, 0, 0]],
            [[ "post_inst" ], [0, 0, -1]],
            [[ "hanger_inst" ], [0, 0, -1]]
        ]],
        ["overhangs_allowed", []]
    ]);
    instance("base_inst", "base") base_part();
    instance("post_inst", "post") translate([0, 0, asm_post_Z]) post_part();
    instance("hanger_inst", "hanger") translate([0, 0, asm_hanger_Z]) hanger_part();
}
