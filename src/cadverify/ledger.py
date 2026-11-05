"""Run directories and the spending ledger: what the requests recorded under a results directory
cost, checked against its budget before a session starts."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

from cadverify.meta_api import cost_usd, search_fee_usd


def new_run_dir(root: Path, kind: str) -> Path:
    path = root / kind / datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    path.mkdir(parents=True, exist_ok=False)
    return path


def spent_usd(root: Path) -> float:
    """Cost of every request recorded under `root` (the raw/ records of meta_api)."""
    total = 0.0
    for raw in root.glob("**/raw/*.json"):
        record = json.loads(raw.read_text(encoding="utf-8"))
        usage = (record.get("response") or {}).get("usage") or {}
        total += cost_usd(
            {
                "input_tokens": usage.get("input_tokens", 0),
                "cached_tokens": (usage.get("input_tokens_details") or {}).get("cached_tokens", 0),
                "output_tokens": usage.get("output_tokens", 0),
            },
            (record.get("request") or {}).get("model"),
        ) + search_fee_usd((record.get("response") or {}).get("output"))
    return total


def check_budget(planned_usd: float, root: Path, budget_usd: float) -> None:
    spent = spent_usd(root)
    if spent + planned_usd > budget_usd:
        raise SystemExit(
            f"Budget: USD {spent:.2f} spent + USD {planned_usd:.2f} planned is more than "
            f"USD {budget_usd:.2f}."
        )
