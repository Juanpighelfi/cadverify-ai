"""scad_write and scad_patch: the only way the agent changes its source.

Both are confined to .scad files under the workspace root. A patch replaces one exact, unique
occurrence of `old`: an edit that matches nowhere, or in two places, fails instead of guessing.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any

MAX_BYTES = 1_000_000


def scad_write(path: str, content: str, root: str | Path = ".") -> dict[str, Any]:
    target = _target(path, root)
    if isinstance(target, dict):
        return target
    data = content.encode("utf-8")
    if len(data) > MAX_BYTES:
        return {"ok": False, "error": f"The file is over {MAX_BYTES} bytes"}
    existed = target.exists()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return {"ok": True, "path": path, "replaced": existed, **_facts(content)}


def scad_patch(path: str, old: str, new: str, root: str | Path = ".") -> dict[str, Any]:
    target = _target(path, root)
    if isinstance(target, dict):
        return target
    if not target.exists():
        return {"ok": False, "error": f"{path} does not exist; create it with scad_write"}
    if not old:
        return {"ok": False, "error": "old is empty"}
    content = target.read_text(encoding="utf-8")
    count = content.count(old)
    if count != 1:
        result = {
            "ok": False,
            "occurrences": count,
            "error": f"old appears {count} times in {path}; it must appear exactly once. "
            + (
                "Add neighboring lines to make it unique."
                if count
                else "Copy the exact text of the file, with its indentation."
            ),
        }
        if count == 0 and _squash(old) in _squash(content):
            result["hint"] = (
                "It appears if whitespace is ignored: check indentation and line breaks."
            )
        return result
    start = content.index(old)
    patched = content[:start] + new + content[start + len(old) :]
    if len(patched.encode("utf-8")) > MAX_BYTES:
        return {"ok": False, "error": f"The file is over {MAX_BYTES} bytes"}
    target.write_text(patched, encoding="utf-8")
    return {
        "ok": True,
        "path": path,
        "line": content.count("\n", 0, start) + 1,
        "lines_removed": old.count("\n") + 1,
        "lines_added": new.count("\n") + 1,
        **_facts(patched),
    }


def _target(path: str, root: str | Path) -> Path | dict[str, Any]:
    base = Path(root).resolve()
    target = (base / path).resolve()
    if not target.is_relative_to(base) or target == base:
        return {"ok": False, "error": f"{path} is outside the workspace"}
    if target.suffix != ".scad":
        return {"ok": False, "error": "Only .scad files can be written"}
    return target


def _facts(content: str) -> dict[str, Any]:
    return {
        "bytes": len(content.encode("utf-8")),
        "lines": len(content.splitlines()),
        "sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
    }


def _squash(text: str) -> str:
    return re.sub(r"\s+", "", text)
