import json

import httpx
import pytest

from cadverify import meta_api
from cadverify.meta_api import (
    ApiCall,
    MetaClient,
    MissingCredentialError,
    cost_usd,
    redact,
    sse_events,
)

KEY = "sk-test-secret-123"


def _client(tmp_path, handler, monkeypatch):
    monkeypatch.setattr(MetaClient, "_backoff", staticmethod(lambda attempt, resp: 0))
    return MetaClient(raw_dir=tmp_path / "raw", api_key=KEY, transport=httpx.MockTransport(handler))


def _raw_records(tmp_path):
    return [json.loads(p.read_text()) for p in sorted((tmp_path / "raw").glob("*.json"))]


def test_missing_key_raises(monkeypatch, tmp_path):
    monkeypatch.delenv("MODEL_API_KEY", raising=False)
    with pytest.raises(MissingCredentialError):
        MetaClient(raw_dir=tmp_path)


def test_redact_replaces_inline_images_only():
    payload = {
        "input": [
            {"type": "input_image", "image_url": "data:image/png;base64,QUJD"},
            {"type": "input_text", "text": "hola"},
        ]
    }
    out = redact(payload)
    assert out["input"][0]["image_url"].startswith("<inline image/png base64, 4 chars, sha256:")
    assert out["input"][1]["text"] == "hola"


def test_key_never_reaches_disk_even_if_echoed(tmp_path, monkeypatch):
    def handler(request):
        assert request.headers["authorization"] == f"Bearer {KEY}"
        return httpx.Response(
            200,
            json={"id": "r1", "status": "completed", "echo": KEY, "output": []},
            headers={"set-cookie": "s=1", "x-request-id": "abc"},
        )

    _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x")
    text = next((tmp_path / "raw").glob("*.json")).read_text()
    assert KEY not in text
    record = json.loads(text)
    assert record["response_headers"]["x-request-id"] == "abc"
    assert "set-cookie" not in record["response_headers"]


def test_retries_retryable_status_then_succeeds(tmp_path, monkeypatch):
    statuses = iter([503, 429, 200])

    def handler(request):
        status = next(statuses)
        if status != 200:
            return httpx.Response(status, json={"error": {"type": "server_error"}})
        return httpx.Response(200, json={"id": "r", "status": "completed", "output": []})

    call = _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x")
    assert call.ok
    assert [a["status_code"] for a in call.attempts] == [503, 429, 200]
    assert len(_raw_records(tmp_path)) == 1


@pytest.mark.parametrize("status", [400, 401, 402, 403, 404])
def test_does_not_retry_client_errors(tmp_path, monkeypatch, status):
    def handler(request):
        return httpx.Response(status, json={"error": {"type": "x", "code": "y", "message": "z"}})

    call = _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x")
    assert not call.ok
    assert len(call.attempts) == 1
    assert call.error_summary()["status_code"] == status


def test_output_accessors_and_cost():
    body = {
        "id": "r",
        "status": "completed",
        "output": [
            {"type": "reasoning", "summary": []},
            {"type": "message", "content": [{"type": "output_text", "text": "Hola"}]},
            {"type": "function_call", "name": "f", "arguments": "{}", "call_id": "c1"},
        ],
        "usage": {
            "input_tokens": 1_000_000,
            "output_tokens": 1_000_000,
            "input_tokens_details": {"cached_tokens": 500_000},
            "output_tokens_details": {"reasoning_tokens": 10},
        },
    }
    call = ApiCall(label="t", status_code=200, body=body, latency_s=1.0, model="muse-wonder-1.0")
    assert call.output_text == "Hola"
    assert [fc["call_id"] for fc in call.function_calls] == ["c1"]
    # 0.5M uncached * $4 + 0.5M cached * $0.20 + 1M output * $20
    assert call.cost_usd == pytest.approx(2.0 + 0.1 + 20.0)
    assert cost_usd({}, "muse-wonder-1.0") == 0


def test_each_model_has_its_price_and_an_unknown_one_costs_the_most():
    usage = {"input_tokens": 1_000_000, "cached_tokens": 500_000, "output_tokens": 1_000_000}
    assert cost_usd(usage, "muse-spark-1.3") == pytest.approx(0.625 + 0.075 + 4.25)
    assert cost_usd(usage, "muse-spark-1.3-contributor") == pytest.approx(0.05 + 0.001 + 0.2)
    assert cost_usd(usage, "muse-new-9") == cost_usd(usage, "muse-wonder-1.0")
    assert cost_usd(usage, None) == cost_usd(usage, "muse-wonder-1.0")


def test_a_call_is_priced_by_the_model_it_asked_for(tmp_path, monkeypatch):
    body = {"id": "r", "status": "completed", "output": [], "usage": {"output_tokens": 1000}}
    client = _client(tmp_path, lambda request: httpx.Response(200, json=body), monkeypatch)
    call = client.responses("t", model="muse-spark-1.3", input="x")
    assert call.model == "muse-spark-1.3" and call.metrics()["model"] == "muse-spark-1.3"
    assert call.cost_usd == pytest.approx(1000 * 4.25 / 1e6)


# ---- streaming --------------------------------------------------------------------------------

USAGE = {"input_tokens": 10, "output_tokens": 5, "input_tokens_details": {"cached_tokens": 0}}


def _sse(*events, done=True) -> bytes:
    """A server-sent event stream as the API sends it: "event:" and "data:" lines."""
    lines = []
    for event in events:
        lines += [f"event: {event['type']}", f"data: {json.dumps(event)}", ""]
    if done:
        lines += ["data: [DONE]", ""]
    return ("\n".join(lines) + "\n").encode()


def _response(status="completed", **extra):
    return {"id": "r1", "status": status, "output": [], "usage": USAGE, **extra}


def _stream(*events, done=True):
    return httpx.Response(
        200, headers={"content-type": "text/event-stream"}, content=_sse(*events, done=done)
    )


def test_a_streamed_response_is_recorded_like_one_without_streaming(tmp_path, monkeypatch):
    final = _response()

    def handler(request):
        assert json.loads(request.content)["stream"] is True
        return _stream(
            {"type": "response.created", "response": _response("in_progress")},
            {"type": "response.output_text.delta", "delta": "Ho"},
            {"type": "response.completed", "response": final},
        )

    call = _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x", stream=True)
    assert (
        call.ok
        and call.body == final
        and call.cost_usd == cost_usd({"input_tokens": 10, "output_tokens": 5}, "m")
    )
    assert call.attempts[0]["stream"] == {"events": 3, "terminal": "response.completed"}
    (record,) = _raw_records(tmp_path)
    assert record["response"] == final and record["request"]["stream"] is True


def test_a_stream_that_fails_with_a_server_error_is_retried(tmp_path, monkeypatch):
    failed = _response("failed", error={"code": "server_error", "message": "boom"})
    streams = iter(
        [
            [{"type": "response.failed", "response": failed}],
            [{"type": "response.completed", "response": _response()}],
        ]
    )
    call = _client(tmp_path, lambda r: _stream(*next(streams)), monkeypatch).responses(
        "t", model="m", input="x", stream=True
    )
    assert call.ok and len(call.attempts) == 2
    assert call.attempts[0]["error"] == {"code": "server_error", "message": "boom"}

    other = _response("failed", error={"code": "invalid_prompt", "message": "no"})
    handler = lambda r: _stream({"type": "response.failed", "response": other})  # noqa: E731
    call = _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x", stream=True)
    assert not call.ok and len(call.attempts) == 1
    assert call.error_summary()["code"] == "invalid_prompt"


class _BrokenStream(httpx.SyncByteStream):
    def __init__(self, first: bytes):
        self.first = first

    def __iter__(self):
        yield self.first
        raise httpx.ReadError("connection cut")


def test_a_broken_stream_is_fetched_from_the_server(tmp_path, monkeypatch):
    monkeypatch.setattr(meta_api, "RECOVER_POLL_S", 0)
    fetched = iter([_response("in_progress"), _response()])

    def handler(request):
        if request.method == "GET":
            assert request.url.path.endswith("/responses/r1")
            return httpx.Response(200, json=next(fetched))
        created = _sse(
            {"type": "response.created", "response": _response("in_progress")}, done=False
        )
        return httpx.Response(200, stream=_BrokenStream(created))

    call = _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x", stream=True)
    assert call.ok and call.response_status == "completed" and len(call.attempts) == 1
    assert call.attempts[0]["stream"] == {"events": 1, "terminal": None, "recovered": True}


def test_a_stream_that_never_started_is_retried_like_a_request(tmp_path, monkeypatch):
    replies = iter([httpx.Response(503, json={"error": {"type": "server_error"}}), None])

    def handler(request):
        reply = next(replies)
        return reply or _stream({"type": "response.completed", "response": _response()})

    call = _client(tmp_path, handler, monkeypatch).responses("t", model="m", input="x", stream=True)
    assert call.ok and [a["status_code"] for a in call.attempts] == [503, 200]


def test_a_chained_request_waits_for_the_previous_response_to_be_stored(tmp_path, monkeypatch):
    monkeypatch.setattr(meta_api, "CHAIN_BACKOFF_S", 0)
    missing = {"error": {"type": "invalid_request_error", "message": "Response r0 not found"}}
    replies = iter([404, 404, 200])

    def handler(request):
        status = next(replies)
        if status == 404:
            return httpx.Response(404, json=missing)
        return httpx.Response(200, json=_response())

    client = _client(tmp_path, handler, monkeypatch)
    call = client.responses("t", model="m", input="x", previous_response_id="r0")
    assert call.ok and [a["status_code"] for a in call.attempts] == [404, 404, 200]


def test_sse_events():
    lines = [
        "event: a",
        'data:{"type": "a"}',
        "",
        ": comentario",
        'data: {"type":',
        'data: "b"}',
        "",
    ]
    lines += ["data: [DONE]", "", 'data: {"type": "c"}', ""]
    assert list(sse_events(lines)) == [{"type": "a"}, {"type": "b"}]
    assert list(sse_events(['data: {"type": "no newline"}'])) == [{"type": "no newline"}]
