# G6 of the recorded sessions

23 sessions with a flex that met what it presses on, 29 flexes; of 20 green sessions, 12 are red in G6 today.

| Why | Greens | Sessions |
|---|--:|---|
| a strain past its limit | 5 | bench/bayonet_jar/20261031T143418Z, showcase/crank_gear_train/20261103T183609Z, stress/ball_joint/20261103T011514Z, stress/desk_drawers/20261103T022156Z, stress/gimbal/20261103T003908Z |
| the part could not be filled with tetrahedra | 4 | bench/bayonet_jar/20261031T143428Z, bench/hinge_box/20261031T164747Z, stress/pill_box/20261103T013129Z, stress/pill_box/20261103T034700Z |
| not computed: G3 or G4 are red with today's code | 2 | bench/hinge_box/20261031T161811Z, bridge/hinge_box/20261102T134650Z |
| ran over its CPU budget | 1 | stress/pill_box/20261103T034711Z |

| Session | Flex | Depth (mm) | Force (N) | Part | Strain / limit (%) | Z / limit (%) | G6 |
|---|---|---|---:|---|---:|---:|---|
| bench/bayonet_jar/20261031T143418Z | motion lid_lock: lid / jar | 0.800 | 2105.34 | lid | 3.891 / 2.26 | 3.854 / 1.0 | red |
| bench/bayonet_jar/20261031T143418Z | motion lid_lock: lid / jar | 0.800 | 2105.34 | jar | 1.954 / 2.26 | 1.915 / 1.0 | red |
| bench/bayonet_jar/20261031T143428Z | motion twist_lock: lid / jar | 0.200 | - |  | - / - | - / - | red |
| bench/hinge_box/20261031T161811Z | | | | | | | not computed:  |
| bench/hinge_box/20261031T164747Z | motion lid_swing: lid / body | 0.428 | - |  | - / - | - / - | red |
| bench/hinge_box/20261031T171141Z | motion open_lid: lid / body | 0.171 | 0.83 | lid | 0.368 / 1.38 | 0.367 / 0.69 | green |
| bench/hinge_box/20261031T171141Z | motion open_lid: lid / body | 0.171 | 0.83 | body | 0.008 / 1.38 | 0.004 / 0.69 | green |
| bridge/hinge_box/20261102T132939Z | motion hinge_open: lid / box | 0.204 | 10.82 | lid | 0.226 / 1.38 | 0.2 / 0.69 | green |
| bridge/hinge_box/20261102T132939Z | motion hinge_open: lid / box | 0.204 | 10.82 | box | 0.076 / 1.38 | 0.053 / 0.69 | green |
| bridge/hinge_box/20261102T134650Z | | | | | | | not computed:  |
| bridge/hinge_box/20261102T153656Z | | | | | | | not computed: assembly_order, step 2: lid does not go in moving along [0, 0.707, -0.707]: it hits base on 245.7 mm² of its shadow (zone [[-22.925, 25.0, 22.345], [24.925, 27.881, 30.0]]); it goes in along no axis direction |
| showcase/crank_gear_train/20261103T181440Z | motion crank_turn: gear1 / base | 0.696 | 201.73 | gear1 | 0.621 / 1.38 | 0.493 / 0.69 | red |
| showcase/crank_gear_train/20261103T181440Z | motion crank_turn: gear1 / base | 0.696 | 201.73 | base | 6.735 / 1.38 | 6.423 / 0.69 | red |
| showcase/crank_gear_train/20261103T183609Z | motion crank_turn: gear1 / base | 0.696 | 201.85 | gear1 | 0.695 / 1.38 | 0.619 / 0.69 | red |
| showcase/crank_gear_train/20261103T183609Z | motion crank_turn: gear1 / base | 0.696 | 201.85 | base | 7.223 / 1.38 | 6.073 / 0.69 | red |
| stress/ball_joint/20261103T011514Z | assembly step 2: holder / base | 0.487 | 5776.73 | holder | 3.497 / 2.76 | 2.81 / 1.38 | red |
| stress/ball_joint/20261103T011514Z | assembly step 2: holder / base | 0.487 | 5776.73 | base | 0.448 / 2.76 | 0.183 / 1.38 | red |
| stress/battery_box/20261103T020825Z | motion slide_off: cover / base | 0.800 | 4.79 | cover | 0.277 / 1.38 | 0.011 / 0.69 | green |
| stress/battery_box/20261103T020825Z | motion slide_off: cover / base | 0.800 | 4.79 | base | 0.018 / 1.38 | 0.011 / 0.69 | green |
| stress/battery_box/20261103T020825Z | assembly step 4: cover / base | 0.800 | 4.79 | cover | 0.288 / 2.76 | 0.016 / 1.38 | green |
| stress/battery_box/20261103T020825Z | assembly step 4: cover / base | 0.800 | 4.79 | base | 0.018 / 2.76 | 0.011 / 1.38 | green |
| stress/desk_drawers/20261103T022156Z | assembly step 2: drawer_lower / frame | 0.700 | 3851.11 | drawer_lower | 2.071 / 2.76 | 2.008 / 1.38 | red |
| stress/desk_drawers/20261103T022156Z | assembly step 2: drawer_lower / frame | 0.700 | 3851.11 | frame | 1.95 / 2.76 | 1.341 / 1.38 | red |
| stress/gimbal/20261103T003908Z | assembly step 2: middle / frame | 0.534 | 835.44 | middle | 1.604 / 2.76 | 0.583 / 1.38 | green |
| stress/gimbal/20261103T003908Z | assembly step 2: middle / frame | 0.534 | 835.44 | frame | 1.439 / 2.76 | 0.973 / 1.38 | green |
| stress/gimbal/20261103T003908Z | assembly step 3: disc / middle | 0.541 | 1917.03 | disc | 1.829 / 2.76 | 0.981 / 1.38 | red |
| stress/gimbal/20261103T003908Z | assembly step 3: disc / middle | 0.541 | 1917.03 | middle | 4.172 / 2.76 | 1.767 / 1.38 | red |
| stress/living_hinge_clip/20261103T041036Z | motion closing: upper / lower | 0.236 | 39.99 | upper | 0.173 / 2.26 | 0.043 / 1.0 | green |
| stress/living_hinge_clip/20261103T041036Z | motion closing: upper / lower | 0.236 | 39.99 | lower | 0.287 / 2.26 | 0.056 / 1.0 | green |
| stress/pi4_case/20261103T024102Z | assembly step 3: lid / base | 0.300 | 11.45 | lid | 0.468 / 2.76 | 0.259 / 1.38 | green |
| stress/pi4_case/20261103T024102Z | assembly step 3: lid / base | 0.300 | 11.45 | base | 0.029 / 2.76 | 0.027 / 1.38 | green |
| stress/pi4_case/20261103T025213Z | assembly step 3: lid / base | 0.300 | 6.55 | lid | 0.09 / 2.76 | 0.089 / 1.38 | green |
| stress/pi4_case/20261103T025213Z | assembly step 3: lid / base | 0.300 | 6.55 | base | 0.175 / 2.76 | 0.175 / 1.38 | green |
| stress/pill_box/20261103T013129Z | motion lid_turn: lid / base | 0.600 | - |  | - / - | - / - | red |
| stress/pill_box/20261103T013129Z | assembly step 2: lid / base | 0.600 | - |  | - / - | - / - | red |
| stress/pill_box/20261103T034700Z | motion lid_turn: lid_main / base_main | 0.400 | - |  | - / - | - / - | red |
| stress/pill_box/20261103T034700Z | assembly step 2: lid_main / base_main | 0.899 | - |  | - / - | - / - | red |
| stress/pill_box/20261103T034711Z | motion lid_turn: lid / base | 0.795 | 39.57 | lid | 1.081 / 1.38 | 0.352 / 0.69 | green |
| stress/pill_box/20261103T034711Z | motion lid_turn: lid / base | 0.795 | 39.57 | base | 0.242 / 1.38 | 0.054 / 0.69 | green |
| stress/ratchet/20261102T195112Z | motion spin_free: wheel_inst / base_inst | 0.683 | 6.87 | wheel_inst | 0.003 / 1.38 | 0.003 / 0.69 | green |
| stress/ratchet/20261102T195112Z | motion spin_free: wheel_inst / base_inst | 0.683 | 6.87 | base_inst | 0.646 / 1.38 | 0.17 / 0.69 | green |
| stress/ratchet/20261103T034705Z | motion free: wheel1 / base1 | 0.604 | 3.5 | wheel1 | 0.002 / 1.38 | 0.002 / 0.69 | green |
| stress/ratchet/20261103T034705Z | motion free: wheel1 / base1 | 0.604 | 3.5 | base1 | 0.501 / 1.38 | 0.183 / 0.69 | green |
| stress/screw_jar/20261102T190646Z | | | | | | | not computed: motion lift_off: lid and jar never overlap along it, so nothing bends: a flex is a feature that rides over what it presses on (a detent, a catch). Make it meet that, or leave the flex out |

## Requests that name a load

Not one recorded spec could declare a load. Today's auditor would ask for one on these.

| Request | What it names |
|---|---|
| ball_joint | 200 g, grips, hold, snaps |
| battery_box | clicks, flexible, holds |
| bayonet_jar | hold |
| crank_gear_train | clicks, flexible, standing up |
| flexi_bracelet | snap |
| headphone_stand | 350 g, weigh |
| living_hinge_clip | clip, flexible, latch |
| m3_knob | grip |
| pi4_case | snaps |
| pill_box | clicks, holds |
| ratchet | clicks, flexible |
| spool_holder | 1 kg, 1.2 kg, holds, loaded, weighs |
