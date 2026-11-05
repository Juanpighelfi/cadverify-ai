"""`cadcheck`: run the tools from a shell and print their JSON result.

    cadcheck compile model.scad -D wall=2
    cadcheck export model.scad --part lid --out-dir exports
    cadcheck mesh exports/model.lid.1a2b3c4d.stl
    cadcheck sheet exports/model.lid.1a2b3c4d.stl --out renders/lid.png
    cadcheck view < request.json
    cadcheck printability exports/model.lid.1a2b3c4d.stl --allowed '[...]'
    cadcheck write model.scad < content.scad
    cadcheck patch model.scad < '{"old": "...", "new": "..."}'
    cadcheck verify model.scad --out-dir /out [--assembly] [--requirements '{"units": 2}']
    cadcheck assembly model.scad --out-dir checks/assembly [--requirements '{"units": 2}']
    cadcheck behaviour model.scad --out-dir checks/behaviour [--material PLA]
    cadcheck slice part.stl --out-dir checks/slices [--material PLA]
    cadcheck run < '{"kind": "shell", "code": "ls", "timeout_s": 60}'
    cadcheck reap
    cadcheck manifest
    cadcheck image plot.png --out renders/image-001.png --max-side 1568 --max-pixels 1800000

Every command exits with 1 when the result is not ok. Modules are imported per command, so
the light ones (run, reap, manifest) start fast.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def parse_define(text: str) -> tuple[str, Any]:
    """`name=value`; the value is read as JSON when it parses (2, true, [1, 2]), else as text."""
    name, sep, value = text.partition("=")
    if not sep or not name:
        raise argparse.ArgumentTypeError(f"expected name=value, got {text!r}")
    try:
        return name, json.loads(value)
    except json.JSONDecodeError:
        return name, value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cadcheck", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("compile", "export"):
        cmd = sub.add_parser(name)
        cmd.add_argument("scad")
        cmd.add_argument("-D", dest="defines", action="append", type=parse_define, default=[])
        cmd.add_argument("--timeout", type=float, default=120 if name == "compile" else 900)
        if name == "export":
            cmd.add_argument("--part")
            cmd.add_argument("--out-dir")
    sub.add_parser("mesh").add_argument("mesh")
    sheet = sub.add_parser("sheet")
    sheet.add_argument("mesh")
    sheet.add_argument("--out", required=True)
    sheet.add_argument("--views", help="comma-separated view names")
    sheet.add_argument("--title")
    printability = sub.add_parser("printability")
    printability.add_argument("mesh")
    printability.add_argument("--allowed", type=json.loads, default=[])
    for name in ("write", "patch"):
        sub.add_parser(name).add_argument("scad")
    verify_cmd = sub.add_parser("verify")
    verify_cmd.add_argument("scad")
    verify_cmd.add_argument("--out-dir")
    verify_cmd.add_argument("--assembly", action="store_true")
    verify_cmd.add_argument("--requirements", type=json.loads, default={})
    verify_cmd.add_argument("--material")
    assembly = sub.add_parser("assembly")
    assembly.add_argument("scad")
    assembly.add_argument("--out-dir", required=True)
    assembly.add_argument("--requirements", type=json.loads, default={})
    behaviour = sub.add_parser("behaviour")
    behaviour.add_argument("scad")
    behaviour.add_argument("--out-dir", required=True)
    behaviour.add_argument("--requirements", type=json.loads, default={})
    behaviour.add_argument("--material")
    slice_cmd = sub.add_parser("slice")
    slice_cmd.add_argument("mesh")
    slice_cmd.add_argument("--out-dir", required=True)
    slice_cmd.add_argument("--material")
    for name in ("view", "run", "reap", "manifest"):
        sub.add_parser(name)
    image = sub.add_parser("image")
    image.add_argument("source")
    image.add_argument("--out", required=True)
    image.add_argument("--max-side", type=int, required=True)
    image.add_argument("--max-pixels", type=int, required=True)
    args = parser.parse_args(argv)

    result = _dispatch(args)
    print(json.dumps(result, ensure_ascii=False, indent=2, default=_plain))
    return 0 if result.get("ok", True) else 1


def _plain(value: Any) -> Any:
    """A numpy number or array left in a result, as JSON: a tool that answers is worth more than
    one that fails on a type (render_view did, on a numpy bool, in an early session)."""
    import numpy as np

    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, np.ndarray):
        return value.tolist()
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def _dispatch(args: argparse.Namespace) -> dict[str, Any]:
    command = args.command
    if command in ("run", "reap", "manifest", "image"):
        from cadverify.cadcheck import run

        if command == "run":
            request = json.loads(sys.stdin.read())
            return run.run(**request)
        if command == "reap":
            return run.reap()
        if command == "manifest":
            return run.manifest()
        return run.normalize_image(args.source, args.out, args.max_side, args.max_pixels)
    if command == "write":
        from cadverify.cadcheck.files import scad_write

        return scad_write(args.scad, sys.stdin.read())
    if command == "patch":
        from cadverify.cadcheck.files import scad_patch

        edit = json.loads(sys.stdin.read())
        return scad_patch(args.scad, edit["old"], edit["new"])
    if command == "mesh":
        from cadverify.cadcheck.mesh import mesh_report

        return mesh_report(args.mesh)
    if command == "compile":
        from cadverify.cadcheck.scad import scad_compile

        return scad_compile(args.scad, dict(args.defines), timeout_s=args.timeout)
    if command == "export":
        from cadverify.cadcheck.scad import scad_export

        return scad_export(
            args.scad, args.part, dict(args.defines), out_dir=args.out_dir, timeout_s=args.timeout
        )
    if command == "sheet":
        from cadverify.cadcheck.render import render_sheet

        views = args.views.split(",") if args.views else None
        return render_sheet(args.mesh, args.out, views, args.title)
    if command == "view":
        from cadverify.cadcheck.view import render_view

        return render_view(json.loads(sys.stdin.read()))
    if command == "printability":
        from cadverify.cadcheck.printability import printability_report

        return printability_report(args.mesh, args.allowed)
    if command == "assembly":
        from cadverify.cadcheck.assembly import assembly_report

        return assembly_report(args.scad, args.out_dir, requirements=args.requirements)
    if command == "slice":
        from cadverify.cadcheck.slicer import slice_report

        return slice_report(args.mesh, args.out_dir, args.material)
    from cadverify.cadcheck.verify import verify

    if command == "behaviour":
        found = verify(
            args.scad,
            out_dir=args.out_dir,
            assembly=True,
            requirements=args.requirements,
            default_material=args.material,
            embed=False,
        )
        return {
            "ok": True,  # the measurement ran; its findings are in behaviour
            "behaviour": found["behaviour"],
            "geometry_problems": (found.get("assembly") or {}).get("problems"),
        }
    return verify(
        args.scad,
        out_dir=args.out_dir,
        assembly=args.assembly,
        requirements=args.requirements,
        default_material=args.material,
    )


if __name__ == "__main__":
    raise SystemExit(main())
