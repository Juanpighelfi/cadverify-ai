"""The loop with the real print (agent/physical.py, cadverify iterate, cadverify baseline)."""

import json

import pytest

from cadverify import cli
from cadverify.agent import physical
from cadverify.agent.closing import registry
from cadverify.agent.loop import Limits, run_session
from cadverify.agent.tools import ToolBox
from cadverify.cadcheck.spec import SpecError, parse_spec
from cadverify.replay import _physical
from tests.test_agent import FakeModel, FakeSandbox, _verify


def _parse(**extra):
    spec = {"bounds": [[0, 0, 0], [10, 10, 10]], "bodies": 1, "through_holes": 0, **extra}
    return parse_spec(json.dumps([[k, v] for k, v in spec.items()]))


def _report(force=10.0, strain=2.0):
    return {
        "declared": True,
        "flex": [
            {
                "a": "lever",
                "b": "wheel",
                "where": "motion turn",
                "force_n": force,
                "ok": True,
                "parts": [{"instance": "lever", "strain_pct": strain, "compliance_mm_per_n": 0.1}],
            }
        ],
        "loads": [
            {"name": "book", "on": "shelf", "largest_mm": 1.0, "strain_pct": 0.5, "ok": True}
        ],
        "stability": [],
    }


def test_a_baseline_keeps_each_force_and_the_next_version_is_told_as_a_ratio():
    base = physical.baseline_numbers(_report(), "results/x")
    new = _report(force=15.0, strain=3.0)
    new["loads"][0]["largest_mm"] = 0.5
    new["flex"].append({"a": "other", "b": "wheel", "force_n": 3.0, "parts": []})
    physical.relative(new, base)
    assert new["baseline_of"] == "results/x"
    versus = new["flex"][0]["vs_baseline"]
    assert versus == {"force": 1.5, "force_then_n": 10.0, "strain": {"lever": 1.5}}
    assert new["flex"][1]["vs_baseline"] is None  # a new flex has nothing to compare with
    assert new["loads"][0]["vs_baseline"] == {"deflection": 0.5}
    untouched = _report()
    physical.relative(untouched, None)
    assert "baseline_of" not in untouched


def test_a_baseline_is_found_up_the_chain_of_versions(tmp_path):
    first, second = tmp_path / "a", tmp_path / "b"
    first.mkdir(), second.mkdir()
    (first / physical.BASELINE_FILE).write_text(json.dumps({"run": "a"}))
    (first / "session.json").write_text("{}")
    (second / "session.json").write_text(json.dumps({"parent": {"run": str(first)}}))
    assert physical.load_baseline(second) == {"run": "a"}
    (tmp_path / "c").mkdir()
    (tmp_path / "c/session.json").write_text("{}")
    assert physical.load_baseline(tmp_path / "c") is None


def _state(volume=100.0, bodies=1, details=("snap",), loads=True):
    return {
        "parts": [
            {
                "part": "lid",
                "mesh": {
                    "volume_mm3": volume,
                    "bounds": [[0, 0, 0], [10, 10, 10]],
                    "bodies": bodies,
                },
                "spec_check": {"details": [{"name": n} for n in details]},
            }
        ],
        "assembly": {"motions": [{"name": "swing"}]},
        "behaviour": _report() if loads else {},
    }


def test_regression_says_what_changed_and_what_disappeared():
    assert physical.regression(None, _state()) is None
    same = physical.regression(_state(), _state(volume=100.5))
    assert same == {"changed": [], "gone": []}
    moved = physical.regression(_state(), _state(volume=80.0, bodies=2, details=(), loads=False))
    assert moved["changed"][0]["volume_change"] == -0.2
    assert moved["changed"][0]["bodies"] == [1, 2]
    assert "detail lid/snap" in moved["gone"]
    assert "flex lever/wheel" in moved["gone"]
    assert "load book" in moved["gone"]


def test_each_flex_and_load_says_what_to_touch_and_it_has_to_move_what_it_says():
    state = {"behaviour": _report()}
    problems = physical.tune_problems(state)
    assert len(problems) == 2 and all("which parameter" in p for p in problems)
    good = {
        "failure": "too hard",
        "param": "arm",
        "value": 1.4,
        "measure": "flex lever/wheel",
        "ok": True,
        "before": 10.0,
        "after": 8.0,
    }
    still = {
        "failure": "it bends",
        "param": "rib",
        "value": 2,
        "measure": "load book",
        "ok": False,
        "why": "load book went from 0.5 to 0.5, which is nothing",
    }
    state["tune"] = {"rows": [good, still]}
    problems = physical.tune_problems(state)
    assert len(problems) == 1 and "does not fix" in problems[0] and "rib" in problems[0]
    state["tune"]["rows"][1] = {**still, "ok": True}
    assert physical.tune_problems(state) == []
    assert physical.tune_problems({"behaviour": {"flex": [], "loads": []}}) == []
    gates = {g: {"ok": True, "problems": []} for g in ("G1", "G2", "G3", "G4", "G5", "G6", "G7")}
    assert "tune arm" in registry({**state, "gates": gates})


@pytest.mark.parametrize(
    ("item", "says"),
    [
        ([["hard", "1bad", 1, "flex a/b"]], "tune"),
        ([["hard", "arm", 1, "strain"]], "tune"),
        ([["hard", "arm", 1]], "tune"),
        ([[["x"], "arm", 1, "flex a/b"]], "tune"),
        ([["a", "b", 1, "load c"]] * 5, "at most"),
    ],
)
def test_what_a_tune_entry_cannot_be(item, says):
    with pytest.raises(SpecError, match=says):
        _parse(tune=item)


def test_a_probe_says_what_it_stands_for():
    assert _parse(probe_of="flex a/b")["probe_of"] == "flex a/b"
    with pytest.raises(SpecError, match="probe_of"):
        _parse(probe_of="the arm")


def _verified(flex_c=0.1, load_c=0.1, strain=1.0, load_strain=1.0):
    return {
        "behaviour": {
            "flex": [
                {
                    "a": "lever",
                    "b": "wheel",
                    "parts": [
                        {
                            "instance": "lever",
                            "compliance_mm_per_n": flex_c,
                            "strain_pct": strain,
                            "deflection_mm": 1.0,
                        }
                    ],
                }
            ],
            "loads": [
                {
                    "name": "press",
                    "on": "test_arm",
                    "compliance_mm_per_n": load_c,
                    "strain_pct": load_strain,
                    "deflection_mm": 1.0,
                }
            ],
        },
        "parts": [
            {"part": "lever", "export": {"spec": {}}},
            {"part": "test_arm", "export": {"spec": {"probe_of": "flex lever/wheel"}}},
        ],
    }


def test_a_probe_that_does_not_scale_is_told_and_one_that_does_stands_for_the_part():
    from cadverify.cadcheck.verify import is_probe, probes_of

    assert is_probe("test_arm") and not is_probe("arm") and not is_probe(None)
    fine = probes_of(_verified())[0]
    assert fine["represents"] is True and fine["stiffness_vs_real"] == 1.0
    stiff = probes_of(_verified(load_c=0.05))[0]
    assert stiff["represents"] is False and "as stiff" in stiff["why"]
    strained = probes_of(_verified(load_strain=2.0))[0]
    assert strained["represents"] is False and strained["strain_vs_real"] == 2.0
    alone = _verified()
    alone["behaviour"]["loads"] = []
    assert "load of its own" in probes_of(alone)[0]["error"]
    unsaid = _verified()
    unsaid["parts"][1]["export"]["spec"] = {}
    assert "what it stands for" in probes_of(unsaid)[0]["error"]


def test_iterate_starts_with_the_request_the_close_the_brief_and_the_feedback():
    session = {
        "request": "A clip.",
        "iterations": [{"close": "rejected", "text": "no"}, {"close": "accepted", "text": "Done."}],
        "final": {"brief": {"failure_modes": ["snaps off"]}},
    }
    task = physical.iterate_task(session, "The arm broke at the root.", {"run": "x"})
    for said in ("A clip.", "Done.", "The arm broke at the root.", "baseline", "design_brief"):
        assert said in task
    assert "baseline" not in physical.iterate_task(session, "ok", None)
    assert "did not close" in physical.iterate_task({"request": "A"}, "ok", None)


def test_the_photo_goes_with_the_first_message_and_a_new_brief_is_required(tmp_path):
    client = FakeModel(["No more."])
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    box = ToolBox(FakeSandbox(workspace, _verify()), tmp_path / "tools")
    assert box.brief is None and box.require_brief
    image = "data:image/png;base64,AAAA"
    session = run_session(
        client,
        box,
        "Next version.",
        Limits(max_requests=1, max_cost_usd=1.0),
        tmp_path,
        first_images=[image],
        parent={"run": "a", "feedback": "It broke."},
    )
    first = client.payloads[0]["input"][0]["content"]
    assert first[0] == {"type": "input_text", "text": "Next version."}
    assert first[1] == {"type": "input_image", "image_url": image}
    assert session["parent"]["feedback"] == "It broke."


def test_the_replay_shows_what_came_back_and_what_to_touch():
    final = {
        "behaviour": {
            "flex": [
                {
                    "a": "lever",
                    "b": "wheel",
                    "force_n": 15.0,
                    "vs_baseline": {"force": 1.5, "force_then_n": 10.0},
                }
            ]
        },
        "regression": {
            "changed": [{"part": "lid", "volume_change": -0.2, "bodies": [1, 2]}],
            "gone": ["detail lid/snap"],
        },
        "probes": [
            {"part": "test_arm", "of": "flex lever/wheel", "why": "it is 2.00 times as stiff"}
        ],
        "tune": {
            "rows": [
                {
                    "failure": "too hard",
                    "param": "arm",
                    "value": 1.4,
                    "measure": "flex lever/wheel",
                    "before": 10.0,
                    "after": 8.0,
                }
            ]
        },
    }
    page = _physical(final, {"parent": {"feedback": "It <broke>.", "photo": True}})
    for said in ("It &lt;broke&gt;.", "With a photo", "detail lid/snap", "1.5 times", "as stiff"):
        assert said in page
    assert "arm = 1.4" in page and "-20.0%" in page
    assert _physical({}, {}) == ""


def test_iterate_keeps_private_things_from_a_contributor_model(tmp_path, monkeypatch):
    public = tmp_path / "requests"
    public.mkdir()
    (public / "bayonet_jar.md").write_text("A jar.")
    monkeypatch.setattr(cli, "PUBLIC_REQUESTS", public)
    run = tmp_path / "bayonet_jar" / "20260101T000000Z"
    run.mkdir(parents=True)
    photo = tmp_path / "x.jpg"
    photo.write_bytes(b"x")
    model = ["muse-spark-1.3-contributor"]
    with pytest.raises(SystemExit, match="not a photo"):
        cli.check_iterate_contributor(run, None, photo, model)
    with pytest.raises(SystemExit, match="only a session from a public"):
        cli.check_iterate_contributor(run, None, None, model)
    public_file = cli.PUBLIC_REQUESTS / "bayonet_jar.md"
    cli.check_iterate_contributor(run, public_file, None, model)
    private_run = tmp_path / "my_own_thing" / "20260101T000000Z"
    with pytest.raises(SystemExit, match="only a session from a public"):
        cli.check_iterate_contributor(private_run, public_file, None, model)
    cli.check_iterate_contributor(run, None, photo, ["muse-wonder-1.0"])


class _Box(FakeSandbox):
    """The fake sandbox as a context manager, as the CLI opens the real one."""

    made: list = []

    def __init__(self, workspace):
        workspace.mkdir(parents=True, exist_ok=True)
        super().__init__(workspace, _verify())
        _Box.made.append(self)

    def restore(self, files):
        self.restored = files
        super().restore(files)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def _recorded(tmp_path):
    run = tmp_path / "old" / "clip" / "20260101T000000Z"
    (run / "workspace").mkdir(parents=True)
    (run / "workspace/model.scad").write_text("cube(1);\n// seed")
    session = {
        "request": "A clip.",
        "requirements": {"units": 2},
        "iterations": [{"close": "accepted", "text": "Closed."}],
        "final": {"brief": {"chosen": "thin arm"}, "parts": []},
    }
    (run / "session.json").write_text(json.dumps(session))
    return run


def test_iterate_runs_a_session_from_the_version_with_what_the_user_said(tmp_path, monkeypatch):
    run = _recorded(tmp_path)
    results = tmp_path / "new"
    client = FakeModel(["Nothing else."])
    client.close = lambda: None
    monkeypatch.setattr(cli, "make_client", lambda run_dir: client)
    monkeypatch.setattr(cli, "Sandbox", _Box)
    code = cli.main(
        ["iterate", str(run), "--feedback", "The arm broke.", "--results", str(results)]
        + ["--budget-usd", "20", "--max-requests", "1"]
    )
    assert code == 0
    first = client.payloads[0]["input"]
    assert "The arm broke." in first and "A clip." in first and "Closed." in first
    written = next(results.glob("clip/*/session.json"))
    session = json.loads(written.read_text())
    assert session["parent"] == {"run": str(run), "feedback": "The arm broke.", "photo": False}
    assert session["requirements"] == {"units": 2}
    assert _Box.made[-1].restored["model.scad"] == b"cube(1);\n// seed"


def test_iterate_needs_something_said(tmp_path):
    run = _recorded(tmp_path)
    with pytest.raises(SystemExit, match="Say what happened"):
        cli.main(["iterate", str(run), "--results", str(tmp_path / "new")])


def test_a_baseline_is_written_next_to_the_session_and_changes_nothing_else(tmp_path, monkeypatch):
    run = _recorded(tmp_path)
    (run / "workspace/checks").mkdir()
    (run / "workspace/checks/x.scad").write_text("skip")

    class Box(_Box):
        def cadcheck(self, args, stdin=None, timeout_s=300):
            self.args = args
            return {"ok": True, "behaviour": _report()}

    monkeypatch.setattr(cli, "Sandbox", Box)
    assert cli.main(["baseline", str(run), "--material", "PETG"]) == 0
    assert "PETG" in Box.made[-1].args and "x.scad" not in str(Box.made[-1].restored)
    saved = json.loads((run / physical.BASELINE_FILE).read_text())
    assert saved["flex"]["lever/wheel"]["force_n"] == 10.0
    assert physical.load_baseline(run) == saved

    class Empty(Box):
        def cadcheck(self, args, stdin=None, timeout_s=300):
            return {"ok": True, "behaviour": {"problems": ["nothing"]}}

    monkeypatch.setattr(cli, "Sandbox", Empty)
    with pytest.raises(SystemExit, match="nothing computed"):
        cli.main(["baseline", str(run)])


def test_a_new_part_in_the_replay_is_new_with_no_change_to_show():
    """A new part carries its own one box and its count of bodies, not a before and an after."""
    new = {
        "part": "probe",
        "new": True,
        "volume_mm3": 10.0,
        "bounds": [[0, 0, 0], [1, 1, 1]],
        "bodies": 1,
    }
    page = _physical({"regression": {"changed": [new], "gone": []}}, {})
    assert "<td>probe</td><td>new</td>" in page
