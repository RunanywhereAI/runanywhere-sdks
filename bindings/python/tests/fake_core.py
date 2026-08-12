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
        synthesis: Optional[Tuple[np.ndarray, int, int]] = None,
        vad_decisions: Optional[Sequence[bool]] = None,
        dimension: int = 4,
    ) -> None:
        self.calls: List[Tuple[str, tuple]] = []
        self.tokens = list(tokens or ["Par", "is"])
        self.transcript = transcript
        # (samples, sample_rate, duration_ms) — duration_ms mirrors commons TTS output.
        self.synthesis = synthesis or (
            np.zeros(2048, dtype=np.float32),
            22050,
            int(round(2048 / 22050 * 1000)),
        )
        self.vad_decisions = list(vad_decisions or [])
        self.dimension = dimension
        self.last_kwargs: Optional[dict] = None
        self.emitted = 0
        self.stopped = False
        self._next_handle = 1
        self._vad_index = 0
        self._registry: dict = {}
        # Prefer the legacy generate path in hermetic tests (typed via generate_typed).
        self.prefer_legacy_generate = True
        self.stream_deltas: Optional[List[tuple]] = None  # [(text, is_thinking), ...]
        self.finish_reason = 0  # FinishReason.UNSPECIFIED
        self.usage: Optional[dict] = None
        self.final_text: Optional[str] = None
        self.final_thinking: Optional[str] = None
        self._vad_cb = None
        self._vad_session = 0
        self._vad_options_bytes: bytes = b""
        self._vad_speech_ms = 0
        self._vad_silence_ms = 0
        self._vad_in_speech = False
        self._vad_start_ms = 0
        self._vad_at_ms = 0
        self._vad_prefix_ms = 0
        self._vad_min_speech = 100
        self._vad_min_silence = 300
        self._audio_calls: List[tuple] = []

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
        self.stopped = False
        pieces = self.stream_deltas or [(token, False) for token in self.tokens]
        for text, _is_thinking in pieces:
            if self.stopped:
                return
            keep = on_token(text)
            self.emitted += 1
            if keep is False:
                self.stopped = True
                return

    def generate_typed(self, handle: int, prompt: str, on_delta: Callable, **kwargs) -> None:
        self._record("generate_typed", handle, prompt)
        self.last_kwargs = kwargs
        self.stopped = False
        pieces = self.stream_deltas or [(token, False) for token in self.tokens]
        for text, is_thinking in pieces:
            if self.stopped:
                return
            keep = on_delta(text, bool(is_thinking))
            self.emitted += 1
            if keep is False:
                self.stopped = True
                return

    def cancel_generate(self, handle: int) -> None:
        self._record("cancel_generate", handle)
        self.stopped = True

    def unload_model(self, handle: int) -> None:
        self._record("unload_model", handle)

    # -- LoRA (rac_lora_*_proto — optional scale presence preserved) ---------
    def __init_lora_state(self) -> None:
        if not hasattr(self, "_lora_state"):
            self._lora_state: list = []

    def lora_apply_proto(self, request_bytes: bytes) -> bytes:
        from runanywhere._proto import lora_options_pb2 as lora_pb

        self.__init_lora_state()
        req = lora_pb.LoraApplyRequest()
        req.ParseFromString(bytes(request_bytes))
        recorded = []
        for adapter in req.adapters:
            recorded.append(
                (
                    adapter.adapter_id,
                    adapter.adapter_path,
                    adapter.HasField("scale"),
                    float(adapter.scale) if adapter.HasField("scale") else None,
                )
            )
        self._record("lora_apply_proto", len(bytes(request_bytes)), tuple(recorded), req.keep_existing)
        if not req.keep_existing:
            self._lora_state = []
        result = lora_pb.LoraApplyResult()
        result.request_id = req.request_id
        for adapter in req.adapters:
            # Simulate commons resolve_effective_lora_scale for list/read-back only.
            resolved = float(adapter.scale) if adapter.HasField("scale") else 1.0
            info = result.adapters.add()
            info.adapter_id = adapter.adapter_id
            info.adapter_path = adapter.adapter_path
            info.scale = resolved
            info.applied = True
            self._lora_state = [
                s for s in self._lora_state if s[0] != (adapter.adapter_id or adapter.adapter_path)
            ]
            self._lora_state.append((adapter.adapter_id or adapter.adapter_path, resolved))
        return result.SerializeToString()

    def lora_remove_proto(self, request_bytes: bytes) -> bytes:
        from runanywhere._proto import lora_options_pb2 as lora_pb

        self.__init_lora_state()
        req = lora_pb.LoraRemoveRequest()
        req.ParseFromString(bytes(request_bytes))
        self._record("lora_remove_proto", len(bytes(request_bytes)), list(req.adapter_ids), req.clear_all)
        if req.clear_all:
            self._lora_state = []
        else:
            remove = set(req.adapter_ids)
            self._lora_state = [s for s in self._lora_state if s[0] not in remove]
        state = lora_pb.LoraState()
        for adapter_id, scale in self._lora_state:
            info = state.loaded_adapters.add()
            info.adapter_id = adapter_id
            info.adapter_path = adapter_id
            info.scale = float(scale)
            info.applied = True
        return state.SerializeToString()

    def lora_list_proto(self, state_bytes: bytes) -> bytes:
        from runanywhere._proto import lora_options_pb2 as lora_pb

        self.__init_lora_state()
        self._record("lora_list_proto", len(bytes(state_bytes)))
        state = lora_pb.LoraState()
        for adapter_id, scale in self._lora_state:
            info = state.loaded_adapters.add()
            info.adapter_id = adapter_id
            info.adapter_path = adapter_id
            info.scale = float(scale)
            info.applied = True
        return state.SerializeToString()

    def lora_state_proto(self, state_bytes: bytes) -> bytes:
        return self.lora_list_proto(state_bytes)

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

    def vad_set_stream_callback(self, handle: int, on_event: Callable) -> None:
        self._record("vad_set_stream_callback", handle)
        self._vad_cb = on_event

    def vad_unset_stream_callback(self, handle: int) -> None:
        self._record("vad_unset_stream_callback", handle)
        self._vad_cb = None

    def vad_stream_start(self, handle: int, options_bytes: bytes) -> int:
        self._record("vad_stream_start", handle, len(bytes(options_bytes)))
        self._vad_options_bytes = bytes(options_bytes)
        self._vad_session += 1
        self._vad_index = 0
        self._vad_at_ms = 0
        self._vad_speech_ms = 0
        self._vad_silence_ms = 0
        self._vad_in_speech = False
        self._vad_start_ms = 0
        # Parse timing options so hermetic tests can assert commons receives them.
        try:
            from runanywhere._proto import vad_options_pb2 as vad_pb

            opts = vad_pb.VADOptions()
            opts.ParseFromString(self._vad_options_bytes)
            self._vad_min_speech = int(opts.min_speech_duration_ms) or 100
            self._vad_min_silence = int(opts.min_silence_duration_ms) or 300
            self._vad_prefix_ms = int(opts.prefix_padding_ms)
        except Exception:  # noqa: BLE001
            self._vad_min_speech = 100
            self._vad_min_silence = 300
            self._vad_prefix_ms = 0
        return self._vad_session

    def _emit_activity(self, kind: int, start_ms: int, end_ms: int = 0) -> None:
        if self._vad_cb is None:
            return
        from runanywhere._proto import vad_options_pb2 as vad_pb

        event = vad_pb.VADStreamEvent()
        event.kind = vad_pb.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY
        event.activity.event_type = kind
        event.activity.audio_start_ms = start_ms
        event.activity.audio_end_ms = end_ms
        self._vad_cb(event.SerializeToString())

    def vad_stream_feed(self, session_id: int, audio_bytes: bytes) -> None:
        self._record("vad_stream_feed", session_id, len(bytes(audio_bytes)))
        # 512 float samples @ 16 kHz = 32 ms; PCM16 is 2 bytes/sample.
        frame_samples = 512
        frame_ms = 32
        raw = bytes(audio_bytes)
        n_frames = max(1, len(raw) // (frame_samples * 2)) if raw else 0
        from runanywhere._proto import vad_options_pb2 as vad_pb

        for _ in range(n_frames):
            speech = False
            if self.vad_decisions:
                speech = bool(
                    self.vad_decisions[min(self._vad_index, len(self.vad_decisions) - 1)]
                )
                self._vad_index += 1
            if speech:
                self._vad_silence_ms = 0
                if not self._vad_in_speech:
                    self._vad_in_speech = True
                    self._vad_speech_ms = 0
                    self._vad_start_ms = max(0, self._vad_at_ms - self._vad_prefix_ms)
                prev = self._vad_speech_ms
                self._vad_speech_ms += frame_ms
                # Emit STARTED once speech clears min_speech (simulates commons policy).
                if prev < self._vad_min_speech <= self._vad_speech_ms:
                    self._emit_activity(
                        vad_pb.SPEECH_ACTIVITY_KIND_SPEECH_STARTED, self._vad_start_ms
                    )
            elif self._vad_in_speech:
                self._vad_silence_ms += frame_ms
                if self._vad_silence_ms >= self._vad_min_silence:
                    if self._vad_speech_ms >= self._vad_min_speech:
                        end_ms = self._vad_at_ms - self._vad_silence_ms + frame_ms
                        self._emit_activity(
                            vad_pb.SPEECH_ACTIVITY_KIND_SPEECH_ENDED,
                            self._vad_start_ms,
                            max(end_ms, self._vad_start_ms),
                        )
                    self._vad_in_speech = False
            self._vad_at_ms += frame_ms

    def vad_stream_stop(self, session_id: int) -> None:
        self._record("vad_stream_stop", session_id)
        from runanywhere._proto import vad_options_pb2 as vad_pb

        if self._vad_in_speech and self._vad_speech_ms >= self._vad_min_speech:
            self._emit_activity(
                vad_pb.SPEECH_ACTIVITY_KIND_SPEECH_ENDED,
                self._vad_start_ms,
                max(self._vad_at_ms, self._vad_start_ms),
            )
        self._vad_in_speech = False

    def vad_stream_cancel(self, session_id: int) -> None:
        self._record("vad_stream_cancel", session_id)
        self._vad_in_speech = False

    # -- audio DSP (record + identity-ish forwards for hermetic tests) -------
    def audio_float32_to_pcm16(self, samples: np.ndarray) -> np.ndarray:
        self._audio_calls.append(("float32_to_pcm16", len(samples)))
        a = np.asarray(samples, dtype=np.float32)
        scaled = np.clip(np.rint(np.clip(a, -1.0, 1.0) * 32768.0), -32768, 32767)
        return scaled.astype(np.int16)

    def audio_pcm16_to_float32(self, samples: np.ndarray) -> np.ndarray:
        self._audio_calls.append(("pcm16_to_float32", len(samples)))
        return (np.asarray(samples, dtype=np.int16).astype(np.float32) / 32768.0).astype(np.float32)

    def audio_resample_f32(self, samples: np.ndarray, in_rate: int, out_rate: int) -> np.ndarray:
        self._audio_calls.append(("resample", len(samples), in_rate, out_rate))
        a = np.asarray(samples, dtype=np.float32)
        if in_rate == out_rate or a.size == 0:
            return a.copy()
        out_len = max(1, int(round(a.size * out_rate / in_rate)))
        x_old = np.linspace(0.0, 1.0, a.size, dtype=np.float64)
        x_new = np.linspace(0.0, 1.0, out_len, dtype=np.float64)
        return np.interp(x_new, x_old, a.astype(np.float64)).astype(np.float32)

    def audio_compute_rms(self, samples: np.ndarray) -> float:
        self._audio_calls.append(("rms", len(samples)))
        a = np.asarray(samples, dtype=np.float32)
        if a.size == 0:
            return 0.0
        return float(np.sqrt(np.mean(a.astype(np.float64) ** 2)))

    def audio_float32_to_wav(self, samples: np.ndarray, sample_rate: int) -> bytes:
        self._audio_calls.append(("encode_wav", len(samples), sample_rate))
        pcm = self.audio_float32_to_pcm16(samples).astype("<i2").tobytes()
        header = bytearray(44)
        header[0:4] = b"RIFF"
        header[4:8] = (36 + len(pcm)).to_bytes(4, "little")
        header[8:12] = b"WAVE"
        header[12:16] = b"fmt "
        header[16:20] = (16).to_bytes(4, "little")
        header[20:22] = (1).to_bytes(2, "little")
        header[22:24] = (1).to_bytes(2, "little")
        header[24:28] = int(sample_rate).to_bytes(4, "little")
        header[28:32] = (int(sample_rate) * 2).to_bytes(4, "little")
        header[32:34] = (2).to_bytes(2, "little")
        header[34:36] = (16).to_bytes(2, "little")
        header[36:40] = b"data"
        header[40:44] = len(pcm).to_bytes(4, "little")
        return bytes(header) + pcm

    def audio_wav_to_float32(self, data: bytes) -> tuple:
        self._audio_calls.append(("decode_wav", len(bytes(data))))
        b = bytes(data)
        if len(b) < 44:
            raise RuntimeError("truncated wav")
        sample_rate = int.from_bytes(b[24:28], "little")
        pcm = np.frombuffer(b[44:], dtype="<i2")
        return sample_rate, self.audio_pcm16_to_float32(pcm)

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
