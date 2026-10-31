"""The OpenSCAD binary and how Python values become `-D` defines. The agent's tools are in
`cadverify.cadcheck`.
"""

from __future__ import annotations

import math
import os
import re
import shutil
from typing import Any


def openscad_bin() -> str:
    path = os.environ.get("OPENSCAD_BIN") or shutil.which("openscad")
    if not path:
        raise FileNotFoundError("OpenSCAD not found; install it or set OPENSCAD_BIN")
    return path


_STRING_ESCAPES = str.maketrans({"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"})


def scad_literal(value: Any) -> str:
    """OpenSCAD source literal for a Python value (bool, number, str, None or a list of them)."""
    if value is None:
        return "undef"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"OpenSCAD has no literal for {value}")
        return repr(value)
    if isinstance(value, str):
        return f'"{value.translate(_STRING_ESCAPES)}"'
    if isinstance(value, list | tuple):
        return "[" + ", ".join(scad_literal(v) for v in value) + "]"
    raise TypeError(f"Unsupported OpenSCAD value: {value!r}")


def define_args(defines: dict[str, Any] | None) -> list[str]:
    """`-D name=value` arguments; they override the file's own assignments."""
    args: list[str] = []
    for name, value in (defines or {}).items():
        if not re.fullmatch(r"\$?[A-Za-z_]\w*", name):
            raise ValueError(f"Invalid OpenSCAD variable name: {name!r}")
        args += ["-D", f"{name}={scad_literal(value)}"]
    return args
