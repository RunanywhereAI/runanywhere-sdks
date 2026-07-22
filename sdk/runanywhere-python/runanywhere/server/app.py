"""The FastAPI app: OpenAI-compatible routes over the RunAnywhere SDK (needs the [server] extra).

``create_app(model_manager=None)`` is the injectable factory (pass a fake manager in tests). Routes
resolve the live manager via the ``get_manager`` dependency, so tests can also use
``app.dependency_overrides``. Streaming iterates the SDK's already-threaded ``agenerate`` directly
(no extra thread); blocking calls (``embed``) are off-loaded with ``asyncio.to_thread``.
"""
from __future__ import annotations

import asyncio
import base64
import hmac
import ipaddress
import json
import os
import socket
import tempfile
import time
import urllib.parse
import urllib.request
import uuid
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, Optional

import numpy as np
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse, Response, StreamingResponse

from ..audio import decode_wav, downsample, encode_wav, pcm16_bytes
from ..catalog import CATALOG
from ..errors import SDKException
from ..grammar import json_schema_to_grammar
from ..structured import ToolCall, ToolSpec
from .errors import http_status_for, install_error_handlers, openai_error_body
from .manager import ModelManager
from .schemas import ChatMessage, ChatRequest, CompletionRequest, EmbeddingsRequest, SpeechRequest

STT_SAMPLE_RATE = 16000
_DONE = "data: [DONE]\n\n"
MAX_IMAGE_BYTES = 20 * 1024 * 1024  # cap decoded/fetched image bytes (DoS guard)
DEFAULT_MAX_BODY_BYTES = 50 * 1024 * 1024  # reject larger request bodies with 413


def get_manager(request: Request) -> ModelManager:
    """FastAPI dependency: the live model manager (set in the lifespan / create_app)."""
    return request.app.state.manager


# --------------------------------------------------------------------------- generic helpers
def _approx_tokens(text: str) -> int:
    return max(1, len(text) // 4)  # rough; the SDK backends don't surface exact counts here


def _gen_opts(req: Any) -> dict[str, Any]:
    """Whitelist the generation controls the SDK honours (unknown keys are dropped by it)."""
    opts: dict[str, Any] = {}
    max_tokens = getattr(req, "max_completion_tokens", None) or getattr(req, "max_tokens", None)
    if max_tokens is not None:
        opts["max_tokens"] = max_tokens
    if getattr(req, "temperature", None) is not None:
        opts["temperature"] = req.temperature
    if getattr(req, "top_p", None) is not None:
        opts["top_p"] = req.top_p
    if getattr(req, "top_k", None) is not None:
        opts["top_k"] = req.top_k
    return opts


def _message_text(content: Any) -> str:
    """The text of a message whose ``content`` is a string or a list of OpenAI parts."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts = []
    for p in content:
        if isinstance(p, dict) and p.get("type") == "text":
            parts.append(p.get("text", ""))
        elif isinstance(p, str):
            parts.append(p)
    return "\n".join(x for x in parts if x)


def _build_prompt(messages: list[ChatMessage]) -> tuple[Optional[str], str]:
    """(system, prompt). A single user turn is passed verbatim (the backend applies the model's
    chat template); multi-turn is serialized into a simple transcript."""
    system = "\n".join(_message_text(m.content) for m in messages if m.role == "system") or None
    turns = [m for m in messages if m.role != "system"]
    if len(turns) == 1 and turns[0].role == "user":
        return system, _message_text(turns[0].content)
    lines = []
    for m in turns:
        who = "User" if m.role == "user" else "Assistant"
        lines.append(f"{who}: {_message_text(m.content)}")
    lines.append("Assistant:")
    return system, "\n".join(lines)


def _last_user_text(messages: list[ChatMessage]) -> str:
    for m in reversed(messages):
        if m.role == "user":
            return _message_text(m.content)
    return ""


def _chat_chunk(cid: str, model: str, delta: dict, finish: Optional[str]) -> str:
    payload = {
        "id": cid,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }
    return f"data: {json.dumps(payload)}\n\n"


def _error_line(exc: Exception) -> str:
    """A terminal SSE ``data:`` error line (any non-SDK exception is coerced to one)."""
    e = exc if isinstance(exc, SDKException) else SDKException.generation_failed(str(exc))
    body = openai_error_body(e.message, http_status_for(e), code=int(e.code))
    return f"data: {json.dumps(body)}\n\n"


def _chat_completion(
    cid: str, model: str, message: dict, finish: str, prompt: str, completion: str
) -> dict:
    pt, ct = _approx_tokens(prompt), _approx_tokens(completion)
    return {
        "id": cid,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "message": message, "finish_reason": finish}],
        "usage": {"prompt_tokens": pt, "completion_tokens": ct, "total_tokens": pt + ct},
    }


# --------------------------------------------------------------------------- structured output
def _apply_response_format(rf: Optional[dict], opts: dict[str, Any]) -> Optional[str]:
    """For ``json_schema`` set a GBNF grammar on ``opts``; for ``json_object`` return a system
    hint. Returns None otherwise."""
    if not rf:
        return None
    rf_type = rf.get("type")
    if rf_type == "json_schema":
        schema = (rf.get("json_schema") or {}).get("schema")
        if schema:
            opts["grammar"] = json_schema_to_grammar(schema)
        return None
    if rf_type == "json_object":
        return "You must respond with a single valid JSON object."
    return None


# --------------------------------------------------------------------------- tool calling
def _tools_to_specs(tools: Optional[list[dict]]) -> list[ToolSpec]:
    specs = []
    for t in tools or []:
        fn = t.get("function") if isinstance(t, dict) else None
        fn = fn if isinstance(fn, dict) else (t if isinstance(t, dict) else {})
        name = fn.get("name")
        if not name:
            continue
        specs.append(
            ToolSpec(
                name=name,
                parameters=fn.get("parameters") or {"type": "object"},
                description=fn.get("description"),
            )
        )
    return specs


def _tool_choice_mode(tool_choice: Any) -> tuple[str, Optional[str]]:
    """(mode, named) where mode is none|auto|required|named."""
    if tool_choice is None:
        return "auto", None
    if isinstance(tool_choice, str):
        return (tool_choice if tool_choice in ("none", "auto", "required") else "auto"), None
    if isinstance(tool_choice, dict):
        return "named", (tool_choice.get("function") or {}).get("name")
    return "auto", None


def _tool_calls_message(tc: ToolCall) -> dict:
    return {
        "role": "assistant",
        "content": None,
        "tool_calls": [
            {
                "id": f"call_{uuid.uuid4().hex[:24]}",
                "type": "function",
                "function": {"name": tc.name, "arguments": json.dumps(tc.arguments)},
            }
        ],
    }


def _auto_tool_prompt(prompt: str, specs: list[ToolSpec]) -> str:
    doc = "\n".join(
        f"- {s.name}: {s.description or ''} (arguments: {json.dumps(s.parameters)})" for s in specs
    )
    return (
        f"{prompt}\n\nYou may call one of these tools if it helps answer:\n{doc}\n\n"
        'If a tool is needed, reply with ONLY a JSON object {"name": <tool>, "arguments": {...}} '
        "and nothing else. Otherwise, answer the user normally."
    )


def _try_parse_tool_call(text: str, names: set[str]) -> Optional[ToolCall]:
    """Best-effort: pull a ``{name, arguments}`` object out of a free-form 'auto' reply."""
    s = text.strip()
    if s.startswith("```"):
        s = s.strip("`")
        if s.lstrip().lower().startswith("json"):
            s = s.lstrip()[4:]
    start, end = s.find("{"), s.rfind("}")
    if start == -1 or end == -1 or end < start:
        return None
    try:
        obj = json.loads(s[start : end + 1])
    except (ValueError, TypeError):
        return None
    if not isinstance(obj, dict):
        return None
    name = obj.get("name")
    if not isinstance(name, str) or name not in names:
        return None
    args = obj.get("arguments")
    return ToolCall(name=name, arguments=args if isinstance(args, dict) else {})


# --------------------------------------------------------------------------- vision (image input)
def _last_user_image(messages: list[ChatMessage]) -> Optional[str]:
    for m in reversed(messages):
        if m.role == "user" and isinstance(m.content, list):
            for p in m.content:
                if isinstance(p, dict) and p.get("type") == "image_url":
                    iu = p.get("image_url")
                    if isinstance(iu, dict):
                        return iu.get("url")
                    if isinstance(iu, str):
                        return iu
    return None


def _img_suffix(header: str) -> str:
    h = header.lower()
    if "png" in h:
        return ".png"
    if "webp" in h:
        return ".webp"
    if "gif" in h:
        return ".gif"
    return ".jpg"


def _reject_ssrf(url: str) -> None:
    """Reject an image URL whose host resolves to a private/loopback/link-local/reserved
    address — a network request must not be usable to reach internal services or cloud
    metadata (SSRF)."""
    host = urllib.parse.urlparse(url).hostname
    if not host:
        raise SDKException.invalid_input("invalid image URL")
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError as exc:
        raise SDKException.invalid_input(f"could not resolve image host: {exc}")
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved
                or ip.is_multicast or ip.is_unspecified):
            raise SDKException.invalid_input("image URL host is not allowed")


def _materialize_image(ref: str) -> tuple[str, bool]:
    """Return ``(temp_path, True)`` for a data-URI or http(s) image. Blocking (base64 decode /
    network fetch / file write) — call it via ``asyncio.to_thread``. Local filesystem paths are
    NOT accepted from a network request (arbitrary-file-read guard); size is capped (DoS guard);
    URLs are SSRF-filtered. Raises ``SDKException.invalid_input`` (-> HTTP 400) on any rejection."""
    if ref.startswith("data:"):
        header, _, data = ref.partition(",")
        try:
            raw = base64.b64decode(data) if ";base64" in header else urllib.parse.unquote_to_bytes(data)
        except Exception as exc:  # noqa: BLE001
            raise SDKException.invalid_input(f"could not decode data-URI image: {exc}")
        if len(raw) > MAX_IMAGE_BYTES:
            raise SDKException.invalid_input("image exceeds the size limit")
        fd, path = tempfile.mkstemp(suffix=_img_suffix(header))
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
        return path, True
    if ref.startswith("http://") or ref.startswith("https://"):
        _reject_ssrf(ref)
        try:
            with urllib.request.urlopen(ref, timeout=10) as r:  # noqa: S310 — SSRF-filtered above
                raw = r.read(MAX_IMAGE_BYTES + 1)
        except SDKException:
            raise
        except Exception as exc:  # noqa: BLE001
            raise SDKException.invalid_input(f"could not fetch image URL: {exc}")
        if len(raw) > MAX_IMAGE_BYTES:
            raise SDKException.invalid_input("image exceeds the size limit")
        fd, path = tempfile.mkstemp(suffix=".img")
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
        return path, True
    # Neither a data: URI nor an http(s) URL: do NOT treat network input as a local file path.
    raise SDKException.invalid_input("image_url must be a data: URI or an http(s) URL")


def _pick_vlm(req_model: Optional[str], default_vlm: str) -> str:
    """A known VLM id or an unknown (custom-path) id is trusted; a known non-VLM id falls back."""
    if req_model:
        entry = CATALOG.get(req_model)
        if entry is None or entry.type == "vlm":
            return req_model
    return default_vlm


def _safe_unlink(path: str) -> None:
    try:
        os.unlink(path)
    except OSError:
        pass


def _encode_embedding(vec: Any, encoding_format: str) -> Any:
    arr = np.asarray(vec, dtype=np.float32)
    if encoding_format == "base64":
        return base64.b64encode(arr.astype("<f4").tobytes()).decode("ascii")
    return [float(x) for x in arr]


# --------------------------------------------------------------------------- SSE generators
async def _chat_text_sse(agen_factory, lock, cid: str, model: str) -> AsyncIterator[str]:
    """Stream chat deltas from an async token iterator factory, holding the model lock."""
    async with lock:
        yield _chat_chunk(cid, model, {"role": "assistant", "content": ""}, None)
        try:
            async for tok in agen_factory():
                yield _chat_chunk(cid, model, {"content": tok}, None)
        except Exception as exc:  # noqa: BLE001 — headers already sent (200); emit a terminal line
            yield _error_line(exc)
            yield _DONE
            return
        yield _chat_chunk(cid, model, {}, "stop")
        yield _DONE


async def _final_sse(cid: str, model: str, message: dict, finish: str) -> AsyncIterator[str]:
    """Emit a pre-computed (buffered) chat message as a short SSE stream."""
    yield _chat_chunk(cid, model, {"role": "assistant", "content": ""}, None)
    if message.get("tool_calls"):
        # OpenAI streamed tool-call deltas MUST carry an `index` so clients can accumulate them.
        deltas = [{**tc, "index": i} for i, tc in enumerate(message["tool_calls"])]
        yield _chat_chunk(cid, model, {"tool_calls": deltas}, None)
    elif message.get("content"):
        yield _chat_chunk(cid, model, {"content": message["content"]}, None)
    yield _chat_chunk(cid, model, {}, finish)
    yield _DONE


async def _completions_sse(agen_factory, lock, cid: str, model: str) -> AsyncIterator[str]:
    async with lock:
        try:
            async for tok in agen_factory():
                payload = {
                    "id": cid, "object": "text_completion", "created": int(time.time()),
                    "model": model,
                    "choices": [{"index": 0, "text": tok, "finish_reason": None, "logprobs": None}],
                }
                yield f"data: {json.dumps(payload)}\n\n"
        except Exception as exc:  # noqa: BLE001
            yield _error_line(exc)
            yield _DONE
            return
        final = {
            "id": cid, "object": "text_completion", "created": int(time.time()), "model": model,
            "choices": [{"index": 0, "text": "", "finish_reason": "stop", "logprobs": None}],
        }
        yield f"data: {json.dumps(final)}\n\n"
        yield _DONE


# --------------------------------------------------------------------------- app factory
def create_app(
    model_manager: Optional[ModelManager] = None,
    *,
    api_key: Optional[str] = None,
    default_llm: Optional[str] = None,
    default_vlm: Optional[str] = None,
    default_embedder: Optional[str] = None,
    default_stt: Optional[str] = None,
    default_tts: Optional[str] = None,
    max_body_bytes: int = DEFAULT_MAX_BODY_BYTES,
) -> FastAPI:
    """Build the FastAPI app. Pass ``model_manager`` to inject a (fake) manager for tests; else a
    real one is built in the lifespan so importing/creating the app never touches native code."""

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        mgr = getattr(app.state, "manager", None) or model_manager
        if mgr is None:
            overrides = {
                k: v
                for k, v in {
                    "default_llm": default_llm, "default_vlm": default_vlm,
                    "default_embedder": default_embedder, "default_stt": default_stt,
                    "default_tts": default_tts,
                }.items()
                if v is not None
            }
            mgr = ModelManager(**overrides)
        app.state.manager = mgr
        mgr.start()
        try:
            yield
        finally:
            mgr.stop()

    app = FastAPI(title="RunAnywhere OpenAI-compatible server", lifespan=lifespan)
    if model_manager is not None:
        app.state.manager = model_manager
    install_error_handlers(app)

    @app.middleware("http")
    async def _limit_body_size(request: Request, call_next):
        cl = request.headers.get("content-length")
        if cl and cl.isdigit() and int(cl) > max_body_bytes:
            return JSONResponse(
                status_code=413,
                content=openai_error_body("request body too large", 413),
            )
        return await call_next(request)

    async def require_api_key(authorization: Optional[str] = Header(default=None)) -> None:
        if api_key is None:
            return
        # Constant-time compare so the Bearer token isn't a timing side channel.
        if authorization is None or not hmac.compare_digest(authorization, f"Bearer {api_key}"):
            raise HTTPException(status_code=401, detail="Invalid API key")

    guarded = [Depends(require_api_key)]

    # -- info ---------------------------------------------------------------
    @app.get("/health")
    async def health() -> dict:
        return {"status": "ok"}

    @app.get("/", dependencies=guarded)
    async def root(mgr: ModelManager = Depends(get_manager)) -> dict:
        return {
            "service": "runanywhere-openai-server",
            "backends": mgr.backends(),
            "models": sorted(CATALOG.keys()),
            "endpoints": [
                "/health", "/v1/models", "/v1/chat/completions", "/v1/completions",
                "/v1/embeddings", "/v1/audio/transcriptions", "/v1/audio/speech",
            ],
        }

    # -- models -------------------------------------------------------------
    def _model_obj(mid: str, entry, status: dict) -> dict:
        st = status.get(mid)
        return {
            "id": mid, "object": "model", "created": 0, "owned_by": "runanywhere",
            "type": entry.type, "downloaded": bool(getattr(st, "downloaded", False)),
        }

    @app.get("/v1/models", dependencies=guarded)
    async def list_models(mgr: ModelManager = Depends(get_manager)) -> dict:
        status = mgr.model_status()
        return {"object": "list", "data": [_model_obj(m, e, status) for m, e in sorted(CATALOG.items())]}

    @app.get("/v1/models/{model_id}", dependencies=guarded)
    async def retrieve_model(model_id: str, mgr: ModelManager = Depends(get_manager)) -> dict:
        entry = CATALOG.get(model_id)
        if entry is None:
            raise HTTPException(status_code=404, detail=f"model {model_id!r} not found")
        return _model_obj(model_id, entry, mgr.model_status())

    # -- chat ---------------------------------------------------------------
    @app.post("/v1/chat/completions", dependencies=guarded)
    async def chat_completions(req: ChatRequest, mgr: ModelManager = Depends(get_manager)):
        cid = f"chatcmpl-{uuid.uuid4().hex}"
        image_ref = _last_user_image(req.messages)
        if image_ref is not None:
            return await _handle_vision(mgr, req, image_ref, cid)

        system, prompt = _build_prompt(req.messages)
        opts = _gen_opts(req)
        hint = _apply_response_format(req.response_format, opts)
        system = "\n".join(x for x in (system, hint) if x) or None
        if system:
            opts["system_prompt"] = system

        model = req.model or mgr.default_llm
        llm, lock = await mgr.llm(model)

        specs = _tools_to_specs(req.tools)
        mode, named = _tool_choice_mode(req.tool_choice)
        if specs and mode != "none":
            return await _handle_tools(llm, lock, prompt, specs, mode, named, opts, req, cid, model)

        if req.stream:
            gen = lambda: llm.agenerate(prompt, **opts)  # noqa: E731
            return StreamingResponse(
                _chat_text_sse(gen, lock, cid, model), media_type="text/event-stream"
            )
        async with lock:
            text = await llm.agenerate_text(prompt, **opts)
        return _chat_completion(cid, model, {"role": "assistant", "content": text}, "stop", prompt, text)

    async def _handle_tools(llm, lock, prompt, specs, mode, named, opts, req, cid, model):
        if mode in ("required", "named"):
            use = [s for s in specs if s.name == named] if mode == "named" else specs
            if not use:
                raise SDKException.invalid_input(f"tool_choice named an unknown tool: {named!r}")
            async with lock:
                tc = await llm.agenerate_tool_call(prompt, use, **opts)
            message, finish, completion = _tool_calls_message(tc), "tool_calls", json.dumps(tc.arguments)
        else:  # auto: let the model decide; parse the free-form reply
            async with lock:
                text = await llm.agenerate_text(_auto_tool_prompt(prompt, specs), **opts)
            tc = _try_parse_tool_call(text, {s.name for s in specs})
            if tc is not None:
                message, finish, completion = _tool_calls_message(tc), "tool_calls", json.dumps(tc.arguments)
            else:
                message, finish, completion = {"role": "assistant", "content": text}, "stop", text
        if req.stream:
            return StreamingResponse(
                _final_sse(cid, model, message, finish), media_type="text/event-stream"
            )
        return _chat_completion(cid, model, message, finish, prompt, completion)

    async def _handle_vision(mgr, req, image_ref, cid):
        prompt = _last_user_text(req.messages) or "Describe the image."
        model = _pick_vlm(req.model, mgr.default_vlm)
        vlm, lock = await mgr.vlm(model)
        # Blocking (decode / SSRF-filtered fetch / write) -> off the event loop; may raise -> 400.
        path, is_temp = await asyncio.to_thread(_materialize_image, image_ref)

        if req.stream:
            async def sse() -> AsyncIterator[str]:
                try:
                    async with lock:
                        yield _chat_chunk(cid, model, {"role": "assistant", "content": ""}, None)
                        try:
                            async for tok in vlm.acaption(path, prompt):
                                yield _chat_chunk(cid, model, {"content": tok}, None)
                        except Exception as exc:  # noqa: BLE001
                            yield _error_line(exc)
                            yield _DONE
                            return
                        yield _chat_chunk(cid, model, {}, "stop")
                        yield _DONE
                finally:
                    if is_temp:
                        _safe_unlink(path)

            return StreamingResponse(sse(), media_type="text/event-stream")

        try:
            async with lock:
                text = await vlm.acaption_text(path, prompt)
        finally:
            if is_temp:
                _safe_unlink(path)
        return _chat_completion(cid, model, {"role": "assistant", "content": text}, "stop", prompt, text)

    # -- completions (legacy) ----------------------------------------------
    @app.post("/v1/completions", dependencies=guarded)
    async def completions(req: CompletionRequest, mgr: ModelManager = Depends(get_manager)):
        prompt = req.prompt if isinstance(req.prompt, str) else "\n".join(req.prompt)
        opts = _gen_opts(req)
        model = req.model or mgr.default_llm
        llm, lock = await mgr.llm(model)
        cid = f"cmpl-{uuid.uuid4().hex}"
        if req.stream:
            gen = lambda: llm.agenerate(prompt, **opts)  # noqa: E731
            return StreamingResponse(
                _completions_sse(gen, lock, cid, model), media_type="text/event-stream"
            )
        async with lock:
            text = await llm.agenerate_text(prompt, **opts)
        pt, ct = _approx_tokens(prompt), _approx_tokens(text)
        return {
            "id": cid, "object": "text_completion", "created": int(time.time()), "model": model,
            "choices": [{"index": 0, "text": text, "finish_reason": "stop", "logprobs": None}],
            "usage": {"prompt_tokens": pt, "completion_tokens": ct, "total_tokens": pt + ct},
        }

    # -- embeddings ---------------------------------------------------------
    @app.post("/v1/embeddings", dependencies=guarded)
    async def embeddings(req: EmbeddingsRequest, mgr: ModelManager = Depends(get_manager)):
        inputs = [req.input] if isinstance(req.input, str) else list(req.input)
        model = req.model or mgr.default_embedder
        embedder, lock = await mgr.embedder(model)
        data, total = [], 0
        async with lock:
            for i, text in enumerate(inputs):
                vec = await asyncio.to_thread(embedder.embed, text)
                data.append(
                    {"object": "embedding", "index": i,
                     "embedding": _encode_embedding(vec, req.encoding_format)}
                )
                total += _approx_tokens(text)
        return {
            "object": "list", "data": data, "model": model,
            "usage": {"prompt_tokens": total, "total_tokens": total},
        }

    # -- audio --------------------------------------------------------------
    @app.post("/v1/audio/transcriptions", dependencies=guarded)
    async def transcriptions(
        file: UploadFile = File(...),
        model: Optional[str] = Form(default=None),
        mgr: ModelManager = Depends(get_manager),
    ):
        stt, lock = await mgr.stt(model or mgr.default_stt)
        raw = await file.read()
        try:
            sample_rate, samples = decode_wav(raw)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=400, detail=f"could not decode audio (send WAV): {exc}")
        if sample_rate != STT_SAMPLE_RATE:
            samples = downsample(samples, sample_rate, STT_SAMPLE_RATE)
        pcm16 = pcm16_bytes(samples)
        async with lock:
            text = await stt.atranscribe(pcm16)
        return {"text": text}

    @app.post("/v1/audio/speech", dependencies=guarded)
    async def speech(req: SpeechRequest, mgr: ModelManager = Depends(get_manager)):
        if req.response_format not in ("wav", "pcm"):
            raise HTTPException(status_code=400, detail="only response_format=wav is supported")
        tts, lock = await mgr.tts(req.model or mgr.default_tts)
        async with lock:
            synth = await tts.asynthesize(req.input)
        return Response(content=encode_wav(synth.samples, synth.sample_rate), media_type="audio/wav")

    return app
