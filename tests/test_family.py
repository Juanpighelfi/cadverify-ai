"""A product made for a range (cadcheck.verify, agent/gates): the spec, the gates at each value, the
close and the curve. The verification itself, in tests/test_agent_docker.py."""

import pytest

from cadverify.agent.closing import registry, summary
from cadverify.agent.gates import evaluate, family_problems, family_rows
from cadverify.agent.spec_history import SpecHistory
from cadverify.cadcheck.spec import SpecError, parse_spec
from cadverify.cadcheck.verify import declared_family, with_parameter
from cadverify.replay import _family
from tests.test_agent import _verify


def _spec(family) -> dict:
    return parse_spec(f'[["bounds", [[0, 0, 0], [1, 1, 1]]], ["family", {family}]]')


def test_a_family_in_a_spec():
    spec = _spec('[["width", [60, 75, 90]], ["grade", ["soft", "hard"]]]')
    assert spec["family"] == [
        {"param": "width", "values": [60, 75, 90]},
        {"param": "grade", "values": ["soft", "hard"]},
    ]
    assert parse_spec('[["bounds", [[0, 0, 0], [1, 1, 1]]]]')["family"] == []


@pytest.mark.parametrize(
    "family,says",
    [
        ('[["width", [60]]]', "at least two"),
        ('[["width", 60]]', "at least two"),
        ('[["no name", [1, 2]]]', "top-level parameter"),
        ('[["width", [1, 1]]]', "a value repeats"),
        ('[["width", [1, 2]], ["width", [3, 4]]]', "the parameter repeats"),
        ('[["width", [1, 2, 3, 4, 5, 6, 7, 8, 9]]]', "at most 8"),
        ('[["width", [[1], [2]]]]', "at least two"),
    ],
)
def test_what_a_family_cannot_be(family, says):
    with pytest.raises(SpecError, match=says):
        _spec(family)


def test_a_parameter_moves_only_where_it_is_assigned():
    source = "width = 75; // [60:90]\nother_width = 1;\ncube([width, 1, 1]);\nwidth2 = 3;\n"
    moved = with_parameter(source, "width", 60)
    assert moved.startswith("width = 60; // [60:90]\nother_width = 1;")
    assert "width2 = 3;" in moved
    assert with_parameter('grade = "soft";', "grade", "hard") == 'grade = "hard";'
    assert with_parameter("module a() { }\n", "width", 60) is None


def test_the_family_the_specs_declare():
    result = {
        "assembly": {"spec": {"family": [{"param": "w", "values": [1, 2]}]}},
        "parts": [
            {"export": {"spec": {"family": [{"param": "w", "values": [3, 4]}]}}},
            {"export": {"spec": {"family": [{"param": "h", "values": [5, 6]}]}}},
            {"export": {"spec": None}},
        ],
    }
    assert declared_family(result) == [
        {"param": "w", "values": [1, 2]},
        {"param": "h", "values": [5, 6]},
    ]


def _flex(force=4.0, ok=True, target=None, strain=1.0):
    return {
        "where": "motion m",
        "a": "arm",
        "b": "phone",
        "force_n": force,
        "force_target_n": target,
        "ok": ok,
        "parts": [{"strain_pct": strain}],
    }


def _at(value, force=4.0, ok=True, target=None):
    verify = _verify()
    problems = [] if ok else [f"over the limit at {value}"]
    verify["behaviour"] = {
        "declared": True,
        "ok": ok,
        "problems": problems,
        "flex": [_flex(force, ok, target)],
    }
    return {"value": value, **verify}


def _with_family(*rows) -> dict:
    verify = _verify()
    verify["family"] = {
        "problems": [],
        "sweeps": [{"param": "width", "values": [r["value"] for r in rows], "rows": list(rows)}],
    }
    return verify


def test_every_value_is_judged_as_the_default_is():
    verify = _with_family(_at(60), _at(90, ok=False))
    gates = evaluate(verify, set(), {})
    assert gates["G6"]["ok"] is False
    assert gates["G6"]["detail"] == ["width = 90: over the limit at 90"]


def test_a_value_that_breaks_something_else_is_red_in_that_gate():
    broken = _at(90)
    broken["parts"][0]["printability"] = {**broken["parts"][0]["printability"], "ok": False}
    broken["parts"][0]["printability"]["fits_bed"] = False
    assert family_problems(_with_family(_at(60), broken))["G5"]


@pytest.mark.parametrize(
    "row,says",
    [
        ({"value": 90, "out_of_time": True}, "out of time"),
        ({"value": 90, "error": "ValueError: x"}, "could not be verified"),
    ],
)
def test_a_value_not_computed_is_red(row, says):
    problems = family_problems(_with_family(_at(60), row))["G6"]
    assert len(problems) == 1 and says in problems[0] and "width = 90" in problems[0]


def test_a_family_not_computed_is_red_and_says_why():
    verify = _verify()
    verify["family"] = {"sweeps": [], "problems": [], "skipped": "the default version is red"}
    assert "not computed" in family_problems(verify)["G6"][0]
    verify["family"] = {"sweeps": [], "problems": ["family: w is not a top-level parameter"]}
    assert "top-level" in family_problems(verify)["G6"][0]


def test_nothing_declared_nothing_to_judge():
    assert not any(family_problems(_verify()).values())
    assert family_rows(_verify()) is None


def test_the_rows_the_close_and_the_replay_read():
    verify = _with_family(_at(60, 3.0), _at(75, 4.5), _at(90, 7.0, ok=False))
    sweeps = family_rows(verify)
    state = {"gates": {}, "parts": [], "family": sweeps}
    assert sweeps[0]["rows"][2]["ok"] is False
    assert sweeps[0]["rows"][0]["flex"][0]["force_n"] == 3.0
    assert registry(state)["family width"][0]["ok"] is False
    assert summary({**state, "gates": {"G1": {"ok": True, "detail": []}}})["family"] == sweeps


def test_the_curve():
    verify = _with_family(_at(60, 3.0, target=[2, 6]), _at(75, 4.5, target=[2, 6]))
    page = _family({"family": family_rows(verify)})
    assert "Along the range" in page and "<polyline" in page and 'class="target"' in page
    assert "arm / phone at 60: 3.0 N" in page and page.count('class="dot"') == 2
    failed = _with_family(_at(60, 3.0), _at(75, 7.0, ok=False))
    page = _family({"family": family_rows(failed)})
    assert page.count('class="failed"') == 1 and "hollow: over a limit" in page


def test_a_family_with_no_forces_has_its_table_and_no_curve():
    bare = _verify()
    verify = _with_family({"value": 1, **bare}, {"value": 2, **bare})
    page = _family({"family": family_rows(verify)})
    assert "<svg" not in page and page.count("badge ok") == 2


def test_a_session_with_no_family_has_no_section():
    assert _family({}) == ""


def test_a_red_value_taken_out_of_the_range_is_an_adjustment():
    history = SpecHistory()
    first = family_rows(_with_family(_at(60), _at(90, ok=False)))
    assert history.observe_family(first) == []
    second = family_rows(_with_family(_at(60), _at(80)))
    found = history.observe_family(second)
    assert len(found) == 1 and "width = 90 was red" in found[0]["text"]


def test_a_range_made_wider_is_not_an_adjustment():
    history = SpecHistory()
    history.observe_family(family_rows(_with_family(_at(60), _at(90))))
    assert history.observe_family(family_rows(_with_family(_at(60), _at(60), _at(90)))) == []
