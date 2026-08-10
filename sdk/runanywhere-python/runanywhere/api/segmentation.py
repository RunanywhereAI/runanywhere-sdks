"""The ``segmentation`` namespace: per-pixel class masks.

Binds ``native/module.cpp``'s ``load_segmentation_model`` / ``segment`` — thin wrappers
over the offline ``rac_segmentation_create`` / ``initialize`` / ``segment`` C ABI (the same
shape the ``runanywhere-electron`` addon already exposes as ``loadSegmentationModel`` /
``segment``). Offline batch segmentation routes through the ONNX provider that
``rac_backend_onnx_register()`` wires in; a build without the ONNX backend registered
surfaces a native ``RAC_ERROR_NOT_SUPPORTED`` rather than a preflight capability error.

``rac_segmentation_image_t`` takes decoded pixels only — pass :meth:`ImageInput.raw_rgb`
(there is no image decoder in commons).
"""

from __future__ import annotations

from typing import Optional

import numpy as np

from .._runtime import runtime
from ..errors import SDKException
from ..inputs import ImageInput
from ..options import SegmentationOptions
from ..results import ClassInfo, SegmentationResult

__all__ = ["segmentation"]

# RAC_SEGMENTATION_PIXEL_FORMAT_RGB8
_PIXEL_FORMAT_RGB8 = 1


class Segmentation:
    """Semantic image segmentation over the resident segmentation model (ONNX)."""

    def segment(
        self, image: ImageInput, options: Optional[SegmentationOptions] = None
    ) -> SegmentationResult:
        """Label every pixel of ``image``.

        Loads (and downloads) ``options.model`` when it is not already resident — pass a
        catalog id, URL, HuggingFace repo, or local path/directory to an ONNX segmentation
        model, exactly like ``diarization.diarize``'s ``options.model``.

        Raises:
            SDKException: no segmentation model is available (and ``options.model`` was not
                given), the image is not raw RGB, this native build predates the
                segmentation bindings, or the native call fails.

        Example:
            >>> pixels = bytes([255, 0, 0]) * (64 * 64)  # solid red
            >>> result = runanywhere.segmentation.segment(
            ...     ImageInput.raw_rgb(pixels, 64, 64),
            ...     SegmentationOptions(model="/path/to/seg-onnx"),
            ... )
            >>> print(result.width, result.height, len(result.classes))
        """
        if not image.rgb or not image.width or not image.height:
            raise SDKException.invalid_input(
                "segmentation needs raw RGB pixels — use ImageInput.raw_rgb(data, width, height)"
            )
        model_id = options.model if options else None
        model = runtime.segmentation(model_id, verb="segmenting")
        raw = model.segment(
            image.rgb,
            width=image.width,
            height=image.height,
            pixel_format=_PIXEL_FORMAT_RGB8,
            include_diagnostic_rgba=bool(options and options.include_diagnostic_image),
        )
        mask = raw["class_mask"]
        if isinstance(mask, np.ndarray):
            mask_bytes = mask.astype("<u2", copy=False).tobytes()
        else:
            mask_bytes = bytes(mask)
        classes = [
            ClassInfo(
                id=int(c["class_id"]),
                label=str(c.get("label") or ""),
                pixel_count=int(c.get("pixel_count") or 0),
            )
            for c in raw["classes"]
        ]
        return SegmentationResult(
            class_mask=mask_bytes,
            width=int(raw["width"]),
            height=int(raw["height"]),
            classes=classes,
        )


#: The ``segmentation`` namespace.
segmentation = Segmentation()
