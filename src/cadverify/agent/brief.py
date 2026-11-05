"""The design brief: what the designer writes before any CAD, and G8's reading of it.

Asked for in a prompt, analysis before CAD did not happen: in 79 recorded sessions, 0 of 443 calls
of the model's own code computed a force or a deformation. So it is a tool, and scad_write and
scad_patch are refused until it has run (agent/tools.py). The harness checks the form of a brief,
not its reasoning: what fails and how, whom and what it serves, the loads, and at least two
candidates with numbers. What it can hold the designer to is the end of the session: each load
has to name what measures it (a `loads` or `stability` entry of the spec, or a flex), and G8 is
red until that exists and is green. The auditor reads the rest against the request and the close.
"""

from __future__ import annotations

from typing import Any

MIN_CANDIDATES = 2
SCHEMA = {
    "failure_modes": {
        "type": "array",
        "description": "How this product fails in use, in print or in assembly, each with the "
        "number or check that tells: [{mode, check}].",
        "items": {
            "type": "object",
            "properties": {"mode": {"type": "string"}, "check": {"type": "string"}},
            "required": ["mode", "check"],
        },
    },
    "serves": {
        "type": "object",
        "description": "Whom and what it has to serve: the people (hands, reach) and the range of "
        "the things it meets (sizes, weights), with numbers, and where they come from.",
        "properties": {"who": {"type": "string"}, "range": {"type": "string"}},
        "required": ["who", "range"],
    },
    "loads": {
        "type": "array",
        "description": "The forces and weights it sees, each with its assumption and "
        "measured_as: the name of the `loads` or `stability` entry of the spec that will measure "
        "it, or 'flex a/b' for a flex. Empty if none, and then no_loads says why.",
        "items": {
            "type": "object",
            "properties": {
                "what": {"type": "string"},
                "value": {"type": "string", "description": "With its unit"},
                "assumption": {"type": "string"},
                "measured_as": {"type": "string"},
            },
            "required": ["what", "value", "assumption", "measured_as"],
        },
    },
    "no_loads": {"type": "string"},
    "candidates": {
        "type": "array",
        "description": f"At least {MIN_CANDIDATES} ways to build it, compared by numbers you "
        "computed (a force, a strain, a mass, an hour of print), each with its assumptions.",
        "items": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "numbers": {
                    "type": "object",
                    "description": 'Quantity with its unit -> number: {"arm strain (%)": 1.1}',
                    "additionalProperties": {"type": "number"},
                },
                "assumptions": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["name", "numbers", "assumptions"],
        },
    },
    "chosen": {"type": "string", "description": "The name of the candidate you build."},
    "why": {"type": "string"},
}
REQUIRED = ["failure_modes", "serves", "loads", "candidates", "chosen", "why"]


def problems(brief: dict[str, Any]) -> list[str]:
    """What a brief lacks to count as one."""
    out = []
    modes = brief.get("failure_modes") or []
    if not modes or not all(_filled(m, "mode", "check") for m in modes):
        out.append("failure_modes: at least one, each with its mode and the check that tells")
    if not _filled(brief.get("serves") or {}, "who", "range"):
        out.append("serves: who and range, with numbers")
    loads = brief.get("loads") or []
    if not loads and not (brief.get("no_loads") or "").strip():
        out.append("loads: the forces it sees, or no_loads with why there are none")
    if not all(_filled(item, "what", "value", "assumption", "measured_as") for item in loads):
        out.append("loads: each with what, value, assumption and measured_as")
    candidates = brief.get("candidates") or []
    if len(candidates) < MIN_CANDIDATES:
        out.append(f"candidates: at least {MIN_CANDIDATES}, compared by numbers")
    for candidate in candidates:
        numbers = candidate.get("numbers")
        if not _filled(candidate, "name") or not numbers or not _all_numbers(numbers):
            out.append(f"candidates: {candidate.get('name')!r} needs a name and numbers")
        if not candidate.get("assumptions"):
            out.append(f"candidates: {candidate.get('name')!r} needs its assumptions")
    names = [c.get("name") for c in candidates]
    if brief.get("chosen") not in names:
        out.append(f"chosen: one of the candidates {names}; got {brief.get('chosen')!r}")
    if not (brief.get("why") or "").strip():
        out.append("why: why this candidate, from its numbers")
    return out


def _filled(item: dict[str, Any], *keys: str) -> bool:
    return isinstance(item, dict) and all(str(item.get(k) or "").strip() for k in keys)


def _all_numbers(numbers: Any) -> bool:
    return isinstance(numbers, dict) and all(
        isinstance(v, int | float) and not isinstance(v, bool) for v in numbers.values()
    )


def closing_problems(state: dict[str, Any], registered: dict[str, list[dict]]) -> list[str]:
    """G8: the loads of the brief, each measured and green in the final version."""
    if "brief" not in state:  # a toolbox that does not ask for one
        return []
    brief = state["brief"]
    if not brief:
        return ["there is no design brief: call design_brief"]
    out = []
    for load in brief.get("loads") or []:
        name = load["measured_as"].strip()
        entries = registered.get(name)
        if not entries:
            out.append(
                f"the brief says {load['what']} ({load['value']}) is measured as {name!r}, and "
                "nothing with that name was measured: declare it in the spec (a `loads` or "
                "`stability` entry, or a flex as 'flex a/b'), or correct the brief"
            )
        elif not all(e["ok"] for e in entries):
            out.append(f"the brief's {load['what']} is measured as {name!r}, which is red")
    return out


def short(brief: dict[str, Any] | None) -> dict[str, Any] | None:
    """A brief as the reader of the close and the reviewer get it: what they compare."""
    return None if not brief else {k: brief.get(k) for k in (*REQUIRED, "no_loads") if k in brief}
