// Weekly pill box with a turning lid
// Two printed parts: base (7 compartments) and lid (one wedge opening).
// Lid clicks at 7 detent positions (360/7 deg), is retained by snap lips
// running in an annular groove on the base, and cannot lift off.
//
// Dimensions (mm):
//   overall assembled: 90 diameter x 25 high
//   base: max radius 43 (bead), top z=22, floor 2.0, outer wall 1.3,
//         dividers 1.6, compartment depth 20
//   lid (in use): top z=25, ceiling z=22.4, skirt OD 90 / ID 86.8,
//         plate 2.6, skirt down to z=9.8
// Detent: one bump on a flexible skirt tab (tip r=42.1, z centre 12.2)
//         engages 7 notches (floor r=41.9) in the base detent band r=42.5.
//         Between notches the bump overlaps the band by 0.4 (flex).
// Retention: 7 lips (tip r=42.2) on slit skirt tabs sit in the base
//         groove (r=41.7); to assemble they snap over the bead (r=43.0),
//         an 0.8 radial interference taken by tab flex.

part = "assembly"; // [assembly, base, lid]

$fn = 128;

step = 360 / 7;

// --- base dimensions ---
base_top = 22;
bead_r = 43.0;
lid_r = 45.0;

// --- lid dimensions (use orientation) ---
lid_top = 25;
lid_ceiling = 22.4;
lid_skirt_bottom = 9.8;
detent_rests = [for (i = [0:7]) i * step];

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- helpers ----------
module sector_prism(r, a0, a1, z0, h) {
    translate([0, 0, z0])
        linear_extrude(height = h)
            polygon(points = concat([[0, 0]],
                [for (a = [a0:3:a1]) [r * cos(a), r * sin(a)]]));
}

module annular_sector(rin, rout, a0, a1, z0, h) {
    translate([0, 0, z0])
        linear_extrude(height = h)
            polygon(points = concat(
                [for (a = [a0:2:a1]) [rout * cos(a), rout * sin(a)]],
                [for (a = [a1:-2:a0]) [rin * cos(a), rin * sin(a)]]));
}

// ---------- base ----------
module notch_cut() {
    // Hexagonal (in vertical/tangential plane) recess, extruded radially.
    // Floor at x=41.85, opens through the r=42.5 detent band. The hex cut
    // sweeps ~+/-2.2 deg of arc at the notch floor, which would hide the
    // rising detent bump near each rest; the wider hex recess below is the
    // notch (cut deeper into the band surface, +/-8 deg), and the hex cut
    // alone forms the deep centre the bump tip drops into.
    for (i = [0:6])
        rotate([0, 0, i * step]) {
            annular_sector(41.9, 42.8, -8, 8, 11.1, 2.2);
            translate([41.85, 0, 12.2])
                rotate([0, 90, 0])
                    linear_extrude(height = 2.6)
                        polygon(points = [
                            [0.9, -1.6], [0.9, 1.6], [0, 2.6],
                            [-0.9, 1.6], [-0.9, -1.6], [0, -2.6]]);
        }
}

module base_part() {
    difference() {
        union() {
            // Floor + outer wall with groove / bead / detent-band profile.
            rotate_extrude()
                polygon(points = [
                    [0, 0], [42.5, 0], [42.5, 12.8], [41.7, 13.8],
                    [41.7, 15.2], [43.0, 16.9], [43.0, 18.1],
                    [42.5, 18.9], [42.5, 21.6], [41.8, 22.0],
                    [41.2, 22.0], [41.2, 2.0], [0, 2.0]]);
            // Central hub.
            translate([0, 0, 2]) cylinder(r = 6.5, h = 19.6);
            // Seven radial dividers (at compartment boundaries).
            for (i = [0:6])
                rotate([0, 0, (i + 0.5) * step])
                    translate([0, -0.8, 2]) cube([41.2, 1.6, 19.6]);
            // Day pips on each compartment floor: 1..7 raised dots.
            for (i = [0:6])
                for (j = [0:i])
                    rotate([0, 0, i * step + (j - i / 2) * 5])
                        translate([25, 0, 2]) cylinder(r = 1.1, h = 0.6);
        }
        notch_cut();
    }
}

// ---------- lid, in use orientation (z = assembly z) ----------
module lid_use() {
    difference() {
        union() {
            // Top plate.
            translate([0, 0, lid_ceiling]) cylinder(r = lid_r, h = lid_top - lid_ceiling);
            // Skirt tube.
            translate([0, 0, lid_skirt_bottom])
                difference() {
                    cylinder(r = lid_r, h = lid_ceiling - lid_skirt_bottom);
                    translate([0, 0, -0.1]) cylinder(r = 43.4, h = lid_ceiling - lid_skirt_bottom + 0.2);
                }
            // Retention lips on the 7 tabs: tip band + 39 deg release slope.
            for (i = [0:6])
                rotate([0, 0, i * step])
                    intersection() {
                        difference() {
                            translate([0, 0, 13.9]) cylinder(r = 43.5, h = 2.5);
                            union() {
                                translate([0, 0, 13.8]) cylinder(r = 42.2, h = 1.1);
                                translate([0, 0, 14.9]) cylinder(r1 = 42.2, r2 = 43.45, h = 1.5);
                            }
                        }
                        sector_prism(46, -19, 19, 13.8, 2.7);
                    }
            // Detent bump on tab 0: hull gives tangential + vertical ramps.
            hull() {
                translate([42.35, 0, 12.2]) cube([0.5, 2.2, 1.2], center = true);
                translate([43.3, 0, 12.2]) cube([1.2, 4.4, 2.6], center = true);
            }
        }
        // The single dispensing opening (wedge) through the plate.
        annular_sector(8.5, 39.5, -17, 17, lid_ceiling - 0.2, lid_top - lid_ceiling + 0.4);
        // Slits between skirt tabs (tabs flex for snap + detent).
        for (i = [0:6])
            rotate([0, 0, (i + 0.5) * step])
                translate([42.7, -0.8, 9.7]) cube([3.0, 1.6, 10.9]);
        // Shallow grip flutes on the upper (anchor) ring of the skirt.
        for (i = [0:13])
            rotate([0, 0, i * 360 / 14])
                hull() {
                    translate([44.9, -1.3, 23.4]) cube([0.7, 2.6, 0.3]);
                    translate([44.3, -1.3, 20.85]) cube([1.3, 2.6, 0.3]);
                }
    }
}

// Lid in print orientation: plate on the bed, skirt up.
module lid_printed() {
    rotate([180, 0, 0]) translate([0, 0, -lid_top]) lid_use();
}

// ---------- verified specifications ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-43, -43, 0], [43, 43, 22]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["print_bed", "-z", 5000]]],
        ["overhangs_allowed", [
            ["detent notch ceilings, 0.65 deep recesses bridging from the band surface", [[-43.5, -43.5, 10.9], [43.5, 43.5, 13.5]]]
        ]],
        ["copies", 1],
        ["details", [
            ["floor", "thickness", [20, 0, -1], [0, 0, 1], 2.0],
            ["outer_wall", "thickness", [48, 0, 10], [-1, 0, 0], 1.3],
            ["compartment", "void", [[15, -8, 5], [37, 8, 20]], 0.88],
            ["hub", "material", [[-5, -5, 5], [5, 5, 20]], 0.9],
            ["detent_notch", "void", [[42.0, -1.5, 11.7], [42.6, 1.5, 12.7]], 0.85],
            ["retention_groove", "void", [[41.9, -4, 13.9], [42.5, 4, 15.0]], 0.95],
            ["snap_bead", "material", [[42.2, -4, 17.0], [42.9, 4, 18.0]], 0.7],
            ["day_pip_1", "material", [[23.9, -1.1, 2.0], [26.1, 1.1, 2.6]], 0.7],
            ["detent_notches", "view", [[40, -6, 10.5], [44, 6, 14]]]
        ]]
    ]);
} else if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 15.2]]],
        ["bodies", 1],
        ["through_holes", 1],
        ["support_faces", [["print_bed", "-z", 5000]]],
        ["overhangs_allowed", [
            ["detent bump underside ramp in print orientation, 1.3 wide bridging from the tab", [[41.5, -3.5, 11.3], [44.5, 3.5, 14.3]]],
            ["retention lip release slopes in print orientation, 1.2 wide bridging from the skirt", [[-44.5, -44.5, 8.4], [44.5, 44.5, 11.3]]]
        ]],
        ["copies", 1],
        ["details", [
            ["top_plate", "thickness", [0, 0, -1], [0, 0, 1], 2.6],
            ["skirt_wall", "thickness", [48, 0, 5], [-1, 0, 0], 1.6],
            ["opening", "void", [[18, -5, 0], [36, 5, 2.6]], 0.95],
            ["retention_lip", "material", [[42.4, -1.5, 10.2], [43.2, 1.5, 11.0]], 0.9],
            ["detent_bump", "material", [[42.3, -1.0, 12.2], [43.2, 1.0, 13.4]], 0.5],
            ["grip_flute", "view", [[43.5, -2.0, 1.5], [45.2, 2.0, 4.6]]],
            ["tab_slit", "view", [[37, -22, 4], [42, -17, 15.2]]],
            ["opening_wedge", "view", [[8, -20, 0], [40, 20, 2.6]]]
        ]]
    ]);
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-45, -45, 0], [45, 45, 25]]],
        ["support_faces", [["table", "-z", 5000]]],
        ["motions", [
            ["lid_turn", ["lid_main"], "rotate", [0, 0, 0], [0, 0, 1], [0, 360],
                ["flex", [["lid_main", "base_main", 0.5, "detent bump rides over the r42.5 band between notches, tab flexes outward"]]],
                ["rests", detent_rests]]
        ]],
        ["assembly_order", [
            [["base_main"], [0, 0, 0]],
            [["lid_main"], [0, 0, -1],
                ["flex", [["lid_main", "base_main", 0.9, "retention lips and detent bump snap over the r43 bead, skirt tabs flex outward"]]]]
        ]],
        ["held", ["lid_main"]]
    ]);
}

// ---------- output ----------
if (part == "base") {
    base_part();
} else if (part == "lid") {
    lid_printed();
} else if (part == "assembly") {
    instance("base_main", "base") base_part();
    instance("lid_main", "lid") translate([0, 0, lid_top]) rotate([180, 0, 0]) lid_printed();
} else {
    assert(false, "unknown part");
}
