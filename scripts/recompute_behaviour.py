"""G6 of the recorded sessions: every flex of a final version recomputed, in the sandbox image, with
the code of today. Costs no model; the recorded results are only read.

    uv run python scripts/recompute_behaviour.py results/g6_recomputed --jobs 2

Each session gets <out_dir>/<set>/<request>/<run>/behaviour.json and the pictures of its parts;
<out_dir>/table.md and table.json say how many greens fall and why. Their specs could not declare a
material, so each is computed in what its request names, or in PLA.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from public_sessions import public_sessions

from cadverify.config import PROJECT_ROOT

SKIPPED = {"behaviour"}  # those sessions ran with G6: it is recorded in them
IMAGE = "cadverify-sandbox"
TIMEOUT_S = 1800  # above what G6 allows itself on a busy machine


def flexes(final: dict[str, Any]) -> list[dict[str, Any]]:
    """The flexes the recorded verification measured a depth for, and the use of each."""
    assembly = final.get("assembly") or {}
    out = []
    for motion in assembly.get("motions") or []:
        for flex in motion.get("flex") or []:
            if flex.get("depth_mm"):
                out.append({"where": f"motion {motion['name']}", **flex})
    for step in assembly.get("assembly_steps") or []:
        for key in ("flex", "turn_flex"):
            for flex in step.get(key) or []:
                if flex.get("depth_mm"):
                    out.append({"where": f"assembly step {step['step']}", **flex})
    return out


def sessions(results: Path) -> list[dict[str, Any]]:
    out = []
    for path in public_sessions(results):
        rel = path.relative_to(results)
        if rel.parts[0] in SKIPPED or not (path.parent / "workspace/model.scad").exists():
            continue
        session = json.loads(path.read_text(encoding="utf-8"))
        final = session.get("final") or {}
        recorded = flexes(final)
        if not recorded:
            continue
        gates = {g: v.get("ok") for g, v in (final.get("gates") or {}).items()}
        out.append(
            {
                "run": str(rel.parent),
                "dir": path.parent,
                "status": session.get("status"),
                "gates": gates,
                "green": session.get("status") == "green",
                "material": "PETG" if "PETG" in (session.get("request") or "") else "PLA",
                "recorded": recorded,
            }
        )
    return out


def compute(item: dict[str, Any], out_root: Path) -> dict[str, Any]:
    out = out_root / item["run"]
    done = out / "behaviour.json"
    if done.exists():
        return {**_public(item), "report": json.loads(done.read_text(encoding="utf-8"))}
    out.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    with tempfile.TemporaryDirectory(dir=out_root) as work:
        work = Path(work)
        for scad in (item["dir"] / "workspace").rglob("*.scad"):
            rel = scad.relative_to(item["dir"] / "workspace")
            if rel.parts[0] != "checks":
                (work / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(scad, work / rel)
        work.chmod(0o777)
        name = f"cadverify-recompute-{uuid.uuid4().hex[:10]}"
        command = ["docker", "run", "--rm", "--name", name]
        command += ["--cpus", "2", "--memory", "4g", "--memory-swap", "4g"]
        command += ["-e", "HOME=/tmp", "-v", f"{work}:/work", "-w", "/work", IMAGE, "sh", "-c"]
        command.append(
            f"cadcheck behaviour model.scad --out-dir /tmp/out --material {item['material']}"
            " && (cp /tmp/out/behaviour/*.png /work/ 2>/dev/null || true)"
        )
        try:
            run = subprocess.run(command, capture_output=True, text=True, timeout=TIMEOUT_S)
            report = _json(run.stdout) or {"error": (run.stderr or run.stdout)[-400:]}
        except subprocess.TimeoutExpired:
            subprocess.run(["docker", "kill", name], capture_output=True)
            report = {"error": f"over {TIMEOUT_S} s"}
        for png in work.glob("*.png"):
            shutil.copy(png, out / png.name)
    report["wall_s"] = round(time.perf_counter() - started, 1)
    done.write_text(json.dumps(report, indent=1, default=str), encoding="utf-8")
    return {**_public(item), "report": report}


def _json(text: str) -> dict[str, Any] | None:
    start = text.find("{")
    try:
        return json.loads(text[start:]) if start >= 0 else None
    except json.JSONDecodeError:
        return None


def _public(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k != "dir"}


def _verdict(row: dict[str, Any]) -> str:
    report = row["report"]
    behaviour = report.get("behaviour") or {}
    if "error" in report:
        return f"not computed: {report['error'][:120]}"
    if behaviour.get("skipped"):
        return "not computed: " + "; ".join(report.get("geometry_problems", {}).get("G4", [])[:1])
    return "green" if behaviour.get("ok") else "red"


def why_red(row: dict[str, Any]) -> str:
    """The one reason a session is counted under, the first of these that holds."""
    report = row["report"]
    problems = " ".join((report.get("behaviour") or {}).get("problems") or [])
    if "error" in report or (report.get("behaviour") or {}).get("skipped"):
        return "not computed: G3 or G4 are red with today's code"
    if "% strain at" in problems or "pulls its layers apart" in problems:
        return "a strain past its limit"
    if "could not be computed" in problems:
        return "the part could not be filled with tetrahedra"
    if "ran over" in problems:
        return "ran over its CPU budget"
    if "did not settle" in problems:
        return "a number that did not settle"
    return "other: " + problems[:80]


def reasons(rows: list[dict[str, Any]]) -> str:
    counts: dict[str, list[str]] = {}
    for row in rows:
        counts.setdefault(why_red(row), []).append(row["run"])
    lines = ["| Why | Greens | Sessions |", "|---|--:|---|"]
    for why, runs in sorted(counts.items(), key=lambda kv: -len(kv[1])):
        lines.append(f"| {why} | {len(runs)} | {', '.join(runs)} |")
    return "\n".join(lines)


def table(rows: list[dict[str, Any]]) -> str:
    lines = [
        "| Session | Flex | Depth (mm) | Force (N) | Part | Strain / limit (%) | Z / limit (%) "
        "| G6 |",
        "|---|---|---|---:|---|---:|---:|---|",
    ]
    for row in rows:
        behaviour = row["report"].get("behaviour") or {}
        verdict = _verdict(row)
        computed = behaviour.get("flex") or []
        if not computed:
            lines.append(f"| {row['run']} | | | | | | | {verdict} |")
        for flex in computed:
            for part in flex.get("parts") or [{}]:
                lines.append(
                    f"| {row['run']} | {flex['where']}: {flex['a']} / {flex['b']} "
                    f"| {flex['depth_mm']:.3f} | {flex.get('force_n', '-')} "
                    f"| {part.get('instance', '')} "
                    f"| {part.get('strain_pct', '-')} / {part.get('limit_pct', '-')} "
                    f"| {part.get('z_strain_pct', '-')} / {part.get('z_limit_pct', '-')} "
                    f"| {'green' if flex.get('ok') else 'red'} |"
                )
    return "\n".join(lines)


# What in a request names a load: today's auditor would ask for a declaration on these (G8).
LOAD_WORDS = re.compile(
    r"\b\d+(\.\d+)? ?(g|kg|n)\b|\b(weigh\w*|load\w*|holds?|grips?|clips?|snaps?|flex\w*|click\w*|"
    r"detents?|latch\w*|presses?|force|stand\w* up|tip\w* over)\b",
    re.I,
)


def named_loads(results: Path) -> str:
    """Each public request that names a load, and the words: all recorded green finals of these
    measured geometry only, since their specs could not declare a load or a weight."""
    lines = ["| Request | What it names |", "|---|---|"]
    for request in sorted((results.parent / "requests").glob("*.md")):
        words = {m.group(0).lower() for m in LOAD_WORDS.finditer(request.read_text("utf-8"))}
        if words and request.stem != "phone_stand_flex":
            lines.append(f"| {request.stem} | {', '.join(sorted(words))} |")
    return "\n".join(lines)


def main() -> int:
    out_root = Path(sys.argv[1] if len(sys.argv) > 1 else "results/g6_recomputed").resolve()
    jobs = int(sys.argv[sys.argv.index("--jobs") + 1]) if "--jobs" in sys.argv else 2
    out_root.mkdir(parents=True, exist_ok=True)
    items = sessions(PROJECT_ROOT / "results")
    items = [i for i in items if not str(i["dir"]).startswith(str(out_root))]
    with ThreadPoolExecutor(jobs) as pool:
        rows = list(pool.map(lambda i: compute(i, out_root), items))
    (out_root / "table.json").write_text(json.dumps(rows, indent=1, default=str), encoding="utf-8")
    green = [r for r in rows if r["green"]]
    fell = [r for r in green if _verdict(r) != "green"]
    summary = (
        f"{len(rows)} sessions with a flex that met what it presses on, "
        f"{sum(len(r['recorded']) for r in rows)} flexes; of {len(green)} green sessions, "
        f"{len(fell)} are red in G6 today."
    )
    (out_root / "table.md").write_text(
        f"# G6 of the recorded sessions\n\n{summary}\n\n{reasons(fell)}\n\n{table(rows)}\n\n"
        "## Requests that name a load\n\nNot one recorded spec could declare a load. Today's "
        "auditor "
        f"would ask for one on these.\n\n{named_loads(PROJECT_ROOT / 'results')}\n",
        encoding="utf-8",
    )
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
