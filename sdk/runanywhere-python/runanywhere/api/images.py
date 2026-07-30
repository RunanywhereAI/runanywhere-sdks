"""The ``images`` namespace: text-to-image generation.

Not reachable from Python yet. Commons has the diffusion service
(``rac_diffusion_generate_proto``), but ``native/module.cpp`` binds no diffusion entry point
and the desktop wheels link no diffusion backend.
"""

from __future__ import annotations

from typing import Iterator, Optional

from ..errors import SDKException
from ..events import ImageEvent
from ..options import ImageOptions
from ..results import ImageResult

__all__ = ["images"]

_GAP = (
    "images: native/module.cpp binds no diffusion entry point "
    "(rac_diffusion_create / rac_diffusion_generate_proto / "
    "rac_diffusion_generate_with_progress_proto are not exposed to Python)"
)


class Images:
    """Image generation."""

    def generate(self, prompt: str, options: Optional[ImageOptions] = None) -> ImageResult:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no diffusion entry point.
        """
        raise SDKException.not_implemented(_GAP)

    def generate_stream(
        self, prompt: str, options: Optional[ImageOptions] = None
    ) -> Iterator[ImageEvent]:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no diffusion entry point.
        """
        raise SDKException.not_implemented(_GAP)


#: The ``images`` namespace.
images = Images()
