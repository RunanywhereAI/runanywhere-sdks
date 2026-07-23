"""RAG (retrieval-augmented generation) — talk to your documents on-device.

A thin Python facade over the commons RAG pipeline (the native ``rac_rag_*_proto`` byte
ABI). Every call is proto-in / proto-out: this module owns the (de)serialization via the
generated ``_proto`` classes so callers work with plain dataclasses and never touch protobuf.

Two things are optional and fail with a clear hint rather than an obscure error:

* **The protobuf runtime** — only pulled in by the ``[rag]`` extra. A plain
  ``pip install runanywhere`` can still ``import runanywhere`` (and even
  ``from runanywhere import RagResult``); actually *using* RAG raises a friendly
  "install runanywhere[rag]" message.
* **The native RAG bindings** — present only when the wheel was built with the RAG backend
  + protobuf runtime (the published wheels are). A build without them raises a clear
  "compiled without RAG" message instead of an ``AttributeError``.

Typical use::

    with RunAnywhere() as ra:
        rag = ra.create_rag("minilm", llm_model="qwen2.5-0.5b")
        rag.ingest("Paris is the capital of France.")
        print(rag.query("What is the capital of France?").answer)   # -> "Paris"
        rag.close()
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any, AsyncIterator, Callable, Iterator

from ._streaming import aiter_tokens, iter_tokens
from .errors import ErrorCode, SDKException

if TYPE_CHECKING:
    from .results import ResolvedModel

# The generated *_pb2 import google.protobuf. Keep that optional: a base install (no [rag]
# extra) must still import this module — only real RAG operations need the runtime.
try:
    from ._proto import rag_pb2 as _pb

    _PROTO_IMPORT_ERROR: Exception | None = None
except Exception as exc:  # pragma: no cover - exercised only on a protobuf-free install
    _pb = None  # type: ignore[assignment]
    _PROTO_IMPORT_ERROR = exc

__all__ = [
    "RagDocument",
    "RagSearchResult",
    "RagResult",
    "RagStatistics",
    "RagStreamEvent",
    "RagSession",
    "create_session",
]

# rac_inference_framework_t / rac_model_category_t values used to register the RAG models
# into the global registry so commons can resolve embedding_model_id / llm_model_id -> path.
_FRAMEWORK_ONNX = 0
_FRAMEWORK_LLAMACPP = 1
_CATEGORY_LANGUAGE = 0
_CATEGORY_EMBEDDING = 7

# runanywhere.v1.RAGStreamEventKind values (stable proto enum; hardcoded so RagStreamEvent's
# convenience flags don't depend on the optional protobuf runtime being importable).
STREAM_RETRIEVAL_STARTED = 1
STREAM_CHUNK_RETRIEVED = 2
STREAM_CONTEXT_READY = 3
STREAM_TOKEN = 4
STREAM_COMPLETED = 5
STREAM_ERROR = 6


# --------------------------------------------------------------------------- value types
@dataclass
class RagDocument:
    """A document to ingest: its ``text`` body plus an optional id and metadata."""

    text: str
    id: str = ""
    metadata: dict[str, str] = field(default_factory=dict)


@dataclass
class RagSearchResult:
    """One retrieved chunk: the snippet, its similarity score, and provenance."""

    chunk_id: str
    text: str
    similarity_score: float
    source_document: str | None = None
    rank: int = 0
    metadata: dict[str, str] = field(default_factory=dict)


@dataclass
class RagResult:
    """A completed RAG query: the grounded ``answer`` plus the chunks it was built from."""

    answer: str
    retrieved_chunks: list[RagSearchResult] = field(default_factory=list)
    context_used: str = ""
    retrieval_time_ms: int = 0
    generation_time_ms: int = 0
    total_time_ms: int = 0
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    #: The answer model's ``<think>`` reasoning, if any (mirrors LLMGenerationResult).
    thinking_content: str | None = None


@dataclass
class RagStatistics:
    """Index-level counters for a RAG session."""

    indexed_documents: int = 0
    indexed_chunks: int = 0
    total_tokens_indexed: int = 0
    last_updated_ms: int = 0
    index_path: str | None = None
    vector_store_size_bytes: int = 0
    is_persistent: bool = False


@dataclass
class RagStreamEvent:
    """A single streaming event: a retrieved chunk, an answer token, or the terminal result."""

    kind: int
    token: str = ""
    chunk: RagSearchResult | None = None
    result: RagResult | None = None
    error_message: str | None = None

    @property
    def is_token(self) -> bool:
        """True for a generated answer-token event."""
        return self.kind == STREAM_TOKEN

    @property
    def is_final(self) -> bool:
        """True for the terminal COMPLETED event (its ``result`` carries the full answer)."""
        return self.kind == STREAM_COMPLETED

    @property
    def is_error(self) -> bool:
        """True for a terminal ERROR event (``error_message`` is set)."""
        return self.kind == STREAM_ERROR


# --------------------------------------------------------------------------- proto guards
def _require_proto() -> None:
    """Raise a friendly install hint if the protobuf runtime (the [rag] extra) is absent."""
    if _pb is None:
        raise SDKException.of(
            ErrorCode.SERVICE_NOT_AVAILABLE,
            "RAG needs the protobuf runtime — install it with `pip install runanywhere[rag]`",
            nested_message=str(_PROTO_IMPORT_ERROR) if _PROTO_IMPORT_ERROR else None,
        )


def _require_native(core: Any) -> None:
    """Raise if this build's native core was compiled without the RAG proto bindings."""
    if not hasattr(core, "rag_session_create"):
        raise SDKException.of(
            ErrorCode.SERVICE_NOT_AVAILABLE,
            "this runanywhere build was compiled without the RAG backend — "
            "reinstall the published wheel (or build with RAC_BACKEND_RAG=ON + "
            "RAC_ENABLE_PROTOBUF=ON)",
        )


# --------------------------------------------------------------------------- proto <-> dataclass
def _parse_search_result(pb: Any) -> RagSearchResult:
    return RagSearchResult(
        chunk_id=pb.chunk_id,
        text=pb.text,
        similarity_score=pb.similarity_score,
        source_document=pb.source_document if pb.HasField("source_document") else None,
        rank=pb.rank,
        metadata=dict(pb.metadata),
    )


def _parse_result(pb: Any) -> RagResult:
    return RagResult(
        answer=pb.answer,
        retrieved_chunks=[_parse_search_result(c) for c in pb.retrieved_chunks],
        context_used=pb.context_used,
        retrieval_time_ms=pb.retrieval_time_ms,
        generation_time_ms=pb.generation_time_ms,
        total_time_ms=pb.total_time_ms,
        prompt_tokens=pb.prompt_tokens,
        completion_tokens=pb.completion_tokens,
        total_tokens=pb.total_tokens,
        thinking_content=pb.thinking_content if pb.HasField("thinking_content") else None,
    )


def _parse_stats(pb: Any) -> RagStatistics:
    return RagStatistics(
        indexed_documents=pb.indexed_documents,
        indexed_chunks=pb.indexed_chunks,
        total_tokens_indexed=pb.total_tokens_indexed,
        last_updated_ms=pb.last_updated_ms,
        index_path=pb.index_path if pb.HasField("index_path") else None,
        vector_store_size_bytes=pb.vector_store_size_bytes,
        is_persistent=pb.is_persistent,
    )


def _parse_stream_event(raw: bytes) -> RagStreamEvent:
    ev = _pb.RAGStreamEvent()
    ev.ParseFromString(raw)
    return RagStreamEvent(
        kind=int(ev.kind),
        token=ev.token,
        chunk=_parse_search_result(ev.chunk) if ev.HasField("chunk") else None,
        result=_parse_result(ev.result) if ev.HasField("result") else None,
        error_message=ev.error_message if ev.HasField("error_message") else None,
    )


def _stats_from_bytes(raw: bytes) -> RagStatistics:
    pb = _pb.RAGStatistics()
    pb.ParseFromString(raw)
    return _parse_stats(pb)


# Query-option keys accepted by ingest/query kwargs and mapped onto RAGQueryOptions.
_QUERY_INT = ("max_tokens", "top_k", "retrieval_top_k")
_QUERY_FLOAT = ("temperature", "top_p", "similarity_threshold")


def _build_query(question: str, opts: dict, *, stream: bool) -> Any:
    """Assemble a RAGQueryOptions from a question + generation kwargs."""
    q = _pb.RAGQueryOptions(question=question)
    for key in _QUERY_INT:
        if opts.get(key) is not None:
            setattr(q, key, int(opts[key]))
    for key in _QUERY_FLOAT:
        if opts.get(key) is not None:
            setattr(q, key, float(opts[key]))
    if opts.get("system_prompt") is not None:
        q.system_prompt = str(opts["system_prompt"])
    if opts.get("scope_prefix") is not None:
        q.scope_prefix = str(opts["scope_prefix"])
    if opts.get("disable_thinking") is not None:
        q.disable_thinking = bool(opts["disable_thinking"])
    q.stream = stream
    return q


# --------------------------------------------------------------------------- session
class RagSession:
    """A live RAG session: ingest documents, then query for grounded answers.

    Created via :meth:`RunAnywhere.create_rag`. Not reused across processes — close it (or
    use it as a context manager) so the native session and its embedding/LLM services are
    released deterministically.
    """

    def __init__(self, core: Any, handle: int) -> None:
        self._core = core
        self._handle = handle
        self._closed = False

    def _live(self) -> Any:
        if self._closed:
            raise SDKException.invalid_state("RAG session is closed")
        return self._core

    # -- ingestion -----------------------------------------------------------
    def ingest(
        self,
        document: "str | RagDocument",
        *,
        id: str = "",
        metadata: dict[str, str] | None = None,
    ) -> RagStatistics:
        """Ingest one document (a ``str`` body or a :class:`RagDocument`). Returns updated stats."""
        core = self._live()
        doc = _pb.RAGDocument()
        if isinstance(document, RagDocument):
            doc.id = document.id
            doc.text = document.text
            src = document.metadata or {}
        else:
            doc.id = id
            doc.text = str(document)
            src = metadata or {}
        for k, v in src.items():
            doc.metadata[str(k)] = str(v)
        raw = core.rag_ingest(self._handle, doc.SerializeToString())
        return _stats_from_bytes(raw)

    def ingest_many(self, documents: "list[str | RagDocument]") -> RagStatistics:
        """Ingest a batch of documents in order; returns the stats after the last one."""
        stats: RagStatistics | None = None
        for doc in documents:
            stats = self.ingest(doc)
        return stats if stats is not None else self.stats()

    # -- query ---------------------------------------------------------------
    def query(self, question: str, **opts: Any) -> RagResult:
        """Retrieve relevant chunks and generate a grounded answer.

        Accepts ``max_tokens`` / ``temperature`` / ``top_p`` / ``top_k`` / ``system_prompt`` /
        ``retrieval_top_k`` / ``similarity_threshold`` / ``disable_thinking`` / ``scope_prefix``.
        """
        core = self._live()
        q = _build_query(question, opts, stream=False)
        raw = core.rag_query(self._handle, q.SerializeToString())
        pb = _pb.RAGResult()
        pb.ParseFromString(raw)
        if pb.error_code != 0:
            raise SDKException.generation_failed(
                pb.error_message or f"RAG query failed (code {pb.error_code})"
            )
        return _parse_result(pb)

    async def aquery(self, question: str, **opts: Any) -> RagResult:
        """Async twin of :meth:`query` (runs on the loop's default executor)."""
        import asyncio

        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self.query(question, **opts))

    def query_stream(self, question: str, **opts: Any) -> Iterator[RagStreamEvent]:
        """Stream a query as :class:`RagStreamEvent`\\ s (retrieval → tokens → terminal result).

        The terminal COMPLETED event's ``result`` carries the full :class:`RagResult`; break
        out of the loop early to stop generation (backpressure to the native pipeline).
        """
        core = self._live()
        payload = _build_query(question, opts, stream=True).SerializeToString()
        handle = self._handle

        def native_call(on_event: Callable[[bytes], "bool | None"]) -> None:
            core.rag_query_stream(handle, payload, on_event)

        for raw in iter_tokens(native_call):
            yield _parse_stream_event(raw)

    async def aquery_stream(self, question: str, **opts: Any) -> AsyncIterator[RagStreamEvent]:
        """Async twin of :meth:`query_stream`."""
        core = self._live()
        payload = _build_query(question, opts, stream=True).SerializeToString()
        handle = self._handle

        def native_call(on_event: Callable[[bytes], "bool | None"]) -> None:
            core.rag_query_stream(handle, payload, on_event)

        async for raw in aiter_tokens(native_call):
            yield _parse_stream_event(raw)

    def cancel(self) -> None:
        """Request cancellation of an in-flight query (safe to call from another thread)."""
        self._live().rag_cancel(self._handle)

    # -- index ---------------------------------------------------------------
    def stats(self) -> RagStatistics:
        """Snapshot the current index statistics."""
        return _stats_from_bytes(self._live().rag_stats(self._handle))

    def clear(self) -> RagStatistics:
        """Clear the index (drop all ingested chunks); returns the post-clear stats."""
        return _stats_from_bytes(self._live().rag_clear(self._handle))

    # -- lifecycle -----------------------------------------------------------
    def close(self) -> None:
        """Destroy the native session. Idempotent."""
        if self._closed:
            return
        self._closed = True
        self._core.rag_session_destroy(self._handle)

    # Also exposed as unload() so RunAnywhere.shutdown()'s model-teardown loop closes it.
    unload = close

    def __enter__(self) -> "RagSession":
        return self

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        self.close()


# --------------------------------------------------------------------------- factory
def _framework_for_llm(path: str) -> int:
    ext = os.path.splitext(path)[1].lower()
    if ext in (".onnx", ".ort"):
        return _FRAMEWORK_ONNX
    # .gguf / .ggml and anything else default to llama.cpp — the desktop LLM engine.
    return _FRAMEWORK_LLAMACPP


# RAGConfiguration knobs the caller may pass to create_rag (proto field -> coercion).
_CFG_INT = ("embedding_dimension", "top_k", "chunk_size", "chunk_overlap", "max_context_tokens")
_CFG_STR = ("prompt_template", "embedding_config_json", "llm_config_json", "index_path")


def create_session(
    core: Any,
    embedding_model: str,
    llm_model: str | None,
    cfg: dict,
    resolve: "Callable[[str], ResolvedModel]",
) -> RagSession:
    """Register the embedding (+ optional LLM) model into the global registry and open a session.

    ``resolve`` maps a catalog id / local path to a :class:`ResolvedModel` (downloading if
    needed). The commons RAG session ABI resolves ``embedding_model_id`` / ``llm_model_id`` to
    on-disk paths via that registry, so both must be registered before the session is created.
    """
    _require_proto()
    _require_native(core)

    emb = resolve(embedding_model)
    core.register_model(emb.id, emb.primary, _FRAMEWORK_ONNX, _CATEGORY_EMBEDDING)

    config = _pb.RAGConfiguration(embedding_model_id=emb.id)

    if llm_model:
        llm = resolve(llm_model)
        core.register_model(
            llm.id, llm.primary, _framework_for_llm(llm.primary), _CATEGORY_LANGUAGE
        )
        config.llm_model_id = llm.id

    for key in _CFG_INT:
        if cfg.get(key) is not None:
            setattr(config, key, int(cfg[key]))
    if cfg.get("similarity_threshold") is not None:
        config.similarity_threshold = float(cfg["similarity_threshold"])
    for key in _CFG_STR:
        if cfg.get(key) is not None:
            setattr(config, key, str(cfg[key]))
    if cfg.get("persist_index") is not None:
        config.persist_index = bool(cfg["persist_index"])
    if cfg.get("rerank_results") is not None:
        config.rerank_results = bool(cfg["rerank_results"])
    if cfg.get("reranker_model_id"):
        rr = resolve(cfg["reranker_model_id"])
        core.register_model(rr.id, rr.primary, _FRAMEWORK_ONNX, _CATEGORY_EMBEDDING)
        config.reranker_model_id = rr.id

    handle = core.rag_session_create(config.SerializeToString())
    return RagSession(core, handle)
