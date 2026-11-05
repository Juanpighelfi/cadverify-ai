# G6 of the recorded sessions, checked by hand

The three worst and three that pass, each against a beam or contact estimate made from the numbers in
its source. E = 2750 MPa for PLA. The FEA strain is averaged over 0.4 mm, the width of a line, so on a
wall a few lines thick it reads about 0.7 to 0.8 of a beam's surface value. `behaviour.json` and the
pictures of each are next to this file, under the session's name.

## The worst

**Crank gear train, detent, `showcase/crank_gear_train/20261103T183609Z`.** 201.85 N, 7.22% against
1.38%. Red, correctly. The wall that carries the bump is 1.8 mm thick, 6.9 mm tall and about 16 mm along
its arc, standing on the plate along its whole bottom edge. As a straight cantilever taking all 0.7 mm,
the formula 3 t d / (2 L^2) gives 3.97%. FEA gives more because the load does not bend the wall evenly:
it comes in at the top of one end, through a short arm, so the strain gathers at that corner. The
stiffness agrees: 3 E I / L^3 is 12.2 N/mm per mm of width, so about 20 mm of effective width makes
about 245 N/mm, and FEA gives 290 N/mm. The turn would stall or the wall would break.

**Bayonet jar, `bench/bayonet_jar/20261031T143418Z`.** 2105 N, 3.89% against 2.26% in PETG. Red,
correctly. The lid's skirt is a stiff ring with lugs on it, and the source asks them to ride 0.8 mm over
the jar. Nothing there is a spring: at about 2600 N/mm most of the compliance is the skirt's local
bending. Nobody turns a lid against that by hand.

**Ball joint, `stress/ball_joint/20261103T011514Z`.** 5777 N, 3.50% against 2.76%. Red, correctly. The
holder is a block 88 x 23 x 20 mm with a 19 mm opening and slots 4 mm wide, and a 20 mm ball goes
through it. For a contact patch about 2 mm in radius, a half space gives 2 E a / (1 - nu^2), about
12,500 N/mm, and FEA gives about 11,900 N/mm: the block does not flex, it dents. The absolute force
means little here, and the verdict does not hang on it.

Also read, since its force looked too high at first: **desk drawers,
`stress/desk_drawers/20261103T022156Z`.** About 3900 N for 0.7 mm, red. The stop tabs meet the drawer's
wall at its rear corner, against its back wall and floor, and the frame's wall 8 mm from its floor. Both
are stiff: a beam clamped at floor and shelf gives about 7,000 N/mm per tab on the frame and FEA about
11,000 N/mm for the two tabs. This session found a flaw in the solver: gmsh could not remesh the drawer,
it kept its surface, and 216 tetrahedra made it twice too stiff with no sign of it on refining. A kept
surface is now split to the mesh's size first (`fea._split`). The same fix took the bayonet jar's own
strain, above, from 0.85% to 1.95%. Past the first flex this session runs out of its CPU budget.

## That pass

**Battery box, `stress/battery_box/20261103T020825Z`.** 4.79 N, 0.28% against 1.38%. Passes, correctly. A
tab 12 mm wide, 2 mm thick, 19.1 mm from its root to the tooth, with a finger hole in it. Without the hole,
3 E I / L^3 gives 9.5 N/mm, and FEA gives 6.1 N/mm with the hole and the root's give. The moment at the
root gives 0.38% at the surface, which is the 0.28% over the 0.4 mm of the line.

**Hinge box catch, `bench/hinge_box/20261031T171141Z`.** 0.83 N, 0.37% against 1.38%. Passes, correctly. A
tab 7 mm wide, 0.6 mm thick, about 6.8 mm from the lid to the bump gives 3.3 N/mm against 5.1 N/mm from
FEA, which also sees the bump stiffening the tab. The moment gives 0.51% at the surface against 0.37%
averaged. A 0.6 mm tab is two lines wide, which is its own risk, and the slicer reports that.

**Ratchet pawl, `stress/ratchet/20261103T034705Z`.** 3.5 N, 0.50% against 1.38%. Passes, correctly. A
backbone 1.5 mm thick, 10 mm tall, 19.25 mm long gives about 3.3 N/mm, and FEA gives 5.8 N/mm. The moment of
that force gives 0.65% at the surface against 0.50% averaged. Far enough under the limit for the factor
of two in stiffness not to matter.

## What this shows and what it does not

Among these seven, no red looks false and no green looks false. The other sessions in the table were
not checked by hand. Where FEA and a beam differ here, it is by up to a factor of two in stiffness,
either way: FEA softer on the battery tab with its hole, stiffer on the hinge catch and the pawl. That is why a force here is an
estimate and `cadverify baseline` compares against a version that worked. None of these was printed.

A flex with a strain under its limit passes whatever force it takes, unless its spec gives a target:
at 835 N, the gimbal's first flex is within its strain. The close has to state the force, and the reviewer
reads it, but no gate judges it.
