"""The ``segmentation`` namespace: per-pixel class masks.

Not reachable from Python yet. Commons implements segmentation
(``rac_segmentation_component_segment_proto``), but ``native/module.cpp`` binds no
segmentation entry point.
"""

from __future__ import annotations

from typing import Optional

from ..errors import SDKException
from ..inputs import ImageInput
from ..options import SegmentationOptions
from ..results import SegmentationResult

__all__ = ["segmentation"]

_GAP = (
    "segmentation: native/module.cpp binds no segmentation entry point "
    "(rac_segmentation_component_create / rac_segmentation_component_load_model / "
    "rac_segmentation_component_segment_proto are not exposed to Python)"
)


class Segmentation:
    """Semantic image segmentation."""

    def segment(
        self, image: ImageInput, options: Optional[SegmentationOptions] = None
    ) -> SegmentationResult:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no segmentation entry point.
        """
        raise SDKException.not_implemented(_GAP)


#: The ``segmentation`` namespace.
segmentation = Segmentation()
