"""The reviewer: before a close is judged, someone who is going to use the product looks at it.

On runs kept out of this repo, the model that closed green with a known defect 2 times of 3 found it
every time when asked to review the finished part, and a rule in the prompt changed nothing. So it
is a separate role with a separate context. It never sees the designer's reasoning or source: it
gets the request, the brief, the harness's own drawings and cuts of the final version, and the
numbers of G6, and it answers as a user would: where it breaks, what blocks what, what is left
hanging, what happens when a hand goes in.

Those reviews also raised one false positive in each control, with a fix that brought the defect
back. So a finding is never a verdict: it is a hypothesis with the measurement that would confirm
it. The designer runs a measurement and answers each with answer_finding: fixed, on a new version,
or refuted, with the numbers. G8 stays red while one is open; the review itself blocks nothing.
"""

from __future__ import annotations

import json
import re
from typing import Any

from cadverify.agent.brief import short
from cadverify.agent.closing import _short_behaviour
from cadverify.meta_api import MODEL

REVIEW_EFFORT = "medium"
REVIEW_MAX_OUTPUT = 8_000
MAX_FINDINGS = 5
MAX_REVIEWS = 2  # per session: the first close, and the version that answers it
FENCE = re.compile(r"```(?:json)?\s*(\{.*\})\s*```", re.S)

REVIEW_INSTRUCTIONS = f"""You are about to use a product someone else designed for FDM printing. \
You did not design it, and you do not know how they reasoned. You get what was asked for, the \
designer's brief, drawings and cuts of the final version, and the numbers a harness measured.

Every number the harness reports is right, and so is what it verifies: closed meshes, parts that \
do not collide, a print without supports, a spec held. Do not check those again. Look for what \
measuring the declared things does not catch. Answer as the person who will print it, put it \
together and use it: where does it break, what blocks what, what part is left hanging or joined \
by almost nothing, what happens when a hand or the object goes in, what bends that cannot bend, \
what it does not serve from the range it promises.

Each finding is a hypothesis, and has to name the measurement that would confirm it: where to cut, \
what to measure and what number would mean it is real. It says what would go wrong in use, not how \
to fix it. Not findings: looks, preferences, what could be nicer, tolerances that may or may not \
work out, what you cannot see because no drawing shows it. A product that works as drawn has no \
findings, and most have none or one: an empty list is a good answer. At most {MAX_FINDINGS}, the \
worst first.

Answer only with this JSON:
{{"findings": [{{"where": "the part and the place, with coordinates if you can read them", \
"what": "what goes wrong in use", "confirm_by": "the cut or measurement, and the number that \
confirms it"}}]}}"""

REVIEW_REQUEST = """REQUEST
{request}

BRIEF
{brief}

NUMBERS (what the harness computed of how it behaves)
{numbers}

The images follow: {captions}."""

REVIEW_FINDINGS = """A reviewer who did not see your reasoning looked at the final version as \
someone who will use it. Each finding is a hypothesis: nobody measured it, and reviewers are wrong \
often. For each one, measure what it names (a cut, a calculation, behaviour_check) and answer with \
answer_finding: "fixed" on a new version, with the number that changed, or "refuted", with the \
number that says the product is right. Do not change a part only because a finding says so: if the \
measurement refutes it, say so. G8 stays red while one is open.

{findings}"""


def due(session: dict[str, Any], state: dict[str, Any]) -> bool:
    """A review of this version: not yet done on it, within the session's reviews."""
    reviews = session.get("reviews") or []
    if len(reviews) >= MAX_REVIEWS:
        return False
    if any(r["source"] == state["source"] for r in reviews):
        return False
    return not any(f["status"] == "open" for f in state.get("findings") or [])


def parse(text: str) -> list[dict[str, str]] | None:
    """The findings of a review, or None when it is not the JSON asked for."""
    fenced = FENCE.search(text or "")
    raw = fenced.group(1) if fenced else (text or "")
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end < 0:
        return None
    try:
        found = json.loads(raw[start : end + 1])["findings"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return None
    if not isinstance(found, list):
        return None
    out = []
    for item in found[:MAX_FINDINGS]:
        if not (isinstance(item, dict) and all(item.get(k) for k in ("where", "what"))):
            return None
        if not item.get("confirm_by"):  # a finding nobody could measure is not a hypothesis
            continue
        out.append({k: str(item[k]) for k in ("where", "what", "confirm_by")})
    return out


def input_for(
    request: str, state: dict[str, Any], images: list[tuple[str, str]]
) -> list[dict[str, Any]]:
    """The message of a review: only what the role may see."""
    numbers = _short_behaviour(state["behaviour"]) if state.get("behaviour") else {}
    captions = "; ".join(caption for caption, _ in images) or "none"
    text = REVIEW_REQUEST.format(
        request=request.strip() or "(none)",
        brief=json.dumps(short(state.get("brief")), ensure_ascii=False),
        numbers=json.dumps(numbers, ensure_ascii=False),
        captions=captions,
    )
    content: list[dict[str, Any]] = [{"type": "input_text", "text": text}]
    for caption, url in images:
        content.append({"type": "input_text", "text": caption})
        content.append({"type": "input_image", "image_url": url})
    return [{"role": "user", "content": content}]


def run(
    client,
    request: str,
    state: dict[str, Any],
    images: list[tuple[str, str]],
    label: str,
    model: str = MODEL,
) -> tuple[list[dict[str, str]] | None, list]:
    """One review: its findings (None: it did not answer in two attempts), and the API calls."""
    payload = {
        "model": model,
        "instructions": REVIEW_INSTRUCTIONS,
        "input": input_for(request, state, images),
        "reasoning": {"effort": REVIEW_EFFORT},
        "max_output_tokens": REVIEW_MAX_OUTPUT,
    }
    calls = []
    for attempt in (1, 2):
        call = client.responses(label=f"{label}-review{attempt}", **payload)
        calls.append(call)
        found = parse(call.output_text) if call.ok else None
        if found is not None:
            return found, calls
    return None, calls


def message(findings: list[dict[str, Any]]) -> str:
    listed = "\n".join(
        f"- {f['id']}: {f['where']}: {f['what']} Confirmed by: {f['confirm_by']}" for f in findings
    )
    return REVIEW_FINDINGS.format(findings=listed)
