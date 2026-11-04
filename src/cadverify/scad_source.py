"""Static inspection of OpenSCAD source text (no geometry evaluation)."""

from __future__ import annotations

import re

QUOTED = re.compile(r'\s*"([^"]*)"')


def customizer_options(code: str, name: str) -> list[str]:
    """Options of a Customizer drop-down: `name = "a"; // [a, b, c]` -> ["a", "b", "c"].

    Options may be quoted (`["a", "b c"]`), as OpenSCAD reads them: the value without its
    quotes. Labeled options (`[a:Label A, "b":Label B]`) keep only the value. Sliders
    (`[0:5:120]`) and unannotated variables give [].
    """
    match = re.search(
        rf"^\s*{re.escape(name)}\s*=\s*[^;\n]*;\s*//\s*\[([^\]]*,[^\]]*)\]", code, re.M
    )
    if not match:
        return []
    options = []
    for item in _split(match.group(1)):
        quoted = QUOTED.match(item)
        options.append(quoted.group(1) if quoted else item.split(":")[0].strip())
    return options


def _split(text: str) -> list[str]:
    """`text` split at the commas outside double quotes."""
    items, current, quoted = [], "", False
    for char in text:
        if char == '"':
            quoted = not quoted
        if char == "," and not quoted:
            items.append(current)
            current = ""
        else:
            current += char
    return [*items, current]
