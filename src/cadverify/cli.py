"""CADVerify: a verified OpenSCAD design agent on the Meta Model API.

uv run cadverify design requests/bayonet_jar.md          # one design session (uses the API)
uv run cadverify design request.md --add "One more requirement."  # one more paragraph
uv run cadverify design request.md --units 2 --max-usd 4  # two chained units, USD 4 at most
uv run cadverify design request.md --model muse-spark-1.3 --auditor muse-wonder-1.0
uv run cadverify summary results/design/<request>/<UTC>   # a session in Markdown
uv run cadverify replay results/design/<request>/<UTC>    # the session as a static page
uv run cadverify table results/bench                        # sessions side by side, per model
uv run cadverify spent                                     # USD spent under the results dir
uv run cadverify hostile                                   # hostile cases in the real sandbox

A request is a Markdown file. If it carries a starting .scad (everything from its first line that
starts with //), that is model.scad when the session starts, and the request says so in one added
line. --add puts one more paragraph between the request and its .scad.

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
import time
from dataclasses import replace
from pathlib import Path

from cadverify import hostile, ledger, replay, summary
from cadverify.agent.loop import Limits, run_session
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
SEED_NOTE = "\n\n(The .scad of this message is already model.scad, in your workspace.)"


def split_request(text: str, add: str = "") -> tuple[str, bytes | None]:
    """The request for the model and the .scad it carries, if any, which seeds model.scad. `add`
    is one more paragraph for the request, after its text and before the .scad."""
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.startswith("//")), None)
    request = "".join(lines[:start]).rstrip()
    if add.strip():
        request += "\n\n" + add.strip()
    if start is None:
        return request, None
    scad = "".join(lines[start:])
    return request + "\n" + scad.rstrip() + SEED_NOTE, scad.encode("utf-8")


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


def design(args: argparse.Namespace) -> int:
    check_contributor(args.request, [args.model, args.auditor])
    request, seed = split_request(args.request.read_text(encoding="utf-8"), args.add)
    if args.units < 1:
        raise SystemExit("--units starts at 1.")
    left = args.budget_usd - ledger.spent_usd(args.results)
    limits = replace(
        LIMITS,
        max_requests=args.max_requests,
        max_cost_usd=min(args.max_usd, left),
        max_wall_s=args.max_minutes * 60,
        max_live_images=MAX_LIVE_IMAGES,
    )
    if limits.max_cost_usd < 1.0:
        raise SystemExit(f"USD {left:.2f} left of USD {args.budget_usd:.2f}: raise the budget.")
    ledger.check_budget(limits.max_cost_usd, args.results, args.budget_usd)
    print(f"Session cap: USD {limits.max_cost_usd:.2f}", flush=True)
    run_dir = ledger.new_run_dir(args.results, args.request.stem)
    print(run_dir, flush=True)
    client = make_client(run_dir)
    try:
        with Sandbox(run_dir / "workspace") as box:
            if seed is not None:
                box.restore({"model.scad": seed})
            toolbox = ToolBox(box, run_dir / "tools", requirements={"units": args.units})
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
            )
    finally:
        client.close()
    print(session["status"], json.dumps(session["totals"]), flush=True)
    if "final" in session:
        print(json.dumps({k: v["ok"] for k, v in session["final"]["gates"].items()}), flush=True)
    return 0


def run_hostile() -> int:
    load_env()  # only to check, on the host, that the key's value never comes out
    run_dir = ledger.new_run_dir(PROJECT_ROOT / "results", "hostile")
    print(run_dir)
    results = hostile.run_all(run_dir, os.environ.get("MODEL_API_KEY") or None)
    print(json.dumps({c["case"]: c["passed"] for c in results}, indent=2))
    return 0 if all(c["passed"] for c in results) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="cadverify", description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("design", help="one design session on a request file")
    run.add_argument("request", type=Path)
    run.add_argument("--add", default="", help="one more paragraph for the request")
    run.add_argument("--units", type=int, default=1, help="chained units the assembly shows")
    run.add_argument("--max-usd", type=float, default=LIMITS.max_cost_usd)
    run.add_argument("--max-requests", type=int, default=LIMITS.max_requests)
    run.add_argument("--max-minutes", type=float, default=LIMITS.max_wall_s / 60)
    run.add_argument("--model", choices=sorted(PRICE_PER_MTOK), default=MODEL)
    run.add_argument("--auditor", choices=sorted(PRICE_PER_MTOK), default=MODEL)
    spent = sub.add_parser("spent", help="USD spent under the results directory")
    for command in (run, spent):
        command.add_argument("--results", type=Path, default=RESULTS)
        command.add_argument("--budget-usd", type=float, default=BUDGET_USD)
    sub.add_parser("summary", help="a session in Markdown").add_argument("run_dir", type=Path)
    sub.add_parser("replay", help="a session as <run>/replay.html").add_argument(
        "run_dir", type=Path
    )
    sub.add_parser("table", help="the sessions of a results dir, per model").add_argument(
        "results", type=Path
    )
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
    if args.command == "hostile":
        return run_hostile()
    return design(args)


if __name__ == "__main__":
    raise SystemExit(main())
