"""Minimal client for the Meta Model API Responses endpoint.

Every request is timed and saved as a redacted raw record (request body, response body,
selected headers) so experiment results can be audited later. The API key is never written.

Reference: https://dev.meta.ai/docs/protocols/responses and /docs/error-handling (read 2026-10-26).

With stream=True the response comes as server-sent events. A request without streaming has a
server time limit (HTTP 504 gateway_timeout after about 600 s: the first session with 64k of
output hit it while the model designed); a streamed one does not. The record is the same: the
body is the response of the terminal event. If the stream breaks after the response started, the
server still stores it, and the client fetches it (GET /v1/responses/<id>).
"""

from __future__ import annotations

import hashlib
import itertools
import json
import os
import random
import re
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx

BASE_URL = "https://api.meta.ai/v1"
MODEL = "muse-wonder-1.0"

# USD per 1M tokens (dev.meta.ai/docs/pricing-rate-limits, read 2026-10-31). A "-contributor"
# model is the same model at a discount, in exchange for Meta training on what it is sent.
# dev.meta.ai/docs/pricing-rate-limits: USD 2.50 per 1000 search queries, on top of the tokens.
WEB_SEARCH_USD = 0.0025
PRICE_PER_MTOK = {
    "muse-wonder-1.0": {"input": 4.00, "cached_input": 0.20, "output": 20.00},
    "muse-spark-1.3": {"input": 1.25, "cached_input": 0.15, "output": 4.25},
    "muse-spark-1.3-contributor": {"input": 0.10, "cached_input": 0.002, "output": 0.20},
}
# A model without a price here is counted at the highest one, so a budget is never underestimated.
UNKNOWN_PRICE = {k: max(p[k] for p in PRICE_PER_MTOK.values()) for k in PRICE_PER_MTOK[MODEL]}

# Statuses the docs say are worth retrying with backoff. 400/401/402/403/404/413/504 are not.
RETRYABLE_STATUS = {429, 500, 503}
MAX_ATTEMPTS = 4

# Streaming (dev.meta.ai/docs/protocols/responses, read 2026-10-29; seen in a probe: "event:" and
# "data:" lines, response.completed with the whole response, then "data: [DONE]").
TERMINAL_EVENTS = {"response.completed", "response.incomplete", "response.failed"}
TERMINAL_STATUSES = {"completed", "incomplete", "failed", "cancelled"}
STREAM_READ_TIMEOUT_S = 1800.0  # the stream is quiet while the model reasons: no reasoning events
RECOVER_POLL_S = 10.0
RECOVER_MAX_S = 1800.0
# A response just finished can take a few seconds to be stored for previous_response_id.
CHAIN_RETRIES = 3
CHAIN_BACKOFF_S = 2.0

# Response headers worth keeping for diagnosis. Everything else (cookies included) is dropped.
_KEPT_HEADER = re.compile(
    r"^(content-type|date|retry-after|.*request-id.*|.*ratelimit.*|.*processing.*)$"
)
_DATA_URL = re.compile(r"^data:([\w/+.-]+);base64,(.+)$", re.S)


class MissingCredentialError(RuntimeError):
    pass


@dataclass
class ApiCall:
    """One logical request (possibly several attempts) and its outcome."""

    label: str
    status_code: int | None
    body: dict[str, Any] | None
    latency_s: float
    attempts: list[dict[str, Any]] = field(default_factory=list)
    error: str | None = None
    model: str | None = None  # the model asked for, which sets the price

    @property
    def ok(self) -> bool:
        # A stream that failed comes as a response with status "failed" and its error.
        return (
            self.status_code == 200
            and self.body is not None
            and self.body.get("status") != "failed"
        )

    @property
    def response_id(self) -> str | None:
        return (self.body or {}).get("id")

    @property
    def response_status(self) -> str | None:
        return (self.body or {}).get("status")

    @property
    def output(self) -> list[dict[str, Any]]:
        return (self.body or {}).get("output") or []

    @property
    def output_text(self) -> str:
        parts = []
        for item in self.output:
            if item.get("type") == "message":
                for content in item.get("content") or []:
                    if content.get("type") == "output_text":
                        parts.append(content.get("text", ""))
        return "".join(parts)

    @property
    def function_calls(self) -> list[dict[str, Any]]:
        return [item for item in self.output if item.get("type") == "function_call"]

    @property
    def usage(self) -> dict[str, int]:
        usage = (self.body or {}).get("usage") or {}
        return {
            "input_tokens": usage.get("input_tokens", 0),
            "cached_tokens": (usage.get("input_tokens_details") or {}).get("cached_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
            "reasoning_tokens": (usage.get("output_tokens_details") or {}).get(
                "reasoning_tokens", 0
            ),
            "total_tokens": usage.get("total_tokens", 0),
        }

    @property
    def cost_usd(self) -> float:
        return cost_usd(self.usage, self.model) + search_fee_usd(self.output)

    def error_summary(self) -> dict[str, Any] | None:
        if self.ok:
            return None
        err = (self.body or {}).get("error") or {}
        return {
            "status_code": self.status_code,
            "type": err.get("type"),
            "code": err.get("code"),
            "message": err.get("message") or self.error,
        }

    def metrics(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "model": self.model,
            "ok": self.ok,
            "status_code": self.status_code,
            "response_status": self.response_status,
            "latency_s": round(self.latency_s, 3),
            "attempts": len(self.attempts),
            "usage": self.usage,
            "cost_usd": round(self.cost_usd, 6),
            "error": self.error_summary(),
        }


def search_fee_usd(output: list[dict[str, Any]] | None) -> float:
    """What a response's web searches cost, on top of its tokens."""
    return WEB_SEARCH_USD * sum(1 for i in output or [] if i.get("type") == "web_search_call")


def cost_usd(usage: dict[str, int], model: str | None) -> float:
    price = PRICE_PER_MTOK.get(model or "", UNKNOWN_PRICE)
    cached = usage.get("cached_tokens", 0)
    uncached = max(usage.get("input_tokens", 0) - cached, 0)
    return (
        uncached * price["input"]
        + cached * price["cached_input"]
        + usage.get("output_tokens", 0) * price["output"]
    ) / 1_000_000


def redact(value: Any) -> Any:
    """Replace inline images (base64 data URLs) with a short fingerprint."""
    if isinstance(value, dict):
        return {k: redact(v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, str):
        match = _DATA_URL.match(value)
        if match:
            digest = hashlib.sha256(match.group(2).encode()).hexdigest()[:16]
            return f"<inline {match.group(1)} base64, {len(match.group(2))} chars, sha256:{digest}>"
    return value


def kept_headers(headers: httpx.Headers) -> dict[str, str]:
    return {k: v for k, v in headers.items() if _KEPT_HEADER.match(k.lower())}


def sse_events(lines) -> Any:
    """The JSON events of a server-sent event stream: its "data:" lines, each event ended by a
    blank line; "[DONE]" ends the stream."""
    data: list[str] = []
    for line in itertools.chain(lines, [""]):  # lazily: the events come while the stream runs
        if line.startswith("data:"):
            data.append(line[5:].lstrip())
        elif not line and data:
            text, data = "\n".join(data), []
            if text == "[DONE]":
                return
            yield json.loads(text)


def _json_body(resp: httpx.Response) -> tuple[dict[str, Any] | None, str | None]:
    try:
        return resp.json(), None
    except ValueError:
        return None, f"non-JSON body: {resp.text[:500]}"


def _chain_not_stored(payload: dict, status_code: int | None, body: dict | None) -> bool:
    message = str(((body or {}).get("error") or {}).get("message", ""))
    return (
        "previous_response_id" in payload
        and status_code in (400, 404)
        and "not found" in message.lower()
    )


class MetaClient:
    def __init__(
        self,
        raw_dir: Path,
        api_key: str | None = None,
        base_url: str = BASE_URL,
        timeout_s: float = 900.0,
        transport: httpx.BaseTransport | None = None,
    ):
        key = api_key if api_key is not None else os.environ.get("MODEL_API_KEY", "")
        if not key.strip():
            raise MissingCredentialError(
                "MODEL_API_KEY is not set. Put it in .env (see .env.example) or export it."
            )
        self._key = key.strip()
        self.raw_dir = raw_dir
        self.raw_dir.mkdir(parents=True, exist_ok=True)
        self._http = httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {self._key}"},
            timeout=httpx.Timeout(timeout_s, connect=30.0),
            transport=transport,
        )
        self._lock = threading.Lock()
        self._seq = 0

    def close(self) -> None:
        self._http.close()

    def responses(self, label: str, **payload: Any) -> ApiCall:
        """POST /v1/responses with retries on 429/500/503 and on a stream that failed with a
        server error, honoring Retry-After; streamed with stream=True. A request chained to a
        response the server has not stored yet is retried after a few seconds."""
        attempts: list[dict[str, Any]] = []
        started = time.perf_counter()
        status_code: int | None = None
        body: dict[str, Any] | None = None
        error: str | None = None
        headers: dict[str, str] = {}
        for attempt in range(1, MAX_ATTEMPTS + 1):
            t0 = time.perf_counter()
            if payload.get("stream"):
                status_code, headers, body, error, resp, stream = self._post_stream(payload)
            else:
                (status_code, headers, body, error, resp), stream = self._post(payload), None
            failed = (body or {}).get("status") == "failed"
            attempts.append(
                {
                    "attempt": attempt,
                    "status_code": status_code,
                    "latency_s": round(time.perf_counter() - t0, 3),
                    "error": error
                    or ((body or {}).get("error") if status_code != 200 or failed else None),
                    **({"stream": stream} if stream else {}),
                }
            )
            server_failed = failed and ((body or {}).get("error") or {}).get("code") == (
                "server_error"
            )
            # A stream that sent no event has no response to fetch (a showcase session waited
            # 30 min on one, then ended): the only way on is to send it again, though the server
            # may have billed it, since no usage of it ever reaches the client. A request without
            # streaming that timed out may still be running, and is not sent twice.
            silent = stream is not None and stream["events"] == 0 and status_code is None
            retryable = (
                status_code in RETRYABLE_STATUS
                or server_failed
                or silent
                or (status_code is None and isinstance(error, str) and "Timeout" not in error)
            )
            chained = attempt <= CHAIN_RETRIES and _chain_not_stored(payload, status_code, body)
            if not (retryable or chained) or attempt == MAX_ATTEMPTS:
                break
            time.sleep(CHAIN_BACKOFF_S * attempt if chained else self._backoff(attempt, resp))
        call = ApiCall(
            label=label,
            status_code=status_code,
            body=body,
            # Latency of the attempt that produced the final answer, not of the retries.
            latency_s=attempts[-1]["latency_s"],
            attempts=attempts,
            error=error,
            model=payload.get("model"),
        )
        call_total = round(time.perf_counter() - started, 3)
        self._write_raw(call, payload, headers, call_total)
        return call

    def _post(self, payload: dict) -> tuple:
        """One attempt without streaming: status, headers, body, error and the response."""
        try:
            resp = self._http.post("/responses", json=payload)
        except httpx.HTTPError as exc:
            return None, {}, None, f"{type(exc).__name__}: {exc}", None
        body, error = _json_body(resp)
        return resp.status_code, kept_headers(resp.headers), body, error, resp

    def _post_stream(self, payload: dict) -> tuple:
        """One streamed attempt: status, headers, body, error, the response and what the stream
        brought ({"events", "first_event_s", "terminal", "recovered"})."""
        info: dict[str, Any] = {"events": 0, "terminal": None}
        started = time.perf_counter()
        headers: dict[str, str] = {}
        response_id, final, error, resp = None, None, None, None
        timeout = httpx.Timeout(STREAM_READ_TIMEOUT_S, connect=30.0)
        try:
            with self._http.stream("POST", "/responses", json=payload, timeout=timeout) as resp:
                headers = kept_headers(resp.headers)
                if resp.status_code != 200:
                    resp.read()
                    body, error = _json_body(resp)
                    return resp.status_code, headers, body, error, resp, None
                for event in sse_events(resp.iter_lines()):
                    info["events"] += 1
                    if info["events"] == 1:
                        info["first_event_s"] = round(time.perf_counter() - started, 3)
                    response = event.get("response")
                    if isinstance(response, dict):
                        response_id = response.get("id") or response_id
                    if event.get("type") in TERMINAL_EVENTS:
                        info["terminal"], final = event["type"], response
                        break
        except (httpx.HTTPError, ValueError) as exc:
            error = f"{type(exc).__name__} in the stream: {exc}"
        if final is None and response_id is not None:
            final = self._recover(response_id)
            info["recovered"] = final is not None
        if final is None:
            error = error or "the stream ended without a final event"
            return None, headers, None, error, resp, info
        return 200, headers, final, None, resp, info

    def _recover(self, response_id: str) -> dict[str, Any] | None:
        """The response of a broken stream, once the server has it in a final status."""
        deadline = time.perf_counter() + RECOVER_MAX_S
        while True:
            try:
                resp = self._http.get(f"/responses/{response_id}")
                body = resp.json() if resp.status_code == 200 else None
            except (httpx.HTTPError, ValueError):
                body = None
            if body and body.get("status") in TERMINAL_STATUSES:
                return body
            if time.perf_counter() >= deadline:
                return None
            time.sleep(RECOVER_POLL_S)

    @staticmethod
    def _backoff(attempt: int, resp: httpx.Response | None) -> float:
        if resp is not None:
            retry_after = resp.headers.get("retry-after")
            if retry_after and retry_after.replace(".", "", 1).isdigit():
                return min(float(retry_after), 120.0)
        return min(2**attempt + random.uniform(0, 1), 60.0)

    def _write_raw(
        self, call: ApiCall, payload: dict, headers: dict[str, str], total_s: float
    ) -> Path:
        with self._lock:
            self._seq += 1
            seq = self._seq
        name = f"{seq:04d}-{re.sub(r'[^\w.-]+', '_', call.label)}-{uuid.uuid4().hex[:6]}.json"
        record = {
            "label": call.label,
            "endpoint": "POST /v1/responses",
            "request": redact(payload),
            "status_code": call.status_code,
            "response_headers": headers,
            "response": call.body,
            "latency_s": call.latency_s,
            "total_with_retries_s": total_s,
            "attempts": call.attempts,
            "client_error": call.error,
        }
        text = json.dumps(record, ensure_ascii=False, indent=2)
        # Defense in depth: the key must never reach disk, whatever the server echoes back.
        text = text.replace(self._key, "<redacted>")
        path = self.raw_dir / name
        path.write_text(text, encoding="utf-8")
        return path
