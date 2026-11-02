"""The gates, judged by the orchestrator.

Input: `cadcheck verify` on the current source (compile, every printable part exported with the
default parameters, its spec check and its printability, and the assembly) and the images the
model has seen.
- G1, it compiles and exports without errors, failed asserts or warnings;
- G2, every part is a closed mesh with the declared bodies;
- G3, the assembly: every part where the assembly places it, all of them, no overlaps, one
  group, the units the request chains (cadcheck.assembly);
- G4, motion: the declared motions and the assembly order, without collisions;
- G5, overhangs only inside the allowed boxes, which cover at most half of a part's surface, the
  part of each overhang steeper than 60° a bridge of 10 mm at most, no body that starts in the air
  (cadcheck.printability), and every part fits the bed; for an assembly printed in place, the
  same on all its parts together as they print (as they stand, or in its print pose), and the
  clearance it declares between any two (cadcheck.assembly);
- G7, the spec, details included, and what the model saw of the final version: the sheet of
  every part, a view of the assembly with all its instances, and a close view of every "view"
  detail (cadcheck.view, details_in_view);
- G8, the close: what it announces is verified (agent/closing.py). It needs the close's text,
  so it is judged when the model closes; until then it is pending (ok None).
"""

from __future__ import annotations

from typing import Any

GATES = ("G1", "G2", "G3", "G4", "G5", "G7", "G8")
# What a green gate verified, in the words the auditor of the close reads (agent/closing.py).
GREEN_MEANS = {
    "G1": "the source compiles and every part exports with the default parameters, with no "
    "errors, failed asserts, timeouts or warnings",
    "G2": "every part is a closed mesh: watertight, 0 bad edges, no inverted shells, a positive "
    "volume and the declared number of bodies",
    "G3": "the assembly: each instance is its part moved (same volume, area and principal "
    "moments), every part placed as many times as its copies, no overlap between instances "
    "beyond the allowed_interferences, all of them one connected group, and the units the "
    "request chains (nothing to check for one part without an assembly)",
    "G4": "every declared motion swept through its whole range, and every assembly_order step "
    "brought in from far away along its direction (turning, when it turns), without a collision "
    "with what is already placed (a press fit only as a fit: no thicker than one along a motion, "
    "and pushed in only where it overlaps in place). The parts are swept as rigid bodies; a pair "
    "a motion declares as flex may overlap while it moves, no deeper than declared and never at "
    "an end of the range: how deep is measured, not whether the feature can bend that far",
    "G5": "each part alone, in the orientation it is exported in: no overhang steeper than 45° "
    "outside its declared overhangs_allowed boxes (which cover at most half of its surface), "
    "the part of every overhang steeper than 60° (where the A1's slicer adds supports by "
    "default) a bridge of 10 mm at most (no point of it more than 5 mm, seen from above, from "
    "the material under its lowest edge), every body resting on the bed or starting 1 mm or "
    "less over another, and it fits the bed (Bambu Lab A1, 256 mm cube). Only an "
    "assembly that declares print_in_place is checked as printed whole: the same checks on all "
    "its parts together as they print (as they stand, or in the declared print_pose), and "
    "every two of them at least the declared clearance apart in that pose. Whether a bridge "
    "sags, or how the print looks, is not measured",
    "G7": "every spec check holds (bounds, bodies, through holes, support faces, details), and "
    "the designer saw the final version: the multi-view sheet of every part, all the "
    "instances of the assembly together in one view, and a close view of every detail of kind "
    "view",
}
MAX_WARNINGS = 10  # per stage in the gate report; scad_compile lists them all
MAX_ALLOWED_COVERAGE = 0.5  # of a part's surface inside its overhangs_allowed boxes
PENDING = "judged when you close"
DEFAULT_OUTPUT = "default output"  # the label of a source without a part selector


def evaluate(
    verify: dict[str, Any],
    seen_sheets: set[str],
    stl_sha: dict[str, str],
    view_groups: list[set[str]] | None = None,
    close_views: set[tuple[str, str]] | None = None,
) -> dict:
    """Each gate: {"ok", "detail"}; detail lists every reason a gate is red.

    `seen_sheets` holds the SHA-256 of every STL whose sheet was shown to the model and
    `stl_sha` the SHA-256 of each part's verification export, keyed by the part's label.
    `view_groups`, the SHA-256 of the STL files drawn together in each render_view, and
    `close_views`, (SHA-256 of the STL, detail name) of each detail a render_view showed up close.
    """
    gates: dict[str, list[str]] = {name: [] for name in GATES}
    compiled = verify["compile"]
    reported: set[str] = set()
    gates["G1"] += _diagnostics("compilation", compiled, reported)
    for part in verify["parts"]:
        label = part["part"] or DEFAULT_OUTPUT
        export, printability = part["export"], part["printability"]
        gates["G1"] += _diagnostics(f"export of {label}", export, reported)
        if not export["ok"] or not export["mesh"] or not export["mesh"]["triangles"]:
            reason = f"{label}: no mesh could be exported"
            for gate in ("G2", "G5", "G7"):
                gates[gate].append(reason)
            continue
        spec = export["spec"]
        gates["G2"] += [f"{label}: {r}" for r in mesh_problems(export["mesh"], spec)]
        gates["G5"] += [f"{label}: {r}" for r in print_problems(printability)]
        gates["G7"] += [f"{label}: {r}" for r in spec_problems(export)]
        if stl_sha.get(label) not in seen_sheets:
            gates["G7"].append(
                f"{label}: you did not see the sheet of the final version (export it with the "
                "default parameters: scad_export brings its sheet)"
            )
        looked = close_views or set()
        for detail in (spec or {}).get("details") or []:
            if detail["kind"] == "view" and (stl_sha.get(label), detail["name"]) not in looked:
                gates["G7"].append(
                    f"{label}: you did not look closely at the detail {detail['name']} in the "
                    "final version (render_view of the STL exported with the default "
                    "parameters, zoomed to its box: at least a quarter of the image's side)"
                )
    assembly = verify.get("assembly") or {}
    gates["G3"] += assembly_problems(assembly)
    gates["G4"] += list((assembly.get("problems") or {}).get("G4", []))
    gates["G5"] += print_in_place_problems(assembly)
    gates["G7"] += assembly_view_problems(assembly, view_groups or [])
    result = {name: {"ok": not reasons, "detail": reasons} for name, reasons in gates.items()}
    result["G8"] = {"ok": None, "detail": [PENDING]}
    return result


def assembly_problems(assembly: dict[str, Any]) -> list[str]:
    """G3 from the assembly report of verify."""
    if not assembly:
        return ["the verification did not measure the assembly"]
    if assembly.get("not_needed"):
        return []
    if assembly.get("missing"):
        return [
            'there are two printable parts or more and the part selector has no "assembly": '
            "the assembly shows how they go together, with instance() for each part"
        ]
    if "problems" not in assembly:
        return [f"the assembly could not be measured: {assembly.get('error', 'no detail')}"]
    problems = list(assembly["problems"].get("G3", []))
    if problems:
        problems.append(
            "interference_check measures the same in your session and leaves each instance and "
            "each overlap as an STL to look at with render_view"
        )
    return problems


def print_in_place_problems(assembly: dict[str, Any]) -> list[str]:
    """G5 of an assembly printed as it stands: its clearances, and the print of all its parts."""
    in_place = assembly.get("print_in_place")
    if not in_place:
        return []
    problems = [f"printed in place: {p}" for p in assembly["problems"].get("G5", [])]
    if in_place["printability"] is None:
        return problems + ["printed in place: there is no printed part in unit 1"]
    return problems + [
        f"assembly as printed in place: {p}" for p in print_problems(in_place["printability"])
    ]


def assembly_view_problems(assembly: dict[str, Any], view_groups: list[set[str]]) -> list[str]:
    """G7, assembly half: a render_view of the final version's instances, all in one view."""
    shas = {i.get("sha256") for i in assembly.get("instances") or []}
    if not shas or None in shas:
        return []
    if any(shas <= group for group in view_groups):
        return []
    return [
        "assembly: you did not see the instances of the final version together in one "
        "render_view (the STLs interference_check leaves)"
    ]


def part_ok(part: dict[str, Any]) -> bool:
    """A part of verify with no problem of its own in G1, G2, G5 or G7 (the sheet aside)."""
    export = part["export"]
    if export.get("errors") or export.get("asserts_failed") or export.get("timed_out"):
        return False
    if not export["ok"] or not export["mesh"] or not export["mesh"]["triangles"]:
        return False
    spec = export["spec"]
    return not (
        mesh_problems(export["mesh"], spec)
        or print_problems(part["printability"])
        or spec_problems(export)
    )


def all_green(gates: dict[str, Any]) -> bool:
    return all(g["ok"] is True for g in gates.values())


def green_but(gates: dict[str, Any], *skip: str) -> bool:
    return all(g["ok"] is True for name, g in gates.items() if name not in skip)


def mesh_problems(mesh: dict[str, Any], spec: dict[str, Any] | None) -> list[str]:
    """G2, strict: closed, no bad edges, the declared bodies, none
    inside out and a positive volume."""
    bodies = (spec or {}).get("bodies", 1)
    problems = []
    if not mesh["watertight"] or mesh["bad_edges"]:
        where = mesh.get("bad_edge_locations", [])[:3]
        problems.append(
            f"mesh not watertight: {mesh['bad_edges']} bad edges, for example at {where}"
        )
    if mesh["inverted_shells"]:
        problems.append(
            f"{mesh['inverted_shells']} inverted shell(s): likely cause, the faces of a "
            "polyhedron listed the wrong way round (they go clockwise seen from outside)"
        )
    if mesh["volume_mm3"] <= 0:
        problems.append(f"volume not positive ({mesh['volume_mm3']} mm³)")
    if mesh["bodies"] != bodies:
        problems.append(f"{mesh['bodies']} bodies, {bodies} expected")
    return problems


def print_problems(report: dict[str, Any] | None) -> list[str]:
    """G5: overhangs only inside declared zones, whose boxes cover at most half of the part's
    surface, the steep part of each zone a bridge no longer than the report's limit, no body
    that starts in the air, and the part fits the bed."""
    if not report or not report.get("ok"):
        return ["no printability_report"]
    problems = []
    share = (report.get("allowed_coverage") or {}).get("share", 0.0)
    if share > MAX_ALLOWED_COVERAGE:
        boxes = ", ".join(
            f"{b['name']} {b['share']:.0%}" for b in report["allowed_coverage"]["per_box"]
        )
        problems.append(
            f"the overhangs_allowed boxes cover {share:.0%} of the part's surface (at most "
            f"{MAX_ALLOWED_COVERAGE:.0%}): {boxes}. A box goes around the overhang it justifies, "
            "not around the part"
        )
    if not report["fits_bed"]:
        problems.append(f"does not fit the bed {report['bed_mm']}: it measures {report['size']}")
    for zone in report["zones"]:
        span = bridge_problem(
            zone.get("bridge"), report.get("max_bridge_mm"), report.get("bridge_deg")
        )
        if not zone["declared"]:
            problems.append(
                f"undeclared {zone['max_angle_deg']}° overhang ({zone['area_mm2']} mm², "
                f"bounds {zone['bounds']})"
                + (f"; {span}: declaring it is not enough" if span else "")
            )
        elif span:
            problems.append(f"declared overhang {zone['declared_as']!r}: {span}")
    for body in report.get("in_the_air") or []:
        problems.append(
            f"a body ({body['volume_mm3']} mm³, bounds {body['bounds']}) starts in the air at z "
            f"{body['z']}: nothing under its lowest layers within 1 mm, so its first layers print "
            "on nothing. It has to rest on the bed or start over another part"
        )
    hidden = report["zones_undeclared"] - sum(not z["declared"] for z in report["zones"])
    if hidden > 0:
        problems.append(f"and {hidden} more undeclared overhang zones")
    return problems


def bridge_problem(
    bridge: dict[str, Any] | None, limit: float | None, steep: float | None = None
) -> str | None:
    """Why the steep part of an overhang zone (steeper than `steep` degrees, or flat) does not
    print as a bridge, or None."""
    if not bridge or limit is None:
        return None
    seen = f"{bridge['area_mm2']} mm², {bridge['bounds_xy']}"
    if bridge.get("flat", True):
        where, under = f"the flat ceiling at z {bridge['z']} ({seen})", "under it"
    else:
        where = (
            f"its part steeper than {steep or 60:g}° from z {bridge['z']} to {bridge['z_top']} "
            f"({seen} seen from above)"
        )
        under = "under its lowest edge"
    if bridge["floating"]:
        return f"{where} has no material {under} to start from: it prints in the air"
    if bridge["bridge_mm"] <= limit:
        return None
    return (
        f"{where} has a point {bridge['farthest_mm']} mm from any material {under}: a bridge "
        f"that reaches it spans {bridge['bridge_mm']} mm or more, and a bridge prints clean up "
        f"to {limit:g} mm: hold it from below, narrow it, or print it in another pose"
    )


def spec_problems(export: dict[str, Any]) -> list[str]:
    """G7, numeric half: the spec exists, parses and the mesh meets it."""
    if export["spec_error"]:
        return [f"invalid spec: {export['spec_error']}"]
    if not export["spec"]:
        return ["echo(cadverify_spec = [...]) with the verifiable spec is missing"]
    check = export["spec_check"]
    bounds = check.get("bounds") or {"deviations": []}
    problems = [f"bounds off the spec: {d}" for d in bounds["deviations"]]
    for key in ("bodies", "through_holes"):
        if key in check and not check[key]["ok"]:
            problems.append(
                f"{key}: measured {check[key]['actual']}, specified {check[key]['expected']}"
            )
    for face in check["support_faces"]:
        if not face["ok"]:
            text = (
                f"support face {face['name']} ({face['direction']}): "
                f"{face['area_on_extreme_plane_mm2']} mm² on the extreme plane "
                f"{face['extreme_plane']}, {face['min_area_mm2']} required"
            )
            if "protrusion_mm" in face:
                text += (
                    f"; material sticks out {face['protrusion_mm']} mm past the largest flat "
                    f"face ({face['largest_flat_face']['plane']})"
                )
            problems.append(text)
    for detail in check.get("details") or []:
        if not detail["ok"]:
            problems.append(f"detail {detail['name']} ({detail['kind']}): {detail_text(detail)}")
    return problems


def detail_text(detail: dict[str, Any]) -> str:
    """What a detail measures against what it declares, in one line."""
    if "error" in detail:
        return detail["error"]
    kind = detail["kind"]
    if kind == "material":
        return (
            f"{detail['material_fraction']:.0%} of the box {detail['box']} has material; at "
            f"least {detail['min_fraction']:.0%} was declared"
        )
    if kind == "void":
        empty = 1 - detail["material_fraction"]
        return (
            f"{empty:.0%} of the box {detail['box']} is empty; at least "
            f"{detail['min_empty_fraction']:.0%} was declared"
        )
    if kind == "view":
        state = "all material" if detail["material_fraction"] >= 1 else "all air"
        return f"the box {detail['box']} is {state}: it does not touch the part's surface"
    if kind == "thickness":
        return (
            f"measures {detail['measured_mm']} mm from {detail['enters_at']}; "
            f"{detail['expected_mm']} ± {detail['tolerance_mm']} was declared"
        )
    wrong = [
        f"Ø{c['measured_mm']} at {c['depth_mm']:g} mm from the mouth "
        f"(Ø{c['expected_mm']:g} declared)"
        for c in detail["diameters"]
        if not c["ok"]
    ]
    profile = ", ".join(f"{d:g}: {'-' if v is None else v}" for d, v in detail["profile"])
    wrong_text = "; ".join(wrong)
    return f"mouth at {detail['mouth']}; {wrong_text}. Measured profile (mm: Ø): {profile}"


def _diagnostics(what: str, result: dict[str, Any], reported: set[str]) -> list[str]:
    """G1: errors, failed asserts, timeouts and every OpenSCAD warning. None of the warnings
    seen in the first sessions was harmless: an unknown variable or module evaluates to undef or
    nothing and the part still exports. Each export repeats the evaluation warnings already
    listed for the compilation, so `reported` keeps each one to one line."""
    problems = [f"{what}: {e}" for e in result.get("errors", [])]
    for failed in result.get("asserts_failed", []):
        problems.append(
            f"{what}: failed assert {failed['condition']} at line {failed['line']}: "
            f"{failed['message']}"
        )
    new = [w for w in result.get("warnings", []) if w not in reported]
    reported.update(new)
    problems += [f"{what}: {w}" for w in new[:MAX_WARNINGS]]
    if len(new) > MAX_WARNINGS:
        problems.append(f"{what}: and {len(new) - MAX_WARNINGS} more warnings (see scad_compile)")
    if result.get("timed_out"):
        problems.append(f"{what}: OpenSCAD ran over the time limit")
    if not problems and not result.get("ok"):
        problems.append(f"{what}: failed ({result.get('error') or 'no output'})")
    return problems
