/* Box with print-in-place hinge - step 1: params + base */
part = "assembly"; // [base, lid, pin, assembly]

cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---- parameters (mm) ----
W = 80; D = 60; H = 40;          // body outer, closed
baseH = 30;                      // base height
gapZLid = 0.3;                   // lid-base vertical gap
lidBot = baseH + gapZLid;        // 30.3
lidTop = H;                      // 40
axY = 0; axZ = baseH + gapZLid/2; // hinge axis (0, 30.15)
wallT = 2; floorT = 2.5; lidTopT = 2.5;
pinH = 1.8; boreH = 2.2; outH = 4.0; cbH = 3.2; capH = 2.8;
clrR = 0.4; clrA = 0.4;
divT = 2; divTop = 37.2;

// knuckle X intervals
bx10=-40; bx11=-24; lx10=-23.6; lx11=-7.6;
bx20=-7.2; bx21=7.2; lx20=7.6; lx21=23.6; bx30=24; bx31=40;

// generic prism along X from polygon in (Z,Y) mapped: poly points [z,y]
module prism_x(poly, x0, len) {
    translate([x0, 0, 0]) rotate([0,90,0])
        linear_extrude(height=len) polygon(poly);
}
function diamond(h) = [[-h,0],[0,-h],[h,0],[0,h]];

module knuckle_out(x0, len) {
    // diamond cross-section points [z,y] centered at (axZ, axY)
    p = diamond(outH);
    translate([0, axY, axZ]) prism_x(p, x0, len);
}
module bore_small(x0, len) {
    p = diamond(boreH);
    translate([0, axY, axZ]) prism_x(p, x0, len);
}
module bore_cb(x0, len) {
    p = diamond(cbH);
    translate([0, axY, axZ]) prism_x(p, x0, len);
}

module base_geo() {
    difference() {
        union() {
            // floor + walls
            cube([W, D, floorT], center=false); // placeholder, moved below
        }
        // subtractions added in step 1b
        cube([0.01,0.01,0.01]);
    }
}

// stubs
module lid_geo() { cube([0.01,0.01,0.01]); }
module pin_geo() { cube([0.01,0.01,0.01]); }

if (part=="base") { base_geo(); }
else if (part=="lid") { lid_geo(); }
else if (part=="pin") { pin_geo(); }
else if (part=="assembly") {
    instance("base","base") base_geo();
    instance("lid","lid") lid_geo();
    instance("pin","pin") pin_geo();
}
