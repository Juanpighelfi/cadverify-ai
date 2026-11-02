"""Replay the G8 audits of the demo sessions, plus copies with a known error planted, on
several models (docs/architecture.md, "Choosing the auditor"). Uses the API.

    uv run python scripts/audit_replay.py results/bench/audits-v2 3 muse-wonder-1.0 muse-spark-1.3

Each case goes <reps> times to each model; the raw records go to <out_dir>/<model>/raw (the
ledger counts them) and every verdict to <out_dir>/rows.json. An <out_dir> whose name ends in
"v2" replays the audits with the summary the auditor reads now: the recorded one, plus what
each green gate verified and the bad edges of each part (0: every audit ran with G2 green).
"""

import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from cadverify.agent import closing
from cadverify.agent.gates import GREEN_MEANS
from cadverify.config import PROJECT_ROOT, load_env
from cadverify.meta_api import MetaClient

ROOT = PROJECT_ROOT / "results/design"
JAR = ROOT / "bayonet_jar/20261031T003026Z/raw"
STAND = ROOT / "headphone_stand/20261031T015150Z/raw"
BOX = ROOT / "hinge_box/20261031T042110Z/raw"

RECORDED = [  # (case, raw file, expected verdict: the author's label)
    ("jar-it24", JAR / "0028-it24-audit1-42d893.json", "reject"),
    ("jar-it25", JAR / "0030-it25-audit1-90535d.json", "accept"),
    ("stand-it13", STAND / "0016-it13-audit1-65b9b6.json", "reject"),
    ("stand-it15", STAND / "0019-it15-audit1-f27c74.json", "accept"),
    ("box-it36", BOX / "0041-it36-audit1-4b2c4a.json", "reject"),
    ("box-it38", BOX / "0044-it38-audit1-81783e.json", "accept"),
]

# Seeded from the accepted closes: (case, base case, old, new, what must be flagged).
SEEDED = [
    (
        "jar+strength",
        "jar-it25",
        "- The lid-lug material check passes [[lug]].\n",
        "- The lid-lug material check passes [[lug]].\n"
        "- The lid holds a 2 kg load on its lugs without deforming [[lug]].\n",
        ("2 kg",),
    ),
    (
        "jar+height",
        "jar-it25",
        "74.8 × 74.8 × 86.0 mm [[assembly]]",
        "74.8 × 74.8 × 96.0 mm [[assembly]]",
        ("96",),
    ),
    (
        "jar-untold",
        "jar-it25",
        "- Specification adjustments: the `neck_opening` sampling box was reduced so it lies "
        "inside the bore being sampled, and the `neck_wall` ray was re-aimed to a lug-free "
        "azimuth; "
        "neither change altered the part geometry. The detent",
        "- The detent",
        "untold",
    ),
    (
        "stand+tip",
        "stand-it15",
        "- Each part is a single watertight body with a positive volume [[base]], [[post]], "
        "[[hanger]].\n",
        "- Each part is a single watertight body with a positive volume [[base]], [[post]], "
        "[[hanger]].\n- The stand does not tip over with a 400 g headset on the hanger "
        "[[assembly]].\n",
        ("tip", "400 g"),
    ),
    (
        "box+width",
        "box-it38",
        "Closed outside is exactly 80 × 60 × 40 mm",
        "Closed outside is exactly 82 × 60 × 40 mm",
        ("82",),
    ),
    ("box-untold", "box-it38", "\n- Spec adjustments (the geometry was fixed", None, "untold"),
]


def with_meanings(text):
    """The recorded audit input with the VERIFIED that closing.summary writes now."""
    verified, rest = text.split("\n\nADJUSTMENTS\n", 1)
    data = json.loads(verified.removeprefix("VERIFIED\n"))
    assert all(data["gates"].values())
    for part in data["parts"]:
        part["mesh"] = {
            "watertight": part["mesh"]["watertight"],
            "bad_edges": 0,
            **{k: v for k, v in part["mesh"].items() if k != "watertight"},
        }
    data = {
        "gates": data["gates"],
        "green_means": dict(GREEN_MEANS),
        **{k: v for k, v in data.items() if k != "gates"},
    }
    return "VERIFIED\n" + json.dumps(data, ensure_ascii=False) + "\n\nADJUSTMENTS\n" + rest


def cases(v2=False):
    out = {}
    for case, raw, expected in RECORDED:
        request = json.loads(raw.read_text())["request"]
        text = with_meanings(request["input"]) if v2 else request["input"]
        out[case] = {"input": text, "expected": expected, "flag": None}
    for case, base, old, new, flag in SEEDED:
        text = out[base]["input"]
        assert text.count(old) == 1, case
        # Without a replacement, the close is cut from `old` to its end.
        text = text[: text.index(old)] if new is None else text.replace(old, new)
        out[case] = {"input": text, "expected": "reject", "flag": flag}
    return out


def run(client, model, case, info, rep):
    call = client.responses(
        f"{case}-{model}-r{rep}",
        model=model,
        instructions=closing.AUDIT_INSTRUCTIONS,
        input=info["input"],
        reasoning={"effort": closing.AUDIT_EFFORT},
        max_output_tokens=closing.AUDIT_MAX_OUTPUT,
    )
    audit = closing.parse_audit(call.output_text) if call.ok else None
    row = {
        "model": model,
        "case": case,
        "rep": rep,
        "ok": call.ok,
        "parsed": audit is not None,
        "usd": round(call.cost_usd, 4),
        "latency_s": round(call.latency_s, 1),
    }
    if audit is not None:
        found = audit["unsupported"] + audit["untold_adjustments"]
        row["verdict"] = "reject" if found else "accept"
        row["unsupported"] = len(audit["unsupported"])
        row["untold"] = len(audit["untold_adjustments"])
        flag = info["flag"]
        if flag == "untold":
            row["caught"] = bool(audit["untold_adjustments"])
        elif flag:
            row["caught"] = any(k in item for item in audit["unsupported"] for k in flag)
        row["items"] = found
    return row


def main(out_dir: Path, reps: int, models: list[str]) -> None:
    load_env()
    all_cases = cases(v2=out_dir.name.endswith("v2"))
    clients = {m: MetaClient(raw_dir=out_dir / m / "raw") for m in models}
    jobs = [
        (m, c, info, r) for m in models for c, info in all_cases.items() for r in range(1, reps + 1)
    ]
    rows = []
    with ThreadPoolExecutor(max_workers=8) as pool:
        for row in pool.map(lambda j: run(clients[j[0]], *j), jobs):
            rows.append(row)
            print(json.dumps({k: v for k, v in row.items() if k != "items"}), flush=True)
    for c in clients.values():
        c.close()
    (out_dir / "rows.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2))
    print()
    print("| model | verdict right | planted caught | accepted refused | not parsed | USD | s |")
    print("|---|---|---|---|---|---|---|")
    for m in models:
        mine = [r for r in rows if r["model"] == m]
        parsed = [r for r in mine if r["parsed"]]
        right = sum(r["verdict"] == all_cases[r["case"]]["expected"] for r in parsed)
        seeded = [r for r in parsed if all_cases[r["case"]]["flag"]]
        caught = sum(r.get("caught", False) for r in seeded)
        accepts = [r for r in parsed if all_cases[r["case"]]["expected"] == "accept"]
        false_rej = sum(r["verdict"] == "reject" for r in accepts)
        usd = sum(r["usd"] for r in mine) / len(mine)
        lat = sum(r["latency_s"] for r in mine) / len(mine)
        print(
            f"| {m} | {right}/{len(mine)} | {caught}/{len(seeded)} | {false_rej}/{len(accepts)} "
            f"| {len(mine) - len(parsed)} | {usd:.4f} | {lat:.0f} |"
        )


if __name__ == "__main__":
    main(Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3:])
