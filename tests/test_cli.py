"""The cadverify command without the model: the request it sends and how it waits for answers."""

import json

import pytest

from cadverify import cli
from cadverify.cli import SEED_NOTE, FileAsker, split_request


def test_a_request_without_a_scad_starts_from_an_empty_workspace():
    assert split_request("Design a jar.\n\nWith a lid.\n") == ("Design a jar.\n\nWith a lid.", None)
    assert split_request("Design a jar.\n", add=" Make it pretty. \n") == (
        "Design a jar.\n\nMake it pretty.",
        None,
    )


def test_the_scad_of_a_request_seeds_model_scad():
    request, seed = split_request("Improve this.\n// ===\n//  Jar\nx = 1;\n")
    assert request == "Improve this.\n// ===\n//  Jar\nx = 1;" + SEED_NOTE
    assert seed == b"// ===\n//  Jar\nx = 1;\n"


def test_an_added_paragraph_goes_between_the_request_and_its_scad():
    request, seed = split_request("Improve this.\n// ===\nx = 1;\n", add=" Make it pretty. \n")
    assert request == "Improve this.\n\nMake it pretty.\n// ===\nx = 1;" + SEED_NOTE
    assert seed == b"// ===\nx = 1;\n"


def test_the_asker_writes_the_questions_and_reads_the_answer(tmp_path, capsys):
    (tmp_path / "03.answer.md").write_text("The recommended one.\n", encoding="utf-8")
    assert FileAsker(tmp_path, poll_s=0.01)("PETG pins?", 3) == "The recommended one."
    assert (tmp_path / "03.md").read_text(encoding="utf-8") == "PETG pins?"
    assert capsys.readouterr().out == f"QUESTIONS {tmp_path / '03.md'}\n"


def test_a_session_needs_units_and_budget(tmp_path):
    request = tmp_path / "jar.md"
    request.write_text("Design a jar.\n", encoding="utf-8")
    with pytest.raises(SystemExit, match="--units starts at 1"):
        cli.main(["design", str(request), "--units", "0", "--results", str(tmp_path)])
    with pytest.raises(SystemExit, match="raise the budget"):
        cli.main(["design", str(request), "--results", str(tmp_path), "--budget-usd", "0.5"])


def test_spent_reads_the_ledger_of_the_results_dir(tmp_path, capsys):
    assert cli.main(["spent", "--results", str(tmp_path), "--budget-usd", "20"]) == 0
    assert capsys.readouterr().out == "USD 0.0000 of USD 20.00\n"


def test_spent_prices_each_request_by_its_model(tmp_path, capsys):
    raw = tmp_path / "jar" / "20261101T000000Z" / "raw"
    raw.mkdir(parents=True)
    for i, model in enumerate(("muse-wonder-1.0", "muse-spark-1.3")):
        record = {"request": {"model": model}, "response": {"usage": {"output_tokens": 100_000}}}
        (raw / f"{i}.json").write_text(json.dumps(record), encoding="utf-8")
    assert cli.main(["spent", "--results", str(tmp_path), "--budget-usd", "20"]) == 0
    assert capsys.readouterr().out == "USD 2.4250 of USD 20.00\n"  # 0.1M * (20 + 4.25)


def test_a_contributor_model_only_gets_the_public_requests(tmp_path):
    private = tmp_path / "jar.md"
    private.write_text("Design a jar.\n", encoding="utf-8")
    for flags in (
        ["--model", "muse-spark-1.3-contributor"],
        ["--auditor", "muse-spark-1.3-contributor"],
    ):
        with pytest.raises(SystemExit, match="lets Meta train on what it is sent"):
            cli.main(["design", str(private), "--results", str(tmp_path), *flags])
    public = cli.PUBLIC_REQUESTS / "bayonet_jar.md"
    cli.check_contributor(public, ["muse-spark-1.3-contributor"])
    cli.check_contributor(private, ["muse-spark-1.3", "muse-wonder-1.0"])
    with pytest.raises(SystemExit):  # a path that only looks like it is inside requests/
        cli.check_contributor(cli.PUBLIC_REQUESTS / ".." / "jar.md", ["muse-spark-1.3-contributor"])


def _session(path, model, status, requests, usage, auditor=None):
    path.mkdir(parents=True)
    request = {"usage": usage, "model": model}
    session = {
        "model": model,
        "auditor": auditor or model,
        "status": status,
        "iterations": [{"request": request}] * (requests - 1)
        + [{"request": request, "close": "rejected"}],
        "audits": [{"requests": [{"usage": usage, "model": auditor or model}]}],
        "totals": {"requests": requests, "cost_usd": 0.5 * requests, "wall_s": 60.0 * requests},
    }
    (path / "session.json").write_text(json.dumps(session), encoding="utf-8")


def test_table_puts_the_sessions_of_each_model_side_by_side(tmp_path, capsys):
    usage = {"input_tokens": 0, "cached_tokens": 0, "output_tokens": 1_000_000}
    spark = "muse-spark-1.3-contributor"
    _session(tmp_path / "jar" / "1", spark, "green", 10, usage, auditor="muse-wonder-1.0")
    _session(tmp_path / "jar" / "2", spark, "API error", 20, usage, auditor="muse-wonder-1.0")
    _session(tmp_path / "jar" / "3", "muse-wonder-1.0", "green", 4, usage)
    _session(tmp_path / "jar" / "4", "muse-wonder-1.0", "running", 4, usage)
    assert cli.main(["table", str(tmp_path)]) == 0
    lines = capsys.readouterr().out.splitlines()
    # Spark at Standard: (9 or 19 requests + 1 rejected) x $4.25 + one audit by Wonder at $20.
    assert lines[2] == "| jar | muse-spark-1.3-contributor | 1 of 2 | 15 | 7.50 | 83.75 | 15 | 1 |"
    assert lines[3] == "| jar | muse-wonder-1.0 | 1 of 1 | 4 | 2.00 | 100.00 | 4 | 1 |"
    assert len(lines) == 4
