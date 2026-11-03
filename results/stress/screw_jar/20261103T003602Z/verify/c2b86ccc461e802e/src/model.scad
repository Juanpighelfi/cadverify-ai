/* Jar with screw-on lid - PETG, 0.4mm nozzle, support-free thread
   Inside ~60mm across, ~70mm deep. Pitch 6mm, 1.5 turns = 9mm travel.
   Trapezoid thread flanks ~39 deg from horizontal plane normal... self-supporting.
*/

part = "assembly"; // [jar, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
jar_inner_r = 30;
jar_inner_depth = 70;
wall_t = 2.4;
floor_t = 3.0;
R_out = 32.4;
jar_H = 73;

pitch = 6;
thread_steps = 240;

male_z0 = 60;
male_turns = 1;
female_z0_print = 7;

R_root_f = 33.8;
R_tip_f = 32.8;
R_lid_out = 36.2;
lid_top_t = 3.0;
lid_inside_h = 18;
lid_H = 21;

module helical_thread(R_low, w_low, R_high, w_high, pitch, phi_start_deg, phi_end_deg, z_at_start, steps, handed=1) {
    // OpenSCAD sin()/cos() take degrees; right-hand: z rises pitch per 360 deg
    N = steps;
    pts = [ for(i=[0:N])
        let(
            phi = phi_start_deg + (phi_end_deg-phi_start_deg)*i/N,
            zc = z_at_start + handed*pitch*(phi-phi_start_deg)/360,
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
    difference() {
        cylinder(r=R_out, h=jar_H, $fn=180);
        translate([0,0,floor_t]) cylinder(r=jar_inner_r, h=jar_inner_depth+2, $fn=180);
    }
    helical_thread(32.2, 3.0, 33.4, 1.6, pitch, 0, 540, male_z0, thread_steps);
}

module lid_geom() {
    difference() {
        cylinder(r=R_lid_out, h=lid_H, $fn=180);
        translate([0,0,lid_top_t]) cylinder(r=R_root_f, h=lid_inside_h+2, $fn=180);
    }
    helical_thread(32.8, 1.6, 34.0, 3.0, pitch, 180, 720, female_z0_print, thread_steps);
}

module jar() { jar_geom(); }
module lid() { lid_geom(); }

module assembly() {
    instance("jar", "jar") jar();
    instance("lid", "lid") translate([0,0,76]) rotate([180,0,0]) lid();
}

if (part == "jar") {
    echo(cadverify_spec = [
        ["bounds", [[-33.4,-33.4,0],[33.4,33.4,73]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base","-z",2000]]],
        ["overhangs_allowed", [["support-free thread flanks", [[-33.6,-33.6,52.5],[33.6,33.6,69.5]]]]],
        ["copies", 1],
        ["details", [
            ["wall", "thickness", [40,0,30], [-1,0,0], 2.4],
            ["floor", "thickness", [0,0,-1], [0,0,1], 3.0],
            ["cavity", "void", [[-21,-21,10],[21,21,65]], 0.95],
            ["mouth", "hole", [0,0,80], [0,0,-1], [[0,60],[60,60]]],
            ["thread_view", "view", [[-34,-34,53],[34,34,69]]]
        ]]
    ]);
    jar();
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-36.2,-36.2,0],[36.2,36.2,21]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["base","-z",2000]]],
        ["overhangs_allowed", [["support-free thread flanks", [[-34,-34,4],[34,34,20]]]]],
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
            ["lid_open", ["lid"], "screw", [0,0,0], [0,0,1], -6, [0,540]]
        ]],
        ["assembly_order", [
            [["jar"], [0,0,0]],
            [["lid"], [0,0,-1], ["screw", [0,0,0], [0,0,1], -6, -540]]
        ]],
        ["held", ["lid"]]
    ]);
    assembly();
}
