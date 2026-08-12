"""The ``diarization`` namespace: attribute speech to speakers.

Binds ``native/module.cpp``'s ``load_diarization_model`` / ``diarize`` — thin wrappers over
the offline ``rac_diarization_create`` / ``initialize`` / ``diarize`` C ABI (the same shape
the ``runanywhere-electron`` addon already exposes as ``loadDiarizationModel`` /
``diarize``). Offline batch diarization routes through the ONNX Sortformer provider that
``rac_backend_onnx_register()`` wires in; a build without the ONNX backend registered
surfaces a native ``RAC_ERROR_NOT_SUPPORTED`` rather than a preflight capability error.

Only the resident-model shape is covered here — no streaming diarization (the underlying
``rac_diarization_stream_*`` ABI exists in commons, but ``native/module.cpp`` binds no
streaming entry point for it).
"""

from __future__ import annotations

from typing import Optional

from .._runtime import runtime
from ..inputs import STT_SAMPLE_RATE, AudioInput
from ..options import DiarizationOptions
from ..results import DiarizationResult, SpeakerSegment

__all__ = ["diarization"]

_SAMPLE_RATE = STT_SAMPLE_RATE


class Diarization:
    """Speaker diarization over the resident diarization model (ONNX Sortformer)."""

    def diarize(
        self, audio: AudioInput, options: Optional[DiarizationOptions] = None
    ) -> DiarizationResult:
        """Attribute spans of ``audio`` to speakers.

        Loads (and downloads) ``options.model`` when it is not already resident — pass a
        catalog id, URL, HuggingFace repo, or local path/directory to a Sortformer ONNX
        model, exactly like ``stt.transcribe``'s ``options.model``.

        Raises:
            SDKException: no diarization model is available (and ``options.model`` was not
                given), this native build predates the diarization bindings, or the native
                call fails.

        Example:
            >>> audio = AudioInput.file("meeting.wav")
            >>> result = runanywhere.diarization.diarize(
            ...     audio, DiarizationOptions(model="sortformer-onnx")
            ... )
            >>> print(result.speaker_count)
        """
        model_id = options.model if options else None
        model = runtime.diarization(model_id, verb="diarizing")
        samples = audio.samples(_SAMPLE_RATE)
        raw = model.diarize(
            samples,
            sample_rate_hz=_SAMPLE_RATE,
            threshold=options.threshold if options else None,
            minimum_duration_ms=options.minimum_duration_ms if options else None,
            merge_gap_ms=options.merge_gap_ms if options else None,
        )
        segments = [
            SpeakerSegment(
                speaker_id=seg["speaker_id"], start_ms=seg["start_ms"], end_ms=seg["end_ms"]
            )
            for seg in raw["segments"]
        ]
        return DiarizationResult(segments=segments, speaker_count=raw["speaker_count"])


#: The ``diarization`` namespace.
diarization = Diarization()
