"""The agent loop: the model proposes, the harness verifies.

Each iteration is one model request: the orchestrator runs the requested tools in the sandbox,
returns their JSON (and the sheet image), then verifies the gates on the current source. The
model closes by answering without tool calls; the orchestrator accepts only with every gate
green, and otherwise sends the red gates back. Limits: requests, cost and wall time.

With someone to answer (`asker`), a session can ask before it edits: a reply without tool calls
while the sources are still the ones the session started with is a question, not a close. A
question goes to the user only after the model looked at what it got (ToolBox.look_missing);
before that, the model is told what to look at first. The asker returns the user's answer, which
goes back as the next message; the time spent waiting does not count against the wall time
limit.

A response cut short (status "incomplete", usually at max_output_tokens) runs nothing: a tool
call in it may be half written. The conversation goes on from the request before, with a note
asking for smaller steps, for that once: one session cut at 32k right after the user's
answers then made 65 of its next 76 requests with one tool call, mostly a scad_patch, until the
request limit.

With `wrap_up_requests`, a session is told when it has about that many requests left
(the request limit, or the cost and the time left at the session's average per request), with
what a close needs; the last one asks for the close. One session without it spent its last
request rewriting model.scad, and ended with two parts broken and unseen. The last one is sent
once: a close is quicker than the average request, so the estimate often finds one left again
after it, and six sessions were told to close now without tools again and again (up to 14 times),
one closing red four times in a row while G7 asked for a view. After it, the note is the first.

Every request is streamed (cadverify.meta_api): without streaming the server answers 504 after
about 600 s, and a response of 64k tokens takes longer.

The conversation is chained with previous_response_id, and also kept here: in the first
acceptance run the server lost a stored response (404 on GET /v1/responses/<id> 40 minutes
later), and the only way on is to resend the whole history without it.

G8 is judged at the close, when every other gate is green (agent/closing.py: the close's
references and the auditor, whose requests count against the session's cost). The auditor is
muse-wonder-1.0 whatever the designer: replaying the recorded audits, plus copies of them with
a claim planted, it was the one that caught the subtle unsupported claims, and it was as strict
with its own closes as with any.

With `max_live_images`, old images leave the context: when more than that many are live, the
  history is resent without the previous response, keeping the last `keep_images` images and
  the last one of each part and of the assembly; every other image is replaced by a line with
  what it showed and the call that shows it again.
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from cadverify.agent import closing, review
from cadverify.agent.gates import all_green, green_but
from cadverify.agent.prompts import (
    CLOSE_REJECTED,
    LOOK_FIRST,
    OUTPUT_CUT,
    SPEC_NOTES,
    WRAP_UP,
    WRAP_UP_LAST,
    gate_report,
    instructions,
)
from cadverify.agent.tools import ToolBox
from cadverify.meta_api import MAX_ATTEMPTS, MODEL

PROMPT_CACHE_KEY = "cadverify-agent"


@dataclass(frozen=True)
class Limits:
    """Per session of one simple part: in the first acceptance runs the green sessions took 5
    to 14 requests, USD 0.30 to 0.85 and 2.6 to 7.7 minutes."""

    max_requests: int = 25
    max_cost_usd: float = 2.0
    max_wall_s: float = 1200.0
    effort: str = "high"
    max_output_tokens: int = 32_000
    max_live_images: int = 0  # 0: every image stays in the context
    keep_images: int = 10  # the most recent ones kept when old images leave
    wrap_up_requests: int = 0  # told when about this many requests are left; 0: never


def run_session(
    client,
    toolbox: ToolBox,
    task: str,
    limits: Limits,
    out: Path,
    asker: Callable[[str, int], str] | None = None,
    model: str = MODEL,
    auditor: str = MODEL,
    reviewer: str | None = None,
    first_images: list[str] | None = None,
    parent: dict[str, Any] | None = None,
) -> dict:
    """Run one session of `model` and write `session.json` in `out` after every iteration.
    `asker(questions, iteration)` answers the model's questions and returns the user's answer;
    `auditor` is the model that audits the close (G8); `reviewer` looks at the product before it
    (agent/review.py); `first_images` go with the first message, `parent` is the session this one
    continues (agent/physical.py)."""
    started = time.perf_counter()
    system = instructions(
        questions=asker is not None,
        requirements=toolbox.requirements,
        lookup=toolbox.searcher is not None,
    )
    initial_source = toolbox.source_hash()
    session: dict[str, Any] = {
        "model": model,
        "auditor": auditor,
        "limits": asdict(limits),
        "request": task,
        "parent": parent,
        "requirements": toolbox.requirements,
        "instructions": system,
        "tools": [s["name"] for s in toolbox.schemas],
        "reviews": [],
        "iterations": [],
        "status": "running",
        "user_wait_s": 0.0,
        "audits": [],
        "compactions": [],
    }

    def working_s() -> float:
        return time.perf_counter() - started - session["user_wait_s"]

    first: Any = task
    if first_images:
        first = [{"type": "input_text", "text": task}]
        first += [{"type": "input_image", "image_url": url} for url in first_images]
    payload: dict[str, Any] = {
        "input": [{"role": "user", "content": first}] if first_images else task
    }
    history: list[dict[str, Any]] = [{"role": "user", "content": first}]
    live: list[dict[str, int]] = []  # the images in the context: tool call seq, history index
    spent = 0.0
    told_last = False  # WRAP_UP_LAST was sent
    for i in range(1, limits.max_requests + 1):
        elapsed = working_s()
        if spent >= limits.max_cost_usd:
            session["status"] = "session budget spent"
            break
        if elapsed > limits.max_wall_s:
            session["status"] = "time limit reached"
            break
        compacted = None
        if limits.max_live_images and len(live) > limits.max_live_images:
            compacted = compact(history, live, toolbox, limits.keep_images)
            session["compactions"].append(
                {"iteration": i, "removed": compacted, "kept": [e["seq"] for e in live]}
            )
            payload = {"input": list(history)}  # stateless: the stored context had them
        request = dict(
            model=model,
            instructions=system,  # not carried over by previous_response_id
            tools=toolbox.schemas,
            reasoning={"effort": limits.effort},
            max_output_tokens=limits.max_output_tokens,
            # Streamed: a long response passes the server's limit for one without streaming.
            stream=True,
            # The session that reached G7 paid USD 7.48 of its 12.49 in requests that missed the
            # cache (dev.meta.ai/docs/prompt-caching: one stable key per application routes
            # requests to the backend that holds the prefix; "24h" outlasts a user's answer).
            prompt_cache_key=f"{PROMPT_CACHE_KEY}-{model}",
            prompt_cache_retention="24h",
        )
        call = client.responses(label=f"it{i:02d}", **request, **payload)
        lost = None
        if _lost_previous(call, payload):
            lost = call.metrics()
            call = client.responses(label=f"it{i:02d}-replay", **request, input=list(history))
        spent += call.cost_usd
        iteration: dict[str, Any] = {
            "iteration": i,
            "request": call.metrics(),
            "text": call.output_text,
            "tool_calls": [],
            "images": [],
        }
        if lost:
            iteration["lost_previous_response"] = lost
        if compacted:
            iteration["images_removed"] = compacted
        session["iterations"].append(iteration)
        if not call.ok:
            session["status"] = "API error"
            break
        if call.response_status == "incomplete":
            details = (call.body or {}).get("incomplete_details") or {}
            iteration["incomplete"] = details
            note = OUTPUT_CUT.format(
                reason=details.get("reason", "no reason"), tokens=limits.max_output_tokens
            )
            payload = {**payload, "input": _as_items(payload["input"]) + [_user(note)]}
            history.append(_user(note))
            _write(out, session, spent, started, toolbox)
            continue
        history += _replayable(call.output)
        outputs = []
        for fc in call.function_calls:
            result, image = toolbox.call(fc.get("name", ""), fc.get("arguments", ""), i)
            iteration["tool_calls"].append(
                {"seq": toolbox.seq, "name": fc.get("name"), "summary": summarize(fc, result)}
            )
            spent += sum(c.cost_usd for c in toolbox.take_api_calls())
            text = json.dumps(result, ensure_ascii=False)
            output: Any = text
            if image:
                iteration["images"].append({"seq": toolbox.seq, "tool": fc.get("name")})
                live.append({"seq": toolbox.seq, "index": len(history) + len(outputs)})
                output = [
                    {"type": "input_text", "text": text},
                    {"type": "input_image", "image_url": image},
                ]
            outputs.append(
                {"type": "function_call_output", "call_id": fc.get("call_id"), "output": output}
            )
        iteration["source"] = toolbox.source_hash()
        state = toolbox.gates()
        iteration["gates"] = {name: gate["ok"] for name, gate in state["gates"].items()}
        elapsed = working_s()
        notice = wrap_up_notice(limits, i, spent, elapsed, last=not told_last)
        told_last = told_last or bool(notice) and requests_left(limits, i, spent, elapsed) == 1
        if notice:
            iteration["wrap_up_notice"] = notice
        if outputs:
            outputs += [_user(notice)] if notice else []
            payload = {"previous_response_id": call.response_id, "input": outputs}
            history += outputs
        elif (
            asker
            and call.output_text.strip()
            and toolbox.source_hash() == initial_source
            and (missing := toolbox.look_missing())
        ):
            iteration["close"] = "questions before looking"
            message = LOOK_FIRST.format(missing="\n".join(f"- {m}" for m in missing))
            payload = {"previous_response_id": call.response_id, "input": message}
            history.append(_user(message))
        elif asker and call.output_text.strip() and toolbox.source_hash() == initial_source:
            iteration["close"] = "questions"
            _write(out, session, spent, started, toolbox)
            waiting = time.perf_counter()
            answer = asker(call.output_text, i)
            session["user_wait_s"] += time.perf_counter() - waiting
            iteration["answer"] = answer
            payload = {"previous_response_id": call.response_id, "input": answer}
            history.append(_user(answer))
        else:
            current = state["gates"]
            if reviewer and green_but(current, "G8") and review.due(session, state):
                images = toolbox.review_images(state)
                found, calls = review.run(client, task, state, images, f"it{i:02d}", model=reviewer)
                spent += sum(c.cost_usd for c in calls)
                new = toolbox.add_findings(found or [])
                session["reviews"].append(
                    {
                        "iteration": i,
                        "source": state["source"],
                        "model": reviewer,
                        "images": [caption for caption, _ in images],
                        "findings": new,
                        **({"not_reviewed": True} if found is None else {}),
                        "requests": [c.metrics() for c in calls],
                    }
                )
                if new:
                    iteration["close"] = "reviewed"
                    iteration["findings"] = new
                    message = review.message(new)
                    if notice:
                        message += "\n\n" + notice
                    payload = {"previous_response_id": call.response_id, "input": message}
                    history.append(_user(message))
                    _write(out, session, spent, started, toolbox)
                    continue
                state["findings"] = [dict(f) for f in toolbox.findings]
            if green_but(current, "G8"):
                g8, calls = closing.judge(
                    client,
                    call.output_text,
                    state,
                    toolbox.history.adjustments,
                    f"it{i:02d}",
                    model=auditor,
                    request=task,
                )
                spent += sum(c.cost_usd for c in calls)
                session["audits"].append(
                    {
                        "iteration": i,
                        "source": state["source"],
                        "g8": g8,
                        "requests": [c.metrics() for c in calls],
                    }
                )
                current["G8"] = g8
                iteration["gates"]["G8"] = g8["ok"]
            if all_green(current):
                iteration["close"] = "accepted"
                session["status"] = "green"
            else:
                iteration["close"] = "rejected"
                iteration["gate_detail"] = current
                message = CLOSE_REJECTED.format(report=gate_report(current))
                if notes := toolbox.take_notes():
                    message += SPEC_NOTES.format(notes="\n".join(f"- {n}" for n in notes))
                if notice:
                    message += "\n\n" + notice
                payload = {"previous_response_id": call.response_id, "input": message}
                history.append(_user(message))
        _write(out, session, spent, started, toolbox)
        if session["status"] == "green":
            break
    else:
        session["status"] = "request limit reached"
    session["final"] = final = toolbox.gates()
    audits = session["audits"]
    # The last close judged counts if it judged the final version.
    if audits and audits[-1]["source"] == final["source"]:
        final["gates"]["G8"] = audits[-1]["g8"]
    _write(out, session, spent, started, toolbox)
    return session


def compact(history: list[dict], live: list[dict], toolbox: ToolBox, keep: int) -> list[int]:
    """Take old images out of the history, in place: all but the last `keep` and the last one
    of each part and of the assembly. Each goes as a line with what it showed and the call that
    shows it again (ToolBox.describe_image). Returns the seq of the images taken out."""
    kept = {e["seq"] for e in live[-keep:]} if keep > 0 else set()
    last: dict[str, int] = {}
    for entry in live:
        info = toolbox.image_log.get(entry["seq"]) or {}
        for part in info.get("parts", []):
            last[f"part {part}"] = entry["seq"]
        if info.get("assembly"):
            last["assembly"] = entry["seq"]
    kept |= set(last.values())
    removed = [e for e in live if e["seq"] not in kept]
    for entry in removed:
        item = history[entry["index"]]
        text = toolbox.describe_image(entry["seq"])
        history[entry["index"]] = {
            **item,
            "output": [
                {"type": "input_text", "text": text} if c.get("type") == "input_image" else c
                for c in item["output"]
            ],
        }
    live[:] = [e for e in live if e["seq"] in kept]
    return [e["seq"] for e in removed]


def requests_left(limits: Limits, done: int, spent: float, elapsed_s: float) -> int:
    """About how many requests the session has after `done`: the request limit, or the cost and
    the time left at the session's average per request, whichever comes first. The cost and the
    time count once half of them is used: a first request may take minutes (reading the request,
    planning), and nineteen recorded sessions were told at their first or second request that
    about 4 to 10 were left, and to put closing first."""
    left = limits.max_requests - done
    if done and spent > 0 and spent >= limits.max_cost_usd / 2:
        left = min(left, int((limits.max_cost_usd - spent) / (spent / done)))
    if done and elapsed_s > 0 and elapsed_s >= limits.max_wall_s / 2:
        left = min(left, int((limits.max_wall_s - elapsed_s) / (elapsed_s / done)))
    return max(left, 0)


def wrap_up_notice(
    limits: Limits, done: int, spent: float, elapsed_s: float, last: bool = True
) -> str | None:
    """The note for a design session with its end in sight (Limits.wrap_up_requests): with one
    request left, the one that asks for the close, unless `last` is False (it was sent)."""
    if not limits.wrap_up_requests:
        return None
    left = requests_left(limits, done, spent, elapsed_s)
    if left > limits.wrap_up_requests or left == 0:
        return None
    text = WRAP_UP_LAST if left == 1 and last else WRAP_UP
    return text.format(
        left=left,
        requests="request" if left == 1 else "requests",
        are="is" if left == 1 else "are",
        done=done,
        max_requests=limits.max_requests,
        spent=spent,
        max_cost=limits.max_cost_usd,
        minutes=elapsed_s / 60,
        max_minutes=limits.max_wall_s / 60,
    )


def _user(text: str) -> dict[str, str]:
    return {"role": "user", "content": text}


def _as_items(value: Any) -> list[dict[str, Any]]:
    return [_user(value)] if isinstance(value, str) else list(value)


def _lost_previous(call, payload: dict[str, Any]) -> bool:
    """The server no longer has the response this request continues from, or fails on it. Any
    attempt may have said so: the session of 2026-10-30 got "not found" on the three chained
    retries and then a 500 on the last attempt, and ended. A chained request that fails with a
    server error on every attempt is resent whole too: a stress-set session got four 500s in a
    row, two seconds each, on its 19th request, and ended."""
    if call.ok or "previous_response_id" not in payload:
        return False
    tried = [(a.get("status_code"), a.get("error")) for a in call.attempts]
    if len(tried) == MAX_ATTEMPTS and all(code in (500, 503) for code, _ in tried):
        return True
    for status_code, error in tried or [(call.status_code, call.error_summary())]:
        message = error.get("message", "") if isinstance(error, dict) else error
        if status_code in (400, 404) and "not found" in str(message).lower():
            return True
    return False


def _replayable(output: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """The model's output as input items: function calls and text. Reasoning items stay out:
    without store they would need their encrypted content."""
    items: list[dict[str, Any]] = []
    for item in output:
        if item.get("type") == "function_call":
            items.append({k: item.get(k) for k in ("type", "call_id", "name", "arguments")})
        elif item.get("type") == "message":
            text = "".join(
                c.get("text", "")
                for c in item.get("content") or []
                if c.get("type") == "output_text"
            )
            if text:
                items.append({"role": "assistant", "content": text})
    return items


def summarize(call: dict[str, Any], result: dict[str, Any]) -> str:
    """One line per tool call for the iteration table of the report."""
    name = call.get("name")
    try:
        args = json.loads(call.get("arguments") or "{}")
    except json.JSONDecodeError:
        args = {}
    if not result.get("ok", True) and "error" in result:
        return f"error: {result['error'][:160]}"
    if name in ("scad_write", "scad_patch"):
        where = f" line {result['line']}" if "line" in result else ""
        return f"{args.get('path')}{where}: {result.get('lines')} lines"
    if name == "scad_compile":
        return (
            f"ok={result.get('ok')}, {len(result.get('echo', []))} echo, "
            f"{len(result.get('warnings', []))} warnings, "
            f"{len(result.get('asserts_failed', []))} failed asserts, "
            f"{len(result.get('errors', []))} errors"
        )
    if name == "scad_export":
        mesh = result.get("mesh") or {}
        check = result.get("spec_check")
        spec = "no spec" if check is None else ("spec ok" if check["ok"] else "spec FAILS")
        sheet = result.get("sheet") or {}
        sheet = f", sheet {sheet['png']}" if sheet.get("png") else (", no sheet" if sheet else "")
        return (
            f"ok={result.get('ok')}, watertight={mesh.get('watertight')}, "
            f"bodies={mesh.get('bodies')}, bounds={mesh.get('bounds')}, {spec}{sheet}"
        )
    if name == "mesh_report":
        return (
            f"watertight={result.get('watertight')}, bodies={result.get('bodies')}, "
            f"bounds={result.get('bounds')}"
        )
    if name == "printability_report":
        return (
            f"zones={result.get('zones_total')}, undeclared={result.get('zones_undeclared')}, "
            f"fits the bed={result.get('fits_bed')}"
        )
    if name == "render_sheet":
        return f"{result.get('png')}, edges={result.get('edges')}"
    if name in ("run_shell", "run_python"):
        files = result.get("files") or {}
        counts = "/".join(str(len(files.get(k, []))) for k in ("created", "modified", "deleted"))
        edited = f", .scad edited {result['scad_edited']}" if "scad_edited" in result else ""
        return (
            f"exit={result.get('exit_code')}, {result.get('seconds')} s, "
            f"stdout {result.get('stdout_bytes')} B, files +/~/- {counts}{edited}"
        )
    if name == "view_image":
        return f"{args.get('path')} -> {result.get('path')} {result.get('size')}"
    if name == "interference_check":
        problems = result.get("problems") or {}
        return (
            f"{len(result.get('instances') or [])} instances, "
            f"{sum(1 for p in result.get('pairs') or [] if p.get('interference'))} overlaps, "
            f"G3 {len(problems.get('G3', []))} problems, G4 {len(problems.get('G4', []))}, "
            f"G5 {len(problems.get('G5', []))}, "
            f"{result.get('seconds')} s"
        )
    if name == "render_view":
        what = [k for k in ("camera", "zoom", "cut", "explode", "highlight") if args.get(k)]
        cut = (result.get("cut") or [{}])[0]
        numbers = f", cut {cut.get('area_mm2')} mm² {cut.get('regions')} regions" if cut else ""
        return f"{result.get('png')}: {', '.join(what) or 'iso'}{numbers}"
    return json.dumps(result, ensure_ascii=False)[:160]


def _write(out: Path, session: dict, spent: float, started: float, toolbox: ToolBox) -> None:
    requests = [it["request"] for it in session["iterations"]]
    requests += [r for audit in session.get("audits", []) for r in audit["requests"]]
    session["rule_events"] = toolbox.rule_events
    session["spec_adjustments"] = toolbox.history.adjustments
    session["totals"] = {
        "requests": len(requests),
        "tool_calls": sum(len(it["tool_calls"]) for it in session["iterations"]),
        "images": dict(toolbox.images),
        "cost_usd": round(spent, 4),
        "model_latency_s": round(sum(r["latency_s"] for r in requests), 1),
        "wall_s": round(time.perf_counter() - started - session["user_wait_s"], 1),
        "user_wait_s": round(session["user_wait_s"], 1),
        **{
            key: sum(r["usage"][key] for r in requests)
            for key in ("input_tokens", "cached_tokens", "output_tokens", "reasoning_tokens")
        },
    }
    (out / "session.json").write_text(
        json.dumps(session, ensure_ascii=False, indent=2), encoding="utf-8"
    )
