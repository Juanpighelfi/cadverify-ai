"""Offline tests of the cadcheck tools: OpenSCAD log parsing, -D literals and mesh_report.

The logs are verbatim OpenSCAD output (2021.01 and 2026.10 print them the same way).
"""

import argparse
import json
import math

import numpy as np
import pytest
import trimesh

from cadverify.cadcheck import mesh_report, scad_export
from cadverify.cadcheck.cli import _plain, parse_define
from cadverify.cadcheck.scad import MAX_LINES, parse_log
from cadverify.openscad import define_args, scad_literal
from cadverify.scad_source import customizer_options

WARNING_LOG = """\
ECHO: "valor", 1
WARNING: Ignoring unknown variable "y" in file warn.scad, line 3
ECHO: "fin 2"
"""

ASSERT_LOG = """\
ECHO: "top"
ERROR: Assertion '(v > 0)' failed: "v debe ser positivo, vale -1" in file assertmod.scad, line 1
TRACE: called by 'assert' in file assertmod.scad, line 1
TRACE: call of 'm(v = -1)' in file assertmod.scad, line 1
TRACE: called by 'm' in file assertmod.scad, line 3
Current top level object is empty.
"""

PARSER_LOG = """\
ERROR: Parser error: syntax error in file syntax.scad, line 2
Can't parse file 'syntax.scad'!
"""


def test_parse_log_splits_echo_and_warnings():
    assert parse_log(WARNING_LOG) == {
        "echo": ['"valor", 1', "fin 2"],
        "warnings": ['WARNING: Ignoring unknown variable "y" in file warn.scad, line 3'],
        "asserts_failed": [],
        "errors": [],
    }


def test_parse_log_reads_failed_assert_with_its_call_chain():
    diag = parse_log(ASSERT_LOG)
    assert diag["errors"] == []
    assert diag["asserts_failed"] == [
        {
            "condition": "(v > 0)",
            "message": "v debe ser positivo, vale -1",
            "file": "assertmod.scad",
            "line": 1,
            "trace": [
                "called by 'assert' in file assertmod.scad, line 1",
                "call of 'm(v = -1)' in file assertmod.scad, line 1",
                "called by 'm' in file assertmod.scad, line 3",
            ],
        }
    ]


def test_parse_log_assert_without_message():
    log = "ERROR: Assertion '(a < 3)' failed in file a.scad, line 7\n"
    (failed,) = parse_log(log)["asserts_failed"]
    assert failed["message"] is None and failed["line"] == 7


def test_parse_log_keeps_other_errors():
    diag = parse_log(PARSER_LOG)
    assert diag["errors"] == ["ERROR: Parser error: syntax error in file syntax.scad, line 2"]
    assert diag["asserts_failed"] == []


def test_parse_log_unquotes_only_single_strings():
    # Verbatim output of echo("x=2"), echo("a\\b"), echo("a", "b"), echo(3) and
    # echo("dice \"hola\""): OpenSCAD does not escape quotes or backslashes.
    log = 'ECHO: "x=2"\nECHO: "a\\b"\nECHO: "a", "b"\nECHO: 3\nECHO: "dice "hola""\n'
    assert parse_log(log)["echo"] == ["x=2", "a\\b", '"a", "b"', "3", '"dice "hola""']


def test_parse_log_dedupes_and_caps_repeated_messages():
    log = "WARNING: same\n" * 3 + "".join(f"WARNING: w{i}\n" for i in range(MAX_LINES + 5))
    warnings = parse_log(log)["warnings"]
    assert warnings[0] == "WARNING: same" and warnings.count("WARNING: same") == 1
    assert len(warnings) == MAX_LINES + 1 and warnings[-1] == "... 6 more lines"


def test_the_cli_prints_numpy_values_as_plain_json():
    result = {"a": np.bool_(True), "b": np.float32(1.5), "c": np.arange(3)}
    assert json.dumps(result, default=_plain) == '{"a": true, "b": 1.5, "c": [0, 1, 2]}'
    with pytest.raises(TypeError):
        json.dumps({"x": object()}, default=_plain)


def test_scad_literal():
    assert scad_literal(True) == "true"
    assert scad_literal(3) == "3"
    assert scad_literal(0.1) == "0.1"
    assert scad_literal(None) == "undef"
    assert scad_literal('a "b"\\\n') == '"a \\"b\\"\\\\\\n"'
    assert scad_literal([1, [2.5, "x"]]) == '[1, [2.5, "x"]]'
    with pytest.raises(ValueError):
        scad_literal(math.nan)
    with pytest.raises(TypeError):
        scad_literal({"a": 1})


def test_define_args_validates_names():
    assert define_args({"part": "key", "$fn": 32}) == ["-D", 'part="key"', "-D", "$fn=32"]
    with pytest.raises(ValueError):
        define_args({"a; cube(1)": 1})


def test_export_rejects_unsupported_format():
    with pytest.raises(ValueError, match="Unsupported format"):
        scad_export("model.scad", "llave", fmt="obj")


def test_parse_define():
    assert parse_define("thickness=2.5") == ("thickness", 2.5)
    assert parse_define("mostrar_soga=false") == ("mostrar_soga", False)
    assert parse_define("v=[1, 2]") == ("v", [1, 2])
    assert parse_define("part=lid") == ("part", "lid")
    with pytest.raises(argparse.ArgumentTypeError):
        parse_define("part")


def test_customizer_options():
    code = """\
part = "a"; // [a, b:Part B, c]
spread = 0; // [0:5:120]
no_range = 2;
"""
    assert customizer_options(code, "part") == ["a", "b", "c"]
    assert customizer_options(code, "spread") == []
    assert customizer_options(code, "no_range") == []
    assert customizer_options(code, "other") == []


def _report(tmp_path, mesh):
    """mesh_report of an ASCII STL written with full double precision, as OpenSCAD writes it."""
    lines = ["solid part"]
    for triangle in mesh.triangles:
        lines += ["facet normal 0 0 0", "outer loop"]
        lines += [f"vertex {x!r} {y!r} {z!r}" for x, y, z in triangle.tolist()]
        lines += ["endloop", "endfacet"]
    path = tmp_path / "part.stl"
    path.write_text("\n".join([*lines, "endsolid part"]) + "\n")
    return mesh_report(path)


def test_mesh_report_closed_box(tmp_path):
    report = _report(tmp_path, trimesh.creation.box((10, 20, 5)))
    assert report["watertight"] and report["winding_consistent"]
    assert report["bad_edges"] == 0 and report["bad_edge_locations"] == []
    assert report["volume_mm3"] == 1000
    assert report["size"] == [10, 20, 5]
    assert report["bounds"] == [[-5, -10, -2.5], [5, 10, 2.5]]
    assert (report["bodies"], report["cavities"], report["inverted_shells"]) == (1, 0, 0)


def test_mesh_report_locates_holes(tmp_path):
    box = trimesh.creation.box((10, 10, 10))
    open_box = trimesh.Trimesh(box.vertices, box.faces[1:], process=False)
    report = _report(tmp_path, open_box)
    assert not report["watertight"]
    assert report["bad_edges"] == 3 and len(report["bad_edge_locations"]) == 3


def test_mesh_report_counts_bodies_cavities_and_inverted_shells(tmp_path):
    def box(size, offset=(0, 0, 0)):
        return trimesh.creation.box((size,) * 3).apply_translation(offset)

    cavity = box(4)
    cavity.invert()
    hollow = _report(tmp_path, trimesh.util.concatenate([box(10), cavity]))
    assert (hollow["bodies"], hollow["cavities"], hollow["inverted_shells"]) == (1, 1, 0)
    assert hollow["volume_mm3"] == 1000 - 64

    two = _report(tmp_path, trimesh.util.concatenate([box(1), box(1, (5, 0, 0))]))
    assert (two["bodies"], two["cavities"], two["inverted_shells"]) == (2, 0, 0)

    inside_out = box(10)
    inside_out.invert()
    inverted = _report(tmp_path, inside_out)
    assert inverted["watertight"] and inverted["volume_mm3"] == -1000
    assert (inverted["bodies"], inverted["cavities"], inverted["inverted_shells"]) == (0, 0, 1)


def test_mesh_report_does_not_fuse_nearly_coincident_vertices(tmp_path):
    # OpenSCAD 2026.10 writes distinct vertices 1e-9 mm apart; a tolerance merge would fuse
    # these two cubes into one mesh with non-manifold edges.
    a = trimesh.creation.box((1, 1, 1))
    b = trimesh.creation.box((1, 1, 1)).apply_translation((1 + 1e-9, 0, 0))
    report = _report(tmp_path, trimesh.util.concatenate([a, b]))
    assert report["watertight"] and report["bad_edges"] == 0
    assert report["bodies"] == 2


def test_mesh_report_empty_mesh(tmp_path):
    path = tmp_path / "empty.stl"
    path.write_text("solid empty\nendsolid empty\n")
    assert mesh_report(path)["triangles"] == 0


def test_winding_number_of_closed_box():
    from cadverify.cadcheck.mesh import _winding_number

    box = trimesh.creation.box((2, 2, 2))
    assert _winding_number(np.zeros(3), box.triangles) == pytest.approx(1)
    assert _winding_number(np.array([5.0, 0, 0]), box.triangles) == pytest.approx(0)
