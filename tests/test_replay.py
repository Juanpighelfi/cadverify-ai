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
    assert "audited by" not in page


def test_the_page_names_an_auditor_that_is_not_the_designer(tmp_path):
    run = _run(tmp_path)
    session = json.loads((run / "session.json").read_text())
    session.update(model="muse-spark-1.3", auditor="muse-wonder-1.0")
    (run / "session.json").write_text(json.dumps(session))
    page = replay.html_page(run)
    assert "<span>muse-spark-1.3</span><span>audited by muse-wonder-1.0</span>" in page


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


def test_the_markdown_the_model_writes_is_rendered_and_escaped():
    text = (
        "**Verified**\n\n"
        "- walls 2.4 mm [[body_wall]], in `model.scad`\n"
        "  and a line that goes on\n"
        "  - a nested *point*\n"
        "- <b>not bold</b> **2 × 3**\n\n"
        "1. first\n2. second\n\n"
        "## Not verified\nstrength"
    )
    html = replay._markdown(text)
    assert "<p><strong>Verified</strong></p>" in html
    assert (
        '<ul><li>walls 2.4 mm <span class="cite">body_wall</span>, in <code>model.scad</code> '
        "and a line that goes on<ul><li>a nested <em>point</em></li></ul></li>"
    ) in html
    assert "<li>&lt;b&gt;not bold&lt;/b&gt; <strong>2 × 3</strong></li></ul>" in html
    assert "<ol><li>first</li><li>second</li></ol>" in html
    assert '<p class="h">Not verified</p><p>strength</p>' in html
    assert replay._inline("diameters [[0.0, 4.6]]") == "diameters [[0.0, 4.6]]"


def test_a_numbered_list_keeps_its_first_number():
    assert (
        replay._markdown("3. third\n4. fourth")
        == '<ol start="3"><li>third</li><li>fourth</li></ol>'
    )


def test_a_tool_call_shows_the_problems_it_found_and_the_spec_moves(tmp_path):
    run = _run(tmp_path)
    problems = [f"printed in place: a and b are 0.0{i} mm apart" for i in range(7)]
    check = {
        "seq": 3,
        "name": "interference_check",
        "image": None,
        "result": {
            "problems": {"G3": [], "G5": problems},
            "spec_notes": ["assembly: the spec moved toward what the mesh already measured"],
        },
    }
    (run / "tools" / "0003-interference_check.json").write_text(json.dumps(check))
    session = json.loads((run / "session.json").read_text())
    session["iterations"][0]["tool_calls"].append(
        {"seq": 3, "name": "interference_check", "summary": "G5 7"}
    )
    (run / "session.json").write_text(json.dumps(session))
    page = replay.html_page(run)
    assert "<li><b>G5</b>printed in place: a and b are 0.00 mm apart</li>" in page
    assert "0.05 mm apart" in page and "0.06 mm apart" not in page
    assert '<li class="more">and 1 more</li>' in page
    assert '<ul class="found note"><li><b>spec moved</b>assembly: the spec moved' in page


def test_the_request_does_not_repeat_the_title(tmp_path):
    page = replay.html_page(_run(tmp_path))
    assert '<div class="panel md"><p>A 10 mm cube.</p></div>' in page


def test_the_index_links_every_replay_of_each_results_dir(tmp_path):
    requests = tmp_path / "results" / "design" / "cube"
    requests.mkdir(parents=True)
    for name, status, page in [
        ("20261031T003026Z", "green", True),
        ("20261031T010000Z", "running", True),
        ("20261031T020000Z", "green", False),
    ]:
        run = _run(tmp_path)
        session = json.loads((run / "session.json").read_text())
        session["status"] = status
        (run / "session.json").write_text(json.dumps(session))
        if page:
            replay.write(run)
        run.rename(requests / name)
    out = tmp_path / "index.html"
    dirs = [str(requests.parent), str(tmp_path / "results" / "bench")]
    assert cli.main(["index", *dirs, "--out", str(out)]) == 0
    page = out.read_text(encoding="utf-8")
    assert page.count("<tr><td>") == 1  # running, and without replay.html: left out
    assert '<a href="results/design/cube/20261031T003026Z/replay.html">A cube</a>' in page
    assert "<h2>results/design</h2>" in page and "results/bench" not in page
    numbers = '<td class="n">3</td><td class="n">0.30</td><td class="n">2</td><td class="n">1</td>'
    assert numbers in page and "<td>2026-10-31 00:30</td>" in page
