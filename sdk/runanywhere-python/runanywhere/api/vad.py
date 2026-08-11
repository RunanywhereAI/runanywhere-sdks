"""The ``vad`` namespace: find speech in audio via commons ``rac_vad_stream_*``."""

from __future__ import annotations

import asyncio
from typing import Iterable, Iterator, List, Optional

import numpy as np

from .._runtime import runtime
from ..audio import float32_to_pcm16
from ..errors import SDKException
from ..events import VadEvent, VadEventKind
from ..inputs import AudioEncoding, AudioFormatSpec, STT_SAMPLE_RATE, AudioInput
from ..options import VadOptions
from ..results import AudioFrame, Segment, VadResult, VadStream

__all__ = ["vad"]

_SAMPLE_RATE = STT_SAMPLE_RATE


def _vad_options_bytes(options: Optional[VadOptions]) -> bytes:
    """Serialize ``VadOptions`` for ``rac_vad_stream_start_proto``."""
    from .._proto import vad_options_pb2 as vad_pb

    opts = options or VadOptions()
    msg = vad_pb.VADOptions()
    if opts.activation_threshold is not None:
        msg.activation_threshold = float(opts.activation_threshold)
    msg.min_speech_duration_ms = int(opts.min_speech_ms)
    msg.min_silence_duration_ms = int(opts.min_silence_ms)
    msg.prefix_padding_ms = int(opts.prefix_padding_ms)
    return msg.SerializeToString()


def _activity_to_event(activity) -> Optional[VadEvent]:
    from .._proto import vad_options_pb2 as vad_pb

    kind = activity.event_type
    if kind == vad_pb.SPEECH_ACTIVITY_KIND_SPEECH_STARTED:
        return VadEvent(kind=VadEventKind.SPEECH_STARTED, timestamp_ms=int(activity.audio_start_ms))
    if kind == vad_pb.SPEECH_ACTIVITY_KIND_SPEECH_ENDED:
        return VadEvent(kind=VadEventKind.SPEECH_ENDED, timestamp_ms=int(activity.audio_end_ms))
    return None


def _frame_to_event(result, timestamp_ms: int) -> VadEvent:
    is_speech = bool(result.is_speech)
    return VadEvent(
        kind=VadEventKind.ACTIVITY,
        timestamp_ms=timestamp_ms,
        is_speech=is_speech,
        probability=float(result.probability) if result.probability else (1.0 if is_speech else 0.0),
    )


def _decode_stream_event(raw: bytes) -> List[VadEvent]:
    from .._proto import vad_options_pb2 as vad_pb

    event = vad_pb.VADStreamEvent()
    event.ParseFromString(raw)
    out: List[VadEvent] = []
    if event.kind == vad_pb.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY and event.HasField("activity"):
        mapped = _activity_to_event(event.activity)
        if mapped is not None:
            out.append(mapped)
    elif event.kind == vad_pb.VAD_STREAM_EVENT_KIND_FRAME and event.HasField("result"):
        ts = int(event.result.duration_ms) if event.result.duration_ms else 0
        out.append(_frame_to_event(event.result, ts))
    elif event.kind == vad_pb.VAD_STREAM_EVENT_KIND_ERROR:
        out.append(
            VadEvent(
                kind=VadEventKind.FAILED,
                error=SDKException.generation_failed(
                    event.error.message if event.HasField("error") else "vad stream error"
                ),
            )
        )
    return out


def _pcm16_bytes_from_float32(samples: np.ndarray) -> bytes:
    return float32_to_pcm16(np.asarray(samples, dtype=np.float32)).astype("<i2").tobytes()


def _frame_pcm16(frame: AudioFrame, format: AudioFormatSpec) -> bytes:
    if format.encoding == AudioEncoding.PCM16:
        return bytes(frame.samples)
    samples = np.frombuffer(frame.samples, dtype="<f4")
    return _pcm16_bytes_from_float32(samples)


class _CommonsVadStream(VadStream):
    """Live push stream backed by ``rac_vad_stream_*`` / SPEECH_ACTIVITY events."""

    def __init__(self, format: AudioFormatSpec, options: Optional[VadOptions]) -> None:
        self._format = format
        opts = options or VadOptions()
        self._detector = runtime.vad(opts.model, opts.activation_threshold)
        self._core = self._detector._core
        self._handle = self._detector._handle
        self._queue: List[VadEvent] = []
        self._finished = False
        self._closed = False
        self._session_id: Optional[int] = None
        self._segments: List[Segment] = []
        self._open_start_ms: Optional[int] = None

        def _on_event(raw: bytes) -> None:
            for event in _decode_stream_event(bytes(raw)):
                if event.kind == VadEventKind.SPEECH_STARTED:
                    self._open_start_ms = event.timestamp_ms
                elif event.kind == VadEventKind.SPEECH_ENDED and self._open_start_ms is not None:
                    self._segments.append(
                        Segment(start_ms=self._open_start_ms, end_ms=max(event.timestamp_ms, self._open_start_ms))
                    )
                    self._open_start_ms = None
                self._queue.append(event)

        if not hasattr(self._core, "vad_stream_start"):
            raise SDKException.unsupported_capability(
                "vad.stream",
                "this native/_core build predates rac_vad_stream_* bindings — rebuild the native extension",
            )
        self._core.vad_set_stream_callback(self._handle, _on_event)
        self._session_id = int(self._core.vad_stream_start(self._handle, _vad_options_bytes(opts)))

    def push_frame(self, frame: AudioFrame) -> None:
        if self._closed or self._finished or self._session_id is None:
            return
        try:
            self._core.vad_stream_feed(self._session_id, _frame_pcm16(frame, self._format))
        except Exception as error:  # noqa: BLE001
            self._queue.append(VadEvent(kind=VadEventKind.FAILED, error=error))
            self._finished = True

    def flush(self) -> None:
        """No-op: commons processes each feed as it arrives."""

    def finish(self) -> None:
        if self._finished or self._session_id is None:
            return
        self._finished = True
        self._core.vad_stream_stop(self._session_id)
        self._queue.append(VadEvent(kind=VadEventKind.COMPLETED))

    def events(self) -> Iterator[VadEvent]:
        while self._queue:
            yield self._queue.pop(0)

    def close(self) -> None:
        self._closed = True
        if self._session_id is not None and not self._finished:
            try:
                self._core.vad_stream_cancel(self._session_id)
            except Exception:  # noqa: BLE001
                pass
            self._finished = True
        try:
            self._core.vad_unset_stream_callback(self._handle)
        except Exception:  # noqa: BLE001
            pass


def _run_session(
    detector,
    pcm16: bytes,
    options: Optional[VadOptions],
) -> tuple[List[Segment], List[VadEvent]]:
    """Feed one PCM buffer through a commons VAD stream session."""
    core = detector._core
    handle = detector._handle
    segments: List[Segment] = []
    events: List[VadEvent] = []
    open_start: Optional[int] = None

    def _on_event(raw: bytes) -> None:
        nonlocal open_start
        for event in _decode_stream_event(bytes(raw)):
            if event.kind == VadEventKind.SPEECH_STARTED:
                open_start = event.timestamp_ms
            elif event.kind == VadEventKind.SPEECH_ENDED and open_start is not None:
                segments.append(Segment(start_ms=open_start, end_ms=max(event.timestamp_ms, open_start)))
                open_start = None
            if event.kind in (VadEventKind.SPEECH_STARTED, VadEventKind.SPEECH_ENDED):
                events.append(event)

    if not hasattr(core, "vad_stream_start"):
        raise SDKException.unsupported_capability(
            "vad.stream",
            "this native/_core build predates rac_vad_stream_* bindings — rebuild the native extension",
        )
    core.vad_set_stream_callback(handle, _on_event)
    try:
        session_id = int(core.vad_stream_start(handle, _vad_options_bytes(options)))
        if pcm16:
            core.vad_stream_feed(session_id, pcm16)
        core.vad_stream_stop(session_id)
    finally:
        core.vad_unset_stream_callback(handle)
    return segments, events


class Vad:
    """Voice-activity detection over the resident detector + commons stream policy."""

    def detect(self, audio: AudioInput, options: Optional[VadOptions] = None) -> VadResult:
        """Find the speech segments in a piece of audio.

        Endpointing (min-speech / min-silence / prefix padding) is applied by
        commons ``rac_vad_stream_*``; this method only feeds PCM and maps events.

        Raises:
            SDKException: the SDK is not initialized, or the audio cannot be decoded.
        """
        opts = options or VadOptions()
        detector = runtime.vad(opts.model, opts.activation_threshold)
        samples = audio.samples(_SAMPLE_RATE)
        pcm16 = _pcm16_bytes_from_float32(samples)
        segments, _events = _run_session(detector, pcm16, opts)
        speech = bool(segments)
        return VadResult(
            is_speech=speech, probability=1.0 if speech else 0.0, segments=segments
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
        """
        if format.encoding == AudioEncoding.WAV:
            raise SDKException.invalid_input(
                "vad.open_stream needs raw PCM audio; container formats are batch-only "
                "— use vad.detect."
            )
        return _CommonsVadStream(format, options)

    def detect_stream(
        self, audio: Iterable[AudioInput], options: Optional[VadOptions] = None
    ) -> Iterator[VadEvent]:
        """Emit speech-started / speech-ended events from a stream of audio chunks."""
        opts = options or VadOptions()
        detector = runtime.vad(opts.model, opts.activation_threshold)
        chunks = [_pcm16_bytes_from_float32(chunk.samples(_SAMPLE_RATE)) for chunk in audio]
        pcm16 = b"".join(chunks)
        _segments, events = _run_session(detector, pcm16, opts)
        yield from events


#: The ``vad`` namespace.
vad = Vad()
