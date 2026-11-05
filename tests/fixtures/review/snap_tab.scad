// A flat bracket with a springy arm cut out of it, that bends in the plane of the plate to let a
// 6 mm rod in. defect=true leaves a thin skin under the slots: the arm is joined to the plate along
// its whole length and cannot bend.
defect = false;
plate = [60, 34, 4];
arm_w = 2.4;
arm_l = 34;
slot = 1.2;
rod = 6;
skin = defect ? 0.6 : -1;

echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], plate]],
    ["bodies", 1],
    ["through_holes", defect ? 0 : 2],
    ["material", "PLA"]
]);

x0 = 10;
y0 = 12;
difference() {
    cube(plate);
    // the U-shaped slot around the arm, and the seat of the rod at its free end
    translate([x0, y0 - slot, skin]) cube([arm_l, slot, plate[2] + 2]);
    translate([x0, y0 + arm_w, skin]) cube([arm_l, slot, plate[2] + 2]);
    translate([x0 + arm_l, y0 - slot, skin]) cube([slot, arm_w + 2 * slot, plate[2] + 2]);
    translate([x0 + arm_l + rod / 2 + slot, y0 + arm_w / 2, skin])
        cylinder(d = rod, h = plate[2] + 2, $fn = 48);
}
