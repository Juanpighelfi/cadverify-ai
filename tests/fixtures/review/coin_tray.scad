// A coin tray with a scoop in its front wall for the fingers. defect=true stands a fin right
// behind the scoop, where the fingers go.
defect = false;
size = [60, 40, 18];
wall = 2.4;
floor_t = 1.6;
scoop = 24;

echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], size]],
    ["bodies", 1],
    ["through_holes", 0],
    ["material", "PLA"]
]);

difference() {
    cube(size);
    translate([wall, wall, floor_t]) cube([size[0] - 2 * wall, size[1] - 2 * wall, size[2]]);
    // the scoop: an open notch in the front wall, down to the floor
    translate([size[0] / 2 - scoop / 2, -1, floor_t]) cube([scoop, wall + 2, size[2]]);
}
if (defect)
    translate([size[0] / 2 - scoop / 2 - 2, wall + 1.5, 0]) cube([scoop + 4, 1.6, size[2]]);
