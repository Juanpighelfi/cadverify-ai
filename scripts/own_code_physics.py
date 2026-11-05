"""How much of the model's own code computes anything physical, over the public recorded
sessions: the number behind G6. Costs no model; prints each hit, to read it, since a word is not a
calculation.

    uv run python scripts/own_code_physics.py
"""

from __future__ import annotations

import json
import re

from public_sessions import public_sessions

from cadverify.config import PROJECT_ROOT

HARNESS_ASKED = {"behaviour"}  # sessions that ran with the brief: not what the models do unasked
PHYSICAL = re.compile(
    r"\b(force|newton|deflect\w*|strain|stress|young|modulus|cantilever|moment of inertia|torque|"
    r"mpa)\b",
    re.I,
)


def main() -> int:
    results = PROJECT_ROOT / "results"
    sessions = calls = 0
    hits = []
    for path in public_sessions(results):
        if path.relative_to(results).parts[0] in HARNESS_ASKED:
            continue
        sessions += 1
        for tool in ("run_python", "run_shell"):
            for log in sorted((path.parent / "tools").glob(f"*-{tool}.json")):
                calls += 1
                arguments = json.loads(log.read_text(encoding="utf-8")).get("arguments")
                text = " ".join(map(str, arguments.values())) if arguments else ""
                if found := PHYSICAL.search(text):
                    around = text[max(0, found.start() - 50) : found.end() + 30]
                    hits.append(f"{log.relative_to(results)}: {around!r}")
    print(f"{sessions} sessions, {calls} calls of the model's own code, {len(hits)} name a force")
    print("\n".join(hits))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
