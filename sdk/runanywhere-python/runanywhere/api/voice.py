"""The ``voice`` namespace: a voice agent session over file/numpy PCM.

Binds ``native/module.cpp``'s ``create_voice_agent`` / ``initialize_voice_agent`` /
``process_voice_turn`` — the commons ``rac_voice_agent_*`` file-PCM turn path
(STT → LLM → TTS). There is no microphone, WebRTC, or wake-word support in this
SDK; feed complete utterances via :meth:`VoiceSession.process_turn`.
"""

from __future__ import annotations

from typing import Optional

from .._handles import VoiceAgent
from .._runtime import runtime
from ..inputs import STT_SAMPLE_RATE, AudioFormat, AudioInput, ModelRef
from ..options import LlmOptions, TurnHandlingOptions, VadOptions
from ..results import Audio, VoiceTurnResult

__all__ = ["VoiceSession", "voice"]


class VoiceSession:
    """A voice agent that processes file/numpy PCM turns (no mic required)."""

    def __init__(self, agent: VoiceAgent) -> None:
        self._agent = agent
        self._closed = False

    def process_turn(self, audio: AudioInput) -> VoiceTurnResult:
        """Run one STT → LLM → TTS turn over a complete utterance.

        ``audio`` is normalized to 16 kHz mono PCM16 (the same contract as
        ``stt.transcribe``). Returns the transcript, assistant text, and reply
        audio (WAV bytes when the native path synthesizes a reply).
        """
        if self._closed:
            from ..errors import SDKException

            raise SDKException.invalid_state("voice session has been closed")
        pcm16 = audio.to_pcm16(STT_SAMPLE_RATE)
        raw = self._agent.process_turn(pcm16)
        return _turn_result(raw)

    async def aprocess_turn(self, audio: AudioInput) -> VoiceTurnResult:
        """Async twin of :meth:`process_turn`."""
        if self._closed:
            from ..errors import SDKException

            raise SDKException.invalid_state("voice session has been closed")
        pcm16 = audio.to_pcm16(STT_SAMPLE_RATE)
        raw = await self._agent.aprocess_turn(pcm16)
        return _turn_result(raw)

    def close(self) -> None:
        """Release the native voice agent. Idempotent."""
        if self._closed:
            return
        self._closed = True
        self._agent.unload()

    def __enter__(self) -> "VoiceSession":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def _turn_result(raw: dict) -> VoiceTurnResult:
    audio_bytes = bytes(raw.get("synthesized_audio") or b"")
    sample_rate = int(raw.get("sample_rate_hz") or 0)
    return VoiceTurnResult(
        transcription=str(raw.get("transcription") or ""),
        response=str(raw.get("assistant_response") or ""),
        audio=Audio(
            data=audio_bytes,
            sample_rate=sample_rate,
            format=AudioFormat.WAV if audio_bytes[:4] == b"RIFF" else AudioFormat.PCM,
        ),
        speech_detected=bool(raw.get("speech_detected")),
        stt_time_ms=int(raw.get("stt_time_ms") or 0),
        llm_time_ms=int(raw.get("llm_time_ms") or 0),
        tts_time_ms=int(raw.get("tts_time_ms") or 0),
        total_time_ms=int(raw.get("total_time_ms") or 0),
    )


class Voice:
    """Voice agent sessions."""

    def create_session(
        self,
        stt: ModelRef,
        llm: ModelRef,
        tts: ModelRef,
        vad: Optional[VadOptions] = None,
        turn_handling: Optional[TurnHandlingOptions] = None,
        generation: Optional[LlmOptions] = None,
        download_if_needed: bool = True,
    ) -> VoiceSession:
        """Create a voice agent that loads ``stt`` / ``llm`` / ``tts`` models.

        ``vad``, ``turn_handling``, and ``generation`` are accepted for cross-SDK
        signature parity; the file-PCM turn path uses commons defaults for VAD and
        does not open a microphone. ``download_if_needed`` is honored by the
        runtime's normal resolve/download path.

        Raises:
            SDKException: this native build predates the voice-agent bindings, a
                model cannot be resolved, or initialize fails.

        Example:
            >>> session = runanywhere.voice.create_session(
            ...     ModelRef("whisper-tiny"),
            ...     ModelRef("qwen3-0.6b"),
            ...     ModelRef("piper-lessac"),
            ... )
            >>> result = session.process_turn(AudioInput.file("utterance.wav"))
            >>> print(result.transcription, result.response)
        """
        _ = (vad, turn_handling, generation, download_if_needed)  # signature parity
        agent = runtime.create_voice_agent(stt.id, llm.id, tts.id)
        return VoiceSession(agent)


#: The ``voice`` namespace.
voice = Voice()
