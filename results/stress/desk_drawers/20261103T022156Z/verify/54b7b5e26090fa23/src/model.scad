part = "assembly"; // [assembly:Assembly, frame:Frame, drawer:Drawer]
cadverify_only = "";
module instance(name, part, unit = 1) {
    echo(cadverify_instance = [name, part, unit]);
    if (cadverify_only == "" || cadverify_only == name) children();
}
// frame assembly coords: X -60..60, Y 0..150, Z 0..90
module frame_asm() {
    union() {
        translate([-60,0,0]) cube([120,5,90]);
        translate([-60,0,0]) cube([5,150,90]);
        translate([55,0,0]) cube([5,150,90]);
        translate([-55,5,0]) cube([110,145,6]);
        translate([-55,5,42]) cube([110,145,6]);
        translate([-55,5,84]) cube([110,145,6]);
        translate([-55,125,10.5]) cube([1.2,10,5]);
        translate([53.8,125,10.5]) cube([1.2,10,5]);
        translate([-55,125,52.5]) cube([1.2,10,5]);
        translate([53.8,125,52.5]) cube([1.2,10,5]);
    }
}
module frame_print() {
    translate([0,90,0]) rotate([90,0,0]) frame_asm();
}
// drawer part coords: X -54.5..54.5, Y 0..144 body + handle to 156, Z 0..34
module drawer_raw() {
    difference() {
        union() {
            translate([-54.5,0,0]) cube([109,144,34]);
            // handle tip block
            translate([-35,144,30]) cube([70,12,4]);
            // handle wedge (triangular prism)
            polyhedron(points=[[-35,144,18],[-35,144,30],[-35,156,30],[-35,144,18],[35,144,18],[35,144,30],[35,156,30],[-35,156,30],[35,144,18],[35,156,30]], faces=[[0,1,2],[5,4,3],[0,4,5,1],[1,5,6,2],[2,6,7],[7,6,5],[0,2,7,3],[3,7,6,4]]);
        }
        translate([-50.5,4,3]) cube([101,135,32]);
        translate([-54.5,14,4]) cube([2.5,116,6]);
        translate([52,14,4]) cube([2.5,116,6]);
    }
}
module drawer_part() { drawer_raw(); }
module frame_spec() {
    echo(cadverify_spec = [
        ["bounds", [[-60,0,0],[60,90,150]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",5000]]],
        ["overhangs_allowed", [
            ["stop tab underside, bridge 2.4mm", [[-55,74.5,124],[-53.8,79.5,126]]],
            ["stop tab underside, bridge 2.4mm", [[53.8,74.5,124],[55,79.5,126]]],
            ["stop tab underside, bridge 2.4mm", [[-55,32.5,124],[-53.8,37.5,126]]],
            ["stop tab underside, bridge 2.4mm", [[53.8,32.5,124],[55,37.5,126]]]
        ]],
        ["copies", 1],
        ["details", [
            ["back_panel","material",[[-60,0,0],[60,90,5]],0.9],
            ["stop_tab_ll","material",[[-55,74.5,125],[-53.8,79.5,135]],0.9],
            ["stop_tab_lr","material",[[53.8,74.5,125],[55,79.5,135]],0.9],
            ["stop_tab_ul","material",[[-55,32.5,125],[-53.8,37.5,135]],0.9],
            ["stop_tab_ur","material",[[53.8,32.5,125],[55,37.5,135]],0.9],
            ["lower_cavity","void",[[-55,48,5],[55,84,150]],0.9],
            ["upper_cavity","void",[[-55,6,5],[55,42,150]],0.9],
            ["back","thickness",[0,10,-1],[0,0,1],5]
        ]]
    ]);
}
module drawer_spec() {
    echo(cadverify_spec = [
        ["bounds", [[-54.5,0,0],[54.5,156,34]]],
        ["bodies", 1],
        ["through_holes", 0],
        ["support_faces", [["bed","-z",10000]]],
        ["overhangs_allowed", [
            ["drawer slide groove ceiling, bridge 5mm", [[-54.5,14,9],[-52,130,11]]],
            ["drawer slide groove ceiling, bridge 5mm", [[52,14,9],[54.5,130,11]]]
        ]],
        ["copies", 2],
        ["details", [
            ["pull_tip","material",[[-35,150,30],[35,156,34]],0.9],
            ["groove_left","void",[[-54.5,14,4],[-52,130,10]],0.9],
            ["groove_right","void",[[52,14,4],[54.5,130,10]],0.9],
            ["drawer_cavity","void",[[-50.5,4,3],[50.5,139,34]],0.9],
            ["bottom","thickness",[0,70,-1],[0,0,1],3],
            ["side_walls","thickness",[-55.5,70,20],[1,0,0],8],
            ["pull_shape","view",[[-35,144,18],[35,156,34]]]
        ]]
    ]);
}
module assembly_spec() {
    echo(cadverify_spec = [
        ["bounds", [[-60,0,0],[60,162,90]]],
        ["support_faces", [["base","-z",5000]]],
        ["allowed_interferences", []],
        ["motions", [
            ["drawer_lower_slide", ["drawer_lower"], "slide", [0,1,0], [0,105], ["stops", [0,105]]],
            ["drawer_upper_slide", ["drawer_upper"], "slide", [0,1,0], [0,105], ["stops", [0,105]]]
        ]],
        ["assembly_order", [
            [["frame"], [0,0,0]],
            [["drawer_lower"], [0,-1,0], ["flex", [["drawer_lower","frame",0.7,"stop tabs snap into grooves"]]]],
            [["drawer_upper"], [0,-1,0], ["flex", [["drawer_upper","frame",0.7,"stop tabs snap into grooves"]]]]
        ]]
    ]);
}
if (part == "frame") { frame_spec(); frame_print(); }
else if (part == "drawer") { drawer_spec(); drawer_part(); }
else if (part == "assembly") {
    assembly_spec();
    instance("frame","frame",1) frame_asm();
    instance("drawer_lower","drawer",1) translate([0,6,7]) drawer_raw();
    instance("drawer_upper","drawer",1) translate([0,6,49]) drawer_raw();
}
