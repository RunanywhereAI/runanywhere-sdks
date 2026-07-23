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
from ..catalog import CATALOG, is_catalog_id
from ..errors import SDKException
from ..grammar import json_schema_to_grammar
from ..structured import ToolCall, ToolSpec
from .errors import http_status_for, install_error_handlers, openai_error_body
from .manager import ModelManager
from .schemas import ChatMessage, ChatRequest, CompletionRequest, EmbeddingsRequest, SpeechRequest

STT_SAMPLE_RATE = 16000
_DONE = "data: [DONE]\n\n"
MAX_IMAGE_BYTES = 20 * 1024 * 1024  # cap decoded/fetched image bytes (DoS guard)
_MAX_DATA_URI_CHARS = (MAX_IMAGE_BYTES // 3 + 1) * 4 + 64  # base64 input cap (pre-decode)
DEFAULT_MAX_BODY_BYTES = 50 * 1024 * 1024  # reject larger request bodies with 413
MAX_EMBEDDING_INPUTS = 2048  # cap the /v1/embeddings batch (matches OpenAI) — bound the lock hold


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
    """A terminal SSE ``data:`` error line for a mid-stream failure.

    SDKException messages are intentional and safe to surface; any OTHER exception is coerced to
    a GENERIC message rather than ``str(exc)`` so the streaming path does not leak raw backend
    exception text (paths, model internals) to the client — matching the non-streaming catch-all
    handler's no-echo posture. The exact error is still logged server-side by the caller.
    """
    e = exc if isinstance(exc, SDKException) else SDKException.generation_failed(
        "internal error during generation"
    )
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
            try:
                opts["grammar"] = json_schema_to_grammar(schema)
            except Exception as exc:  # noqa: BLE001 — a bad schema is a client error (400), not 500
                raise SDKException.invalid_input(f"invalid response_format json_schema: {exc}") from exc
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


def _validate_public_host(url: str) -> None:
    """Reject a URL whose host resolves to a non-globally-routable address (SSRF guard).

    Uses ``not is_global`` (allowlist) plus explicit reserved/mapped checks so loopback,
    private, link-local (169.254/16, incl. cloud metadata), CGNAT, and IPv4-mapped-IPv6
    loopback are all rejected. NOTE: a residual DNS-rebinding TOCTOU remains (urllib re-resolves
    at connect); URL fetch is therefore opt-in (allow_image_urls) — data-URIs are the safe path.
    """
    host = urllib.parse.urlparse(url).hostname
    if not host:
        raise SDKException.invalid_input("invalid image URL")
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        raise SDKException.invalid_input("could not resolve image host") from None
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        mapped = getattr(ip, "ipv4_mapped", None)
        if mapped is not None:  # normalise ::ffff:127.0.0.1 -> 127.0.0.1 before the check
            ip = mapped
        if not ip.is_global or ip.is_reserved:
            raise SDKException.invalid_input("image URL host is not allowed")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse to follow redirects — a redirect can bounce an allowed public URL to an internal
    address, bypassing the SSRF host check (which only vets the original URL)."""

    def redirect_request(self, *_args, **_kwargs):  # noqa: D102
        raise SDKException.invalid_input("image URL redirects are not allowed")


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirect)


def _fetch_image_bytes(url: str) -> bytes:
    """Fetch an http(s) image with the SSRF host check + no redirects + a hard size cap."""
    _validate_public_host(url)
    try:
        with _NO_REDIRECT_OPENER.open(url, timeout=10) as r:  # noqa: S310 — host-vetted, no redirects
            raw = r.read(MAX_IMAGE_BYTES + 1)
    except SDKException:
        raise
    except Exception:  # noqa: BLE001 — generic message; exact error stays server-side (recon oracle)
        raise SDKException.invalid_input("could not fetch image URL") from None
    if len(raw) > MAX_IMAGE_BYTES:
        raise SDKException.invalid_input("image exceeds the size limit")
    return raw


def _materialize_image(ref: str, allow_urls: bool) -> tuple[str, bool]:
    """Return ``(temp_path, True)`` for a data-URI (or, if ``allow_urls``, an http(s)) image.
    Blocking (decode / fetch / write) — call via ``asyncio.to_thread``. Local filesystem paths
    are never accepted (arbitrary-file-read guard); size is capped BEFORE decode (DoS guard).
    Raises ``SDKException.invalid_input`` (-> HTTP 400) on any rejection."""
    if ref.startswith("data:"):
        header, _, data = ref.partition(",")
        if len(data) > _MAX_DATA_URI_CHARS:  # cap the base64 INPUT before allocating the decode
            raise SDKException.invalid_input("image exceeds the size limit")
        try:
            raw = base64.b64decode(data) if ";base64" in header else urllib.parse.unquote_to_bytes(data)
        except Exception:  # noqa: BLE001
            raise SDKException.invalid_input("could not decode data-URI image") from None
        if len(raw) > MAX_IMAGE_BYTES:
            raise SDKException.invalid_input("image exceeds the size limit")
        fd, path = tempfile.mkstemp(suffix=_img_suffix(header))
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
        return path, True
    if ref.startswith("http://") or ref.startswith("https://"):
        if not allow_urls:
            raise SDKException.invalid_input(
                "image URLs are disabled; send the image as a data: URI "
                "(or start the server with allow_image_urls=True)"
            )
        raw = _fetch_image_bytes(ref)
        fd, path = tempfile.mkstemp(suffix=".img")
        with os.fdopen(fd, "wb") as f:
            f.write(raw)
        return path, True
    # Neither a data: URI nor an http(s) URL: do NOT treat network input as a local file path.
    raise SDKException.invalid_input("image_url must be a data: URI or an http(s) URL")


def _resolve_model_id(req_model: Optional[str], default: str, allow_arbitrary: bool) -> str:
    """The model id to load. Client-supplied ids must be catalog ids (or match the operator's
    configured default) unless ``allow_arbitrary`` — so a network client can't make the server
    load an arbitrary local path / HF repo (arbitrary-load + unbounded-model-pinning guard)."""
    model = req_model or default
    if allow_arbitrary or model == default or is_catalog_id(model):
        return model
    raise SDKException.model_not_found(model)


def _pick_vlm(req_model: Optional[str], default_vlm: str, allow_arbitrary: bool) -> str:
    """Resolve the VLM: a known VLM id is used; a custom path only if ``allow_arbitrary`` or it is
    the configured default; anything else falls back to the default VLM (vision never 404s here)."""
    if req_model:
        entry = CATALOG.get(req_model)
        if entry is not None and entry.type == "vlm":
            return req_model
        if entry is None and (allow_arbitrary or req_model == default_vlm):
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


class _BodyLimitMiddleware:
    """Reject request bodies over ``max_bytes`` with 413, enforced on ACTUAL bytes (so a chunked
    body with no Content-Length can't bypass a header-only check). Buffers up to the limit, then
    replays the body to the app — bounding memory to ``max_bytes`` per request."""

    def __init__(self, app, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        body = b""
        more = True
        while more:
            msg = await receive()
            if msg["type"] != "http.request":
                return await self.app(scope, _prepend(msg, receive), send)
            body += msg.get("body", b"")
            more = msg.get("more_body", False)
            if len(body) > self.max_bytes:
                await send({"type": "http.response.start", "status": 413,
                            "headers": [(b"content-type", b"application/json")]})
                await send({"type": "http.response.body",
                            "body": json.dumps(openai_error_body("request body too large", 413)).encode()})
                return
        replayed = False

        async def replay():
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        return await self.app(scope, replay, send)


def _prepend(first, receive):
    sent = False

    async def _recv():
        nonlocal sent
        if not sent:
            sent = True
            return first
        return await receive()

    return _recv


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
    allow_image_urls: bool = False,
    allow_arbitrary_models: bool = False,
) -> FastAPI:
    """Build the FastAPI app. Pass ``model_manager`` to inject a (fake) manager for tests; else a
    real one is built in the lifespan so importing/creating the app never touches native code.

    Security defaults (opt in only if you trust the clients): ``allow_image_urls=False`` accepts
    only data-URI images (no server-side URL fetch = no SSRF); ``allow_arbitrary_models=False``
    accepts only catalog model ids (or the configured defaults), not arbitrary paths / HF repos.
    """

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
        try:
            mgr.start()  # inside the try so a failed init still runs stop() (idempotent)
            yield
        finally:
            mgr.stop()

    app = FastAPI(title="RunAnywhere OpenAI-compatible server", lifespan=lifespan)
    if model_manager is not None:
        app.state.manager = model_manager
    install_error_handlers(app)
    app.add_middleware(_BodyLimitMiddleware, max_bytes=max_body_bytes)

    async def require_api_key(authorization: Optional[str] = Header(default=None)) -> None:
        if api_key is None:
            return
        # Constant-time compare on bytes (never raises on a non-ASCII header, unlike str compare).
        expected = f"Bearer {api_key}".encode()
        got = authorization.encode() if isinstance(authorization, str) else b""
        if not hmac.compare_digest(got, expected):
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
        if not req.messages:
            raise SDKException.invalid_input("messages must not be empty")
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

        model = _resolve_model_id(req.model, mgr.default_llm, allow_arbitrary_models)
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
        model = _pick_vlm(req.model, mgr.default_vlm, allow_arbitrary_models)
        vlm, lock = await mgr.vlm(model)
        # Blocking (decode / SSRF-filtered fetch / write) -> off the event loop; may raise -> 400.
        path, is_temp = await asyncio.to_thread(_materialize_image, image_ref, allow_image_urls)

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
        model = _resolve_model_id(req.model, mgr.default_llm, allow_arbitrary_models)
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
        if not inputs or any(not isinstance(t, str) or t == "" for t in inputs):
            raise SDKException.invalid_input("input must be a non-empty string or list of non-empty strings")
        if len(inputs) > MAX_EMBEDDING_INPUTS:
            # An unbounded batch would hold the per-model lock for a long time, blocking every
            # other embeddings request (DoS). Reject oversized batches like OpenAI does.
            raise SDKException.invalid_input(f"too many inputs (max {MAX_EMBEDDING_INPUTS})")
        model = _resolve_model_id(req.model, mgr.default_embedder, allow_arbitrary_models)
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
        stt, lock = await mgr.stt(_resolve_model_id(model, mgr.default_stt, allow_arbitrary_models))
        raw = await file.read()
        try:
            sample_rate, samples = decode_wav(raw)
        except Exception:  # noqa: BLE001 — generic client-facing message; details stay server-side
            raise HTTPException(status_code=400, detail="could not decode audio (send a 16-bit WAV)") from None
        if sample_rate != STT_SAMPLE_RATE:
            samples = downsample(samples, sample_rate, STT_SAMPLE_RATE)
        pcm16 = pcm16_bytes(samples)
        async with lock:
            text = await stt.atranscribe(pcm16)
        return {"text": text}

    @app.post("/v1/audio/speech", dependencies=guarded)
    async def speech(req: SpeechRequest, mgr: ModelManager = Depends(get_manager)):
        if req.response_format != "wav":
            raise HTTPException(status_code=400, detail="only response_format=wav is supported")
        tts, lock = await mgr.tts(_resolve_model_id(req.model, mgr.default_tts, allow_arbitrary_models))
        async with lock:
            synth = await tts.asynthesize(req.input)
        return Response(content=encode_wav(synth.samples, synth.sample_rate), media_type="audio/wav")

    return app
