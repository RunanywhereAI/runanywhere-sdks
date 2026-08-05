"""The ``images`` namespace: text-to-image generation.

Binds ``native/module.cpp``'s ``load_diffusion_model`` / ``generate_image`` when the
wheel was built with the CoreML diffusion backend (``RAC_HAVE_BACKEND_COREML``).
Desktop CPU wheels typically omit that backend — :meth:`Images.generate` then raises
:meth:`SDKException.unsupported_capability` and :func:`runanywhere.capabilities`
lists ``images`` as unavailable.
"""

from __future__ import annotations

from typing import Iterator, Optional

from .._runtime import runtime
from ..errors import SDKException
from ..events import ImageEvent
from ..options import ImageModeKind, ImageOptions
from ..results import ImageData, ImageResult

__all__ = ["images"]

_STREAM_GAP = (
    "images.generate_stream: native/module.cpp binds no diffusion progress/stream "
    "entry point (use images.generate for the blocking path)"
)


class Images:
    """Image generation over the resident diffusion model (CoreML builds)."""

    def generate(self, prompt: str, options: Optional[ImageOptions] = None) -> ImageResult:
        """Generate an image from ``prompt``.

        Loads (and downloads) ``options.model`` when it is not already resident.

        Raises:
            SDKException: this build has no diffusion bindings (no CoreML backend),
                no model is available, an unsupported mode is requested, or the
                native call fails.

        Example:
            >>> result = runanywhere.images.generate(
            ...     "a red bicycle", ImageOptions(model="/path/to/sd-coreml")
            ... )
            >>> open("out.rgba", "wb").write(result.images[0].data)
        """
        if options and options.mode.kind != ImageModeKind.GENERATE:
            raise SDKException.not_implemented(
                "images.generate: only text-to-image is bound "
                "(img2img / inpaint are not exposed by native/module.cpp)"
            )
        model = runtime.diffusion(options.model if options else None)
        raw = model.generate(
            prompt,
            negative_prompt=options.negative_prompt if options else None,
            width=options.width if options else None,
            height=options.height if options else None,
            steps=options.steps if options else None,
            guidance_scale=options.guidance_scale if options else None,
            seed=options.seed if options else None,
        )
        return ImageResult(
            images=[
                ImageData(
                    data=bytes(raw.get("image_data") or b""),
                    width=int(raw.get("width") or 0),
                    height=int(raw.get("height") or 0),
                )
            ],
            seed=int(raw.get("seed") or 0),
            steps=int(options.steps) if options and options.steps is not None else 0,
        )

    def generate_stream(
        self, prompt: str, options: Optional[ImageOptions] = None
    ) -> Iterator[ImageEvent]:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge binds no diffusion progress stream.
        """
        raise SDKException.unsupported_capability("images.generate_stream", _STREAM_GAP)


#: The ``images`` namespace.
images = Images()
