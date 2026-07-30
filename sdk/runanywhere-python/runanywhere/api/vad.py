"""The ``vad`` namespace: find speech in audio."""

from __future__ import annotations

import asyncio
from typing import Iterable, Iterator, List, Optional

import numpy as np

from .._runtime import runtime
from ..events import VadEvent, VadEventKind
from ..inputs import AudioInput
from ..options import VadOptions
from ..results import Segment, VadResult

__all__ = ["vad"]

_SAMPLE_RATE = 16000
_FRAME = 512  # the frame size the detector expects at 16 kHz
_FRAME_MS = _FRAME * 1000 // _SAMPLE_RATE


class _Segmenter:
    """Turns per-frame speech decisions into segments, applying the timing options."""

    def __init__(self, options: Optional[VadOptions]) -> None:
        opts = options or VadOptions()
        self._min_speech_ms = opts.min_speech_ms
        self._min_silence_ms = opts.min_silence_ms
        self._pad_ms = opts.prefix_padding_ms
        self._in_speech = False
        self._start_ms = 0
        self._silence_ms = 0
        self._speech_ms = 0
        self.segments: List[Segment] = []
        self.events: List[VadEvent] = []

    def push(self, speech: bool, at_ms: int) -> None:
        """Feed one frame's decision, taken at ``at_ms``."""
        if speech:
            self._silence_ms = 0
            if not self._in_speech:
                self._in_speech = True
                self._speech_ms = 0
                self._start_ms = max(0, at_ms - self._pad_ms)
                self.events.append(
                    VadEvent(kind=VadEventKind.SPEECH_STARTED, timestamp_ms=self._start_ms)
                )
            self._speech_ms += _FRAME_MS
            return
        if not self._in_speech:
            return
        self._silence_ms += _FRAME_MS
        if self._silence_ms >= self._min_silence_ms:
            end_ms = at_ms - self._silence_ms + _FRAME_MS
            self._close(end_ms)

    def finish(self, at_ms: int) -> None:
        """Close an open segment at the end of the audio."""
        if self._in_speech:
            self._close(at_ms)

    def _close(self, end_ms: int) -> None:
        self._in_speech = False
        if self._speech_ms >= self._min_speech_ms:
            self.segments.append(Segment(start_ms=self._start_ms, end_ms=max(end_ms, self._start_ms)))
            self.events.append(VadEvent(kind=VadEventKind.SPEECH_ENDED, timestamp_ms=end_ms))
        elif self.events and self.events[-1].kind == VadEventKind.SPEECH_STARTED:
            # Too short to count as speech — retract the start we announced.
            self.events.pop()


def _frames(samples: np.ndarray) -> Iterator[np.ndarray]:
    for start in range(0, max(0, len(samples) - _FRAME + 1), _FRAME):
        yield samples[start : start + _FRAME]


class Vad:
    """Voice-activity detection over the resident detector."""

    def detect(self, audio: AudioInput, options: Optional[VadOptions] = None) -> VadResult:
        """Find the speech segments in a piece of audio.

        ``probability`` is 1.0 or 0.0: the bridge returns a boolean decision per frame, not a
        score.

        Raises:
            SDKException: the SDK is not initialized, or the audio cannot be decoded.

        Example:
            >>> result = runanywhere.vad.detect(AudioInput.file("clip.wav"))
            >>> print(result.is_speech, result.segments)
        """
        opts = options or VadOptions()
        detector = runtime.vad(opts.model, opts.activation_threshold)
        detector.reset()
        samples = audio.samples(_SAMPLE_RATE)
        segmenter = _Segmenter(opts)
        at_ms = 0
        for frame in _frames(samples):
            segmenter.push(detector.process(frame), at_ms)
            at_ms += _FRAME_MS
        segmenter.finish(at_ms)
        speech = bool(segmenter.segments)
        return VadResult(
            is_speech=speech, probability=1.0 if speech else 0.0, segments=segmenter.segments
        )

    async def adetect(
        self, audio: AudioInput, options: Optional[VadOptions] = None
    ) -> VadResult:
        """Async form of :meth:`detect` (runs on the loop's default executor)."""
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, lambda: self.detect(audio, options))

    def detect_stream(
        self, audio: Iterable[AudioInput], options: Optional[VadOptions] = None
    ) -> Iterator[VadEvent]:
        """Emit a speech-started / speech-ended event for each boundary in a stream of audio.

        Raises:
            SDKException: the SDK is not initialized, or a chunk cannot be decoded.
        """
        opts = options or VadOptions()
        detector = runtime.vad(opts.model, opts.activation_threshold)
        detector.reset()
        segmenter = _Segmenter(opts)
        at_ms = 0
        pending = np.zeros(0, dtype=np.float32)
        for chunk in audio:
            pending = np.concatenate([pending, chunk.samples(_SAMPLE_RATE)])
            while len(pending) >= _FRAME:
                segmenter.push(detector.process(pending[:_FRAME]), at_ms)
                pending = pending[_FRAME:]
                at_ms += _FRAME_MS
                while segmenter.events:
                    yield segmenter.events.pop(0)
        segmenter.finish(at_ms)
        while segmenter.events:
            yield segmenter.events.pop(0)


#: The ``vad`` namespace.
vad = Vad()
