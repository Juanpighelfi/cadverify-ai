/* Jar with screw-on lid - PETG, 0.4mm nozzle, support-free 45deg thread
   Inside ~60mm across, ~70mm deep. Pitch 6mm, 1.5 turns = 9mm travel.
*/

// Customizer part selector
part = "assembly"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
jar_inner_d = 60;
jar_inner_r = 60/2;
jar_inner_depth = 70;
wall_t = 2.4;
floor_t = 3.0;
R_out = 30 + 2.4; // 32.4
jar_H = 3.0 + 70; // 73

pitch = 6;
thread_h = 1.0;
thread_w_root = 3.6;
thread_w_tip = 2.0;
thread_k = (3.6-2.0)/2/1.0; // 0.8, flank ~38.7 deg from vertical
clear_radial = 0.4;

R_tip_m = 32.4 + 1.0; // 33.4
R_root_f = 33.4 + 0.4; // 33.8
R_tip_f = 32.4 + 0.4; // 32.8
R_lid_out = 33.8 + 2.4; // 36.2

lid_top_t = 3.0;
lid_inside_h = 18;
lid_H = 3.0 + 18; // 21

// thread spans (centers)
male_z0 = 55;
male_turns = 2;
female_z0_print = 6;
female_turns = 2;

thread_steps = 240;

module helical_thread(R_low, w_low, R_high, w_high, pitch, phi_start_deg, phi_end_deg, z_at_start, steps) {
    // NOTE: OpenSCAD sin()/cos() take degrees; helix rises pitch per 360 deg (right-hand)
    N = steps;
    pts = [ for(i=[0:N])
        let(
            phi = phi_start_deg + (phi_end_deg-phi_start_deg)*i/N,
            zc = z_at_start + pitch*(phi-phi_start_deg)/360,
            c = cos(phi), s = sin(phi)
        )
        each [
            [R_low*c, R_low*s, zc - w_low/2],
            [R_low*c, R_low*s, zc + w_low/2],
            [R_high*c, R_high*s, zc + w_high/2],
            [R_high*c, R_high*s, zc - w_high/2]
        ]
    ];
    faces = concat(
        [ for(i=[0:N-1]) [i*4+0, i*4+1, (i+1)*4+1] ],
        [ for(i=[0:N-1]) [i*4+0, (i+1)*4+1, (i+1)*4+0] ],
        [ for(i=[0:N-1]) [i*4+3, (i+1)*4+3, (i+1)*4+2] ],
        [ for(i=[0:N-1]) [i*4+3, (i+1)*4+2, i*4+2] ],
        [ for(i=[0:N-1]) [i*4+0, (i+1)*4+0, (i+1)*4+3] ],
        [ for(i=[0:N-1]) [i*4+0, (i+1)*4+3, i*4+3] ],
        [ for(i=[0:N-1]) [i*4+1, i*4+2, (i+1)*4+2] ],
        [ for(i=[0:N-1]) [i*4+1, (i+1)*4+2, (i+1)*4+1] ],
        [[0,3,2],[0,2,1]],
        [[N*4+0, N*4+1, N*4+2],[N*4+0, N*4+2, N*4+3]]
    );
    polyhedron(points=pts, faces=faces, convexity=10);
}

module jar_geom() {
    // base body
    difference() {
        cylinder(r=R_out, h=jar_H, $fn=180);
        translate([0,0,floor_t]) cylinder(r=jar_inner_r, h=jar_inner_depth+2, $fn=180);
    }
    // external thread, embedded 0.2 into wall
    // R_low=32.2 (embedded), w_low=3.92, R_high=33.4, w_high=2.0
    helical_thread(32.2, 3.92, 33.4, 2.0, pitch, 0, 720, male_z0, thread_steps);
}

module lid_geom() {
    // outer solid minus bore
    difference() {
        cylinder(r=R_lid_out, h=lid_H, $fn=180);
        translate([0,0,lid_top_t]) cylinder(r=R_root_f, h=lid_inside_h+2, $fn=180);
    }
    // internal thread, embedded 0.2 outward
    // R_low=32.8 (tip, exposed), w_low=2.0, R_high=34.0 (embedded), w_high=3.92
    helical_thread(32.8, 2.0, 34.0, 3.92, pitch, 0, 720, female_z0_print, thread_steps);
}

module jar() {
    jar_geom();
}

module lid() {
    lid_geom();
}

module assembly() {
    instance("jar", "jar") jar();
    // lid printed opening-up (0..21, sealing at 3), assembled flipped: z_asm = 76 - z_print
    instance("lid", "lid") translate([0,0,76]) rotate([180,0,0]) lid();
}

// ---------- specs ----------
if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-33.4,-33.4,0],[33.4,33.4,73]]],
    ]);
    jar();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-36.2,-36.2,0],[36.2,36.2,21]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base","-z",2000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [42,0,20.5], [-1,0,0], 2.4],
            ["top", "thickness", [0,0,-1], [0,0,1], 3.0],
            ["bore", "void", [[-20,-20,5],[20,20,19]], 0.95],
            ["thread_view", "view", [[-34,-34,4],[34,34,20]]]
        ]]
    ]);
    lid();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-36.2,-36.2,0],[36.2,36.2,76]]],
        ["support_faces", [["base","-z",2000]]],
        ["motions", [
            ["lid_open", ["lid"], "screw", [0,0,0], [0,0,1], 6, [0,540]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,-1], ["screw", [0,0,0], [0,0,1], 6, 540]]
        ]],
        ["held", ["lid"]]
    ]);
    assembly();
}
