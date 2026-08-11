"""Proto plumbing for the native RAG session ABI (``rac_rag_*_proto``).

Internal. Every call across the bridge is proto-in / proto-out; this module owns the
(de)serialization so :mod:`runanywhere.api.rag` works in plain dataclasses. Two things are
optional and fail with a clear hint rather than an obscure error: the protobuf runtime (the
``[rag]`` extra) and the native RAG bindings (present when the wheel was built with the RAG
backend).
"""

from __future__ import annotations

from typing import Any, List, Optional

from .errors import ErrorCode, SDKException
from .events import RagEvent, RagEventKind
from .options import RagConfig, RagQueryOptions, ReasoningMode
from .results import Match, RagResult, RagStats, TokenKind

try:
    from ._proto import rag_pb2 as _pb

    _PROTO_IMPORT_ERROR: Optional[Exception] = None
except Exception as exc:  # pragma: no cover - exercised only on a protobuf-free install
    _pb = None  # type: ignore[assignment]
    _PROTO_IMPORT_ERROR = exc

__all__ = [
    "build_config",
    "build_query",
    "build_search",
    "parse_result",
    "parse_search_response",
    "parse_stats",
    "parse_stream_event",
    "require_native",
    "require_proto",
    "require_search",
]

# runanywhere.v1.RAGStreamEventKind wire values, hardcoded so the event mapping does not
# depend on the optional protobuf runtime being importable. The stream no longer signals a
# distinct "chunk retrieved" stage (RAGStreamEventKind collapsed to just TOKEN/COMPLETED/ERROR
# on top of UNSPECIFIED=0) — retrieval happens before the first token, with no separate event.
_STREAM_TOKEN = 1
_STREAM_COMPLETED = 2
_STREAM_ERROR = 3


def require_proto() -> None:
    """Raise a friendly install hint when the protobuf runtime is absent."""
    if _pb is None:
        raise SDKException.of(
            ErrorCode.SERVICE_NOT_AVAILABLE,
            "RAG needs the protobuf runtime — install it with `pip install runanywhere[rag]`",
            nested_message=str(_PROTO_IMPORT_ERROR) if _PROTO_IMPORT_ERROR else None,
        )


def require_native(core: Any) -> None:
    """Raise when this build's native core was compiled without the RAG bindings."""
    if not hasattr(core, "rag_session_create"):
        raise SDKException.of(
            ErrorCode.SERVICE_NOT_AVAILABLE,
            "this runanywhere build was compiled without the RAG backend — reinstall the "
            "published wheel (or build with RAC_BACKEND_RAG=ON + RAC_ENABLE_PROTOBUF=ON)",
        )


def require_search(core: Any) -> None:
    """Raise when the retrieval-only ``rac_rag_search_proto`` binding is missing."""
    if not hasattr(core, "rag_search"):
        raise SDKException.of(
            ErrorCode.FEATURE_NOT_AVAILABLE,
            "rag.search is unavailable in this build — rebuild/reinstall with a commons that "
            "exports rac_rag_search_proto (no query workaround)",
        )


def build_config(
    embedding_model_id: str, llm_model_id: Optional[str], config: Optional[RagConfig]
) -> bytes:
    """Serialize a RAGConfiguration from registered model ids plus the public config."""
    cfg = config or RagConfig()
    message = _pb.RAGConfiguration(embedding_model_id=embedding_model_id)
    if llm_model_id:
        message.llm_model_id = llm_model_id
    message.top_k = cfg.top_k
    message.chunk_size = cfg.chunk_size
    message.chunk_overlap = cfg.chunk_overlap
    if cfg.similarity_threshold is not None:
        message.score_threshold = cfg.similarity_threshold
    return message.SerializeToString()


def build_document(text: str, doc_id: str, metadata: Optional[dict]) -> bytes:
    """Serialize one RAGDocument."""
    doc = _pb.RAGDocument(id=doc_id, text=text)
    for key, value in (metadata or {}).items():
        doc.metadata[str(key)] = str(value)
    return doc.SerializeToString()


def build_query(
    question: str,
    options: Optional[RagQueryOptions],
) -> bytes:
    """Serialize a RAGQueryOptions from a question plus retrieval/generation overrides."""
    query = _pb.RAGQueryOptions(query=question)
    if options is not None:
        retrieval = options.retrieval
        if retrieval is not None:
            if retrieval.top_k is not None:
                query.retrieval.top_k = int(retrieval.top_k)
            if retrieval.similarity_threshold is not None:
                query.retrieval.score_threshold = retrieval.similarity_threshold
        generation = options.generation
        if generation is not None:
            query.generation.max_output_tokens = generation.max_output_tokens
            query.generation.temperature = generation.temperature
            query.generation.top_p = generation.top_p
            if generation.top_k is not None:
                query.generation.top_k = generation.top_k
            if generation.system_prompt is not None:
                query.generation.system_prompt = generation.system_prompt
            if generation.reasoning is not None:
                query.generation.reasoning.mode = int(generation.reasoning.mode)
                query.generation.reasoning.include_in_output = (
                    generation.reasoning.include_in_output
                )
    return query.SerializeToString()


def build_search(question: str, *, top_k: Optional[int] = None) -> bytes:
    """Serialize a RAGSearchRequest for the retrieval-only ABI."""
    request = _pb.RAGSearchRequest(query=question)
    if top_k is not None:
        request.retrieval.top_k = int(top_k)
    return request.SerializeToString()


def _match(pb: Any) -> Match:
    return Match(text=pb.text, score=pb.score, metadata=dict(pb.metadata))


def parse_search_response(raw: bytes) -> List[Match]:
    """Parse a RAGSearchResponse, raising when it carries an error.

    Raises:
        SDKException: the pipeline reported a failure.
    """
    pb = _pb.RAGSearchResponse()
    pb.ParseFromString(raw)
    if pb.HasField("error"):
        raise SDKException.from_proto(pb.error)
    return [_match(chunk) for chunk in pb.chunks]


def parse_result(raw: bytes, model: str) -> RagResult:
    """Parse a RAGResult, raising when it carries an error.

    Raises:
        SDKException: the pipeline reported a failure.
    """
    pb = _pb.RAGResult()
    pb.ParseFromString(raw)
    if pb.HasField("error"):
        raise SDKException.from_proto(pb.error)
    return _result_from_pb(pb, model)


def _result_from_pb(pb: Any, model: str) -> RagResult:
    # Metrics come only from commons TokenUsage — never from phase timings or
    # host-side tokens/generation_time division.
    usage = pb.usage
    return RagResult(
        answer=pb.answer,
        sources=[_match(chunk) for chunk in pb.retrieved_chunks],
        input_tokens=int(usage.input_tokens),
        output_tokens=int(usage.output_tokens),
        time_to_first_token_ms=float(usage.ttft_ms),
        tokens_per_second=float(usage.decode_tokens_per_second),
        request_id=pb.request_id,
        model=model,
    )


def parse_stats(raw: bytes) -> RagStats:
    """Parse a RAGStatistics message."""
    pb = _pb.RAGStatistics()
    pb.ParseFromString(raw)
    return RagStats(
        document_count=int(pb.indexed_documents),
        chunk_count=int(pb.indexed_chunks),
        index_size_bytes=int(pb.vector_store_size_bytes),
    )


def parse_stream_event(raw: bytes, model: str) -> Optional[RagEvent]:
    """Map one RAGStreamEvent onto the public event grammar, or None for internal stages.

    ``RAGStreamEventKind`` no longer has a CHUNK_RETRIEVED/CONTEXT_READY stage — commons'
    ``rac_rag_query_stream_proto`` only ever emitted TOKEN then a terminal COMPLETED (see
    ``rac_rag_proto_abi.cpp``'s ``on_token``/terminal ``emit()`` calls), so retrieval sources
    surface solely on the terminal event's ``result.retrieved_chunks`` — there was never a
    separate mid-stream retrieval signal to lose here.

    Raises:
        SDKException: the pipeline reported a failure mid-stream.
    """
    pb = _pb.RAGStreamEvent()
    pb.ParseFromString(raw)
    kind = int(pb.kind)
    if kind == _STREAM_TOKEN:
        return RagEvent(kind=RagEventKind.TOKEN, text=pb.token, token_kind=TokenKind.TEXT)
    if kind == _STREAM_COMPLETED and pb.HasField("result"):
        return RagEvent(
            kind=RagEventKind.COMPLETED, result=_result_from_pb(pb.result, model)
        )
    if kind == _STREAM_ERROR:
        if pb.HasField("error"):
            raise SDKException.from_proto(pb.error)
        raise SDKException.generation_failed("RAG stream failed")
    return None


def matches(result: RagResult) -> List[Match]:
    """The retrieved chunks of a result (used by retrieval-only search)."""
    return list(result.sources)


def thinking_suppressed(options: Optional[RagQueryOptions]) -> bool:
    """True when the caller asked for no thinking on this query."""
    generation = options.generation if options is not None else None
    return bool(generation and generation.reasoning and generation.reasoning.mode == ReasoningMode.OFF)
