// Headphone stand in three parts - PLA, no supports, 0.4mm nozzle
// Print orientations (+Z up, bottom on bed):
//   base   : flat, plate bottom on bed
//   post   : vertical, bottom on bed (250+ tall)
//   hanger : flat bottom on bed, curved top up, socket opening down (bridged)
// Assembly (desk Z=0): base 0-30, post 10-262, hanger 244-270 (top ~270)

part = "base"; // [base:Base, post:Post, hanger:Hanger, assembly:Assembly]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}

// ---------- parameters ----------
baseW = 160; baseD = 180; baseT = 12; baseR = 12;
bossW = 56; bossD = 50; bossH = 18; bossR = 8;
bossTop = baseT + bossH; // 30
sockW = 30.4; sockD = 24.4; sockR = 4.2; // base socket (post 30x24 +0.4)
sockDepthBase = 20;
sockFloorBase = bossTop - sockDepthBase; // 10
flare = 1.5;
mouthWBase = sockW + 2*flare; mouthDBase = sockD + 2*flare; mouthRBase = sockR + flare;

postW = 30; postD = 24; postR = 4; postH = 252; postCham = 1.5;
tipW = postW - 2*postCham; tipD = postD - 2*postCham; tipR = 2.5;

hangW = 42; hangL = 120; hangZc = 26; hangZe = 14; hangFillet = 8; hangPlanR = 15;
hangSockW = 30.4; hangSockD = 24.4; hangSockR = 4.2; hangSockDepth = 18;
mouthWH = hangSockW + 2*flare; mouthDH = hangSockD + 2*flare; mouthRH = hangSockR + flare;

postZ = 10;          // post bottom in assembly
hangerZ = 244;       // hanger bottom in assembly -> top 270
// post top = postZ+postH = 262 = hangerZ+hangSockDepth (socket floor)

// ---------- helpers ----------
module rounded_box(W,D,H,R) {
    // centered in XY, bottom at Z=0
    if (R <= 0.01) {
        translate([-W/2,-D/2,0]) cube([W,D,H]);
    } else {
        hull() {
            for (sx=[-1,1], sy=[-1,1])
                translate([sx*(W/2-R), sy*(D/2-R), 0])
                    cylinder(r=R, h=H, $fn=32);
        }
    }
}
module rect_frustum(W1,D1,R1, W2,D2,R2, H) {
    // bottom size 1 at Z=0, top size 2 at Z=H
    hull() {
        translate([0,0,0]) rounded_box(W1,D1,0.1,R1);
        translate([0,0,H-0.1]) rounded_box(W2,D2,0.1,R2);
    }
}

// ---------- parts (print orientation, bottom Z=0, centered XY) ----------
module base_part() {
    difference() {
        union() {
            rounded_box(baseW, baseD, baseT, baseR);
            translate([0,0,baseT-0.2]) rounded_box(bossW, bossD, bossH+0.2, bossR);
        }
        // socket bore (extend above mouth for clean cut)
        translate([0,0,sockFloorBase]) rounded_box(sockW, sockD, sockDepthBase+1.0, sockR);
        // entry flare 45deg (mouth larger at top)
        translate([0,0,bossTop-flare])
            rect_frustum(sockW,sockD,sockR, mouthWBase,mouthDBase,mouthRBase, flare+1.0);
    }
}

module post_part() {
    // single hull of nested rounded-rect slices: no internal ledges,
    // straight sides, 45° lead-in chamfers at both ends
    hull() {
        translate([0,0,0]) rounded_box(tipW, tipD, 0.2, tipR);
        translate([0,0,postCham-0.15]) rounded_box(postW, postD, 0.3, postR);
        translate([0,0,postH-postCham-0.15]) rounded_box(postW, postD, 0.3, postR);
        translate([0,0,postH-0.2]) rounded_box(tipW, tipD, 0.2, tipR);
    }
}

module hanger_A() {
    union() {
        // lower block 0 .. Zc-r
        translate([-hangW/2, -hangL/2, 0]) cube([hangW, hangL, hangZc-hangFillet]);
        // upper block (narrower) Zc-r .. top
        translate([-(hangW-2*hangFillet)/2, -hangL/2, hangZc-hangFillet])
            cube([hangW-2*hangFillet, hangL, hangFillet]);
        // two side fillet cylinders along Y
        for (sx=[-1,1])
            translate([sx*(hangW/2-hangFillet), -hangL/2, hangZc-hangFillet])
                rotate([-90,0,0])
                    cylinder(r=hangFillet, h=hangL, $fn=32);
    }
}
module hanger_B() {
    // hull of slices under parabolic top (convex hypograph)
    N = 25;
    hull() {
        for (i=[0:N-1]) {
            yi = -hangL/2 + hangL*i/(N-1);
            hi = hangZc - (hangZc-hangZe)*pow(2*yi/hangL,2);
            translate([-hangW/2, yi-0.3, 0]) cube([hangW, 0.6, hi]);
        }
    }
}
module hanger_D() {
    rounded_box(hangW, hangL, 30, hangPlanR);
}
module hanger_part() {
    difference() {
        intersection() {
            hanger_A();
            hanger_B();
            hanger_D();
        }
        // socket bore (extend below bed for clean cut)
        translate([0,0,-0.5]) rounded_box(hangSockW, hangSockD, hangSockDepth+0.5, hangSockR);
        // entry flare at mouth (bottom)
        translate([0,0,-0.5])
            rect_frustum(mouthWH,mouthDH,mouthRH, hangSockW,hangSockD,hangSockR, flare+0.5);
    }
}

// ---------- specs ----------
if (part == "base") {
    echo(cadverify_spec = [
        ["bounds", [[-baseW/2, -baseD/2, 0], [baseW/2, baseD/2, bossTop]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 20000]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["plate", "material", [[-baseW/2, -baseD/2, 0], [baseW/2, baseD/2, baseT]], 0.95],
            ["boss", "material", [[-bossW/2, -bossD/2, baseT], [bossW/2, bossD/2, bossTop]], 0.60],
            ["socket", "void", [[-sockW/2, -sockD/2, sockFloorBase], [sockW/2, sockD/2, bossTop]], 0.90],
            ["floor", "thickness", [0, 0, -5], [0, 0, 1], 10],
            ["corner", "view", [[65, 75, 0], [80, 90, 12]]],
            ["mouth", "view", [[-17, -14, 28], [17, 14, 30]]]
        ]]
    ]);
    base_part();
} else if (part == "post") {
    echo(cadverify_spec = [
        ["bounds", [[-postW/2, -postD/2, 0], [postW/2, postD/2, postH]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 400]]],
        ["overhangs_allowed", []],
        ["copies", 1],
        ["details", [
            ["shaft", "material", [[-9.5, -9.5, 10], [9.5, 9.5, 242]], 0.99],
            ["wall", "thickness", [30, 0, 126], [-1, 0, 0], 30],
            ["lead", "view", [[-15, -12, 0], [15, 12, 3]]],
            ["topcham", "view", [[-15, -12, 249], [15, 12, 252]]]
        ]]
    ]);
    post_part();
} else if (part == "hanger") {
    echo(cadverify_spec = [
        ["bounds", [[-hangW/2, -hangL/2, 0], [hangW/2, hangL/2, hangZc]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed", "-z", 2500]]],
        ["overhangs_allowed", [["bridging socket ceiling", [[-hangSockW/2, -hangSockD/2, 16], [hangSockW/2, hangSockD/2, 20]]]]],
        ["copies", 1],
        ["details", [
            ["contact", "material", [[-15, -30, 18], [15, 30, 22]], 0.95],
            ["socket", "void", [[-hangSockW/2, -hangSockD/2, 0], [hangSockW/2, hangSockD/2, hangSockDepth]], 0.90],
            ["topwall", "thickness", [0, 0, 30], [0, 0, -1], 8],
            ["fillet", "view", [[13, -20, 18], [21, 20, 26]]],
            ["arch", "view", [[-21, -60, 12], [21, -40, 16]]],
            ["mouth", "view", [[-17, -14, 0], [17, 14, 2]]]
        ]]
    ]);
    hanger_part();
} else if (part == "assembly") {
    echo(cadverify_spec = [
        ["bounds", [[-baseW/2, -baseD/2, 0], [baseW/2, baseD/2, hangerZ+hangZc]]],
        ["support_faces", [["desk", "-z", 20000]]],
        ["allowed_interferences", []],
        ["motions", []],
        ["assembly_order", [
            [["base_1"], [0, 0, 0]],
            [["post_1"], [0, 0, -1]],
            [["hanger_1"], [0, 0, -1]]
        ]]
    ]);
    instance("base_1", "base") translate([0,0,0]) base_part();
    instance("post_1", "post") translate([0,0,postZ]) post_part();
    instance("hanger_1", "hanger") translate([0,0,hangerZ]) hanger_part();
}
