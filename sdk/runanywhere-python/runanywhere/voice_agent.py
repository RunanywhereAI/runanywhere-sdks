"""Voice turn pipeline: audio in -> transcript -> LLM response -> audio out.

Port of VoiceAgent.ts. Orchestrates the STT, LLM and TTS models into a single call.
Optional callbacks surface the transcript and the response tokens as they are
produced. (Segmentation / VAD — deciding *when* an utterance starts and ends — is a
separate layer; ``process_turn`` takes an already-captured utterance.)
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import TYPE_CHECKING, Callable

from .results import VoiceTurn

if TYPE_CHECKING:
    from .models import LLMModel, STTModel, TTSVoice


@dataclass
class VoiceAgentModels:
    """The three models a :class:`VoiceAgent` orchestrates."""

    stt: "STTModel"
    llm: "LLMModel"
    tts: "TTSVoice"


class VoiceAgent:
    """Run one voice turn: STT -> LLM -> TTS.

    Mirrors the Electron SDK ``VoiceAgent``: the utterance is transcribed and
    trimmed, the (optional) system prompt is prepended to the transcript, the LLM
    reply is streamed and trimmed, then synthesized to audio.
    """

    def __init__(
        self,
        stt: "STTModel",
        llm: "LLMModel",
        tts: "TTSVoice",
        system_prompt: str | None = None,
    ) -> None:
        self._stt = stt
        self._llm = llm
        self._tts = tts
        self._system_prompt = system_prompt

    def _build_prompt(self, transcript: str) -> str:
        if self._system_prompt:
            return f"{self._system_prompt}\n\n{transcript}"
        return transcript

    def process_turn(
        self,
        pcm16: bytes,
        on_transcript: Callable[[str], None] | None = None,
        on_token: Callable[[str], None] | None = None,
    ) -> VoiceTurn:
        """Run one voice turn over 16 kHz mono PCM16 audio bytes."""
        transcript = self._stt.transcribe(pcm16).strip()
        if on_transcript is not None:
            on_transcript(transcript)

        prompt = self._build_prompt(transcript)
        response = ""
        for token in self._llm.generate(prompt):
            response += token
            if on_token is not None:
                on_token(token)
        response = response.strip()

        audio = self._tts.synthesize(response)
        return VoiceTurn(transcript=transcript, response=response, audio=audio)

    async def aprocess_turn(
        self,
        pcm16: bytes,
        on_transcript: Callable[[str], None] | None = None,
        on_token: Callable[[str], None] | None = None,
    ) -> VoiceTurn:
        """Async twin of :meth:`process_turn`.

        STT and TTS are synchronous native calls; they are run on the default
        executor so as not to block the event loop. The LLM reply is streamed via
        the model's async token iterator.
        """
        loop = asyncio.get_running_loop()
        raw = await loop.run_in_executor(None, self._stt.transcribe, pcm16)
        transcript = raw.strip()
        if on_transcript is not None:
            on_transcript(transcript)

        prompt = self._build_prompt(transcript)
        response = ""
        async for token in self._llm.agenerate(prompt):
            response += token
            if on_token is not None:
                on_token(token)
        response = response.strip()

        audio = await loop.run_in_executor(None, self._tts.synthesize, response)
        return VoiceTurn(transcript=transcript, response=response, audio=audio)
