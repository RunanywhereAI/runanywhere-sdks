"""A local, OpenAI-compatible inference server backed by the on-device RunAnywhere SDK.

Turns the on-device engine into a drop-in OpenAI API — 100% local, offline, no keys. Point any
OpenAI client (the `openai` Python lib, LangChain, LlamaIndex, curl) at http://localhost:8000/v1
and it works with no cloud.

Endpoints (a practical subset of the OpenAI API):
  GET  /v1/models                    list the built-in catalog models
  POST /v1/chat/completions          chat (streaming SSE + non-streaming)   -> LLM
  POST /v1/embeddings                text embeddings                        -> Embedder
  POST /v1/audio/transcriptions      Whisper-style speech-to-text (WAV)     -> STT
  POST /v1/audio/speech              text-to-speech (returns WAV)           -> TTS

The `model` field of each request is a RunAnywhere catalog id for that modality (see /v1/models),
e.g. chat -> "qwen2.5-0.5b", embeddings -> "minilm", transcriptions -> "whisper-tiny",
speech -> "piper-lessac". Models are downloaded on first use and cached.

Run:  uvicorn server:app --port 8000     (see README.md)
"""
from __future__ import annotations

import asyncio
import io
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Optional, Union

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse, Response, StreamingResponse
from pydantic import BaseModel

from runanywhere import CATALOG, RunAnywhere, SDKException
from runanywhere.audio import decode_wav, downsample, encode_wav, pcm16_bytes

# Per-modality defaults used when a request omits `model`.
DEFAULT_LLM = "qwen2.5-0.5b"
DEFAULT_EMBEDDER = "minilm"
DEFAULT_STT = "whisper-tiny"
DEFAULT_TTS = "piper-lessac"
STT_SAMPLE_RATE = 16000


class Models:
    """Lazily loads + caches one instance of each model, and serializes same-model calls.

    A loaded model backend is single-in-flight (the SDK raises on concurrent generation on the
    same instance), so we guard each cached model with an asyncio.Lock and hold it for the call.
    """

    def __init__(self) -> None:
        self.ra = RunAnywhere()
        self._cache: dict[tuple[str, str], object] = {}
        self._locks: dict[tuple[str, str], asyncio.Lock] = {}
        self._load_lock = asyncio.Lock()

    def start(self) -> None:
        self.ra.initialize()

    def stop(self) -> None:
        self.ra.shutdown()

    def backends(self) -> list[str]:
        return self.ra.available_backends()

    async def _get(self, kind: str, model_id: str, loader) -> tuple[object, asyncio.Lock]:
        key = (kind, model_id)
        if key not in self._cache:
            async with self._load_lock:
                if key not in self._cache:  # double-checked under the lock
                    # Loading is blocking (download on first use + native load); off-thread it.
                    self._cache[key] = await asyncio.to_thread(loader, model_id)
                    self._locks[key] = asyncio.Lock()
        return self._cache[key], self._locks[key]

    async def llm(self, model_id: str):
        return await self._get("llm", model_id, self.ra.load_llm)

    async def embedder(self, model_id: str):
        return await self._get("emb", model_id, self.ra.load_embedder)

    async def stt(self, model_id: str):
        return await self._get("stt", model_id, self.ra.load_stt)

    async def tts(self, model_id: str):
        return await self._get("tts", model_id, self.ra.load_tts)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.models = Models()
    app.state.models.start()
    try:
        yield
    finally:
        app.state.models.stop()


app = FastAPI(title="RunAnywhere OpenAI-compatible server", lifespan=lifespan)


def _models(request_app: FastAPI = None) -> Models:  # small accessor
    return app.state.models


# --------------------------------------------------------------------------- request schemas
class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    model: str = DEFAULT_LLM
    messages: list[ChatMessage]
    stream: bool = False
    max_tokens: Optional[int] = None
    temperature: Optional[float] = None
    top_p: Optional[float] = None


class EmbeddingsRequest(BaseModel):
    model: str = DEFAULT_EMBEDDER
    input: Union[str, list[str]]


class SpeechRequest(BaseModel):
    model: str = DEFAULT_TTS
    input: str
    voice: Optional[str] = None  # accepted for OpenAI-compat; the model id selects the voice
    response_format: str = "wav"


# --------------------------------------------------------------------------- helpers
def _gen_opts(req: ChatRequest) -> dict[str, Any]:
    opts: dict[str, Any] = {}
    if req.max_tokens is not None:
        opts["max_tokens"] = req.max_tokens
    if req.temperature is not None:
        opts["temperature"] = req.temperature
    if req.top_p is not None:
        opts["top_p"] = req.top_p
    return opts


def _build_prompt(messages: list[ChatMessage]) -> tuple[Optional[str], str]:
    """(system_prompt, prompt). A single user turn is passed verbatim so the backend applies the
    model's chat template cleanly; multi-turn is serialized into a simple transcript."""
    system = "\n".join(m.content for m in messages if m.role == "system") or None
    turns = [m for m in messages if m.role != "system"]
    if len(turns) == 1 and turns[0].role == "user":
        return system, turns[0].content
    lines = []
    for m in turns:
        who = "User" if m.role == "user" else "Assistant"
        lines.append(f"{who}: {m.content}")
    lines.append("Assistant:")
    return system, "\n".join(lines)


def _approx_tokens(text: str) -> int:
    return max(1, len(text) // 4)  # rough; the SDK backends don't expose exact counts here


def _chat_chunk(cid: str, model: str, delta: dict, finish: Optional[str]) -> str:
    payload = {
        "id": cid,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }
    import json

    return f"data: {json.dumps(payload)}\n\n"


# --------------------------------------------------------------------------- routes
@app.get("/")
async def root() -> dict:
    return {
        "service": "runanywhere-openai-server",
        "backends": _models().backends(),
        "models": sorted(CATALOG.keys()),
        "endpoints": [
            "/v1/models",
            "/v1/chat/completions",
            "/v1/embeddings",
            "/v1/audio/transcriptions",
            "/v1/audio/speech",
        ],
    }


@app.get("/v1/models")
async def list_models() -> dict:
    data = [
        {"id": mid, "object": "model", "created": 0, "owned_by": "runanywhere",
         "type": entry.type}
        for mid, entry in sorted(CATALOG.items())
    ]
    return {"object": "list", "data": data}


@app.post("/v1/chat/completions")
async def chat_completions(req: ChatRequest):
    llm, lock = await _models().llm(req.model)
    system, prompt = _build_prompt(req.messages)
    opts = _gen_opts(req)
    if system is not None:
        opts["system_prompt"] = system
    cid = f"chatcmpl-{uuid.uuid4().hex}"

    if req.stream:
        async def sse() -> AsyncIterator[str]:
            async with lock:
                yield _chat_chunk(cid, req.model, {"role": "assistant"}, None)
                try:
                    async for tok in llm.agenerate(prompt, **opts):
                        yield _chat_chunk(cid, req.model, {"content": tok}, None)
                except SDKException as exc:  # surface as a final error-ish stop
                    yield _chat_chunk(cid, req.model, {"content": f"\n[error: {exc}]"}, None)
                yield _chat_chunk(cid, req.model, {}, "stop")
                yield "data: [DONE]\n\n"

        return StreamingResponse(sse(), media_type="text/event-stream")

    async with lock:
        text = await llm.agenerate_text(prompt, **opts)
    prompt_tokens = _approx_tokens(prompt)
    completion_tokens = _approx_tokens(text)
    return {
        "id": cid,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": req.model,
        "choices": [
            {"index": 0, "message": {"role": "assistant", "content": text},
             "finish_reason": "stop"}
        ],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }


@app.post("/v1/embeddings")
async def embeddings(req: EmbeddingsRequest):
    embedder, lock = await _models().embedder(req.model)
    inputs = [req.input] if isinstance(req.input, str) else list(req.input)
    data = []
    total = 0
    async with lock:
        for i, text in enumerate(inputs):
            vec = await asyncio.to_thread(embedder.embed, text)
            data.append({"object": "embedding", "index": i, "embedding": [float(x) for x in vec]})
            total += _approx_tokens(text)
    return {
        "object": "list",
        "data": data,
        "model": req.model,
        "usage": {"prompt_tokens": total, "total_tokens": total},
    }


@app.post("/v1/audio/transcriptions")
async def transcriptions(
    file: UploadFile = File(...),
    model: str = Form(DEFAULT_STT),
):
    stt, lock = await _models().stt(model)
    raw = await file.read()
    try:
        sample_rate, samples = decode_wav(raw)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=400,
            detail=f"could not decode audio (send 16 kHz mono WAV): {exc}",
        )
    if sample_rate != STT_SAMPLE_RATE:
        samples = downsample(samples, sample_rate, STT_SAMPLE_RATE)
    pcm16 = pcm16_bytes(samples)
    async with lock:
        text = await stt.atranscribe(pcm16)
    return {"text": text}


@app.post("/v1/audio/speech")
async def speech(req: SpeechRequest):
    if req.response_format not in ("wav", "pcm"):
        raise HTTPException(status_code=400, detail="only response_format=wav is supported")
    tts, lock = await _models().tts(req.model)
    async with lock:
        synth = await tts.asynthesize(req.input)
    wav = encode_wav(synth.samples, synth.sample_rate)
    return Response(content=wav, media_type="audio/wav")


@app.exception_handler(SDKException)
async def sdk_error_handler(_request, exc: SDKException):  # -> OpenAI-ish error body
    return JSONResponse(
        status_code=400,
        content={"error": {"message": str(exc), "type": "runanywhere_error",
                           "code": int(getattr(exc, "code", 0) or 0)}},
    )
