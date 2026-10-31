"""Static inspection of OpenSCAD source text (no geometry evaluation)."""

from __future__ import annotations

import re


def customizer_options(code: str, name: str) -> list[str]:
    """Options of a Customizer drop-down: `name = "a"; // [a, b, c]` -> ["a", "b", "c"].

    Labeled options (`[a:Label A, b:Label B]`) keep only the value. Sliders (`[0:5:120]`) and
    unannotated variables give [].
    """
    match = re.search(
        rf"^\s*{re.escape(name)}\s*=\s*[^;\n]*;\s*//\s*\[([^\]]*,[^\]]*)\]", code, re.M
    )
    if not match:
        return []
    return [option.split(":")[0].strip() for option in match.group(1).split(",")]
