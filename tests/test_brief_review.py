"""The design brief before any CAD, and the reviewer before the close (agent/brief.py and
agent/review.py), through the session loop with a scripted model."""

import json

import pytest

from cadverify.agent import brief, review
from cadverify.agent.closing import registry
from cadverify.agent.loop import Limits, run_session
from cadverify.agent.tools import ToolBox
from cadverify.replay import _brief, _review
from tests.test_agent import EXPORT, WRITE, FakeModel, FakeSandbox, _args, _verify

BRIEF = {
    "failure_modes": [{"mode": "the arm breaks", "check": "strain under the limit"}],
    "serves": {"who": "anyone", "range": "phones 60 to 90 mm wide"},
    "loads": [],
    "no_loads": "it holds nothing",
    "candidates": [
        {"name": "thin arm", "numbers": {"strain (%)": 1.1}, "assumptions": ["PLA"]},
        {"name": "thick arm", "numbers": {"strain (%)": 2.9}, "assumptions": ["PLA"]},
    ],
    "chosen": "thin arm",
    "why": "1.1% is under the limit of 1.38%",
}
BRIEF_CALL = [("design_brief", BRIEF)]
FINDING = {"where": "base, floor", "what": "it hangs by 3 tabs", "confirm_by": "cut at z=1"}


def _box(tmp_path, **kwargs) -> ToolBox:
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    return ToolBox(FakeSandbox(workspace, _verify()), tmp_path / "tools", **kwargs)


# ---- the brief --------------------------------------------------------------------------------


def test_a_complete_brief_has_no_problems():
    assert brief.problems(BRIEF) == []


@pytest.mark.parametrize(
    "change,says",
    [
        ({"failure_modes": []}, "failure_modes"),
        ({"failure_modes": [{"mode": "x", "check": ""}]}, "failure_modes"),
        ({"serves": {"who": "x"}}, "serves"),
        ({"no_loads": ""}, "no_loads"),
        ({"loads": [{"what": "a", "value": "1 N", "assumption": "b"}]}, "measured_as"),
        ({"candidates": BRIEF["candidates"][:1]}, "at least 2"),
        ({"chosen": "other"}, "chosen"),
        ({"why": " "}, "why"),
        (
            {
                "candidates": [
                    {"name": "a", "numbers": {}, "assumptions": ["x"]},
                    {"name": "thin arm", "numbers": {"n": 1}, "assumptions": ["x"]},
                ]
            },
            "numbers",
        ),
        (
            {
                "candidates": [
                    {"name": "a", "numbers": {"n": "good"}, "assumptions": ["x"]},
                    {"name": "thin arm", "numbers": {"n": 1}, "assumptions": ["x"]},
                ]
            },
            "numbers",
        ),
        (
            {
                "candidates": [
                    {"name": "a", "numbers": {"n": 1}, "assumptions": []},
                    {"name": "thin arm", "numbers": {"n": 1}, "assumptions": ["x"]},
                ]
            },
            "assumptions",
        ),
    ],
)
def test_what_a_brief_cannot_lack(change, says):
    assert any(says in p for p in brief.problems({**BRIEF, **change}))


def test_no_cad_before_the_brief(tmp_path):
    box = _box(tmp_path)
    write = _args(path="model.scad", content="cube(10);\n")
    result, _ = box.call("scad_write", write, 1)
    assert result["ok"] is False and "design_brief" in result["error"]
    assert box.rule_events[-1]["rule"] == "brief"
    assert not (box.workspace / "model.scad").exists()
    incomplete, _ = box.call("design_brief", _args(**{**BRIEF, "candidates": []}), 1)
    assert incomplete["ok"] is False
    assert box.call("scad_write", write, 1)[0]["ok"] is False
    assert box.call("design_brief", _args(**BRIEF), 1)[0]["ok"] is True
    assert box.call("scad_write", write, 1)[0]["ok"] is True


def test_each_load_of_the_brief_has_to_be_measured_by_its_name():
    load = {"what": "the phone", "value": "2 N", "assumption": "200 g", "measured_as": "phone"}
    state = {
        "gates": {},
        "parts": [],
        "brief": {**BRIEF, "loads": [load]},
        "behaviour": {"loads": [{"name": "phone", "ok": True}]},
    }
    assert brief.closing_problems(state, registry(state)) == []
    state["behaviour"] = {"loads": [{"name": "phone", "ok": False}]}
    assert "red" in brief.closing_problems(state, registry(state))[0]
    state["behaviour"] = {"loads": []}
    assert "nothing with that name" in brief.closing_problems(state, registry(state))[0]


def test_a_close_with_no_brief_is_red_and_a_session_without_the_rule_is_not():
    assert "no design brief" in brief.closing_problems({"brief": None}, {})[0]
    assert brief.closing_problems({}, {}) == []


# ---- the reviewer ----------------------------------------------------------------------------


def test_what_a_review_answers():
    assert review.parse('{"findings": []}') == []
    assert review.parse('```json\n{"findings": []}\n```') == []
    assert review.parse("I see nothing wrong") is None
    assert review.parse('{"findings": "none"}') is None
    assert review.parse(json.dumps({"findings": [FINDING]})) == [FINDING]
    unmeasurable = {"where": "base", "what": "ugly", "confirm_by": ""}
    assert review.parse(json.dumps({"findings": [unmeasurable, FINDING]})) == [FINDING]
    many = {"findings": [FINDING] * 9}
    assert len(review.parse(json.dumps(many))) == review.MAX_FINDINGS


def test_the_reviewer_sees_neither_the_source_nor_the_reasoning(tmp_path):
    secret = "my private reasoning about cube sizes"
    box = _box(tmp_path)
    close = f"Done [[G2]]. {secret}"
    model = FakeModel([BRIEF_CALL, WRITE, EXPORT, close])
    session = run_session(model, box, "the request", Limits(), tmp_path, reviewer="muse-wonder-1.0")
    assert session["status"] == "green"
    sent = json.dumps(model.review_payloads)
    assert "the request" in sent and "thin arm" in sent  # the request and the brief
    assert secret not in sent and "cube(10)" not in sent
    assert "scad" not in model.review_payloads[0]["instructions"]


def test_a_finding_is_a_hypothesis_answered_by_measuring(tmp_path):
    box = _box(tmp_path)
    numbers = "the cut at z=1 shows the floor joined all around: 400 mm2"
    measure = [("run_python", {"code": "print(400)"})]
    script = [
        BRIEF_CALL,
        WRITE,
        EXPORT,
        "Done [[G2]].",
        # Not answered, with a measurement missing: refused, and the close stays red.
        [("answer_finding", {"id": "R1", "verdict": "refuted", "numbers": numbers})],
        "Done [[G2]].",
        measure,
        [("answer_finding", {"id": "R9", "verdict": "refuted", "numbers": numbers})],
        [("answer_finding", {"id": "R1", "verdict": "fixed", "numbers": numbers})],
        [("answer_finding", {"id": "R1", "verdict": "refuted", "numbers": numbers})],
        "Done [[G2]], and the finding was wrong.",
    ]
    model = FakeModel(script, reviews=[json.dumps({"findings": [FINDING]})])
    session = run_session(model, box, "request", Limits(), tmp_path, reviewer="muse-wonder-1.0")
    assert session["status"] == "green"
    closes = [it.get("close") for it in session["iterations"]]
    assert closes.count("reviewed") == 1 and closes.count("rejected") == 1
    assert closes[-1] == "accepted"
    results = [
        json.loads((tmp_path / "tools" / path.name).read_text())
        for path in sorted((tmp_path / "tools").glob("*answer_finding*.json"))
    ]
    said = [r["result"] for r in results]
    assert "nothing was measured" in said[0]["error"]
    assert "no finding" in said[1]["error"]
    assert "fixed takes" in said[2]["error"]
    assert said[3]["ok"] is True
    assert len(model.review_payloads) == 1  # same version: not reviewed again
    assert session["final"]["findings"][0]["status"] == "refuted"
    assert session["final"]["findings"][0]["tool"] == "run_python"
    audit = model.audit_payloads[-1]["input"]
    assert "reviewer_findings" in audit and numbers in audit
    page = _review(session["final"], session)
    assert "R1 refuted" in page and "400 mm2" in page
    assert "thin arm (chosen)" in _brief(session["final"]["brief"])


def test_a_fix_takes_a_new_version_and_is_reviewed_once_more(tmp_path):
    box = _box(tmp_path)
    fix = [("scad_write", {"path": "model.scad", "content": "cube(11);\n"})]
    script = [
        BRIEF_CALL,
        WRITE,
        EXPORT,
        "Done [[G2]].",
        fix,
        [("scad_export", {"path": "model.scad"})],
        [("answer_finding", {"id": "R1", "verdict": "fixed", "numbers": "now 11 mm"})],
        "Done [[G2]].",
    ]
    model = FakeModel(script, reviews=[json.dumps({"findings": [FINDING]}), '{"findings": []}'])
    box.sandbox.verify_result = _verify()
    session = run_session(model, box, "request", Limits(), tmp_path, reviewer="muse-wonder-1.0")
    assert len(model.review_payloads) == 2
    assert session["final"]["findings"][0]["status"] == "fixed"
    assert [r["findings"] != [] for r in session["reviews"]] == [True, False]


def test_a_review_that_does_not_answer_is_said_and_does_not_stop_the_close(tmp_path):
    box = _box(tmp_path)
    model = FakeModel([BRIEF_CALL, WRITE, EXPORT, "Done [[G2]]."], reviews=["no", "still no"])
    session = run_session(model, box, "request", Limits(), tmp_path, reviewer="muse-wonder-1.0")
    assert session["status"] == "green"
    assert session["reviews"][0]["not_reviewed"] is True
    assert "did not answer" in _review(session["final"], session)


def test_a_session_without_a_reviewer_has_none(tmp_path):
    box = _box(tmp_path)
    model = FakeModel([BRIEF_CALL, WRITE, EXPORT, "Done [[G2]]."])
    session = run_session(model, box, "request", Limits(), tmp_path)
    assert session["status"] == "green" and session["reviews"] == []
    assert model.review_payloads == []
    assert _review(session["final"], session) == ""
