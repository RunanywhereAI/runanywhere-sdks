"""The ``diarization`` namespace: attribute speech to speakers.

Not reachable from Python yet. Commons implements diarization
(``rac_diarization_component_diarize_proto``), but ``native/module.cpp`` binds no diarization
entry point.
"""

from __future__ import annotations

from typing import Optional

from ..errors import SDKException
from ..inputs import AudioInput
from ..options import DiarizationOptions
from ..results import DiarizationResult

__all__ = ["diarization"]

_GAP = (
    "diarization: native/module.cpp binds no diarization entry point "
    "(rac_diarization_component_create / rac_diarization_component_load_model / "
    "rac_diarization_component_diarize_proto are not exposed to Python)"
)


class Diarization:
    """Speaker diarization."""

    def diarize(
        self, audio: AudioInput, options: Optional[DiarizationOptions] = None
    ) -> DiarizationResult:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no diarization entry point.
        """
        raise SDKException.not_implemented(_GAP)


#: The ``diarization`` namespace.
diarization = Diarization()
