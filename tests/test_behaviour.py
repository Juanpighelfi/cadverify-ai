"""G6 (cadcheck.behaviour, cadcheck.fea), against closed forms. The solver needs gmsh's libraries,
as in the sandbox image; the spec, the gate and the replay run anywhere."""

import json
import math
import os
import signal
import time

import numpy as np
import pytest
import trimesh

from cadverify.agent.closing import reference_problems, registry, summary
from cadverify.agent.gates import behaviour_problems
from cadverify.agent.spec_history import SpecHistory
from cadverify.cadcheck.materials import MATERIALS, POISSON
from cadverify.cadcheck.spec import SpecError, parse_spec
from cadverify.replay import _behaviour

in_sandbox = pytest.mark.skipif(
    os.environ.get("CADVERIFY_SANDBOX") != "1", reason="runs inside the sandbox image"
)
PLA = MATERIALS["PLA"]


# ---- materials and spec ---------------------------------------------------------------------


def test_every_material_has_its_sources_and_its_limits():
    for material in MATERIALS.values():
        assert len(material.sources) >= 3
        assert all("http" in source for source in material.sources)
        assert 0 < material.strain_repeated < material.strain_once < 0.1
        assert 0 < material.z_factor < 1
    assert PLA.strain_once == pytest.approx(76 / 2750)
    assert PLA.strain_repeated == pytest.approx(76 / 2750 / 2)


def _spec(**extra):
    return {"bounds": [[0, 0, 0], [10, 10, 10]], "bodies": 1, "through_holes": 0, **extra}


def _parse(extra):
    pairs = [[k, v] for k, v in _spec(**extra).items()]
    return parse_spec(json.dumps(pairs))


def test_a_material_a_load_and_a_stability_in_a_spec():
    box = [[0, 0, 0], [1, 1, 1]]
    spec = _parse(
        {
            "material": "PETG",
            "loads": [
                ["shelf", box, ["weight_kg", 2, [0, 0, -1]], box, 3],
                ["push", box, [1, 0, 0], box],
            ],
            "stability": [["stands", [0, 0, -1], [[0.5, [0, 0, 20]]], 8]],
        }
    )
    assert spec["material"] == "PETG"
    shelf, push = spec["loads"]
    assert shelf["force"] == pytest.approx([0, 0, -2 * 9.81])
    assert shelf["max_deflection_mm"] == 3
    assert push.get("max_deflection_mm") is None
    assert spec["stability"][0]["carries"] == [{"kg": 0.5, "at": [0, 0, 20]}]
    assert spec["stability"][0]["min_tilt_deg"] == 8


@pytest.mark.parametrize(
    "extra",
    [
        {"material": "wood"},
        {"loads": [["no force", [[0, 0, 0], [1, 1, 1]], [0, 0, 0], [[0, 0, 0], [1, 1, 1]]]]},
        {"loads": [["no held", [[0, 0, 0], [1, 1, 1]], [1, 0, 0]]]},
        {"stability": [["no down", [0, 0, 0], []]]},
    ],
)
def test_what_a_behaviour_key_must_say(extra):
    with pytest.raises(SpecError):
        _parse(extra)


# ---- the gate, never green by omission --------------------------------------------------------


def test_without_a_report_the_gate_is_red():
    assert behaviour_problems({}) == ["the verification did not compute the behaviour"]
    assert behaviour_problems({"behaviour": {"problems": ["over"]}}) == ["over"]
    assert behaviour_problems({"behaviour": {"problems": []}}) == []


def _report(ok=True):
    part = {
        "instance": "arm",
        "material": "PLA",
        "deflection_mm": 0.6,
        "strain_pct": 1.0 if ok else 6.2,
        "limit_pct": 1.38,
        "z_strain_pct": 0.1,
        "z_limit_pct": 0.69,
        "tets": 1000,
        "picture_png": "AAAA",
    }
    flex = {
        "where": "motion turn",
        "a": "arm",
        "b": "wheel",
        "depth_mm": 0.7,
        "force_n": 4.0,
        "force_target_n": [2, 6],
        "use": "repeated",
        "ok": ok,
        "parts": [part],
    }
    return {
        "declared": True,
        "ok": ok,
        "problems": [] if ok else ["motion turn, flex arm / wheel: over the limit"],
        "flex": [flex],
        "loads": [
            {
                "name": "shelf",
                "on": "base",
                "ok": ok,
                "force_n": 19.62,
                "largest_mm": 0.4,
                "max_deflection_mm": 3,
                **part,
            }
        ],
        "stability": [
            {
                "name": "stands",
                "on": "base",
                "ok": ok,
                "min_tilt_deg": 5,
                "worst": {"fill": 0.3, "margin_mm": 12.0, "tilt_deg": 20.0, "height_mm": 30.0},
            }
        ],
        "materials": {"PLA": PLA.public()},
    }


def test_the_auditor_reads_the_numbers_without_the_pictures():
    state = {
        "gates": {"G1": {"ok": True, "detail": []}, "G6": {"ok": True, "detail": []}},
        "parts": [],
        "behaviour": _report(),
    }
    verified = summary(state)
    text = json.dumps(verified)
    assert "picture" not in text
    assert verified["behaviour"]["flex"][0]["force_n"] == 4.0
    assert verified["behaviour"]["loads"][0]["name"] == "shelf"


def test_a_close_cites_what_g6_computed_only_when_it_is_green():
    state = {"gates": {"G5": {"ok": True, "detail": []}}, "parts": [], "behaviour": _report()}
    assert {"flex arm/wheel", "shelf", "stands"} <= set(registry(state))
    text = "It holds [[shelf]], stays up [[stands]] and rides over [[flex arm/wheel]]."
    assert reference_problems(text, state) == []
    state["behaviour"] = _report(ok=False)
    assert len(reference_problems(text, state)) == 3


def test_the_replay_shows_the_numbers_and_the_picture():
    page = _behaviour({"behaviour": _report()})
    assert "4.0 N" in page and "target 2 to 6 N" in page and "data:image/png;base64,AAAA" in page
    assert "within limits" in page and "20.0° before it tips" in page
    assert "over a limit" not in page
    red = _behaviour({"behaviour": _report(ok=False)})
    assert 'class="over">6.20 / 1.38' in red and "over a limit" in red
    assert "over the limit" in red


def test_a_session_recorded_before_g6_has_no_section():
    assert _behaviour({}) == ""
    assert _behaviour({"behaviour": {"declared": False}}) == ""


def _load_report(force=19.62, ok=True, strain=1.0):
    row = {"name": "shelf", "on": "base", "ok": ok, "force_n": force, "material": "PLA"}
    return {"declared": True, "ok": ok, "problems": [], "loads": [{**row, "strain_pct": strain}]}


def test_a_load_made_lighter_so_it_passes_is_an_adjustment():
    history = SpecHistory()
    assert history.observe_behaviour(_load_report(ok=False, strain=3.0)) == []
    found = history.observe_behaviour(_load_report(force=5.0, ok=True, strain=0.8))
    assert len(found) == 1 and found[0]["item"] == "load shelf on base"
    assert "5.0" in found[0]["text"]
    assert history.observe_behaviour(_load_report(force=5.0, ok=True, strain=0.8)) == []


def test_a_part_made_stronger_for_the_same_load_is_not_an_adjustment():
    history = SpecHistory()
    history.observe_behaviour(_load_report(ok=False, strain=3.0))
    assert history.observe_behaviour(_load_report(ok=True, strain=1.0)) == []


def test_a_red_load_taken_out_of_the_spec_is_an_adjustment():
    history = SpecHistory()
    history.observe_behaviour(_load_report(ok=False, strain=3.0))
    found = history.observe_behaviour({"declared": True, "problems": [], "loads": []})
    assert len(found) == 1 and "removed" in found[0]["text"]


def test_a_force_target_widened_around_the_same_force_is_an_adjustment():
    def report(target, ok):
        flex = {"where": "motion a", "a": "x", "b": "y", "force_n": 9.0, "ok": ok, "parts": []}
        return {"declared": True, "flex": [{**flex, "force_target_n": target}], "problems": []}

    history = SpecHistory()
    history.observe_behaviour(report([2, 6], False))
    found = history.observe_behaviour(report([2, 12], True))
    assert len(found) == 1 and "[2, 12]" in found[0]["text"]


# ---- the solver, against closed forms ----------------------------------------------------------


def _beam(length: float, thick: float, width: float, root: float = 6.0) -> trimesh.Trimesh:
    """A straight cantilever along +X, its root in a block, its top face up in Z."""
    beam = trimesh.creation.box(extents=(length + root, width, thick))
    beam.apply_translation(((length - root) / 2, 0, 0))
    return beam


def _beam_unit(length, thick, width, modulus=2750.0, poisson=POISSON, scale=1.0):
    from cadverify.cadcheck import fea

    mesh = _beam(length, thick, width)
    tip_points = mesh.vertices[mesh.vertices[:, 0] > length - 1e-6]
    tets = fea.filled(mesh, tip_points, 0.5, scale)

    def loaded(centers):
        return centers[:, 0] >= length - 1e-6

    def fixed(centers):
        return centers[:, 0] <= 1e-6 - 6.0 + 1e-3

    return fea.solve_unit(tets, modulus, poisson, loaded, fixed, direction=np.array([0, 0, -1.0]))


@in_sandbox
@pytest.mark.parametrize("length,thick,width", [(20.0, 2.0, 6.0), (10.0, 1.0, 5.0)])
def test_a_cantilever_against_its_closed_form(length, thick, width):
    from cadverify.cadcheck import fea

    length_total = length + 6.0  # held at the back of the block, the whole bar bends
    unit = _beam_unit(length, thick, width)
    inertia = width * thick**3 / 12
    assert unit.compliance == pytest.approx(length_total**3 / (3 * 2750 * inertia), rel=0.10)
    peak = fea.peaks(unit, 1.0, 2750.0, np.array([0.0, 0.0, 1.0]))
    # The tension over a 0.4 mm line, away from where it is held.
    expected = (length_total - 0.4) * (thick / 2) / inertia
    assert peak["tension_mpa"] == pytest.approx(expected, rel=0.15)


@in_sandbox
def test_a_finer_mesh_moves_a_cantilever_under_ten_percent():
    coarse = _beam_unit(20.0, 2.0, 6.0)
    fine = _beam_unit(20.0, 2.0, 6.0, scale=0.7)
    assert abs(fine.compliance - coarse.compliance) / fine.compliance < 0.10


@in_sandbox
def test_the_solver_is_deterministic():
    from cadverify.cadcheck import fea

    up = np.array([0.0, 0.0, 1.0])
    first, second = _beam_unit(10.0, 1.0, 5.0), _beam_unit(10.0, 1.0, 5.0)
    assert first.compliance == second.compliance
    assert fea.peaks(first, 1.0, 2750.0, up) == fea.peaks(second, 1.0, 2750.0, up)


@in_sandbox
def test_what_poissons_ratio_moves_on_a_cantilever():
    from cadverify.cadcheck import fea

    up = np.array([0.0, 0.0, 1.0])
    low = _beam_unit(20.0, 2.0, 6.0, poisson=0.30)
    high = _beam_unit(20.0, 2.0, 6.0, poisson=0.40)
    assert abs(high.compliance - low.compliance) / low.compliance < 0.03
    a, b = fea.peaks(low, 1.0, 2750.0, up), fea.peaks(high, 1.0, 2750.0, up)
    assert abs(a["tension_mpa"] - b["tension_mpa"]) / a["tension_mpa"] < 0.05


@in_sandbox
def test_two_springs_in_series_share_the_depth():
    """One beam of thickness t against one of 2t: the force from their compliances, each deflecting
    its share, the softer almost all of it (8 to 1 by the closed form)."""
    from cadverify.cadcheck import behaviour

    soft, stiff = _beam(20.0, 1.5, 6.0, root=0.0), _beam(20.0, 3.0, 6.0, root=0.0)
    soft.apply_translation((-20.0, 0, 0))
    stiff.apply_transform(trimesh.transformations.rotation_matrix(math.pi, (0, 1, 0)))
    stiff.apply_translation((0.0, 0, 2.25 - 0.1))
    # The overlap of the two tips, as G4 measures it.
    overlap = trimesh.creation.box(extents=(1.0, 6.0, 0.1))
    overlap.apply_translation((-0.5, 0, 0.7))
    a = behaviour._contact(soft, overlap, PLA)["compliance"]
    b = behaviour._contact(stiff, overlap, PLA)["compliance"]
    assert a / b == pytest.approx(8.0, rel=0.35)


# ---- what happens when it cannot be computed --------------------------------------------------


def _hanging(*_args, **kwargs):
    """A report half written, and then a solver that does not come back."""
    kwargs["save"].write_text(
        json.dumps(
            {"ok": False, "declared": True, "problems": [], "flex": [{"a": "x"}], "loads": []}
        )
    )
    time.sleep(60)


def _dying(*_args, **_kwargs):
    os._exit(137)  # what running out of memory looks like from here


def _raising(*_args, **_kwargs):
    raise ValueError("a bad mesh")


@pytest.mark.parametrize(
    "work,says",
    [
        ("_hanging", "ran over its 2 s of CPU, or hung"),
        ("_dying", "died (exit 137)"),
        ("_raising", "ValueError: a bad mesh"),
    ],
)
def test_a_solver_that_fails_leaves_the_gate_red_and_the_verification_alive(tmp_path, work, says):
    from cadverify.cadcheck import verify

    started = time.perf_counter()
    report = verify.behaviour_of(
        {"parts": []}, tmp_path, "PLA", False, 2.0, compute=f"tests.test_behaviour:{work}"
    )
    assert time.perf_counter() - started < 20
    assert report["ok"] is False and any(says in p for p in report["problems"])
    assert behaviour_problems({"behaviour": report})
    if work == "_hanging":
        assert report["flex"] == [{"a": "x"}]  # what was computed until then


def _spins(*_args, **kwargs):
    kwargs["save"].write_text(json.dumps({"ok": False, "problems": [], "flex": [], "loads": []}))
    while True:
        pass


def test_the_limit_is_in_cpu_so_a_solver_that_spins_is_stopped_by_it(tmp_path):
    from cadverify.cadcheck import verify

    report = verify.behaviour_of(
        {"parts": []}, tmp_path, "PLA", False, 2.0, compute="tests.test_behaviour:_spins"
    )
    assert any("ran over its 2 s of CPU" in p for p in report["problems"])


@pytest.mark.parametrize(
    "strain,moved,follows,red",
    [
        (0.3, {"compliance": 0.36, "strain": 0.29, "z_strain": 0.0}, True, False),  # far under
        (1.8, {"compliance": 0.05, "strain": 0.30, "z_strain": 0.0}, True, True),  # could cross
        (
            1.8,
            {"compliance": 0.30, "strain": 0.05, "z_strain": 0.0},
            True,
            True,
        ),  # through the force
        (
            1.8,
            {"compliance": 0.30, "strain": 0.05, "z_strain": 0.0},
            False,
            False,
        ),  # a load's force
        (9.0, {"compliance": 0.30, "strain": 0.20, "z_strain": 0.0}, True, False),  # far over
        (1.8, {"compliance": 0.05, "strain": 0.04, "z_strain": 0.0}, True, False),  # settled
    ],
)
def test_a_number_that_moved_is_red_only_if_its_verdict_could_change(strain, moved, follows, red):
    from cadverify.cadcheck.behaviour import _unsettled

    part = {"strain_pct": strain, "limit_pct": 2.26, "z_strain_pct": 0.0, "z_limit_pct": 1.0}
    assert _unsettled(part, moved, follows) is red


def _segfault(_gmsh, _field):
    os.kill(os.getpid(), signal.SIGSEGV)


@in_sandbox
def test_gmsh_dying_is_a_failed_attempt_and_the_next_one_runs(monkeypatch):
    from cadverify.cadcheck import fea

    box = trimesh.creation.box((20.0, 6.0, 2.0))
    with pytest.raises(RuntimeError, match="gmsh died"):
        fea._isolated(box, lambda p: np.full(len(p), 2.0), _segfault)
    monkeypatch.setattr(fea, "_remeshed", _segfault)
    tets = fea.tetrahedra(box, lambda p: np.full(len(p), 2.0))
    assert tets.method == "its own surface"
    assert fea._tets_volume(tets.points, tets.tets) == pytest.approx(box.volume, rel=0.01)


@in_sandbox
def test_a_surface_gmsh_keeps_is_split_to_the_mesh_size():
    from cadverify.cadcheck import fea

    box = trimesh.creation.box((60.0, 20.0, 4.0))
    coarse = fea._split(box, lambda p: np.full(len(p), 8.0))
    fine = fea._split(box, lambda p: np.full(len(p), 2.0))
    assert len(box.faces) < len(coarse.faces) < len(fine.faces)
    assert fine.is_watertight
    assert fine.volume == pytest.approx(box.volume)
    assert fine.edges_unique_length.max() < 2 * 2.0  # refine_to_length is about that length


@in_sandbox
def test_a_strain_picture_looks_from_where_the_peak_can_be_seen():
    from cadverify.cadcheck import fea

    plate = trimesh.creation.box((40.0, 40.0, 3.0))
    plate.apply_translation((0.0, 0.0, 1.5))
    arm = trimesh.creation.box((20.0, 6.0, 2.0))
    arm.apply_translation((0.0, 0.0, 4.6))
    part = trimesh.util.concatenate([plate, arm])

    under_the_arm = np.array([0.0, 0.0, 3.6])
    eye = fea.clear_view(part, under_the_arm, np.array([0.0, 0.0, -1.0]))
    assert abs(eye[2]) < 0.01  # along the gap: above it is the arm, below it the plate
    assert fea.faces_ahead(part.triangles, under_the_arm - [0.0, 0.0, 0.05], eye) == 0

    on_top = np.array([0.0, 0.0, 5.6])
    eye = fea.clear_view(part, on_top, np.array([0.0, 0.0, 1.0]))
    assert eye[2] > 0.7  # free to look at it along its own normal
    assert fea.faces_ahead(part.triangles, on_top, np.array([0.0, 0.0, -1.0])) > 0


@in_sandbox
def test_a_strain_picture_has_no_back_faces_to_flag(tmp_path):
    from PIL import Image

    from cadverify.cadcheck import fea
    from cadverify.cadcheck.render import BACK

    box = trimesh.creation.box((20.0, 6.0, 2.0))
    box.apply_translation((10.0, 0.0, 0.0))
    unit = fea.solve_unit(
        fea.filled(box, box.vertices[box.vertices[:, 0] > 20 - 1e-6], 2.0),
        2750.0,
        0.35,
        lambda c: c[:, 0] > 20 - 1e-6,
        lambda c: c[:, 0] < 1e-6,
        direction=np.array([0.0, 0.0, 1.0]),
    )
    strain = np.linalg.norm(unit.stress, axis=(1, 2)) / 2750.0
    out = tmp_path / "strain.png"
    fea.draw_strain(unit, strain, float(strain.max()), unit.points[0], out, "a caption")
    pixels = np.asarray(Image.open(out).convert("RGB"), dtype=float) / 255
    assert not (np.abs(pixels - np.array(BACK)).sum(axis=2) < 0.12).any()


def _a_sheet(folder):
    from cadverify.cadcheck.render import render_sheet

    folder.mkdir(parents=True, exist_ok=True)
    stl = folder / "cube.stl"
    trimesh.creation.box((10, 10, 10)).export(stl)
    return render_sheet(stl, folder / "sheet.png")


def _draws(_assembly, _parts, out_dir, _material, **kwargs):
    from pathlib import Path

    drawn = _a_sheet(Path(out_dir) / "child")
    report = {"ok": True, "problems": [], "flex": [], "loads": [], "drawn": drawn["ok"]}
    kwargs["save"].write_text(json.dumps({**report, "seconds": 0}))


@in_sandbox
def test_a_context_opened_before_g6_does_not_hang_its_pictures(tmp_path):
    """The sheets open OpenGL first. A forked child that drew through it waited forever in
    glReadPixels, with no CPU, and 16 of 23 recorded sessions ran out of time on it."""
    from cadverify.cadcheck import verify

    assert _a_sheet(tmp_path / "parent")["ok"]
    report = verify.behaviour_of(
        {"parts": []}, tmp_path, "PLA", False, 30.0, compute="tests.test_behaviour:_draws"
    )
    assert report["ok"] is True, report["problems"]
    assert report["drawn"] is True


# ---- loads and stability ----------------------------------------------------------------------


def _shelf_load(force=(0.0, 0.0, -5.0), bound=None):
    length = 40.0
    box = [[length - 2, -10, 0], [length + 1, 10, 3]]
    held = [[-1, -10, -3], [0.001, 10, 3]]
    out = {"name": "shelf", "box": box, "force": list(force), "fixed": held}
    if bound is not None:
        out["max_deflection_mm"] = bound
    return out, length


def _bar(length=40.0, width=10.0, thick=3.0):
    bar = trimesh.creation.box(extents=(length, width, thick))
    bar.apply_translation((length / 2, 0, thick / 2))
    return bar


@in_sandbox
def test_a_load_on_a_bar_against_its_closed_form():
    from cadverify.cadcheck import behaviour

    load, length = _shelf_load()
    problems = []
    row = behaviour._load(load, _bar(), PLA, np.array([0, 0, 1.0]), "bar", {}, problems)
    inertia = 10 * 3**3 / 12
    assert row["force_n"] == 5.0
    assert row["largest_mm"] == pytest.approx(5 * length**3 / (3 * 2750 * inertia), rel=0.2)
    assert row["ok"] and not problems


@in_sandbox
def test_a_load_past_its_deflection_and_a_load_pulling_layers_apart_are_red():
    from cadverify.cadcheck import behaviour

    load, _ = _shelf_load(bound=0.001)
    problems = []
    row = behaviour._load(load, _bar(), PLA, np.array([0, 0, 1.0]), "bar", {}, problems)
    assert not row["ok"] and "past the 0.001 mm" in problems[0]
    # The same bar printed standing up: its bending is across the layers, at half the limit.
    load, _ = _shelf_load(force=(0.0, 0.0, -40.0))
    flat, standing = [], []
    behaviour._load(load, _bar(), PLA, np.array([0, 0, 1.0]), "bar", {}, flat)
    behaviour._load(load, _bar(), PLA, np.array([1.0, 0, 0]), "bar", {}, standing)
    assert any("pulls its layers apart" in p for p in standing)
    assert not any("pulls its layers apart" in p for p in flat)


def test_a_load_that_touches_nothing_is_red_not_green():
    pytest.importorskip("gmsh", exc_type=ImportError)
    if os.environ.get("CADVERIFY_SANDBOX") != "1":
        pytest.skip("runs inside the sandbox image")
    from cadverify.cadcheck import behaviour

    load, _ = _shelf_load()
    load["box"] = [[500, 500, 500], [501, 501, 501]]
    problems = []
    row = behaviour._load(load, _bar(), PLA, np.array([0, 0, 1.0]), "bar", {}, problems)
    assert not row["ok"] and "could not be computed" in problems[0]


def _tower(width=20.0, height=100.0):
    tower = trimesh.creation.box(extents=(width, width, height))
    tower.apply_translation((0, 0, height / 2))
    return tower


def test_stability_of_a_tower_against_its_closed_form():
    from cadverify.cadcheck import behaviour

    item = {"name": "stands", "down": [0, 0, -1], "carries": []}
    problems = []
    row = behaviour._stability(item, [_tower()], PLA, "tower", {}, problems)
    assert row["worst"]["margin_mm"] == pytest.approx(10.0, abs=0.01)
    assert row["worst"]["tilt_deg"] == pytest.approx(math.degrees(math.atan(10 / 50)), abs=0.1)
    assert row["ok"] and not problems


def test_what_it_carries_can_tip_it():
    from cadverify.cadcheck import behaviour

    item = {"name": "phone", "down": [0, 0, -1], "carries": [{"kg": 1.0, "at": [40.0, 0, 100.0]}]}
    problems = []
    row = behaviour._stability(item, [_tower()], PLA, "tower", {}, problems)
    assert row["worst"]["margin_mm"] < 0 and not row["ok"]
    assert "it tips" in problems[0]


def test_a_stability_without_a_material_is_red():
    from cadverify.cadcheck import behaviour

    item = {"name": "stands", "down": [0, 0, -1], "carries": []}
    problems = []
    assert not behaviour._stability(item, [_tower()], None, "tower", {}, problems)["ok"]
    assert "no material" in problems[0]


def test_alignment_finds_how_a_part_was_turned():
    from cadverify.cadcheck import behaviour

    part = trimesh.creation.box(extents=(30, 10, 3))
    turn = trimesh.transformations.rotation_matrix(math.pi / 2, (1, 0, 0))
    moved = part.copy()
    moved.apply_transform(turn)
    rotation = behaviour.alignment(part, moved)
    assert np.abs(rotation @ np.array([0, 0, 1.0])) == pytest.approx(
        np.abs(turn[:3, :3] @ np.array([0, 0, 1.0])), abs=1e-6
    )
