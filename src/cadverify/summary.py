"""A session in Markdown: one row per iteration (tools, images, gates, tokens, cost, latency) and
the model's own code grouped by what it did. And the sessions of a results directory side by
side, one row per request and model (table).

The groups come from an automatic pass over the code (what it calls and writes): a first sort,
not a judgment.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path
from statistics import median
from typing import Any

from cadverify.meta_api import cost_usd

GROUPS = (
    ("edit", None),
    ("renders", re.compile(r"savefig|cadcheck (sheet|view)|--render|\.png|view_image|imshow")),
    # A plane cut, not a boolean intersection (which is a measurement).
    (
        "cuts",
        re.compile(
            r"\.section\(|section_multiplane|slice_plane|trim_by_plane|split_by_plane"
            r"|cadcheck\.section"
        ),
    ),
    (
        "measurements",
        re.compile(
            r"trimesh|numpy|np\.|volume|bounds|area|ray|contains|manifold3d|cadcheck "
            r"(mesh|printability|export)|openscad .*-o|scipy|shapely"
        ),
    ),
    ("other", re.compile(r".")),
)


def num(value: float | None, decimals: int = 0) -> str:
    """A number with thousands separators; "-" when there is none (a call that failed on its
    arguments has no time)."""
    if value is None:
        return "-"
    return f"{value:,.{decimals}f}"


def code_calls(run_dir: Path) -> list[dict[str, Any]]:
    """Every run_shell / run_python call with its group."""
    calls = []
    for path in sorted((run_dir / "tools").glob("*-run_*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        args = record["arguments"] if isinstance(record["arguments"], dict) else {}
        code = args.get("cmd") or args.get("code") or ""
        result = record["result"]
        edited = record.get("scad_changed") and record["name"] in ("run_shell", "run_python")
        group = "edit" if edited else next(g for g, rx in GROUPS[1:] if rx.search(code))
        calls.append(
            {
                "seq": record["seq"],
                "iteration": record["iteration"],
                "tool": record["name"],
                "group": group,
                "exit_code": result.get("exit_code"),
                "seconds": result.get("seconds"),
                "first_line": code.strip().splitlines()[0][:100] if code.strip() else "",
                "rule": (record.get("rule") or {}).get("edit"),
            }
        )
    return calls


def _without_tools(iteration: dict[str, Any]) -> str:
    if "incomplete" in iteration:
        return f"response cut short ({iteration['incomplete'].get('reason', 'no reason')})"
    if iteration.get("close") == "questions":
        return "questions to the user"
    if iteration.get("close") == "questions before looking":
        return "questions held back: it had not looked yet"
    return f"close: {iteration.get('close')}"


def markdown(run_dir: Path) -> str:
    session = json.loads((run_dir / "session.json").read_text(encoding="utf-8"))
    rows = [
        "| It. | Tools | Images | Red gates | Input (cached) | Output (reasoning) | USD "
        "| Latency |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for it in session["iterations"]:
        req = it["request"]
        usage = req["usage"]
        tools = ", ".join(t["name"] for t in it["tool_calls"]) or _without_tools(it)
        images = ", ".join(i["tool"] for i in it.get("images", [])) or "-"
        red = [g for g, ok in (it.get("gates") or {}).items() if ok is False]
        rows.append(
            f"| {it['iteration']} | {tools} | {images} | {', '.join(red) or '-'} "
            f"| {num(usage['input_tokens'])} ({num(usage['cached_tokens'])}) "
            f"| {num(usage['output_tokens'])} ({num(usage['reasoning_tokens'])}) "
            f"| {num(req['cost_usd'], 4)} | {num(req['latency_s'], 1)} s |"
        )
    totals = session["totals"]
    images = totals.get("images") or {}
    seen = ", ".join(f"{n} {tool}" for tool, n in images.items() if n) or "none"
    lines = [
        f"## {run_dir.name}: {session['status']}",
        "",
        f"{totals['requests']} requests, {totals['tool_calls']} tool calls, images: {seen}, "
        f"USD {num(totals['cost_usd'], 2)}, "
        f"{num(totals['wall_s'] / 60, 1)} min ({num(totals['model_latency_s'] / 60, 1)} min in "
        "the model)"
        + (
            f", plus {num(totals['user_wait_s'] / 60, 1)} min waiting for answers"
            if totals.get("user_wait_s")
            else ""
        ),
        "",
        *rows,
        "",
    ]
    calls = code_calls(run_dir)
    if calls:
        lines += [
            "| seq | It. | Tool | Group | exit | s | First line |",
            "|---|---|---|---|---|---|---|",
        ]
        for c in calls:
            first = c["first_line"].replace("|", "\\|")
            lines.append(
                f"| {c['seq']} | {c['iteration']} | {c['tool']} | {c['group']}"
                f"{' (' + c['rule'] + ')' if c['rule'] else ''} | {num(c['exit_code'])} "
                f"| {num(c['seconds'], 2)} | `{first}` |"
            )
        lines.append("")
    if session.get("rule_events"):
        events = json.dumps(session["rule_events"], ensure_ascii=False)
        lines.append(f"Image rule: {events}")
    for compaction in session.get("compactions") or []:
        lines.append(
            f"Images out of the context at iteration {compaction['iteration']}: "
            f"{len(compaction['removed'])} (kept {len(compaction['kept'])})"
        )
    for adjustment in session.get("spec_adjustments") or []:
        lines.append(
            f"Spec adjustment (seq {adjustment.get('seq') or '-'}): {adjustment['part']}, "
            f"{adjustment['item']}: {adjustment['from']} -> {adjustment['to']}, measured "
            f"{adjustment['measured']} ({adjustment['why']})"
        )
    for audit in session.get("audits") or []:
        g8 = audit["g8"]
        cost = sum(r["cost_usd"] for r in audit["requests"])
        state = "green" if g8["ok"] else "RED"
        if g8.get("not_audited"):
            state += f" ({g8['not_audited']})"
        lines.append(
            f"G8 at iteration {audit['iteration']}: {state}, USD {num(cost, 4)}"
            + "".join(f"\n  - {d}" for d in g8["detail"])
        )
    if "final" in session:
        gates = {k: v["ok"] for k, v in session["final"]["gates"].items()}
        lines.append(f"Final gates: {gates}")
    return "\n".join(lines)


def table(results: Path) -> str:
    """The sessions under `results` (<request>/<UTC>/session.json), one row per request and
    model: how many closed green, and the median session's requests, USD, minutes and closes
    refused. "USD Standard" prices each request at its model's Standard price: what a session
    on a "-contributor" model would have cost without the discount."""
    rows: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for path in sorted(results.glob("*/*/session.json")):
        session = json.loads(path.read_text(encoding="utf-8"))
        if session["status"] == "running":
            continue
        requests = [(it["request"], session["model"]) for it in session["iterations"]]
        auditor = session.get("auditor") or session["model"]
        requests += [(r, auditor) for a in session.get("audits") or [] for r in a["requests"]]
        standard = sum(
            cost_usd(r["usage"], (r.get("model") or model).removesuffix("-contributor"))
            for r, model in requests
        )
        rows[(path.parent.parent.name, session["model"])].append(
            {
                "green": session["status"] == "green",
                "requests": session["totals"]["requests"],
                "usd": session["totals"]["cost_usd"],
                "standard": standard,
                "minutes": session["totals"]["wall_s"] / 60,
                "refused": sum(it.get("close") == "rejected" for it in session["iterations"]),
            }
        )
    lines = [
        "| Request | Model | Green | Requests | USD | USD Standard | Minutes | Closes refused |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for (request, model), runs in sorted(rows.items()):

        def mid(key: str, runs=runs) -> float:
            return median(r[key] for r in runs)

        lines.append(
            f"| {request} | {model} | {sum(r['green'] for r in runs)} of {len(runs)} "
            f"| {mid('requests'):g} | {mid('usd'):.2f} | {mid('standard'):.2f} "
            f"| {mid('minutes'):.0f} | {mid('refused'):g} |"
        )
    return "\n".join(lines)
