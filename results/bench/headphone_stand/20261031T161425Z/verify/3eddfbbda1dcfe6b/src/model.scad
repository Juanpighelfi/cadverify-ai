// Headphone stand in three printed parts: base, post, hanger.
// No glue/screws: rectangular tenons (anti-spin) in blind sockets,
// 0.3 mm clearance per side for PLA.
// Part to print or show
part = "assembly"; // [base, post, hanger, assembly]
$fn = 64;

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------------- parameters (mm) ----------------
base_r = 88; base_h = 14; sock_floor = 4;
sock_w = 20.6; sock_cy = 2;            // socket is sock_w square, centre y offset
tenon_w = 20; tenon_h = 20;            // 0.3/side clearance
post_len = 225.6; post_w = 34; post_h = 24;
post_z0 = 4.4;                         // assembled z of post tenon tip
collar_w = 44;

hang_len = 110; hang_w = 42; hang_drop = 14; hang_thk = 12;
boss_w_x = 48; boss_len_y = 44;        // in hanger print coords: x by (print) y
asm_top = 270; asm_boss_bottom = 216;

// ---------------- specs ----------------
if (part == "base") echo(cadverify_spec = [
    ["bounds", [[-base_r, -base_r, 0], [base_r, base_r, base_h]]],
    ["bodies", 1], ["through_holes", 0], ["copies", 1],
    ["support_faces", [["desk", "-z", 18000]]],
    ["overhangs_allowed", []],
    ["details", [
        ["base_plate", "material", [[35, -20, 2], [55, 20, 12]], 0.98],
        ["base_socket", "void", [[-9, -6, 5], [9, 10, 13]], 0.98],
        ["socket_floor", "thickness", [0, sock_cy, 13], [0, 0, -1], sock_floor],
        ["base_rim", "thickness", [70, 0, -1], [0, 0, 1], base_h],
        ["top_groove", "void", [[58, -1.5, 12.8], [62, 1.5, 13.9]], 0.95],
        ["groove_view", "view", [[50, -10, 12], [70, 10, 14.2]]]
    ]]
]);
if (part == "post") echo(cadverify_spec = [
    ["bounds", [[0, -collar_w/2, 0], [post_len, collar_w/2, post_h]]],
    ["bodies", 1], ["through_holes", 0], ["copies", 1],
    ["support_faces", [["bed", "-z", 4500]]],
    ["overhangs_allowed", []],
    ["details", [
        ["shaft", "material", [[50, -14, 2], [150, 14, 22]], 0.98],
        ["bottom_tenon", "material", [[1, -9, 1], [9, 9, 19]], 0.98],
        ["collar", "material", [[11, -20, 2], [17, 20, 22]], 0.98],
        ["top_tenon", "material", [[212.6, -9, 1], [224.6, 9, 19]], 0.98],
        ["shaft_thickness", "thickness", [100, -18, 12], [0, 1, 0], post_w],
        ["tenon_antispin_view", "view", [[-1, -11, -0.5], [11, 11, 21]]]
    ]]
]);
if (part == "hanger") echo(cadverify_spec = [
    ["bounds", [[-55.6, 0, 0], [55.6, 54, hang_w]]],
    ["bodies", 1], ["through_holes", 0], ["copies", 1],
    ["support_faces", [["bed", "-z", 2000]]],
    ["overhangs_allowed", [
        ["socket roof bridges 21 mm across in PLA", [[-11, -1, 32], [11, 16, 34.5]]]
    ]],
    ["details", [
        ["saddle_contact", "material", [[-15, 47, 3], [15, 52, 39]], 0.95],
        ["saddle_thickness", "thickness", [26, 56, 21], [0, -1, 0], 12.34],
        ["boss", "material", [[-22, 2, 2], [22, 20, 6]], 0.95],
        ["hanger_socket", "void", [[-8, 1, 12], [8, 13, 30]], 0.98],
        ["boss_wall", "thickness", [0, 7, 39], [0, 0, -1], 6.7],
        ["saddle_curve", "view", [[-55, 26, 0], [55, 55, 42]]]
    ]]
]);
if (part == "assembly") echo(cadverify_spec = [
    ["bounds", [[-base_r, -base_r, 0], [base_r, base_r, asm_top]]],
    ["support_faces", [["desk", "-z", 18000]]],
    ["allowed_interferences", []],
    ["motions", []],
    ["assembly_order", [
        [["base"], [0, 0, 0]],
        [["post"], [0, 0, -1]],
        [["hanger"], [0, 0, -1]]
    ]]
]);

// ---------------- helpers ----------------
module rounded_rect_2d(w, d, r) {
    hull() for (sx = [-1, 1], sy = [-1, 1])
        translate([sx * (w/2 - r), sy * (d/2 - r)]) circle(r = r);
}
module rbox(center, size, r) {
    translate(center) hull()
        for (sx = [-1, 1], sy = [-1, 1], sz = [-1, 1])
            translate([sx * (size[0]/2 - r), sy * (size[1]/2 - r), sz * (size[2]/2 - r)])
                sphere(r = r, $fn = 24);
}
// post segment along +x, cross-section (y width) x (z height) rounded, bottom flat-ish on bed
module post_seg(x0, x1, w, h, r) {
    hull() for (yy = [-(w/2 - r), w/2 - r], zz = [r, h - r])
        translate([x0, yy, zz]) rotate([0, 90, 0]) cylinder(h = x1 - x0, r = r);
}

// ---------------- base (print: flat on desk side) ----------------
module base() {
    difference() {
        rotate_extrude($fn = 128) polygon(points = [
            [0, 0], [84, 0], [88, 5], [88, 9], [82, base_h], [0, base_h]]);
        // blind rectangular socket for post tenon
        translate([0, sock_cy, sock_floor - 0.1]) linear_extrude(base_h)
            rounded_rect_2d(sock_w, sock_w, 3);
        // shallow decorative groove in the top face
        rotate_extrude($fn = 128) polygon(points = [
            [56, 12.6], [64, 12.6], [62, base_h + 0.2], [58, base_h + 0.2]]);
    }
}

// ---------------- post (print: lying on its back face) ----------------
module post() {
    post_seg(0, 10, tenon_w, tenon_h, 3);              // bottom tenon
    post_seg(10, 18, collar_w, post_h, 4);             // stop collar
    post_seg(18, 211.6, post_w, post_h, 4);            // shaft
    post_seg(211.6, post_len, tenon_w, tenon_h, 3);    // top tenon
}

// ---------------- hanger (print: on its side, -z face on bed) ----------------
// print coords: x = assembled x, y = assembled z-216 (profile), z = assembled width
function saddle_top(x) = 54 - hang_drop * pow(x / 55, 2);
module saddle_slice(x) {
    translate([x + 0.6, 0, 0]) rotate([0, -90, 0])
        linear_extrude(1.2)
            translate([hang_w/2, saddle_top(x) - hang_thk/2])
                rounded_rect_2d(hang_w, hang_thk, 5);
}
module hanger() {
    difference() {
        union() {
            for (i = [0 : 21])
                hull() { saddle_slice(-55 + 5*i); saddle_slice(-50 + 5*i); }
            // socket boss, flat bed face at z=0, flat top at z=38
            linear_extrude(38) translate([0, boss_len_y/2]) rounded_rect_2d(boss_w_x, boss_len_y, 5);
        }
        // blind rectangular socket, opens at y=0, ceiling at y=15.
        // offset in z like the base socket: the assembled post back face
        // ends at z=21 (assembled y), 0.3 mm clear of the boss bed face.
        translate([0, 15, 0.3]) rotate([90, 0, 0]) linear_extrude(17)
            translate([0, 21]) rounded_rect_2d(sock_w, sock_w, 3);
    }
}

// ---------------- dispatch / assembly ----------------
if (part == "base") base();
else if (part == "post") post();
else if (part == "hanger") hanger();
else if (part == "assembly") {
    instance("base", "base") base();
    // print x -> assembled z, print z -> assembled -y (back face flush)
    instance("post", "post")
        translate([0, 12, post_z0]) rotate([0, -90, 0]) rotate([90, 0, 0]) post();
    // print y -> assembled z (up), print z -> assembled +y (back face flush),
    // flipped 180 about z so the socket opening faces down, on the post tenon
    instance("hanger", "hanger")
        translate([0, 21, asm_boss_bottom]) rotate([90, 0, 0]) rotate([0, 0, 180]) hanger();
}
