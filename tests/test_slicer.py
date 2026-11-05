"""cadcheck.slicer: a real slicer on real meshes, in the sandbox image; the gate and the replay
anywhere."""

import json
import os

import numpy as np
import pytest
import trimesh

from cadverify.agent.gates import slice_problems
from cadverify.replay import _slices

in_sandbox = pytest.mark.skipif(
    os.environ.get("CADVERIFY_SANDBOX") != "1", reason="runs inside the sandbox image"
)


def _part_with_fin(path, fin_mm: float):
    """A plate with a base along its fin, so that the print goes on after losing the fin."""
    from cadverify.cadcheck import section

    def box(size, center):
        mesh = trimesh.creation.box(size)
        mesh.apply_translation(center)
        return section.to_manifold(mesh)

    solid = (
        box((30, 30, 2), (15, 15, 1))
        + box((30, 6, 2), (55, 15, 1))
        + box((30, fin_mm, 10), (55, 15, 5))
    )
    out = solid.to_mesh()
    mesh = trimesh.Trimesh(np.asarray(out.vert_properties)[:, :3], np.asarray(out.tri_verts))
    mesh.export(path)
    return path


@in_sandbox
def test_a_wall_the_slicer_loses_is_found_and_one_it_prints_is_not(tmp_path):
    from cadverify.cadcheck.slicer import slice_report

    lost = slice_report(_part_with_fin(tmp_path / "thin.stl", 0.08), tmp_path / "a", "PLA")
    assert lost["ok"] and lost["lost"], lost
    assert lost["lost"][0]["layers"] > 20
    assert lost["lost"][0]["area_mm2"] == pytest.approx(2.4, abs=0.2)
    problems = slice_problems(lost)
    assert problems and "does not print part of what you drew" in problems[0]
    printed = slice_report(_part_with_fin(tmp_path / "ok.stl", 0.8), tmp_path / "b", "PLA")
    assert printed["ok"] and printed["lost"] == [], printed
    assert slice_problems(printed) == []
    assert printed["lines_in_thinnest_wall"] == pytest.approx(0.8 / 0.42, abs=0.3)


@in_sandbox
def test_its_grams_follow_the_volume_and_the_material_and_it_is_deterministic(tmp_path):
    from cadverify.cadcheck.slicer import slice_report

    stl = tmp_path / "cube.stl"
    cube = trimesh.creation.box((20, 20, 20))
    cube.apply_translation((10, 10, 10))
    cube.export(stl)
    pla = slice_report(stl, tmp_path / "pla", "PLA")
    again = slice_report(stl, tmp_path / "again", "PLA")
    petg = slice_report(stl, tmp_path / "petg", "PETG")
    for key in ("grams", "hours", "filament_m", "lost", "extruded_vs_section"):
        assert pla[key] == again[key]
    # a cube of 8 cm3 in PLA, 15% infill: more than the walls alone, less than solid
    assert 2 < pla["grams"] < 8 * 1.24
    assert 0 < pla["hours"] < 1
    assert petg["grams"] / pla["grams"] == pytest.approx(1.25 / 1.24, abs=0.03)
    assert pla["material_assumed"] is False
    assert slice_report(stl, tmp_path / "x", None)["material_assumed"] is True


@in_sandbox
def test_a_file_that_is_not_a_mesh_fails_as_a_slice_never_as_a_pass(tmp_path):
    from cadverify.cadcheck.verify import slice_of

    bad = tmp_path / "bad.stl"
    bad.write_text("solid nothing\nendsolid nothing\n")
    report = slice_of(str(bad), tmp_path / "out", "PLA")
    assert report["ok"] is False and report["error"]
    assert slice_problems(report)


def test_the_gate_is_red_without_a_slice_and_when_it_could_not_compare():
    assert "did not run" in slice_problems(None)[0]
    assert "could not slice" in slice_problems({"ok": False, "error": "no"})[0]
    not_compared = {"ok": True, "not_compared": "the mesh is not a closed solid"}
    assert "could not be compared" in slice_problems(not_compared)[0]


def test_the_replay_says_grams_hours_and_what_was_lost():
    final = {
        "parts": [
            {
                "part": "lid",
                "slice": {
                    "ok": True,
                    "engine": "PrusaSlicer 2.9.2",
                    "grams": 12.34,
                    "hours": 1.5,
                    "thinnest_wall_mm": 0.8,
                    "lines_in_thinnest_wall": 1.9,
                    "lost": [{"area_mm2": 2.4, "z": 2.1, "z_to": 9.9}],
                },
            },
            {"part": "base", "slice": {"ok": False, "error": "it <broke>"}},
        ]
    }
    page = _slices(final)
    assert "12.3" in page and "1.50" in page and "2.4 mm²" in page and "PrusaSlicer" in page
    assert "it &lt;broke&gt;" in page
    assert _slices({"parts": [{"part": "x"}]}) == ""
    assert json.dumps(final)  # a report is plain data
