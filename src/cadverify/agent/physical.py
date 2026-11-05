"""The loop with the real world: what comes back from a print goes into the next version.

- `iterate_task`: a new session from a recorded version, with its request, its brief, its close and
  what the user saw. The brief starts empty again: what the user reports changes what it assumed.
- `baseline`: "this version worked". G6's absolute numbers rest on datasheets and an elastic model,
  and nobody should believe them to the newton; how a new force compares with one that felt right
  does not depend on either. `relative` adds that comparison to a behaviour report.
- `regression`: what changed from the parent version, part by part, and what is gone that a
  session could have dropped without anybody asking.
- `probes` and `tune`: small test prints, and which parameter fixes which failure. Both are in the
  spec and are checked by the harness (cadcheck.verify); here they are read for G8 and the close.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from cadverify.agent.brief import short

BASELINE_FILE = "baseline.json"
BASELINE_TIMEOUT_S = 960
VOLUME_REL = 0.01  # a part that changed by less than this has not changed
BOUNDS_MM = 0.05


ITERATE_START = "This is a new version of a design you already closed."
ITERATE_NOW = "WHAT THE USER SAYS NOW, AFTER USING IT"
ITERATE_RULE = "What the user reports is a fact about the real part"

ITERATE = """{request}

This is a new version of a design you already closed. model.scad is that version.

WHAT YOU SAID THEN
{close}

YOUR BRIEF THEN
{brief}

WHAT THE USER SAYS NOW, AFTER USING IT
{feedback}

What the user reports is a fact about the real part, and it outranks every number that said \
otherwise: find which assumption it breaks, write the brief again with that (design_brief), and \
change what it asks for. A number from G6 that said this could not happen says the model was \
wrong. {baseline}"""
WITH_BASELINE = """The version the user called good is a baseline: behaviour_check gives each \
force relative to that version. Trust those ratios more than the absolute newtons."""


def iterate_task(session: dict[str, Any], feedback: str, baseline: dict[str, Any] | None) -> str:
    """The first message of a session that continues `session`."""
    closes = [it["text"] for it in session.get("iterations") or [] if it.get("close") == "accepted"]
    return ITERATE.format(
        request=session.get("request", "").strip(),
        close=(closes[-1] if closes else "(the session did not close)").strip(),
        brief=json.dumps(short((session.get("final") or {}).get("brief")), ensure_ascii=False),
        feedback=feedback.strip(),
        baseline=WITH_BASELINE if baseline else "",
    )


def load_baseline(run: Path) -> dict[str, Any] | None:
    """The baseline a session stands on: in its folder, or in that of the session it came from."""
    seen = set()
    while run and run not in seen:
        seen.add(run)
        file = run / BASELINE_FILE
        if file.exists():
            return json.loads(file.read_text(encoding="utf-8"))
        parent = run / "session.json"
        if not parent.exists():
            return None
        link = json.loads(parent.read_text(encoding="utf-8")).get("parent") or {}
        run = Path(link["run"]) if link.get("run") else None
    return None


def baseline_numbers(behaviour: dict[str, Any], run: str) -> dict[str, Any]:
    """What a baseline keeps: each force and each peak."""
    return {
        "run": run,
        "flex": {
            f"{f['a']}/{f['b']}": {
                "force_n": f.get("force_n"),
                "strain_pct": {p["instance"]: p.get("strain_pct") for p in f.get("parts") or []},
            }
            for f in behaviour.get("flex") or []
        },
        "loads": {
            load["name"]: {
                "largest_mm": load.get("largest_mm"),
                "strain_pct": load.get("strain_pct"),
            }
            for load in behaviour.get("loads") or []
        },
    }


def relative(behaviour: dict[str, Any], base: dict[str, Any] | None) -> None:
    """Each force and peak as a ratio to the version that worked, in place. A flex or a load with
    nothing to compare with says so: a new one has no baseline."""
    if not base:
        return
    behaviour["baseline_of"] = base.get("run")
    for flex in behaviour.get("flex") or []:
        known = (base.get("flex") or {}).get(f"{flex['a']}/{flex['b']}")
        if known is None or not known.get("force_n") or flex.get("force_n") is None:
            flex["vs_baseline"] = None
            continue
        flex["vs_baseline"] = {
            "force": round(flex["force_n"] / known["force_n"], 2),
            "force_then_n": known["force_n"],
            "strain": {
                p["instance"]: round(p["strain_pct"] / known["strain_pct"][p["instance"]], 2)
                for p in flex.get("parts") or []
                if (known.get("strain_pct") or {}).get(p["instance"]) and p.get("strain_pct")
            },
        }
    for load in behaviour.get("loads") or []:
        known = (base.get("loads") or {}).get(load["name"])
        if known is None or not known.get("largest_mm") or load.get("largest_mm") is None:
            load["vs_baseline"] = None
            continue
        load["vs_baseline"] = {"deflection": round(load["largest_mm"] / known["largest_mm"], 2)}


def _part_box(part: dict[str, Any]) -> dict[str, Any]:
    mesh = part.get("mesh") or {}
    return {k: mesh.get(k) for k in ("volume_mm3", "bounds", "bodies")}


def _declared_names(state: dict[str, Any]) -> dict[str, set[str]]:
    assembly = state.get("assembly") or {}
    behaviour = state.get("behaviour") or {}
    details, supports = set(), set()
    for part in state.get("parts") or []:
        check = part.get("spec_check") or {}
        label = part["part"]
        details |= {f"{label}/{d['name']}" for d in check.get("details") or []}
        supports |= {f"{label}/{f['name']}" for f in check.get("support_faces") or []}
    return {
        "part": {p["part"] or "default" for p in state.get("parts") or []},
        "motion": {m["name"] for m in assembly.get("motions") or []},
        "detail": details,
        "support face": supports,
        "flex": {f"{f['a']}/{f['b']}" for f in behaviour.get("flex") or []},
        "load": {load["name"] for load in behaviour.get("loads") or []},
        "stability": {s["name"] for s in behaviour.get("stability") or []},
    }


def regression(parent: dict[str, Any] | None, state: dict[str, Any]) -> dict[str, Any] | None:
    """What changed from the parent version: each part's volume, box and bodies, and what is gone.
    `gone` is for the auditor: a close has to say it was asked for, or why."""
    if not parent:
        return None
    before = {p["part"] or "default": _part_box(p) for p in parent.get("parts") or []}
    changed = []
    for part in state.get("parts") or []:
        name = part["part"] or "default"
        old, new = before.get(name), _part_box(part)
        if old is None:
            changed.append({"part": name, "new": True, **new})
            continue
        row: dict[str, Any] = {"part": name}
        if old["volume_mm3"] and new["volume_mm3"]:
            change = new["volume_mm3"] / old["volume_mm3"] - 1
            if abs(change) > VOLUME_REL:
                row["volume_change"] = round(change, 3)
        if old["bodies"] != new["bodies"]:
            row["bodies"] = [old["bodies"], new["bodies"]]
        if old["bounds"] and new["bounds"]:
            moved = max(
                abs(a - b)
                for corner_a, corner_b in zip(old["bounds"], new["bounds"], strict=True)
                for a, b in zip(corner_a, corner_b, strict=True)
            )
            if moved > BOUNDS_MM:
                row["bounds"] = [old["bounds"], new["bounds"]]
        if len(row) > 1:
            changed.append(row)
    was, now = _declared_names(parent), _declared_names(state)
    gone = [f"{kind} {name}" for kind in was for name in sorted(was[kind] - now[kind])]
    return {"changed": changed, "gone": gone}


def tune_problems(state: dict[str, Any]) -> list[str]:
    """G8: each flex and load has what to tune when the print disagrees, and each parameter named
    exists and moves what it says it moves."""
    report = state.get("tune")
    behaviour = state.get("behaviour") or {}
    named = {
        *(f"flex {f['a']}/{f['b']}" for f in behaviour.get("flex") or []),
        *(f"load {load['name']}" for load in behaviour.get("loads") or []),
    }
    if not named:
        return []
    out = []
    rows = (report or {}).get("rows") or []
    covered = {row["measure"] for row in rows}
    for name in sorted(named - covered):
        out.append(
            f"nothing says which parameter to touch when {name} is wrong on the real print: "
            'declare it in the spec, ["tune", [["what goes wrong", "parameter", value to try, '
            f'"{name}"]]]'
        )
    if (report or {}).get("skipped"):
        return out
    for row in rows:
        if not row.get("ok"):
            out.append(
                f"the parameter {row['param']} does not fix {row['failure']!r}: {row.get('why')}"
            )
    return out
