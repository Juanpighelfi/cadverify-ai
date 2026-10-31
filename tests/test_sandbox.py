"""Integration tests of the sandbox image: they run only inside it (CADVERIFY_SANDBOX=1).

docker build -t cadverify-sandbox .
docker run --rm -w /app cadverify-sandbox pytest -p no:cacheprovider
"""

import json
import os
import subprocess
import tomllib
from importlib import metadata
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from cadverify.cadcheck import scad_compile, scad_export

pytestmark = pytest.mark.skipif(
    os.environ.get("CADVERIFY_SANDBOX") != "1", reason="runs inside the sandbox image"
)

ROOT = Path(__file__).parents[1]


def test_pinned_openscad():
    proc = subprocess.run(["openscad", "--version"], capture_output=True, text=True)
    assert (proc.stdout + proc.stderr).strip() == "OpenSCAD version 2026.10.26"


def test_python_packages_match_the_pins():
    pins = tomllib.loads((ROOT / "pyproject.toml").read_text())["project"]["dependencies"]
    for pin in pins:
        name, version = pin.split("==")
        assert metadata.version(name) == version, name


def test_analysis_stack_works_headless(tmp_path):
    import manifold3d
    import matplotlib
    import matplotlib.pyplot as plt
    import scipy.spatial
    import shapely

    assert manifold3d.Manifold.cube((2, 2, 2)).volume() == pytest.approx(8)
    assert shapely.box(0, 0, 2, 3).area == 6
    assert scipy.spatial.ConvexHull([[0, 0], [1, 0], [0, 1]]).volume == pytest.approx(0.5)
    assert matplotlib.get_backend().lower() == "agg"
    plt.plot([0, 1], [0, 1])
    plt.savefig(tmp_path / "plot.png")
    assert Image.open(tmp_path / "plot.png").size[0] > 0


def _write(tmp_path, name, code):
    path = tmp_path / name
    path.write_text(code)
    return path


def test_compile_reports_echo_warnings_and_overrides(tmp_path):
    scad = _write(tmp_path, "w.scad", 'x = 1;\nname = "a";\necho(x, name);\ncube(y);\n')
    result = scad_compile(scad, {"x": 2.5, "name": 'with "quotes"'})
    assert result["ok"]
    assert result["echo"] == ['2.5, "with "quotes""']  # OpenSCAD prints strings raw
    assert result["warnings"] == ['WARNING: Ignoring unknown variable "y" in file w.scad, line 4']


def test_compile_fails_on_assert_even_though_openscad_exits_0(tmp_path):
    scad = _write(tmp_path, "a.scad", 'a = 5;\nassert(a < 3, "lower a");\ncube(a);\n')
    result = scad_compile(scad)
    assert result["returncode"] == 0
    assert not result["ok"]
    assert result["asserts_failed"][0]["message"] == "lower a"
    assert scad_compile(scad, {"a": 2})["ok"]


def test_compile_reports_parser_errors(tmp_path):
    result = scad_compile(_write(tmp_path, "s.scad", "cube(5)\nsphere(2;\n"))
    assert not result["ok"]
    assert result["errors"] == ["ERROR: Parser error: syntax error in file s.scad, line 2"]


def test_export_cube(tmp_path):
    result = scad_export(_write(tmp_path, "c.scad", "cube([10, 20, 5]);\n"))
    assert result["ok"] and Path(result["path"]).exists()
    mesh = result["mesh"]
    assert mesh["watertight"] and mesh["bad_edges"] == 0 and mesh["bodies"] == 1
    assert mesh["volume_mm3"] == 1000 and mesh["bounds"] == [[0, 0, 0], [10, 20, 5]]


def test_export_fails_on_empty_model_and_assert(tmp_path):
    empty = scad_export(_write(tmp_path, "e.scad", 'echo("nothing");\n'))
    assert not empty["ok"] and empty["empty"] and empty["path"] is None and empty["mesh"] is None
    failed = scad_export(_write(tmp_path, "a.scad", 'assert(false, "no");\ncube(1);\n'))
    assert not failed["ok"] and failed["asserts_failed"][0]["message"] == "no"


def test_png_render_without_display(tmp_path):
    scad = _write(tmp_path, "c.scad", "cube(10);\n")
    png = tmp_path / "egl.png"
    camera = ["--camera=0,0,0,55,0,25,0", "--viewall", "--autocenter"]
    cmd = ["openscad", "-o", str(png), "--render=true", *camera, str(scad)]
    subprocess.run(cmd, check=True, capture_output=True, timeout=120)
    assert len(Image.open(png).getcolors(1 << 16)) > 1


def test_png_render_under_xvfb(tmp_path):
    scad = _write(tmp_path, "c.scad", "cube(10);\n")
    png = tmp_path / "xvfb.png"
    cmd = ["xvfb-run", "-a", "openscad", "-o", str(png), "--render=true", str(scad)]
    subprocess.run(cmd, check=True, capture_output=True, timeout=120)
    assert len(Image.open(png).getcolors(1 << 16)) > 1


# ---- the tools ------------------------------------------------------------------------------

BRACKET = ROOT / "tests/fixtures/l_bracket_protrusion.scad"
# What the bracket means to be, in its own parameters and its print orientation (lying on the
# side): wall face on x = 0, shelf face on y = 0.
BRACKET_SPEC = """
echo(cadverify_spec = [
    ["bounds", [[0, 0, 0], [shelf_flange_length, wall_flange_height, bracket_width]]],
    ["bodies", 1],
    ["through_holes", 3],
    ["support_faces", [["wall", "-x", 0.8 * wall_flange_height * bracket_width],
                       ["shelf", "-y", 0.8 * shelf_flange_length * bracket_width]]]
]);
"""
# The fix: keep only the quadrant of the cylinder inside the corner (local x >= 0, y <= 0 before
# the module's rotate([90, 0, 0])).
FILLET = "            cylinder(r = inner_fillet_radius, h = bracket_width);"
FILLET_FIXED = (
    "            intersection() { cylinder(r = inner_fillet_radius, h = bracket_width);\n"
    "                translate([0, -inner_fillet_radius, 0])\n"
    "                    cube([inner_fillet_radius, inner_fillet_radius, bracket_width]); }"
)


def test_spec_check_catches_the_protruding_cylinder(tmp_path):
    scad = _write(tmp_path, "bracket.scad", BRACKET.read_text() + BRACKET_SPEC)
    result = scad_export(scad)
    mesh, check = result["mesh"], result["spec_check"]
    # The mesh is perfect: no compile or mesh check can see the defect.
    assert result["ok"] and mesh["watertight"] and mesh["bad_edges"] == 0
    assert (mesh["bodies"], mesh["inverted_shells"], mesh["through_holes"]) == (1, 0, 3)
    assert not check["ok"]
    assert check["bounds"]["deviations"] == [
        "min x: measured -2.000, specified 0 (off by -2.000 mm)",
        "min y: measured -2.000, specified 0 (off by -2.000 mm)",
    ]
    wall, shelf = check["support_faces"]
    for face in (wall, shelf):
        assert not face["ok"] and face["area_on_extreme_plane_mm2"] == 0
        assert face["protrusion_mm"] == 2.0
    assert wall["largest_flat_face"]["plane"] == "x = 0.000"


def test_spec_check_passes_the_fixed_bracket(tmp_path):
    source = BRACKET.read_text()
    assert source.count(FILLET) == 1
    fixed = source.replace(FILLET, FILLET_FIXED) + BRACKET_SPEC
    result = scad_export(_write(tmp_path, "bracket.scad", fixed))
    assert result["ok"] and result["spec_check"]["ok"], result["spec_check"]
    assert result["mesh"]["bounds"] == [[0, 0, 0], [130, 120, 50]]


def test_printability_of_the_bracket(tmp_path):
    from cadverify.cadcheck.printability import printability_report

    stl = scad_export(_write(tmp_path, "bracket.scad", BRACKET.read_text()))["path"]
    report = printability_report(stl)
    assert report["fits_bed"] and report["z_min"] == 0
    # Lying on its side, the three countersunk holes are horizontal: their tops overhang.
    assert report["zones_total"] == report["zones_undeclared"] >= 3
    everything = [{"name": "all", "bounds": [[-5, -5, -5], [140, 130, 60]]}]
    assert printability_report(stl, everything)["zones_undeclared"] == 0


def _sheet(tmp_path, code):
    from cadverify.cadcheck.render import render_sheet

    stl = scad_export(_write(tmp_path, "p.scad", code))["path"]
    result = render_sheet(stl, tmp_path / "sheet.png")
    assert result["ok"] and result["renderer"].startswith("llvmpipe")
    return result, np.asarray(Image.open(tmp_path / "sheet.png").convert("RGB")).astype(int)


def _count(pixels, rgb, tolerance=40):
    return int((np.abs(pixels - np.array(rgb)).sum(axis=2) < tolerance).sum())


def test_render_sheet_of_a_closed_part(tmp_path):
    code = (
        "difference() { cube([40, 30, 5]); translate([20, 15, -1]) cylinder(7, 3, 3, $fn = 32); }"
    )
    result, pixels = _sheet(tmp_path, code)
    assert result["size"] == [1800, 964] and pixels.shape == (964, 1800, 3)
    assert result["edges"] == {"sharp": 12 + 2 * 32, "open": 0, "nonmanifold": 0}
    tiles = pixels[64:]
    assert _count(tiles, (230, 13, 13)) == 0  # no red defect lines
    assert _count(tiles, (217, 64, 191)) == 0  # no magenta back faces
    assert _count(tiles, (0, 0, 0), tolerance=120) > 1000  # edges drawn


def test_render_sheet_shows_inverted_faces_in_magenta(tmp_path):
    # A polyhedron cube with every face listed the wrong way round.
    code = (
        "polyhedron(points = [[0,0,0],[10,0,0],[10,10,0],[0,10,0],"
        "[0,0,10],[10,0,10],[10,10,10],[0,10,10]], faces = [[3,2,1,0],[4,5,6,7],[0,1,5,4],"
        "[1,2,6,5],[2,3,7,6],[3,0,4,7]]);"
    )
    _, pixels = _sheet(tmp_path, code)
    assert _count(pixels[64:], (217, 64, 191), tolerance=60) > 10000


def test_render_sheet_draws_open_edges_in_red(tmp_path):
    from cadverify.cadcheck.render import render_sheet

    stl = tmp_path / "open.stl"
    stl.write_text(
        "solid o\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 10 0 0\nvertex 0 10 0\n"
        "endloop\nendfacet\nendsolid o\n"
    )
    result = render_sheet(stl, tmp_path / "sheet.png")
    assert result["edges"]["open"] == 3
    pixels = np.asarray(Image.open(tmp_path / "sheet.png").convert("RGB")).astype(int)
    assert _count(pixels[64:], (230, 13, 13), tolerance=60) > 500


def test_cadcheck_cli_write_patch_and_verify(tmp_path):
    def cadcheck(*args, stdin=""):
        proc = subprocess.run(
            ["cadcheck", *args], input=stdin, capture_output=True, text=True, cwd=tmp_path
        )
        return json.loads(proc.stdout)

    code = (
        'part = "assembly"; // [assembly, base, lid]\n'
        'echo(cadverify_spec = [["bounds", [[0, 0, 0], [20, 20, part == "lid" ? 2 : 10]]]]);\n'
        'if (part == "lid") cube([20, 20, 2]); else cube([20, 20, 10]);\n'
    )
    assert cadcheck("write", "m.scad", stdin=code)["ok"]
    assert not cadcheck("write", "../m.scad", stdin=code)["ok"]
    edit = json.dumps({"old": "cube([20, 20, 10])", "new": "cube([20, 20, 9])"})
    assert cadcheck("patch", "m.scad", stdin=edit)["line"] == 3
    verify = cadcheck("verify", "m.scad")
    assert verify["compile"]["ok"]
    parts = {p["part"]: p for p in verify["parts"]}
    assert set(parts) == {"base", "lid"}
    assert not parts["base"]["export"]["spec_check"]["ok"]  # 9 mm tall, the spec says 10
    assert parts["lid"]["export"]["spec_check"]["ok"]
    assert parts["lid"]["printability"]["zones_total"] == 0
