// Raspberry Pi 4 case: base + snap lid, board as external block
// Units mm, print orientation: +Z up, parts rest on min Z.

part = "assembly"; // [base, lid, assembly]
cadverify_only = "";

module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
ox = 92; oy = 63; wall_t = 2; floor_t = 2;
base_top = 20;
board_bottom = 7; board_t = 1.4; board_top = board_bottom + board_t;
board_x0 = 3.5; board_y0 = 3.5;
board_sx = 85; board_sy = 56;
standoff_d = 6; standoff_hole = 2.5;
standoff_bot = 2; standoff_top = 7;
lug_w = 10; lug_t = 2; lug_bot = 19.9; lug_top = 23.5;
lid_clear = 0.3; skirt_t = 2;
lid_x0 = -lid_clear - skirt_t; // -2.3
lid_x1 = ox + lid_clear + skirt_t; // 94.3
lid_y0 = -lid_clear - skirt_t;
lid_y1 = oy + lid_clear + skirt_t;
lid_ceiling = 23; lid_top = 25; skirt_bot = 14;
$fn = 64;

// standoff centers in assembly coords
sx1 = 17; sx2 = 75; sy1 = 7; sy2 = 56;

// ---------- base geometry (assembly == print coords) ----------
module base_asm() {
    difference() {
        union() {
            // floor
            cube([ox, oy, floor_t], false);
            // south wall
            translate([0, 0, floor_t-0.1]) cube([ox, wall_t, base_top-floor_t+0.1], false);
            // north wall
            translate([0, oy-wall_t, floor_t-0.1]) cube([ox, wall_t, base_top-floor_t+0.1], false);
            // west wall (between)
            translate([0, wall_t, floor_t-0.1]) cube([wall_t, oy-2*wall_t, base_top-floor_t+0.1], false);
            // east wall (between)
            translate([ox-wall_t, wall_t, floor_t-0.1]) cube([wall_t, oy-2*wall_t, base_top-floor_t+0.1], false);
            // standoffs
            for (sx=[sx1,sx2]) for (sy=[sy1,sy2])
                translate([sx, sy, standoff_bot-0.1]) cylinder(d=standoff_d, h=standoff_top-standoff_bot+0.1);
            // snap lugs on south + north wall tops
            for (lx=[25,67]) {
                translate([lx-lug_w/2, 0, lug_bot]) cube([lug_w, lug_t, lug_top-lug_bot], false);
                translate([lx-lug_w/2, oy-lug_t, lug_bot]) cube([lug_w, lug_t, lug_top-lug_bot], false);
            }
        }
        // south port notches open to top (board drops straight in)
        // usb-c: center ax 18.5, w 9.8, z 7.1 up to top
        translate([13.6, -0.1, 7.1]) cube([9.8, 2.2, 13.1], false);
        // hdmi0: ax 33.5, w 8.8
        translate([29.1, -0.1, 7.1]) cube([8.8, 2.2, 13.1], false);
        // hdmi1: ax 46.5
        translate([42.1, -0.1, 7.1]) cube([8.8, 2.2, 13.1], false);
        // audio: ax 61.5, w 6.8
        translate([58.1, -0.1, 7.1]) cube([6.8, 2.2, 13.1], false);
        // east notches open to top (lower halves)
        // ethernet y 7.1-23.9
        translate([ox-wall_t-0.1, 7.1, 8.0]) cube([wall_t+0.2, 16.8, base_top+0.2-8.0], false);
        // usb1 y 26.1-40.9
        translate([ox-wall_t-0.1, 26.1, 7.1]) cube([wall_t+0.2, 14.8, base_top+0.2-7.1], false);
        // usb2 y 42.1-56.9
        translate([ox-wall_t-0.1, 42.1, 7.1]) cube([wall_t+0.2, 14.8, base_top+0.2-7.1], false);
        // west microSD notch open to top
        translate([-0.1, 25.1, 5.6]) cube([wall_t+0.2, 12.8, base_top+0.2-5.6], false);
        // standoff holes
        for (sx=[sx1,sx2]) for (sy=[sy1,sy2])
            translate([sx, sy, 2.5]) cylinder(d=standoff_hole, h=7.1-2.5);
    }
}

// ---------- lid geometry in ASSEMBLY coords ----------
module lid_asm() {
    difference() {
        union() {
            // top plate
            translate([lid_x0, lid_y0, lid_ceiling]) cube([lid_x1-lid_x0, lid_y1-lid_y0, lid_top-lid_ceiling], false);
            // south skirt
            translate([lid_x0, lid_y0, skirt_bot]) cube([lid_x1-lid_x0, skirt_t, lid_ceiling-skirt_bot+0.1], false);
            // north skirt
            translate([lid_x0, lid_y1-skirt_t, skirt_bot]) cube([lid_x1-lid_x0, skirt_t, lid_ceiling-skirt_bot+0.1], false);
            // west skirt (between)
            translate([lid_x0, lid_y0+skirt_t, skirt_bot]) cube([skirt_t, (lid_y1-lid_y0)-2*skirt_t, lid_ceiling-skirt_bot+0.1], false);
            // east skirt (between)
            translate([lid_x1-skirt_t, lid_y0+skirt_t, skirt_bot]) cube([skirt_t, (lid_y1-lid_y0)-2*skirt_t, lid_ceiling-skirt_bot+0.1], false);
        }
        // sockets for lugs (blind slots in plate underside)
        for (lx=[25,67]) {
            // south: x 19.8-30.2 etc, y 0.2-1.8, z 23-24.5
            translate([lx-5.2, 0.2, lid_ceiling]) cube([10.4, 1.6, 1.5], false);
            translate([lx+5.2-10.4+10.4-10.4, 0, 0]) cube([0.001,0.001,0.001], false); // keep syntax (no-op tiny)
            // north: y 61.2-62.8
            translate([lx-5.2, oy-1.8, lid_ceiling]) cube([10.4, 1.6, 1.5], false);
        }
        // east skirt notches open to bottom (upper halves of ports)
        // ethernet: y 7.1-23.9, z up to 21.8
        translate([lid_x1-skirt_t-0.1, 7.1, skirt_bot-0.1]) cube([skirt_t+0.2, 16.8, 21.8-(skirt_bot-0.1)], false);
        // usb1 up to 22.9
        translate([lid_x1-skirt_t-0.1, 26.1, skirt_bot-0.1]) cube([skirt_t+0.2, 14.8, 22.9-(skirt_bot-0.1)], false);
        // usb2 up to 22.9
        translate([lid_x1-skirt_t-0.1, 42.1, skirt_bot-0.1]) cube([skirt_t+0.2, 14.8, 22.9-(skirt_bot-0.1)], false);
        // vents over CPU: 5 slots 2.5 x 18 through plate
        for (vx=[42.5, 46.0, 49.5, 53.0, 56.5])
            translate([vx-1.25, 22.5, lid_ceiling-0.1]) cube([2.5, 18, (lid_top-lid_ceiling)+0.2], false);
    }
}

// ---------- board (external) in assembly coords ----------
module board_asm() {
    union() {
        // pcb
        translate([board_x0, board_y0, board_bottom]) cube([board_sx, board_sy, board_t], false);
        // SoC
        translate([board_x0+38, board_y0+21, board_top]) cube([14, 14, 1.5], false);
        // GPIO header along north
        translate([board_x0+10, board_y0+45, board_top]) cube([51, 5, 8], false);
        // south ports to base outer Y=0
        // usb-c
        translate([board_x0+15-4.5, 0, 7.5]) cube([9, 5.0, 3.5], false);
        // hdmi0
        translate([board_x0+30-4, 0, 7.5]) cube([8, 5.0, 2.5], false);
        // hdmi1
        translate([board_x0+43-4, 0, 7.5]) cube([8, 5.0, 2.5], false);
        // audio
        translate([board_x0+58-3, 0, 7.5]) cube([6, 5.0, 5.0], false);
        // east ports to lid outer X=94.3
        // ethernet
        translate([board_x0+85-2, board_y0+12-8, 8.4]) cube([94.3-(board_x0+85-2), 16, 13.0], false);
        // usb stacks
        translate([board_x0+85-2, board_y0+30-7, 7.5]) cube([94.3-(board_x0+85-2), 14, 15.0], false);
        translate([board_x0+85-2, board_y0+46-7, 7.5]) cube([94.3-(board_x0+85-2), 14, 15.0], false);
        // west microSD to X=0
        translate([0, board_y0+28-6, 6.0]) cube([5.0, 12, 2.0], false);
    }
}

// ---------- specs ----------
// base spec in print coords (= assembly)
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [92, 63, 23.5]]],
        ["bodies", 1],
        ["support_faces", [["base_bottom", "-z", 5000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["floor", "thickness", [46, 31.5, -1], [0, 0, 1], 2],
            ["south_wall", "thickness", [46, -1, 10], [0, 1, 0], 2],
            ["standoff_hole", "hole", [17, 7, 10], [0, 0, -1], [[0, 2.5], [1, 2.5]]],
            ["usb_c_opening", "void", [[13.6, -0.1, 7.1], [23.4, 2.1, 11.4]], 0.9],
            ["hdmi0_opening", "void", [[29.1, -0.1, 7.1], [37.9, 2.1, 10.4]], 0.9],
            ["audio_opening", "void", [[58.1, -0.1, 7.1], [64.9, 2.1, 12.9]], 0.9],
            ["ethernet_notch", "void", [[89.9, 7.1, 8.0], [92.1, 23.9, 20.0]], 0.9],
            ["snap_lug", "material", [[20, 0, 20], [30, 2, 23.5]], 0.9],
            ["standoff", "material", [[14, 4, 2], [20, 10, 7]], 0.5]
        ]]
    ]);
    base_asm();
}

// lid spec in PRINT coords (flipped: Xp=Xa+2.3, Yp=65.3-Ya, Zp=25-Za)
if (part == "lid") {
    echo(cadverify_spec = [
        ["bounds", [[0, 0, 0], [96.6, 67.6, 11]]],
        ["bodies", 1],
        ["support_faces", [["lid_top", "-z", 6000]]],
        ["copies", 1],
        ["details", [
            ["top_plate", "thickness", [10, 10, -1], [0, 0, 1], 2],
            ["vent_slot", "void", [[43.55, 24.8, -0.1], [46.05, 42.8, 2.1]], 0.9],
            ["socket_south", "void", [[22.1, 63.5, 0.5], [32.5, 65.1, 2.0]], 0.9],
            ["skirt_wall", "material", [[35, 0, 5], [45, 2, 10]], 0.9],
            ["plate_corner", "material", [[0.5, 55, 0], [10, 65, 2]], 0.9]
        ]]
    ]);
    // assembly -> print: rotate 180 about X then translate
    translate([2.3, 65.3, 25]) rotate([180, 0, 0]) lid_asm();
}

if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-2.3, -2.3, 0], [94.3, 65.3, 25]]],
        ["support_faces", [["case_bottom", "-z", 5000]]],
        ["allowed_interferences", [["base", "lid", "lug press fit into sockets"]]],
        ["assembly_order", [
            [["base"], [0, 0, 0]],
            [["board"], [0, 0, 100]],
            [["lid"], [0, 0, 100]]
        ]]
    ]);
    instance("base", "base") base_asm();
    instance("board", "external") board_asm();
    instance("lid", "lid") lid_asm();
}
