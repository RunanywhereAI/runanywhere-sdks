"""The ``tts`` namespace: synthesize speech."""

from __future__ import annotations

from typing import Iterator, List, Optional

import numpy as np

from .._options_bridge import check_tts_options
from .._runtime import runtime
from ..audio import downsample, encode_wav, pcm16_bytes
from ..catalog import CATALOG
from ..errors import SDKException
from ..inputs import AudioFormat
from ..options import TtsOptions
from ..results import Audio, AudioChunk, Voice

__all__ = ["tts"]


def _voice_model(options: Optional[TtsOptions]) -> Optional[str]:
    """The voice bank to load: ``model`` wins, then ``voice`` read as a catalog id."""
    if options is None:
        return None
    return options.model or options.voice


def _encode(samples: np.ndarray, sample_rate: int, options: Optional[TtsOptions]) -> Audio:
    rate = sample_rate
    if options is not None and options.sample_rate and options.sample_rate < sample_rate:
        # Only downsampling is available host-side; a higher request keeps the native rate,
        # which Audio.sample_rate reports.
        samples = downsample(samples, sample_rate, options.sample_rate)
        rate = options.sample_rate
    fmt = options.format if options is not None else AudioFormat.PCM
    data = encode_wav(samples, rate) if fmt == AudioFormat.WAV else pcm16_bytes(samples)
    return Audio(
        data=data,
        sample_rate=rate,
        format=fmt,
        duration_ms=int(round(len(samples) / rate * 1000)) if rate else 0,
    )


class Tts:
    """Text-to-speech over the resident voice bank."""

    def synthesize(self, text: str, options: Optional[TtsOptions] = None) -> Audio:
        """Synthesize ``text`` to audio.

        Raises:
            SDKException: no voice is available, or an unsupported option is set.

        Example:
            >>> audio = runanywhere.tts.synthesize("Hello", TtsOptions(voice="piper-amy"))
            >>> open("out.wav", "wb").write(audio.data)
        """
        check_tts_options(options)
        voice = runtime.tts(_voice_model(options))
        synthesis = voice.synthesize(text)
        return _encode(synthesis.samples, synthesis.sample_rate, options)

    async def asynthesize(self, text: str, options: Optional[TtsOptions] = None) -> Audio:
        """Async form of :meth:`synthesize`."""
        check_tts_options(options)
        voice = runtime.tts(_voice_model(options))
        synthesis = await voice.asynthesize(text)
        return _encode(synthesis.samples, synthesis.sample_rate, options)

    def synthesize_stream(
        self, text: str, options: Optional[TtsOptions] = None
    ) -> Iterator[AudioChunk]:
        """Yield the synthesized audio as chunks.

        The bridge synthesizes whole utterances, so this yields exactly one final chunk.

        Raises:
            SDKException: no voice is available, or an unsupported option is set.
        """
        audio = self.synthesize(text, options)
        yield AudioChunk(data=audio.data, index=0, is_final=True, sample_rate=audio.sample_rate)

    def speak(self, text: str, options: Optional[TtsOptions] = None) -> None:
        """Not available in this SDK.

        Raises:
            SDKException: always — there is no host playback path.
        """
        raise SDKException.not_implemented(
            "tts.speak: the Python SDK has no audio output device (numpy is its only runtime "
            "dependency) and native/module.cpp binds no rac_tts_platform_synthesize; use "
            "synthesize() and play the bytes with your own audio stack"
        )

    def stop(self) -> None:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge binds no synthesis-stop entry point.
        """
        raise SDKException.not_implemented(
            "tts.stop: native/module.cpp binds no rac_tts_component_stop"
        )

    def voices(self) -> List[Voice]:
        """The voice banks this build can load."""
        return [
            Voice(id=model_id, name=entry.label or model_id, language="en-US")
            for model_id, entry in sorted(CATALOG.items())
            if entry.type == "tts"
        ]


#: The ``tts`` namespace.
tts = Tts()
