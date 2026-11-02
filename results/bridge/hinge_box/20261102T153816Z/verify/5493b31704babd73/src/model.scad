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

function D(h,y0,z0) = [[y0-h,-z0],[y0,-z0-h],[y0+h,-z0],[y0,-z0+h]];
module dia(h,y0,z0,x0,x1) {
    translate([x0,0,0]) rotate([0,90,0])
        linear_extrude(height=x1-x0, convexity=4) polygon(D(h,y0,z0));
}
module base_geo() {
    difference() {
        union() {
            translate([-40,0,0]) cube([80,60,2.5]);            // floor
            translate([-40,0,0]) cube([80,2,30]);              // back wall
            translate([-40,58,0]) cube([80,2,30]);             // front wall
            translate([-40,2,0]) cube([2,56,30]);              // left wall
            translate([38,2,0]) cube([2,56,30]);               // right wall
            for (cy=[12.6,24.2,35.8,47.4])
                translate([-38,cy-1,2.5]) cube([76,2,27.5]);   // dividers
            dia(outH,0,axZ,bx10,bx11);                         // knuckles
            dia(outH,0,axZ,bx20,bx21);
            dia(outH,0,axZ,bx30,bx31);
        }
        // bore channels + cap pockets
        dia(boreH,0,axZ,bx10,bx11); dia(cbH,0,axZ,-27.6,-24.4);
        dia(boreH,0,axZ,bx20,bx21);
        dia(boreH,0,axZ,bx30,bx31); dia(cbH,0,axZ,24.4,27.6);
        // back-wall notches under lid knuckles
        dia(boreH+clrR,0,axZ,lx10,lx11);
        dia(boreH+clrR,0,axZ,lx20,lx21);
        // catch groove in front wall outer face
        translate([-6,58.8,27.5]) cube([12,1.21,1.5]);
    }
}

module lid_geo() {
    difference() {
        union() {
            // top plate: x -40..40, y 0..60, z 37.5..40
            translate([-40,0,37.5]) cube([80,60,2.5]);
            // lid skirt walls 2mm, y 0..60, z 30.3..37.5
            translate([-40,0,30.3]) cube([80,2,7.2]);    // back band
            translate([-40,58,30.3]) cube([80,2,7.2]);   // front band
            translate([-40,2,30.3]) cube([2,56,7.2]);    // left band
            translate([38,2,30.3]) cube([2,56,7.2]);     // right band
            // lid skirt inner closure panels (also skirt divider walls)
            for (cy=[12.6,24.2,35.8,47.4])
                translate([-38,cy-1,30.3]) cube([76,2,4.2]);  // up to 34.5
            // lid knuckles + catch tongue
            dia(outH,0,axZ,lx10,lx11);
            dia(outH,0,axZ,lx20,lx21);
            translate([-6,58.3,27.5]) cube([12,1.7,3.4]);  // tongue tab below front band
        }
        // bore channels
        dia(boreH,0,axZ,lx10,lx11);
        dia(boreH,0,axZ,lx20,lx21);
        // clearance pockets opposite base knuckles
        dia(boreH+clrR,0,axZ,-27.6,-23.6);
        dia(boreH+clrR,0,axZ,-7.6,-7.2);
        dia(boreH+clrR,0,axZ,7.2,7.6);
        dia(boreH+clrR,0,axZ,23.6,27.6);
    }
}
// stubs
module pin_geo() { cube([0.01,0.01,0.01]); }

if (part=="base") { base_geo(); }
else if (part=="lid") { lid_geo(); }
else if (part=="pin") { pin_geo(); }
else if (part=="assembly") {
    instance("base","base") base_geo();
    instance("lid","lid") lid_geo();
    instance("pin","pin") pin_geo();
}
