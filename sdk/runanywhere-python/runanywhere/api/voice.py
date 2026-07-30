"""The ``voice`` namespace: a live voice agent session.

Not reachable from Python yet, for two independent reasons: ``native/module.cpp`` binds no
voice-agent entry point, and the package has no audio capture or playback device (numpy is
its only runtime dependency), so ``VoiceSession.start()`` could not open a microphone even
if the agent were bound. Compose ``stt`` → ``llm`` → ``tts`` yourself in the meantime.
"""

from __future__ import annotations

from typing import Optional

from ..errors import SDKException
from ..inputs import ModelRef
from ..options import LlmOptions, TurnHandlingOptions, VadOptions

__all__ = ["voice"]

_GAP = (
    "voice.create_session: native/module.cpp binds no voice-agent entry point "
    "(rac_voice_agent_initialize_proto / rac_voice_agent_feed_audio_proto / "
    "rac_voice_agent_set_proto_callback are not exposed to Python), and the Python SDK has "
    "no microphone or speaker adapter"
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
    ) -> "object":
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no voice agent and there is no audio device.
        """
        raise SDKException.not_implemented(_GAP)


#: The ``voice`` namespace.
voice = Voice()
