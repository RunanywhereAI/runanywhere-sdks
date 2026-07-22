"""Hermetic tests for the built-in OpenAI-compatible server (runanywhere.server).

Runs with NO native build and NO downloaded models: a fake ``ModelManager`` is injected into
``create_app`` and its fake models return real strings/ndarrays, so the routes, SSE streaming,
embeddings encoding, tool-calling shape, vision temp-file handling, error->HTTP mapping, and
api-key auth are all genuinely exercised. Skipped entirely unless the ``[server]`` extra
(fastapi) is installed.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
from types import SimpleNamespace

import numpy as np
import pytest

pytest.importorskip("fastapi")
from fastapi.testclient import TestClient  # noqa: E402

from runanywhere.audio import decode_wav, encode_wav  # noqa: E402
from runanywhere.errors import SDKException  # noqa: E402
from runanywhere.results import Synthesis  # noqa: E402
from runanywhere.server import create_app  # noqa: E402
from runanywhere.structured import ToolCall  # noqa: E402


# --------------------------------------------------------------------------- fakes
class FakeLLM:
    def __init__(self, tokens=("Hello", " world"), *, text=None, tool_call=None,
                 raise_exc=None, raise_mid_stream=False):
        self._tokens = list(tokens)
        self._text = text
        self._tool_call = tool_call
        self._raise = raise_exc
        self._raise_mid = raise_mid_stream
        self.last_prompt = None   # recorded so tests can assert prompt/opts assembly
        self.last_opts = None

    async def agenerate(self, prompt, **opts):
        self.last_prompt, self.last_opts = prompt, opts
        if self._raise and not self._raise_mid:
            raise self._raise
        for i, tok in enumerate(self._tokens):
            yield tok
            if self._raise_mid and i == 0:
                raise self._raise or SDKException.generation_failed("boom")

    async def agenerate_text(self, prompt, **opts):
        self.last_prompt, self.last_opts = prompt, opts
        if self._raise:
            raise self._raise
        return self._text if self._text is not None else "".join(self._tokens)

    async def agenerate_tool_call(self, prompt, tools, **opts):
        self.last_prompt, self.last_opts = prompt, opts
        if self._raise:
            raise self._raise
        return self._tool_call


class FakeVLM:
    def __init__(self, tokens=("a", " cat"), *, text=None):
        self._tokens = list(tokens)
        self._text = text
        self.captured_path = None  # the path the route handed us (must be a real materialized file)

    async def acaption(self, image_path, prompt):
        self.captured_path = image_path
        assert os.path.exists(image_path)  # the route must have materialized the image
        for tok in self._tokens:
            yield tok

    async def acaption_text(self, image_path, prompt):
        self.captured_path = image_path
        assert os.path.exists(image_path)
        return self._text if self._text is not None else "".join(self._tokens)


class FakeEmbedder:
    def __init__(self, dim=4):
        self._dim = dim

    def embed(self, text):
        # input-dependent so a reorder/drop/dup regression is observable in tests
        return np.arange(self._dim, dtype=np.float32) + float(len(text))


class FakeSTT:
    def __init__(self, text="hello"):
        self._text = text

    async def atranscribe(self, pcm16):
        assert isinstance(pcm16, (bytes, bytearray))
        return self._text


class FakeTTS:
    async def asynthesize(self, text):
        return Synthesis(samples=np.zeros(8, dtype=np.float32), sample_rate=22050)


class FakeManager:
    def __init__(self, *, llm=None, vlm=None, embedder=None, stt=None, tts=None, status=None):
        self.default_llm = "fake-llm"
        self.default_vlm = "fake-vlm"
        self.default_embedder = "fake-emb"
        self.default_stt = "fake-stt"
        self.default_tts = "fake-tts"
        self._llm = llm or FakeLLM()
        self._vlm = vlm or FakeVLM()
        self._emb = embedder or FakeEmbedder()
        self._stt = stt or FakeSTT()
        self._tts = tts or FakeTTS()
        self._status = status or {}
        self._locks: dict = {}  # cached per (kind, id) — mirrors the real ModelManager

    def start(self):
        pass

    def stop(self):
        pass

    def backends(self):
        return ["fake"]

    def model_status(self):
        return self._status

    def _lock(self, key):
        return self._locks.setdefault(key, asyncio.Lock())

    async def llm(self, model_id):
        return self._llm, self._lock(("llm", model_id))

    async def vlm(self, model_id):
        return self._vlm, self._lock(("vlm", model_id))

    async def embedder(self, model_id):
        return self._emb, self._lock(("emb", model_id))

    async def stt(self, model_id):
        return self._stt, self._lock(("stt", model_id))

    async def tts(self, model_id):
        return self._tts, self._lock(("tts", model_id))


def _client(manager=None, **kw):
    return TestClient(create_app(model_manager=manager or FakeManager(), **kw))


def _sse_events(text: str) -> list:
    """Parse `data: {json}` lines from an SSE body (dropping the [DONE] sentinel)."""
    out = []
    for line in text.splitlines():
        if line.startswith("data: "):
            payload = line[len("data: "):]
            if payload.strip() == "[DONE]":
                continue
            out.append(json.loads(payload))
    return out


# --------------------------------------------------------------------------- info
def test_health():
    with _client() as c:
        assert c.get("/health").json() == {"status": "ok"}


def test_root_reports_backends_and_endpoints():
    with _client() as c:
        body = c.get("/").json()
        assert body["service"] == "runanywhere-openai-server"
        assert body["backends"] == ["fake"]
        assert "/v1/chat/completions" in body["endpoints"]


def test_list_and_retrieve_models():
    with _client() as c:
        data = c.get("/v1/models").json()["data"]
        assert data and all({"id", "object", "type", "downloaded"} <= set(m) for m in data)
        first = data[0]["id"]
        assert c.get(f"/v1/models/{first}").json()["id"] == first
        assert c.get("/v1/models/does-not-exist-xyz").status_code == 404


# --------------------------------------------------------------------------- chat
def test_chat_completions_non_stream():
    with _client() as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m", "messages": [{"role": "user", "content": "hi"}]})
        j = r.json()
        assert j["object"] == "chat.completion"
        assert j["choices"][0]["message"]["content"] == "Hello world"
        assert j["choices"][0]["finish_reason"] == "stop"
        assert j["usage"]["total_tokens"] >= 1


def test_chat_completions_stream():
    with _client() as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m", "stream": True, "messages": [{"role": "user", "content": "hi"}]})
        assert r.headers["content-type"].startswith("text/event-stream")
        events = _sse_events(r.text)
        assert events[0]["choices"][0]["delta"].get("role") == "assistant"
        content = "".join(e["choices"][0]["delta"].get("content", "") for e in events)
        assert content == "Hello world"
        assert events[-1]["choices"][0]["finish_reason"] == "stop"
        assert r.text.rstrip().endswith("data: [DONE]")


def test_chat_stream_mid_stream_error_is_terminal():
    mgr = FakeManager(llm=FakeLLM(raise_mid_stream=True,
                                  raise_exc=SDKException.generation_failed("kaboom")))
    with _client(mgr) as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m", "stream": True, "messages": [{"role": "user", "content": "hi"}]})
        assert r.status_code == 200  # headers already sent; error is a terminal data line
        assert '"error"' in r.text
        assert r.text.rstrip().endswith("data: [DONE]")


def test_system_prompt_is_accepted():
    with _client() as c:
        r = c.post("/v1/chat/completions", json={"model": "m", "messages": [
            {"role": "system", "content": "be terse"},
            {"role": "user", "content": "hi"}]})
        assert r.status_code == 200


# --------------------------------------------------------------------------- completions
def test_completions_non_stream():
    with _client() as c:
        j = c.post("/v1/completions", json={"model": "m", "prompt": "once upon"}).json()
        assert j["object"] == "text_completion"
        assert j["choices"][0]["text"] == "Hello world"


def test_completions_stream():
    with _client() as c:
        r = c.post("/v1/completions", json={"model": "m", "prompt": "x", "stream": True})
        events = _sse_events(r.text)
        assert "".join(e["choices"][0]["text"] for e in events) == "Hello world"


# --------------------------------------------------------------------------- embeddings
def test_embeddings_float():
    with _client() as c:
        j = c.post("/v1/embeddings", json={"model": "m", "input": "a"}).json()
        assert len(j["data"]) == 1
        assert j["data"][0]["embedding"] == [1.0, 2.0, 3.0, 4.0]  # arange(4) + len("a")


def test_embeddings_multi_input_preserves_order_and_index():
    # FakeEmbedder is input-length-dependent, so a reorder/drop would change the vectors.
    with _client() as c:
        j = c.post("/v1/embeddings", json={"model": "m", "input": ["a", "bb", "ccc"]}).json()
        assert [d["index"] for d in j["data"]] == [0, 1, 2]
        assert [d["embedding"][0] for d in j["data"]] == [1.0, 2.0, 3.0]  # len 1, 2, 3


def test_embeddings_base64():
    with _client() as c:
        j = c.post("/v1/embeddings", json={
            "model": "m", "input": "a", "encoding_format": "base64"}).json()
        raw = base64.b64decode(j["data"][0]["embedding"])
        assert np.frombuffer(raw, dtype="<f4").tolist() == [1.0, 2.0, 3.0, 4.0]


# --------------------------------------------------------------------------- audio
def test_transcriptions_round_trip():
    wav = encode_wav(np.zeros(16000, dtype=np.float32), 16000)
    with _client() as c:
        r = c.post("/v1/audio/transcriptions",
                   files={"file": ("a.wav", wav, "audio/wav")}, data={"model": "whisper"})
        assert r.json() == {"text": "hello"}


def test_transcriptions_bad_audio_is_400():
    with _client() as c:
        r = c.post("/v1/audio/transcriptions",
                   files={"file": ("a.wav", b"not a wav", "audio/wav")})
        assert r.status_code == 400


def test_speech_returns_wav():
    with _client() as c:
        r = c.post("/v1/audio/speech", json={"model": "tts", "input": "hello"})
        assert r.headers["content-type"] == "audio/wav"
        rate, samples = decode_wav(r.content)
        assert rate == 22050 and samples.shape[0] == 8


# --------------------------------------------------------------------------- tools
def test_tools_required_returns_tool_calls():
    mgr = FakeManager(llm=FakeLLM(tool_call=ToolCall("get_weather", {"city": "Paris"})))
    with _client(mgr) as c:
        j = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "weather in Paris?"}],
            "tools": [{"type": "function", "function": {"name": "get_weather",
                       "parameters": {"type": "object"}}}],
            "tool_choice": "required"}).json()
        msg = j["choices"][0]["message"]
        assert j["choices"][0]["finish_reason"] == "tool_calls"
        assert msg["tool_calls"][0]["function"]["name"] == "get_weather"
        assert json.loads(msg["tool_calls"][0]["function"]["arguments"]) == {"city": "Paris"}


def test_tools_auto_detects_tool_call():
    call = json.dumps({"name": "get_weather", "arguments": {"city": "Paris"}})
    mgr = FakeManager(llm=FakeLLM(text=call))
    with _client(mgr) as c:
        j = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "weather?"}],
            "tools": [{"type": "function", "function": {"name": "get_weather",
                       "parameters": {"type": "object"}}}]}).json()
        assert j["choices"][0]["finish_reason"] == "tool_calls"
        assert j["choices"][0]["message"]["tool_calls"][0]["function"]["name"] == "get_weather"


def test_tools_auto_falls_back_to_content():
    mgr = FakeManager(llm=FakeLLM(text="It is sunny."))
    with _client(mgr) as c:
        j = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "weather?"}],
            "tools": [{"type": "function", "function": {"name": "get_weather",
                       "parameters": {"type": "object"}}}]}).json()
        assert j["choices"][0]["finish_reason"] == "stop"
        assert j["choices"][0]["message"]["content"] == "It is sunny."


def test_tool_choice_none_ignores_tools():
    with _client() as c:
        j = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "hi"}],
            "tools": [{"type": "function", "function": {"name": "x",
                       "parameters": {"type": "object"}}}],
            "tool_choice": "none"}).json()
        assert j["choices"][0]["message"]["content"] == "Hello world"


# --------------------------------------------------------------------------- vision
def test_vision_data_uri_routes_to_vlm():
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n fake bytes").decode()
    mgr = FakeManager(vlm=FakeVLM(text="a cat on a mat"))
    with _client(mgr) as c:
        j = c.post("/v1/chat/completions", json={"model": "m", "messages": [{
            "role": "user", "content": [
                {"type": "text", "text": "what is this?"},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}"}}]}]}).json()
        assert j["choices"][0]["message"]["content"] == "a cat on a mat"


# --------------------------------------------------------------------------- structured
def test_response_format_json_schema_is_accepted():
    mgr = FakeManager(llm=FakeLLM(text='{"x": 1}'))
    with _client(mgr) as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "give json"}],
            "response_format": {"type": "json_schema", "json_schema": {
                "schema": {"type": "object", "properties": {"x": {"type": "integer"}}}}}})
        assert r.status_code == 200
        assert r.json()["choices"][0]["message"]["content"] == '{"x": 1}'


# --------------------------------------------------------------------------- error mapping
@pytest.mark.parametrize("exc,status", [
    (SDKException.model_not_found("x"), 404),
    (SDKException.invalid_state("busy"), 409),
    (SDKException.not_initialized("engine"), 503),
    (SDKException.invalid_input("bad"), 400),
    (SDKException.generation_failed("oops"), 500),
])
def test_error_code_maps_to_http_status(exc, status):
    mgr = FakeManager(llm=FakeLLM(raise_exc=exc))
    with _client(mgr) as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m", "messages": [{"role": "user", "content": "hi"}]})
        assert r.status_code == status
        assert r.json()["error"]["message"]


# --------------------------------------------------------------------------- auth
def test_api_key_required_when_configured():
    with _client(api_key="secret") as c:
        body = {"model": "m", "messages": [{"role": "user", "content": "hi"}]}
        assert c.post("/v1/chat/completions", json=body).status_code == 401
        assert c.post("/v1/chat/completions", json=body,
                      headers={"Authorization": "Bearer wrong"}).status_code == 401
        assert c.post("/v1/chat/completions", json=body,
                      headers={"Authorization": "Bearer secret"}).status_code == 200
        # health is unauthenticated (for liveness probes)
        assert c.get("/health").status_code == 200


@pytest.mark.parametrize("method,path,json_body", [
    ("get", "/", None),
    ("get", "/v1/models", None),
    ("get", "/v1/models/minilm", None),
    ("post", "/v1/chat/completions", {"messages": [{"role": "user", "content": "hi"}]}),
    ("post", "/v1/completions", {"prompt": "x"}),
    ("post", "/v1/embeddings", {"input": "a"}),
    ("post", "/v1/audio/speech", {"input": "hi"}),
])
def test_api_key_guards_every_v1_route_and_root(method, path, json_body):
    with _client(api_key="secret") as c:
        r = c.request(method, path, json=json_body)
        assert r.status_code == 401  # missing key -> 401 on all guarded routes (root included)
        ok = c.request(method, path, json=json_body, headers={"Authorization": "Bearer secret"})
        assert ok.status_code == 200


def test_health_is_never_guarded():
    with _client(api_key="secret") as c:
        assert c.get("/health").status_code == 200


# --------------------------------------------------------------------------- streaming shapes
def test_streamed_tool_calls_carry_index():
    mgr = FakeManager(llm=FakeLLM(tool_call=ToolCall("get_weather", {"city": "Paris"})))
    with _client(mgr) as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m", "stream": True,
            "messages": [{"role": "user", "content": "weather?"}],
            "tools": [{"type": "function", "function": {"name": "get_weather",
                       "parameters": {"type": "object"}}}],
            "tool_choice": "required"})
        events = _sse_events(r.text)
        tc_deltas = [e for e in events if e["choices"][0]["delta"].get("tool_calls")]
        assert tc_deltas, "expected a tool_calls delta"
        call = tc_deltas[0]["choices"][0]["delta"]["tool_calls"][0]
        assert call["index"] == 0  # required by openai-python/LangChain accumulation
        assert call["function"]["name"] == "get_weather"
        assert events[-1]["choices"][0]["finish_reason"] == "tool_calls"


def test_completions_stream_mid_stream_error_is_terminal():
    mgr = FakeManager(llm=FakeLLM(raise_mid_stream=True,
                                  raise_exc=SDKException.generation_failed("boom")))
    with _client(mgr) as c:
        r = c.post("/v1/completions", json={"model": "m", "prompt": "x", "stream": True})
        assert r.status_code == 200
        assert '"error"' in r.text and r.text.rstrip().endswith("data: [DONE]")


# --------------------------------------------------------------------------- tools edge cases
def test_tool_choice_named_unknown_is_400():
    with _client() as c:
        r = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "hi"}],
            "tools": [{"type": "function", "function": {"name": "known",
                       "parameters": {"type": "object"}}}],
            "tool_choice": {"type": "function", "function": {"name": "nonexistent"}}})
        assert r.status_code == 400


def test_tool_choice_named_known_forces_that_tool():
    mgr = FakeManager(llm=FakeLLM(tool_call=ToolCall("known", {"a": 1})))
    with _client(mgr) as c:
        j = c.post("/v1/chat/completions", json={
            "model": "m",
            "messages": [{"role": "user", "content": "hi"}],
            "tools": [{"type": "function", "function": {"name": "known",
                       "parameters": {"type": "object"}}}],
            "tool_choice": {"type": "function", "function": {"name": "known"}}}).json()
        assert j["choices"][0]["message"]["tool_calls"][0]["function"]["name"] == "known"


# --------------------------------------------------------------------------- vision (security + streaming)
def test_vision_streaming():
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n x").decode()
    mgr = FakeManager(vlm=FakeVLM(tokens=("a", " cat")))
    with _client(mgr) as c:
        r = c.post("/v1/chat/completions", json={"model": "m", "stream": True, "messages": [{
            "role": "user", "content": [
                {"type": "text", "text": "what?"},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}"}}]}]})
        content = "".join(e["choices"][0]["delta"].get("content", "") for e in _sse_events(r.text))
        assert content == "a cat"


def test_vision_temp_file_is_cleaned_up():
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n x").decode()
    vlm = FakeVLM(text="ok")
    with _client(FakeManager(vlm=vlm)) as c:
        c.post("/v1/chat/completions", json={"model": "m", "messages": [{
            "role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}"}}]}]})
    assert vlm.captured_path is not None
    assert not os.path.exists(vlm.captured_path)  # temp image removed after the request


@pytest.mark.parametrize("url", ["/etc/passwd", "C:\\Windows\\win.ini", "file:///etc/shadow"])
def test_vision_rejects_local_paths(url):
    with _client() as c:
        r = c.post("/v1/chat/completions", json={"model": "m", "messages": [{
            "role": "user", "content": [{"type": "image_url", "image_url": {"url": url}}]}]})
        assert r.status_code == 400  # arbitrary-file-read guard


@pytest.mark.parametrize("url", ["http://127.0.0.1/x", "http://169.254.169.254/latest/meta-data"])
def test_vision_rejects_ssrf_targets(url):
    with _client() as c:
        r = c.post("/v1/chat/completions", json={"model": "m", "messages": [{
            "role": "user", "content": [{"type": "image_url", "image_url": {"url": url}}]}]})
        assert r.status_code == 400  # SSRF guard (loopback / link-local)


# --------------------------------------------------------------------------- prompt / structured / limits
def test_multi_turn_prompt_is_serialized_to_transcript():
    llm = FakeLLM()
    with _client(FakeManager(llm=llm)) as c:
        c.post("/v1/chat/completions", json={"model": "m", "messages": [
            {"role": "user", "content": "hi"},
            {"role": "assistant", "content": "hello"},
            {"role": "user", "content": "bye"}]})
    assert "User: hi" in llm.last_prompt and "Assistant: hello" in llm.last_prompt


def test_response_format_json_object_adds_system_hint():
    llm = FakeLLM(text="{}")
    with _client(FakeManager(llm=llm)) as c:
        c.post("/v1/chat/completions", json={
            "model": "m", "messages": [{"role": "user", "content": "give json"}],
            "response_format": {"type": "json_object"}})
    assert "JSON" in (llm.last_opts.get("system_prompt") or "")


def test_response_format_json_schema_sets_grammar():
    llm = FakeLLM(text='{"x": 1}')
    with _client(FakeManager(llm=llm)) as c:
        c.post("/v1/chat/completions", json={
            "model": "m", "messages": [{"role": "user", "content": "json"}],
            "response_format": {"type": "json_schema", "json_schema": {
                "schema": {"type": "object", "properties": {"x": {"type": "integer"}}}}}})
    assert llm.last_opts.get("grammar")  # a GBNF grammar was passed to the model


def test_transcriptions_resamples_non_16k():
    wav = encode_wav(np.zeros(48000, dtype=np.float32), 48000)  # 48 kHz -> exercises downsample
    with _client() as c:
        r = c.post("/v1/audio/transcriptions",
                   files={"file": ("a.wav", wav, "audio/wav")}, data={"model": "whisper"})
        assert r.json() == {"text": "hello"}


def test_models_downloaded_flag_reflects_status():
    mgr = FakeManager(status={"minilm": SimpleNamespace(downloaded=True, size_bytes=1)})
    with _client(mgr) as c:
        data = c.get("/v1/models").json()["data"]
        minilm = next(m for m in data if m["id"] == "minilm")
        assert minilm["downloaded"] is True
        other = next(m for m in data if m["id"] != "minilm")
        assert other["downloaded"] is False


def test_body_size_limit_returns_413():
    with TestClient(create_app(model_manager=FakeManager(), max_body_bytes=100)) as c:
        big = {"model": "m", "messages": [{"role": "user", "content": "x" * 500}]}
        assert c.post("/v1/chat/completions", json=big).status_code == 413
