"""The ``vad`` namespace: find speech in audio."""

from __future__ import annotations

import asyncio
from typing import Iterable, Iterator, List, Optional

import numpy as np

from .._runtime import runtime
from ..errors import SDKException
from ..events import VadEvent, VadEventKind
from ..inputs import AudioEncoding, AudioFormatSpec, STT_SAMPLE_RATE, AudioInput
from ..options import VadOptions
from ..results import AudioFrame, Segment, VadResult, VadStream

__all__ = ["vad"]

_SAMPLE_RATE = STT_SAMPLE_RATE
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


def _frame_to_float32(frame: AudioFrame, format: AudioFormatSpec) -> np.ndarray:
    if format.encoding == AudioEncoding.PCM16:
        from ..audio import pcm16_to_float32

        return pcm16_to_float32(np.frombuffer(frame.samples, dtype="<i2"))
    return np.frombuffer(frame.samples, dtype="<f4")


class _PythonVadStream(VadStream):
    """Live push stream backing ``vad.open_stream``.

    Each pushed frame is processed immediately against one persistent detector, so speech
    transitions are reported as soon as :meth:`push_frame` returns; :meth:`events` just drains
    whatever has accumulated since the last call.
    """

    def __init__(self, format: AudioFormatSpec, options: Optional[VadOptions]) -> None:
        self._format = format
        opts = options or VadOptions()
        self._detector = runtime.vad(opts.model, opts.activation_threshold)
        self._detector.reset()
        self._segmenter = _Segmenter(opts)
        self._at_ms = 0
        self._queue: List[VadEvent] = []
        self._finished = False
        self._closed = False

    def _drain_segmenter(self) -> None:
        while self._segmenter.events:
            self._queue.append(self._segmenter.events.pop(0))

    def push_frame(self, frame: AudioFrame) -> None:
        if self._closed or self._finished:
            return
        try:
            samples = _frame_to_float32(frame, self._format)
            for start in range(0, max(0, len(samples) - _FRAME + 1), _FRAME):
                chunk = samples[start : start + _FRAME]
                is_speech = self._detector.process(chunk)
                self._segmenter.push(is_speech, self._at_ms)
                self._at_ms += _FRAME_MS
                self._drain_segmenter()
                self._queue.append(
                    VadEvent(
                        kind=VadEventKind.ACTIVITY,
                        timestamp_ms=self._at_ms,
                        is_speech=is_speech,
                        probability=1.0 if is_speech else 0.0,
                    )
                )
        except Exception as error:  # noqa: BLE001
            self._queue.append(VadEvent(kind=VadEventKind.FAILED, error=error))
            self._finished = True

    def flush(self) -> None:
        """No-op: every pushed frame is already processed as it arrives."""

    def finish(self) -> None:
        if self._finished:
            return
        self._finished = True
        self._segmenter.finish(self._at_ms)
        self._drain_segmenter()
        self._queue.append(VadEvent(kind=VadEventKind.COMPLETED))

    def events(self) -> Iterator[VadEvent]:
        """Drain the events accumulated since the last call."""
        while self._queue:
            yield self._queue.pop(0)

    def close(self) -> None:
        self._closed = True


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

    def open_stream(
        self, format: AudioFormatSpec, options: Optional[VadOptions] = None
    ) -> VadStream:
        """Open a live voice-activity stream with one audio format established up front.

        Raises:
            SDKException: ``format`` uses a container encoding — live streams take raw
                PCM only; use :meth:`detect` for containers.

        Example:
            >>> stream = runanywhere.vad.open_stream(
            ...     AudioFormatSpec(AudioEncoding.PCM16, sample_rate=16000))
            >>> stream.push_frame(AudioFrame(samples=pcm16, sample_count=len(pcm16) // 2))
            >>> stream.finish()
            >>> for event in stream.events():
            ...     print(event.kind)
        """
        if format.encoding == AudioEncoding.WAV:
            raise SDKException.invalid_input(
                "vad.open_stream needs raw PCM audio; container formats are batch-only "
                "— use vad.detect."
            )
        return _PythonVadStream(format, options)

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
