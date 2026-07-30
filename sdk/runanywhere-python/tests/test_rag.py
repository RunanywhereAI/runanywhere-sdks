"""The ``rag`` namespace, over an in-process implementation of the native ``rag_*`` byte ABI.

No native build and no models: the fake core parses and builds the exact proto messages
commons would, so config marshaling, ingest, search, query, streaming, stats and lifecycle are
all covered. Skips cleanly when the protobuf runtime (the ``[rag]`` extra) is absent.
"""
from __future__ import annotations

import os
import sys

_PKG_PARENT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PKG_PARENT not in sys.path:
    sys.path.insert(0, _PKG_PARENT)

import pytest  # noqa: E402

pytest.importorskip("google.protobuf", reason="RAG tests need the [rag] extra (protobuf)")

from fake_core import FakeCore  # noqa: E402

import runanywhere as ra  # noqa: E402
import runanywhere._native as _native  # noqa: E402
from runanywhere import (  # noqa: E402
    ErrorCode,
    LlmOptions,
    Match,
    ModelCategory,
    ModelRef,
    RagConfig,
    RagDocument,
    RagResult,
    RagSession,
    ReasoningMode,
    ReasoningOptions,
    SDKException,
)
from runanywhere._proto import rag_pb2 as pb  # noqa: E402
from runanywhere._runtime import runtime  # noqa: E402
from runanywhere.events import RagEventKind  # noqa: E402
from runanywhere.inputs import InferenceFramework  # noqa: E402
from runanywhere.results import ResolvedModel  # noqa: E402


class RagCore(FakeCore):
    """The shared fake core plus the RAG byte ABI."""

    def __init__(self, *, fail_query: bool = False) -> None:
        super().__init__()
        self.docs: list = []
        self.created_config = None
        self.last_query = None
        self.cancelled = False
        self.destroyed = False
        self._fail_query = fail_query

    def rag_session_create(self, config_bytes):
        config = pb.RAGConfiguration()
        config.ParseFromString(config_bytes)
        self.created_config = config
        return 7

    def rag_ingest(self, handle, document_bytes):
        document = pb.RAGDocument()
        document.ParseFromString(document_bytes)
        self.docs.append(document)
        stats = pb.RAGStatistics(indexed_documents=len(self.docs), indexed_chunks=len(self.docs))
        return stats.SerializeToString()

    def rag_query(self, handle, query_bytes):
        query = pb.RAGQueryOptions()
        query.ParseFromString(query_bytes)
        self.last_query = query
        result = pb.RAGResult()
        if self._fail_query:
            result.error_code = 130
            result.error_message = "no context"
            return result.SerializeToString()
        result.answer = "Paris"
        result.completion_tokens = 2
        result.generation_time_ms = 10
        result.retrieval_time_ms = 3
        result.retrieved_chunks.add(
            chunk_id="c0",
            text=(self.docs[0].text if self.docs else ""),
            similarity_score=0.9,
            rank=0,
        )
        return result.SerializeToString()

    def rag_query_stream(self, handle, query_bytes, on_event):
        chunk = pb.RAGStreamEvent(kind=pb.RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED)
        chunk.chunk.text = "context"
        chunk.chunk.similarity_score = 0.5
        on_event(chunk.SerializeToString())
        for token in ("Par", "is"):
            event = pb.RAGStreamEvent(kind=pb.RAG_STREAM_EVENT_KIND_TOKEN, token=token)
            if on_event(event.SerializeToString()) is False:
                return
        done = pb.RAGStreamEvent(kind=pb.RAG_STREAM_EVENT_KIND_COMPLETED)
        done.result.answer = "Paris"
        on_event(done.SerializeToString())

    def rag_stats(self, handle):
        return pb.RAGStatistics(
            indexed_documents=len(self.docs),
            indexed_chunks=len(self.docs),
            vector_store_size_bytes=64,
        ).SerializeToString()

    def rag_clear(self, handle):
        self.docs.clear()
        return pb.RAGStatistics().SerializeToString()

    def rag_cancel(self, handle):
        self.cancelled = True

    def rag_session_destroy(self, handle):
        self.destroyed = True


def _resolved(model_id: str) -> ResolvedModel:
    suffix = "onnx" if model_id == "minilm" else "gguf"
    kind = "embedder" if model_id == "minilm" else "llm"
    return ResolvedModel(id=model_id, type=kind, dir="/tmp", primary=f"/tmp/{model_id}.{suffix}")


@pytest.fixture()
def rag_core(monkeypatch, tmp_path):
    """An initialized SDK whose core speaks the RAG ABI, with resolution stubbed out."""
    core = RagCore()
    monkeypatch.setattr(_native, "get_core", lambda: core)
    monkeypatch.setattr(runtime, "resolve", lambda model_id, on_progress=None: _resolved(model_id))
    monkeypatch.setenv("RUNANYWHERE_HOME", str(tmp_path / "home"))
    runtime._core = None
    runtime._resident.clear()
    ra.initialize()
    try:
        yield core
    finally:
        ra.reset()


def _open(core: RagCore, llm: str | None = "qwen", config: RagConfig | None = None) -> RagSession:
    return ra.rag.open(ModelRef("minilm"), ModelRef(llm) if llm else None, config)


# --------------------------------------------------------------------------- open
def test_open_registers_both_models_and_marshals_config(rag_core) -> None:
    _open(rag_core, config=RagConfig(top_k=3, chunk_size=256, chunk_overlap=16))
    registered = {args[0]: args for name, args in rag_core.calls if name == "register_model"}
    assert registered["minilm"][1:] == (
        "/tmp/minilm.onnx",
        int(InferenceFramework.ONNX),
        int(ModelCategory.EMBEDDING),
    )
    assert registered["qwen"][1:] == (
        "/tmp/qwen.gguf",
        int(InferenceFramework.LLAMACPP),
        int(ModelCategory.LANGUAGE),
    )
    config = rag_core.created_config
    assert config.embedding_model_id == "minilm" and config.llm_model_id == "qwen"
    assert (config.top_k, config.chunk_size, config.chunk_overlap) == (3, 256, 16)


def test_open_retrieval_only_omits_the_answer_model(rag_core) -> None:
    _open(rag_core, llm=None)
    assert rag_core.created_config.llm_model_id == ""


def test_persist_path_turns_on_index_persistence(rag_core) -> None:
    _open(rag_core, config=RagConfig(persist_path="/tmp/index"))
    assert rag_core.created_config.index_path == "/tmp/index"
    assert rag_core.created_config.persist_index is True


def test_open_requires_the_rag_bindings(rag_core, monkeypatch) -> None:
    class NoRag:
        pass

    monkeypatch.setattr(runtime, "core", lambda: NoRag())
    with pytest.raises(SDKException) as error:
        _open(rag_core)
    assert error.value.code == ErrorCode.SERVICE_NOT_AVAILABLE
    assert "without the RAG backend" in str(error.value)


# --------------------------------------------------------------------------- ingest / query
def test_ingest_one_and_many(rag_core) -> None:
    session = _open(rag_core)
    session.ingest(RagDocument("Paris is the capital of France.", {"src": "unit"}))
    session.ingest([RagDocument("a"), RagDocument("b")])
    assert [doc.text for doc in rag_core.docs] == ["Paris is the capital of France.", "a", "b"]
    assert dict(rag_core.docs[0].metadata) == {"src": "unit"}


def test_query_returns_answer_sources_and_metrics(rag_core) -> None:
    session = _open(rag_core)
    session.ingest(RagDocument("Paris is the capital of France."))
    result = session.query(
        "Capital of France?",
        LlmOptions(
            max_output_tokens=64, top_k=4, reasoning=ReasoningOptions(mode=ReasoningMode.OFF)
        ),
    )
    assert isinstance(result, RagResult) and result.answer == "Paris"
    assert result.sources and isinstance(result.sources[0], Match)
    assert result.sources[0].score == pytest.approx(0.9)
    assert result.output_tokens == 2 and result.tokens_per_second > 0
    query = rag_core.last_query
    assert query.question == "Capital of France?"
    assert query.generation.max_output_tokens == 64 and query.generation.top_k == 4
    assert query.generation.reasoning.mode == int(ReasoningMode.OFF)


def test_search_returns_only_matches(rag_core) -> None:
    session = _open(rag_core)
    session.ingest(RagDocument("Paris is the capital of France."))
    matches = session.search("capital", top_k=2)
    assert [match.text for match in matches] == ["Paris is the capital of France."]
    assert rag_core.last_query.retrieval_top_k == 2
    # An answer model is loaded, so generation is capped rather than skipped.
    assert rag_core.last_query.generation.max_output_tokens == 1


def test_query_raises_on_a_pipeline_error(monkeypatch, tmp_path) -> None:
    core = RagCore(fail_query=True)
    monkeypatch.setattr(_native, "get_core", lambda: core)
    monkeypatch.setattr(runtime, "resolve", lambda model_id, on_progress=None: _resolved(model_id))
    monkeypatch.setenv("RUNANYWHERE_HOME", str(tmp_path / "home"))
    runtime._core = None
    ra.initialize()
    try:
        session = _open(core)
        with pytest.raises(SDKException) as error:
            session.query("anything")
        assert error.value.code == ErrorCode.GENERATION_FAILED
        assert "no context" in str(error.value)
    finally:
        ra.reset()


# --------------------------------------------------------------------------- streaming
def test_query_stream_follows_the_event_grammar(rag_core) -> None:
    session = _open(rag_core)
    events = list(session.query_stream("Capital?"))
    assert events[0].kind == RagEventKind.RETRIEVED
    assert [event.text for event in events if event.is_token] == ["Par", "is"]
    assert events[-1].is_completed and events[-1].result.answer == "Paris"


def test_query_stream_early_break_stops_the_pipeline(rag_core) -> None:
    session = _open(rag_core)
    seen = []
    stream = session.query_stream("Capital?")
    for event in stream:
        if event.is_token:
            seen.append(event.text)
            break
    stream.close()
    assert seen == ["Par"]


def test_aquery_and_aquery_stream(rag_core) -> None:
    import asyncio

    session = _open(rag_core)

    async def run():
        result = await session.aquery("Capital?")
        events = [event async for event in session.aquery_stream("Capital?")]
        return result, events

    result, events = asyncio.run(run())
    assert result.answer == "Paris"
    assert events[-1].is_completed


def test_aopen_aingest_and_asearch(rag_core) -> None:
    import asyncio

    async def run():
        session = await ra.rag.aopen(ModelRef("minilm"), ModelRef("qwen"))
        try:
            await session.aingest(RagDocument("Paris is the capital of France."))
            return await session.asearch("Capital?", top_k=1)
        finally:
            session.close()

    assert all(isinstance(match, Match) for match in asyncio.run(run()))


# --------------------------------------------------------------------------- lifecycle
def test_stats_clear_cancel_close(rag_core) -> None:
    session = _open(rag_core)
    session.ingest(RagDocument("x"))
    stats = session.stats()
    assert stats.document_count == 1 and stats.index_size_bytes == 64
    session.clear()
    assert rag_core.docs == []
    session.cancel()
    assert rag_core.cancelled is True
    session.close()
    assert rag_core.destroyed is True
    session.close()  # idempotent


def test_closed_session_rejects_operations(rag_core) -> None:
    session = _open(rag_core)
    session.close()
    with pytest.raises(SDKException) as error:
        session.query("x")
    assert error.value.code == ErrorCode.INVALID_STATE


def test_context_manager_closes_the_session(rag_core) -> None:
    with _open(rag_core) as session:
        session.ingest(RagDocument("x"))
    assert rag_core.destroyed is True


def test_document_from_file(tmp_path) -> None:
    path = tmp_path / "notes.txt"
    path.write_text("on-device", encoding="utf-8")
    document = RagDocument.file(str(path))
    assert document.text == "on-device"
    assert document.metadata == {"source": str(path)}
    assert document.id == "notes.txt"


def test_registry_ints_pin_the_c_abi() -> None:
    assert int(InferenceFramework.ONNX) == 0
    assert int(InferenceFramework.LLAMACPP) == 1
    assert int(ModelCategory.LANGUAGE) == 0
    assert int(ModelCategory.EMBEDDING) == 7
