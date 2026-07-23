"""Hermetic tests for the RAG facade — pure-Python, no native build, no models.

A ``FakeCore`` implements the native ``rag_*`` byte ABI in-process (parsing the exact proto
messages the real commons ABI would), so ingest/query/stream/stats/clear/close, model
registration, config marshaling, and the facade's dataclass shapes are all covered without a
compiled ``_core``. Skips cleanly when the protobuf runtime (the ``[rag]`` extra) is absent.
"""
from __future__ import annotations

import pytest

# The whole module needs the protobuf runtime to build/parse RAG proto bytes.
pytest.importorskip("google.protobuf", reason="RAG tests need the [rag] extra (protobuf)")

import runanywhere
from runanywhere import rag as ragmod
from runanywhere.errors import ErrorCode, SDKException
from runanywhere.rag import RagDocument, RagResult, RagSearchResult, RagSession, RagStatistics
from runanywhere.results import ResolvedModel
from runanywhere._proto import rag_pb2 as pb


# --------------------------------------------------------------------------- fake native core
class FakeCore:
    """In-process implementation of the native rag_* / register_model byte ABI."""

    def __init__(self, *, fail_query: bool = False):
        self.registered: dict[str, tuple] = {}
        self.docs: list[str] = []
        self.created_config: pb.RAGConfiguration | None = None
        self.last_query: pb.RAGQueryOptions | None = None
        self.cancelled = False
        self.destroyed = False
        self._fail_query = fail_query

    # register_model(id, path, framework:int, category:int)
    def register_model(self, mid, path, framework, category):
        self.registered[mid] = (path, framework, category)

    def rag_session_create(self, cfg_bytes):
        c = pb.RAGConfiguration()
        c.ParseFromString(cfg_bytes)
        self.created_config = c
        return 7

    def rag_ingest(self, handle, doc_bytes):
        d = pb.RAGDocument()
        d.ParseFromString(doc_bytes)
        self.docs.append(d.text)
        s = pb.RAGStatistics(indexed_documents=len(self.docs), indexed_chunks=len(self.docs))
        return s.SerializeToString()

    def rag_query(self, handle, q_bytes):
        q = pb.RAGQueryOptions()
        q.ParseFromString(q_bytes)
        self.last_query = q
        r = pb.RAGResult()
        if self._fail_query:
            r.error_code = 130
            r.error_message = "no context"
            return r.SerializeToString()
        r.answer = "Paris"
        r.context_used = self.docs[0] if self.docs else ""
        r.total_time_ms = 5
        r.retrieved_chunks.add(
            chunk_id="c0", text=(self.docs[0] if self.docs else ""), similarity_score=0.9, rank=0
        )
        return r.SerializeToString()

    def rag_query_stream(self, handle, q_bytes, on_event):
        for tok in ("Par", "is"):
            e = pb.RAGStreamEvent(kind=pb.RAG_STREAM_EVENT_KIND_TOKEN, token=tok)
            if on_event(e.SerializeToString()) is False:
                return
        done = pb.RAGStreamEvent(kind=pb.RAG_STREAM_EVENT_KIND_COMPLETED)
        done.result.answer = "Paris"
        on_event(done.SerializeToString())

    def rag_stats(self, handle):
        return pb.RAGStatistics(indexed_documents=len(self.docs)).SerializeToString()

    def rag_clear(self, handle):
        self.docs.clear()
        return pb.RAGStatistics(indexed_documents=0).SerializeToString()

    def rag_cancel(self, handle):
        self.cancelled = True

    def rag_session_destroy(self, handle):
        self.destroyed = True


def _resolve(model_id: str) -> ResolvedModel:
    ext = "onnx" if model_id == "minilm" else "gguf"
    kind = "embedder" if model_id == "minilm" else "llm"
    return ResolvedModel(id=model_id, type=kind, dir="/tmp", primary=f"/tmp/{model_id}.{ext}")


def _session(core: FakeCore, llm: str | None = "qwen", **cfg) -> RagSession:
    return ragmod.create_session(core, "minilm", llm, cfg, _resolve)


# --------------------------------------------------------------------------- proto round-trip
def test_proto_round_trip():
    cfg = pb.RAGConfiguration(embedding_model_id="minilm", llm_model_id="qwen", top_k=3)
    parsed = pb.RAGConfiguration()
    parsed.ParseFromString(cfg.SerializeToString())
    assert parsed.embedding_model_id == "minilm" and parsed.top_k == 3


# --------------------------------------------------------------------------- create_session
def test_create_session_registers_models_and_config():
    core = FakeCore()
    _session(core, top_k=3, chunk_size=256)
    # embedder -> ONNX(0)/EMBEDDING(7); llm(.gguf) -> LLAMACPP(1)/LANGUAGE(0)
    assert core.registered["minilm"] == ("/tmp/minilm.onnx", 0, 7)
    assert core.registered["qwen"] == ("/tmp/qwen.gguf", 1, 0)
    assert core.created_config.embedding_model_id == "minilm"
    assert core.created_config.llm_model_id == "qwen"
    assert core.created_config.top_k == 3 and core.created_config.chunk_size == 256


def test_create_session_embed_only_omits_llm():
    core = FakeCore()
    _session(core, llm=None)
    assert "qwen" not in core.registered
    assert core.created_config.llm_model_id == ""


def test_llm_framework_from_extension():
    assert ragmod._framework_for_llm("/m/x.gguf") == ragmod._FRAMEWORK_LLAMACPP
    assert ragmod._framework_for_llm("/m/x.onnx") == ragmod._FRAMEWORK_ONNX
    assert ragmod._framework_for_llm("/m/x.bin") == ragmod._FRAMEWORK_LLAMACPP  # default


# --------------------------------------------------------------------------- ingest / query
def test_ingest_and_query():
    core = FakeCore()
    sess = _session(core)
    stats = sess.ingest("Paris is the capital of France.")
    assert isinstance(stats, RagStatistics) and stats.indexed_documents == 1
    res = sess.query("Capital of France?", top_k=4, disable_thinking=True)
    assert isinstance(res, RagResult) and res.answer == "Paris"
    assert res.retrieved_chunks and isinstance(res.retrieved_chunks[0], RagSearchResult)
    assert res.retrieved_chunks[0].similarity_score == pytest.approx(0.9)
    # options actually reached the native RAGQueryOptions
    assert core.last_query.question == "Capital of France?"
    assert core.last_query.disable_thinking is True and core.last_query.top_k == 4


def test_ingest_ragdocument_carries_metadata():
    core = FakeCore()
    sess = _session(core)
    sess.ingest(RagDocument(text="hello", id="d1", metadata={"src": "unit"}))
    assert core.docs == ["hello"]


def test_ingest_many():
    core = FakeCore()
    sess = _session(core)
    stats = sess.ingest_many(["a", "b", RagDocument(text="c")])
    assert stats.indexed_documents == 3 and core.docs == ["a", "b", "c"]


def test_query_raises_on_error_code():
    core = FakeCore(fail_query=True)
    sess = _session(core)
    with pytest.raises(SDKException) as ei:
        sess.query("anything")
    assert ei.value.code == ErrorCode.GENERATION_FAILED and "no context" in str(ei.value)


# --------------------------------------------------------------------------- streaming
def test_query_stream_events():
    core = FakeCore()
    sess = _session(core)
    events = list(sess.query_stream("Capital?"))
    tokens = [e.token for e in events if e.is_token]
    finals = [e for e in events if e.is_final]
    assert tokens == ["Par", "is"]
    assert len(finals) == 1 and finals[0].result is not None and finals[0].result.answer == "Paris"


def test_query_stream_early_break_stops():
    core = FakeCore()
    sess = _session(core)
    seen = []
    for ev in sess.query_stream("Capital?"):
        seen.append(ev.token)
        break  # closing the generator must set the stop flag; no hang
    assert seen == ["Par"]


# --------------------------------------------------------------------------- index + lifecycle
def test_stats_clear_cancel_close():
    core = FakeCore()
    sess = _session(core)
    sess.ingest("x")
    assert sess.stats().indexed_documents == 1
    assert sess.clear().indexed_documents == 0
    sess.cancel()
    assert core.cancelled is True
    sess.close()
    assert core.destroyed is True
    sess.close()  # idempotent


def test_closed_session_rejects_ops():
    core = FakeCore()
    sess = _session(core)
    sess.close()
    with pytest.raises(SDKException) as ei:
        sess.query("x")
    assert ei.value.code == ErrorCode.INVALID_STATE


def test_context_manager_closes():
    core = FakeCore()
    with _session(core) as sess:
        sess.ingest("x")
    assert core.destroyed is True


# --------------------------------------------------------------------------- guards
def test_native_without_rag_raises_hint():
    class NoRagCore:
        pass

    with pytest.raises(SDKException) as ei:
        ragmod.create_session(NoRagCore(), "minilm", None, {}, _resolve)
    assert ei.value.code == ErrorCode.SERVICE_NOT_AVAILABLE
    assert "without the RAG backend" in str(ei.value)


# --------------------------------------------------------------------------- client.create_rag
def test_client_create_rag_wires_resolve(monkeypatch):
    core = FakeCore()
    ra = runanywhere.RunAnywhere()
    ra._initialized = True
    ra._core = core
    monkeypatch.setattr("runanywhere.client.resolve_model", lambda mid, d, p: _resolve(mid))
    sess = ra.create_rag("minilm", llm_model="qwen", top_k=2)
    assert isinstance(sess, RagSession)
    assert core.created_config.top_k == 2
    assert sess in ra._models  # tracked so shutdown() closes it


def test_client_create_rag_rejects_remote_embedder():
    ra = runanywhere.RunAnywhere()
    ra._initialized = True
    ra._core = FakeCore()
    with pytest.raises(SDKException):
        ra.create_rag("sentence-transformers/all-MiniLM-L6-v2")  # HF repo -> unsupported embedder


# --------------------------------------------------------------------------- top-level exports
def test_rag_types_exported():
    for name in ("RagSession", "RagDocument", "RagResult", "RagSearchResult", "RagStatistics", "RagStreamEvent"):
        assert hasattr(runanywhere, name)
