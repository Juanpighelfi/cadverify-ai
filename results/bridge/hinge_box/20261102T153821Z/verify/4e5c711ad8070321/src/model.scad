// Box with print-in-place hinge - params + box
part = "box";

W = 80; D = 60; Hbox = 30; Hlid = 10; wall = 2.4; floor_t = 2.4;
lid_t = 2.4; skirt_h = 7.6;
pin_r = 2.0; pin_clear = 0.35; knuckle_r = 4.0;
hinge_y = -D/2; hinge_z = 20;
n_knuckle = 5;

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

module box_part() {
    difference() {
        cube([W, D, Hbox]);
        translate([wall, wall, floor_t])
            cube([W-2*wall, D-2*wall, Hbox]);
    }
}

if (part == "box") box_part();
