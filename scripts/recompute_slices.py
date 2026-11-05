"""The slicer on the final parts of the recorded green sessions, to find greens of G5 it
contradicts. Costs no model; the recorded results are only read.

    uv run python scripts/recompute_slices.py results/slices_recomputed

<out_dir>/table.md and table.json: each part's grams, hours and thinnest wall, what the slicer
loses.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from public_sessions import public_sessions

from cadverify.config import PROJECT_ROOT

SKIPPED = {"behaviour"}  # those sessions ran with the slicer: it is recorded in them
IMAGE = "cadverify-sandbox"
TIMEOUT_S = 900
GREEN = {"green", "verde"}
INNER = """
import json, sys
from pathlib import Path
from cadverify.cadcheck.slicer import slice_report
out = {}
for stl in sorted(Path('/in').glob('*.stl')):
    try:
        out[stl.name] = slice_report(stl, '/tmp/out', sys.argv[1])
    except Exception as exc:
        out[stl.name] = {'ok': False, 'error': f'{type(exc).__name__}: {exc}'}
print(json.dumps(out))
"""


def latest(exports: Path, part: str) -> Path | None:
    """The newest export of a part: its name carries the hash of the source, not the order."""
    found = sorted(exports.glob(f"model.{part}.*.stl"), key=lambda p: p.stat().st_mtime)
    return found[-1] if found else None


def sessions(results: Path) -> list[dict[str, Any]]:
    out = []
    for path in public_sessions(results):
        rel = path.relative_to(results)
        if rel.parts[0] in SKIPPED:
            continue
        session = json.loads(path.read_text(encoding="utf-8"))
        final = session.get("final") or {}
        if session.get("status") not in GREEN or not final.get("parts"):
            continue
        exports = path.parent / "workspace/exports"
        stls = [latest(exports, p["part"] or "default") for p in final["parts"]]
        stls = [s for s in stls if s is not None]
        if stls:
            request = session.get("request") or ""
            material = "PETG" if "PETG" in request else "PLA"
            out.append({"run": str(rel.parent), "stls": stls, "material": material})
    return out


def run(item: dict[str, Any]) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="slices") as work:
        for stl in item["stls"]:
            # the part's name, without the hash of the source
            shutil.copy(stl, Path(work) / re.sub(r"^model\.|\.[0-9a-f]{8}(?=\.stl$)", "", stl.name))
        Path(work).chmod(0o755)
        command = ["docker", "run", "--rm", "--cpus", "2", "--memory", "4g", "--memory-swap", "4g"]
        command += ["--network", "none", "-e", "HOME=/tmp", "-v", f"{work}:/in:ro", IMAGE]
        command += ["python", "-c", INNER, item["material"]]
        try:
            done = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return {"error": f"over {TIMEOUT_S} s"}
    try:
        return json.loads(done.stdout)
    except json.JSONDecodeError:
        return {"error": (done.stderr or done.stdout)[-300:]}


def main() -> int:
    out_root = Path(sys.argv[1] if len(sys.argv) > 1 else "results/slices_recomputed").resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    rows = []
    for item in sessions(PROJECT_ROOT / "results"):
        print(item["run"], flush=True)
        rows.append({"run": item["run"], "material": item["material"], "parts": run(item)})
    (out_root / "table.json").write_text(json.dumps(rows, indent=1), encoding="utf-8")
    lines = [
        "| Session | Part | Grams | Hours | Thinnest wall (mm) | Lines | Lost by the slicer |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    parts = lost = failed = 0
    for row in rows:
        for name, part in row["parts"].items():
            if not isinstance(part, dict):
                failed += 1
                lines.append(f"| {row['run']} | - | | | | | {part} |")
                continue
            parts += 1
            gone = part.get("lost") or []
            lost += bool(gone)
            failed += not part.get("ok")
            said = part.get("error") or "; ".join(
                f"{g['area_mm2']} mm² at {g['at']}, z {g['z']}-{g['z_to']}" for g in gone[:3]
            )
            lines.append(
                f"| {row['run']} | {name[:-4]} | {part.get('grams', '-')} | "
                f"{part.get('hours', '-')} | {part.get('thinnest_wall_mm', '-')} | "
                f"{part.get('lines_in_thinnest_wall', '-')} | {said} |"
            )
    summary = (
        f"{len(rows)} green sessions, {parts} parts: the slicer loses part of {lost}, "
        f"could not slice {failed}."
    )
    (out_root / "table.md").write_text(
        f"# The slicer on the recorded greens\n\n{summary}\n\n" + "\n".join(lines) + "\n",
        encoding="utf-8",
    )
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
