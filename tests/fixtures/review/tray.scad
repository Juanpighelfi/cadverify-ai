// A parts tray. defect=true leaves its floor hanging from three tabs.
defect = false;
size = [80, 60, 20];
wall = 2.4;
floor_t = 1.6;
slit = 0.8;
tab = 3;

echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], size]],
    ["bodies", 1],
    ["through_holes", defect ? 3 : 0],
    ["material", "PLA"]
]);

module shell() {
    difference() {
        cube(size);
        translate([wall, wall, floor_t]) cube([size[0] - 2 * wall, size[1] - 2 * wall, size[2]]);
    }
}

module slit_ring() {
    translate([wall, wall, -1]) difference() {
        cube([size[0] - 2 * wall, size[1] - 2 * wall, floor_t + 2]);
        translate([slit, slit, -1])
            cube([size[0] - 2 * wall - 2 * slit, size[1] - 2 * wall - 2 * slit, floor_t + 4]);
    }
}

module tabs() {
    translate([size[0] / 2 - tab / 2, wall - 0.5, 0]) cube([tab, slit + 1, floor_t]);
    translate([wall - 0.5, size[1] * 0.75, 0]) cube([slit + 1, tab, floor_t]);
    translate([size[0] - wall - slit - 0.5, size[1] * 0.25, 0]) cube([slit + 1, tab, floor_t]);
}

if (defect) {
    difference() {
        shell();
        slit_ring();
    }
    tabs();
} else {
    shell();
}
