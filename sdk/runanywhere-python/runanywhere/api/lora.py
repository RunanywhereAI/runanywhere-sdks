"""The ``lora`` namespace: apply adapters to the resident model.

Not reachable from Python yet. Commons has the LoRA service (``rac_lora_apply_proto``), but
``native/module.cpp`` binds no LoRA entry point.
"""

from __future__ import annotations

from typing import Optional

from ..errors import SDKException
from ..results import LoraState

__all__ = ["lora"]

_GAP = (
    "lora: native/module.cpp binds no LoRA entry point "
    "(rac_lora_apply_proto / rac_lora_remove_proto / rac_lora_state_proto are not exposed "
    "to Python)"
)


class Lora:
    """LoRA adapter management."""

    def apply(self, adapter_id: str, scale: Optional[float] = None) -> None:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no LoRA entry point.
        """
        raise SDKException.not_implemented(_GAP)

    def remove(self, adapter_id: Optional[str] = None) -> None:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no LoRA entry point.
        """
        raise SDKException.not_implemented(_GAP)

    def list(self) -> LoraState:
        """Not available in this SDK.

        Raises:
            SDKException: always — the bridge exposes no LoRA entry point.
        """
        raise SDKException.not_implemented(_GAP)


#: The ``lora`` namespace.
lora = Lora()
