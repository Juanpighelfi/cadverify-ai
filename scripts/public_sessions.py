"""The recorded sessions that are public: what git does not ignore, so a run that stays local never
gets counted, in a table or anywhere else, and the scripts need not know its name."""

from __future__ import annotations

import subprocess
from pathlib import Path


def public_sessions(results: Path) -> list[Path]:
    """Each public session.json under `results`, in order."""
    found = sorted(results.glob("**/session.json"))
    ignored = subprocess.run(
        ["git", "check-ignore", "--stdin"],
        input="\n".join(str(p) for p in found),
        capture_output=True,
        text=True,
        cwd=results,
        check=False,
    ).stdout.splitlines()
    return [p for p in found if str(p) not in set(ignored)]
