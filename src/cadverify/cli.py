"""CADVerify: a verified OpenSCAD design agent on the Meta Model API.

uv run cadverify design requests/bayonet_jar.md          # one design session (uses the API)
uv run cadverify design request.md --add "One more requirement."  # one more paragraph
uv run cadverify design request.md --seed <run>/workspace/model.scad  # go on from a design
uv run cadverify design request.md --units 2 --max-usd 4  # two chained units, USD 4 at most
uv run cadverify design request.md --model muse-spark-1.3 --auditor muse-wonder-1.0
uv run cadverify iterate <run> --feedback "It snaps too hard." --photo x.jpg  # the next version
uv run cadverify baseline <run> --material PLA              # "this version worked" (no model)
uv run cadverify summary results/design/<request>/<UTC>   # a session in Markdown
uv run cadverify replay results/design/<request>/<UTC>    # the session as a static page
uv run cadverify table results/bench                        # sessions side by side, per model
uv run cadverify index results/design results/bench         # index.html linking every replay
uv run cadverify spent                                     # USD spent under the results dir
uv run cadverify hostile                                   # hostile cases in the real sandbox

A request is a Markdown file. If it carries a starting .scad (everything from its first line that
starts with //), that is model.scad when the session starts, and the request says so in one added
line. --seed gives that .scad from a file instead (the model.scad of a session that stopped, to go
on from it). --add puts one more paragraph between the request and its .scad.

Each session runs in a new sandbox container, with the full tool set and gates G1 to G8, and
records everything under <results>/<request name>/<UTC>/: raw/ (every request, without the key),
tools/ (every tool call and its result), workspace/ (the .scad, the meshes and the images) and
session.json. Before it starts, the ledger checks what the requests under <results> cost against
--budget-usd; the session stops at --max-usd, --max-requests or --max-minutes, and is told when
about 10 requests are left.

--model designs and --auditor audits the close (G8), both muse-wonder-1.0 by default. A
"-contributor" model lets Meta train on what it is sent: only the public requests of requests/
may go to one.

Questions: before its first edit, a reply without tools goes to the user (cadverify.agent.loop).
The session writes it to <run>/questions/NN.md, prints that path, and waits for the answer in
<run>/questions/NN.answer.md. Write the answer to another name and rename it, so the session
never reads half a file.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from dataclasses import replace
from pathlib import Path

from cadverify import hostile, ledger, replay, summary
from cadverify.agent import physical, world
from cadverify.agent.loop import Limits, run_session
from cadverify.agent.prompts import SEED_NOTE
from cadverify.agent.sandbox import Sandbox
from cadverify.agent.tools import ToolBox
from cadverify.config import PROJECT_ROOT, load_env, make_client
from cadverify.meta_api import MODEL, PRICE_PER_MTOK

RESULTS = PROJECT_ROOT / "results" / "design"
PUBLIC_REQUESTS = PROJECT_ROOT / "requests"
BUDGET_USD = 20.0  # set by the user for the demo pieces (2026-10-30)
# One session: 64k of output per response (reasoning included), told 10 requests before the end.
LIMITS = Limits(
    max_requests=100,
    max_cost_usd=6.0,
    max_wall_s=3600.0,
    max_output_tokens=64_000,
    wrap_up_requests=10,
)
MAX_LIVE_IMAGES = 40  # more than this in the context and the oldest leave it (agent/loop.py)
MIN_SESSION_USD = 1.0


def split_request(text: str, add: str = "", seed: str | None = None) -> tuple[str, bytes | None]:
    """The request for the model and the .scad it carries, if any, which seeds model.scad. `add`
    is one more paragraph for the request, after its text and before the .scad. `seed` is a .scad
    from elsewhere (a previous session's model.scad) for a request that carries none."""
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.startswith("//")), None)
    request = "".join(lines[:start]).rstrip()
    if add.strip():
        request += "\n\n" + add.strip()
    if start is not None:
        if seed is not None:
            raise ValueError("the request already carries a .scad: --seed would replace it")
        seed = "".join(lines[start:])
    if seed is None:
        return request, None
    fenced = f"\n\n```openscad\n{seed.rstrip()}\n```"
    return request + fenced + SEED_NOTE, seed.encode("utf-8")


class FileAsker:
    """Writes the model's questions to <directory>/NN.md and waits for NN.answer.md."""

    def __init__(self, directory: Path, poll_s: float = 2.0):
        self.directory = directory
        self.poll_s = poll_s

    def __call__(self, questions: str, iteration: int) -> str:
        self.directory.mkdir(parents=True, exist_ok=True)
        asked = self.directory / f"{iteration:02d}.md"
        answer = self.directory / f"{iteration:02d}.answer.md"
        asked.write_text(questions, encoding="utf-8")
        print(f"QUESTIONS {asked}", flush=True)
        while not answer.exists():
            time.sleep(self.poll_s)
        return answer.read_text(encoding="utf-8").strip()


def check_contributor(request: Path, models: list[str]) -> None:
    """A contributor model only gets the public requests: Meta trains on what it is sent."""
    contributors = [m for m in models if m.endswith("-contributor")]
    if contributors and not request.resolve().is_relative_to(PUBLIC_REQUESTS):
        raise SystemExit(
            f"{contributors[0]} lets Meta train on what it is sent: only the public requests "
            f"in {PUBLIC_REQUESTS} may go to it."
        )


def session_cap(max_usd: float, budget_usd: float, spent_usd: float) -> float:
    """What the session may spend: --max-usd, or less when the budget has less left; refused
    when the budget leaves less than USD 1 of it (too little for a session to get anywhere). A
    smaller --max-usd is the user's own choice, for a cheaper model or a short session."""
    if max_usd <= 0:
        raise SystemExit("--max-usd must be above 0.")
    left = budget_usd - spent_usd
    if left < min(max_usd, MIN_SESSION_USD):
        raise SystemExit(f"USD {left:.2f} left of USD {budget_usd:.2f}: raise the budget.")
    return min(max_usd, left)


def design(args: argparse.Namespace) -> int:
    check_contributor(
        args.request, [args.model, args.auditor, args.reviewer or args.auditor, args.lookup or ""]
    )
    try:
        request, seed = split_request(
            args.request.read_text(encoding="utf-8"),
            args.add,
            args.seed.read_text(encoding="utf-8") if args.seed else None,
        )
    except ValueError as exc:
        raise SystemExit(f"{args.request}: {exc}") from None
    if args.units < 1:
        raise SystemExit("--units starts at 1.")
    limits = replace(
        LIMITS,
        max_requests=args.max_requests,
        max_cost_usd=session_cap(args.max_usd, args.budget_usd, ledger.spent_usd(args.results)),
        max_wall_s=args.max_minutes * 60,
        max_live_images=MAX_LIVE_IMAGES,
    )
    ledger.check_budget(limits.max_cost_usd, args.results, args.budget_usd)
    print(f"Session cap: USD {limits.max_cost_usd:.2f}", flush=True)
    run_dir = ledger.new_run_dir(args.results, args.request.stem)
    print(run_dir, flush=True)
    client = make_client(run_dir)
    try:
        with Sandbox(run_dir / "workspace") as box:
            if seed is not None:
                box.restore({"model.scad": seed})
            toolbox = ToolBox(
                box,
                run_dir / "tools",
                requirements={"units": args.units},
                searcher=world.Searcher(client, args.lookup) if args.lookup else None,
            )
            asker = FileAsker(run_dir / "questions")
            session = run_session(
                client,
                toolbox,
                request,
                limits,
                run_dir,
                asker=asker,
                model=args.model,
                auditor=args.auditor,
                reviewer=args.reviewer or args.auditor,
            )
    finally:
        client.close()
    print(session["status"], json.dumps(session["totals"]), flush=True)
    if "final" in session:
        print(json.dumps({k: v["ok"] for k, v in session["final"]["gates"].items()}), flush=True)
    return 0


def check_iterate_contributor(
    run: Path, feedback_file: Path | None, photo: Path | None, models: list[str]
) -> None:
    """Meta trains on what a contributor model gets: a photo or the user's own words are neither
    public nor theirs to give away by accident, so only a file of requests/ goes to one, on top of a
    session that came from a public request."""
    contributors = [m for m in models if m.endswith("-contributor")]
    if not contributors:
        return
    if photo is not None:
        raise SystemExit(f"{contributors[0]} lets Meta train on what it is sent: not a photo.")
    public = (PUBLIC_REQUESTS / f"{run.resolve().parent.name}.md").exists()
    written = feedback_file and feedback_file.resolve().is_relative_to(PUBLIC_REQUESTS)
    if not (public and written):
        raise SystemExit(
            f"{contributors[0]} lets Meta train on what it is sent: only a session from a public "
            f"request, with its feedback in a file of {PUBLIC_REQUESTS} (--feedback-file)."
        )


def iterate(args: argparse.Namespace) -> int:
    """A new session from a version that was printed, with what the user found (agent/physical)."""
    check_iterate_contributor(
        args.run,
        args.feedback_file,
        args.photo,
        [args.model, args.auditor, args.reviewer or args.auditor, args.lookup or ""],
    )
    if bool(args.feedback) == bool(args.feedback_file):
        raise SystemExit("Say what happened: one of --feedback or --feedback-file.")
    feedback = args.feedback or args.feedback_file.read_text(encoding="utf-8")
    parent = json.loads((args.run / "session.json").read_text(encoding="utf-8"))
    seed = (args.run / "workspace/model.scad").read_bytes()
    baseline = physical.load_baseline(args.run)
    limits = replace(
        LIMITS,
        max_requests=args.max_requests,
        max_cost_usd=session_cap(args.max_usd, args.budget_usd, ledger.spent_usd(args.results)),
        max_wall_s=args.max_minutes * 60,
        max_live_images=MAX_LIVE_IMAGES,
    )
    ledger.check_budget(limits.max_cost_usd, args.results, args.budget_usd)
    print(f"Session cap: USD {limits.max_cost_usd:.2f}", flush=True)
    run_dir = ledger.new_run_dir(args.results, args.run.resolve().parent.name)
    print(run_dir, flush=True)
    client = make_client(run_dir)
    try:
        with Sandbox(run_dir / "workspace") as box:
            box.restore({"model.scad": seed})
            toolbox = ToolBox(
                box,
                run_dir / "tools",
                requirements=parent.get("requirements") or {"units": args.units},
                baseline=baseline,
                parent_final=parent.get("final"),
                searcher=world.Searcher(client, args.lookup) if args.lookup else None,
            )
            first_images = []
            if args.photo:
                url = toolbox.photo_url(args.photo.name, args.photo.read_bytes())
                if url is None:
                    raise SystemExit(f"{args.photo}: not an image the sandbox could read.")
                first_images.append(url)
            session = run_session(
                client,
                toolbox,
                physical.iterate_task(parent, feedback, baseline),
                limits,
                run_dir,
                asker=FileAsker(run_dir / "questions"),
                model=args.model,
                auditor=args.auditor,
                reviewer=args.reviewer or args.auditor,
                first_images=first_images,
                parent={"run": str(args.run), "feedback": feedback, "photo": bool(args.photo)},
            )
    finally:
        client.close()
    print(session["status"], json.dumps(session["totals"]), flush=True)
    return 0


def baseline(args: argparse.Namespace) -> int:
    """The user says this version worked: its numbers, measured now, in <run>/baseline.json. Costs
    no model; the session's own files are only read."""
    workspace = args.run / "workspace"
    files = {
        str(p.relative_to(workspace)): p.read_bytes()
        for p in workspace.rglob("*.scad")
        if p.relative_to(workspace).parts[0] != "checks"
    }
    with tempfile.TemporaryDirectory() as work, Sandbox(Path(work)) as box:
        box.restore(files)
        args_ = ["behaviour", "model.scad", "--out-dir", "checks/behaviour"]
        args_ += ["--material", args.material]
        result = box.cadcheck(args_, timeout_s=physical.BASELINE_TIMEOUT_S)
    report = result.get("behaviour") or {}
    if not report.get("flex") and not report.get("loads"):
        raise SystemExit(f"{args.run}: nothing computed to compare with: {report.get('problems')}")
    numbers = physical.baseline_numbers(report, str(args.run))
    out = args.run / physical.BASELINE_FILE
    out.write_text(json.dumps(numbers, indent=1), encoding="utf-8")
    print(out)
    print(json.dumps(numbers))
    return 0


def run_hostile() -> int:
    load_env()  # only to check, on the host, that the key's value never comes out
    run_dir = ledger.new_run_dir(PROJECT_ROOT / "results", "hostile")
    print(run_dir)
    results = hostile.run_all(run_dir, os.environ.get("MODEL_API_KEY") or None)
    for case in results:
        verdict = "contained" if case["passed"] else f"NOT CONTAINED {case['error'] or ''}"
        print(f"{case['case']:26} {verdict} ({case['seconds']} s)")
    held = sum(c["passed"] for c in results)
    print(f"{held} of {len(results)} attacks contained; each one in {run_dir}/<attack>/case.json")
    return 0 if held == len(results) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cadverify", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("design", help="one design session on a request file")
    run.add_argument("request", type=Path)
    run.add_argument("--add", default="", help="one more paragraph for the request")
    run.add_argument(
        "--seed", type=Path, help="a .scad that starts as model.scad (a previous session's)"
    )
    run.add_argument("--units", type=int, default=1, help="chained units the assembly shows")
    run.add_argument("--max-usd", type=float, default=LIMITS.max_cost_usd)
    run.add_argument("--max-requests", type=int, default=LIMITS.max_requests)
    run.add_argument("--max-minutes", type=float, default=LIMITS.max_wall_s / 60)
    run.add_argument("--model", choices=sorted(PRICE_PER_MTOK), default=MODEL)
    run.add_argument("--auditor", choices=sorted(PRICE_PER_MTOK), default=MODEL)
    run.add_argument(
        "--reviewer",
        choices=sorted(PRICE_PER_MTOK),
        help="looks at the product, the auditor's model by default",
    )
    again = sub.add_parser("iterate", help="the next version of a session, after a real print")
    again.add_argument("run", type=Path, help="the session it starts from")
    again.add_argument("--feedback", default="", help="what happened when you used it")
    again.add_argument("--feedback-file", type=Path, help="the same, from a file")
    again.add_argument("--photo", type=Path, help="a photo of it")
    again.add_argument(
        "--units", type=int, default=1, help="chained units, for a session that did not record it"
    )
    again.add_argument("--max-usd", type=float, default=LIMITS.max_cost_usd)
    again.add_argument("--max-requests", type=int, default=LIMITS.max_requests)
    again.add_argument("--max-minutes", type=float, default=LIMITS.max_wall_s / 60)
    again.add_argument("--model", choices=sorted(PRICE_PER_MTOK), default=MODEL)
    again.add_argument("--auditor", choices=sorted(PRICE_PER_MTOK), default=MODEL)
    again.add_argument("--reviewer", choices=sorted(PRICE_PER_MTOK))
    good = sub.add_parser("baseline", help="this version worked: new forces compare with it")
    good.add_argument("run", type=Path)
    good.add_argument("--material", default="PLA")
    for command in (run, again):
        command.add_argument(
            "--lookup",
            choices=sorted(PRICE_PER_MTOK),
            help="the model that searches the web for the designer (web_lookup); off without it",
        )
    spent = sub.add_parser("spent", help="USD spent under the results directory")
    for command in (run, again, spent):
        command.add_argument("--results", type=Path, default=RESULTS)
        command.add_argument("--budget-usd", type=float, default=BUDGET_USD)
    sub.add_parser("summary", help="a session in Markdown").add_argument("run_dir", type=Path)
    sub.add_parser("replay", help="a session as <run>/replay.html").add_argument(
        "run_dir", type=Path
    )
    sub.add_parser("table", help="the sessions of a results dir, per model").add_argument(
        "results", type=Path
    )
    index = sub.add_parser("index", help="one page linking the replays of results dirs")
    index.add_argument("results", type=Path, nargs="+")
    index.add_argument("--out", type=Path, default=Path("index.html"))
    sub.add_parser("hostile", help="hostile cases against the real sandbox")
    args = parser.parse_args(argv)

    if args.command == "spent":
        print(f"USD {ledger.spent_usd(args.results):.4f} of USD {args.budget_usd:.2f}")
        return 0
    if args.command == "summary":
        print(summary.markdown(args.run_dir))
        return 0
    if args.command == "replay":
        print(replay.write(args.run_dir))
        return 0
    if args.command == "table":
        print(summary.table(args.results))
        return 0
    if args.command == "index":
        print(replay.write_index(args.results, args.out))
        return 0
    if args.command == "hostile":
        return run_hostile()
    if args.command == "iterate":
        return iterate(args)
    if args.command == "baseline":
        return baseline(args)
    return design(args)


if __name__ == "__main__":
    raise SystemExit(main())
