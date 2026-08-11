"""The ``lora`` namespace: apply adapters to the resident model.

Binds ``native/module.cpp``'s ``lora_apply_proto`` / ``lora_remove_proto`` /
``lora_list_proto`` — thin wrappers over ``rac_lora_*_proto``. Commons owns
optional scale resolution (explicit → catalog including 0.0 → 1.0); this
namespace never coerces an unset scale to 1.0.

``adapter_id`` is a local filesystem path to a LoRA adapter GGUF file: this SDK
has no catalog/download plumbing for adapters yet (only for base models), so
there is no id → path resolution step here — pass the path directly.
"""

from __future__ import annotations

from typing import Optional

from .._runtime import runtime
from ..results import LoraState

__all__ = ["lora"]


class Lora:
    """LoRA adapter management on the resident LLM."""

    def apply(self, adapter_id: str, scale: Optional[float] = None) -> None:
        """Load and apply a LoRA adapter onto the resident LLM.

        Args:
            adapter_id: path to the LoRA adapter GGUF file.
            scale: optional adapter scale. Unset leaves resolution to commons
                (``resolve_effective_lora_scale``). An explicit ``0.0`` is honoured.

        Raises:
            SDKException: no LLM is resident, this native build predates the LoRA
                bindings, or the backend rejects the adapter.
        """
        model = runtime.llm(verb="applying a LoRA adapter")
        model.lora_apply(adapter_id, scale)

    def remove(self, adapter_id: str) -> None:
        """Remove one adapter previously applied via :meth:`apply`.

        Args:
            adapter_id: the same path passed to :meth:`apply`.

        Raises:
            SDKException: no LLM is resident, this native build predates the LoRA
                bindings, or the adapter is not currently applied.
        """
        model = runtime.llm(verb="removing a LoRA adapter")
        model.lora_remove(adapter_id)

    def remove_all(self) -> None:
        """Remove every LoRA adapter applied to the resident LLM.

        Raises:
            SDKException: no LLM is resident, or this native build predates the LoRA
                bindings.
        """
        model = runtime.llm(verb="clearing LoRA adapters")
        model.lora_remove_all()

    def list(self) -> LoraState:
        """The LoRA adapters currently applied to the resident LLM.

        Returns an empty :class:`LoraState` (rather than raising) when no LLM is
        resident.
        """
        model = runtime.llm_if_resident()
        if model is None:
            return LoraState()
        return LoraState(applied=model.lora_list())


#: The ``lora`` namespace.
lora = Lora()
