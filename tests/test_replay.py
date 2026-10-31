"""The replay page of a session, from a synthetic run directory."""

import json
import re

from cadverify import cli, replay
from cadverify.agent.gates import GATES

GREEN = {g: True for g in GATES}


def _request(cost=0.1):
    usage = {"input_tokens": 1000, "cached_tokens": 0, "output_tokens": 2000}
    return {"cost_usd": cost, "latency_s": 12.0, "usage": usage}


def _run(tmp_path):
    run = tmp_path / "run"
    (run / "tools").mkdir(parents=True)
    (run / "workspace" / "renders").mkdir(parents=True)
    (run / "workspace" / "model.scad").write_text("cube(10); // <b>\n", encoding="utf-8")
    sheet = {"seq": 2, "name": "scad_export", "image": "renders/sheet-002.png"}
    (run / "tools" / "0002-scad_export.json").write_text(json.dumps(sheet))
    (run / "tools" / "0001-scad_write.json").write_text(json.dumps({"seq": 1, "image": None}))
    red = {g: {"ok": True, "detail": []} for g in GATES}
    red["G8"] = {"ok": False, "detail": ["unsupported claim: <script>it is strong</script>"]}
    session = {
        "model": "muse-wonder-1.0",
        "request": "# A cube\n\nA 10 mm cube.",
        "status": "green",
        "iterations": [
            {
                "iteration": 1,
                "request": _request(),
                "text": "Let me <write> it.",
                "tool_calls": [
                    {"seq": 1, "name": "scad_write", "summary": "model.scad: 1 lines"},
                    {"seq": 2, "name": "scad_export", "summary": "ok=True, spec ok"},
                ],
                "images": [{"seq": 2, "tool": "scad_export"}],
                "gates": {**GREEN, "G8": None},
            },
            {
                "iteration": 2,
                "request": _request(),
                "text": "Done, and strong.",
                "tool_calls": [],
                "images": [],
                "gates": {**GREEN, "G8": False},
                "close": "rejected",
                "gate_detail": red,
            },
            {
                "iteration": 3,
                "request": _request(),
                "text": "Done.",
                "tool_calls": [],
                "images": [],
                "gates": GREEN,
                "close": "accepted",
            },
        ],
        "totals": {"requests": 3, "tool_calls": 2, "cost_usd": 0.3, "wall_s": 120.0},
        "final": {"gates": {g: {"ok": True, "detail": []} for g in GATES}},
    }
    (run / "session.json").write_text(json.dumps(session), encoding="utf-8")
    return run


def test_the_page_shows_the_session(tmp_path):
    page = replay.html_page(_run(tmp_path))
    assert "<title>A cube</title>" in page and "<h1>A cube</h1>" in page
    assert '<span class="badge ok">green</span>' in page
    assert "3 requests" in page and "USD 0.30" in page and "2 min" in page
    assert page.count('<li class="panel" id="it-') == 3
    assert 'src="workspace/renders/sheet-002.png"' in page  # relative to the run directory
    assert '<span class="badge red">close refused</span>' in page
    assert '<span class="badge ok">accepted</span>' in page
    assert "unsupported claim: &lt;script&gt;it is strong&lt;/script&gt;" in page


def test_the_gate_grid_has_one_cell_per_gate_and_iteration(tmp_path):
    page = replay.html_page(_run(tmp_path))
    cells = re.findall(r'<a class="(ok|red|pend)" href="#it-(\d)"', page)
    assert len(cells) == len(GATES) * 3
    g8 = [state for state, _ in cells[(len(GATES) - 1) * 3 :]]
    assert g8 == ["pend", "red", "ok"]


def test_everything_the_model_wrote_is_escaped(tmp_path):
    page = replay.html_page(_run(tmp_path))
    assert "Let me &lt;write&gt; it." in page
    assert "cube(10); // &lt;b&gt;" in page
    assert "<script>" not in page and "<write>" not in page


def test_the_command_writes_the_page_into_the_run(tmp_path, capsys):
    run = _run(tmp_path)
    assert cli.main(["replay", str(run)]) == 0
    assert capsys.readouterr().out.strip() == str(run / "replay.html")
    assert (run / "replay.html").read_text(encoding="utf-8").startswith("<!doctype html>")
