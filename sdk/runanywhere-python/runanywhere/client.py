"""The public ``RunAnywhere`` client — the single entry point over the native core.

Mirrors the Electron SDK facade (``RunAnywhere.ts``) but as an instantiable client so
tests and multi-tenant hosts can hold independent handles. The compiled ``_core``
extension is brought up lazily (via :func:`runanywhere._native.get_core`) and reference
counted process-wide: the first client to initialize starts the core, the last to shut
down tears it down. Each client tracks the models it loaded (weakly) and unloads them on
its own shutdown.
"""

from __future__ import annotations

import os
import threading
import weakref
from typing import TYPE_CHECKING, Callable

from . import _native
from .catalog import is_catalog_id
from .chat import Chat
from .download import assert_remote_supported, model_status, resolve_model
from .errors import SDKException
from .events import (
    EventBus,
    InitializedEvent,
    ModelLoadedEvent,
    ServicesReadyEvent,
    ShutdownEvent,
    bus,
)
from .models import Embedder, LLMModel, STTModel, TTSVoice, Vad, VLMModel
from .results import DownloadProgress, ModelStatus, ResolvedModel
from .voice_agent import VoiceAgent

if TYPE_CHECKING:
    from types import ModuleType

    from .rag import RagSession

# Process-wide native lifecycle. The native core is a single shared runtime, so multiple
# RunAnywhere clients share one instance: `_init_count` tracks how many clients are up and
# `_native_up` guards the one-time `core.initialize` / `core.shutdown`. `_state_lock` is an
# RLock so a load path can re-enter (e.g. `get_core()` under an already-held lock).
_state_lock = threading.RLock()
_init_count = 0
_native_up = False
# Phase-2 "services" bring-up flag (process-wide), mirroring the Electron facade's
# areServicesReady. A local no-op seam today for future backend auth/telemetry.
_services_ready = False

# A default so `os.path.join(base, "secure")` mirrors the Electron facade's default secure
# dir when the caller does not override it.
_HOME = os.path.join(os.path.expanduser("~"), ".runanywhere")


def _validate_secure_key(key: str) -> str:
    """Reject secure-store keys that could escape the store directory.

    The native adapter maps each key onto a file ``<store_dir>/<key>``, and a key containing a
    path separator, ``..``, or an absolute/drive path would read/write/delete an arbitrary file
    (path traversal). The secure store is a flat key-value namespace, so only simple names are
    valid. Enforced here at the public boundary; the native adapters validate too (defense in
    depth). Returns the key unchanged when valid.
    """
    if not isinstance(key, str) or not key:
        raise SDKException.invalid_input("secure store key must be a non-empty string")
    if (
        "/" in key
        or "\\" in key
        or key in (".", "..")
        or os.path.isabs(key)
        or (os.altsep and os.altsep in key)
        or "\x00" in key
    ):
        raise SDKException.invalid_input(
            f"invalid secure store key {key!r}: must be a simple name "
            "(no path separators, '..', absolute paths, or NUL)"
        )
    return key


class RunAnywhere:
    """On-device AI client: load models, generate, chat, run voice turns.

    A client is inert until :meth:`initialize` (which brings the shared native core up,
    ref-counted across clients). Use it as a context manager for guaranteed teardown::

        with RunAnywhere() as ra:
            llm = ra.load_llm("smollm2-360m")
            print(llm.generate_text("Hello"))
    """

    def __init__(
        self,
        *,
        secure_dir: str | None = None,
        base_dir: str | None = None,
        environment: str = "production",
    ) -> None:
        self._secure_dir = secure_dir
        self._base_dir = base_dir
        self._environment = environment
        self._initialized = False
        # The native module handle, resolved on initialize(); None while down.
        self._core: "ModuleType | None" = None
        # Weakly track every model/voice this client loaded so shutdown can unload them
        # without keeping them alive (or double-unloading a model the caller already did).
        self._models: "weakref.WeakSet[object]" = weakref.WeakSet()

    # -- properties ----------------------------------------------------------
    @property
    def version(self) -> str:
        """The bundled commons/runtime version (requires initialize())."""
        return self._require_core().version()

    def available_backends(self) -> list[str]:
        """The engine backends compiled into this build, e.g. ``['llamacpp', 'onnx', 'sherpa']``.

        Does not require :meth:`initialize` — it reflects the wheel's build config, i.e.
        compile-time availability only. A listed engine can still refuse registration at runtime
        (``'neurt'`` is Apple-only, so a non-Apple build lists it but never routes to it). The
        plugin registry auto-selects the highest-priority *registered* backend for each modality,
        so an Android QHexRT-linked build reports ``'qhexrt'`` here (priority 150) and
        ``load_llm`` routes to it for HNPU bundles. Windows Snapdragon HNPU is not
        available yet — desktop wheels report CPU backends (llamacpp/onnx/sherpa).
        """
        return list(_native.get_core().backends())

    @property
    def is_initialized(self) -> bool:
        """True once this client has completed :meth:`initialize` (and not shut down)."""
        return self._initialized

    @property
    def are_services_ready(self) -> bool:
        """True once Phase-2 services bring-up has completed (process-wide)."""
        return _services_ready

    @property
    def events(self) -> EventBus:
        """The process-wide lifecycle + telemetry event bus (subscribe with ``.on``)."""
        return bus

    @property
    def environment(self) -> str:
        """The configured deployment environment."""
        return self._environment

    # -- lifecycle -----------------------------------------------------------
    def initialize(self) -> "RunAnywhere":
        """Bring the runtime up. Idempotent per instance; ref-counted process-wide.

        The first client to initialize loads the native core, calls
        ``core.initialize(secure_dir, base_dir)`` and emits :class:`InitializedEvent`
        (followed by :class:`ServicesReadyEvent`). Later clients only bump the ref-count.
        Returns ``self`` so the call can be chained.
        """
        global _init_count, _native_up
        # Resolve host paths outside the lock (no shared state). The per-client
        # idempotency check MUST run under `_state_lock` so two concurrent
        # initialize() calls on the same instance cannot both bump `_init_count`.
        base = self._base_dir if self._base_dir is not None else _HOME
        secure = self._secure_dir if self._secure_dir is not None else os.path.join(base, "secure")

        first = False
        with _state_lock:
            if self._initialized:
                return self
            core = _native.get_core()
            if not _native_up:
                core.initialize(secure, base)
                _native_up = True
                first = True
            _init_count += 1
            self._core = core
            self._initialized = True

        # Emit outside the lock so a listener can't deadlock the lifecycle. Only the client
        # that actually started the native core announces bring-up, then runs Phase 2.
        if first:
            bus.emit(InitializedEvent())
            self.complete_services_initialization()
        return self

    def complete_services_initialization(self) -> None:
        """Mark Phase-2 services ready. Idempotent; emits :class:`ServicesReadyEvent` once.

        Local-only no-op today: no network auth or remote telemetry is performed.
        Kept as an explicit lifecycle seam mirroring the other SDKs' Phase-2 hook.
        """
        global _services_ready
        emit = False
        with _state_lock:
            if not _services_ready:
                _services_ready = True
                emit = True
        if emit:
            bus.emit(ServicesReadyEvent())

    def shutdown(self) -> None:
        """Tear this client down. Idempotent; the last client shuts the native core down.

        Unloads every model this client loaded, decrements the process-wide ref-count, and
        — when it reaches zero — calls ``core.shutdown()`` and emits :class:`ShutdownEvent`.
        """
        global _init_count, _native_up, _services_ready
        # Claim ownership of this client's teardown under the lock so concurrent
        # shutdown() calls cannot double-decrement `_init_count`.
        with _state_lock:
            if not self._initialized:
                return
            self._initialized = False
            models = list(self._models)
            self._models.clear()
            core = self._core
            self._core = None
            if _init_count > 0:
                _init_count -= 1
            last = _init_count == 0 and _native_up
            if last:
                _native_up = False
                _services_ready = False

        # Unload outside the lock (best-effort; a failed unload must not leak the ref-count).
        for model in models:
            unload = getattr(model, "unload", None) or getattr(model, "close", None)
            if unload is not None:
                try:
                    unload()
                except Exception:
                    # A single model failing to unload must not block core teardown.
                    pass

        if last and core is not None:
            core.shutdown()
            bus.emit(ShutdownEvent())

    def __enter__(self) -> "RunAnywhere":
        return self.initialize()

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        self.shutdown()

    # -- model loading -------------------------------------------------------
    def load_llm(
        self,
        id_or_path: str,
        *,
        id: str | None = None,
        name: str | None = None,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
    ) -> LLMModel:
        """Load an LLM by catalog id (auto-downloaded if missing) or local path."""
        core = self._require_core()
        resolved = resolve_model(id_or_path, dir, on_progress)
        handle = core.load_model(resolved.primary, id, name)
        model = LLMModel(core, handle)
        self._register(model)
        bus.emit(ModelLoadedEvent(modality="llm", id=id_or_path))
        return model

    def load_vlm(
        self,
        id_or_path: str,
        mmproj_path: str | None = None,
        *,
        id: str | None = None,
        name: str | None = None,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
    ) -> VLMModel:
        """Load a vision-language model. ``mmproj_path`` overrides the auto-resolved mmproj."""
        core = self._require_core()
        resolved = resolve_model(id_or_path, dir, on_progress)
        mmproj = mmproj_path if mmproj_path is not None else resolved.mmproj
        if not mmproj:
            raise SDKException.validation_failed(
                field_path="mmproj",
                message="load_vlm needs an mmproj path (or a catalog id that includes one)",
            )
        handle = core.load_vlm_model(resolved.primary, mmproj, id, name)
        model = VLMModel(core, handle)
        self._register(model)
        bus.emit(ModelLoadedEvent(modality="vlm", id=id_or_path))
        return model

    def load_embedder(
        self,
        id_or_path: str,
        *,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
    ) -> Embedder:
        """Load a text embedder by catalog id or local path (URL/HF sources unsupported)."""
        core = self._require_core()
        assert_remote_supported(id_or_path, "embedder")
        resolved = resolve_model(id_or_path, dir, on_progress)
        handle = core.load_embedding_model(resolved.primary)
        model = Embedder(core, handle)
        self._register(model)
        bus.emit(ModelLoadedEvent(modality="embedder", id=id_or_path))
        return model

    def load_stt(
        self,
        id_or_path: str,
        *,
        id: str | None = None,
        name: str | None = None,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
    ) -> STTModel:
        """Load a speech-to-text model by catalog id or local path."""
        core = self._require_core()
        assert_remote_supported(id_or_path, "stt")
        resolved = resolve_model(id_or_path, dir, on_progress)
        handle = core.load_stt_model(resolved.primary, id, name)
        model = STTModel(core, handle)
        self._register(model)
        bus.emit(ModelLoadedEvent(modality="stt", id=id_or_path))
        return model

    def load_tts(
        self,
        id_or_path: str,
        *,
        id: str | None = None,
        name: str | None = None,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
    ) -> TTSVoice:
        """Load a text-to-speech voice by catalog id or local path."""
        core = self._require_core()
        assert_remote_supported(id_or_path, "tts")
        resolved = resolve_model(id_or_path, dir, on_progress)
        handle = core.load_tts_voice(resolved.primary, id, name)
        voice = TTSVoice(core, handle)
        self._register(voice)
        bus.emit(ModelLoadedEvent(modality="tts", id=id_or_path))
        return voice

    # -- downloads -----------------------------------------------------------
    def download_model(
        self,
        id_or_path: str,
        *,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
    ) -> ResolvedModel:
        """Download a catalog model (or resolve a local path) to concrete file paths.

        Does not require initialize() — downloading is pure host I/O.
        """
        return resolve_model(id_or_path, dir, on_progress)

    def model_status(self) -> dict[str, ModelStatus]:
        """Downloaded state + on-disk size for every catalog model.

        Scans the models root where :func:`resolve_model` downloads (``models_root()``),
        not this client's ``base_dir`` (which is only the native runtime's base path).
        """
        return model_status()

    # -- factories -----------------------------------------------------------
    def create_chat(self, llm: LLMModel, system: str | None = None) -> Chat:
        """Start a multi-turn chat session over a loaded LLM (keeps history)."""
        return Chat(llm, system)

    def create_voice_agent(
        self,
        stt: STTModel,
        llm: LLMModel,
        tts: TTSVoice,
        system_prompt: str | None = None,
    ) -> VoiceAgent:
        """Compose loaded STT + LLM + TTS models into a voice-turn pipeline."""
        return VoiceAgent(stt, llm, tts, system_prompt)

    def create_vad(self, threshold: float | None = None) -> Vad:
        """Create a voice-activity detector (built-in energy VAD; requires initialize())."""
        core = self._require_core()
        handle = core.create_vad(threshold)
        vad = Vad(core, handle)
        self._register(vad)
        return vad

    def create_rag(
        self,
        embedding_model: str,
        llm_model: str | None = None,
        *,
        dir: str | None = None,
        on_progress: Callable[[DownloadProgress], None] | None = None,
        **config: object,
    ) -> "RagSession":
        """Open a RAG (talk-to-your-documents) session over an embedder (+ optional LLM).

        ``embedding_model`` / ``llm_model`` are catalog ids or local paths (embedders can't be
        loaded from a URL/HF repo). The models are registered into the native model registry so
        commons can resolve them, then a session is created. Extra keyword config maps onto
        ``RAGConfiguration`` — e.g. ``top_k``, ``chunk_size``, ``chunk_overlap``,
        ``similarity_threshold``, ``prompt_template``, ``index_path``, ``persist_index``,
        ``rerank_results``, ``reranker_model_id``. Requires the ``[rag]`` extra (protobuf).

        Use it as a context manager, or ``close()`` it, to release the session deterministically
        (``shutdown()`` also closes any session this client opened)::

            with ra.create_rag("minilm", llm_model="qwen2.5-0.5b") as rag:
                rag.ingest("Paris is the capital of France.")
                print(rag.query("Capital of France?").answer)
        """
        core = self._require_core()
        assert_remote_supported(embedding_model, "embedder")
        from . import rag as _rag

        def _resolve(model_id: str) -> ResolvedModel:
            return resolve_model(model_id, dir, on_progress)

        session = _rag.create_session(core, embedding_model, llm_model, config, _resolve)
        self._register(session)
        return session

    # -- model registry ------------------------------------------------------
    def register_model(
        self, model_id: str, local_path: str, *, framework: int, category: int
    ) -> None:
        """Register a model id → path into the global registry (C ABI enums)."""
        self._require_core().register_model(model_id, local_path, framework, category)

    def get_model(self, model_id: str) -> dict | None:
        """Look up a registered model by id, or None if absent."""
        return self._require_core().get_model(model_id)

    def list_models(self) -> list[dict]:
        """List all models currently in the global registry."""
        return list(self._require_core().list_models())

    def remove_model(self, model_id: str) -> None:
        """Remove a model from the global registry."""
        self._require_core().remove_model(model_id)

    # -- secure store --------------------------------------------------------
    def secure_set(self, key: str, value: str) -> None:
        """Store a key-value pair in the platform secure store (requires initialize()).

        On Windows the value is DPAPI-protected. On macOS/Linux the store is a
        mode-0600 plaintext file under the secure directory — not encrypted.
        """
        self._require_core().secure_set(_validate_secure_key(key), value)

    def secure_get(self, key: str) -> str | None:
        """Read a value from the secure store, or None if absent."""
        return self._require_core().secure_get(_validate_secure_key(key))

    def secure_delete(self, key: str) -> None:
        """Delete a value from the secure store (a missing key is a no-op)."""
        self._require_core().secure_delete(_validate_secure_key(key))

    # -- internals -----------------------------------------------------------
    def _require_core(self) -> "ModuleType":
        """Return the live native core, or raise if this client is not initialized."""
        core = self._core
        if not self._initialized or core is None:
            raise SDKException.not_initialized("RunAnywhere")
        return core

    def _register(self, model: object) -> None:
        """Track a loaded model weakly so shutdown can unload it."""
        self._models.add(model)


__all__ = ["RunAnywhere"]
