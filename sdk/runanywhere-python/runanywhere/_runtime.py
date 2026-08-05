"""Internal process-wide runtime: native bring-up plus the resident-model registry.

The public namespaces never touch ``_core`` directly — they ask the runtime for the model
they need. One model per category is resident at a time; asking for a different id in the
same category swaps it, which is what ``models.state()`` reports and ``models.unload()``
clears. Nothing here is public API.
"""

from __future__ import annotations

import logging
import os
import shutil
import threading
import uuid
from typing import Callable, Dict, Optional, Tuple

from . import _native
from ._handles import (
    DiarizationModel,
    DiffusionModel,
    Embedder,
    LLMModel,
    STTModel,
    SegmentationModel,
    TTSVoice,
    Vad,
    VLMModel,
    VoiceAgent,
)
from .catalog import CATALOG, is_catalog_id
from .download import assert_remote_supported, model_status, models_root, resolve_model
from .errors import SDKException
from .events import SdkEvent, SdkEventKind, bus
from .inputs import InferenceFramework, ModelCategory
from .options import Environment, LoadOptions
from .results import DownloadProgress, ModelInfo, ModelsState, ResolvedModel

__all__ = ["Runtime", "runtime"]

_LOG = logging.getLogger("runanywhere")


def _home() -> str:
    """The RunAnywhere home directory, overridable with ``RUNANYWHERE_HOME``."""
    return os.environ.get("RUNANYWHERE_HOME") or os.path.join(
        os.path.expanduser("~"), ".runanywhere"
    )


# Catalog model types → the category the registry and ModelsState report.
_CATEGORY_FOR_TYPE = {
    "llm": ModelCategory.LANGUAGE,
    "vlm": ModelCategory.VISION,
    "embedder": ModelCategory.EMBEDDING,
    "stt": ModelCategory.SPEECH_RECOGNITION,
    "tts": ModelCategory.SPEECH_SYNTHESIS,
}

_FRAMEWORK_FOR_CATEGORY = {
    ModelCategory.LANGUAGE: InferenceFramework.LLAMACPP,
    ModelCategory.VISION: InferenceFramework.LLAMACPP,
    ModelCategory.EMBEDDING: InferenceFramework.ONNX,
    ModelCategory.SPEECH_RECOGNITION: InferenceFramework.SHERPA,
    ModelCategory.SPEECH_SYNTHESIS: InferenceFramework.SHERPA,
    ModelCategory.VOICE_ACTIVITY_DETECTION: InferenceFramework.BUILTIN,
    ModelCategory.SPEAKER_DIARIZATION: InferenceFramework.ONNX,
    ModelCategory.SEMANTIC_SEGMENTATION: InferenceFramework.ONNX,
    ModelCategory.IMAGE_GENERATION: InferenceFramework.COREML,
}


class Runtime:
    """Owns the native core's lifecycle and the resident model per category."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._core: object | None = None
        self._environment = Environment.PRODUCTION
        self._device_id: Optional[str] = None
        # category -> (model id, handle wrapper)
        self._resident: Dict[ModelCategory, Tuple[str, object]] = {}

    # -- lifecycle -----------------------------------------------------------
    def initialize(
        self,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        environment: Environment = Environment.PRODUCTION,
    ) -> None:
        """Bring the native runtime up. Idempotent."""
        with self._lock:
            if self._core is not None:
                return
            core = _native.get_core()
            base = _home()
            core.initialize(os.path.join(base, "secure"), base)
            self._core = core
            self._environment = environment
        if api_key or base_url:
            # Never imply a control plane that is not wired: this SDK performs no auth,
            # device registration or telemetry (see the bridge gaps in AGENTS.md).
            _LOG.warning(
                "runanywhere.initialize: api_key/base_url are accepted for signature parity "
                "but this SDK has no control-plane client — no auth, device registration or "
                "telemetry is performed"
            )
        bus.emit(SdkEvent(kind=SdkEventKind.READY))

    def reset(self) -> None:
        """Unload every model, close the native runtime, and forget all state. Idempotent."""
        with self._lock:
            core = self._core
            resident = list(self._resident.values())
            self._resident.clear()
            self._core = None
        for _model_id, handle in resident:
            try:
                handle.unload()  # type: ignore[attr-defined]
            except Exception:  # noqa: BLE001 — one bad unload must not block teardown
                _LOG.debug("unload failed during reset", exc_info=True)
        if core is not None:
            core.shutdown()  # type: ignore[attr-defined]

    @property
    def is_ready(self) -> bool:
        """True once local inference is usable."""
        return self._core is not None

    @property
    def environment(self) -> Environment:
        """The environment this runtime was initialized with."""
        return self._environment

    def version(self) -> str:
        """The native runtime version."""
        return str(self.core().version())  # type: ignore[attr-defined]

    def backends(self) -> list:
        """Engine backends compiled into this build."""
        return list(_native.get_core().backends())

    def device_id(self) -> str:
        """A stable id for this install, persisted under the RunAnywhere home directory."""
        with self._lock:
            if self._device_id is not None:
                return self._device_id
            base = _home()
            path = os.path.join(base, "device_id")
            try:
                os.makedirs(base, exist_ok=True)
                if os.path.exists(path):
                    with open(path, "r", encoding="utf-8") as handle:
                        value = handle.read().strip()
                else:
                    value = ""
                if not value:
                    value = str(uuid.uuid4())
                    with open(path, "w", encoding="utf-8") as handle:
                        handle.write(value)
            except OSError as exc:
                raise SDKException.storage_error(f"could not read or write {path}: {exc}") from exc
            self._device_id = value
            return value

    def core(self):
        """The live native module.

        Raises:
            SDKException: the SDK has not been initialized.
        """
        core = self._core
        if core is None:
            raise SDKException.not_initialized("runanywhere.initialize() has not been called")
        return core

    # -- model resolution ----------------------------------------------------
    def category_for(self, model_id: str) -> ModelCategory:
        """The category of a catalog id or local artifact.

        Raises:
            SDKException: the category cannot be inferred from the id.
        """
        entry = CATALOG.get(model_id)
        if entry is not None:
            return _CATEGORY_FOR_TYPE[entry.type]
        if model_id.lower().endswith((".gguf", ".ggml")):
            return ModelCategory.LANGUAGE
        raise SDKException.invalid_input(
            f"cannot infer a category for {model_id!r}: register it with "
            "models.register(ModelRegistration(id=..., category=...)) first"
        )

    def resolve(
        self,
        model_id: str,
        on_progress: Optional[Callable[[DownloadProgress], None]] = None,
    ) -> ResolvedModel:
        """Resolve a catalog id, URL, HF repo or path to concrete files, downloading if needed."""
        return resolve_model(model_id, None, on_progress)

    def resolve_for_load(self, model_id: str) -> ResolvedModel:
        """Resolve for a load, refusing a path that is not on disk.

        ``resolve`` alone tolerates an absent local path (``models.register`` uses it to
        record a model whose files arrive later); handing one to the engine would surface as
        an opaque native failure instead.

        Raises:
            SDKException: the resolved artifact does not exist.
        """
        resolved = self.resolve(model_id)
        if not os.path.exists(resolved.primary):
            raise SDKException.model_not_found(
                f"{model_id}: no file at {resolved.primary}"
            )
        return resolved

    def register_native(self, resolved: ResolvedModel, category: ModelCategory) -> None:
        """Register ``id -> path`` in the native model registry so commons can resolve it."""
        framework = _FRAMEWORK_FOR_CATEGORY.get(category, InferenceFramework.LLAMACPP)
        self.core().register_model(resolved.id, resolved.primary, int(framework), int(category))

    def model_info(self, model_id: str) -> ModelInfo:
        """Describe a model from the catalog plus its on-disk state."""
        entry = CATALOG.get(model_id)
        status = model_status().get(model_id)
        category = _CATEGORY_FOR_TYPE[entry.type] if entry is not None else ModelCategory.UNKNOWN
        return ModelInfo(
            id=model_id,
            category=category,
            name=(entry.label if entry is not None else None),
            downloaded=bool(status and status.downloaded),
            size_bytes=(status.size_bytes if status else 0),
            local_path=os.path.join(models_root(), model_id) if status else None,
            framework=_FRAMEWORK_FOR_CATEGORY.get(category),
        )

    # -- resident models -----------------------------------------------------
    def resident_id(self, category: ModelCategory) -> Optional[str]:
        """The id of the model currently resident in ``category``, if any."""
        entry = self._resident.get(category)
        return entry[0] if entry else None

    def state(self) -> ModelsState:
        """Snapshot the resident models and disk usage."""
        loaded = {cat: self.model_info(mid) for cat, (mid, _handle) in self._resident.items()}
        root = models_root()
        used = sum(s.size_bytes for s in model_status().values())
        try:
            os.makedirs(root, exist_ok=True)
            free = shutil.disk_usage(root).free
        except OSError:
            free = 0
        return ModelsState(loaded=loaded, storage_used_bytes=used, storage_free_bytes=free)

    def unload(self, category: Optional[ModelCategory] = None) -> None:
        """Unload one category's resident model, or every one when ``category`` is None."""
        with self._lock:
            targets = (
                list(self._resident.items())
                if category is None
                else [(category, self._resident[category])]
                if category in self._resident
                else []
            )
            for cat, _entry in targets:
                self._resident.pop(cat, None)
        for cat, (model_id, handle) in targets:
            try:
                handle.unload()  # type: ignore[attr-defined]
            except Exception:  # noqa: BLE001 — teardown is best effort
                _LOG.debug("unload failed for %s", model_id, exc_info=True)
            bus.emit(SdkEvent(kind=SdkEventKind.MODEL_UNLOADED, model_id=model_id, category=cat))

    def _put(self, category: ModelCategory, model_id: str, handle: object) -> None:
        with self._lock:
            self._resident[category] = (model_id, handle)
        bus.emit(SdkEvent(kind=SdkEventKind.MODEL_LOADED, model_id=model_id, category=category))

    def _reuse(self, category: ModelCategory, model_id: Optional[str]):
        """The resident handle when it already serves ``model_id`` (or any, when unset)."""
        entry = self._resident.get(category)
        if entry is None:
            return None
        resident_id, handle = entry
        if model_id is None or model_id == resident_id:
            return handle
        return None

    def _missing(self, category: ModelCategory, verb: str):
        raise SDKException.invalid_state(
            f"no {category.name.lower()} model is loaded — pass options.model or call "
            f"models.load(id) before {verb}"
        )

    def check_load_options(self, options: Optional[LoadOptions]) -> None:
        """Reject placement knobs the bridge cannot carry.

        Only a single ``backend_preferences`` entry (equivalently the deprecated
        ``framework``) is even meaningful here, and the bridge's
        ``load_model(path, id, name)`` has no placement parameters for it either — so any
        of ``backend_preferences``, ``accelerator``, ``context_length``, or ``threads`` fails
        preflight rather than being silently dropped.

        Raises:
            SDKException: a LoadOptions field is set.
        """
        if options is None:
            return
        if options.resolved_backend_preferences:
            raise SDKException.unsupported_capability(
                "LoadOptions.backend_preferences",
                "the bridge's load_model(path, id, name) has no placement parameters",
            )
        if options.resolved_accelerator is not None:
            raise SDKException.unsupported_capability(
                "LoadOptions.accelerator",
                "the bridge's load_model(path, id, name) has no placement parameters",
            )
        for field in ("context_length", "threads"):
            if getattr(options, field) is not None:
                raise SDKException.unsupported_capability(
                    f"LoadOptions.{field}",
                    "the bridge's load_model(path, id, name) has no placement parameters",
                )

    # -- per-modality loaders ------------------------------------------------
    def llm(self, model_id: Optional[str] = None, *, verb: str = "generating") -> LLMModel:
        """The resident LLM, loading ``model_id`` (and downloading it) when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.LANGUAGE, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.LANGUAGE, verb)
            self.unload(ModelCategory.LANGUAGE)
            resolved = self.resolve_for_load(model_id)
            model = LLMModel(self.core(), self.core().load_model(resolved.primary, model_id, None))
            self._put(ModelCategory.LANGUAGE, model_id, model)
            return model

    def vlm(self, model_id: Optional[str] = None, *, verb: str = "generating") -> VLMModel:
        """The resident VLM, loading ``model_id`` (and downloading it) when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.VISION, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.VISION, verb)
            self.unload(ModelCategory.VISION)
            resolved = self.resolve_for_load(model_id)
            if not resolved.mmproj:
                raise SDKException.validation_failed(
                    field_path="mmproj",
                    message=f"{model_id} has no multimodal projector; a VLM needs one",
                )
            handle_id = self.core().load_vlm_model(resolved.primary, resolved.mmproj, model_id, None)
            model = VLMModel(self.core(), handle_id)
            self._put(ModelCategory.VISION, model_id, model)
            return model

    def embedder(self, model_id: Optional[str] = None, *, verb: str = "embedding") -> Embedder:
        """The resident embedding model, loading ``model_id`` when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.EMBEDDING, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.EMBEDDING, verb)
            assert_remote_supported(model_id, "embedder")
            self.unload(ModelCategory.EMBEDDING)
            resolved = self.resolve_for_load(model_id)
            model = Embedder(self.core(), self.core().load_embedding_model(resolved.primary))
            self._put(ModelCategory.EMBEDDING, model_id, model)
            return model

    def stt(self, model_id: Optional[str] = None, *, verb: str = "transcribing") -> STTModel:
        """The resident STT model, loading ``model_id`` when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.SPEECH_RECOGNITION, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.SPEECH_RECOGNITION, verb)
            assert_remote_supported(model_id, "stt")
            self.unload(ModelCategory.SPEECH_RECOGNITION)
            resolved = self.resolve_for_load(model_id)
            model = STTModel(self.core(), self.core().load_stt_model(resolved.primary, model_id, None))
            self._put(ModelCategory.SPEECH_RECOGNITION, model_id, model)
            return model

    def tts(self, model_id: Optional[str] = None, *, verb: str = "synthesizing") -> TTSVoice:
        """The resident TTS voice bank, loading ``model_id`` when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.SPEECH_SYNTHESIS, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.SPEECH_SYNTHESIS, verb)
            assert_remote_supported(model_id, "tts")
            self.unload(ModelCategory.SPEECH_SYNTHESIS)
            resolved = self.resolve_for_load(model_id)
            voice = TTSVoice(self.core(), self.core().load_tts_voice(resolved.primary, model_id, None))
            self._put(ModelCategory.SPEECH_SYNTHESIS, model_id, voice)
            return voice

    def vad(self, model_id: Optional[str] = None, threshold: Optional[float] = None) -> Vad:
        """The resident detector: the built-in energy VAD, or a model VAD when ``model_id`` is set."""
        with self._lock:
            key = model_id or "builtin-energy-vad"
            handle = self._reuse(ModelCategory.VOICE_ACTIVITY_DETECTION, key)
            if handle is not None:
                if threshold is not None:
                    handle.set_threshold(threshold)  # type: ignore[attr-defined]
                return handle  # type: ignore[return-value]
            self.unload(ModelCategory.VOICE_ACTIVITY_DETECTION)
            detector = Vad(self.core(), self.core().create_vad(threshold))
            if model_id is not None:
                resolved = self.resolve_for_load(model_id)
                detector.load_model(resolved.dir or resolved.primary, id=model_id)
            self._put(ModelCategory.VOICE_ACTIVITY_DETECTION, key, detector)
            return detector

    def diarization(
        self, model_id: Optional[str] = None, *, verb: str = "diarizing"
    ) -> DiarizationModel:
        """The resident diarization model, loading ``model_id`` when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.SPEAKER_DIARIZATION, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.SPEAKER_DIARIZATION, verb)
            core = self.core()
            if not hasattr(core, "load_diarization_model"):
                raise SDKException.unsupported_capability(
                    "diarization.diarize",
                    "this native/_core build predates the diarization bindings "
                    "(load_diarization_model / diarize are not exported by native/module.cpp) "
                    "— rebuild the native extension",
                )
            self.unload(ModelCategory.SPEAKER_DIARIZATION)
            resolved = self.resolve_for_load(model_id)
            handle_id = core.load_diarization_model(resolved.primary, model_id)
            model = DiarizationModel(core, handle_id)
            self._put(ModelCategory.SPEAKER_DIARIZATION, model_id, model)
            return model

    def segmentation(
        self, model_id: Optional[str] = None, *, verb: str = "segmenting"
    ) -> SegmentationModel:
        """The resident segmentation model, loading ``model_id`` when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.SEMANTIC_SEGMENTATION, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.SEMANTIC_SEGMENTATION, verb)
            core = self.core()
            if not hasattr(core, "load_segmentation_model"):
                raise SDKException.unsupported_capability(
                    "segmentation.segment",
                    "this native/_core build predates the segmentation bindings "
                    "(load_segmentation_model / segment are not exported by native/module.cpp) "
                    "— rebuild the native extension",
                )
            self.unload(ModelCategory.SEMANTIC_SEGMENTATION)
            resolved = self.resolve_for_load(model_id)
            handle_id = core.load_segmentation_model(resolved.primary, model_id)
            model = SegmentationModel(core, handle_id)
            self._put(ModelCategory.SEMANTIC_SEGMENTATION, model_id, model)
            return model

    def diffusion(
        self, model_id: Optional[str] = None, *, verb: str = "generating an image"
    ) -> DiffusionModel:
        """The resident diffusion model, loading ``model_id`` when needed."""
        with self._lock:
            handle = self._reuse(ModelCategory.IMAGE_GENERATION, model_id)
            if handle is not None:
                return handle  # type: ignore[return-value]
            if model_id is None:
                self._missing(ModelCategory.IMAGE_GENERATION, verb)
            core = self.core()
            if not hasattr(core, "load_diffusion_model"):
                raise SDKException.unsupported_capability(
                    "images.generate",
                    "this native/_core build has no diffusion bindings "
                    "(load_diffusion_model / generate_image are only exported when "
                    "RAC_HAVE_BACKEND_COREML is set at compile time) — rebuild with the "
                    "CoreML backend, or use a wheel that includes it",
                )
            self.unload(ModelCategory.IMAGE_GENERATION)
            resolved = self.resolve_for_load(model_id)
            handle_id = core.load_diffusion_model(resolved.primary, model_id)
            model = DiffusionModel(core, handle_id)
            self._put(ModelCategory.IMAGE_GENERATION, model_id, model)
            return model

    def create_voice_agent(
        self,
        stt_id: str,
        llm_id: str,
        tts_id: str,
    ) -> VoiceAgent:
        """Create and initialize a voice agent from STT/LLM/TTS model refs."""
        with self._lock:
            core = self.core()
            if not hasattr(core, "create_voice_agent"):
                raise SDKException.unsupported_capability(
                    "voice.create_session",
                    "this native/_core build predates the voice-agent bindings "
                    "(create_voice_agent / initialize_voice_agent / process_voice_turn "
                    "are not exported by native/module.cpp) — rebuild the native extension",
                )
            stt = self.resolve_for_load(stt_id)
            llm = self.resolve_for_load(llm_id)
            tts = self.resolve_for_load(tts_id)
            handle_id = core.create_voice_agent()
            try:
                # Same path shape load_stt_model / load_tts_voice / load_model use.
                core.initialize_voice_agent(
                    handle_id,
                    stt.primary,
                    llm.primary,
                    tts.primary,
                    stt_id=stt_id,
                    llm_id=llm_id,
                    tts_id=tts_id,
                )
            except Exception:
                core.destroy_voice_agent(handle_id)
                raise
            return VoiceAgent(core, handle_id)

    def llm_if_resident(self) -> Optional[LLMModel]:
        """The resident LLM, or ``None`` — never loads one (used by ``lora.list``)."""
        entry = self._resident.get(ModelCategory.LANGUAGE)
        return entry[1] if entry else None  # type: ignore[return-value]

    def load(self, model_id: str, options: Optional[LoadOptions] = None) -> ModelCategory:
        """Load ``model_id`` into its category and return that category."""
        self.check_load_options(options)
        category = self.category_for(model_id)
        loaders = {
            ModelCategory.LANGUAGE: self.llm,
            ModelCategory.VISION: self.vlm,
            ModelCategory.EMBEDDING: self.embedder,
            ModelCategory.SPEECH_RECOGNITION: self.stt,
            ModelCategory.SPEECH_SYNTHESIS: self.tts,
            ModelCategory.VOICE_ACTIVITY_DETECTION: self.vad,
            ModelCategory.SPEAKER_DIARIZATION: self.diarization,
            ModelCategory.SEMANTIC_SEGMENTATION: self.segmentation,
            ModelCategory.IMAGE_GENERATION: self.diffusion,
        }
        loader = loaders.get(category)
        if loader is None:
            raise SDKException.not_implemented(f"loading {category.name} models")
        loader(model_id)
        return category

    def new_request_id(self) -> str:
        """A fresh id for one request, echoed back in the result and the started event."""
        return uuid.uuid4().hex


#: The process-wide runtime instance the namespaces talk to.
runtime = Runtime()


def is_catalog(model_id: str) -> bool:
    """True when ``model_id`` names a built-in catalog entry."""
    return is_catalog_id(model_id)
