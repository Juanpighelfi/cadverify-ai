// Headphone stand: base, post, hanger. Units mm. Print orientation = export orientation (+Z up).
part = "base"; // [base, post, hanger, assembly]
cadverify_only = "";

/* Parameters */
base_L = 180; base_W = 140; base_H = 14;
base_sock_L = 24.4; base_sock_W = 20.4; base_sock_D = 10; // depth from top
base_floor = base_H - base_sock_D; // 4
base_cham_H = 2; base_cham_extra = 1.5; // per side funnel

post_low_L = 24; post_low_W = 20; post_low_H = 10;
post_flare_H = 6;
post_shaft_L = 34; post_shaft_W = 28;
post_shaft_bot = post_low_H + post_flare_H; // 16
post_shaft_top = 230;
post_shaft_H = post_shaft_top - post_shaft_bot; // 214
post_up_L = 20; post_up_W = 16; post_up_H = 12;
post_up_cham_H = 1.5; post_up_cham_extra = 1.5; // per side taper at top
post_H = post_shaft_top + post_up_H; // 242

hanger_L = 120; hanger_W = 36; hanger_base_H = 14; hanger_R = 18; // half-cyl radius = W/2
hanger_cyl_H = 18; // cylinder peak 14+18=32
lip_L = 10; lip_W = 36; lip_bot = 14; lip_top = 36; // end stops 14..36
hanger_H = 36;
hanger_sock_L = 20.4; hanger_sock_W = 16.4; hanger_sock_D = 12; // straight depth from bottom
hanger_roof_H = 10; // triangular roof above straight, ridge along X
hanger_cham_H = 2; hanger_cham_extra = 1.5;

asm_post_Z = base_floor; // 4, post bottom in assembly
asm_hanger_Z = 234; // hanger bottom in assembly
// shaft top 230 + post bottom 4 = 234 = hanger bottom; tenon 230..242 -> hanger 0..12; hanger top 234+36=270

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module base_part() {
    difference() {
        translate([-base_L/2, -base_W/2, 0]) cube([base_L, base_W, base_H]);
        // straight socket
        translate([-base_sock_L/2, -base_sock_W/2, base_floor])
            cube([base_sock_L, base_sock_W, base_sock_D+0.01]);
        // entry funnel (frustum widening upward)
        hull() {
            translate([-base_sock_L/2, -base_sock_W/2, base_H-base_cham_H])
                cube([base_sock_L, base_sock_W, 0.01]);
            translate([-(base_sock_L/2+base_cham_extra), -(base_sock_W/2+base_cham_extra), base_H-0.01])
                cube([base_sock_L+2*base_cham_extra, base_sock_W+2*base_cham_extra, 0.01]);
        }
    }
}

module post_part() {
    // lower tenon (press fit into base)
    translate([-post_low_L/2, -post_low_W/2, 0]) cube([post_low_L, post_low_W, post_low_H]);
    // flare collar 45deg-compatible transition to shaft
    hull() {
        translate([-post_low_L/2, -post_low_W/2, post_low_H-0.01])
            cube([post_low_L, post_low_W, 0.01]);
        translate([-post_shaft_L/2, -post_shaft_W/2, post_shaft_bot-0.01])
            cube([post_shaft_L, post_shaft_W, 0.01]);
    }
    // shaft
    translate([-post_shaft_L/2, -post_shaft_W/2, post_shaft_bot])
        cube([post_shaft_L, post_shaft_W, post_shaft_H]);
    // upper tenon straight part
    translate([-post_up_L/2, -post_up_W/2, post_shaft_top])
        cube([post_up_L, post_up_W, post_up_H-post_up_cham_H]);
    // upper tenon lead chamfer (tapers inward going up)
    hull() {
        translate([-post_up_L/2, -post_up_W/2, post_H-post_up_cham_H-0.01])
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
            // rounded top: half cylinder along X
            intersection() {
                translate([0, 0, hanger_base_H]) rotate([0, 90, 0])
                    cylinder(r=hanger_R, h=hanger_L, center=true, $fn=128);
                translate([-hanger_L/2, -hanger_W/2, hanger_base_H]) cube([hanger_L, hanger_W, hanger_cyl_H]);
            }
            // end stops (full height from base top, no floating ledge)
            for (sx=[-1,1])
                translate([sx*(hanger_L/2-lip_L), -lip_W/2, lip_bot])
                    cube([lip_L, lip_W, lip_top-lip_bot]);
        }
        // straight socket
        translate([-hanger_sock_L/2, -hanger_sock_W/2, 0])
            cube([hanger_sock_L, hanger_sock_W, hanger_sock_D]);
        // entry funnel at mouth (widens downward)
        hull() {
            translate([-hanger_sock_L/2, -hanger_sock_W/2, hanger_cham_H])
                cube([hanger_sock_L, hanger_sock_W, 0.01]);
            translate([-(hanger_sock_L/2+hanger_cham_extra), -(hanger_sock_W/2+hanger_cham_extra), -0.01])
                cube([hanger_sock_L+2*hanger_cham_extra, hanger_sock_W+2*hanger_cham_extra, 0.01]);
        }
        // pointed roof above straight (ridge along X), self-supporting slopes
        // closed wedge: sharp apex edge, no flat -> no overhang patch
        polyhedron(
            points = [
                [-hanger_sock_L/2, -hanger_sock_W/2, hanger_sock_D],
                [ hanger_sock_L/2, -hanger_sock_W/2, hanger_sock_D],
                [ hanger_sock_L/2,  hanger_sock_W/2, hanger_sock_D],
                [-hanger_sock_L/2,  hanger_sock_W/2, hanger_sock_D],
                [-hanger_sock_L/2, 0, hanger_sock_D+hanger_roof_H],
                [ hanger_sock_L/2, 0, hanger_sock_D+hanger_roof_H]
            ],
            faces = [
                [0, 3, 2, 1],
                [0, 1, 5, 4],
                [2, 3, 4, 5],
                [0, 4, 3],
                [1, 2, 5]
            ]
        );
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
            ["socket_funnel", "void", [[-(base_sock_L/2+base_cham_extra), -(base_sock_W/2+base_cham_extra), base_H-base_cham_H], [base_sock_L/2+base_cham_extra, base_sock_W/2+base_cham_extra, base_H]], 0.7],
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
            ["shaft", "material", [[-10, -8, 60], [10, 8, 160]], 0.9],
            ["lower_tenon", "material", [[-post_low_L/2, -post_low_W/2, 0], [post_low_L/2, post_low_W/2, post_low_H]], 0.9],
            ["upper_tenon", "material", [[-post_up_L/2, -post_up_W/2, post_shaft_top], [post_up_L/2, post_up_W/2, post_H]], 0.8],
            ["collar", "material", [[-14, -12, post_low_H], [14, 12, post_shaft_bot]], 0.7],
            ["shaft_wall", "thickness", [30, 0, 116], [-1, 0, 0], post_shaft_L],
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
            ["saddle", "material", [[-40, -8, 20], [40, 8, 26]], 0.9],
            ["end_stop", "material", [[hanger_L/2-lip_L, -lip_W/2, lip_bot], [hanger_L/2, lip_W/2, lip_top]], 0.9],
            ["socket", "void", [[-hanger_sock_L/2, -hanger_sock_W/2, 0], [hanger_sock_L/2, hanger_sock_W/2, hanger_sock_D]], 0.9],
            ["socket_funnel", "void", [[-(hanger_sock_L/2+hanger_cham_extra), -(hanger_sock_W/2+hanger_cham_extra), 0], [hanger_sock_L/2+hanger_cham_extra, hanger_sock_W/2+hanger_cham_extra, hanger_cham_H]], 0.7],
            ["top_skin", "thickness", [0, 0, hanger_H+4], [0, 0, -1], (hanger_base_H+hanger_cyl_H)-(hanger_sock_D+hanger_roof_H)],
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
