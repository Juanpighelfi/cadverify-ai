"""The cadverify command without the model: the request it sends and how it waits for answers."""

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
