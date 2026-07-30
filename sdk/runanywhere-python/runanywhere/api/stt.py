"""The ``stt`` namespace: transcribe audio."""

from __future__ import annotations

from typing import Iterable, Iterator, Optional

from .._options_bridge import check_stt_options
from .._runtime import runtime
from ..errors import SDKException
from ..events import TranscriptionEvent
from ..inputs import AudioInput, ModelCategory
from ..options import SttOptions
from ..results import SttState, Transcription

__all__ = ["stt"]

_SAMPLE_RATE = 16000


class Stt:
    """Speech-to-text over the resident STT model."""

    def transcribe(self, audio: AudioInput, options: Optional[SttOptions] = None) -> Transcription:
        """Transcribe an utterance.

        ``words`` comes back empty and ``confidence`` zero: the bridge's ``transcribe`` returns
        text only.

        Raises:
            SDKException: no STT model is available, or an unsupported option is set.

        Example:
            >>> audio = AudioInput.file("hello.wav")
            >>> print(runanywhere.stt.transcribe(audio).text)
        """
        check_stt_options(options)
        model = runtime.stt(options.model if options else None)
        pcm16 = audio.to_pcm16(_SAMPLE_RATE)
        text = model.transcribe(pcm16)
        return Transcription(
            text=text,
            language=options.language if options else None,
            duration_ms=audio.duration_ms(_SAMPLE_RATE),
        )

    async def atranscribe(
        self, audio: AudioInput, options: Optional[SttOptions] = None
    ) -> Transcription:
        """Async form of :meth:`transcribe`."""
        check_stt_options(options)
        model = runtime.stt(options.model if options else None)
        pcm16 = audio.to_pcm16(_SAMPLE_RATE)
        text = await model.atranscribe(pcm16)
        return Transcription(
            text=text,
            language=options.language if options else None,
            duration_ms=audio.duration_ms(_SAMPLE_RATE),
        )

    def transcribe_stream(
        self, audio: Iterable[AudioInput], options: Optional[SttOptions] = None
    ) -> Iterator[TranscriptionEvent]:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge binds no streaming STT entry point.
        """
        raise SDKException.not_implemented(
            "stt.transcribe_stream: native/module.cpp binds no streaming STT "
            "(rac_stt_component_transcribe_stream_proto / rac_stt_stream_start_proto are "
            "not exposed to Python)"
        )

    def state(self) -> SttState:
        """Report whether transcription is ready and what it supports."""
        model_id = runtime.resident_id(ModelCategory.SPEECH_RECOGNITION)
        return SttState(
            is_ready=model_id is not None,
            model_id=model_id,
            # rac_stt_component_supports_streaming is not bound, so streaming is off here.
            supports_streaming=False,
            languages=[],
        )


#: The ``stt`` namespace.
stt = Stt()
