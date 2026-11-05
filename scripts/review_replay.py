"""How good the reviewer is (agent/review.py), measured before anybody relies on it: defects a user
found in real parts, planted in models that pass every gate, the same models without them, and
green finals of recorded sessions. Hits, false positives and cost.

    # Offline, with a canned reviewer: everything but the model.
    uv run python scripts/review_replay.py results/behaviour/review_eval --fake
    # What a real run may cost at most, and the run.
    uv run python scripts/review_replay.py results/behaviour/review_eval --plan \
        --model muse-wonder-1.0
    uv run python scripts/review_replay.py results/behaviour/review_eval \
        --model muse-wonder-1.0 --reps 2 --budget-usd N

The raw records go under <out_dir>/<model>/raw, where `cadverify spent --results results/behaviour`
counts them. A planted defect counts as a hit when a finding names what it is by the words of
EXPECTED; every finding on a control goes to <out_dir>/findings.md to be read by a person, because
some will be true.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import shutil
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from cadverify import ledger
from cadverify.agent import review
from cadverify.agent.sandbox import Sandbox
from cadverify.agent.tools import ToolBox
from cadverify.config import PROJECT_ROOT, load_env
from cadverify.meta_api import PRICE_PER_MTOK, ApiCall, MetaClient

FIXTURES = PROJECT_ROOT / "tests/fixtures/review"
RESULTS = PROJECT_ROOT / "results"
TOKENS_PER_IMAGE = 2_600  # a view with its cut (the measured line of an image's tokens)
TOKENS_OF_TEXT = 6_000  # the instructions, the request and the numbers, at most


# Each model with a request a person would write, and what a reviewer who found it would say.
PLANTED = {
    "tray": {
        "request": "A parts tray, 80 x 60 x 20 mm, that I pick up by its rim with 200 g of screws "
        "inside.",
        "expected": r"tab|bridge|slit|gap|detach|hang|fall|tear|sever|narrow",
        "where": r"floor|bottom|base",
    },
    "coin_tray": {
        "request": "A coin tray, 60 x 40 x 18 mm, with a scoop in the front wall so my fingers can "
        "reach in and slide the coins out.",
        "expected": r"fin|wall|rib|block|obstruct|baffle|barrier|plate",
        "where": r"scoop|notch|finger|front|opening",
    },
    "snap_tab": {
        "request": "A flat bracket with a springy arm cut out of the plate: the arm bends in the "
        "plane of the plate to let a 6 mm rod snap into its seat.",
        "expected": r"skin|floor|web|membrane|joined|not through|fused|connected|cannot bend|"
        r"can't bend|stiff|rigid|attached",
        "where": r"arm|slot|cantilever",
    },
}
# Green finals of sessions recorded in public, one per request: for false positives.
RECORDED = (
    "stress/ratchet/20261103T034705Z",
    "stress/battery_box/20261103T020825Z",
    "stress/desk_drawers/20261103T022156Z",
    "stress/pi4_case/20261103T025213Z",
    "bench/hinge_box/20261031T171141Z",
)


def cases() -> dict[str, dict[str, Any]]:
    out = {}
    for name, info in PLANTED.items():
        source = (FIXTURES / f"{name}.scad").read_text(encoding="utf-8")
        planted = source.replace("defect = false;", "defect = true;", 1)
        out[f"{name}+defect"] = {**info, "source": {"model.scad": planted}, "kind": "planted"}
        out[f"{name}-control"] = {
            "request": info["request"],
            "source": {"model.scad": source},
            "kind": "control",
        }
    for run in RECORDED:
        folder = RESULTS / run
        session = json.loads((folder / "session.json").read_text(encoding="utf-8"))
        sources = {
            str(path.relative_to(folder / "workspace")): path.read_text(encoding="utf-8")
            for path in (folder / "workspace").rglob("*.scad")
            if "checks" not in path.relative_to(folder / "workspace").parts
        }
        out[f"recorded {run}"] = {
            "request": session["request"],
            "source": sources,
            "kind": "recorded",
        }
    return out


def prepare(name: str, case: dict[str, Any], out_dir: Path) -> dict[str, Any]:
    """The harness's part of a review, once per case: what the reviewer gets, kept on disk."""
    folder = out_dir / "cases" / re.sub(r"[^\w+-]", "_", name)
    saved = folder / "material.json"
    if saved.exists():
        return json.loads(saved.read_text(encoding="utf-8"))
    folder.mkdir(parents=True, exist_ok=True)
    with Sandbox(folder / "workspace") as box:
        box.restore({k: v.encode() for k, v in case["source"].items()})
        toolbox = ToolBox(box, folder / "tools", require_brief=False)
        state = toolbox.gates()
        images = toolbox.review_images(state)
    material = {
        "gates": {k: v["ok"] for k, v in state["gates"].items()},
        "state": {k: state.get(k) for k in ("behaviour", "brief")},
        "images": [{"caption": caption, "url": url} for caption, url in images],
    }
    for i, (_, url) in enumerate(images):
        (folder / f"{i:02d}.png").write_bytes(base64.b64decode(url.split(",", 1)[1]))
    saved.write_text(json.dumps(material), encoding="utf-8")
    shutil.rmtree(folder / "workspace", ignore_errors=True)
    return material


class FakeClient:
    """Finds what was planted and nothing else, at a fixed cost: it tests the pipeline, not a
    reviewer, and whatever it scores means nothing."""

    def responses(self, label: str, **payload: Any) -> ApiCall:
        planted = "defect" in label and "+" in label
        found = {
            "where": "the floor of the scoop, the arm",
            "what": "a fin blocks it, tabs hang it, a skin joins it",
            "confirm_by": "a cut through its middle",
        }
        body = {
            "id": "fake",
            "status": "completed",
            "output": [
                {
                    "type": "message",
                    "content": [
                        {
                            "type": "output_text",
                            "text": json.dumps({"findings": [found] if planted else []}),
                        }
                    ],
                }
            ],
            "usage": {"input_tokens": 0, "output_tokens": 0},
        }
        return ApiCall(label=label, status_code=200, body=body, latency_s=0.0)

    def close(self) -> None:
        pass


def score(name: str, case: dict[str, Any], found: list[dict[str, str]] | None) -> dict[str, Any]:
    row = {"case": name, "kind": case["kind"], "findings": found, "parsed": found is not None}
    if case["kind"] == "planted" and found is not None:
        row["hit"] = any(
            re.search(case["expected"], text, re.I) and re.search(case["where"], text, re.I)
            for text in (f"{f['where']} {f['what']}" for f in found)
        )
    return row


def worst_case(model: str, reps: int, images: int = 12) -> float:
    """Every review answers at its output limit and is retried once, with nothing cached."""
    price = PRICE_PER_MTOK[model]
    each = (TOKENS_OF_TEXT + images * TOKENS_PER_IMAGE) * price["input"]
    each += review.REVIEW_MAX_OUTPUT * price["output"]
    return 2 * reps * len(cases()) * each / 1e6


def table(rows: list[dict[str, Any]], model: str) -> str:
    planted = [r for r in rows if r["kind"] == "planted"]
    controls = [r for r in rows if r["kind"] == "control"]
    recorded = [r for r in rows if r["kind"] == "recorded"]
    usd = sum(r["usd"] for r in rows)
    lines = [
        f"Model {model}, {len(rows)} reviews, USD {usd:.2f}.",
        "",
        "| | Reviews | Result |",
        "|---|--:|---|",
        f"| Planted defect | {len(planted)} | {sum(r.get('hit', False) for r in planted)} found |",
        f"| The same models without it | {len(controls)} "
        f"| {sum(len(r['findings'] or []) for r in controls)} findings, false until read |",
        f"| Recorded green finals | {len(recorded)} "
        f"| {sum(len(r['findings'] or []) for r in recorded)} findings, to be read |",
        f"| No usable answer | {sum(not r['parsed'] for r in rows)} | |",
    ]
    return "\n".join(lines)


def findings_page(rows: list[dict[str, Any]]) -> str:
    parts = ["# Everything the reviewer said, to read by hand\n"]
    for row in rows:
        verdict = f" (hit: {row['hit']})" if "hit" in row else ""
        parts.append(f"\n## {row['case']}, rep {row['rep']}{verdict}\n")
        for found in row["findings"] or []:
            parts.append(
                f"- **{found['where']}**: {found['what']} *Confirm:* {found['confirm_by']}"
            )
        if not row["findings"]:
            parts.append("- none" if row["parsed"] else "- no usable answer")
    return "\n".join(parts) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--model", default="muse-wonder-1.0", choices=sorted(PRICE_PER_MTOK))
    parser.add_argument("--reps", type=int, default=2)
    parser.add_argument("--fake", action="store_true")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--budget-usd", type=float, default=0.0)
    args = parser.parse_args()
    planned = worst_case(args.model, args.reps)
    print(f"{len(cases())} cases, {args.reps} reps, worst case USD {planned:.2f}", flush=True)
    if args.plan:
        return 0
    if args.fake:
        client: Any = FakeClient()
    else:
        ledger.check_budget(planned, RESULTS / "behaviour", args.budget_usd)
        load_env()
        client = MetaClient(raw_dir=args.out_dir / args.model / "raw")
    all_cases = cases()
    material = {name: prepare(name, case, args.out_dir) for name, case in all_cases.items()}

    def one(job: tuple[str, int]) -> dict[str, Any]:
        name, rep = job
        case, ready = all_cases[name], material[name]
        images = [(i["caption"], i["url"]) for i in ready["images"]]
        state = dict(ready["state"])
        found, calls = review.run(
            client, case["request"], state, images, f"{name}-r{rep}", model=args.model
        )
        row = score(name, case, found)
        row.update(
            rep=rep,
            gates=ready["gates"],
            images=len(images),
            usd=sum(c.cost_usd for c in calls),
            attempts=len(calls),
        )
        return row

    jobs = [(name, rep) for name in all_cases for rep in range(1, args.reps + 1)]
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(one, jobs))
    client.close()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    suffix = "-fake" if args.fake else ""
    (args.out_dir / f"rows{suffix}.json").write_text(json.dumps(rows, indent=1), encoding="utf-8")
    (args.out_dir / f"findings{suffix}.md").write_text(findings_page(rows), encoding="utf-8")
    print(table(rows, "canned, not a reviewer" if args.fake else args.model))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
