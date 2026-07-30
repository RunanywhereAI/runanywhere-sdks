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
from .options import LlmOptions, RagConfig, ReasoningMode
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
    "parse_result",
    "parse_stats",
    "parse_stream_event",
    "require_native",
    "require_proto",
]

# runanywhere.v1.RAGStreamEventKind wire values, hardcoded so the event mapping does not
# depend on the optional protobuf runtime being importable.
_STREAM_CHUNK_RETRIEVED = 2
_STREAM_TOKEN = 4
_STREAM_COMPLETED = 5
_STREAM_ERROR = 6


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
        message.similarity_threshold = cfg.similarity_threshold
    if cfg.persist_path:
        message.index_path = cfg.persist_path
        message.persist_index = True
    return message.SerializeToString()


def build_document(text: str, doc_id: str, metadata: Optional[dict]) -> bytes:
    """Serialize one RAGDocument."""
    doc = _pb.RAGDocument(id=doc_id, text=text)
    for key, value in (metadata or {}).items():
        doc.metadata[str(key)] = str(value)
    return doc.SerializeToString()


def build_query(
    question: str,
    options: Optional[LlmOptions],
    *,
    top_k: Optional[int] = None,
    stream: bool = False,
) -> bytes:
    """Serialize a RAGQueryOptions from a question plus generation options."""
    query = _pb.RAGQueryOptions(question=question)
    if options is not None:
        query.generation.max_output_tokens = options.max_output_tokens
        query.generation.temperature = options.temperature
        query.generation.top_p = options.top_p
        if options.top_k is not None:
            query.generation.top_k = options.top_k
        if options.system_prompt is not None:
            query.generation.system_prompt = options.system_prompt
        if options.reasoning is not None:
            query.generation.reasoning.mode = int(options.reasoning.mode)
            query.generation.reasoning.include_in_output = options.reasoning.include_in_output
    if top_k is not None:
        query.retrieval_top_k = int(top_k)
    query.stream = stream
    return query.SerializeToString()


def _match(pb: Any) -> Match:
    return Match(text=pb.text, score=pb.similarity_score, metadata=dict(pb.metadata))


def parse_result(raw: bytes, model: str) -> RagResult:
    """Parse a RAGResult, raising when it carries an error.

    Raises:
        SDKException: the pipeline reported a failure.
    """
    pb = _pb.RAGResult()
    pb.ParseFromString(raw)
    if pb.error_code != 0:
        raise SDKException.generation_failed(
            pb.error_message or f"RAG query failed (code {pb.error_code})"
        )
    return _result_from_pb(pb, model)


def _result_from_pb(pb: Any, model: str) -> RagResult:
    generation_ms = float(pb.generation_time_ms)
    tokens = int(pb.completion_tokens)
    return RagResult(
        answer=pb.answer,
        sources=[_match(chunk) for chunk in pb.retrieved_chunks],
        input_tokens=int(pb.prompt_tokens),
        output_tokens=tokens,
        # The pipeline reports phase timings, not a first-token timestamp.
        time_to_first_token_ms=float(pb.retrieval_time_ms),
        tokens_per_second=(tokens / (generation_ms / 1000.0)) if generation_ms > 0 else 0.0,
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

    Raises:
        SDKException: the pipeline reported a failure mid-stream.
    """
    pb = _pb.RAGStreamEvent()
    pb.ParseFromString(raw)
    kind = int(pb.kind)
    if kind == _STREAM_CHUNK_RETRIEVED and pb.HasField("chunk"):
        return RagEvent(kind=RagEventKind.RETRIEVED, matches=[_match(pb.chunk)])
    if kind == _STREAM_TOKEN:
        return RagEvent(kind=RagEventKind.TOKEN, text=pb.token, token_kind=TokenKind.TEXT)
    if kind == _STREAM_COMPLETED and pb.HasField("result"):
        return RagEvent(
            kind=RagEventKind.COMPLETED, result=_result_from_pb(pb.result, model)
        )
    if kind == _STREAM_ERROR:
        raise SDKException.generation_failed(
            pb.error_message or f"RAG stream failed (code {pb.error_code})"
        )
    return None


def matches(result: RagResult) -> List[Match]:
    """The retrieved chunks of a result (used by retrieval-only search)."""
    return list(result.sources)


def thinking_suppressed(options: Optional[LlmOptions]) -> bool:
    """True when the caller asked for no thinking on this query."""
    return bool(options and options.reasoning and options.reasoning.mode == ReasoningMode.OFF)
