"""The FastAPI app: OpenAI-compatible routes over the RunAnywhere namespaces.

``create_app(model_manager=None)`` is the injectable factory (pass a fake manager in tests).
Routes resolve the live manager via the ``get_manager`` dependency. The wire contract is
OpenAI's — ``max_tokens``, ``response_format``, ``tool_choice`` and ``stop`` keep their OpenAI
names on the HTTP surface and are translated into the SDK's options here.
"""
from __future__ import annotations

import asyncio
import base64
import hmac
import http.client
import ipaddress
import json
import os
import socket
import ssl
import tempfile
import time
import urllib.parse
import uuid
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator, List, Optional

import numpy as np
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import Response, StreamingResponse

import runanywhere as ra

from ..catalog import CATALOG, is_catalog_id
from ..errors import SDKException
from ..inputs import AudioFormat, AudioInput, ImageInput, ToolDefinition
from ..options import (
    EmbedOptions,
    LlmOptions,
    StructuredOutput,
    SttOptions,
    ToolChoice,
    ToolChoiceMode,
    TtsOptions,
)
from ..results import ToolCall
from .errors import http_status_for, install_error_handlers, openai_error_body
from .manager import ModelManager
from .schemas import ChatMessage, ChatRequest, CompletionRequest, EmbeddingsRequest, SpeechRequest

_DONE = "data: [DONE]\n\n"
MAX_IMAGE_BYTES = 20 * 1024 * 1024  # cap decoded/fetched image bytes (DoS guard)
_MAX_DATA_URI_CHARS = (MAX_IMAGE_BYTES // 3 + 1) * 4 + 64  # base64 input cap (pre-decode)
DEFAULT_MAX_BODY_BYTES = 50 * 1024 * 1024  # reject larger request bodies with 413
MAX_EMBEDDING_INPUTS = 2048  # cap the /v1/embeddings batch (matches OpenAI)


def get_manager(request: Request) -> ModelManager:
    """FastAPI dependency: the live model manager (set in the lifespan / create_app)."""
    return request.app.state.manager


# --------------------------------------------------------------------------- generic helpers
def _token_usage(*, input_tokens: int = 0, output_tokens: int = 0) -> dict:
    """OpenAI usage block from commons/engine TokenUsage fields (0 if absent)."""
    prompt = int(input_tokens or 0)
    completion = int(output_tokens or 0)
    return {
        "prompt_tokens": prompt,
        "completion_tokens": completion,
        "total_tokens": prompt + completion,
    }


def _gen_opts(req: Any, model: str) -> LlmOptions:
    """Translate the OpenAI sampling fields into SDK generation options."""
    options = LlmOptions(model=model)
    max_tokens = getattr(req, "max_completion_tokens", None) or getattr(req, "max_tokens", None)
    if max_tokens is not None:
        options.max_output_tokens = int(max_tokens)
    if getattr(req, "temperature", None) is not None:
        options.temperature = float(req.temperature)
    if getattr(req, "top_p", None) is not None:
        options.top_p = float(req.top_p)
    if getattr(req, "top_k", None) is not None:
        options.top_k = int(req.top_k)
    stop = getattr(req, "stop", None)
    if stop:
        options.stop_sequences = [stop] if isinstance(stop, str) else list(stop)
    return options


def _message_text(content: Any) -> str:
    """The text of a message whose ``content`` is a string or a list of OpenAI parts."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    parts = []
    for part in content:
        if isinstance(part, dict) and part.get("type") == "text":
            parts.append(part.get("text", ""))
        elif isinstance(part, str):
            parts.append(part)
    return "\n".join(x for x in parts if x)


def _build_prompt(messages: List[ChatMessage]) -> tuple:
    """(system, prompt). A single user turn is passed verbatim (the engine applies the model's
    chat template); multi-turn is serialized into a simple transcript."""
    system = "\n".join(_message_text(m.content) for m in messages if m.role == "system") or None
    turns = [m for m in messages if m.role != "system"]
    if len(turns) == 1 and turns[0].role == "user":
        return system, _message_text(turns[0].content)
    lines = []
    for message in turns:
        who = "User" if message.role == "user" else "Assistant"
        lines.append(f"{who}: {_message_text(message.content)}")
    lines.append("Assistant:")
    return system, "\n".join(lines)


def _last_user_text(messages: List[ChatMessage]) -> str:
    for message in reversed(messages):
        if message.role == "user":
            return _message_text(message.content)
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

    SDKException messages are intentional and safe to surface; any OTHER exception is coerced
    to a generic message so the streaming path does not leak raw backend exception text.
    """
    error = (
        exc
        if isinstance(exc, SDKException)
        else SDKException.generation_failed("internal error during generation")
    )
    body = openai_error_body(error.message, http_status_for(error), code=int(error.code))
    return f"data: {json.dumps(body)}\n\n"


def _chat_completion(
    cid: str,
    model: str,
    message: dict,
    finish: str,
    *,
    input_tokens: int = 0,
    output_tokens: int = 0,
) -> dict:
    return {
        "id": cid,
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "message": message, "finish_reason": finish}],
        "usage": _token_usage(input_tokens=input_tokens, output_tokens=output_tokens),
    }


# --------------------------------------------------------------------------- structured output
def _apply_response_format(rf: Optional[dict], options: LlmOptions) -> Optional[str]:
    """For ``json_schema`` constrain decoding; for ``json_object`` return a system hint."""
    if not rf:
        return None
    rf_type = rf.get("type")
    if rf_type == "json_schema":
        schema = (rf.get("json_schema") or {}).get("schema")
        if schema:
            options.structured_output = StructuredOutput(schema=schema)
        return None
    if rf_type == "json_object":
        return "You must respond with a single valid JSON object."
    return None


# --------------------------------------------------------------------------- tool calling
def _tool_defs(tools: Optional[List[dict]]) -> List[ToolDefinition]:
    out: List[ToolDefinition] = []
    for tool in tools or []:
        fn = tool.get("function") if isinstance(tool, dict) else None
        fn = fn if isinstance(fn, dict) else (tool if isinstance(tool, dict) else {})
        name = fn.get("name")
        if not name:
            continue
        out.append(
            ToolDefinition(
                name=name,
                parameters=fn.get("parameters") or {"type": "object"},
                description=fn.get("description"),
            )
        )
    return out


def _tool_choice(tool_choice: Any, tools: List[ToolDefinition]) -> ToolChoice:
    """Map OpenAI's ``tool_choice`` onto the SDK's policy."""
    if tool_choice is None:
        return ToolChoice(ToolChoiceMode.AUTO)
    if isinstance(tool_choice, str):
        if tool_choice == "none":
            return ToolChoice(ToolChoiceMode.NONE)
        if tool_choice == "required":
            return ToolChoice(ToolChoiceMode.REQUIRED)
        return ToolChoice(ToolChoiceMode.AUTO)
    if isinstance(tool_choice, dict):
        name = (tool_choice.get("function") or {}).get("name")
        if not name or name not in {tool.name for tool in tools}:
            raise SDKException.invalid_input(f"tool_choice named an unknown tool: {name!r}")
        return ToolChoice.forced(name)
    return ToolChoice(ToolChoiceMode.AUTO)


def _tool_calls_message(calls: List[ToolCall]) -> dict:
    return {
        "role": "assistant",
        "content": None,
        "tool_calls": [
            {
                "id": f"call_{uuid.uuid4().hex[:24]}",
                "type": "function",
                "function": {"name": call.name, "arguments": json.dumps(call.arguments)},
            }
            for call in calls
        ],
    }


# --------------------------------------------------------------------------- vision (image input)
def _last_user_image(messages: List[ChatMessage]) -> Optional[str]:
    for message in reversed(messages):
        if message.role == "user" and isinstance(message.content, list):
            for part in message.content:
                if isinstance(part, dict) and part.get("type") == "image_url":
                    url = part.get("image_url")
                    if isinstance(url, dict):
                        return url.get("url")
                    if isinstance(url, str):
                        return url
    return None


def _img_suffix(header: str) -> str:
    lowered = header.lower()
    if "png" in lowered:
        return ".png"
    if "webp" in lowered:
        return ".webp"
    if "gif" in lowered:
        return ".gif"
    return ".jpg"


def _ip_is_public(ip) -> bool:
    """True iff ``ip`` is globally routable (SSRF allowlist). Normalises IPv4-mapped IPv6."""
    mapped = getattr(ip, "ipv4_mapped", None)
    if mapped is not None:  # ::ffff:127.0.0.1 -> 127.0.0.1 before the check
        ip = mapped
    return bool(ip.is_global) and not ip.is_reserved


def _validated_connect_targets(host: str, port: int) -> list:
    """Resolve ``host`` and return ``getaddrinfo`` rows whose IPs pass the SSRF allowlist.

    Fail-closed: any non-public address in the resolution set rejects the whole host. Callers
    then ``connect()`` to one of these sockaddr tuples — never re-resolve — closing the
    DNS-rebinding window.
    """
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except OSError:
        raise SDKException.invalid_input("could not resolve image host") from None
    if not infos:
        raise SDKException.invalid_input("could not resolve image host")
    out = []
    for family, socktype, proto, _canon, sockaddr in infos:
        if not _ip_is_public(ipaddress.ip_address(sockaddr[0])):
            raise SDKException.invalid_input("image URL host is not allowed")
        out.append((family, socktype, proto, sockaddr))
    return out


def _fetch_image_bytes(url: str) -> bytes:
    """Fetch an http(s) image with SSRF hardening: DNS allowlist, connect-by-IP, no redirects."""
    parsed = urllib.parse.urlparse(url)
    scheme = (parsed.scheme or "").lower()
    if scheme not in ("http", "https"):
        raise SDKException.invalid_input("invalid image URL")
    host = parsed.hostname
    if not host:
        raise SDKException.invalid_input("invalid image URL")
    port = parsed.port or (443 if scheme == "https" else 80)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    family, socktype, proto, sockaddr = _validated_connect_targets(host, port)[0]
    conn: Optional[http.client.HTTPConnection] = None
    try:
        sock = socket.socket(family, socktype, proto)
        sock.settimeout(10)
        sock.connect(sockaddr)  # validated IP — no second DNS lookup
        if scheme == "https":
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
        # Pre-connected socket: HTTPConnection must not dial/resolve again.
        conn = http.client.HTTPConnection(host, port, timeout=10)
        conn.sock = sock
        conn.request(
            "GET", path, headers={"Host": host, "Accept": "image/*,*/*", "Connection": "close"}
        )
        resp = conn.getresponse()
        if 300 <= resp.status < 400:
            # A public URL redirecting to 169.254.169.254 would bypass a one-shot host check.
            raise SDKException.invalid_input("image URL redirects are not allowed")
        if resp.status != 200:
            raise SDKException.invalid_input("could not fetch image URL")
        raw = resp.read(MAX_IMAGE_BYTES + 1)
    except SDKException:
        raise
    except Exception:  # noqa: BLE001 — generic message; exact error stays server-side
        raise SDKException.invalid_input("could not fetch image URL") from None
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:  # noqa: BLE001 — best-effort cleanup
                pass
    if len(raw) > MAX_IMAGE_BYTES:
        raise SDKException.invalid_input("image exceeds the size limit")
    return raw


def _materialize_image(ref: str, allow_urls: bool) -> tuple:
    """Return ``(temp_path, True)`` for a data-URI (or, if ``allow_urls``, an http(s)) image.

    Blocking (decode / fetch / write) — call via ``asyncio.to_thread``. Local filesystem paths
    are never accepted (arbitrary-file-read guard); size is capped BEFORE decode (DoS guard).
    """
    if ref.startswith("data:"):
        header, _, data = ref.partition(",")
        if len(data) > _MAX_DATA_URI_CHARS:  # cap the base64 INPUT before allocating the decode
            raise SDKException.invalid_input("image exceeds the size limit")
        try:
            raw = (
                base64.b64decode(data)
                if ";base64" in header
                else urllib.parse.unquote_to_bytes(data)
            )
        except Exception:  # noqa: BLE001
            raise SDKException.invalid_input("could not decode data-URI image") from None
        if len(raw) > MAX_IMAGE_BYTES:
            raise SDKException.invalid_input("image exceeds the size limit")
        fd, path = tempfile.mkstemp(suffix=_img_suffix(header))
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw)
        return path, True
    if ref.startswith("http://") or ref.startswith("https://"):
        if not allow_urls:
            raise SDKException.invalid_input(
                "image URLs are disabled; send the image as a data: URI "
                "(or start the server with allow_image_urls=True)"
            )
        raw = _fetch_image_bytes(ref)
        fd, path = tempfile.mkstemp(suffix=".img")
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw)
        return path, True
    # Neither a data: URI nor an http(s) URL: do NOT treat network input as a local file path.
    raise SDKException.invalid_input("image_url must be a data: URI or an http(s) URL")


def _resolve_model_id(req_model: Optional[str], default: str, allow_arbitrary: bool) -> str:
    """The model id to load. Client-supplied ids must be catalog ids (or the operator's
    configured default) unless ``allow_arbitrary`` — so a network client cannot make the
    server load an arbitrary local path / HF repo."""
    model = req_model or default
    if allow_arbitrary or model == default or is_catalog_id(model):
        return model
    raise SDKException.model_not_found(model)


def _pick_vlm(req_model: Optional[str], default_vlm: str, allow_arbitrary: bool) -> str:
    """Resolve the VLM: a known VLM id is used; a custom path only if ``allow_arbitrary`` or it
    is the configured default; anything else falls back to the default VLM."""
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
async def _atext(events) -> AsyncIterator[str]:
    """Yield answer text from a generation event stream."""
    async for event in events:
        if event.is_token and not event.is_thought:
            yield event.text


async def _chat_text_sse(factory, lock, cid: str, model: str) -> AsyncIterator[str]:
    """Stream chat deltas from an event-stream factory, holding the category lock."""
    async with lock:
        yield _chat_chunk(cid, model, {"role": "assistant", "content": ""}, None)
        try:
            async for text in _atext(factory()):
                yield _chat_chunk(cid, model, {"content": text}, None)
        except Exception as exc:  # noqa: BLE001 — headers already sent (200)
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
        deltas = [{**call, "index": i} for i, call in enumerate(message["tool_calls"])]
        yield _chat_chunk(cid, model, {"tool_calls": deltas}, None)
    elif message.get("content"):
        yield _chat_chunk(cid, model, {"content": message["content"]}, None)
    yield _chat_chunk(cid, model, {}, finish)
    yield _DONE


async def _completions_sse(factory, lock, cid: str, model: str) -> AsyncIterator[str]:
    async with lock:
        try:
            async for text in _atext(factory()):
                payload = {
                    "id": cid, "object": "text_completion", "created": int(time.time()),
                    "model": model,
                    "choices": [{"index": 0, "text": text, "finish_reason": None, "logprobs": None}],
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
    """Reject request bodies over ``max_bytes`` with 413, enforced on ACTUAL bytes (so a
    chunked body with no Content-Length can't bypass a header-only check). Buffers up to the
    limit, then replays the body to the app — bounding memory to ``max_bytes`` per request."""

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
    """Build the FastAPI app. Pass ``model_manager`` to inject a (fake) manager for tests; else
    a real one is built in the lifespan so importing/creating the app never touches native code.

    Security defaults (opt in only if you trust the clients): ``allow_image_urls=False``
    accepts only data-URI images (no server-side URL fetch = no SSRF);
    ``allow_arbitrary_models=False`` accepts only catalog model ids.
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
        # Constant-time compare on bytes (never raises on a non-ASCII header).
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
    def _model_obj(mid: str, entry, downloaded: set) -> dict:
        return {
            "id": mid, "object": "model", "created": 0, "owned_by": "runanywhere",
            "type": entry.type, "downloaded": mid in downloaded,
        }

    @app.get("/v1/models", dependencies=guarded)
    async def list_models(mgr: ModelManager = Depends(get_manager)) -> dict:
        downloaded = mgr.downloaded()
        return {
            "object": "list",
            "data": [_model_obj(m, e, downloaded) for m, e in sorted(CATALOG.items())],
        }

    @app.get("/v1/models/{model_id}", dependencies=guarded)
    async def retrieve_model(model_id: str, mgr: ModelManager = Depends(get_manager)) -> dict:
        entry = CATALOG.get(model_id)
        if entry is None:
            raise HTTPException(status_code=404, detail=f"model {model_id!r} not found")
        return _model_obj(model_id, entry, mgr.downloaded())

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
        model = _resolve_model_id(req.model, mgr.default_llm, allow_arbitrary_models)
        options = _gen_opts(req, model)
        hint = _apply_response_format(req.response_format, options)
        system = "\n".join(x for x in (system, hint) if x) or None
        if system:
            options.system_prompt = system

        tools = _tool_defs(req.tools)
        choice = _tool_choice(req.tool_choice, tools)
        lock = mgr.lock("llm")
        if tools and choice.mode != ToolChoiceMode.NONE:
            options.tools = tools
            options.tool_choice = choice
            return await _handle_tools(lock, prompt, options, req, cid, model)

        if req.stream:
            return StreamingResponse(
                _chat_text_sse(lambda: ra.llm.agenerate_stream(prompt, options), lock, cid, model),
                media_type="text/event-stream",
            )
        async with lock:
            result = await ra.llm.agenerate(prompt, options)
        return _chat_completion(
            cid,
            model,
            {"role": "assistant", "content": result.text},
            "stop",
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
        )

    async def _handle_tools(lock, prompt, options, req, cid, model):
        async with lock:
            result = await ra.llm.agenerate(prompt, options)
        if result.tool_calls:
            message = _tool_calls_message(result.tool_calls)
            finish = "tool_calls"
        else:
            message = {"role": "assistant", "content": result.text}
            finish = "stop"
        if req.stream:
            return StreamingResponse(
                _final_sse(cid, model, message, finish), media_type="text/event-stream"
            )
        return _chat_completion(
            cid,
            model,
            message,
            finish,
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
        )

    async def _handle_vision(mgr, req, image_ref, cid):
        prompt = _last_user_text(req.messages) or "Describe the image."
        model = _pick_vlm(req.model, mgr.default_vlm, allow_arbitrary_models)
        options = _gen_opts(req, model)
        lock = mgr.lock("vlm")
        # Blocking (decode / SSRF-filtered fetch / write) -> off the event loop; may raise -> 400.
        path, is_temp = await asyncio.to_thread(_materialize_image, image_ref, allow_image_urls)

        if req.stream:
            async def sse() -> AsyncIterator[str]:
                try:
                    async with lock:
                        yield _chat_chunk(cid, model, {"role": "assistant", "content": ""}, None)
                        try:
                            events = ra.vlm.agenerate_stream(ImageInput.file(path), prompt, options)
                            async for text in _atext(events):
                                yield _chat_chunk(cid, model, {"content": text}, None)
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
                result = await ra.vlm.agenerate(ImageInput.file(path), prompt, options)
        finally:
            if is_temp:
                _safe_unlink(path)
        return _chat_completion(
            cid,
            model,
            {"role": "assistant", "content": result.text},
            "stop",
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
        )

    # -- completions (legacy) ----------------------------------------------
    @app.post("/v1/completions", dependencies=guarded)
    async def completions(req: CompletionRequest, mgr: ModelManager = Depends(get_manager)):
        prompt = req.prompt if isinstance(req.prompt, str) else "\n".join(req.prompt)
        model = _resolve_model_id(req.model, mgr.default_llm, allow_arbitrary_models)
        options = _gen_opts(req, model)
        cid = f"cmpl-{uuid.uuid4().hex}"
        lock = mgr.lock("llm")
        if req.stream:
            return StreamingResponse(
                _completions_sse(
                    lambda: ra.llm.agenerate_stream(prompt, options), lock, cid, model
                ),
                media_type="text/event-stream",
            )
        async with lock:
            result = await ra.llm.agenerate(prompt, options)
        return {
            "id": cid, "object": "text_completion", "created": int(time.time()), "model": model,
            "choices": [{"index": 0, "text": result.text, "finish_reason": "stop", "logprobs": None}],
            "usage": _token_usage(
                input_tokens=result.input_tokens,
                output_tokens=result.output_tokens,
            ),
        }

    # -- embeddings ---------------------------------------------------------
    @app.post("/v1/embeddings", dependencies=guarded)
    async def embeddings(req: EmbeddingsRequest, mgr: ModelManager = Depends(get_manager)):
        inputs = [req.input] if isinstance(req.input, str) else list(req.input)
        if not inputs or any(not isinstance(t, str) or t == "" for t in inputs):
            raise SDKException.invalid_input(
                "input must be a non-empty string or list of non-empty strings"
            )
        if len(inputs) > MAX_EMBEDDING_INPUTS:
            # An unbounded batch would hold the lock for a long time, blocking every other
            # embeddings request (DoS). Reject oversized batches like OpenAI does.
            raise SDKException.invalid_input(f"too many inputs (max {MAX_EMBEDDING_INPUTS})")
        model = _resolve_model_id(req.model, mgr.default_embedder, allow_arbitrary_models)
        async with mgr.lock("embeddings"):
            vectors = await ra.embeddings.aembed(inputs, EmbedOptions(model=model))
        data = [
            {
                "object": "embedding",
                "index": vector.index,
                "embedding": _encode_embedding(vector.vector, req.encoding_format),
            }
            for vector in vectors
        ]
        total = 0
        return {
            "object": "list", "data": data, "model": model,
            # Embeddings have no TokenUsage on this path — report 0, never chars/4.
            "usage": {"prompt_tokens": total, "total_tokens": total},
        }

    # -- audio --------------------------------------------------------------
    @app.post("/v1/audio/transcriptions", dependencies=guarded)
    async def transcriptions(
        file: UploadFile = File(...),
        model: Optional[str] = Form(default=None),
        mgr: ModelManager = Depends(get_manager),
    ):
        model_id = _resolve_model_id(model, mgr.default_stt, allow_arbitrary_models)
        raw = await file.read()
        try:
            audio = AudioInput.wav(raw)
            audio.samples()  # decode eagerly so a bad upload is a 400, not a 500
        except Exception:  # noqa: BLE001 — generic client-facing message
            raise HTTPException(
                status_code=400, detail="could not decode audio (send a 16-bit WAV)"
            ) from None
        async with mgr.lock("stt"):
            transcription = await ra.stt.atranscribe(audio, SttOptions(model=model_id))
        return {"text": transcription.text}

    @app.post("/v1/audio/speech", dependencies=guarded)
    async def speech(req: SpeechRequest, mgr: ModelManager = Depends(get_manager)):
        if req.response_format != "wav":
            raise HTTPException(status_code=400, detail="only response_format=wav is supported")
        model_id = _resolve_model_id(req.model, mgr.default_tts, allow_arbitrary_models)
        async with mgr.lock("tts"):
            audio = await ra.tts.asynthesize(
                req.input, TtsOptions(model=model_id, voice=req.voice, format=AudioFormat.WAV)
            )
        return Response(content=audio.data, media_type="audio/wav")

    return app
