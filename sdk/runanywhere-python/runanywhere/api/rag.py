"""The ``rag`` namespace: talk to your documents, one session per corpus."""

from __future__ import annotations

import asyncio
from typing import Any, AsyncIterator, Iterator, List, Optional, Sequence, Union

from .. import _rag_bridge as bridge
from .._runtime import runtime
from .._streaming import aiter_tokens, iter_tokens
from ..errors import SDKException
from ..events import RagEvent, RagEventKind
from ..inputs import ModelCategory, ModelRef, RagDocument
from ..options import LlmOptions, RagConfig
from ..results import Match, RagResult, RagStats

__all__ = ["RagSession", "rag"]

Documents = Union[RagDocument, Sequence[RagDocument]]


class RagSession:
    """A live RAG session: ingest documents, then search or ask grounded questions.

    Open one with :meth:`Rag.open`. Sessions are independent — two corpora can be open at
    once. Close it (or use it as a context manager) to release the native session.
    """

    def __init__(self, core: Any, handle: int, model: str) -> None:
        self._core = core
        self._handle = handle
        self._model = model
        self._closed = False

    def _live(self) -> Any:
        if self._closed:
            raise SDKException.invalid_state("RAG session is closed")
        return self._core

    def ingest(self, documents: Documents) -> None:
        """Index one document or a batch of them.

        Raises:
            SDKException: the session is closed or indexing fails.
        """
        core = self._live()
        items = [documents] if isinstance(documents, RagDocument) else list(documents)
        for doc in items:
            payload = bridge.build_document(doc.text, doc.id, doc.metadata)
            core.rag_ingest(self._handle, payload)

    async def aingest(self, documents: Documents) -> None:
        """Async form of :meth:`ingest` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, lambda: self.ingest(documents))

    def search(self, query: str, top_k: Optional[int] = None) -> List[Match]:
        """Retrieve the chunks most similar to ``query`` without generating an answer.

        Uses the commons retrieval-only ABI (``rac_rag_search_proto``).

        Raises:
            SDKException: the session is closed, search is unavailable, or retrieval fails.
        """
        core = self._live()
        bridge.require_search(core)
        payload = bridge.build_search(query, top_k=top_k)
        return bridge.parse_search_response(core.rag_search(self._handle, payload))

    async def asearch(self, query: str, top_k: Optional[int] = None) -> List[Match]:
        """Async form of :meth:`search` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self.search(query, top_k))

    def query(self, question: str, options: Optional[LlmOptions] = None) -> RagResult:
        """Answer ``question`` from the indexed documents.

        Raises:
            SDKException: the session is closed or generation fails.
        """
        core = self._live()
        payload = bridge.build_query(question, options)
        return bridge.parse_result(core.rag_query(self._handle, payload), self._model)

    async def aquery(self, question: str, options: Optional[LlmOptions] = None) -> RagResult:
        """Async form of :meth:`query` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self.query(question, options))

    def query_stream(
        self, question: str, options: Optional[LlmOptions] = None
    ) -> Iterator[RagEvent]:
        """Stream retrieved chunks, then answer tokens, then the terminal result.

        Commons does not emit ``CHUNK_RETRIEVED`` from ``rac_rag_query_stream_proto`` today,
        so in practice the stream is token deltas then ``completed``, whose result carries
        the sources. The ``retrieved`` branch lights up when commons starts emitting it. The
        streamed ``RAGResult`` also leaves ``prompt_tokens``/``completion_tokens`` at 0, so
        the terminal result's token counts read 0 — :meth:`query` reports them.

        Raises:
            SDKException: the session is closed or generation fails.
        """
        core = self._live()
        payload = bridge.build_query(question, options, stream=True)
        handle = self._handle

        def native_call(on_event) -> None:
            core.rag_query_stream(handle, payload, on_event)

        for raw in iter_tokens(native_call, on_stop=self.cancel):
            event = bridge.parse_stream_event(raw, self._model)
            if event is not None:
                yield event

    async def aquery_stream(
        self, question: str, options: Optional[LlmOptions] = None
    ) -> AsyncIterator[RagEvent]:
        """Async form of :meth:`query_stream`."""
        core = self._live()
        payload = bridge.build_query(question, options, stream=True)
        handle = self._handle

        def native_call(on_event) -> None:
            core.rag_query_stream(handle, payload, on_event)

        inner = aiter_tokens(native_call, on_stop=self.cancel)
        try:
            async for raw in inner:
                event = bridge.parse_stream_event(raw, self._model)
                if event is not None:
                    yield event
        finally:
            await inner.aclose()

    def cancel(self) -> None:
        """Stop an in-flight query (safe from another thread)."""
        if not self._closed:
            self._core.rag_cancel(self._handle)

    def stats(self) -> RagStats:
        """Snapshot the index counters."""
        return bridge.parse_stats(self._live().rag_stats(self._handle))

    def clear(self) -> None:
        """Drop every indexed chunk."""
        self._live().rag_clear(self._handle)

    def close(self) -> None:
        """Destroy the native session. Idempotent."""
        if self._closed:
            return
        self._closed = True
        self._core.rag_session_destroy(self._handle)

    def __enter__(self) -> "RagSession":
        return self

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        self.close()


class Rag:
    """RAG session factory."""

    def open(
        self,
        embedding_model: ModelRef,
        llm_model: Optional[ModelRef] = None,
        config: Optional[RagConfig] = None,
    ) -> RagSession:
        """Open a session over an embedding model, optionally with an answer model.

        Both models are downloaded, registered and resolved by the SDK. Pass no
        ``llm_model`` for a retrieval-only session.

        Raises:
            SDKException: a model cannot be resolved, or this build has no RAG backend.

        Example:
            >>> with runanywhere.rag.open(ModelRef("minilm"), ModelRef("smollm2-135m")) as session:
            ...     session.ingest(RagDocument("Paris is the capital of France."))
        """
        core = runtime.core()
        bridge.require_proto()
        bridge.require_native(core)

        embedding = runtime.resolve(embedding_model.id)
        runtime.register_native(embedding, ModelCategory.EMBEDDING)
        answer_id = ""
        if llm_model is not None:
            answer = runtime.resolve(llm_model.id)
            runtime.register_native(answer, ModelCategory.LANGUAGE)
            answer_id = answer.id
        payload = bridge.build_config(embedding.id, answer_id or None, config)
        handle = core.rag_session_create(payload)
        return RagSession(core, handle, answer_id)

    async def aopen(
        self,
        embedding_model: ModelRef,
        llm_model: Optional[ModelRef] = None,
        config: Optional[RagConfig] = None,
    ) -> RagSession:
        """Async form of :meth:`open` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(
            None, lambda: self.open(embedding_model, llm_model, config)
        )


#: The ``rag`` namespace.
rag = Rag()
