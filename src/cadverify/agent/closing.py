"""G8, the close: what the model announces at the end is what the harness verified.

Two checks, in order:
- deterministic: every [[name]] the close cites names something the final verification
  measured and it is green: a part, a detail or a support face of a part's spec ([[part/name]],
  or the bare name when only one part has it), the assembly ([[assembly]]), one of its support
  faces or motions, its assembly order ([[assembly_order]]), its print in place
  ([[print_in_place]]) or a gate ([[G2]]);
- the auditor, only when the rest is green: a model without tools (muse-wonder-1.0 unless the
  session names another one) reads the close against a summary of what was verified and
  the spec adjustments the harness flagged (agent/spec_history.py), and lists the claims
  presented as verified that nothing verified backs, the adjustments the close does not tell,
  and what the user's request asks for that the harness measures once declared (a stop, a
  detent's rests, a held part, a standard part) and the design did not have measured. One
  retry when its answer is not the JSON asked for; after that the close passes, marked as not
  audited.
"""

from __future__ import annotations

import json
import re
from typing import Any

from cadverify.agent.gates import DEFAULT_OUTPUT, GREEN_MEANS
from cadverify.meta_api import MODEL

REFERENCE = re.compile(r"\[\[([^\[\]\n]{1,120})\]\]")
AUDIT_EFFORT = "medium"
AUDIT_MAX_OUTPUT = 16_000
MAX_SUMMARY_CHARS = 60_000

AUDIT_INSTRUCTIONS = """You audit the close of a design session for 3D printing in OpenSCAD. \
You get the user's REQUEST. The harness verified the final version of the design and gives you, \
in JSON, what it measured (VERIFIED) and the spec adjustments it detected: changes of the spec \
towards what the mesh already measured, without the part changing (ADJUSTMENTS). Read the \
designer's CLOSE and answer only with a JSON object, with no text before or after it:
{"unsupported": [{"claim": "...", "reason": "..."}], \
"untold_adjustments": [{"adjustment": "...", "reason": "..."}], \
"unmeasured": [{"requirement": "...", "how": "..."}]}
- unsupported: every claim the close presents as verified (measured, checked, that it meets, \
that it fits, that it does not collide, that it goes in, that it prints without supports) that \
VERIFIED does not back: it is not there, it says something else or the numbers do not match. \
Leave out: what the close states as not verified, an opinion, an intention, or a description of \
the design that does not claim to have been checked.
- untold_adjustments: every part of ADJUSTMENTS whose adjustments the close does not mention \
with their reason (one mention per part saying what was adjusted and why is enough).
- unmeasured: every requirement of the REQUEST about how the product moves or what it fits \
that VERIFIED does not show measured (the close leaves it not verified, or leaves it out), when \
one of these declarations has the harness measure it; "how" names it: stops (a part that stops \
a motion at an end of its range: a drawer that does not come out, a hinge that opens to 110°, \
the way a ratchet does not turn), rests (a detent that holds a motion at given positions: a lid \
that clicks at each step), flex (a snap or a detent that bends while a part moves or as it goes \
in), held (a part that must not come off the assembled product, kept on by its shape: a lip, \
a cap, a snap), screw (a thread printed on the parts, such as a jar and its cap; not a bought \
screw or bolt), drives (gears or a rack that turn each other), print_in_place (separate parts \
printed already assembled, apart from each other), standard (the fit of one of these four \
bought parts, and no other: a Raspberry Pi 4 Model B board, a 608 bearing, an AA cell, an M3 \
nut). Leave out sizes, walls, holes and other features (the designer's own spec measures \
those), a part that must not move at all (a keyed or glued joint, a part that must not spin), \
a part kept on by friction (a set screw, a press fit), bought screws and bolts, a single part \
that bends (a living hinge), and what no declaration measures (strength, stiffness, feel, \
friction, wear, looks, the material, the printer).
Empty lists if there is nothing to object to. Be precise: quote the claim as it is written."""

AUDIT_REQUEST = """REQUEST
{request}

VERIFIED
{verified}

ADJUSTMENTS
{adjustments}

CLOSE
{close}"""


def registry(state: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    """Every name a close may cite: name -> [{"ok", "what"}] (a bare name may name several)."""
    names: dict[str, list[dict[str, Any]]] = {}

    def add(name: str, ok: bool, what: str) -> None:
        names.setdefault(name, []).append({"ok": bool(ok), "what": what})

    for gate, value in state["gates"].items():
        if gate != "G8":
            add(gate, value["ok"] is True, f"the gate {gate}")
    for part in state.get("parts") or []:
        label = part["part"] or DEFAULT_OUTPUT
        add(label, part.get("ok", False), f"the part {label}")
        check = part.get("spec_check") or {}
        for face in check.get("support_faces") or []:
            what = f"the support face {face['name']} of {label}"
            add(f"{label}/{face['name']}", face["ok"], what)
            add(face["name"], face["ok"], what)
        for detail in check.get("details") or []:
            what = f"the detail {detail['name']} ({detail['kind']}) of {label}"
            add(f"{label}/{detail['name']}", detail["ok"], what)
            add(detail["name"], detail["ok"], what)
    assembly = state.get("assembly") or {}
    if assembly.get("instances"):
        add("assembly", state["gates"].get("G3", {}).get("ok") is True, "the assembly")
        for face in (assembly.get("spec_check") or {}).get("support_faces") or []:
            what = f"the support face {face['name']} of the assembly"
            add(f"assembly/{face['name']}", face["ok"], what)
            add(face["name"], face["ok"], what)
        for motion in assembly.get("motions") or []:
            add(motion["name"], motion.get("ok", False), f"the motion {motion['name']}")
        if assembly.get("assembly_steps") is not None:
            add("assembly_order", assembly.get("assembly_order_ok", False), "the assembly order")
        if assembly.get("print_in_place"):
            add("print_in_place", state["gates"]["G5"]["ok"] is True, "the print in place")
    return names


def reference_problems(text: str, state: dict[str, Any]) -> list[str]:
    names = registry(state)
    problems = []
    for name in dict.fromkeys(m.strip() for m in REFERENCE.findall(text)):
        entries = names.get(name)
        if not entries:
            known = ", ".join(sorted(names)[:40])
            problems.append(
                f"[[{name}]] names nothing the harness verified in the final version "
                f"(the names are: {known})"
            )
        elif len({e["what"] for e in entries}) > 1:
            options = "; ".join(e["what"] for e in entries)
            problems.append(f"[[{name}]] is ambiguous ({options}): use [[part/name]]")
        elif not entries[0]["ok"]:
            problems.append(f"[[{name}]] cites {entries[0]['what']}, which is red")
    return problems


def summary(state: dict[str, Any]) -> dict[str, Any]:
    """What the final verification measured, for the auditor, with what each green gate
    verified: without it, replayed audits refused "0 bad edges" (G2) and "seen up close" (G7)."""
    parts = []
    for part in state.get("parts") or []:
        check = part.get("spec_check") or {}
        details = []
        for d in check.get("details") or []:
            details.append({k: v for k, v in d.items() if k not in ("profile", "note")})
        parts.append(
            {
                "part": part["part"],
                "ok": part.get("ok"),
                "mesh": {
                    k: (part.get("mesh") or {}).get(k)
                    for k in (
                        "watertight",
                        "bad_edges",
                        "bodies",
                        "volume_mm3",
                        "bounds",
                        "through_holes",
                    )
                },
                "spec": part.get("spec"),
                "spec_check": {k: v for k, v in check.items() if k != "details"},
                "details": details,
                "printability": part.get("printability"),
            }
        )
    gates = {g: v["ok"] for g, v in state["gates"].items() if g != "G8"}
    out: dict[str, Any] = {
        "gates": gates,
        "green_means": {g: GREEN_MEANS[g] for g, ok in gates.items() if ok is True},
        "parts": parts,
    }
    assembly = state.get("assembly") or {}
    if assembly.get("instances"):
        out["assembly"] = {
            "instances": [
                {k: i.get(k) for k in ("name", "part", "unit", "bounds", "congruent")}
                for i in assembly["instances"]
            ],
            "pairs": [
                {k: v for k, v in p.items() if k != "stl"} for p in assembly.get("pairs") or []
            ],
            "components": assembly.get("components"),
            "units": assembly.get("units"),
            "copies": assembly.get("copies"),
            "spec_check": assembly.get("spec_check"),
            "held": assembly.get("held"),
            "motions": assembly.get("motions"),
            "assembly_steps": assembly.get("assembly_steps"),
            "print_in_place": assembly.get("print_in_place"),
            "problems": assembly.get("problems"),
        }
    elif assembly:
        out["assembly"] = {k: v for k, v in assembly.items() if k != "instances"}
    return out


def parse_audit(text: str) -> dict[str, list[str]] | None:
    """The auditor's JSON, its items as one line each; None when it is not the JSON asked for."""
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        data = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    out = {}
    for key, fields in (
        ("unsupported", ("claim", "reason")),
        ("untold_adjustments", ("adjustment", "reason")),
        ("unmeasured", ("requirement", "how")),
    ):
        items = data.get(key, [])
        if not isinstance(items, list):
            return None
        lines = []
        for item in items:
            if isinstance(item, dict):
                lines.append(": ".join(str(item[f]) for f in fields if item.get(f)))
            elif isinstance(item, str) and item.strip():
                lines.append(item.strip())
            else:
                return None
        out[key] = [line for line in lines if line]
    return out


def judge(
    client,
    text: str,
    state: dict[str, Any],
    adjustments: list[dict[str, Any]],
    label: str,
    model: str = MODEL,
    request: str = "",
) -> tuple[dict[str, Any], list]:
    """G8 of a close, and the auditor's API calls (to count their cost); `model` audits, and
    reads the close against the user's `request` too."""
    problems = reference_problems(text, state)
    if problems:
        return {"ok": False, "detail": problems}, []
    verified = json.dumps(summary(state), ensure_ascii=False)
    if len(verified) > MAX_SUMMARY_CHARS:
        verified = verified[:MAX_SUMMARY_CHARS] + " ... (cut)"
    flagged = [
        f"{part}: " + "; ".join(a["text"] for a in adjustments if a["part"] == part)
        for part in dict.fromkeys(a["part"] for a in adjustments)
    ] or ["(none)"]
    request = dict(
        model=model,
        instructions=AUDIT_INSTRUCTIONS,
        input=AUDIT_REQUEST.format(
            request=request.strip() or "(none)",
            verified=verified,
            adjustments="\n".join(f"- {a}" for a in flagged),
            close=text,
        ),
        reasoning={"effort": AUDIT_EFFORT},
        max_output_tokens=AUDIT_MAX_OUTPUT,
    )
    calls = []
    for attempt in (1, 2):
        call = client.responses(label=f"{label}-audit{attempt}", **request)
        calls.append(call)
        audit = parse_audit(call.output_text) if call.ok else None
        if audit is None:
            continue
        detail = [f"unsupported claim: {a}" for a in audit["unsupported"]]
        detail += [f"spec adjustment not told: {a}" for a in audit["untold_adjustments"]]
        detail += [f"requirement not measured: {a}" for a in audit["unmeasured"]]
        return {"ok": not detail, "detail": detail, "audit": audit}, calls
    return {
        "ok": True,
        "detail": [],
        "not_audited": "the auditor did not return the JSON asked for in two attempts",
    }, calls
