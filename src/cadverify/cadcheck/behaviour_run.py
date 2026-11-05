"""G6 in a process of its own: `python -m cadverify.cadcheck.behaviour_run <arguments.json>`.

A new interpreter, not a fork. By the time G6 runs, this process has an OpenGL context, from the
sheets of the parts, and a forked child that draws through it waits forever in glReadPixels, with
no CPU: on 16 of 23 recorded sessions (stack in moderngl's read, under fea.draw_strain). That hang
is what cadcheck.verify.behaviour_of holds from outside, whatever else causes one.
"""

from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path


def main(path: str) -> int:
    args = json.loads(Path(path).read_text(encoding="utf-8"))
    module, _, name = args.pop("compute").partition(":")
    compute = getattr(importlib.import_module(module), name)
    saved = Path(args["save"])
    from cadverify.cadcheck.verify import _red_report

    try:
        compute(
            args["assembly"],
            args["parts"],
            args["out_dir"],
            args["default_material"],
            time_budget_s=args["time_budget_s"],
            embed=args["embed"],
            save=saved,
        )
    except Exception as exc:  # a crash of the solver is a red gate, not a verification lost
        _red_report(saved, f"the behaviour could not be computed: {type(exc).__name__}: {exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
