"""A session as one static page: the request, the gates at every iteration, what the model said
and did, the images it saw, and how it closed.

`cadverify replay <run>` writes <run>/replay.html. The page has no scripts and loads nothing:
the images are the run's own files (workspace/renders/...), linked by relative path, so the page
works opened from disk or served with the run directory.
"""

from __future__ import annotations

import json
from html import escape
from pathlib import Path
from typing import Any

from cadverify.agent.gates import GATES

GATE_NAMES = {
    "G1": "compiles clean",
    "G2": "closed meshes",
    "G3": "assembly",
    "G4": "motion",
    "G5": "printable",
    "G7": "spec held, all seen",
    "G8": "honest close",
}
CLOSES = {
    "accepted": ("accepted", "ok"),
    "rejected": ("close refused", "red"),
    "questions": ("questions to the user", "info"),
    "questions before looking": ("questions held back: look first", "info"),
}

STATUS = {"green": "ok", "running": "info"}

CSS = """
:root {
  --bg: #f7f7f5; --panel: #ffffff; --text: #1d1d1b; --muted: #6b6b66; --line: #e2e2dc;
  --ok: #1f8a4c; --ok-bg: #e3f4ea; --red: #c23b2a; --red-bg: #fbe7e4;
  --pend: #b8b8b0; --info: #2f5fb3; --info-bg: #e6edf9; --code: #f0f0ec;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #161615; --panel: #1f1f1d; --text: #ecece8; --muted: #9a9a93; --line: #34342f;
    --ok: #4cc27c; --ok-bg: #18301f; --red: #ef6b5a; --red-bg: #3a1d19;
    --pend: #55554f; --info: #7da2e8; --info-bg: #1b2539; --code: #272724;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--text);
  font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif;
}
main { max-width: 1100px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 26px; margin: 0 0 6px; }
h2 { font-size: 18px; margin: 32px 0 12px; }
.meta { color: var(--muted); display: flex; flex-wrap: wrap; gap: 6px 16px; }
.badge {
  display: inline-block; padding: 1px 9px; border-radius: 999px; font-size: 13px;
  font-weight: 600;
}
.badge.ok { color: var(--ok); background: var(--ok-bg); }
.badge.red { color: var(--red); background: var(--red-bg); }
.badge.info { color: var(--info); background: var(--info-bg); }
.badge.pend { color: var(--muted); background: var(--code); }
.panel {
  background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
  padding: 14px 16px;
}
pre {
  margin: 0; white-space: pre-wrap; word-break: break-word;
  font: 13px/1.45 ui-monospace, "SFMono-Regular", Menlo, monospace;
}
.prose { white-space: pre-wrap; overflow-wrap: anywhere; }
pre.code { background: var(--code); border-radius: 8px; padding: 12px; overflow-x: auto;
  white-space: pre; }
details > summary { cursor: pointer; font-weight: 600; }
details[open] > summary { margin-bottom: 10px; }
.grid { overflow-x: auto; }
.grid table { border-collapse: separate; border-spacing: 2px; }
.grid th { font-weight: 500; color: var(--muted); font-size: 12px; text-align: left;
  white-space: nowrap; padding-right: 8px; }
.grid td { padding: 0; }
.grid a { display: block; width: 14px; height: 18px; border-radius: 3px; }
.grid a.ok { background: var(--ok); }
.grid a.red { background: var(--red); }
.grid a.pend { background: var(--pend); }
.grid .num { font-size: 10px; color: var(--muted); text-align: center; }
ol.timeline { list-style: none; padding: 0; margin: 0; display: grid; gap: 12px; }
.it-head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 12px; }
.it-head b { font-size: 16px; }
.it-head span { color: var(--muted); font-size: 13px; }
.said { margin-top: 10px; border-left: 3px solid var(--info); padding-left: 12px; }
.answer { border-left-color: var(--ok); }
ul.calls { margin: 10px 0 0; padding: 0; list-style: none; display: grid; gap: 4px; }
ul.calls li { font-size: 13px; overflow-wrap: anywhere; }
ul.calls code { font-weight: 600; }
.images { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 10px; margin-top: 12px; }
.images figure { margin: 0; }
.images img { width: 100%; border: 1px solid var(--line); border-radius: 6px;
  background: #fff; }
.images figcaption { font-size: 12px; color: var(--muted); }
ul.detail { margin: 8px 0 0; padding-left: 18px; font-size: 13px; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.legend { color: var(--muted); font-size: 13px; margin: 10px 0 0; }
.legend i { display: inline-block; width: 10px; height: 12px; border-radius: 2px;
  vertical-align: -1px; margin: 0 4px 0 10px; }
.legend i:first-child { margin-left: 0; }
.legend .ok { background: var(--ok); } .legend .red { background: var(--red); }
.legend .pend { background: var(--pend); }
"""


def _state(ok: bool | None) -> str:
    return "pend" if ok is None else ("ok" if ok else "red")


def _title(request: str) -> str:
    for line in request.splitlines():
        if line.strip():
            return line.lstrip("# ").strip()
    return "Design session"


def _images(run_dir: Path) -> dict[int, str]:
    """The image of each tool call, by seq, as a path relative to the run directory."""
    images = {}
    for path in sorted((run_dir / "tools").glob("*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        if record.get("image"):
            images[record["seq"]] = f"workspace/{record['image']}"
    return images


def _gate_grid(iterations: list[dict[str, Any]]) -> str:
    head = "".join(
        f'<td class="num">{it["iteration"] if it["iteration"] % 5 == 0 else ""}</td>'
        for it in iterations
    )
    rows = [f"<tr><th></th>{head}</tr>"]
    for gate in GATES:
        cells = []
        for it in iterations:
            gates = it.get("gates")
            if not gates:
                cells.append("<td></td>")
                continue
            ok = gates.get(gate)
            label = f"iteration {it['iteration']}: {gate} {_state(ok)}"
            cells.append(
                f'<td><a class="{_state(ok)}" href="#it-{it["iteration"]}" '
                f'title="{escape(label)}"></a></td>'
            )
        rows.append(f"<tr><th>{gate} {GATE_NAMES[gate]}</th>{''.join(cells)}</tr>")
    legend = (
        '<p class="legend"><i class="ok"></i>passed<i class="red"></i>failed'
        '<i class="pend"></i>pending: G8 is judged when the model closes. One column per '
        "iteration; each cell links to it.</p>"
    )
    return f'<div class="grid panel"><table>{"".join(rows)}</table>{legend}</div>'


def _iteration(it: dict[str, Any], images: dict[int, str]) -> str:
    req = it["request"]
    parts = [
        '<div class="it-head">',
        f"<b>Iteration {it['iteration']}</b>",
        f"<span>USD {req['cost_usd']:.3f} · {req['latency_s']:.0f} s · "
        f"{req['usage']['output_tokens']:,} output tokens</span>",
    ]
    if close := it.get("close"):
        label, state = CLOSES.get(close, (close, "info"))
        parts.append(f'<span class="badge {state}">{escape(label)}</span>')
    if "incomplete" in it:
        reason = it["incomplete"].get("reason", "no reason")
        parts.append(f'<span class="badge red">response cut short ({escape(reason)})</span>')
    parts.append("</div>")
    if it.get("text", "").strip():
        parts.append(f'<div class="said prose">{escape(it["text"].strip())}</div>')
    if it.get("answer"):
        parts.append(
            f'<div class="said answer prose"><b>User:</b> {escape(it["answer"].strip())}</div>'
        )
    if it["tool_calls"]:
        calls = "".join(
            f"<li><code>{escape(t['name'] or '?')}</code> {escape(t['summary'])}</li>"
            for t in it["tool_calls"]
        )
        parts.append(f'<ul class="calls">{calls}</ul>')
    figures = [
        f'<figure><a href="{escape(images[i["seq"]])}"><img loading="lazy" '
        f'alt="{escape(i["tool"])} (call {i["seq"]})" src="{escape(images[i["seq"]])}"></a>'
        f"<figcaption>{escape(i['tool'])}, call {i['seq']}</figcaption></figure>"
        for i in it.get("images", [])
        if i["seq"] in images
    ]
    if figures:
        parts.append(f'<div class="images">{"".join(figures)}</div>')
    red = [(g, d) for g, d in (it.get("gate_detail") or {}).items() if d.get("ok") is False]
    if red:
        items = "".join(
            f"<li><b>{g}</b>: {escape(line)}</li>" for g, d in red for line in d["detail"][:6]
        )
        parts.append(f'<ul class="detail">{items}</ul>')
    return f'<li class="panel" id="it-{it["iteration"]}">{"".join(parts)}</li>'


def html_page(run_dir: Path) -> str:
    session = json.loads((run_dir / "session.json").read_text(encoding="utf-8"))
    iterations = session["iterations"]
    totals = session.get("totals") or {}
    images = _images(run_dir)
    status = session["status"]
    final = {g: v["ok"] for g, v in ((session.get("final") or {}).get("gates") or {}).items()}
    title = _title(session["request"])
    meta = [
        f'<span class="badge {STATUS.get(status, "red")}">{escape(status)}</span>',
        f"<span>{escape(session['model'])}</span>",
        f"<span>{totals.get('requests', len(iterations))} requests</span>",
        f"<span>{totals.get('tool_calls', 0)} tool calls</span>",
        f"<span>USD {totals.get('cost_usd', 0):.2f}</span>",
        f"<span>{totals.get('wall_s', 0) / 60:.0f} min</span>",
    ]
    chips = "".join(
        f'<span class="badge {_state(final.get(g))}">{g} {GATE_NAMES[g]}</span>' for g in GATES
    )
    source = run_dir / "workspace" / "model.scad"
    body = [
        f"<h1>{escape(title)}</h1>",
        f'<div class="meta">{"".join(meta)}</div>',
        "<h2>Request</h2>",
        f'<div class="panel prose">{escape(session["request"].strip())}</div>',
        "<h2>Gates at every iteration</h2>",
        _gate_grid(iterations),
        "<h2>Session</h2>",
        f'<ol class="timeline">{"".join(_iteration(it, images) for it in iterations)}</ol>',
        "<h2>Final verification</h2>",
        f'<div class="chips">{chips}</div>',
    ]
    if source.exists():
        body.append(
            '<h2>Source</h2><details class="panel"><summary>model.scad</summary>'
            f'<pre class="code">{escape(source.read_text(encoding="utf-8"))}</pre></details>'
        )
    return (
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>{escape(title)}</title><style>{CSS}</style></head>"
        f"<body><main>{''.join(body)}</main></body></html>\n"
    )


def write(run_dir: Path) -> Path:
    out = run_dir / "replay.html"
    out.write_text(html_page(run_dir), encoding="utf-8")
    return out
