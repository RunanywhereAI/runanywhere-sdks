"""Hermetic tests for the built-in OpenAI-compatible server (runanywhere.server).

Runs with NO native build and NO downloaded models: the SDK namespaces are replaced with fakes
and a fake manager is injected into ``create_app``, so the routes, SSE streaming, embeddings
encoding, tool-call shape, vision temp-file handling, error→HTTP mapping and api-key auth are
all genuinely exercised. Skipped entirely unless the ``[server]`` extra (fastapi) is installed.
"""
from __future__ import annotations

import asyncio
import base64
import json
import os

import numpy as np
import pytest

pytest.importorskip("fastapi")
from fastapi.testclient import TestClient  # noqa: E402

import runanywhere  # noqa: E402
from runanywhere.audio import decode_wav, encode_wav  # noqa: E402
from runanywhere.errors import SDKException  # noqa: E402
from runanywhere.events import GenerationEvent, GenerationEventKind  # noqa: E402
from runanywhere.inputs import AudioFormat  # noqa: E402
from runanywhere.options import ToolChoiceMode  # noqa: E402
from runanywhere.results import (  # noqa: E402
    Audio,
    Embedding,
    FinishReason,
    GenerationResult,
    ToolCall,
    Transcription,
)
from runanywhere.server import create_app  # noqa: E402


# --------------------------------------------------------------------------- namespace fakes
class FakeLlm:
    def __init__(
        self,
        tokens=("Hello", " world"),
        *,
        text=None,
        tool_call=None,
        raise_exc=None,
        raise_mid_stream=False,
    ) -> None:
        self._tokens = list(tokens)
        self._text = text
        self._tool_call = tool_call
        self._raise = raise_exc
        self._raise_mid = raise_mid_stream
        self.last_prompt = None
        self.last_options = None

    def _answer(self) -> str:
        return self._text if self._text is not None else "".join(self._tokens)

    def _tools_enabled(self, options) -> bool:
        return bool(
            options
            and options.tools
            and options.tool_choice.mode != ToolChoiceMode.NONE
        )

    async def agenerate(self, prompt, options=None):
        self.last_prompt, self.last_options = prompt, options
        if self._raise:
            raise self._raise
        if self._tool_call is not None and self._tools_enabled(options):
            return GenerationResult(
                tool_calls=[self._tool_call], finish_reason=FinishReason.TOOL_CALLS
            )
        return GenerationResult(text=self._answer(), output_tokens=len(self._tokens))

    async def agenerate_stream(self, prompt, options=None):
        self.last_prompt, self.last_options = prompt, options
        if self._raise and not self._raise_mid:
            raise self._raise
        yield GenerationEvent(kind=GenerationEventKind.STARTED, request_id="r")
        for index, token in enumerate(self._tokens):
            yield GenerationEvent(kind=GenerationEventKind.TOKEN, text=token)
            if self._raise_mid and index == 0:
                raise self._raise or SDKException.generation_failed("boom")
        yield GenerationEvent(
            kind=GenerationEventKind.COMPLETED, result=GenerationResult(text=self._answer())
        )


class FakeVlm:
    def __init__(self, tokens=("a", " cat"), *, text=None) -> None:
        self._tokens = list(tokens)
        self._text = text
        self.captured_path = None

    def _capture(self, image) -> None:
        self.captured_path = image.path
        assert os.path.exists(image.path)  # the route must have materialized the image

    async def agenerate(self, image, prompt, options=None):
        self._capture(image)
        return GenerationResult(text=self._text if self._text is not None else "".join(self._tokens))

    async def agenerate_stream(self, image, prompt, options=None):
        self._capture(image)
        yield GenerationEvent(kind=GenerationEventKind.STARTED)
        for token in self._tokens:
            yield GenerationEvent(kind=GenerationEventKind.TOKEN, text=token)
        yield GenerationEvent(
            kind=GenerationEventKind.COMPLETED, result=GenerationResult(text="".join(self._tokens))
        )


class FakeEmbeddings:
    def __init__(self, dimension=4, *, raise_exc=None) -> None:
        self._dimension = dimension
        self._raise = raise_exc

    async def aembed(self, texts, options=None):
        if self._raise:
            raise self._raise
        # input-dependent so a reorder / drop / dup regression is observable
        return [
            Embedding(index=i, vector=np.arange(self._dimension, dtype=np.float32) + float(len(t)))
            for i, t in enumerate(texts)
        ]


class FakeStt:
    def __init__(self, text="hello") -> None:
        self._text = text
        self.last_duration_ms = 0

    async def atranscribe(self, audio, options=None):
        self.last_duration_ms = audio.duration_ms()
        return Transcription(text=self._text, duration_ms=self.last_duration_ms)


class FakeTts:
    def __init__(self) -> None:
        self.last_options = None

    async def asynthesize(self, text, options=None):
        self.last_options = options
        return Audio(
            data=encode_wav(np.zeros(8, dtype=np.float32), 22050),
            sample_rate=22050,
            format=AudioFormat.WAV,
            duration_ms=1,
        )


class FakeManager:
    def __init__(self, *, downloaded=None) -> None:
        self.default_llm = "fake-llm"
        self.default_vlm = "fake-vlm"
        self.default_embedder = "fake-emb"
        self.default_stt = "fake-stt"
        self.default_tts = "fake-tts"
        self._downloaded = downloaded or set()
        self._locks: dict = {}

    def start(self) -> None:
        pass

    def stop(self) -> None:
        pass

    def backends(self) -> list:
        return ["fake"]

    def downloaded(self) -> set:
        return self._downloaded

    def lock(self, category: str):
        return self._locks.setdefault(category, asyncio.Lock())


class _Proxy:
    """Forwards attribute access to whatever fake the test currently installed."""

    def __init__(self, box: dict, key: str) -> None:
        self._box = box
        self._key = key

    def __getattr__(self, name):
        return getattr(self._box[self._key], name)


@pytest.fixture(autouse=True)
def namespaces(monkeypatch):
    """Swap the SDK namespaces for fakes; tests replace entries to change behaviour."""
    box = {
        "llm": FakeLlm(),
        "vlm": FakeVlm(),
        "embeddings": FakeEmbeddings(),
        "stt": FakeStt(),
        "tts": FakeTts(),
    }
    for key in box:
        monkeypatch.setattr(runanywhere, key, _Proxy(box, key))
    return box


def _client(manager=None, **kwargs):
    # Tests exercise routing with fake ids like "m", so allow arbitrary ids by default; the
    # catalog restriction has its own test.
    kwargs.setdefault("allow_arbitrary_models", True)
    return TestClient(create_app(model_manager=manager or FakeManager(), **kwargs))


def _sse_events(text: str) -> list:
    """Parse ``data: {json}`` lines from an SSE body (dropping the [DONE] sentinel)."""
    out = []
    for line in text.splitlines():
        if line.startswith("data: "):
            payload = line[len("data: ") :]
            if payload.strip() == "[DONE]":
                continue
            out.append(json.loads(payload))
    return out


# --------------------------------------------------------------------------- info
def test_health() -> None:
    with _client() as client:
        assert client.get("/health").json() == {"status": "ok"}


def test_root_reports_backends_and_endpoints() -> None:
    with _client() as client:
        body = client.get("/").json()
        assert body["service"] == "runanywhere-openai-server"
        assert body["backends"] == ["fake"]
        assert "/v1/chat/completions" in body["endpoints"]


def test_list_and_retrieve_models() -> None:
    with _client() as client:
        data = client.get("/v1/models").json()["data"]
        assert data and all({"id", "object", "type", "downloaded"} <= set(m) for m in data)
        first = data[0]["id"]
        assert client.get(f"/v1/models/{first}").json()["id"] == first
        assert client.get("/v1/models/does-not-exist-xyz").status_code == 404


def test_models_downloaded_flag_reflects_state() -> None:
    with _client(FakeManager(downloaded={"minilm"})) as client:
        data = client.get("/v1/models").json()["data"]
        assert next(m for m in data if m["id"] == "minilm")["downloaded"] is True
        assert next(m for m in data if m["id"] != "minilm")["downloaded"] is False


# --------------------------------------------------------------------------- chat
def test_chat_completions_non_stream() -> None:
    with _client() as client:
        body = client.post(
            "/v1/chat/completions",
            json={"model": "m", "messages": [{"role": "user", "content": "hi"}]},
        ).json()
        assert body["object"] == "chat.completion"
        assert body["choices"][0]["message"]["content"] == "Hello world"
        assert body["choices"][0]["finish_reason"] == "stop"
        assert body["usage"]["total_tokens"] >= 1


def test_chat_completions_stream() -> None:
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={"model": "m", "stream": True, "messages": [{"role": "user", "content": "hi"}]},
        )
        assert response.headers["content-type"].startswith("text/event-stream")
        events = _sse_events(response.text)
        assert events[0]["choices"][0]["delta"].get("role") == "assistant"
        content = "".join(e["choices"][0]["delta"].get("content", "") for e in events)
        assert content == "Hello world"
        assert events[-1]["choices"][0]["finish_reason"] == "stop"
        assert response.text.rstrip().endswith("data: [DONE]")


def test_chat_stream_mid_stream_error_is_terminal(namespaces) -> None:
    namespaces["llm"] = FakeLlm(
        raise_mid_stream=True, raise_exc=SDKException.generation_failed("kaboom")
    )
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={"model": "m", "stream": True, "messages": [{"role": "user", "content": "hi"}]},
        )
        assert response.status_code == 200  # headers already sent
        assert '"error"' in response.text
        assert response.text.rstrip().endswith("data: [DONE]")


def test_sampling_fields_reach_the_sdk_options(namespaces) -> None:
    with _client() as client:
        client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "hi"}],
                "max_tokens": 16,
                "temperature": 0.2,
                "top_p": 0.9,
                "stop": ["\nUser:"],
            },
        )
    options = namespaces["llm"].last_options
    assert options.max_output_tokens == 16 and options.temperature == 0.2
    assert options.top_p == 0.9 and options.stop_sequences == ["\nUser:"]


def test_system_prompt_is_forwarded(namespaces) -> None:
    with _client() as client:
        client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {"role": "system", "content": "be terse"},
                    {"role": "user", "content": "hi"},
                ],
            },
        )
    assert namespaces["llm"].last_options.system_prompt == "be terse"


def test_multi_turn_prompt_is_serialized_to_a_transcript(namespaces) -> None:
    with _client() as client:
        client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {"role": "user", "content": "hi"},
                    {"role": "assistant", "content": "hello"},
                    {"role": "user", "content": "bye"},
                ],
            },
        )
    prompt = namespaces["llm"].last_prompt
    assert "User: hi" in prompt and "Assistant: hello" in prompt


# --------------------------------------------------------------------------- completions
def test_completions_non_stream() -> None:
    with _client() as client:
        body = client.post("/v1/completions", json={"model": "m", "prompt": "once upon"}).json()
        assert body["object"] == "text_completion"
        assert body["choices"][0]["text"] == "Hello world"


def test_completions_stream() -> None:
    with _client() as client:
        response = client.post(
            "/v1/completions", json={"model": "m", "prompt": "x", "stream": True}
        )
        events = _sse_events(response.text)
        assert "".join(e["choices"][0]["text"] for e in events) == "Hello world"


def test_completions_stream_mid_stream_error_is_terminal(namespaces) -> None:
    namespaces["llm"] = FakeLlm(
        raise_mid_stream=True, raise_exc=SDKException.generation_failed("boom")
    )
    with _client() as client:
        response = client.post(
            "/v1/completions", json={"model": "m", "prompt": "x", "stream": True}
        )
        assert response.status_code == 200
        assert '"error"' in response.text and response.text.rstrip().endswith("data: [DONE]")


# --------------------------------------------------------------------------- embeddings
def test_embeddings_float() -> None:
    with _client() as client:
        body = client.post("/v1/embeddings", json={"model": "m", "input": "a"}).json()
        assert len(body["data"]) == 1
        assert body["data"][0]["embedding"] == [1.0, 2.0, 3.0, 4.0]  # arange(4) + len("a")


def test_embeddings_multi_input_preserves_order_and_index() -> None:
    with _client() as client:
        body = client.post("/v1/embeddings", json={"model": "m", "input": ["a", "bb", "ccc"]}).json()
        assert [d["index"] for d in body["data"]] == [0, 1, 2]
        assert [d["embedding"][0] for d in body["data"]] == [1.0, 2.0, 3.0]


def test_embeddings_base64() -> None:
    with _client() as client:
        body = client.post(
            "/v1/embeddings", json={"model": "m", "input": "a", "encoding_format": "base64"}
        ).json()
        raw = base64.b64decode(body["data"][0]["embedding"])
        assert np.frombuffer(raw, dtype="<f4").tolist() == [1.0, 2.0, 3.0, 4.0]


# --------------------------------------------------------------------------- audio
def test_transcriptions_round_trip() -> None:
    wav = encode_wav(np.zeros(16000, dtype=np.float32), 16000)
    with _client() as client:
        response = client.post(
            "/v1/audio/transcriptions",
            files={"file": ("a.wav", wav, "audio/wav")},
            data={"model": "whisper"},
        )
        assert response.json() == {"text": "hello"}


def test_transcriptions_accepts_non_16k_audio(namespaces) -> None:
    wav = encode_wav(np.zeros(48000, dtype=np.float32), 48000)
    with _client() as client:
        response = client.post(
            "/v1/audio/transcriptions",
            files={"file": ("a.wav", wav, "audio/wav")},
            data={"model": "whisper"},
        )
        assert response.json() == {"text": "hello"}
    assert namespaces["stt"].last_duration_ms == 1000  # one second, resampled to 16 kHz


def test_transcriptions_bad_audio_is_400() -> None:
    with _client() as client:
        response = client.post(
            "/v1/audio/transcriptions", files={"file": ("a.wav", b"not a wav", "audio/wav")}
        )
        assert response.status_code == 400


def test_speech_returns_wav() -> None:
    with _client() as client:
        response = client.post("/v1/audio/speech", json={"model": "tts", "input": "hello"})
        assert response.headers["content-type"] == "audio/wav"
        rate, samples = decode_wav(response.content)
        assert rate == 22050 and samples.shape[0] == 8


def test_speech_requests_wav_from_the_sdk(namespaces) -> None:
    with _client() as client:
        client.post("/v1/audio/speech", json={"model": "tts", "input": "hi", "voice": "amy"})
    options = namespaces["tts"].last_options
    assert options.format == AudioFormat.WAV and options.voice == "amy"


def test_speech_pcm_is_rejected() -> None:
    with _client() as client:
        response = client.post(
            "/v1/audio/speech", json={"model": "m", "input": "hi", "response_format": "pcm"}
        )
        assert response.status_code == 400


# --------------------------------------------------------------------------- tools
_TOOLS = [{"type": "function", "function": {"name": "get_weather", "parameters": {"type": "object"}}}]


def test_tools_required_returns_tool_calls(namespaces) -> None:
    namespaces["llm"] = FakeLlm(tool_call=ToolCall(name="get_weather", arguments={"city": "Paris"}))
    with _client() as client:
        body = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "weather in Paris?"}],
                "tools": _TOOLS,
                "tool_choice": "required",
            },
        ).json()
        message = body["choices"][0]["message"]
        assert body["choices"][0]["finish_reason"] == "tool_calls"
        assert message["tool_calls"][0]["function"]["name"] == "get_weather"
        assert json.loads(message["tool_calls"][0]["function"]["arguments"]) == {"city": "Paris"}
    assert namespaces["llm"].last_options.tool_choice.mode == ToolChoiceMode.REQUIRED


def test_tools_auto_falls_back_to_content(namespaces) -> None:
    namespaces["llm"] = FakeLlm(text="It is sunny.")
    with _client() as client:
        body = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "weather?"}],
                "tools": _TOOLS,
            },
        ).json()
        assert body["choices"][0]["finish_reason"] == "stop"
        assert body["choices"][0]["message"]["content"] == "It is sunny."
    assert namespaces["llm"].last_options.tool_choice.mode == ToolChoiceMode.AUTO


def test_tool_choice_none_ignores_tools(namespaces) -> None:
    with _client() as client:
        body = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "hi"}],
                "tools": _TOOLS,
                "tool_choice": "none",
            },
        ).json()
        assert body["choices"][0]["message"]["content"] == "Hello world"


def test_tool_choice_named_unknown_is_400() -> None:
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "hi"}],
                "tools": _TOOLS,
                "tool_choice": {"type": "function", "function": {"name": "nonexistent"}},
            },
        )
        assert response.status_code == 400


def test_tool_choice_named_known_forces_that_tool(namespaces) -> None:
    namespaces["llm"] = FakeLlm(tool_call=ToolCall(name="get_weather", arguments={"a": 1}))
    with _client() as client:
        body = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "hi"}],
                "tools": _TOOLS,
                "tool_choice": {"type": "function", "function": {"name": "get_weather"}},
            },
        ).json()
        assert body["choices"][0]["message"]["tool_calls"][0]["function"]["name"] == "get_weather"
    assert namespaces["llm"].last_options.tool_choice.name == "get_weather"


def test_streamed_tool_calls_carry_index(namespaces) -> None:
    namespaces["llm"] = FakeLlm(tool_call=ToolCall(name="get_weather", arguments={"city": "Paris"}))
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "stream": True,
                "messages": [{"role": "user", "content": "weather?"}],
                "tools": _TOOLS,
                "tool_choice": "required",
            },
        )
        events = _sse_events(response.text)
        deltas = [e for e in events if e["choices"][0]["delta"].get("tool_calls")]
        assert deltas, "expected a tool_calls delta"
        call = deltas[0]["choices"][0]["delta"]["tool_calls"][0]
        assert call["index"] == 0  # required by openai-python / LangChain accumulation
        assert call["function"]["name"] == "get_weather"
        assert events[-1]["choices"][0]["finish_reason"] == "tool_calls"


# --------------------------------------------------------------------------- vision
def test_vision_data_uri_routes_to_the_vlm(namespaces) -> None:
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n fake bytes").decode()
    namespaces["vlm"] = FakeVlm(text="a cat on a mat")
    with _client() as client:
        body = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": "what is this?"},
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}"}},
                        ],
                    }
                ],
            },
        ).json()
        assert body["choices"][0]["message"]["content"] == "a cat on a mat"


def test_vision_streaming(namespaces) -> None:
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n x").decode()
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "stream": True,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": "what?"},
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}"}},
                        ],
                    }
                ],
            },
        )
        content = "".join(
            e["choices"][0]["delta"].get("content", "") for e in _sse_events(response.text)
        )
        assert content == "a cat"


def test_vision_temp_file_is_cleaned_up(namespaces) -> None:
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n x").decode()
    vlm = FakeVlm(text="ok")
    namespaces["vlm"] = vlm
    with _client() as client:
        client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}"}}
                        ],
                    }
                ],
            },
        )
    assert vlm.captured_path is not None
    assert not os.path.exists(vlm.captured_path)  # temp image removed after the request


@pytest.mark.parametrize("url", ["/etc/passwd", "C:\\Windows\\win.ini", "file:///etc/shadow"])
def test_vision_rejects_local_paths(url) -> None:
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {"role": "user", "content": [{"type": "image_url", "image_url": {"url": url}}]}
                ],
            },
        )
        assert response.status_code == 400  # arbitrary-file-read guard


@pytest.mark.parametrize("url", ["http://127.0.0.1/x", "http://169.254.169.254/latest/meta-data"])
def test_vision_rejects_ssrf_targets(url) -> None:
    with _client(allow_image_urls=True) as client:
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {"role": "user", "content": [{"type": "image_url", "image_url": {"url": url}}]}
                ],
            },
        )
        assert response.status_code == 400  # SSRF guard (loopback / link-local)


def test_image_urls_disabled_by_default() -> None:
    with _client() as client:  # allow_image_urls defaults False
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"type": "image_url", "image_url": {"url": "http://example.com/x.png"}}
                        ],
                    }
                ],
            },
        )
        assert response.status_code == 400  # URL fetch is opt-in


# --------------------------------------------------------------------------- structured output
def test_response_format_json_schema_sets_structured_output(namespaces) -> None:
    namespaces["llm"] = FakeLlm(text='{"x": 1}')
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "give json"}],
                "response_format": {
                    "type": "json_schema",
                    "json_schema": {
                        "schema": {"type": "object", "properties": {"x": {"type": "integer"}}}
                    },
                },
            },
        )
        assert response.status_code == 200
        assert response.json()["choices"][0]["message"]["content"] == '{"x": 1}'
    structured = namespaces["llm"].last_options.structured_output
    assert structured is not None and structured.schema["type"] == "object"


def test_response_format_json_object_adds_a_system_hint(namespaces) -> None:
    namespaces["llm"] = FakeLlm(text="{}")
    with _client() as client:
        client.post(
            "/v1/chat/completions",
            json={
                "model": "m",
                "messages": [{"role": "user", "content": "give json"}],
                "response_format": {"type": "json_object"},
            },
        )
    assert "JSON" in (namespaces["llm"].last_options.system_prompt or "")


# --------------------------------------------------------------------------- error mapping
@pytest.mark.parametrize(
    "exc,status",
    [
        (SDKException.model_not_found("x"), 404),
        (SDKException.invalid_state("busy"), 409),
        (SDKException.not_initialized("engine"), 503),
        (SDKException.invalid_input("bad"), 400),
        (SDKException.generation_failed("oops"), 500),
    ],
)
def test_error_code_maps_to_http_status(namespaces, exc, status) -> None:
    namespaces["llm"] = FakeLlm(raise_exc=exc)
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={"model": "m", "messages": [{"role": "user", "content": "hi"}]},
        )
        assert response.status_code == status
        assert response.json()["error"]["message"]


def test_unexpected_error_is_a_generic_500(namespaces) -> None:
    namespaces["embeddings"] = FakeEmbeddings(raise_exc=ValueError("internal path /secret/thing"))
    app = create_app(model_manager=FakeManager(), allow_arbitrary_models=True)
    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.post("/v1/embeddings", json={"model": "m", "input": "a"})
        assert response.status_code == 500
        assert response.json()["error"]["message"] == "internal server error"


def test_malformed_request_is_an_openai_400() -> None:
    with _client() as client:
        response = client.post("/v1/chat/completions", json={"model": "m"})  # no 'messages'
        assert response.status_code == 400
        assert response.json()["error"]["type"] == "invalid_request_error"


def test_raw_http_exceptions_use_the_openai_envelope() -> None:
    with _client(api_key="secret") as client:
        unauthorized = client.post(
            "/v1/chat/completions",
            json={"model": "m", "messages": [{"role": "user", "content": "hi"}]},
        )
        assert unauthorized.status_code == 401
        assert "error" in unauthorized.json() and "detail" not in unauthorized.json()
    with _client() as client:
        missing = client.get("/v1/models/nope-not-a-model")
        assert missing.status_code == 404
        assert missing.json()["error"]["type"] == "invalid_request_error"
        bad_audio = client.post(
            "/v1/audio/transcriptions", files={"file": ("a.wav", b"not wav", "audio/wav")}
        )
        assert bad_audio.status_code == 400 and "error" in bad_audio.json()


# --------------------------------------------------------------------------- auth
def test_api_key_required_when_configured() -> None:
    with _client(api_key="secret") as client:
        body = {"model": "m", "messages": [{"role": "user", "content": "hi"}]}
        assert client.post("/v1/chat/completions", json=body).status_code == 401
        assert (
            client.post(
                "/v1/chat/completions", json=body, headers={"Authorization": "Bearer wrong"}
            ).status_code
            == 401
        )
        assert (
            client.post(
                "/v1/chat/completions", json=body, headers={"Authorization": "Bearer secret"}
            ).status_code
            == 200
        )
        assert client.get("/health").status_code == 200


@pytest.mark.parametrize(
    "method,path,json_body",
    [
        ("get", "/", None),
        ("get", "/v1/models", None),
        ("get", "/v1/models/minilm", None),
        ("post", "/v1/chat/completions", {"messages": [{"role": "user", "content": "hi"}]}),
        ("post", "/v1/completions", {"prompt": "x"}),
        ("post", "/v1/embeddings", {"input": "a"}),
        ("post", "/v1/audio/speech", {"input": "hi"}),
    ],
)
def test_api_key_guards_every_v1_route_and_root(method, path, json_body) -> None:
    with _client(api_key="secret") as client:
        assert client.request(method, path, json=json_body).status_code == 401
        allowed = client.request(
            method, path, json=json_body, headers={"Authorization": "Bearer secret"}
        )
        assert allowed.status_code == 200


def test_api_key_non_ascii_header_is_401_not_500() -> None:
    app = create_app(model_manager=FakeManager(), api_key="secret", allow_arbitrary_models=True)
    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.post(
            "/v1/chat/completions",
            json={"model": "m", "messages": [{"role": "user", "content": "hi"}]},
            headers=[(b"authorization", b"Bearer \xff")],
        )
        assert response.status_code == 401


# --------------------------------------------------------------------------- limits and guards
def test_body_size_limit_returns_413() -> None:
    app = create_app(
        model_manager=FakeManager(), max_body_bytes=100, allow_arbitrary_models=True
    )
    with TestClient(app) as client:
        big = {"model": "m", "messages": [{"role": "user", "content": "x" * 500}]}
        assert client.post("/v1/chat/completions", json=big).status_code == 413


def test_empty_messages_is_400() -> None:
    with _client() as client:
        assert (
            client.post("/v1/chat/completions", json={"model": "m", "messages": []}).status_code
            == 400
        )


@pytest.mark.parametrize("value", [[], ""])
def test_empty_embeddings_input_is_400(value) -> None:
    with _client() as client:
        assert client.post("/v1/embeddings", json={"model": "m", "input": value}).status_code == 400


def test_max_tokens_zero_is_400() -> None:
    with _client() as client:
        response = client.post(
            "/v1/chat/completions",
            json={"model": "m", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 0},
        )
        assert response.status_code == 400
        assert response.json()["error"]["type"] == "invalid_request_error"


def test_catalog_restriction_rejects_an_unknown_model() -> None:
    with TestClient(create_app(model_manager=FakeManager())) as client:
        assert (
            client.post(
                "/v1/chat/completions",
                json={"model": "not-a-real-model", "messages": [{"role": "user", "content": "hi"}]},
            ).status_code
            == 404
        )
        assert (
            client.post(
                "/v1/chat/completions",
                json={"model": "qwen2.5-0.5b", "messages": [{"role": "user", "content": "hi"}]},
            ).status_code
            == 200
        )
