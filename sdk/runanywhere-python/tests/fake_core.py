"""A recording stand-in for the compiled ``_core`` extension.

Every test that touches the runtime installs one of these through
``runanywhere._native.get_core``, so the whole suite runs with no native build. It records
each call as ``(method, args)`` and hands back fake integer handles.
"""

from __future__ import annotations

from typing import Callable, List, Optional, Sequence, Tuple

import numpy as np


class FakeCore:
    """Fake native core with scriptable outputs."""

    def __init__(
        self,
        tokens: Optional[Sequence[str]] = None,
        *,
        transcript: str = "hello there",
        synthesis: Optional[Tuple[np.ndarray, int]] = None,
        vad_decisions: Optional[Sequence[bool]] = None,
        dimension: int = 4,
    ) -> None:
        self.calls: List[Tuple[str, tuple]] = []
        self.tokens = list(tokens or ["Par", "is"])
        self.transcript = transcript
        self.synthesis = synthesis or (np.zeros(2048, dtype=np.float32), 22050)
        self.vad_decisions = list(vad_decisions or [])
        self.dimension = dimension
        self.last_kwargs: Optional[dict] = None
        self.emitted = 0
        self.stopped = False
        self._next_handle = 1
        self._vad_index = 0
        self._registry: dict = {}

    # -- bookkeeping ---------------------------------------------------------
    def _record(self, method: str, *args: object) -> None:
        self.calls.append((method, args))

    def count(self, method: str) -> int:
        return sum(1 for name, _ in self.calls if name == method)

    def args_of(self, method: str) -> tuple:
        return next(args for name, args in self.calls if name == method)

    def _handle(self) -> int:
        handle = self._next_handle
        self._next_handle += 1
        return handle

    # -- lifecycle -----------------------------------------------------------
    def version(self) -> str:
        return "fake-0"

    def backends(self) -> List[str]:
        return ["llamacpp", "onnx", "sherpa"]

    def initialize(self, secure_dir: str, base_dir: str) -> None:
        self._record("initialize", secure_dir, base_dir)

    def shutdown(self) -> None:
        self._record("shutdown")

    # -- LLM -----------------------------------------------------------------
    def load_model(self, path: str, model_id: object = None, name: object = None) -> int:
        self._record("load_model", path, model_id, name)
        return self._handle()

    def generate(self, handle: int, prompt: str, on_token: Callable, **kwargs) -> None:
        self._record("generate", handle, prompt)
        self.last_kwargs = kwargs
        for token in self.tokens:
            keep = on_token(token)
            self.emitted += 1
            if keep is False:
                self.stopped = True
                return

    def cancel_generate(self, handle: int) -> None:
        self._record("cancel_generate", handle)

    def unload_model(self, handle: int) -> None:
        self._record("unload_model", handle)

    # -- LoRA (rac_llm_component_{load,remove,clear}_lora) --------------------
    def lora_apply(self, handle: int, adapter_path: str, scale: object = None) -> None:
        self._record("lora_apply", handle, adapter_path, scale)

    def lora_remove(self, handle: int, adapter_path: str) -> None:
        self._record("lora_remove", handle, adapter_path)

    def lora_remove_all(self, handle: int) -> None:
        self._record("lora_remove_all", handle)

    # -- VLM -----------------------------------------------------------------
    def load_vlm_model(
        self, path: str, mmproj: str, model_id: object = None, name: object = None
    ) -> int:
        self._record("load_vlm_model", path, mmproj, model_id, name)
        return self._handle()

    def generate_vlm(
        self, handle: int, image_path: str, prompt: str, on_token: Callable, **kwargs
    ) -> None:
        self._record("generate_vlm", handle, image_path, prompt)
        self.last_kwargs = kwargs
        for token in self.tokens:
            if on_token(token) is False:
                self.stopped = True
                return

    def cancel_generate_vlm(self, handle: int) -> None:
        self._record("cancel_generate_vlm", handle)

    def unload_vlm_model(self, handle: int) -> None:
        self._record("unload_vlm_model", handle)

    # -- embeddings ----------------------------------------------------------
    def load_embedding_model(self, path: str) -> int:
        self._record("load_embedding_model", path)
        return self._handle()

    def embed(self, handle: int, text: str) -> np.ndarray:
        self._record("embed", handle, text)
        return np.arange(self.dimension, dtype=np.float32)

    def embed_batch(self, handle: int, texts: Sequence[str]) -> List[np.ndarray]:
        self._record("embed_batch", handle, tuple(texts))
        return [np.arange(self.dimension, dtype=np.float32) for _ in texts]

    def unload_embedding_model(self, handle: int) -> None:
        self._record("unload_embedding_model", handle)

    # -- STT / TTS -----------------------------------------------------------
    def load_stt_model(self, path: str, model_id: object = None, name: object = None) -> int:
        self._record("load_stt_model", path, model_id, name)
        return self._handle()

    def transcribe(self, handle: int, pcm16: bytes) -> str:
        self._record("transcribe", handle, len(bytes(pcm16)))
        return self.transcript

    def unload_stt_model(self, handle: int) -> None:
        self._record("unload_stt_model", handle)

    def load_tts_voice(self, path: str, model_id: object = None, name: object = None) -> int:
        self._record("load_tts_voice", path, model_id, name)
        return self._handle()

    def synthesize(self, handle: int, text: str):
        self._record("synthesize", handle, text)
        return self.synthesis

    def unload_tts_voice(self, handle: int) -> None:
        self._record("unload_tts_voice", handle)

    # -- VAD -----------------------------------------------------------------
    def create_vad(self, threshold: object = None) -> int:
        self._record("create_vad", threshold)
        return self._handle()

    def vad_process(self, handle: int, samples: np.ndarray) -> bool:
        index = self._vad_index
        self._vad_index += 1
        if not self.vad_decisions:
            return False
        return bool(self.vad_decisions[min(index, len(self.vad_decisions) - 1)])

    def vad_is_active(self, handle: int) -> bool:
        return False

    def vad_set_threshold(self, handle: int, threshold: float) -> None:
        self._record("vad_set_threshold", handle, threshold)

    def vad_reset(self, handle: int) -> None:
        self._record("vad_reset", handle)
        self._vad_index = 0

    def load_vad_model(self, handle: int, path: str, model_id=None, name=None) -> None:
        self._record("load_vad_model", handle, path, model_id, name)

    def unload_vad(self, handle: int) -> None:
        self._record("unload_vad", handle)

    # -- diarization (rac_diarization_create/initialize/diarize) -------------
    def load_diarization_model(self, model_path: str, model_id: object = None) -> int:
        self._record("load_diarization_model", model_path, model_id)
        return self._handle()

    def diarize(
        self,
        handle: int,
        samples: np.ndarray,
        sample_rate_hz: object = None,
        threshold: object = None,
        minimum_duration_ms: object = None,
        merge_gap_ms: object = None,
    ) -> dict:
        self._record(
            "diarize", handle, len(samples), sample_rate_hz, threshold,
            minimum_duration_ms, merge_gap_ms,
        )
        return {
            "segments": [
                {"start_ms": 0, "end_ms": 500, "speaker_index": 0, "speaker_id": "speaker_0"},
                {"start_ms": 500, "end_ms": 1000, "speaker_index": 1, "speaker_id": "speaker_1"},
            ],
            "speaker_count": 2,
            "duration_ms": 1000,
        }

    def unload_diarization_model(self, handle: int) -> None:
        self._record("unload_diarization_model", handle)

    # -- segmentation (rac_segmentation_create/initialize/segment) -----------
    def load_segmentation_model(self, model_path: str, model_id: object = None) -> int:
        self._record("load_segmentation_model", model_path, model_id)
        return self._handle()

    def segment(
        self,
        handle: int,
        data: object,
        width: int,
        height: int,
        pixel_format: object = None,
        stride_bytes: object = None,
        include_diagnostic_rgba: object = None,
    ) -> dict:
        self._record(
            "segment", handle, width, height, pixel_format, stride_bytes,
            include_diagnostic_rgba,
        )
        mask = np.zeros(width * height, dtype=np.uint16)
        mask[: width * height // 2] = 1
        return {
            "width": width,
            "height": height,
            "class_mask": mask,
            "classes": [
                {"class_id": 0, "pixel_count": width * height // 2, "fraction": 0.5, "label": "bg"},
                {"class_id": 1, "pixel_count": width * height // 2, "fraction": 0.5, "label": "fg"},
            ],
        }

    def unload_segmentation_model(self, handle: int) -> None:
        self._record("unload_segmentation_model", handle)

    # -- voice agent (file-PCM turn) ----------------------------------------
    def create_voice_agent(self) -> int:
        self._record("create_voice_agent")
        return self._handle()

    def initialize_voice_agent(
        self,
        handle: int,
        stt_path: str,
        llm_path: str,
        tts_path: str,
        stt_id: object = None,
        llm_id: object = None,
        tts_id: object = None,
        stt_name: object = None,
        llm_name: object = None,
        tts_name: object = None,
    ) -> None:
        self._record(
            "initialize_voice_agent", handle, stt_path, llm_path, tts_path,
            stt_id, llm_id, tts_id,
        )

    def process_voice_turn(self, handle: int, pcm16: object) -> dict:
        self._record("process_voice_turn", handle, len(bytes(pcm16)))
        return {
            "speech_detected": True,
            "transcription": self.transcript,
            "assistant_response": "hi from the agent",
            "synthesized_audio": b"RIFF" + b"\x00" * 40,
            "sample_rate_hz": 22050,
            "channels": 1,
            "stt_time_ms": 10,
            "llm_time_ms": 20,
            "tts_time_ms": 30,
            "total_time_ms": 60,
        }

    def destroy_voice_agent(self, handle: int) -> None:
        self._record("destroy_voice_agent", handle)

    # -- diffusion (CoreML; present on fake to exercise the happy path) ------
    def load_diffusion_model(self, model_path: str, model_id: object = None) -> int:
        self._record("load_diffusion_model", model_path, model_id)
        return self._handle()

    def generate_image(
        self,
        handle: int,
        prompt: str,
        negative_prompt: object = None,
        width: object = None,
        height: object = None,
        steps: object = None,
        guidance_scale: object = None,
        seed: object = None,
    ) -> dict:
        w = int(width or 64)
        h = int(height or 64)
        self._record("generate_image", handle, prompt, w, h, steps, seed)
        return {
            "image_data": bytes([0] * (w * h * 4)),
            "width": w,
            "height": h,
            "seed": int(seed if seed is not None else 42),
            "generation_time_ms": 100,
            "safety_flagged": False,
        }

    def unload_diffusion_model(self, handle: int) -> None:
        self._record("unload_diffusion_model", handle)

    # -- registry ------------------------------------------------------------
    def register_model(self, model_id: str, local_path: str, framework: int, category: int) -> None:
        self._record("register_model", model_id, local_path, framework, category)
        self._registry[model_id] = {
            "id": model_id, "path": local_path, "framework": framework, "category": category
        }

    def get_model(self, model_id: str):
        return self._registry.get(model_id)

    def list_models(self) -> list:
        return list(self._registry.values())

    def remove_model(self, model_id: str) -> None:
        self._record("remove_model", model_id)
        self._registry.pop(model_id, None)

    # -- secure store --------------------------------------------------------
    def secure_set(self, key: str, value: str) -> None:
        self._record("secure_set", key, value)

    def secure_get(self, key: str):
        self._record("secure_get", key)
        return None

    def secure_delete(self, key: str) -> None:
        self._record("secure_delete", key)
