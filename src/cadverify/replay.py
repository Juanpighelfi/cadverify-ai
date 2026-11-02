"""A session as one static page: the request, the gates at every iteration, what the model said
and did, what each tool found, the images it saw, and how it closed.

`cadverify replay <run>` writes <run>/replay.html. The page has no scripts and loads nothing:
the images are the run's own files (workspace/renders/...), linked by relative path, so the page
works opened from disk or served with the run directory.
"""

from __future__ import annotations

import json
import re
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
# Lines of findings shown per tool call and per red gate of a refused close.
MAX_FINDINGS = 6
# Width of the gate grid's cells: they share the panel, within these bounds (px).
GRID_WIDTH, CELL_MIN, CELL_MAX = 860, 10, 32

INLINE = re.compile(
    r"\*\*(?P<bold>.+?)\*\*"
    r"|`(?P<code>[^`]+)`"
    r"|\[\[(?P<cite>[A-Za-z_][^\[\]\n]{0,119})\]\]"  # a name, as closing.REFERENCE; not [[0, 1]]
    r"|(?<![*\w])\*(?P<em>[^*\s](?:[^*]*[^*\s])?)\*(?![*\w])"
)
LIST_ITEM = re.compile(r"( *)(?:[-*•]|(\d+)[.)])\s+(.*)")
HEADING = re.compile(r"#{1,6}\s+(.*)")

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
.md { overflow-wrap: anywhere; }
.md > :first-child { margin-top: 0; }
.md > :last-child { margin-bottom: 0; }
.md p { margin: 0 0 8px; }
.md p.h { font-weight: 700; margin-top: 12px; }
.md ul, .md ol { margin: 0 0 8px; padding-left: 22px; }
.md ul { list-style: disc; }
.md li > ul { list-style: circle; }
.md li > ul, .md li > ol { margin: 2px 0 0; }
.md code, .detail code { font: 13px ui-monospace, "SFMono-Regular", Menlo, monospace;
  background: var(--code); border-radius: 4px; padding: 0 4px; }
.cite { font: 600 12px ui-monospace, "SFMono-Regular", Menlo, monospace; color: var(--info);
  background: var(--info-bg); border-radius: 4px; padding: 0 5px; white-space: nowrap; }
pre.code { background: var(--code); border-radius: 8px; padding: 12px; overflow-x: auto;
  white-space: pre; }
details > summary { cursor: pointer; font-weight: 600; }
details[open] > summary { margin-bottom: 10px; }
.grid { overflow-x: auto; }
.grid table { border-collapse: separate; border-spacing: 2px; }
.grid th { font-weight: 500; color: var(--muted); font-size: 13px; text-align: left;
  white-space: nowrap; padding-right: 10px; }
.grid td { padding: 0; }
.grid a { display: block; width: var(--cell); height: 22px; border-radius: 3px; }
.grid a.ok { background: var(--ok); }
.grid a.red { background: var(--red); }
.grid a.pend { background: var(--pend); }
.grid .num { font-size: 11px; color: var(--muted); text-align: center; }
ol.timeline { list-style: none; padding: 0; margin: 0; display: grid; gap: 12px; }
.it-head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 12px; }
.it-head b { font-size: 16px; }
.it-head span { color: var(--muted); font-size: 13px; }
.said { margin-top: 10px; border-left: 3px solid var(--info); padding-left: 12px; }
.answer { border-left-color: var(--ok); }
ul.calls { margin: 10px 0 0; padding: 0; list-style: none; display: grid; gap: 4px; }
ul.calls > li { font-size: 13px; overflow-wrap: anywhere; }
ul.calls > li > code { font-weight: 600; }
.images { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 12px; margin-top: 12px; }
.images figure { margin: 0; }
.images img { display: block; width: 100%; border: 1px solid var(--line); border-radius: 6px;
  background: #fff; }
.images figcaption { font-size: 12px; color: var(--muted); margin-top: 2px; }
ul.detail, ul.found { list-style: none; margin: 10px 0 0; padding: 2px 0 2px 12px;
  border-left: 3px solid var(--red); font-size: 13px; display: grid; gap: 3px;
  overflow-wrap: anywhere; }
ul.found { margin: 4px 0 4px 2px; }
ul.found.note { border-left-color: var(--info); }
ul.detail b, ul.found b { color: var(--red); margin-right: 4px; }
ul.found.note b { color: var(--info); }
.more { color: var(--muted); }
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


def _inline(text: str) -> str:
    """Escaped text with the Markdown the model writes inline: bold, code, emphasis, and its
    [[citations]] of what the harness verified."""

    def one(m: re.Match) -> str:
        if m["bold"] is not None:
            return f"<strong>{_inline(m['bold'])}</strong>"
        if m["code"] is not None:
            return f"<code>{escape(m['code'])}</code>"
        if m["cite"] is not None:
            return f'<span class="cite">{escape(m["cite"])}</span>'
        return f"<em>{_inline(m['em'])}</em>"

    out, last = [], 0
    for m in INLINE.finditer(text):
        out += [escape(text[last : m.start()]), one(m)]
        last = m.end()
    return "".join(out) + escape(text[last:])


def _markdown(text: str) -> str:
    """The Markdown the model and the requests use, as HTML: paragraphs, headings, bulleted and
    numbered lists one level deep, and the inline marks of _inline. Everything is escaped."""
    blocks: list[str] = []
    para: list[str] = []
    lists: list[list] = []  # open lists, outermost first: [tag, start, items]

    def close_para() -> None:
        if para:
            blocks.append(f"<p>{_inline(' '.join(para))}</p>")
            para.clear()

    def close_lists(depth: int = 0) -> None:
        while len(lists) > depth:
            tag, start, items = lists.pop()
            first = f' start="{start}"' if tag == "ol" and start != 1 else ""
            html = f"<{tag}{first}>{''.join(f'<li>{i}</li>' for i in items)}</{tag}>"
            if lists:
                lists[-1][2][-1] += html
            else:
                blocks.append(html)

    for line in text.strip().splitlines():
        stripped = line.strip()
        if not stripped:
            close_para()
            close_lists()
        elif heading := HEADING.fullmatch(stripped):
            close_para()
            close_lists()
            blocks.append(f'<p class="h">{_inline(heading[1])}</p>')
        elif item := LIST_ITEM.fullmatch(line):
            close_para()
            depth = 1 if lists and len(item[1]) >= 2 else 0
            tag = "ol" if item[2] else "ul"
            close_lists(depth + 1)
            if len(lists) > depth and lists[-1][0] != tag:
                close_lists(depth)
            if len(lists) == depth:
                lists.append([tag, int(item[2] or 1), []])
            lists[-1][2].append(_inline(item[3]))
        elif lists and line[:1].isspace():
            lists[-1][2][-1] += " " + _inline(stripped)
        else:
            close_lists()
            para.append(stripped)
    close_para()
    close_lists()
    return "".join(blocks)


def _records(run_dir: Path) -> dict[int, dict[str, Any]]:
    """Every tool call's record, by seq."""
    records = {}
    for path in sorted((run_dir / "tools").glob("*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        records[record["seq"]] = record
    return records


def _capped(items: list[str], css: str) -> str:
    shown = "".join(f"<li>{i}</li>" for i in items[:MAX_FINDINGS])
    if len(items) > MAX_FINDINGS:
        shown += f'<li class="more">and {len(items) - MAX_FINDINGS} more</li>'
    return f'<ul class="{css}">{shown}</ul>'


def _found(record: dict[str, Any] | None) -> str:
    """What a tool call told the model beyond its summary: the problems it found, by gate, and
    the spec moves it flagged."""
    result = (record or {}).get("result")
    if not isinstance(result, dict):
        return ""
    parts = []
    problems = [
        f"<b>{escape(gate)}</b>{_inline(line)}"
        for gate, lines in (result.get("problems") or {}).items()
        for line in lines
    ]
    if problems:
        parts.append(_capped(problems, "found"))
    notes = [f"<b>spec moved</b>{_inline(n)}" for n in result.get("spec_notes") or []]
    if notes:
        parts.append(_capped(notes, "found note"))
    return "".join(parts)


def _gate_grid(iterations: list[dict[str, Any]]) -> str:
    cell = max(CELL_MIN, min(CELL_MAX, GRID_WIDTH // max(len(iterations), 1) - 2))
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
    return (
        f'<div class="grid panel"><table style="--cell: {cell}px">{"".join(rows)}</table>'
        f"{legend}</div>"
    )


def _iteration(it: dict[str, Any], records: dict[int, dict[str, Any]]) -> str:
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
        parts.append(f'<div class="said md">{_markdown(it["text"])}</div>')
    if it.get("answer"):
        parts.append(
            f'<div class="said answer md"><p><b>User:</b></p>{_markdown(it["answer"])}</div>'
        )
    if it["tool_calls"]:
        calls = "".join(
            f"<li><code>{escape(t['name'] or '?')}</code> {escape(t['summary'])}"
            f"{_found(records.get(t['seq']))}</li>"
            for t in it["tool_calls"]
        )
        parts.append(f'<ul class="calls">{calls}</ul>')
    figures = []
    for i in it.get("images", []):
        image = (records.get(i["seq"]) or {}).get("image")
        if image:
            src = escape(f"workspace/{image}")
            figures.append(
                f'<figure><a href="{src}"><img loading="lazy" '
                f'alt="{escape(i["tool"])} (call {i["seq"]})" src="{src}"></a>'
                f"<figcaption>{escape(i['tool'])}, call {i['seq']}</figcaption></figure>"
            )
    if figures:
        parts.append(f'<div class="images">{"".join(figures)}</div>')
    red = [(g, d) for g, d in (it.get("gate_detail") or {}).items() if d.get("ok") is False]
    for gate, detail in red:
        lines = [f"<b>{escape(gate)}</b>{_inline(line)}" for line in detail["detail"]]
        parts.append(_capped(lines, "detail"))
    return f'<li class="panel" id="it-{it["iteration"]}">{"".join(parts)}</li>'


def html_page(run_dir: Path) -> str:
    session = json.loads((run_dir / "session.json").read_text(encoding="utf-8"))
    iterations = session["iterations"]
    totals = session.get("totals") or {}
    records = _records(run_dir)
    status = session["status"]
    final = {g: v["ok"] for g, v in ((session.get("final") or {}).get("gates") or {}).items()}
    title = _title(session["request"])
    meta = [
        f'<span class="badge {STATUS.get(status, "red")}">{escape(status)}</span>',
        f"<span>{escape(session['model'])}</span>",
        *(
            [f"<span>audited by {escape(session['auditor'])}</span>"]
            if session.get("auditor", session["model"]) != session["model"]
            else []
        ),
        f"<span>{totals.get('requests', len(iterations))} requests</span>",
        f"<span>{totals.get('tool_calls', 0)} tool calls</span>",
        f"<span>USD {totals.get('cost_usd', 0):.2f}</span>",
        f"<span>{totals.get('wall_s', 0) / 60:.0f} min</span>",
    ]
    chips = "".join(
        f'<span class="badge {_state(final.get(g))}">{g} {GATE_NAMES[g]}</span>' for g in GATES
    )
    source = run_dir / "workspace" / "model.scad"
    request = session["request"].strip()
    first, _, rest = request.partition("\n")
    if HEADING.fullmatch(first.strip()) and _title(first) == title:
        request = rest  # the page's own heading already says it
    body = [
        f"<h1>{escape(title)}</h1>",
        f'<div class="meta">{"".join(meta)}</div>',
        "<h2>Request</h2>",
        f'<div class="panel md">{_markdown(request)}</div>',
        "<h2>Gates at every iteration</h2>",
        _gate_grid(iterations),
        "<h2>Session</h2>",
        f'<ol class="timeline">{"".join(_iteration(it, records) for it in iterations)}</ol>',
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
