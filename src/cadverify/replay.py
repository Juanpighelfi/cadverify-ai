"""A session as one static page: the request, the gates at every iteration, what the model said
and did, what each tool found, the images it saw, and how it closed.

`cadverify replay <run>` writes <run>/replay.html. The page has no scripts and loads nothing:
the images are the run's own files (workspace/renders/...), linked by relative path, so the page
works opened from disk or served with the run directory. `cadverify index <results dirs>` writes
one page that links every replay under them.
"""

from __future__ import annotations

import json
import math
import os
import re
from html import escape
from importlib.metadata import PackageNotFoundError, metadata
from pathlib import Path
from typing import Any

from cadverify.agent import physical
from cadverify.agent.gates import GATES
from cadverify.agent.prompts import SEED_NOTE

GATE_NAMES = {
    "G1": "compiles clean",
    "G2": "closed meshes",
    "G3": "assembly",
    "G4": "motion",
    "G5": "printable",
    "G6": "behaviour",
    "G7": "spec held, all seen",
    "G8": "honest close",
}
CLOSES = {
    "accepted": ("accepted", "ok"),
    "rejected": ("close refused", "red"),
    "reviewed": ("reviewer's findings", "info"),
    "questions": ("questions to the user", "info"),
    "questions before looking": ("questions held back: look first", "info"),
}

STATUS = {"green": "ok", "running": "info"}
# Lines of findings shown per tool call and per red gate of a refused close.
MAX_FINDINGS = 6
CURVE_SERIES = 4  # lines of one force curve: more go in its table only
FORCE_SETTLED = 0.10  # how far a finer mesh moved a force before the page says so
FOLD_CODE_LINES = 20  # a longer code block (a seeded model.scad) is folded
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
  --series-1: #2a78d6; --series-2: #eb6834; --series-3: #1baf7a; --series-4: #eda100;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #161615; --panel: #1f1f1d; --text: #ecece8; --muted: #9a9a93; --line: #34342f;
    --ok: #4cc27c; --ok-bg: #18301f; --red: #ef6b5a; --red-bg: #3a1d19;
    --pend: #55554f; --info: #7da2e8; --info-bg: #1b2539; --code: #272724;
    --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70; --series-4: #c98500;
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
.md pre.code, .md details { margin: 0 0 8px; }
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
.grid a.none { box-shadow: inset 0 0 0 1.5px var(--pend); }
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
.behaviour { margin-top: 10px; }
.curve { display: block; width: 100%; max-width: 680px; height: auto; margin: 8px 0; }
.curve text { fill: var(--muted); font: 12px system-ui, sans-serif; }
.curve .grid { stroke: var(--line); stroke-width: 1; }
.curve .target { fill: var(--code); }
.curve .line { fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
.curve .dot { stroke: var(--panel); stroke-width: 2; }
.curve .failed { fill: var(--panel); stroke-width: 2; }
.keys { display: flex; flex-wrap: wrap; gap: 4px 14px; font-size: 13px; color: var(--muted); }
.keys i { display: inline-block; width: 14px; height: 2px; vertical-align: 4px; margin-right: 6px; }
.findings { list-style: none; margin: 8px 0 0; padding: 0; display: grid; gap: 8px; }
.behaviour td:nth-child(2) { white-space: normal; text-align: left; }
.behaviour th:nth-child(2) { text-align: left; }
.behaviour .text th, .behaviour .text td { text-align: left; white-space: normal; }
.behaviour .text td:last-child { min-width: 170px; }
.behaviour .curve-wrap { overflow-x: auto; }
.behaviour .curve { min-width: 520px; }
.behaviour p { margin: 6px 0; }
.behaviour ul { margin: 4px 0 8px; padding-left: 22px; }
.behaviour h3 { font-size: 15px; margin: 14px 0 8px; display: flex; flex-wrap: wrap; gap: 4px 10px;
  align-items: baseline; }
.behaviour h3 .badge { align-self: center; }
.behaviour h3:first-child { margin-top: 0; }
.behaviour h3 span.where { color: var(--muted); font-weight: 400; font-size: 13px; }
.behaviour .scroll { overflow-x: auto; }
.behaviour table { border-collapse: collapse; width: 100%; font-size: 13px; }
.behaviour th { color: var(--muted); font-weight: 500; text-align: right; white-space: nowrap; }
.behaviour td { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
.behaviour th, .behaviour td { padding: 4px 8px; border-top: 1px solid var(--line); }
.behaviour tr:first-child th { border-top: 0; }
.behaviour th:first-child, .behaviour td:first-child { text-align: left; padding-left: 0; }
.behaviour td.over { color: var(--red); font-weight: 600; }
.behaviour figure { margin: 10px 0 0; }
.behaviour figure img { display: block; max-width: 100%; height: auto; border-radius: 6px;
  border: 1px solid var(--line); background: #fff; }
.legend { color: var(--muted); font-size: 13px; margin: 10px 0 0; }
.legend i { display: inline-block; width: 10px; height: 12px; border-radius: 2px;
  vertical-align: -1px; margin: 0 4px 0 10px; }
.legend i:first-child { margin-left: 0; }
.legend .ok { background: var(--ok); } .legend .red { background: var(--red); }
.legend .pend { background: var(--pend); }
.legend .none { box-shadow: inset 0 0 0 1.5px var(--pend); }
a { color: var(--info); }
.lead { color: var(--muted); max-width: 780px; margin: 0; }
.runs { overflow-x: auto; padding: 6px 8px; }
.runs table { border-collapse: collapse; width: 100%; min-width: 960px; table-layout: fixed;
  font-size: 14px; }
.runs col.request { width: 27%; } .runs col.model { width: 19%; }
.runs col.status { width: 17%; } .runs col.n { width: 6%; } .runs col.when { width: 13%; }
.runs th { font-weight: 500; color: var(--muted); font-size: 13px; text-align: left; }
.runs th, .runs td { padding: 6px 8px; }
.runs th { vertical-align: bottom; }
.runs td { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.runs td:first-child { white-space: normal; }
.runs tr + tr td { border-top: 1px solid var(--line); }
.runs .n { text-align: right; font-variant-numeric: tabular-nums; }
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

    code: list[str] | None = None  # the lines of an open ``` block
    language = ""

    def code_block() -> str:
        pre = f'<pre class="code">{escape(chr(10).join(code or []))}</pre>'
        if len(code or []) <= FOLD_CODE_LINES:
            return pre
        name = f"{language} · " if language else ""
        return f"<details><summary>{escape(name)}{len(code or [])} lines</summary>{pre}</details>"

    for line in text.strip().splitlines():
        stripped = line.strip()
        if code is not None:
            if stripped.startswith("```"):
                blocks.append(code_block())
                code = None
            else:
                code.append(line)
        elif stripped.startswith("```"):
            close_para()
            close_lists()
            code, language = [], stripped[3:].strip()
        elif not stripped:
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
    if code is not None:
        blocks.append(code_block())
    return "".join(blocks)


def _fenced_seed(request: str) -> str:
    """A request that carries a .scad, with the .scad fenced: the sessions before the fence had
    it bare, from its first line that starts with // (where the command found it) to SEED_NOTE.
    A later version's first message goes on after that note."""
    note = SEED_NOTE.strip()
    head, found, after = request.partition(note)
    if not found or "\n```" in head:
        return request
    lines = head.rstrip().splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith("//")), None)
    if start is None:
        return request
    scad = "\n".join(lines[start:])
    return "\n".join(lines[:start]).rstrip() + f"\n\n```openscad\n{scad}\n```\n\n{note}{after}"


def _request(request: str) -> str:
    """The request as the model got it. In a later version, what it was reminded of about the last
    one is folded, and what the user said stays in view. A version of a version holds both."""
    asked, start, rest = request.rpartition(physical.ITERATE_START)
    if not start:
        return _markdown(request)
    reminded, _, said = rest.partition(physical.ITERATE_NOW)
    said, rule, after = said.partition(physical.ITERATE_RULE)
    return (
        _request(asked)
        + "<details><summary>What the model was told about the last version</summary>"
        + _markdown(f"{start}{reminded}\n\n{rule}{after}")
        + f"</details><h3>What the user said</h3>{_markdown(said)}"
    )


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


def _gate_grid(iterations: list[dict[str, Any]], gates: tuple[str, ...] = GATES) -> str:
    cell = max(CELL_MIN, min(CELL_MAX, GRID_WIDTH // max(len(iterations), 1) - 2))
    head = "".join(
        f'<td class="num">{it["iteration"] if it["iteration"] % 5 == 0 else ""}</td>'
        for it in iterations
    )
    rows = [f"<tr><th></th>{head}</tr>"]
    for gate in gates:
        cells = []
        for it in iterations:
            state = it.get("gates")
            if not state:
                why = "the response was cut short" if "incomplete" in it else "no response"
                label = f"iteration {it['iteration']}: nothing verified, {why}"
                cells.append(
                    f'<td><a class="none" href="#it-{it["iteration"]}" '
                    f'title="{escape(label)}"></a></td>'
                )
                continue
            ok = state.get(gate)
            label = f"iteration {it['iteration']}: {gate} {_state(ok)}"
            cells.append(
                f'<td><a class="{_state(ok)}" href="#it-{it["iteration"]}" '
                f'title="{escape(label)}"></a></td>'
            )
        rows.append(f"<tr><th>{gate} {GATE_NAMES[gate]}</th>{''.join(cells)}</tr>")
    unverified = (
        '<i class="none"></i>nothing verified: response cut short or failed.'
        if any(not it.get("gates") for it in iterations)
        else ""
    )
    legend = (
        '<p class="legend"><i class="ok"></i>passed<i class="red"></i>failed'
        f'<i class="pend"></i>pending: G8 is judged when the model closes.{unverified} One '
        "column per iteration; each cell links to it.</p>"
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
    if it.get("findings"):
        lines = [
            f"<b>{escape(f['id'])}</b>{_inline(f['where'] + ': ' + f['what'])}"
            for f in it["findings"]
        ]
        parts.append(_capped(lines, "found note"))
    red = [(g, d) for g, d in (it.get("gate_detail") or {}).items() if d.get("ok") is False]
    for gate, detail in red:
        lines = [f"<b>{escape(gate)}</b>{_inline(line)}" for line in detail["detail"]]
        parts.append(_capped(lines, "detail"))
    return f'<li class="panel" id="it-{it["iteration"]}">{"".join(parts)}</li>'


def _recorded_gates(iterations: list[dict[str, Any]], final: dict[str, Any]) -> tuple[str, ...]:
    """The gates of this session: G6 came later, and a session recorded before it has none, which
    is not the same as a gate pending."""
    has_g6 = "G6" in final or any("G6" in (it.get("gates") or {}) for it in iterations)
    return tuple(g for g in GATES if g != "G6" or has_g6)


def _number(value: Any, digits: int = 2) -> str:
    return "-" if value is None else f"{value:.{digits}f}"


def _strain_cell(value: float | None, limit: float | None) -> str:
    over = value is not None and limit is not None and value > limit
    text = f"{_number(value)} / {_number(limit)}"
    return f'<td class="over">{text}</td>' if over else f"<td>{text}</td>"


def _part_rows(parts: list[dict[str, Any]]) -> tuple[str, str]:
    """A row per part of a flex or load, and the pictures of their strain."""
    head = (
        "<tr><th>Part</th><th>Material</th><th>Deflects (mm)</th><th>Strain / limit (%)</th>"
        "<th>Between layers / limit (%)</th><th>Elements</th></tr>"
    )
    rows, figures = [head], []
    for part in parts:
        rows.append(
            f"<tr><td>{escape(part.get('instance') or part.get('on') or '')}</td>"
            f"<td>{escape(part.get('material') or '')}</td>"
            f"<td>{_number(part.get('deflection_mm'), 3)}</td>"
            f"{_strain_cell(part.get('strain_pct'), part.get('limit_pct'))}"
            f"{_strain_cell(part.get('z_strain_pct'), part.get('z_limit_pct'))}"
            f"<td>{part.get('tets', '-')}</td></tr>"
        )
        if part.get("picture_png"):
            figures.append(
                f'<figure><img loading="lazy" alt="Strain of {escape(part.get("instance") or "")}'
                f', with its peak marked" src="data:image/png;base64,{part["picture_png"]}">'
                "</figure>"
            )
    return f'<div class="scroll"><table>{"".join(rows)}</table></div>', "".join(figures)


def _behaviour(final: dict[str, Any]) -> str:
    """G6 of the final version: its numbers, and each part with its strain in color."""
    report = final.get("behaviour") or {}
    if not report.get("declared"):
        return ""
    blocks = []
    for flex in report.get("flex") or []:
        force = flex.get("force_n")
        target = flex.get("force_target_n")
        heading = f"{escape(flex['a'])} on {escape(flex['b'])}"
        facts = [f"{_number(flex.get('depth_mm'))} mm deep"]
        if force is not None:
            facts.append(f"<b>{force:.1f} N</b>")
            if (flex.get("force_moved") or 0) > FORCE_SETTLED:
                facts.append(f"a finer mesh moved it {flex['force_moved']:.0%}")
        if target:
            facts.append(f"target {target[0]:g} to {target[1]:g} N")
        facts.append(escape(flex.get("where", "")))
        table, figures = _part_rows(flex.get("parts") or [])
        blocks.append(_behaviour_block(heading, flex.get("ok"), facts, table + figures))
    for load in report.get("loads") or []:
        facts = [f"<b>{_number(load.get('force_n'), 1)} N</b>", f"on {escape(load.get('on', ''))}"]
        if load.get("largest_mm") is not None:
            bound = load.get("max_deflection_mm")
            limit = f" of {bound:g} allowed" if bound is not None else ""
            facts.append(f"moves up to {load['largest_mm']:.2f} mm{limit}")
        table, figures = _part_rows([load] if "strain_pct" in load else [])
        blocks.append(
            _behaviour_block(escape(load["name"]), load.get("ok"), facts, table + figures)
        )
    for item in report.get("stability") or []:
        worst = item.get("worst") or {}
        facts = [escape(item.get("on", ""))]
        if worst:
            facts += [
                f"<b>{worst['tilt_deg']:.1f}° before it tips</b>",
                f"{item.get('min_tilt_deg', 0):g}° asked",
                f"{worst['margin_mm']:.1f} mm inside what it stands on",
                f"printed at {worst['fill']:.0%}",
            ]
        blocks.append(_behaviour_block(escape(item["name"]), item.get("ok"), facts, ""))
    problems = report.get("problems") or []
    found = (
        '<ul class="found">'
        + "".join(f"<li><b>G6</b>{_inline(p)}</li>" for p in problems)
        + "</ul>"
        if problems
        else ""
    )
    materials = "; ".join(
        f"{escape(m['name'])}: {m['bending_modulus_mpa']:g} MPa, limit "
        f"{m['strain_repeated_pct']:.2f}% repeated, {m['strain_once_pct']:.2f}% once"
        for m in (report.get("materials") or {}).values()
    )
    note = (
        '<p class="legend">Computed by the harness on its own meshes, by finite elements, with the '
        f"public datasheet values of the material ({materials}). Solid and elastic: infill, "
        "creep, fatigue and how the print turns out are not computed.</p>"
        if materials
        else ""
    )
    return f"<h2>Behaviour (G6)</h2>{found}{''.join(blocks)}{note}"


def _family(final: dict[str, Any]) -> str:
    """A declared family: how each force goes along the range, and every value's verdict."""
    sweeps = final.get("family") or []
    if not sweeps:
        return ""
    return "<h2>Along the range</h2>" + "".join(_sweep(sweep) for sweep in sweeps)


def _sweep(sweep: dict[str, Any]) -> str:
    rows = sweep["rows"]
    names = list(dict.fromkeys(f["name"] for row in rows for f in row.get("flex") or []))
    head = "".join(f"<th>{escape(name)} (N)</th><th>Strain (%)</th>" for name in names)
    body = []
    for row in rows:
        by_name = {f["name"]: f for f in row.get("flex") or []}
        cells = ""
        for name in names:
            flex = by_name.get(name) or {}
            peak = max((s for s in flex.get("strain_pct") or [] if s is not None), default=None)
            cells += f"<td>{_number(flex.get('force_n'), 1)}</td><td>{_number(peak)}</td>"
        state = "ok" if row.get("ok") else "red"
        word = "green" if row.get("ok") else "red"
        body.append(
            f"<tr><td>{escape(str(row['value']))}</td>{cells}"
            f'<td><span class="badge {state}">{word}</span></td></tr>'
        )
    table = (
        f'<div class="scroll"><table><tr><th>{escape(sweep["param"])}</th>{head}<th>G1 to G6</th>'
        f"</tr>{''.join(body)}</table></div>"
    )
    return (
        f'<div class="behaviour panel"><h3><span>{escape(sweep["param"])}</span></h3>'
        f'<div class="curve-wrap">{_curve(sweep, names)}</div>{table}</div>'
    )


def _nice_step(raw: float) -> float:
    """The round number at or above `raw`, for an axis: 1, 2, 2.5 or 5 times a power of ten."""
    magnitude = 10 ** math.floor(math.log10(raw))
    return next((m * magnitude for m in (1, 2, 2.5, 5) if m * magnitude >= raw), 10 * magnitude)


def _curve(sweep: dict[str, Any], names: list[str]) -> str:
    """Force against the parameter, one line per flex, on one axis from zero. The values of the
    parameter are spaced by what they are when they are numbers. Nothing to draw without a force
    at two values. Beyond CURVE_SERIES flexes the table carries them."""
    width, height, left, right, top, bottom = 680, 240, 52, 16, 12, 36
    rows = sweep["rows"]
    numeric = all(isinstance(r["value"], int | float) for r in rows)
    values = [float(r["value"]) if numeric else float(i) for i, r in enumerate(rows)]
    series = []
    for name in names[:CURVE_SERIES]:
        points = []
        for x, row in zip(values, rows, strict=True):
            flex = next((f for f in row.get("flex") or [] if f["name"] == name), None)
            if flex and flex.get("force_n") is not None:
                points.append(
                    (x, flex["force_n"], flex.get("ok"), row["value"], flex.get("target_n"))
                )
        if len(points) >= 2:
            series.append((name, points))
    if not series:
        return ""
    targets = [p[4] for _, pts in series for p in pts if p[4]]
    top_force = max(p[1] for _, pts in series for p in pts)
    top_force = max(top_force, max((t[1] for t in targets), default=0.0)) or 1.0
    step = _nice_step(top_force / 4)
    top_force = step * math.ceil(top_force / step)
    low, high = min(values), max(values)
    span = (high - low) or 1.0

    def px(x: float) -> float:
        return left + (x - low) / span * (width - left - right)

    def py(force: float) -> float:
        return height - bottom - force / top_force * (height - top - bottom)

    parts = [
        f'<svg class="curve" viewBox="0 0 {width} {height}" role="img" '
        f'aria-label="Force against {escape(sweep["param"])}">'
    ]
    if targets:
        lo, hi = targets[0]
        parts.append(
            f'<rect class="target" x="{left}" width="{width - left - right}" y="{py(hi):.1f}" '
            f'height="{py(lo) - py(hi):.1f}"><title>Target {lo:g} to {hi:g} N</title></rect>'
            f'<text x="{width - right - 4}" y="{py(hi) + 14:.1f}" text-anchor="end">target</text>'
        )
    for i in range(round(top_force / step) + 1):
        force = step * i
        parts.append(
            f'<line class="grid" x1="{left}" x2="{width - right}" y1="{py(force):.1f}" '
            f'y2="{py(force):.1f}"/><text x="{left - 8}" y="{py(force) + 4:.1f}" '
            f'text-anchor="end">{force:g}</text>'
        )
    for x, row in zip(values, rows, strict=True):
        parts.append(
            f'<text x="{px(x):.1f}" y="{height - bottom + 18}" text-anchor="middle">'
            f"{escape(str(row['value']))}</text>"
        )
    parts.append(
        f'<text x="{(left + width - right) / 2}" y="{height - 4}" text-anchor="middle">'
        f"{escape(sweep['param'])}</text>"
        f'<text x="14" y="{(top + height - bottom) / 2}" text-anchor="middle" '
        f'transform="rotate(-90 14 {(top + height - bottom) / 2})">force (N)</text>'
    )
    keys = []
    for i, (name, points) in enumerate(series, start=1):
        color = f"var(--series-{i})"
        line = " ".join(f"{px(p[0]):.1f},{py(p[1]):.1f}" for p in points)
        parts.append(f'<polyline class="line" style="stroke: {color}" points="{line}"/>')
        for x, force, ok, value, _ in points:
            # A value that failed is drawn hollow, so it does not rest on color alone.
            style = f"stroke: {color}" if ok is False else f"fill: {color}"
            kind = "failed" if ok is False else "dot"
            verdict = "within its limits" if ok else "over a limit"
            parts.append(
                f'<circle class="{kind}" style="{style}" cx="{px(x):.1f}" cy="{py(force):.1f}" '
                f'r="4.5"><title>{escape(name)} at {escape(str(value))}: {force:.1f} N, {verdict}'
                "</title></circle>"
            )
        keys.append(f'<span><i style="background: {color}"></i>{escape(name)}</span>')
    parts.append("</svg>")
    legend = f'<div class="keys">{"".join(keys)}<span>hollow: over a limit</span></div>'
    return legend + "".join(parts)


def _review(final: dict[str, Any], session: dict[str, Any]) -> str:
    """What the reviewer found and how the designer answered: nothing, in a session without one."""
    reviews = session.get("reviews") or []
    if not reviews:
        return ""
    verdicts = {"fixed": "ok", "refuted": "info", "open": "red"}
    rows = []
    for finding in final.get("findings") or []:
        status = finding["status"]
        rows.append(
            f'<li class="panel"><span class="badge {verdicts.get(status, "info")}">'
            f"{escape(finding['id'])} {escape(status)}</span> "
            f"<b>{_inline(finding['where'])}</b>: {_inline(finding['what'])}"
            f'<div class="legend">Would be confirmed by: {_inline(finding["confirm_by"])}</div>'
            + (
                f"<div>Measured{' with ' + escape(finding['tool']) if finding.get('tool') else ''}"
                ": "
                f"{_inline(finding['numbers'])}</div>"
                if finding.get("numbers")
                else ""
            )
            + "</li>"
        )
    images = sum(len(r.get("images") or []) for r in reviews)
    count = f"{len(reviews)} review{'s' if len(reviews) != 1 else ''}"
    pictures = f"{images} image{'s' if images != 1 else ''}"
    said = f"{count} by {escape(reviews[-1]['model'])}, on {pictures}. "
    if any(r.get("not_reviewed") for r in reviews):
        said += "A review did not answer in the form asked for and found nothing. "
    if not rows:
        said += "No findings."
    list_html = f'<ol class="findings">{"".join(rows)}</ol>' if rows else ""
    return f'<h2>Reviewer</h2><p class="lead">{said}</p>{list_html}'


def _slices(final: dict[str, Any]) -> str:
    """What the slicer made of each part: its grams, its hours, and its thinnest wall."""
    rows = []
    for part in final.get("parts") or []:
        report = part.get("slice")
        if not report:
            continue
        name = escape(part.get("part") or "default")
        if not report.get("ok"):
            rows.append(
                f'<tr><td>{name}</td><td colspan="4">{escape(str(report.get("error")))}</td></tr>'
            )
            continue
        lost = "; ".join(
            f"{g['area_mm2']} mm² at z {g['z']} to {g['z_to']}" for g in report.get("lost") or []
        )
        rows.append(
            f"<tr><td>{name}</td><td>{_number(report.get('grams'), 1)}</td>"
            f"<td>{_number(report.get('hours'), 2)}</td>"
            f"<td>{_number(report.get('thinnest_wall_mm'), 2)} "
            f"({_number(report.get('lines_in_thinnest_wall'), 1)} lines)</td>"
            f"<td>{escape(lost) or 'nothing'}</td></tr>"
        )
    if not rows:
        return ""
    engine = next(
        (p["slice"].get("engine") for p in final["parts"] if (p.get("slice") or {}).get("engine")),
        "",
    )
    head = (
        "<tr><th>Part</th><th>Grams</th><th>Hours</th><th>Thinnest wall (mm)</th>"
        "<th>Drawn and not printed</th></tr>"
    )
    return (
        f'<h2>What the slicer makes of it</h2><div class="behaviour panel">'
        f'<p class="legend">{escape(engine or "")}: an estimate on the profile\'s speeds, not what '
        "the printer will report.</p>"
        f'<div class="scroll"><table class="text">{head}{"".join(rows)}</table></div></div>'
    )


def _physical(final: dict[str, Any], session: dict[str, Any]) -> str:
    """What came back from the real print, and what to do with the next one."""
    blocks = []
    parent = session.get("parent") or {}
    if parent:
        photo = " With a photo." if parent.get("photo") else ""
        blocks.append(
            f"<h3>What the user said about the last version</h3><p>{escape(parent['feedback'])}"
            f"{photo}</p>"
        )
    change = final.get("regression") or {}
    if change.get("gone"):
        items = "".join(f"<li>{escape(item)}</li>" for item in change["gone"])
        blocks.append(f"<h3>Gone since the last version</h3><ul>{items}</ul>")
    rows = []
    for item in change.get("changed") or []:
        said = []
        if item.get("new"):
            said.append("new")
        else:
            if "volume_change" in item:
                said.append(f"volume {item['volume_change']:+.1%}")
            if "bodies" in item:
                said.append(f"bodies {item['bodies'][0]} to {item['bodies'][1]}")
            if "bounds" in item:
                said.append("box changed")
        rows.append(f"<tr><td>{escape(item['part'])}</td><td>{escape(', '.join(said))}</td></tr>")
    if rows:
        blocks.append(
            "<h3>What changed</h3><div class='scroll'><table class='text'><tr><th>Part</th>"
            "<th>Change</th></tr>"
            f"{''.join(rows)}</table></div>"
        )
    versus = [
        f"<tr><td>{escape(f['a'])} / {escape(f['b'])}</td><td>{f['vs_baseline']['force']} times "
        f"({f['vs_baseline']['force_then_n']} N then, {f['force_n']} N now)</td></tr>"
        for f in (final.get("behaviour") or {}).get("flex") or []
        if f.get("vs_baseline")
    ]
    if versus:
        blocks.append(
            "<h3>Against the version that worked</h3><div class='scroll'><table class='text'><tr>"
            "<th>Flex</th>"
            f"<th>Force</th></tr>{''.join(versus)}</table></div>"
        )
    rows = []
    for probe in final.get("probes") or []:
        said = (
            probe.get("error")
            or probe.get("why")
            or (
                f"stands for it: {probe.get('stiffness_vs_real')} times as stiff, "
                f"{probe.get('strain_vs_real')} times the strain per mm"
            )
        )
        rows.append(
            f"<tr><td>{escape(probe['part'])}</td><td>{escape(str(probe.get('of')))}</td>"
            f"<td>{_number((probe.get('slice') or {}).get('grams'), 1)}</td>"
            f"<td>{_number((probe.get('slice') or {}).get('hours'), 2)}</td>"
            f"<td>{escape(said)}</td></tr>"
        )
    if rows:
        blocks.append(
            "<h3>Test prints</h3><div class='scroll'><table class='text'><tr><th>Probe</th>"
            "<th>Of</th>"
            f"<th>Grams</th><th>Hours</th><th>Verdict</th></tr>{''.join(rows)}</table></div>"
        )
    rows = [
        f"<tr><td>{escape(row['failure'])}</td><td>{escape(row['param'])} = "
        f"{escape(str(row['value']))}</td><td>{escape(row['measure'])}: "
        f"{_number(row.get('before'), 2)} to {_number(row.get('after'), 2)}</td></tr>"
        for row in (final.get("tune") or {}).get("rows") or []
    ]
    if rows:
        blocks.append(
            "<h3>What to touch</h3><div class='scroll'><table class='text'><tr><th>If</th>"
            "<th>Parameter</th>"
            f"<th>Moved by the harness</th></tr>{''.join(rows)}</table></div>"
        )
    if not blocks:
        return ""
    return '<h2>The real print</h2><div class="behaviour panel">' + "".join(blocks) + "</div>"


def _world(final: dict[str, Any]) -> str:
    """What the session looked up, with where it comes from: data, not a measurement."""
    rows = []
    for entry in final.get("world") or []:
        links = " ".join(
            f'<a href="{escape(s["url"], quote=True)}" rel="noopener noreferrer">'
            f"{escape(s.get('title') or s['url'])}</a>"
            for s in entry.get("sources") or []
        )
        flag = (
            " <strong>Reads like an order; treated as data.</strong>"
            if entry.get("suspicious")
            else ""
        )
        rows.append(
            f"<tr><td>{escape(entry['id'])}</td><td>{escape(entry['query'])}{flag}</td>"
            f"<td>{links or 'no source'}</td></tr>"
        )
    if not rows:
        return ""
    return (
        '<h2>Data from the web</h2><div class="behaviour panel"><p class="legend">What the web '
        "said, "
        "cited as an assumption. None of it is a measurement.</p><div class='scroll'>"
        "<table class='text'><tr><th>Name</th><th>Looked up</th>"
        f"<th>Sources</th></tr>{''.join(rows)}</table></div></div>"
    )


def _brief(brief: dict[str, Any] | None) -> str:
    """The analysis the designer wrote before any CAD."""
    if not brief:
        return ""
    candidates = "".join(
        f"<tr><td>{escape(str(c['name']))}{' (chosen)' if c['name'] == brief.get('chosen') else ''}"
        f"</td><td>{escape(', '.join(f'{k}: {v:g}' for k, v in c['numbers'].items()))}</td></tr>"
        for c in brief.get("candidates") or []
    )
    modes = "".join(
        f"<li>{_inline(m['mode'])} ({_inline(m['check'])})</li>"
        for m in brief.get("failure_modes") or []
    )
    serves = brief.get("serves") or {}
    return (
        f'<h2>Design brief</h2><div class="behaviour panel"><p><b>Serves:</b> '
        f"{_inline(serves.get('who', ''))}; {_inline(serves.get('range', ''))}</p>"
        f"<p><b>How it fails:</b></p><ul>{modes}</ul>"
        f'<div class="scroll"><table><tr><th>Candidate</th><th>Numbers</th></tr>{candidates}'
        f"</table></div><p>{_inline(brief.get('why', ''))}</p></div>"
    )


def _behaviour_block(heading: str, ok: bool | None, facts: list[str], rest: str) -> str:
    state = "ok" if ok else "red"
    word = "within limits" if ok else "over a limit"
    return (
        f'<div class="behaviour panel"><h3><span>{heading}</span>'
        f'<span class="badge {state}">{word}</span>'
        f'<span class="where">{" · ".join(f for f in facts if f)}</span></h3>{rest}</div>'
    )


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
    gates = _recorded_gates(iterations, final)
    chips = "".join(
        f'<span class="badge {_state(final.get(g))}">{g} {GATE_NAMES[g]}</span>' for g in gates
    )
    source = run_dir / "workspace" / "model.scad"
    request = _fenced_seed(session["request"].strip())
    first, _, rest = request.partition("\n")
    if HEADING.fullmatch(first.strip()) and _title(first) == title:
        request = rest  # the page's own heading already says it
    body = [
        f"<h1>{escape(title)}</h1>",
        f'<div class="meta">{"".join(meta)}</div>',
        "<h2>Request</h2>",
        f'<div class="panel md">{_request(request)}</div>',
        "<h2>Gates at every iteration</h2>",
        _gate_grid(iterations, gates),
        "<h2>Session</h2>",
        f'<ol class="timeline">{"".join(_iteration(it, records) for it in iterations)}</ol>',
        "<h2>Final verification</h2>",
        f'<div class="chips">{chips}</div>',
        _behaviour(session.get("final") or {}),
        _family(session.get("final") or {}),
        _slices(session.get("final") or {}),
        _physical(session.get("final") or {}, session),
        _world(session.get("final") or {}),
        _review(session.get("final") or {}, session),
        _brief((session.get("final") or {}).get("brief")),
    ]
    if source.exists():
        body.append(
            '<h2>Source</h2><details class="panel"><summary>model.scad</summary>'
            f'<pre class="code">{escape(source.read_text(encoding="utf-8"))}</pre></details>'
        )
    return _page(title, body)


def write(run_dir: Path) -> Path:
    out = run_dir / "replay.html"
    out.write_text(html_page(run_dir), encoding="utf-8")
    return out


def _page(title: str, body: list[str]) -> str:
    return (
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>{escape(title)}</title><style>{CSS}</style></head>"
        f"<body><main>{''.join(body)}</main></body></html>\n"
    )


def _repository() -> str | None:
    try:
        urls = metadata("cadverify").get_all("Project-URL") or []
    except PackageNotFoundError:
        return None
    return next((u.split(",", 1)[1].strip() for u in urls if u.startswith("Repository,")), None)


def _started(name: str) -> str:
    """A run directory's UTC name (20261031T003026Z) as 2026-10-31 00:30."""
    m = re.fullmatch(r"(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)\d\dZ", name)
    return f"{m[1]}-{m[2]}-{m[3]} {m[4]}:{m[5]}" if m else name


def index_page(results: list[Path], out: Path) -> str:
    """One table per results directory: every session with a replay.html under it
    (<request>/<UTC>/), linked by its path relative to `out`'s directory."""
    sections = []
    for directory in results:
        rows = []
        for path in sorted(directory.glob("*/*/session.json")):
            session = json.loads(path.read_text(encoding="utf-8"))
            page = path.parent / "replay.html"
            if session["status"] == "running" or not page.exists():
                continue
            totals = session["totals"]
            refused = sum(it.get("close") == "rejected" for it in session["iterations"])
            status = session["status"]
            href = escape(Path(os.path.relpath(page, out.parent)).as_posix())
            rows.append(
                f'<tr><td><a href="{href}">{escape(_title(session["request"]))}</a></td>'
                f"<td>{escape(session['model'])}</td>"
                f'<td><span class="badge {STATUS.get(status, "red")}">{escape(status)}</span></td>'
                f'<td class="n">{totals["requests"]}</td>'
                f'<td class="n">{totals["cost_usd"]:.2f}</td>'
                f'<td class="n">{totals["wall_s"] / 60:.0f}</td><td class="n">{refused}</td>'
                f"<td>{escape(_started(path.parent.name))}</td></tr>"
            )
        if not rows:
            continue
        name = Path(os.path.relpath(directory.resolve(), out.parent.resolve())).as_posix()
        sections.append(
            f"<h2>{escape(name)}</h2>"
            '<div class="panel runs"><table><colgroup><col class="request"><col class="model">'
            '<col class="status">' + '<col class="n">' * 4 + '<col class="when"></colgroup>'
            "<tr><th>Request</th><th>Model</th><th>Status</th>"
            '<th class="n">Requests</th><th class="n">USD</th><th class="n">Minutes</th>'
            '<th class="n">Closes refused</th><th>Started (UTC)</th></tr>'
            f"{''.join(rows)}</table></div>"
        )
    repository = _repository()
    about = (
        "Every recorded design session, as its replay: the request, the gates at every "
        "iteration, each tool call and what it found, the images the model saw, and every close."
    )
    if repository:
        about += f' The code and how each set of sessions was run: <a href="{escape(repository)}">'
        about += f"{escape(repository.removeprefix('https://'))}</a>."
    return _page(
        "CADVerify AI replays",
        ["<h1>CADVerify AI replays</h1>", f'<p class="lead">{about}</p>', *sections],
    )


def write_index(results: list[Path], out: Path) -> Path:
    out.write_text(index_page(results, out), encoding="utf-8")
    return out
